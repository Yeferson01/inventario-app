-- Fase 6.16D - Resolución manual de conflictos con resolved_payload
-- Objetivo:
-- Crear public.resolve_sync_conflict_manual(...)
-- para cerrar conflictos abiertos con un payload final decidido manualmente.
--
-- Esta fase NO aplica automáticamente resolved_payload sobre tablas de negocio.
-- Solo registra la decisión, cierra el conflicto, marca la mutación como skipped
-- y recalcula el batch.

begin;

-- =========================================================
-- 1. NORMALIZAR resolution_strategy
-- =========================================================

alter table public.sync_conflicts
  drop constraint if exists sync_conflicts_resolution_strategy_check;

alter table public.sync_conflicts
  add constraint sync_conflicts_resolution_strategy_check
  check (
    resolution_strategy in (
      'server_wins',
      'client_retry',
      'manual_review',
      'manual_resolution',
      'ignored'
    )
  )
  not valid;

do $$
begin
  alter table public.sync_conflicts
    validate constraint sync_conflicts_resolution_strategy_check;
exception when others then
  raise notice 'Could not validate sync_conflicts_resolution_strategy_check: %', sqlerrm;
end $$;

-- =========================================================
-- 2. PATCH HELPER COMÚN PARA DEJAR resolution_strategy EN METADATA
-- =========================================================

drop function if exists private.resolve_sync_conflict_common(
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
);

create function private.resolve_sync_conflict_common(
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

  if p_resolution_strategy not in (
    'server_wins',
    'client_retry',
    'manual_review',
    'manual_resolution',
    'ignored'
  ) then
    raise exception 'Unsupported resolution strategy: %', p_resolution_strategy;
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
        'resolution_strategy', p_resolution_strategy,
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
        when p_resolution_strategy = 'server_wins' then 'Conflict resolved by keeping server version'
        when p_resolution_strategy = 'client_retry' then 'Conflict resolved by requesting client retry'
        when p_resolution_strategy = 'manual_resolution' then 'Conflict resolved manually'
        when p_resolution_strategy = 'ignored' then 'Conflict ignored'
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
    'has_resolved_payload', p_resolved_payload is not null,
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
is 'Common internal helper to resolve an open sync conflict and update the related mutation, batch counts, metadata and resolved_payload.';

revoke all on function private.resolve_sync_conflict_common(uuid, text, text, text, text, text, jsonb) from public;
grant execute on function private.resolve_sync_conflict_common(uuid, text, text, text, text, text, jsonb) to authenticated, service_role;

-- =========================================================
-- 3. RPC PÚBLICA: RESOLUCIÓN MANUAL
-- =========================================================

create or replace function public.resolve_sync_conflict_manual(
  p_sync_conflict_id uuid,
  p_resolved_payload jsonb,
  p_resolution_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if p_resolved_payload is null then
    raise exception 'p_resolved_payload is required';
  end if;

  if jsonb_typeof(p_resolved_payload) <> 'object' then
    raise exception 'p_resolved_payload must be a JSON object';
  end if;

  return private.resolve_sync_conflict_common(
    p_sync_conflict_id,
    'resolved',
    'skipped',
    'manual_resolution',
    'manual_resolution',
    coalesce(p_resolution_notes, 'Conflict resolved manually with resolved_payload.'),
    p_resolved_payload
  );
end;
$$;

comment on function public.resolve_sync_conflict_manual(uuid, jsonb, text)
is 'Resolves an open sync conflict manually by storing resolved_payload, skipping the original mutation and recalculating batch counts. It does not apply the payload to business tables.';

revoke all on function public.resolve_sync_conflict_manual(uuid, jsonb, text) from public;
grant execute on function public.resolve_sync_conflict_manual(uuid, jsonb, text) to authenticated;
grant execute on function public.resolve_sync_conflict_manual(uuid, jsonb, text) to service_role;

commit;