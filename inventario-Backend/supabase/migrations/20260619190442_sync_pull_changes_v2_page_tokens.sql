-- Fase 6.14E - Pull sync v2 with page tokens
-- Objetivo:
-- Agregar paginación real por entidad para descarga incremental.
--
-- Nueva RPC:
-- public.pull_sync_changes_v2(
--   p_app_device_id,
--   p_since,
--   p_entities,
--   p_limit_per_entity,
--   p_page_tokens
-- )
--
-- Page token:
-- {
--   "_window_since": "2026-06-19T19:00:00",
--   "_window_until": "2026-06-19T19:01:00",
--   "products": {
--     "timestamp": "2026-06-19T19:00:30",
--     "row_key": "uuid-o-key"
--   }
-- }

begin;

-- =========================================================
-- HELPER: ROW KEY EXPRESSION PARA PAGINACIÓN
-- =========================================================

create or replace function private.sync_pull_row_key_expression(
  p_entity_table text,
  p_alias text default 'q'
)
returns text
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_alias text;
begin
  v_entity := lower(trim(coalesce(p_entity_table, '')));
  v_alias := coalesce(nullif(trim(p_alias), ''), 'q');

  if v_entity = 'role_permissions' then
    return format(
      '%I.role_id::text || '':'' || %I.permission_id::text',
      v_alias,
      v_alias
    );
  end if;

  if private.sync_pull_column_exists(v_entity, 'id') then
    return format('%I.id::text', v_alias);
  end if;

  -- Fallback defensivo para tablas permitidas sin id.
  return format('md5(to_jsonb(%I)::text)', v_alias);
end;
$$;

comment on function private.sync_pull_row_key_expression(text, text)
is 'Returns a stable row key SQL expression used for pull pagination.';

revoke all on function private.sync_pull_row_key_expression(text, text) from public;
grant execute on function private.sync_pull_row_key_expression(text, text) to authenticated, service_role;

-- =========================================================
-- HELPER: PULL DE UNA ENTIDAD V2 CON PAGE TOKEN
-- =========================================================

create or replace function private.pull_sync_entity_rows_v2(
  p_entity_table text,
  p_business_id uuid,
  p_branch_id uuid,
  p_since timestamp without time zone,
  p_until timestamp without time zone,
  p_limit integer,
  p_page_token jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_timestamp_column text;
  v_row_key_expression text;

  v_from_sql text;
  v_where_sql text;
  v_sql text;

  v_token_timestamp timestamp without time zone;
  v_token_row_key text;

  v_rows jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_has_more boolean := false;
  v_next_page_token jsonb := null;

  v_limit integer;
begin
  v_entity := lower(trim(coalesce(p_entity_table, '')));
  v_limit := greatest(1, least(coalesce(p_limit, 500), 1000));

  if v_entity = '' then
    raise exception 'Entity table is required';
  end if;

  if not v_entity = any(private.sync_pull_allowed_entities()) then
    raise exception 'Entity % is not allowed for pull sync', v_entity;
  end if;

  if not exists (
    select 1
    from information_schema.tables t
    where t.table_schema = 'public'
      and t.table_name = v_entity
  ) then
    raise exception 'Public table % does not exist', v_entity;
  end if;

  v_timestamp_column := private.sync_pull_timestamp_column(v_entity);

  if v_timestamp_column is null then
    raise exception 'Entity % has no supported timestamp column for paginated pull', v_entity;
  end if;

  v_row_key_expression := private.sync_pull_row_key_expression(v_entity, 'q');

  if p_page_token is not null
     and jsonb_typeof(p_page_token) = 'object'
     and p_page_token ? 'timestamp'
     and p_page_token ? 'row_key' then
    v_token_timestamp := nullif(p_page_token ->> 'timestamp', '')::timestamp without time zone;
    v_token_row_key := nullif(p_page_token ->> 'row_key', '');
  else
    v_token_timestamp := null;
    v_token_row_key := null;
  end if;

  -- =======================================================
  -- FROM / WHERE POR ENTIDAD
  -- =======================================================

  if v_entity = 'businesses' then
    v_from_sql := format('public.%I q', v_entity);
    v_where_sql := 'q.id = $1';

  elsif v_entity = 'permissions' then
    v_from_sql := format('public.%I q', v_entity);
    v_where_sql := 'true';

  elsif v_entity = 'roles' then
    v_from_sql := format('public.%I q', v_entity);

    if private.sync_pull_column_exists('roles', 'business_id') then
      v_where_sql := '(q.business_id is null or q.business_id = $1)';
    else
      v_where_sql := 'true';
    end if;

  elsif v_entity = 'role_permissions' then
    v_from_sql := 'public.role_permissions q join public.roles r on r.id = q.role_id';
    v_where_sql := '(r.business_id is null or r.business_id = $1)';

  else
    if not private.sync_pull_column_exists(v_entity, 'business_id') then
      raise exception 'Entity % cannot be pulled generically because it has no business_id column', v_entity;
    end if;

    v_from_sql := format('public.%I q', v_entity);
    v_where_sql := 'q.business_id = $1';

    if v_entity <> 'branches'
       and p_branch_id is not null
       and private.sync_pull_column_exists(v_entity, 'branch_id') then
      v_where_sql := v_where_sql || ' and q.branch_id = $2';
    end if;
  end if;

  -- Ventana incremental.
  v_where_sql := v_where_sql || format(
    ' and q.%I > $3 and q.%I <= $4',
    v_timestamp_column,
    v_timestamp_column
  );

  -- Page token: continuar después del último row devuelto.
  if v_token_timestamp is not null and v_token_row_key is not null then
    v_where_sql := v_where_sql || format(
      ' and (q.%I > $5 or (q.%I = $5 and (%s) > $6))',
      v_timestamp_column,
      v_timestamp_column,
      v_row_key_expression
    );
  end if;

  v_sql := format(
    $sql$
      with raw as (
        select
          q.*,
          q.%1$I as __sync_ts,
          (%2$s) as __sync_row_key
        from %3$s
        where %4$s
        order by q.%1$I asc nulls last, (%2$s) asc
        limit ($7 + 1)
      ),
      paged as (
        select *
        from raw
        order by __sync_ts asc nulls last, __sync_row_key asc
        limit $7
      ),
      last_row as (
        select
          __sync_ts,
          __sync_row_key
        from paged
        order by __sync_ts desc nulls last, __sync_row_key desc
        limit 1
      ),
      counts as (
        select
          (select count(*) from raw) as raw_count,
          (select count(*) from paged) as page_count
      )
      select
        coalesce(
          jsonb_agg(
            to_jsonb(paged) - '__sync_ts' - '__sync_row_key'
            order by paged.__sync_ts, paged.__sync_row_key
          ),
          '[]'::jsonb
        ) as rows,
        (select page_count from counts) as row_count,
        ((select raw_count from counts) > $7) as has_more,
        case
          when ((select raw_count from counts) > $7)
          then (
            select jsonb_build_object(
              'timestamp', __sync_ts,
              'row_key', __sync_row_key
            )
            from last_row
          )
          else null
        end as next_page_token
      from paged
    $sql$,
    v_timestamp_column,
    v_row_key_expression,
    v_from_sql,
    v_where_sql
  );

  execute v_sql
  using
    p_business_id,
    p_branch_id,
    p_since,
    p_until,
    v_token_timestamp,
    v_token_row_key,
    v_limit
  into
    v_rows,
    v_count,
    v_has_more,
    v_next_page_token;

  return jsonb_build_object(
    'rows', coalesce(v_rows, '[]'::jsonb),
    'count', coalesce(v_count, 0),
    'has_more', coalesce(v_has_more, false),
    'timestamp_column', v_timestamp_column,
    'since', p_since,
    'until', p_until,
    'page_token_used', p_page_token,
    'next_page_token', v_next_page_token
  );
end;
$$;

comment on function private.pull_sync_entity_rows_v2(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer, jsonb)
is 'Returns a paginated incremental pull page for one allowlisted entity using timestamp + row_key page tokens.';

revoke all on function private.pull_sync_entity_rows_v2(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer, jsonb) from public;
grant execute on function private.pull_sync_entity_rows_v2(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer, jsonb) to authenticated, service_role;

-- =========================================================
-- PUBLIC RPC V2: PULL SYNC CHANGES WITH PAGE TOKENS
-- =========================================================

create or replace function public.pull_sync_changes_v2(
  p_app_device_id uuid,
  p_since timestamp without time zone default null,
  p_entities text[] default null,
  p_limit_per_entity integer default 500,
  p_page_tokens jsonb default '{}'::jsonb
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
  v_until timestamp without time zone;

  v_entities text[];
  v_entity text;
  v_entity_result jsonb;
  v_changes jsonb := '{}'::jsonb;

  v_limit integer;

  v_any_has_more boolean := false;
  v_has_more_entities jsonb := '[]'::jsonb;

  v_next_page_tokens jsonb := '{}'::jsonb;

  v_cursor_advanced boolean := false;
  v_cursor_advance_blocked_reason text := null;

  v_page_tokens jsonb;
  v_continuation_mode boolean := false;
  v_entity_page_token jsonb;

  v_requested_all_entities boolean := false;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_app_device_id is null then
    raise exception 'p_app_device_id is required';
  end if;

  v_limit := greatest(1, least(coalesce(p_limit_per_entity, 500), 1000));
  v_page_tokens := coalesce(p_page_tokens, '{}'::jsonb);

  if jsonb_typeof(v_page_tokens) <> 'object' then
    raise exception 'p_page_tokens must be a JSON object';
  end if;

  v_continuation_mode := v_page_tokens ? '_window_until';

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

  -- Ventana estable.
  if v_page_tokens ? '_window_since' then
    v_since := nullif(v_page_tokens ->> '_window_since', '')::timestamp without time zone;
  elsif p_since is not null then
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

  if v_page_tokens ? '_window_until' then
    v_until := nullif(v_page_tokens ->> '_window_until', '')::timestamp without time zone;
  else
    v_until := now();
  end if;

  if v_since is null then
    v_since := '1970-01-01 00:00:00'::timestamp without time zone;
  end if;

  if v_until is null then
    v_until := now();
  end if;

  if v_since > v_until then
    raise exception 'Pull window since cannot be greater than until';
  end if;

  v_requested_all_entities := p_entities is null;
  v_entities := coalesce(p_entities, private.sync_pull_allowed_entities());

  update public.app_devices ad
  set
    last_seen_at = now(),
    last_sync_started_at = now(),
    updated_at = now(),
    updated_by = v_profile_id
  where ad.id = p_app_device_id;

  v_next_page_tokens := jsonb_build_object(
    '_window_since', v_since,
    '_window_until', v_until
  );

  foreach v_entity in array v_entities
  loop
    v_entity := lower(trim(v_entity));

    if not v_entity = any(private.sync_pull_allowed_entities()) then
      raise exception 'Entity % is not allowed for pull sync', v_entity;
    end if;

    v_entity_page_token := null;

    if v_continuation_mode then
      -- En modo continuación, solo se consulta una entidad si trae page token.
      -- Las entidades sin token ya estaban completas en una página anterior.
      if v_page_tokens ? v_entity then
        v_entity_page_token := v_page_tokens -> v_entity;
      else
        v_entity_result := jsonb_build_object(
          'rows', '[]'::jsonb,
          'count', 0,
          'has_more', false,
          'timestamp_column', private.sync_pull_timestamp_column(v_entity),
          'since', v_since,
          'until', v_until,
          'page_token_used', null,
          'next_page_token', null,
          'skipped_by_page_token', true
        );

        v_changes := v_changes || jsonb_build_object(
          v_entity,
          v_entity_result
        );

        continue;
      end if;
    elsif v_page_tokens ? v_entity then
      v_entity_page_token := v_page_tokens -> v_entity;
    end if;

    v_entity_result := private.pull_sync_entity_rows_v2(
      v_entity,
      v_device.business_id,
      v_device.branch_id,
      v_since,
      v_until,
      v_limit,
      v_entity_page_token
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

      v_next_page_tokens := v_next_page_tokens || jsonb_build_object(
        v_entity,
        v_entity_result -> 'next_page_token'
      );
    end if;
  end loop;

  if v_any_has_more then
    v_cursor_advanced := false;
    v_cursor_advance_blocked_reason := 'has_more_pages';
  elsif not v_requested_all_entities then
    -- Evitamos avanzar el cursor global si la app pidió solo un subconjunto manual.
    -- Para avanzar el cursor global, la app debe hacer pull con p_entities = null
    -- o completar un ciclo full con todas las entidades.
    v_cursor_advanced := false;
    v_cursor_advance_blocked_reason := 'partial_entity_set';
  else
    perform private.upsert_pull_sync_cursor(
      v_device.business_id,
      v_device.id,
      v_device.profile_id,
      v_device.branch_id,
      v_until
    );

    v_cursor_advanced := true;
    v_cursor_advance_blocked_reason := null;
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
    'cursor_advance_blocked_reason', v_cursor_advance_blocked_reason,
    'has_more', v_any_has_more,
    'has_more_entities', v_has_more_entities,
    'next_page_tokens', case
      when v_any_has_more then v_next_page_tokens
      else '{}'::jsonb
    end,
    'changes', v_changes
  );
end;
$$;

comment on function public.pull_sync_changes_v2(uuid, timestamp without time zone, text[], integer, jsonb)
is 'Pulls incremental sync changes with per-entity page tokens. Uses a stable since/until window and advances cursor only after all pages are complete.';

revoke all on function public.pull_sync_changes_v2(uuid, timestamp without time zone, text[], integer, jsonb) from public;
grant execute on function public.pull_sync_changes_v2(uuid, timestamp without time zone, text[], integer, jsonb) to authenticated;
grant execute on function public.pull_sync_changes_v2(uuid, timestamp without time zone, text[], integer, jsonb) to service_role;

commit;