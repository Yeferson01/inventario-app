-- Fase 6.6 - Sync helper functions
-- Objetivo:
-- Crear helpers internas para process_sync_batch().
--
-- Estas funciones NO aplican todavía mutaciones reales.
-- Preparan:
-- - validación de permisos por entidad
-- - snapshots del servidor
-- - marcado de mutaciones
-- - recálculo de contadores
-- - finalización de batches

begin;

-- =========================================================
-- PERMISSION CANDIDATES BY ENTITY / OPERATION
-- =========================================================

create or replace function private.sync_entity_permission_candidates(
  p_entity_table text,
  p_operation text
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_operation text;
  v_action text;
begin
  v_entity := lower(trim(coalesce(p_entity_table, '')));
  v_operation := lower(trim(coalesce(p_operation, '')));

  v_action := case
    when v_operation in ('insert', 'upsert') then 'create'
    when v_operation = 'update' then 'update'
    when v_operation in ('soft_delete', 'delete') then 'soft_delete'
    else null
  end;

  if v_entity = '' or v_action is null then
    return array[]::text[];
  end if;

  -- Catálogo
  if v_entity = 'categories' then
    return array[
      'categories.' || v_action,
      'products.' || v_action,
      'inventory.' || case when v_action = 'create' then 'adjust' else 'read' end
    ];
  end if;

  if v_entity = 'products' then
    return array[
      'products.' || v_action,
      'inventory.' || case when v_action in ('create', 'update') then 'adjust' else 'read' end
    ];
  end if;

  if v_entity = 'customers' then
    return array[
      'customers.' || v_action,
      'sales.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity = 'suppliers' then
    return array[
      'suppliers.' || v_action,
      'purchases.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  -- Compras
  if v_entity in ('purchases', 'purchase_items') then
    return array[
      'purchases.' || v_action
    ];
  end if;

  -- Ventas / POS
  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array[
      'sales.' || v_action
    ];
  end if;

  if v_entity in ('cash_sessions', 'cash_registers') then
    return array[
      'sales.' || case
        when v_action = 'create' then 'create'
        when v_action = 'update' then 'update'
        else 'soft_delete'
      end
    ];
  end if;

  -- Inventario
  if v_entity = 'inventory_movements' then
    -- inventory_movements debe ser append-only.
    -- No permitimos update/delete vía sync.
    if v_operation in ('insert', 'upsert') then
      return array[
        'inventory.adjust',
        'inventory.count',
        'inventory.transfer',
        'purchases.create',
        'sales.create'
      ];
    end if;

    return array[]::text[];
  end if;

  if v_entity in ('stock_counts', 'stock_count_items') then
    return array[
      'inventory.count'
    ];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array[
      'inventory.transfer'
    ];
  end if;

  -- Fallback conservador
  return array[
    v_entity || '.' || v_action,
    'settings.business'
  ];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text)
is 'Returns candidate permissions required to sync a given entity/operation.';

-- =========================================================
-- CHECK SYNC ENTITY PERMISSION
-- =========================================================

create or replace function private.has_sync_entity_permission(
  p_business_id uuid,
  p_branch_id uuid,
  p_entity_table text,
  p_operation text
)
returns boolean
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_permissions text[];
  v_permission text;
begin
  if p_business_id is null then
    return false;
  end if;

  v_permissions := private.sync_entity_permission_candidates(
    p_entity_table,
    p_operation
  );

  if v_permissions is null or cardinality(v_permissions) = 0 then
    return false;
  end if;

  foreach v_permission in array v_permissions loop
    if private.has_business_permission(p_business_id, v_permission) then
      return true;
    end if;

    if p_branch_id is not null
       and private.has_branch_permission(p_business_id, p_branch_id, v_permission) then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

comment on function private.has_sync_entity_permission(uuid, uuid, text, text)
is 'Checks whether the current authenticated user can sync a given entity/operation.';

-- =========================================================
-- GET CURRENT SERVER PAYLOAD
-- =========================================================

create or replace function private.get_current_server_payload(
  p_entity_table text,
  p_entity_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_payload jsonb;
begin
  v_entity := lower(trim(coalesce(p_entity_table, '')));

  if p_entity_id is null then
    return null;
  end if;

  if v_entity not in (
    'categories',
    'products',
    'customers',
    'suppliers',

    'purchases',
    'purchase_items',

    'sales',
    'sale_items',
    'sale_payments',

    'inventory_movements',
    'stock_counts',
    'stock_count_items',
    'inventory_transfers',
    'inventory_transfer_items',

    'cash_sessions',
    'cash_registers'
  ) then
    raise exception 'Unsupported sync entity_table: %', p_entity_table;
  end if;

  execute format(
    'select to_jsonb(t) from public.%I t where t.id = $1',
    v_entity
  )
  into v_payload
  using p_entity_id;

  return v_payload;
end;
$$;

comment on function private.get_current_server_payload(text, uuid)
is 'Returns current server-side row payload for a whitelisted sync entity.';

-- =========================================================
-- RECALCULATE BATCH COUNTS
-- =========================================================

create or replace function private.recalculate_sync_batch_counts(
  p_sync_batch_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  update public.sync_batches sb
  set
    mutation_count = counts.total_count,
    applied_count = counts.applied_count,
    skipped_count = counts.skipped_count,
    conflict_count = counts.conflict_count,
    error_count = counts.error_count,
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sb.updated_by)
  from (
    select
      count(*)::integer as total_count,
      count(*) filter (where sm.status = 'applied')::integer as applied_count,
      count(*) filter (where sm.status = 'skipped')::integer as skipped_count,
      count(*) filter (where sm.status = 'conflict')::integer as conflict_count,
      count(*) filter (where sm.status = 'error')::integer as error_count
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
  ) counts
  where sb.id = p_sync_batch_id;
end;
$$;

comment on function private.recalculate_sync_batch_counts(uuid)
is 'Recalculates sync batch counters from active sync_mutations.';

-- =========================================================
-- MARK BATCH PROCESSING
-- =========================================================

create or replace function private.mark_sync_batch_processing(
  p_sync_batch_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  update public.sync_batches sb
  set
    status = 'processing',
    server_started_at = coalesce(sb.server_started_at, now()),
    error_message = null,
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sb.updated_by)
  where sb.id = p_sync_batch_id
    and sb.deleted_at is null
    and sb.status in ('pending', 'processing');
end;
$$;

comment on function private.mark_sync_batch_processing(uuid)
is 'Marks a sync batch as processing.';

-- =========================================================
-- MARK MUTATION APPLIED
-- =========================================================

create or replace function private.mark_sync_mutation_applied(
  p_sync_mutation_id uuid,
  p_server_entity_version integer default null
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch_id uuid;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  select sm.sync_batch_id
  into v_batch_id
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_batch_id is null then
    raise exception 'Sync mutation not found';
  end if;

  update public.sync_mutations sm
  set
    status = 'applied',
    server_processed_at = coalesce(sm.server_processed_at, now()),
    server_entity_version = coalesce(p_server_entity_version, sm.server_entity_version),
    error_code = null,
    error_message = null,
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sm.updated_by)
  where sm.id = p_sync_mutation_id;

  perform private.recalculate_sync_batch_counts(v_batch_id);
end;
$$;

comment on function private.mark_sync_mutation_applied(uuid, integer)
is 'Marks a sync mutation as applied and recalculates parent batch counters.';

-- =========================================================
-- MARK MUTATION SKIPPED
-- =========================================================

create or replace function private.mark_sync_mutation_skipped(
  p_sync_mutation_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch_id uuid;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  select sm.sync_batch_id
  into v_batch_id
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_batch_id is null then
    raise exception 'Sync mutation not found';
  end if;

  update public.sync_mutations sm
  set
    status = 'skipped',
    server_processed_at = coalesce(sm.server_processed_at, now()),
    error_code = 'skipped',
    error_message = coalesce(p_reason, 'Mutation skipped'),
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sm.updated_by)
  where sm.id = p_sync_mutation_id;

  perform private.recalculate_sync_batch_counts(v_batch_id);
end;
$$;

comment on function private.mark_sync_mutation_skipped(uuid, text)
is 'Marks a sync mutation as skipped and recalculates parent batch counters.';

-- =========================================================
-- MARK MUTATION ERROR
-- =========================================================

create or replace function private.mark_sync_mutation_error(
  p_sync_mutation_id uuid,
  p_error_code text,
  p_error_message text
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch_id uuid;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  if p_error_message is null or length(trim(p_error_message)) = 0 then
    raise exception 'p_error_message is required';
  end if;

  select sm.sync_batch_id
  into v_batch_id
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_batch_id is null then
    raise exception 'Sync mutation not found';
  end if;

  update public.sync_mutations sm
  set
    status = 'error',
    server_processed_at = coalesce(sm.server_processed_at, now()),
    error_code = coalesce(nullif(trim(p_error_code), ''), 'sync_error'),
    error_message = p_error_message,
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sm.updated_by)
  where sm.id = p_sync_mutation_id;

  perform private.recalculate_sync_batch_counts(v_batch_id);
end;
$$;

comment on function private.mark_sync_mutation_error(uuid, text, text)
is 'Marks a sync mutation as error and recalculates parent batch counters.';

-- =========================================================
-- CREATE CONFLICT FOR MUTATION
-- =========================================================

create or replace function private.create_sync_conflict_for_mutation(
  p_sync_mutation_id uuid,
  p_conflict_type text,
  p_severity text default 'medium',
  p_server_payload jsonb default null,
  p_error_message text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_existing_conflict_id uuid;
  v_conflict_id uuid;
  v_server_version integer;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  select
    sm.id,
    sm.business_id,
    sm.sync_batch_id,
    sm.app_device_id,
    sm.profile_id,
    sm.branch_id,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.client_mutation_id,
    sm.client_sequence,
    sm.payload,
    sm.before_payload,
    sm.base_version,
    sm.server_entity_version
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
    and sm.deleted_at is null
  for update;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  select sc.id
  into v_existing_conflict_id
  from public.sync_conflicts sc
  where sc.sync_mutation_id = p_sync_mutation_id
    and sc.deleted_at is null
  limit 1;

  if v_existing_conflict_id is not null then
    perform private.recalculate_sync_batch_counts(v_mutation.sync_batch_id);
    return v_existing_conflict_id;
  end if;

  if p_server_payload is not null
     and p_server_payload ? 'version'
     and (p_server_payload ->> 'version') ~ '^[0-9]+$' then
    v_server_version := (p_server_payload ->> 'version')::integer;
  else
    v_server_version := v_mutation.server_entity_version;
  end if;

  insert into public.sync_conflicts (
    business_id,
    sync_batch_id,
    sync_mutation_id,
    app_device_id,
    profile_id,
    branch_id,

    entity_table,
    entity_id,
    operation,

    client_mutation_id,
    client_sequence,

    conflict_type,
    severity,
    status,

    base_payload,
    client_payload,
    server_payload,

    base_version,
    server_entity_version,

    error_code,
    error_message,

    created_by,
    updated_by,
    metadata
  )
  values (
    v_mutation.business_id,
    v_mutation.sync_batch_id,
    v_mutation.id,
    v_mutation.app_device_id,
    v_mutation.profile_id,
    v_mutation.branch_id,

    v_mutation.entity_table,
    v_mutation.entity_id,
    v_mutation.operation,

    v_mutation.client_mutation_id,
    v_mutation.client_sequence,

    coalesce(nullif(trim(p_conflict_type), ''), 'unknown'),
    coalesce(nullif(trim(p_severity), ''), 'medium'),
    'open',

    v_mutation.before_payload,
    v_mutation.payload,
    p_server_payload,

    v_mutation.base_version,
    v_server_version,

    coalesce(nullif(trim(p_conflict_type), ''), 'unknown'),
    coalesce(p_error_message, 'Sync conflict detected'),

    auth.uid(),
    auth.uid(),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_conflict_id;

  perform private.recalculate_sync_batch_counts(v_mutation.sync_batch_id);

  return v_conflict_id;
end;
$$;

comment on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb)
is 'Creates a sync_conflict for a mutation and returns the conflict id.';

-- =========================================================
-- FINALIZE BATCH FROM COUNTS
-- =========================================================

create or replace function private.finalize_sync_batch_from_counts(
  p_sync_batch_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch record;
  v_new_status text;
begin
  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  perform private.recalculate_sync_batch_counts(p_sync_batch_id);

  select
    sb.id,
    sb.app_device_id,
    sb.mutation_count,
    sb.applied_count,
    sb.skipped_count,
    sb.conflict_count,
    sb.error_count
  into v_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id
    and sb.deleted_at is null
  for update;

  if v_batch.id is null then
    raise exception 'Sync batch not found';
  end if;

  if v_batch.mutation_count = 0 then
    v_new_status := 'completed';
  elsif v_batch.error_count = v_batch.mutation_count then
    v_new_status := 'failed';
  elsif v_batch.conflict_count > 0
     or v_batch.error_count > 0
     or v_batch.skipped_count > 0 then
    v_new_status := 'partial';
  elsif v_batch.applied_count = v_batch.mutation_count then
    v_new_status := 'completed';
  else
    v_new_status := 'processing';
  end if;

  update public.sync_batches sb
  set
    status = v_new_status,
    server_completed_at = case
      when v_new_status in ('completed', 'partial', 'failed', 'cancelled')
        then coalesce(sb.server_completed_at, now())
      else sb.server_completed_at
    end,
    updated_at = now(),
    updated_by = coalesce(auth.uid(), sb.updated_by)
  where sb.id = p_sync_batch_id;

  if v_new_status in ('completed', 'partial') then
    update public.app_devices ad
    set
      last_seen_at = now(),
      last_sync_completed_at = now(),
      updated_at = now(),
      updated_by = coalesce(auth.uid(), ad.updated_by)
    where ad.id = v_batch.app_device_id;
  else
    update public.app_devices ad
    set
      last_seen_at = now(),
      updated_at = now(),
      updated_by = coalesce(auth.uid(), ad.updated_by)
    where ad.id = v_batch.app_device_id;
  end if;
end;
$$;

comment on function private.finalize_sync_batch_from_counts(uuid)
is 'Finalizes a sync batch status based on mutation counters and updates app_device sync timestamps.';

-- =========================================================
-- GRANTS
-- =========================================================

revoke all on function private.sync_entity_permission_candidates(text, text) from public;
revoke all on function private.has_sync_entity_permission(uuid, uuid, text, text) from public;
revoke all on function private.get_current_server_payload(text, uuid) from public;
revoke all on function private.recalculate_sync_batch_counts(uuid) from public;
revoke all on function private.mark_sync_batch_processing(uuid) from public;
revoke all on function private.mark_sync_mutation_applied(uuid, integer) from public;
revoke all on function private.mark_sync_mutation_skipped(uuid, text) from public;
revoke all on function private.mark_sync_mutation_error(uuid, text, text) from public;
revoke all on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb) from public;
revoke all on function private.finalize_sync_batch_from_counts(uuid) from public;

grant execute on function private.sync_entity_permission_candidates(text, text) to authenticated, service_role;
grant execute on function private.has_sync_entity_permission(uuid, uuid, text, text) to authenticated, service_role;
grant execute on function private.get_current_server_payload(text, uuid) to authenticated, service_role;
grant execute on function private.recalculate_sync_batch_counts(uuid) to authenticated, service_role;
grant execute on function private.mark_sync_batch_processing(uuid) to authenticated, service_role;
grant execute on function private.mark_sync_mutation_applied(uuid, integer) to authenticated, service_role;
grant execute on function private.mark_sync_mutation_skipped(uuid, text) to authenticated, service_role;
grant execute on function private.mark_sync_mutation_error(uuid, text, text) to authenticated, service_role;
grant execute on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb) to authenticated, service_role;
grant execute on function private.finalize_sync_batch_from_counts(uuid) to authenticated, service_role;

commit;