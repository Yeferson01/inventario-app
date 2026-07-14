-- Fase 6.17E - Sync support/admin RPCs
-- Objetivo:
-- Crear RPCs administrativas para soporte:
-- - get_sync_support_workbench
-- - get_sync_support_batch_detail
-- - get_sync_support_device_timeline
--
-- Estas RPCs son de lectura y respetan permisos mediante helpers privados.

begin;

-- =========================================================
-- 1. Índices adicionales para soporte
-- =========================================================

create index if not exists idx_sync_batches_support_business_archived_created
on public.sync_batches (business_id, archived_at, created_at desc)
where deleted_at is null;

create index if not exists idx_sync_mutations_support_business_status_created
on public.sync_mutations (business_id, status, created_at desc)
where deleted_at is null;

create index if not exists idx_sync_conflicts_support_device_status_created
on public.sync_conflicts (app_device_id, status, created_at desc)
where deleted_at is null;

create index if not exists idx_sync_batches_support_device_created
on public.sync_batches (app_device_id, created_at desc)
where deleted_at is null;

-- =========================================================
-- 2. Workbench general de soporte
-- =========================================================

create or replace function public.get_sync_support_workbench(
  p_business_id uuid default null,
  p_days integer default 7,
  p_limit integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_business_ids uuid[];
  v_days integer;
  v_limit integer;
  v_since timestamptz;
begin
  v_business_ids := private.sync_observability_business_ids(p_business_id);

  v_days := greatest(1, least(coalesce(p_days, 7), 90));
  v_limit := greatest(1, least(coalesce(p_limit, 50), 200));
  v_since := now() - make_interval(days => v_days);

  return jsonb_build_object(
    'window', jsonb_build_object(
      'since', v_since,
      'until', now(),
      'days', v_days
    ),
    'business_ids', to_jsonb(v_business_ids),

    -- -----------------------------------------------------
    -- Resumen operativo
    -- -----------------------------------------------------
    'summary', jsonb_build_object(
      'recent_batch_count', (
        select count(*)
        from public.sync_batches sb
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
      ),
      'open_conflict_count', (
        select count(*)
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
          and sc.archived_at is null
      ),
      'recent_error_mutation_count', (
        select count(*)
        from public.sync_mutations sm
        where sm.business_id = any(v_business_ids)
          and sm.created_at >= v_since
          and sm.deleted_at is null
          and sm.archived_at is null
          and (
            sm.status = 'error'
            or nullif(to_jsonb(sm)->>'error_code', '') is not null
          )
      ),
      'recent_archived_batch_count', (
        select count(*)
        from public.sync_batches sb
        where sb.business_id = any(v_business_ids)
          and sb.archived_at is not null
          and sb.archived_at >= v_since
          and sb.deleted_at is null
      ),
      'active_device_count', (
        select count(*)
        from public.app_devices ad
        where ad.business_id = any(v_business_ids)
          and ad.status = 'active'
          and ad.deleted_at is null
      )
    ),

    -- -----------------------------------------------------
    -- Batches recientes
    -- -----------------------------------------------------
    'recent_batches', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
      from (
        select
          sb.id,
          sb.business_id,
          to_jsonb(b)->>'name' as business_name,
          sb.branch_id,
          to_jsonb(br)->>'name' as branch_name,
          sb.app_device_id,
          to_jsonb(ad)->>'device_name' as device_name,
          to_jsonb(ad)->>'platform' as platform,
          to_jsonb(ad)->>'app_version' as app_version,
          sb.profile_id,
          coalesce(
            to_jsonb(p)->>'full_name',
            to_jsonb(p)->>'name',
            to_jsonb(p)->>'email'
          ) as profile_name,
          sb.direction,
          sb.status,
          sb.mutation_count,
          sb.applied_count,
          sb.skipped_count,
          sb.conflict_count,
          sb.error_count,
          sb.client_batch_id,
          sb.created_at,
          sb.updated_at,
          sb.archived_at,
          sb.archived_at is not null as is_archived
        from public.sync_batches sb
        left join public.businesses b on b.id = sb.business_id
        left join public.branches br on br.id = sb.branch_id
        left join public.app_devices ad on ad.id = sb.app_device_id
        left join public.profiles p on p.id = sb.profile_id
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
        order by sb.created_at desc
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Conflictos abiertos
    -- -----------------------------------------------------
    'open_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc), '[]'::jsonb)
      from (
        select
          sc.id,
          sc.business_id,
          to_jsonb(b)->>'name' as business_name,
          sc.branch_id,
          to_jsonb(br)->>'name' as branch_name,
          sc.sync_batch_id,
          sc.sync_mutation_id,
          sc.app_device_id,
          to_jsonb(ad)->>'device_name' as device_name,
          to_jsonb(ad)->>'platform' as platform,
          sc.profile_id,
          coalesce(
            to_jsonb(p)->>'full_name',
            to_jsonb(p)->>'name',
            to_jsonb(p)->>'email'
          ) as profile_name,
          sc.entity_table,
          sc.entity_id,
          sc.operation,
          sc.client_sequence,
          sc.client_mutation_id,
          sc.conflict_type,
          sc.severity,
          sc.status,
          sc.resolution_strategy,
          sc.created_at,
          sc.updated_at,
          sc.metadata
        from public.sync_conflicts sc
        left join public.businesses b on b.id = sc.business_id
        left join public.branches br on br.id = sc.branch_id
        left join public.app_devices ad on ad.id = sc.app_device_id
        left join public.profiles p on p.id = sc.profile_id
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
          and sc.archived_at is null
        order by sc.created_at asc
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Mutaciones problemáticas recientes
    -- -----------------------------------------------------
    'recent_problem_mutations', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
      from (
        select
          sm.id,
          sm.business_id,
          sm.branch_id,
          sm.sync_batch_id,
          sm.app_device_id,
          to_jsonb(ad)->>'device_name' as device_name,
          sm.profile_id,
          sm.client_mutation_id,
          sm.client_sequence,
          sm.entity_table,
          sm.entity_id,
          sm.operation,
          sm.status,
          nullif(to_jsonb(sm)->>'error_code', '') as error_code,
          nullif(to_jsonb(sm)->>'error_message', '') as error_message,
          sm.created_at,
          sm.updated_at,
          sm.metadata
        from public.sync_mutations sm
        left join public.app_devices ad on ad.id = sm.app_device_id
        where sm.business_id = any(v_business_ids)
          and sm.created_at >= v_since
          and sm.deleted_at is null
          and sm.archived_at is null
          and (
            sm.status in ('error', 'conflict')
            or nullif(to_jsonb(sm)->>'error_code', '') is not null
          )
        order by sm.created_at desc
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Dispositivos con estado de soporte
    -- -----------------------------------------------------
    'devices', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.effective_last_seen_at desc nulls last), '[]'::jsonb)
      from (
        select
          d.id as app_device_id,
          d.business_id,
          d.branch_id,
          to_jsonb(br)->>'name' as branch_name,
          d.profile_id,
          coalesce(
            to_jsonb(p)->>'full_name',
            to_jsonb(p)->>'name',
            to_jsonb(p)->>'email'
          ) as profile_name,
          d.device_name,
          d.platform,
          d.app_version,
          d.os_version,
          d.status,
          d.effective_last_seen_at,
          case
            when d.effective_last_seen_at is null then 'unknown'
            when d.effective_last_seen_at < now() - interval '24 hours' then 'stale'
            else 'recent'
          end as health_status,
          (
            select jsonb_build_object(
              'sync_batch_id', sb.id,
              'status', sb.status,
              'direction', sb.direction,
              'mutation_count', sb.mutation_count,
              'applied_count', sb.applied_count,
              'skipped_count', sb.skipped_count,
              'conflict_count', sb.conflict_count,
              'error_count', sb.error_count,
              'created_at', sb.created_at
            )
            from public.sync_batches sb
            where sb.app_device_id = d.id
              and sb.deleted_at is null
            order by sb.created_at desc
            limit 1
          ) as last_batch
        from (
          select
            ad.*,
            coalesce(
              nullif(to_jsonb(ad)->>'last_seen_at', '')::timestamptz,
              ad.updated_at::timestamptz,
              ad.created_at::timestamptz
            ) as effective_last_seen_at
          from public.app_devices ad
          where ad.business_id = any(v_business_ids)
            and ad.deleted_at is null
        ) d
        left join public.branches br on br.id = d.branch_id
        left join public.profiles p on p.id = d.profile_id
        order by d.effective_last_seen_at desc nulls last
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Batches archivados recientes
    -- -----------------------------------------------------
    'recent_archived_batches', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.archived_at desc), '[]'::jsonb)
      from (
        select
          sb.id,
          sb.business_id,
          sb.branch_id,
          to_jsonb(br)->>'name' as branch_name,
          sb.app_device_id,
          to_jsonb(ad)->>'device_name' as device_name,
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
          sb.archived_at,
          sb.archived_by,
          sb.archive_reason,
          sb.retention_until
        from public.sync_batches sb
        left join public.branches br on br.id = sb.branch_id
        left join public.app_devices ad on ad.id = sb.app_device_id
        where sb.business_id = any(v_business_ids)
          and sb.archived_at is not null
          and sb.deleted_at is null
        order by sb.archived_at desc
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Resumen por sucursal
    -- -----------------------------------------------------
    'summary_by_branch', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.batch_count desc), '[]'::jsonb)
      from (
        select
          sb.branch_id,
          coalesce(to_jsonb(br)->>'name', 'Sin sucursal') as branch_name,
          count(*)::integer as batch_count,
          coalesce(sum(sb.mutation_count), 0)::integer as mutation_count,
          coalesce(sum(sb.conflict_count), 0)::integer as conflict_count,
          coalesce(sum(sb.error_count), 0)::integer as error_count
        from public.sync_batches sb
        left join public.branches br on br.id = sb.branch_id
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
        group by sb.branch_id, br.id
        order by count(*) desc
        limit v_limit
      ) x
    ),

    -- -----------------------------------------------------
    -- Resumen por dispositivo
    -- -----------------------------------------------------
    'summary_by_device', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.batch_count desc), '[]'::jsonb)
      from (
        select
          sb.app_device_id,
          coalesce(to_jsonb(ad)->>'device_name', 'Sin dispositivo') as device_name,
          to_jsonb(ad)->>'platform' as platform,
          count(*)::integer as batch_count,
          coalesce(sum(sb.mutation_count), 0)::integer as mutation_count,
          coalesce(sum(sb.conflict_count), 0)::integer as conflict_count,
          coalesce(sum(sb.error_count), 0)::integer as error_count,
          max(sb.created_at) as last_batch_at
        from public.sync_batches sb
        left join public.app_devices ad on ad.id = sb.app_device_id
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
        group by sb.app_device_id, ad.id
        order by count(*) desc
        limit v_limit
      ) x
    )
  );
end;
$$;

comment on function public.get_sync_support_workbench(uuid, integer, integer)
is 'Returns a support/admin sync workbench with recent batches, open conflicts, problem mutations, devices, archived batches and summaries.';

revoke all on function public.get_sync_support_workbench(uuid, integer, integer) from public;
grant execute on function public.get_sync_support_workbench(uuid, integer, integer) to authenticated;
grant execute on function public.get_sync_support_workbench(uuid, integer, integer) to service_role;

-- =========================================================
-- 3. Detalle completo de batch
-- =========================================================

create or replace function public.get_sync_support_batch_detail(
  p_sync_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch record;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  select sb.*
  into v_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id
    and sb.deleted_at is null;

  if v_batch.id is null then
    raise exception 'Sync batch not found';
  end if;

  if not private.can_read_sync_observability(v_batch.business_id) then
    raise exception 'Insufficient permission to read sync batch detail';
  end if;

  return jsonb_build_object(
    'batch', (
      select to_jsonb(x)
      from (
        select
          sb.id,
          sb.business_id,
          to_jsonb(b)->>'name' as business_name,
          sb.branch_id,
          to_jsonb(br)->>'name' as branch_name,
          sb.app_device_id,
          to_jsonb(ad)->>'device_name' as device_name,
          to_jsonb(ad)->>'platform' as platform,
          to_jsonb(ad)->>'app_version' as app_version,
          sb.profile_id,
          coalesce(
            to_jsonb(p)->>'full_name',
            to_jsonb(p)->>'name',
            to_jsonb(p)->>'email'
          ) as profile_name,
          sb.client_batch_id,
          sb.direction,
          sb.status,
          sb.mutation_count,
          sb.applied_count,
          sb.skipped_count,
          sb.conflict_count,
          sb.error_count,
          sb.created_at,
          sb.updated_at,
          sb.archived_at,
          sb.archived_by,
          sb.archive_reason,
          sb.retention_until,
          sb.metadata
        from public.sync_batches sb
        left join public.businesses b on b.id = sb.business_id
        left join public.branches br on br.id = sb.branch_id
        left join public.app_devices ad on ad.id = sb.app_device_id
        left join public.profiles p on p.id = sb.profile_id
        where sb.id = p_sync_batch_id
      ) x
    ),

    'mutations', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.client_sequence), '[]'::jsonb)
      from (
        select
          sm.id,
          sm.client_mutation_id,
          sm.client_sequence,
          sm.entity_table,
          sm.entity_id,
          sm.operation,
          sm.status,
          sm.changed_fields,
          sm.base_version,
          sm.base_updated_at,
          nullif(to_jsonb(sm)->>'server_entity_version', '') as server_entity_version,
          nullif(to_jsonb(sm)->>'server_processed_at', '') as server_processed_at,
          nullif(to_jsonb(sm)->>'error_code', '') as error_code,
          nullif(to_jsonb(sm)->>'error_message', '') as error_message,
          sm.idempotency_key,
          sm.created_at,
          sm.updated_at,
          sm.archived_at,
          sm.archive_reason,
          sm.payload,
          sm.before_payload,
          sm.metadata
        from public.sync_mutations sm
        where sm.sync_batch_id = p_sync_batch_id
          and sm.deleted_at is null
        order by sm.client_sequence
      ) x
    ),

    'conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.client_sequence), '[]'::jsonb)
      from (
        select
          sc.id,
          sc.sync_mutation_id,
          sc.entity_table,
          sc.entity_id,
          sc.operation,
          sc.client_mutation_id,
          sc.client_sequence,
          sc.conflict_type,
          sc.severity,
          sc.status,
          sc.resolution_strategy,
          sc.resolution_notes,
          sc.resolved_at,
          sc.resolved_by,
          sc.created_at,
          sc.updated_at,
          sc.archived_at,
          sc.archive_reason,
          sc.client_payload,
          sc.base_payload,
          sc.server_payload,
          sc.resolved_payload,
          sc.metadata
        from public.sync_conflicts sc
        where sc.sync_batch_id = p_sync_batch_id
          and sc.deleted_at is null
        order by sc.client_sequence
      ) x
    ),

    'device', (
      select case
        when ad.id is null then null
        else jsonb_build_object(
          'app_device_id', ad.id,
          'business_id', ad.business_id,
          'branch_id', ad.branch_id,
          'profile_id', ad.profile_id,
          'device_name', ad.device_name,
          'platform', ad.platform,
          'app_version', ad.app_version,
          'os_version', ad.os_version,
          'status', ad.status,
          'last_seen_at', nullif(to_jsonb(ad)->>'last_seen_at', ''),
          'created_at', ad.created_at,
          'updated_at', ad.updated_at,
          'metadata', ad.metadata
        )
      end
      from public.sync_batches sb
      left join public.app_devices ad on ad.id = sb.app_device_id
      where sb.id = p_sync_batch_id
    )
  );
end;
$$;

comment on function public.get_sync_support_batch_detail(uuid)
is 'Returns full support/admin detail for a sync batch including mutations, conflicts and app device info.';

revoke all on function public.get_sync_support_batch_detail(uuid) from public;
grant execute on function public.get_sync_support_batch_detail(uuid) to authenticated;
grant execute on function public.get_sync_support_batch_detail(uuid) to service_role;

-- =========================================================
-- 4. Timeline de sync por dispositivo
-- =========================================================

create or replace function public.get_sync_support_device_timeline(
  p_app_device_id uuid,
  p_days integer default 30,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_device record;
  v_days integer;
  v_limit integer;
  v_since timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_app_device_id is null then
    raise exception 'p_app_device_id is required';
  end if;

  select ad.*
  into v_device
  from public.app_devices ad
  where ad.id = p_app_device_id
    and ad.deleted_at is null;

  if v_device.id is null then
    raise exception 'App device not found';
  end if;

  if not private.can_read_sync_observability(v_device.business_id) then
    raise exception 'Insufficient permission to read app device sync timeline';
  end if;

  v_days := greatest(1, least(coalesce(p_days, 30), 365));
  v_limit := greatest(1, least(coalesce(p_limit, 100), 500));
  v_since := now() - make_interval(days => v_days);

  return jsonb_build_object(
    'window', jsonb_build_object(
      'since', v_since,
      'until', now(),
      'days', v_days
    ),
    'device', jsonb_build_object(
      'app_device_id', v_device.id,
      'business_id', v_device.business_id,
      'branch_id', v_device.branch_id,
      'profile_id', v_device.profile_id,
      'device_name', v_device.device_name,
      'platform', v_device.platform,
      'app_version', v_device.app_version,
      'os_version', v_device.os_version,
      'status', v_device.status,
      'last_seen_at', nullif(to_jsonb(v_device)->>'last_seen_at', ''),
      'created_at', v_device.created_at,
      'updated_at', v_device.updated_at,
      'metadata', v_device.metadata
    ),
    'summary', jsonb_build_object(
      'batch_count', (
        select count(*)
        from public.sync_batches sb
        where sb.app_device_id = p_app_device_id
          and sb.created_at >= v_since
          and sb.deleted_at is null
      ),
      'conflict_count', (
        select count(*)
        from public.sync_conflicts sc
        where sc.app_device_id = p_app_device_id
          and sc.created_at >= v_since
          and sc.deleted_at is null
      ),
      'open_conflict_count', (
        select count(*)
        from public.sync_conflicts sc
        where sc.app_device_id = p_app_device_id
          and sc.status = 'open'
          and sc.deleted_at is null
          and sc.archived_at is null
      ),
      'error_mutation_count', (
        select count(*)
        from public.sync_mutations sm
        where sm.app_device_id = p_app_device_id
          and sm.created_at >= v_since
          and sm.deleted_at is null
          and sm.archived_at is null
          and (
            sm.status = 'error'
            or nullif(to_jsonb(sm)->>'error_code', '') is not null
          )
      )
    ),
    'batches', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
      from (
        select
          sb.id,
          sb.business_id,
          sb.branch_id,
          sb.profile_id,
          sb.client_batch_id,
          sb.direction,
          sb.status,
          sb.mutation_count,
          sb.applied_count,
          sb.skipped_count,
          sb.conflict_count,
          sb.error_count,
          sb.created_at,
          sb.updated_at,
          sb.archived_at,
          sb.archive_reason
        from public.sync_batches sb
        where sb.app_device_id = p_app_device_id
          and sb.created_at >= v_since
          and sb.deleted_at is null
        order by sb.created_at desc
        limit v_limit
      ) x
    ),
    'open_conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc), '[]'::jsonb)
      from (
        select
          sc.id,
          sc.sync_batch_id,
          sc.sync_mutation_id,
          sc.entity_table,
          sc.entity_id,
          sc.operation,
          sc.client_sequence,
          sc.conflict_type,
          sc.severity,
          sc.status,
          sc.resolution_strategy,
          sc.created_at,
          sc.updated_at,
          sc.metadata
        from public.sync_conflicts sc
        where sc.app_device_id = p_app_device_id
          and sc.status = 'open'
          and sc.deleted_at is null
          and sc.archived_at is null
        order by sc.created_at asc
        limit v_limit
      ) x
    )
  );
end;
$$;

comment on function public.get_sync_support_device_timeline(uuid, integer, integer)
is 'Returns sync support/admin timeline for one app device, including batches and open conflicts.';

revoke all on function public.get_sync_support_device_timeline(uuid, integer, integer) from public;
grant execute on function public.get_sync_support_device_timeline(uuid, integer, integer) to authenticated;
grant execute on function public.get_sync_support_device_timeline(uuid, integer, integer) to service_role;

commit;