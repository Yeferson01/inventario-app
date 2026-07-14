-- Fase 6.16A - RPCs base para resolución de conflictos de sync
-- Objetivo:
-- Crear funciones seguras para cerrar conflictos abiertos:
-- - server wins
-- - client retry
-- - ignored
--
-- Nota:
-- Esta fase NO aplica resolved_payload sobre entidades.
-- La aplicación manual por entidad queda para una fase posterior.

begin;

-- =========================================================
-- 1. NORMALIZAR STATUS DE sync_conflicts
-- =========================================================

alter table public.sync_conflicts
  drop constraint if exists sync_conflicts_status_check;

alter table public.sync_conflicts
  add constraint sync_conflicts_status_check
  check (status in ('open', 'resolved', 'retry_requested', 'ignored'))
  not valid;

do $$
begin
  alter table public.sync_conflicts validate constraint sync_conflicts_status_check;
exception when others then
  raise notice 'Could not validate sync_conflicts_status_check: %', sqlerrm;
end $$;

-- =========================================================
-- 2. HELPER DE PERMISOS
-- =========================================================

create or replace function private.can_resolve_sync_conflict(
  p_business_id uuid,
  p_profile_id uuid,
  p_branch_id uuid default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_current_profile_id uuid;
begin
  v_current_profile_id := auth.uid();

  if v_current_profile_id is null then
    return false;
  end if;

  -- El usuario dueño de la mutación/conflicto puede resolver su propio conflicto.
  if p_profile_id = v_current_profile_id then
    return true;
  end if;

  -- Roles administrativos.
  if private.has_business_permission(p_business_id, 'settings.business')
     or private.has_business_permission(p_business_id, 'security_events.read') then
    return true;
  end if;

  -- Si en el futuro agregamos permisos específicos, este helper queda listo.
  if private.has_business_permission(p_business_id, 'sync.conflicts.resolve') then
    return true;
  end if;

  return false;
end;
$$;

comment on function private.can_resolve_sync_conflict(uuid, uuid, uuid)
is 'Returns whether the current authenticated profile can resolve a sync conflict.';

revoke all on function private.can_resolve_sync_conflict(uuid, uuid, uuid) from public;
grant execute on function private.can_resolve_sync_conflict(uuid, uuid, uuid) to authenticated, service_role;

-- =========================================================
-- 3. HELPER COMÚN DE RESOLUCIÓN
-- =========================================================

create or replace function private.resolve_sync_conflict_common(
  p_sync_conflict_id uuid,
  p_conflict_status text,
  p_mutation_status text,
  p_mutation_error_code text,
  p_resolution_strategy text,
  p_resolution_notes text default null,
  p_resolved_payload jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_conflict record;
  v_new_conflict_version integer;
  v_batch_id uuid;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_conflict_id is null then
    raise exception 'p_sync_conflict_id is required';
  end if;

  if p_conflict_status not in ('resolved', 'retry_requested', 'ignored') then
    raise exception 'Unsupported conflict status: %', p_conflict_status;
  end if;

  if p_mutation_status not in ('skipped', 'pending', 'conflict') then
    raise exception 'Unsupported mutation status for conflict resolution: %', p_mutation_status;
  end if;

  select
    sc.id,
    sc.business_id,
    sc.sync_batch_id,
    sc.sync_mutation_id,
    sc.app_device_id,
    sc.profile_id,
    sc.branch_id,
    sc.entity_table,
    sc.entity_id,
    sc.operation,
    sc.client_mutation_id,
    sc.client_sequence,
    sc.conflict_type,
    sc.status,
    sc.deleted_at,
    sc.version,
    sc.metadata
  into v_conflict
  from public.sync_conflicts sc
  where sc.id = p_sync_conflict_id
  for update;

  if v_conflict.id is null then
    raise exception 'Sync conflict not found';
  end if;

  if v_conflict.deleted_at is not null then
    raise exception 'Cannot resolve deleted sync conflict';
  end if;

  if v_conflict.status <> 'open' then
    raise exception 'Only open sync conflicts can be resolved. Current status: %', v_conflict.status;
  end if;

  if not private.can_resolve_sync_conflict(
    v_conflict.business_id,
    v_conflict.profile_id,
    v_conflict.branch_id
  ) then
    raise exception 'Insufficient permission to resolve this sync conflict';
  end if;

  update public.sync_conflicts sc
  set
    status = p_conflict_status,
    resolved_at = now(),
    resolved_by = v_profile_id,
    resolution_strategy = p_resolution_strategy,
    resolution_notes = p_resolution_notes,
    resolved_payload = p_resolved_payload,
    metadata = coalesce(sc.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'resolved_by_rpc', true,
        'resolution_status', p_conflict_status,
        'mutation_final_status', p_mutation_status,
        'mutation_error_code', p_mutation_error_code,
        'resolved_at', now()
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sc.id = v_conflict.id
  returning sc.version into v_new_conflict_version;

  update public.sync_mutations sm
  set
    status = p_mutation_status,
    error_code = p_mutation_error_code,
    error_message = coalesce(
      p_resolution_notes,
      case
        when p_conflict_status = 'resolved' then 'Conflict resolved'
        when p_conflict_status = 'retry_requested' then 'Conflict resolved by requesting client retry'
        when p_conflict_status = 'ignored' then 'Conflict ignored'
        else 'Conflict resolution applied'
      end
    ),
    server_processed_at = now(),
    updated_at = now(),
    updated_by = v_profile_id,
    metadata = coalesce(sm.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'conflict_resolution', jsonb_build_object(
          'sync_conflict_id', v_conflict.id,
          'status', p_conflict_status,
          'strategy', p_resolution_strategy,
          'resolved_at', now()
        )
      )
  where sm.id = v_conflict.sync_mutation_id
    and sm.deleted_at is null;

  v_batch_id := v_conflict.sync_batch_id;

  perform private.recalculate_sync_batch_counts(v_batch_id);
  perform private.finalize_sync_batch_from_counts(v_batch_id);

  return jsonb_build_object(
    'sync_conflict_id', v_conflict.id,
    'sync_mutation_id', v_conflict.sync_mutation_id,
    'sync_batch_id', v_batch_id,
    'entity_table', v_conflict.entity_table,
    'entity_id', v_conflict.entity_id,
    'operation', v_conflict.operation,
    'conflict_type', v_conflict.conflict_type,
    'conflict_status', p_conflict_status,
    'mutation_status', p_mutation_status,
    'resolution_strategy', p_resolution_strategy,
    'conflict_version', v_new_conflict_version,
    'batch_status', (
      select sb.status
      from public.sync_batches sb
      where sb.id = v_batch_id
    ),
    'batch_counts', (
      select jsonb_build_object(
        'mutation_count', sb.mutation_count,
        'applied_count', sb.applied_count,
        'skipped_count', sb.skipped_count,
        'conflict_count', sb.conflict_count,
        'error_count', sb.error_count
      )
      from public.sync_batches sb
      where sb.id = v_batch_id
    )
  );
end;
$$;

comment on function private.resolve_sync_conflict_common(uuid, text, text, text, text, text, jsonb)
is 'Common internal helper to resolve an open sync conflict and update the related sync mutation and sync batch counts.';

revoke all on function private.resolve_sync_conflict_common(uuid, text, text, text, text, text, jsonb) from public;
grant execute on function private.resolve_sync_conflict_common(uuid, text, text, text, text, text, jsonb) to authenticated, service_role;

-- =========================================================
-- 4. PUBLIC RPC: SERVER WINS
-- =========================================================

create or replace function public.resolve_sync_conflict_server_wins(
  p_sync_conflict_id uuid,
  p_resolution_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  return private.resolve_sync_conflict_common(
    p_sync_conflict_id,
    'resolved',
    'skipped',
    'server_wins',
    'server_wins',
    coalesce(p_resolution_notes, 'Server version kept. Client mutation skipped.'),
    null
  );
end;
$$;

comment on function public.resolve_sync_conflict_server_wins(uuid, text)
is 'Resolves an open sync conflict by keeping the server version and skipping the client mutation.';

revoke all on function public.resolve_sync_conflict_server_wins(uuid, text) from public;
grant execute on function public.resolve_sync_conflict_server_wins(uuid, text) to authenticated;
grant execute on function public.resolve_sync_conflict_server_wins(uuid, text) to service_role;

-- =========================================================
-- 5. PUBLIC RPC: CLIENT RETRY
-- =========================================================

create or replace function public.resolve_sync_conflict_client_retry(
  p_sync_conflict_id uuid,
  p_resolution_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  return private.resolve_sync_conflict_common(
    p_sync_conflict_id,
    'retry_requested',
    'skipped',
    'client_retry',
    'client_retry',
    coalesce(p_resolution_notes, 'Client must pull latest server state, rebase locally and send a new mutation.'),
    null
  );
end;
$$;

comment on function public.resolve_sync_conflict_client_retry(uuid, text)
is 'Resolves an open sync conflict by requesting the client to retry later with a new rebased mutation.';

revoke all on function public.resolve_sync_conflict_client_retry(uuid, text) from public;
grant execute on function public.resolve_sync_conflict_client_retry(uuid, text) to authenticated;
grant execute on function public.resolve_sync_conflict_client_retry(uuid, text) to service_role;

-- =========================================================
-- 6. PUBLIC RPC: IGNORE CONFLICT
-- =========================================================

create or replace function public.ignore_sync_conflict(
  p_sync_conflict_id uuid,
  p_resolution_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  return private.resolve_sync_conflict_common(
    p_sync_conflict_id,
    'ignored',
    'skipped',
    'ignored',
    'ignored',
    coalesce(p_resolution_notes, 'Conflict ignored by authorized user. Client mutation skipped.'),
    null
  );
end;
$$;

comment on function public.ignore_sync_conflict(uuid, text)
is 'Ignores an open sync conflict and skips the related client mutation.';

revoke all on function public.ignore_sync_conflict(uuid, text) from public;
grant execute on function public.ignore_sync_conflict(uuid, text) to authenticated;
grant execute on function public.ignore_sync_conflict(uuid, text) to service_role;

-- =========================================================
-- 7. PUBLIC RPC: SUMMARY DE CONFLICTO
-- =========================================================

create or replace function public.get_sync_conflict_summary(
  p_sync_conflict_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_conflict record;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  select
    sc.*
  into v_conflict
  from public.sync_conflicts sc
  where sc.id = p_sync_conflict_id
    and sc.deleted_at is null;

  if v_conflict.id is null then
    raise exception 'Sync conflict not found';
  end if;

  if not private.can_resolve_sync_conflict(
    v_conflict.business_id,
    v_conflict.profile_id,
    v_conflict.branch_id
  ) then
    raise exception 'Insufficient permission to read this sync conflict';
  end if;

  return jsonb_build_object(
    'conflict', to_jsonb(v_conflict),
    'mutation', (
      select to_jsonb(sm)
      from public.sync_mutations sm
      where sm.id = v_conflict.sync_mutation_id
    ),
    'batch', (
      select to_jsonb(sb)
      from public.sync_batches sb
      where sb.id = v_conflict.sync_batch_id
    )
  );
end;
$$;

comment on function public.get_sync_conflict_summary(uuid)
is 'Returns a JSON summary of a sync conflict, its mutation and its batch for authorized users.';

revoke all on function public.get_sync_conflict_summary(uuid) from public;
grant execute on function public.get_sync_conflict_summary(uuid) to authenticated;
grant execute on function public.get_sync_conflict_summary(uuid) to service_role;

commit;