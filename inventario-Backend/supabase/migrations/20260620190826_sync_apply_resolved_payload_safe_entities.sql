-- Fase 6.16F - Aplicación controlada de resolved_payload para entidades seguras
-- Objetivo:
-- Crear public.apply_resolved_sync_conflict_payload(...)
-- para aplicar resolved_payload.final_payload únicamente en entidades catalogables seguras:
-- categories, customers, suppliers.
--
-- Importante:
-- Esta RPC NO aplica cambios sobre compras, ventas, caja ni inventario.

begin;

-- =========================================================
-- 1. HELPER: columnas permitidas por entidad segura
-- =========================================================

create or replace function private.safe_resolved_payload_columns(
  p_entity_table text
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
begin
  case p_entity_table
    when 'categories' then
      return array[
        'name',
        'description',
        'status',
        'metadata'
      ];

    when 'customers' then
      return array[
        'name',
        'full_name',
        'document_number',
        'tax_id',
        'phone',
        'email',
        'address',
        'notes',
        'status',
        'metadata'
      ];

    when 'suppliers' then
      return array[
        'name',
        'contact_name',
        'document_number',
        'tax_id',
        'phone',
        'email',
        'address',
        'notes',
        'status',
        'metadata'
      ];

    else
      return array[]::text[];
  end case;
end;
$$;

comment on function private.safe_resolved_payload_columns(text)
is 'Returns the allowed columns that can be manually applied from resolved_payload.final_payload for safe catalog entities.';

revoke all on function private.safe_resolved_payload_columns(text) from public;
grant execute on function private.safe_resolved_payload_columns(text) to authenticated, service_role;

-- =========================================================
-- 2. HELPER: existe columna en tabla pública
-- =========================================================

create or replace function private.public_table_column_exists(
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

comment on function private.public_table_column_exists(text, text)
is 'Returns whether a column exists in a public table.';

revoke all on function private.public_table_column_exists(text, text) from public;
grant execute on function private.public_table_column_exists(text, text) to authenticated, service_role;

-- =========================================================
-- 3. RPC: aplicar resolved_payload.final_payload a entidad segura
-- =========================================================

create or replace function public.apply_resolved_sync_conflict_payload(
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

  v_final_payload jsonb;
  v_allowed_columns text[];
  v_key text;
  v_column_type text;

  v_set_parts text[] := array[]::text[];
  v_changed_fields text[] := array[]::text[];

  v_has_deleted_at boolean := false;
  v_sql text;
  v_applied_row jsonb;
  v_existing_application jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_conflict_id is null then
    raise exception 'p_sync_conflict_id is required';
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
    sc.resolution_strategy,
    sc.resolved_payload,
    sc.metadata,
    sc.deleted_at
  into v_conflict
  from public.sync_conflicts sc
  where sc.id = p_sync_conflict_id
  for update;

  if v_conflict.id is null then
    raise exception 'Sync conflict not found';
  end if;

  if v_conflict.deleted_at is not null then
    raise exception 'Cannot apply payload for deleted sync conflict';
  end if;

  if v_conflict.status <> 'resolved' then
    raise exception 'Only resolved sync conflicts can have resolved_payload applied. Current status: %', v_conflict.status;
  end if;

  if v_conflict.resolution_strategy <> 'manual_resolution' then
    raise exception 'Only manual_resolution conflicts can have resolved_payload applied. Current strategy: %', v_conflict.resolution_strategy;
  end if;

  if not private.can_resolve_sync_conflict(
    v_conflict.business_id,
    v_conflict.profile_id,
    v_conflict.branch_id
  ) then
    raise exception 'Insufficient permission to apply this resolved payload';
  end if;

  -- Permiso adicional de escritura sobre la entidad.
  if not (
    private.has_sync_entity_permission(
      v_conflict.business_id,
      v_conflict.branch_id,
      v_conflict.entity_table,
      'update'
    )
    or private.has_business_permission(v_conflict.business_id, 'settings.business')
  ) then
    raise exception 'Insufficient entity permission to apply resolved payload for %', v_conflict.entity_table;
  end if;

  if v_conflict.entity_table not in ('categories', 'customers', 'suppliers') then
    raise exception 'Resolved payload application is not supported for entity_table: %', v_conflict.entity_table;
  end if;

  if v_conflict.operation not in ('insert', 'update', 'upsert') then
    raise exception 'Resolved payload application is not supported for operation: %', v_conflict.operation;
  end if;

  v_existing_application := v_conflict.metadata -> 'resolved_payload_application';

  if coalesce(v_existing_application->>'applied', 'false') = 'true' then
    return jsonb_build_object(
      'sync_conflict_id', v_conflict.id,
      'sync_mutation_id', v_conflict.sync_mutation_id,
      'sync_batch_id', v_conflict.sync_batch_id,
      'entity_table', v_conflict.entity_table,
      'entity_id', v_conflict.entity_id,
      'already_applied', true,
      'applied', false,
      'application', v_existing_application
    );
  end if;

  if v_conflict.resolved_payload is null then
    raise exception 'resolved_payload is required before applying payload';
  end if;

  if jsonb_typeof(v_conflict.resolved_payload) <> 'object' then
    raise exception 'resolved_payload must be a JSON object';
  end if;

  v_final_payload := v_conflict.resolved_payload -> 'final_payload';

  if v_final_payload is null then
    raise exception 'resolved_payload.final_payload is required';
  end if;

  if jsonb_typeof(v_final_payload) <> 'object' then
    raise exception 'resolved_payload.final_payload must be a JSON object';
  end if;

  v_allowed_columns := private.safe_resolved_payload_columns(v_conflict.entity_table);

  if coalesce(array_length(v_allowed_columns, 1), 0) = 0 then
    raise exception 'No safe columns configured for entity_table: %', v_conflict.entity_table;
  end if;

  -- Construir SET dinámico solo con columnas:
  -- 1. presentes en final_payload
  -- 2. permitidas por entidad
  -- 3. existentes en la tabla real
  for v_key in
    select k
    from jsonb_object_keys(v_final_payload) as k
    where k = any(v_allowed_columns)
    order by k
  loop
    select format_type(a.atttypid, a.atttypmod)
    into v_column_type
    from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = v_conflict.entity_table
      and a.attname = v_key
      and a.attnum > 0
      and not a.attisdropped;

    if v_column_type is null then
      continue;
    end if;

    if v_column_type in ('json', 'jsonb') then
      if v_key = 'metadata' then
        v_set_parts := array_append(
          v_set_parts,
          format(
            '%I = coalesce(e.%I::jsonb, ''{}''::jsonb) || coalesce($1 -> %L, ''{}''::jsonb)',
            v_key,
            v_key,
            v_key
          )
        );
      else
        v_set_parts := array_append(
          v_set_parts,
          format('%I = ($1 -> %L)::%s', v_key, v_key, v_column_type)
        );
      end if;
    else
      v_set_parts := array_append(
        v_set_parts,
        format('%I = ($1 ->> %L)::%s', v_key, v_key, v_column_type)
      );
    end if;

    v_changed_fields := array_append(v_changed_fields, v_key);
  end loop;

  if coalesce(array_length(v_changed_fields, 1), 0) = 0 then
    raise exception 'resolved_payload.final_payload does not contain any allowed existing columns for %', v_conflict.entity_table;
  end if;

  -- Auditoría común si existen las columnas.
  if private.public_table_column_exists(v_conflict.entity_table, 'updated_at') then
    v_set_parts := array_append(v_set_parts, 'updated_at = now()');
  end if;

  if private.public_table_column_exists(v_conflict.entity_table, 'updated_by') then
    v_set_parts := array_append(v_set_parts, 'updated_by = $4');
  end if;

  if private.public_table_column_exists(v_conflict.entity_table, 'sync_status') then
    v_set_parts := array_append(v_set_parts, 'sync_status = ''synced''');
  end if;

  v_has_deleted_at := private.public_table_column_exists(v_conflict.entity_table, 'deleted_at');

  v_sql := format(
    'update public.%I as e
     set %s
     where e.id = $2
       and e.business_id = $3
       %s
     returning to_jsonb(e.*)',
    v_conflict.entity_table,
    array_to_string(v_set_parts, ', '),
    case
      when v_has_deleted_at then 'and e.deleted_at is null'
      else ''
    end
  );

  execute v_sql
  using
    v_final_payload,
    v_conflict.entity_id,
    v_conflict.business_id,
    v_profile_id
  into v_applied_row;

  if v_applied_row is null then
    raise exception 'Target entity row not found or not active for %.%', v_conflict.entity_table, v_conflict.entity_id;
  end if;

  update public.sync_conflicts sc
  set
    metadata = coalesce(sc.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'resolved_payload_application',
        jsonb_build_object(
          'applied', true,
          'applied_at', now(),
          'applied_by', v_profile_id,
          'mode', 'safe_existing_entity_update',
          'entity_table', v_conflict.entity_table,
          'entity_id', v_conflict.entity_id,
          'changed_fields', to_jsonb(v_changed_fields)
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sc.id = v_conflict.id;

  update public.sync_mutations sm
  set
    metadata = coalesce(sm.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'resolved_payload_application',
        jsonb_build_object(
          'applied', true,
          'applied_at', now(),
          'applied_by', v_profile_id,
          'mode', 'safe_existing_entity_update',
          'entity_table', v_conflict.entity_table,
          'entity_id', v_conflict.entity_id,
          'changed_fields', to_jsonb(v_changed_fields)
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sm.id = v_conflict.sync_mutation_id
    and sm.deleted_at is null;

  return jsonb_build_object(
    'sync_conflict_id', v_conflict.id,
    'sync_mutation_id', v_conflict.sync_mutation_id,
    'sync_batch_id', v_conflict.sync_batch_id,
    'entity_table', v_conflict.entity_table,
    'entity_id', v_conflict.entity_id,
    'operation', v_conflict.operation,
    'applied', true,
    'already_applied', false,
    'mode', 'safe_existing_entity_update',
    'changed_fields', to_jsonb(v_changed_fields),
    'applied_row', v_applied_row
  );
end;
$$;

comment on function public.apply_resolved_sync_conflict_payload(uuid)
is 'Applies resolved_payload.final_payload to safe existing catalog entities only: categories, customers and suppliers. Does not apply to purchases, sales, cash or inventory. Idempotent via sync_conflicts.metadata.resolved_payload_application.';

revoke all on function public.apply_resolved_sync_conflict_payload(uuid) from public;
grant execute on function public.apply_resolved_sync_conflict_payload(uuid) to authenticated;
grant execute on function public.apply_resolved_sync_conflict_payload(uuid) to service_role;

commit;