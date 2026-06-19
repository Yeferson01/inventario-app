-- Fase 6.14A - RPC pull_sync_changes
-- Objetivo:
-- Crear la primera RPC de descarga incremental:
-- Supabase -> App offline.
--
-- La app podrá solicitar cambios desde un cursor temporal.
-- Esta primera versión usa un cursor global por app_device:
-- sync_cursors.entity_table = 'all'
-- sync_cursors.cursor_name = 'pull_default'

begin;

-- =========================================================
-- HELPER: ENTIDADES PERMITIDAS PARA PULL
-- =========================================================

create or replace function private.sync_pull_allowed_entities()
returns text[]
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select array[
    'businesses',
    'branches',
    'business_members',
    'roles',
    'permissions',
    'role_permissions',

    'categories',
    'products',
    'customers',
    'suppliers',

    'sales',
    'sale_items',
    'sale_payments',

    'product_stock_balances',
    'inventory_movements',

    'cash_registers',
    'cash_sessions'
  ]::text[];
$$;

comment on function private.sync_pull_allowed_entities()
is 'Returns the allowlisted entity tables that can be downloaded by pull_sync_changes.';

revoke all on function private.sync_pull_allowed_entities() from public;
grant execute on function private.sync_pull_allowed_entities() to authenticated, service_role;

-- =========================================================
-- HELPER: EXISTE COLUMNA
-- =========================================================

create or replace function private.sync_pull_column_exists(
  p_table_name text,
  p_column_name text
)
returns boolean
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table_name
      and c.column_name = p_column_name
  );
$$;

comment on function private.sync_pull_column_exists(text, text)
is 'Checks whether a public table has a given column.';

revoke all on function private.sync_pull_column_exists(text, text) from public;
grant execute on function private.sync_pull_column_exists(text, text) to authenticated, service_role;

-- =========================================================
-- HELPER: COLUMNA TEMPORAL PARA PULL
-- =========================================================

create or replace function private.sync_pull_timestamp_column(
  p_table_name text
)
returns text
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_column text;
begin
  -- Prioridad:
  -- updated_at: cambios de negocio.
  -- created_at: inserts.
  -- occurred_at: ledger/eventos.
  -- last_movement_at: balances de inventario.
  -- paid_at: pagos si no tuvieran updated_at.
  foreach v_column in array array[
    'updated_at',
    'created_at',
    'occurred_at',
    'last_movement_at',
    'paid_at'
  ]
  loop
    if private.sync_pull_column_exists(p_table_name, v_column) then
      return v_column;
    end if;
  end loop;

  return null;
end;
$$;

comment on function private.sync_pull_timestamp_column(text)
is 'Returns the best timestamp column to use for incremental pull filters.';

revoke all on function private.sync_pull_timestamp_column(text) from public;
grant execute on function private.sync_pull_timestamp_column(text) to authenticated, service_role;

-- =========================================================
-- HELPER: PULL DE UNA ENTIDAD
-- =========================================================

create or replace function private.pull_sync_entity_rows(
  p_entity_table text,
  p_business_id uuid,
  p_branch_id uuid,
  p_since timestamp without time zone,
  p_until timestamp without time zone,
  p_limit integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_timestamp_column text;
  v_sql text;
  v_where text := 'true';
  v_order text;
  v_rows jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_has_more boolean := false;
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

  -- =======================================================
  -- SPECIAL CASE: businesses
  -- =======================================================

  if v_entity = 'businesses' then
    v_where := 'q.id = $1';

    if v_timestamp_column is not null then
      v_where := v_where || format(
        ' and q.%I > $3 and q.%I <= $4',
        v_timestamp_column,
        v_timestamp_column
      );
      v_order := format('q.%I asc nulls last', v_timestamp_column);
    else
      v_order := 'q.id asc';
    end if;

    v_sql := format(
      'select coalesce(jsonb_agg(to_jsonb(q) order by %s), ''[]''::jsonb), count(*)
       from (
         select *
         from public.%I q
         where %s
         order by %s
         limit $5
       ) q',
      v_order,
      v_entity,
      v_where,
      v_order
    );

    execute v_sql
    using p_business_id, p_branch_id, p_since, p_until, v_limit
    into v_rows, v_count;

    v_has_more := v_count >= v_limit;

    return jsonb_build_object(
      'rows', v_rows,
      'count', v_count,
      'has_more', v_has_more,
      'timestamp_column', v_timestamp_column,
      'since', p_since,
      'until', p_until
    );
  end if;

  -- =======================================================
  -- SPECIAL CASE: permissions
  -- =======================================================

  if v_entity = 'permissions' then
    if v_timestamp_column is not null then
      v_where := format(
        'q.%I > $3 and q.%I <= $4',
        v_timestamp_column,
        v_timestamp_column
      );
      v_order := format('q.%I asc nulls last', v_timestamp_column);
    else
      v_where := 'true';
      v_order := 'q.id asc';
    end if;

    v_sql := format(
      'select coalesce(jsonb_agg(to_jsonb(q) order by %s), ''[]''::jsonb), count(*)
       from (
         select *
         from public.%I q
         where %s
         order by %s
         limit $5
       ) q',
      v_order,
      v_entity,
      v_where,
      v_order
    );

    execute v_sql
    using p_business_id, p_branch_id, p_since, p_until, v_limit
    into v_rows, v_count;

    v_has_more := v_count >= v_limit;

    return jsonb_build_object(
      'rows', v_rows,
      'count', v_count,
      'has_more', v_has_more,
      'timestamp_column', v_timestamp_column,
      'since', p_since,
      'until', p_until
    );
  end if;

  -- =======================================================
  -- SPECIAL CASE: roles
  -- =======================================================

  if v_entity = 'roles' then
    if private.sync_pull_column_exists('roles', 'business_id') then
      v_where := '(q.business_id is null or q.business_id = $1)';
    else
      v_where := 'true';
    end if;

    if v_timestamp_column is not null then
      v_where := v_where || format(
        ' and q.%I > $3 and q.%I <= $4',
        v_timestamp_column,
        v_timestamp_column
      );
      v_order := format('q.%I asc nulls last', v_timestamp_column);
    else
      v_order := 'q.id asc';
    end if;

    v_sql := format(
      'select coalesce(jsonb_agg(to_jsonb(q) order by %s), ''[]''::jsonb), count(*)
       from (
         select *
         from public.%I q
         where %s
         order by %s
         limit $5
       ) q',
      v_order,
      v_entity,
      v_where,
      v_order
    );

    execute v_sql
    using p_business_id, p_branch_id, p_since, p_until, v_limit
    into v_rows, v_count;

    v_has_more := v_count >= v_limit;

    return jsonb_build_object(
      'rows', v_rows,
      'count', v_count,
      'has_more', v_has_more,
      'timestamp_column', v_timestamp_column,
      'since', p_since,
      'until', p_until
    );
  end if;

  -- =======================================================
  -- SPECIAL CASE: role_permissions
  -- =======================================================

  if v_entity = 'role_permissions' then
    v_timestamp_column := private.sync_pull_timestamp_column('role_permissions');

    v_where := '(r.business_id is null or r.business_id = $1)';

    if v_timestamp_column is not null then
      v_where := v_where || format(
        ' and rp.%I > $3 and rp.%I <= $4',
        v_timestamp_column,
        v_timestamp_column
      );
      v_order := format('rp.%I asc nulls last', v_timestamp_column);
    else
      v_order := 'rp.role_id asc';
    end if;

    v_sql := format(
      'select coalesce(jsonb_agg(to_jsonb(q) order by %s), ''[]''::jsonb), count(*)
       from (
         select rp.*
         from public.role_permissions rp
         join public.roles r on r.id = rp.role_id
         where %s
         order by %s
         limit $5
       ) q',
      replace(v_order, 'rp.', 'q.'),
      v_where,
      v_order
    );

    execute v_sql
    using p_business_id, p_branch_id, p_since, p_until, v_limit
    into v_rows, v_count;

    v_has_more := v_count >= v_limit;

    return jsonb_build_object(
      'rows', v_rows,
      'count', v_count,
      'has_more', v_has_more,
      'timestamp_column', v_timestamp_column,
      'since', p_since,
      'until', p_until
    );
  end if;

  -- =======================================================
  -- CASO GENERAL
  -- =======================================================

  if not private.sync_pull_column_exists(v_entity, 'business_id') then
    raise exception 'Entity % cannot be pulled generically because it has no business_id column', v_entity;
  end if;

  v_where := 'q.business_id = $1';

  -- Filtro por sucursal cuando la tabla tiene branch_id.
  -- No aplica a branches, porque ahí queremos descargar la sucursal como entidad.
  if v_entity <> 'branches'
     and p_branch_id is not null
     and private.sync_pull_column_exists(v_entity, 'branch_id') then
    v_where := v_where || ' and q.branch_id = $2';
  end if;

  if v_timestamp_column is not null then
    v_where := v_where || format(
      ' and q.%I > $3 and q.%I <= $4',
      v_timestamp_column,
      v_timestamp_column
    );
    v_order := format('q.%I asc nulls last', v_timestamp_column);
  else
    v_order := 'q.id asc';
  end if;

  v_sql := format(
    'select coalesce(jsonb_agg(to_jsonb(q) order by %s), ''[]''::jsonb), count(*)
     from (
       select *
       from public.%I q
       where %s
       order by %s
       limit $5
     ) q',
    v_order,
    v_entity,
    v_where,
    v_order
  );

  execute v_sql
  using p_business_id, p_branch_id, p_since, p_until, v_limit
  into v_rows, v_count;

  v_has_more := v_count >= v_limit;

  return jsonb_build_object(
    'rows', v_rows,
    'count', v_count,
    'has_more', v_has_more,
    'timestamp_column', v_timestamp_column,
    'since', p_since,
    'until', p_until
  );
end;
$$;

comment on function private.pull_sync_entity_rows(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer)
is 'Returns incremental pull rows for a single allowlisted entity, scoped to business/branch where applicable.';

revoke all on function private.pull_sync_entity_rows(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer) from public;
grant execute on function private.pull_sync_entity_rows(text, uuid, uuid, timestamp without time zone, timestamp without time zone, integer) to authenticated, service_role;

-- =========================================================
-- HELPER: UPSERT CURSOR GLOBAL
-- =========================================================

create or replace function private.upsert_pull_sync_cursor(
  p_business_id uuid,
  p_app_device_id uuid,
  p_profile_id uuid,
  p_branch_id uuid,
  p_until timestamp without time zone
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_cursor_token text;
begin
  v_cursor_token := md5(
    p_app_device_id::text
    || ':'
    || coalesce(p_until::text, '')
    || ':'
    || clock_timestamp()::text
  );

  update public.sync_cursors sc
  set
    last_pulled_at = now(),
    last_successful_sync_at = now(),
    last_server_updated_at = p_until,
    cursor_token = v_cursor_token,
    full_resync_required = false,
    status = 'active',
    error_code = null,
    error_message = null,
    updated_at = now(),
    updated_by = p_profile_id
  where sc.app_device_id = p_app_device_id
    and sc.entity_table = 'all'
    and sc.cursor_name = 'pull_default'
    and sc.deleted_at is null;

  if not found then
    insert into public.sync_cursors (
      business_id,
      app_device_id,
      profile_id,
      branch_id,
      entity_table,
      cursor_name,
      scope,
      last_pulled_at,
      last_successful_sync_at,
      last_server_updated_at,
      cursor_token,
      full_resync_required,
      status,
      created_by,
      updated_by,
      metadata
    )
    values (
      p_business_id,
      p_app_device_id,
      p_profile_id,
      p_branch_id,
      'all',
      'pull_default',
      case
        when p_branch_id is null then 'business'
        else 'branch'
      end,
      now(),
      now(),
      p_until,
      v_cursor_token,
      false,
      'active',
      p_profile_id,
      p_profile_id,
      jsonb_build_object(
        'created_by_pull_sync_changes', true
      )
    );
  end if;
end;
$$;

comment on function private.upsert_pull_sync_cursor(uuid, uuid, uuid, uuid, timestamp without time zone)
is 'Creates or updates the global pull cursor for an app_device.';

revoke all on function private.upsert_pull_sync_cursor(uuid, uuid, uuid, uuid, timestamp without time zone) from public;
grant execute on function private.upsert_pull_sync_cursor(uuid, uuid, uuid, uuid, timestamp without time zone) to authenticated, service_role;

-- =========================================================
-- PUBLIC RPC: PULL SYNC CHANGES
-- =========================================================

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

  -- Si la app manda p_since, manda ese cursor.
  -- Si no, usamos el cursor global guardado.
  -- Si no existe, hacemos full pull desde epoch.
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
  end loop;

  perform private.upsert_pull_sync_cursor(
    v_device.business_id,
    v_device.id,
    v_device.profile_id,
    v_device.branch_id,
    v_until
  );

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
    'changes', v_changes
  );
end;
$$;

comment on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer)
is 'Pulls incremental sync changes for an app_device using a global cursor. Returns allowlisted business-scoped data grouped by entity.';

revoke all on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) from public;
grant execute on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) to authenticated;
grant execute on function public.pull_sync_changes(uuid, timestamp without time zone, text[], integer) to service_role;

commit;