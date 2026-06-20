-- Fase 6.17A - Sync observability RPCs
-- Objetivo:
-- Crear RPCs seguras para dashboards operativos de sync:
-- - get_sync_operational_dashboard
-- - get_sync_open_conflicts
-- - get_app_device_sync_health

begin;

-- =========================================================
-- 1. Índices operativos
-- =========================================================

create index if not exists idx_sync_batches_observability_business_created
on public.sync_batches (business_id, created_at desc);

create index if not exists idx_sync_batches_observability_business_status_created
on public.sync_batches (business_id, status, created_at desc);

create index if not exists idx_sync_batches_observability_device_created
on public.sync_batches (app_device_id, created_at desc);

create index if not exists idx_sync_conflicts_observability_business_status_created
on public.sync_conflicts (business_id, status, created_at desc);

create index if not exists idx_sync_conflicts_observability_business_type_created
on public.sync_conflicts (business_id, conflict_type, created_at desc);

create index if not exists idx_sync_mutations_observability_batch_status_sequence
on public.sync_mutations (sync_batch_id, status, client_sequence);

create index if not exists idx_app_devices_observability_business_status_updated
on public.app_devices (business_id, status, updated_at desc);

-- =========================================================
-- 2. Helper de permisos
-- =========================================================

create or replace function private.can_read_sync_observability(
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

  if private.is_business_member(p_business_id) then
    return true;
  end if;

  if private.has_business_permission(p_business_id, 'settings.business') then
    return true;
  end if;

  if private.has_business_permission(p_business_id, 'security_events.read') then
    return true;
  end if;

  return false;
end;
$$;

comment on function private.can_read_sync_observability(uuid)
is 'Returns whether the current authenticated user can read sync observability data for a business.';

revoke all on function private.can_read_sync_observability(uuid) from public;
grant execute on function private.can_read_sync_observability(uuid) to authenticated, service_role;

-- =========================================================
-- 3. Helper para resolver negocios visibles
-- =========================================================

create or replace function private.sync_observability_business_ids(
  p_business_id uuid default null
)
returns uuid[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_business_ids uuid[];
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is not null then
    if not private.can_read_sync_observability(p_business_id) then
      raise exception 'Insufficient permission to read sync observability for this business';
    end if;

    return array[p_business_id];
  end if;

  select coalesce(array_agg(distinct bm.business_id), array[]::uuid[])
  into v_business_ids
  from public.business_members bm
  where bm.profile_id = v_profile_id
    and bm.status = 'active'
    and bm.deleted_at is null;

  if coalesce(array_length(v_business_ids, 1), 0) = 0 then
    raise exception 'No active business memberships found for current user';
  end if;

  return v_business_ids;
end;
$$;

comment on function private.sync_observability_business_ids(uuid)
is 'Returns the list of businesses visible to the current authenticated user for sync observability.';

revoke all on function private.sync_observability_business_ids(uuid) from public;
grant execute on function private.sync_observability_business_ids(uuid) to authenticated, service_role;

-- =========================================================
-- 4. Dashboard operativo general
-- =========================================================

create or replace function public.get_sync_operational_dashboard(
  p_business_id uuid default null,
  p_days integer default 7,
  p_recent_limit integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_business_ids uuid[];
  v_days integer;
  v_recent_limit integer;
  v_since timestamptz;
  v_result jsonb;
begin
  v_days := greatest(1, least(coalesce(p_days, 7), 90));
  v_recent_limit := greatest(1, least(coalesce(p_recent_limit, 20), 100));
  v_since := now() - make_interval(days => v_days);

  v_business_ids := private.sync_observability_business_ids(p_business_id);

  select jsonb_build_object(
    'window', jsonb_build_object(
      'since', v_since,
      'until', now(),
      'days', v_days
    ),
    'business_ids', to_jsonb(v_business_ids),

    'batches', jsonb_build_object(
      'total', (
        select count(*)
        from public.sync_batches sb
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
      ),
      'by_status', (
        select coalesce(jsonb_object_agg(x.status, x.count), '{}'::jsonb)
        from (
          select sb.status, count(*)::integer
          from public.sync_batches sb
          where sb.business_id = any(v_business_ids)
            and sb.created_at >= v_since
            and sb.deleted_at is null
          group by sb.status
          order by sb.status
        ) x
      ),
      'by_direction', (
        select coalesce(jsonb_object_agg(x.direction, x.count), '{}'::jsonb)
        from (
          select sb.direction, count(*)::integer
          from public.sync_batches sb
          where sb.business_id = any(v_business_ids)
            and sb.created_at >= v_since
            and sb.deleted_at is null
          group by sb.direction
          order by sb.direction
        ) x
      ),
      'totals', (
        select jsonb_build_object(
          'mutation_count', coalesce(sum(sb.mutation_count), 0),
          'applied_count', coalesce(sum(sb.applied_count), 0),
          'skipped_count', coalesce(sum(sb.skipped_count), 0),
          'conflict_count', coalesce(sum(sb.conflict_count), 0),
          'error_count', coalesce(sum(sb.error_count), 0)
        )
        from public.sync_batches sb
        where sb.business_id = any(v_business_ids)
          and sb.created_at >= v_since
          and sb.deleted_at is null
      ),
      'recent', (
        select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
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
            sb.updated_at,
            nullif(to_jsonb(sb)->>'server_started_at', '') as server_started_at,
            nullif(to_jsonb(sb)->>'server_completed_at', '') as server_completed_at
          from public.sync_batches sb
          where sb.business_id = any(v_business_ids)
            and sb.created_at >= v_since
            and sb.deleted_at is null
          order by sb.created_at desc
          limit v_recent_limit
        ) x
      )
    ),

    'conflicts', jsonb_build_object(
      'total', (
        select count(*)
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.created_at >= v_since
          and sc.deleted_at is null
      ),
      'open', (
        select count(*)
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
      ),
      'by_status', (
        select coalesce(jsonb_object_agg(x.status, x.count), '{}'::jsonb)
        from (
          select sc.status, count(*)::integer
          from public.sync_conflicts sc
          where sc.business_id = any(v_business_ids)
            and sc.created_at >= v_since
            and sc.deleted_at is null
          group by sc.status
          order by sc.status
        ) x
      ),
      'by_type_open', (
        select coalesce(jsonb_object_agg(x.conflict_type, x.count), '{}'::jsonb)
        from (
          select sc.conflict_type, count(*)::integer
          from public.sync_conflicts sc
          where sc.business_id = any(v_business_ids)
            and sc.status = 'open'
            and sc.deleted_at is null
          group by sc.conflict_type
          order by sc.conflict_type
        ) x
      ),
      'by_entity_open', (
        select coalesce(jsonb_object_agg(x.entity_table, x.count), '{}'::jsonb)
        from (
          select sc.entity_table, count(*)::integer
          from public.sync_conflicts sc
          where sc.business_id = any(v_business_ids)
            and sc.status = 'open'
            and sc.deleted_at is null
          group by sc.entity_table
          order by sc.entity_table
        ) x
      ),
      'oldest_open_created_at', (
        select min(sc.created_at)
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
      )
    ),

    'devices', jsonb_build_object(
      'total', (
        select count(*)
        from public.app_devices ad
        where ad.business_id = any(v_business_ids)
          and ad.deleted_at is null
      ),
      'by_status', (
        select coalesce(jsonb_object_agg(x.status, x.count), '{}'::jsonb)
        from (
          select ad.status, count(*)::integer
          from public.app_devices ad
          where ad.business_id = any(v_business_ids)
            and ad.deleted_at is null
          group by ad.status
          order by ad.status
        ) x
      )
    )
  )
  into v_result;

  return v_result;
end;
$$;

comment on function public.get_sync_operational_dashboard(uuid, integer, integer)
is 'Returns sync operational metrics for visible businesses: batches, conflicts and app devices.';

revoke all on function public.get_sync_operational_dashboard(uuid, integer, integer) from public;
grant execute on function public.get_sync_operational_dashboard(uuid, integer, integer) to authenticated;
grant execute on function public.get_sync_operational_dashboard(uuid, integer, integer) to service_role;

-- =========================================================
-- 5. Conflictos abiertos
-- =========================================================

create or replace function public.get_sync_open_conflicts(
  p_business_id uuid default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_business_ids uuid[];
  v_limit integer;
begin
  v_business_ids := private.sync_observability_business_ids(p_business_id);
  v_limit := greatest(1, least(coalesce(p_limit, 100), 500));

  return jsonb_build_object(
    'business_ids', to_jsonb(v_business_ids),
    'limit', v_limit,
    'summary', jsonb_build_object(
      'open_count', (
        select count(*)
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
      ),
      'by_type', (
        select coalesce(jsonb_object_agg(x.conflict_type, x.count), '{}'::jsonb)
        from (
          select sc.conflict_type, count(*)::integer
          from public.sync_conflicts sc
          where sc.business_id = any(v_business_ids)
            and sc.status = 'open'
            and sc.deleted_at is null
          group by sc.conflict_type
          order by sc.conflict_type
        ) x
      ),
      'by_entity', (
        select coalesce(jsonb_object_agg(x.entity_table, x.count), '{}'::jsonb)
        from (
          select sc.entity_table, count(*)::integer
          from public.sync_conflicts sc
          where sc.business_id = any(v_business_ids)
            and sc.status = 'open'
            and sc.deleted_at is null
          group by sc.entity_table
          order by sc.entity_table
        ) x
      )
    ),
    'conflicts', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at asc), '[]'::jsonb)
      from (
        select
          sc.id,
          sc.business_id,
          sc.branch_id,
          sc.sync_batch_id,
          sc.sync_mutation_id,
          sc.app_device_id,
          sc.profile_id,
          sc.entity_table,
          sc.entity_id,
          sc.operation,
          sc.client_mutation_id,
          sc.client_sequence,
          sc.conflict_type,
          sc.severity,
          sc.status,
          sc.resolution_strategy,
          sc.metadata,
          sc.created_at,
          sc.updated_at
        from public.sync_conflicts sc
        where sc.business_id = any(v_business_ids)
          and sc.status = 'open'
          and sc.deleted_at is null
        order by sc.created_at asc
        limit v_limit
      ) x
    )
  );
end;
$$;

comment on function public.get_sync_open_conflicts(uuid, integer)
is 'Returns open sync conflicts visible to the current user, grouped by type and entity.';

revoke all on function public.get_sync_open_conflicts(uuid, integer) from public;
grant execute on function public.get_sync_open_conflicts(uuid, integer) to authenticated;
grant execute on function public.get_sync_open_conflicts(uuid, integer) to service_role;

-- =========================================================
-- 6. Salud de dispositivos
-- =========================================================

create or replace function public.get_app_device_sync_health(
  p_business_id uuid default null,
  p_stale_hours integer default 24,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_business_ids uuid[];
  v_stale_hours integer;
  v_limit integer;
begin
  v_business_ids := private.sync_observability_business_ids(p_business_id);
  v_stale_hours := greatest(1, least(coalesce(p_stale_hours, 24), 720));
  v_limit := greatest(1, least(coalesce(p_limit, 100), 500));

  return jsonb_build_object(
    'business_ids', to_jsonb(v_business_ids),
    'stale_hours', v_stale_hours,
    'summary', (
      select jsonb_build_object(
        'total_devices', count(*),
        'stale_devices', count(*) filter (
          where d.effective_last_seen_at < now() - make_interval(hours => v_stale_hours)
        ),
        'unknown_devices', count(*) filter (
          where d.effective_last_seen_at is null
        ),
        'active_status_devices', count(*) filter (
          where d.status = 'active'
        )
      )
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
    ),
    'devices', (
      select coalesce(jsonb_agg(to_jsonb(x) order by x.effective_last_seen_at desc nulls last), '[]'::jsonb)
      from (
        select
          d.id as app_device_id,
          d.business_id,
          d.branch_id,
          d.profile_id,
          d.device_name,
          d.platform,
          d.app_version,
          d.os_version,
          d.status,
          d.effective_last_seen_at,
          case
            when d.effective_last_seen_at is null then 'unknown'
            when d.effective_last_seen_at < now() - make_interval(hours => v_stale_hours) then 'stale'
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
              'created_at', sb.created_at,
              'updated_at', sb.updated_at
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
        order by d.effective_last_seen_at desc nulls last
        limit v_limit
      ) x
    )
  );
end;
$$;

comment on function public.get_app_device_sync_health(uuid, integer, integer)
is 'Returns app device sync health and latest batch information for visible businesses.';

revoke all on function public.get_app_device_sync_health(uuid, integer, integer) from public;
grant execute on function public.get_app_device_sync_health(uuid, integer, integer) to authenticated;
grant execute on function public.get_app_device_sync_health(uuid, integer, integer) to service_role;

commit;