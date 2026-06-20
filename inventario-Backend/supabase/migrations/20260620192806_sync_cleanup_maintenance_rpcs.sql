-- Fase 6.17C - Sync cleanup and maintenance RPCs
-- Objetivo:
-- Crear mantenimiento seguro para sync sin hard delete:
-- - get_sync_cleanup_preview
-- - archive_old_sync_records
--
-- Política:
-- - No borrar físicamente.
-- - Solo archivar batches cerrados y antiguos.
-- - No archivar batches con conflictos abiertos.
-- - No archivar batches pending/processing.

begin;

-- =========================================================
-- 1. Columnas de archivado
-- =========================================================

alter table public.sync_batches
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid,
  add column if not exists archive_reason text,
  add column if not exists retention_until timestamptz;

alter table public.sync_mutations
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid,
  add column if not exists archive_reason text,
  add column if not exists retention_until timestamptz;

alter table public.sync_conflicts
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid,
  add column if not exists archive_reason text,
  add column if not exists retention_until timestamptz;

comment on column public.sync_batches.archived_at
is 'Timestamp when the sync batch was archived for retention/cleanup purposes. This is not a hard delete.';

comment on column public.sync_mutations.archived_at
is 'Timestamp when the sync mutation was archived for retention/cleanup purposes. This is not a hard delete.';

comment on column public.sync_conflicts.archived_at
is 'Timestamp when the sync conflict was archived for retention/cleanup purposes. This is not a hard delete.';

-- =========================================================
-- 2. Índices de mantenimiento
-- =========================================================

create index if not exists idx_sync_batches_archive_candidate
on public.sync_batches (business_id, archived_at, status, created_at)
where deleted_at is null;

create index if not exists idx_sync_mutations_archive_batch
on public.sync_mutations (sync_batch_id, archived_at)
where deleted_at is null;

create index if not exists idx_sync_conflicts_archive_batch_status
on public.sync_conflicts (sync_batch_id, status, archived_at)
where deleted_at is null;

create index if not exists idx_sync_batches_archived_at
on public.sync_batches (business_id, archived_at desc)
where archived_at is not null;

-- =========================================================
-- 3. Helper de permisos para mantenimiento
-- =========================================================

create or replace function private.can_manage_sync_maintenance(
  p_business_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  if p_business_id is null then
    return false;
  end if;

  -- Mantenimiento es más sensible que observabilidad:
  -- requiere permiso de administración/seguridad.
  if private.has_business_permission(p_business_id, 'settings.business') then
    return true;
  end if;

  if private.has_business_permission(p_business_id, 'security_events.read') then
    return true;
  end if;

  return false;
end;
$$;

comment on function private.can_manage_sync_maintenance(uuid)
is 'Returns whether current authenticated user can perform sync maintenance for a business.';

revoke all on function private.can_manage_sync_maintenance(uuid) from public;
grant execute on function private.can_manage_sync_maintenance(uuid) to authenticated, service_role;

-- =========================================================
-- 4. Preview de limpieza
-- =========================================================

create or replace function public.get_sync_cleanup_preview(
  p_business_id uuid,
  p_retention_days integer default 90
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_retention_days integer;
  v_cutoff timestamptz;
  v_candidate_batch_ids uuid[];
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'p_business_id is required';
  end if;

  if not private.can_manage_sync_maintenance(p_business_id) then
    raise exception 'Insufficient permission to manage sync maintenance for this business';
  end if;

  v_retention_days := greatest(1, least(coalesce(p_retention_days, 90), 3650));
  v_cutoff := now() - make_interval(days => v_retention_days);

  select coalesce(array_agg(sb.id order by sb.created_at), array[]::uuid[])
  into v_candidate_batch_ids
  from public.sync_batches sb
  where sb.business_id = p_business_id
    and sb.deleted_at is null
    and sb.archived_at is null
    and sb.created_at < v_cutoff
    and sb.status not in ('pending', 'processing')
    and not exists (
      select 1
      from public.sync_conflicts sc
      where sc.sync_batch_id = sb.id
        and sc.deleted_at is null
        and sc.archived_at is null
        and sc.status = 'open'
    )
    and not exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = sb.id
        and sm.deleted_at is null
        and sm.archived_at is null
        and sm.status in ('pending', 'processing')
    );

  return jsonb_build_object(
    'business_id', p_business_id,
    'retention_days', v_retention_days,
    'cutoff', v_cutoff,
    'mode', 'preview',
    'eligible', jsonb_build_object(
      'batch_count', coalesce(array_length(v_candidate_batch_ids, 1), 0),
      'mutation_count', (
        select count(*)
        from public.sync_mutations sm
        where sm.sync_batch_id = any(v_candidate_batch_ids)
          and sm.deleted_at is null
          and sm.archived_at is null
      ),
      'conflict_count', (
        select count(*)
        from public.sync_conflicts sc
        where sc.sync_batch_id = any(v_candidate_batch_ids)
          and sc.deleted_at is null
          and sc.archived_at is null
          and sc.status <> 'open'
      )
    ),
    'excluded', jsonb_build_object(
      'open_conflict_batches', (
        select count(distinct sb.id)
        from public.sync_batches sb
        join public.sync_conflicts sc on sc.sync_batch_id = sb.id
        where sb.business_id = p_business_id
          and sb.deleted_at is null
          and sb.archived_at is null
          and sb.created_at < v_cutoff
          and sc.deleted_at is null
          and sc.archived_at is null
          and sc.status = 'open'
      ),
      'pending_or_processing_batches', (
        select count(*)
        from public.sync_batches sb
        where sb.business_id = p_business_id
          and sb.deleted_at is null
          and sb.archived_at is null
          and sb.created_at < v_cutoff
          and sb.status in ('pending', 'processing')
      ),
      'pending_or_processing_mutation_batches', (
        select count(distinct sb.id)
        from public.sync_batches sb
        join public.sync_mutations sm on sm.sync_batch_id = sb.id
        where sb.business_id = p_business_id
          and sb.deleted_at is null
          and sb.archived_at is null
          and sb.created_at < v_cutoff
          and sm.deleted_at is null
          and sm.archived_at is null
          and sm.status in ('pending', 'processing')
      )
    ),
    'eligible_batches', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc), '[]'::jsonb)
      from (
        select
          sb.id,
          sb.business_id,
          sb.branch_id,
          sb.app_device_id,
          sb.profile_id,
          sb.direction,
          sb.status,
          sb.mutation_count,
          sb.applied_count,
          sb.skipped_count,
          sb.conflict_count,
          sb.error_count,
          sb.client_batch_id,
          sb.created_at,
          sb.updated_at
        from public.sync_batches sb
        where sb.id = any(v_candidate_batch_ids)
        order by sb.created_at asc
        limit 100
      ) x
    )
  );
end;
$$;

comment on function public.get_sync_cleanup_preview(uuid, integer)
is 'Returns a preview of old closed sync records eligible for archival. Does not modify data.';

revoke all on function public.get_sync_cleanup_preview(uuid, integer) from public;
grant execute on function public.get_sync_cleanup_preview(uuid, integer) to authenticated;
grant execute on function public.get_sync_cleanup_preview(uuid, integer) to service_role;

-- =========================================================
-- 5. Archivar registros antiguos de sync
-- =========================================================

create or replace function public.archive_old_sync_records(
  p_business_id uuid,
  p_retention_days integer default 90,
  p_dry_run boolean default true,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_retention_days integer;
  v_cutoff timestamptz;
  v_reason text;

  v_candidate_batch_ids uuid[];

  v_batch_count integer := 0;
  v_mutation_count integer := 0;
  v_conflict_count integer := 0;

  v_archived_batches integer := 0;
  v_archived_mutations integer := 0;
  v_archived_conflicts integer := 0;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'p_business_id is required';
  end if;

  if not private.can_manage_sync_maintenance(p_business_id) then
    raise exception 'Insufficient permission to manage sync maintenance for this business';
  end if;

  v_retention_days := greatest(1, least(coalesce(p_retention_days, 90), 3650));
  v_cutoff := now() - make_interval(days => v_retention_days);
  v_reason := coalesce(nullif(trim(p_reason), ''), 'sync_retention_archive');

  select coalesce(array_agg(sb.id order by sb.created_at), array[]::uuid[])
  into v_candidate_batch_ids
  from public.sync_batches sb
  where sb.business_id = p_business_id
    and sb.deleted_at is null
    and sb.archived_at is null
    and sb.created_at < v_cutoff
    and sb.status not in ('pending', 'processing')
    and not exists (
      select 1
      from public.sync_conflicts sc
      where sc.sync_batch_id = sb.id
        and sc.deleted_at is null
        and sc.archived_at is null
        and sc.status = 'open'
    )
    and not exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = sb.id
        and sm.deleted_at is null
        and sm.archived_at is null
        and sm.status in ('pending', 'processing')
    );

  v_batch_count := coalesce(array_length(v_candidate_batch_ids, 1), 0);

  select count(*)
  into v_mutation_count
  from public.sync_mutations sm
  where sm.sync_batch_id = any(v_candidate_batch_ids)
    and sm.deleted_at is null
    and sm.archived_at is null;

  select count(*)
  into v_conflict_count
  from public.sync_conflicts sc
  where sc.sync_batch_id = any(v_candidate_batch_ids)
    and sc.deleted_at is null
    and sc.archived_at is null
    and sc.status <> 'open';

  if p_dry_run then
    return jsonb_build_object(
      'business_id', p_business_id,
      'retention_days', v_retention_days,
      'cutoff', v_cutoff,
      'dry_run', true,
      'reason', v_reason,
      'eligible', jsonb_build_object(
        'batch_count', v_batch_count,
        'mutation_count', v_mutation_count,
        'conflict_count', v_conflict_count
      ),
      'archived', jsonb_build_object(
        'batch_count', 0,
        'mutation_count', 0,
        'conflict_count', 0
      )
    );
  end if;

  -- Archivar conflictos cerrados primero.
  update public.sync_conflicts sc
  set
    archived_at = now(),
    archived_by = v_profile_id,
    archive_reason = v_reason,
    retention_until = v_cutoff,
    metadata = coalesce(sc.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'archive', jsonb_build_object(
          'archived_at', now(),
          'archived_by', v_profile_id,
          'reason', v_reason,
          'retention_days', v_retention_days,
          'cutoff', v_cutoff
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sc.sync_batch_id = any(v_candidate_batch_ids)
    and sc.deleted_at is null
    and sc.archived_at is null
    and sc.status <> 'open';

  get diagnostics v_archived_conflicts = row_count;

  -- Archivar mutations.
  update public.sync_mutations sm
  set
    archived_at = now(),
    archived_by = v_profile_id,
    archive_reason = v_reason,
    retention_until = v_cutoff,
    metadata = coalesce(sm.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'archive', jsonb_build_object(
          'archived_at', now(),
          'archived_by', v_profile_id,
          'reason', v_reason,
          'retention_days', v_retention_days,
          'cutoff', v_cutoff
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sm.sync_batch_id = any(v_candidate_batch_ids)
    and sm.deleted_at is null
    and sm.archived_at is null;

  get diagnostics v_archived_mutations = row_count;

  -- Archivar batches.
  update public.sync_batches sb
  set
    archived_at = now(),
    archived_by = v_profile_id,
    archive_reason = v_reason,
    retention_until = v_cutoff,
    metadata = coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'archive', jsonb_build_object(
          'archived_at', now(),
          'archived_by', v_profile_id,
          'reason', v_reason,
          'retention_days', v_retention_days,
          'cutoff', v_cutoff
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sb.id = any(v_candidate_batch_ids)
    and sb.business_id = p_business_id
    and sb.deleted_at is null
    and sb.archived_at is null;

  get diagnostics v_archived_batches = row_count;

  return jsonb_build_object(
    'business_id', p_business_id,
    'retention_days', v_retention_days,
    'cutoff', v_cutoff,
    'dry_run', false,
    'reason', v_reason,
    'eligible', jsonb_build_object(
      'batch_count', v_batch_count,
      'mutation_count', v_mutation_count,
      'conflict_count', v_conflict_count
    ),
    'archived', jsonb_build_object(
      'batch_count', v_archived_batches,
      'mutation_count', v_archived_mutations,
      'conflict_count', v_archived_conflicts
    ),
    'safety', jsonb_build_object(
      'hard_delete', false,
      'open_conflicts_archived', false,
      'pending_batches_archived', false,
      'pending_mutations_archived', false
    )
  );
end;
$$;

comment on function public.archive_old_sync_records(uuid, integer, boolean, text)
is 'Archives old closed sync batches, mutations and resolved conflicts without hard deleting. Dry-run by default. Does not archive open conflicts or pending/processing records.';

revoke all on function public.archive_old_sync_records(uuid, integer, boolean, text) from public;
grant execute on function public.archive_old_sync_records(uuid, integer, boolean, text) to authenticated;
grant execute on function public.archive_old_sync_records(uuid, integer, boolean, text) to service_role;

commit;