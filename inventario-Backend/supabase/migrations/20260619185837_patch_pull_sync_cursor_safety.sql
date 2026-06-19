-- Fase 6.14C - Pull sync cursor safety
-- Objetivo:
-- Evitar pérdida de datos cuando alguna entidad llega al límite por página.
--
-- Regla:
-- Si cualquier entidad tiene has_more = true:
--   - NO avanzamos sync_cursors.last_server_updated_at
--   - devolvemos cursor_advanced = false
--   - devolvemos has_more_entities
--
-- Si ninguna entidad tiene has_more:
--   - avanzamos el cursor normalmente
--   - devolvemos cursor_advanced = true

begin;

create or replace function public.pull_sync_changes(
  p_app_device_id uuid,
  p_since timestamp without time zone default null,
  p_entities text[] default null,
  p_limit_per_entity integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_device record;

  v_since timestamp without time zone;
  v_until timestamp without time zone := now();

  v_entities text[];
  v_entity text;
  v_entity_result jsonb;
  v_changes jsonb := '{}'::jsonb;

  v_limit integer;

  v_any_has_more boolean := false;
  v_has_more_entities jsonb := '[]'::jsonb;
  v_cursor_advanced boolean := false;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_app_device_id is null then
    raise exception 'p_app_device_id is required';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit_per_entity, 500), 1000));

  select
    ad.id,
    ad.business_id,
    ad.profile_id,
    ad.branch_id,
    ad.status,
    ad.deleted_at
  into v_device
  from public.app_devices ad
  where ad.id = p_app_device_id;

  if v_device.id is null then
    raise exception 'app_device not found';
  end if;

  if v_device.deleted_at is not null then
    raise exception 'Cannot pull sync changes for deleted app_device';
  end if;

  if v_device.status <> 'active' then
    raise exception 'Cannot pull sync changes for inactive or blocked app_device';
  end if;

  if v_device.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_device.business_id, 'settings.business')
       or private.has_business_permission(v_device.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to pull sync changes for this app_device';
  end if;

  if p_since is not null then
    v_since := p_since;
  else
    select sc.last_server_updated_at
    into v_since
    from public.sync_cursors sc
    where sc.app_device_id = p_app_device_id
      and sc.entity_table = 'all'
      and sc.cursor_name = 'pull_default'
      and sc.deleted_at is null
    order by sc.updated_at desc nulls last, sc.created_at desc nulls last
    limit 1;

    v_since := coalesce(v_since, '1970-01-01 00:00:00'::timestamp without time zone);
  end if;

  if v_since > v_until then
    raise exception 'p_since cannot be greater than current server time';
  end if;

  v_entities := coalesce(p_entities, private.sync_pull_allowed_entities());

  update public.app_devices ad
  set
    last_seen_at = now(),
    last_sync_started_at = now(),
    updated_at = now(),
    updated_by = v_profile_id
  where ad.id = p_app_device_id;

  foreach v_entity in array v_entities
  loop
    v_entity := lower(trim(v_entity));

    if not v_entity = any(private.sync_pull_allowed_entities()) then
      raise exception 'Entity % is not allowed for pull sync', v_entity;
    end if;

    v_entity_result := private.pull_sync_entity_rows(
      v_entity,
      v_device.business_id,
      v_device.branch_id,
      v_since,
      v_until,
      v_limit
    );

    v_changes := v_changes || jsonb_build_object(
      v_entity,
      v_entity_result
    );

    if coalesce((v_entity_result ->> 'has_more')::boolean, false) then
      v_any_has_more := true;

      v_has_more_entities := v_has_more_entities || jsonb_build_array(
        jsonb_build_object(
          'entity_table', v_entity,
          'count', coalesce((v_entity_result ->> 'count')::integer, 0),
          'limit', v_limit,
          'timestamp_column', v_entity_result ->> 'timestamp_column'
        )
      );
    end if;
  end loop;

  if not v_any_has_more then
    perform private.upsert_pull_sync_cursor(
      v_device.business_id,
      v_device.id,
      v_device.profile_id,
      v_device.branch_id,
      v_until
    );

    v_cursor_advanced := true;
  else
    v_cursor_advanced := false;
  end if;

  update public.app_devices ad
  set
    last_seen_at = now(),
    last_sync_completed_at = now(),
    updated_at = now(),
    updated_by = v_profile_id
  where ad.id = p_app_device_id;

  return jsonb_build_object(
    'app_device_id', p_app_device_id,
    'business_id', v_device.business_id,
    'branch_id', v_device.branch_id,
    'since', v_since,
    'next_since', v_until,
    'limit_per_entity', v_limit,
    'entities_requested', v_entities,
    'cursor_advanced', v_cursor_advanced,
    'has_more', v_any_has_more,
    'has_more_entities', v_has_more_entities,
    'changes', v_changes
  );
end;
$$;

comment on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer)
is 'Pulls incremental sync changes for an app_device using a global cursor. Cursor advances only when no requested entity reports has_more.';

revoke all on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) from public;
grant execute on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) to authenticated;
grant execute on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) to service_role;

commit;