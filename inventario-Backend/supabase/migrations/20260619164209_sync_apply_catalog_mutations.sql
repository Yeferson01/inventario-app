-- Fase 6.9 - Apply catalog mutations
-- Objetivo:
-- Permitir que process_sync_batch() aplique mutaciones reales de catálogo:
-- - categories
-- - products
-- - customers
-- - suppliers
--
-- Operaciones soportadas:
-- - insert
-- - update
-- - upsert
-- - soft_delete
--
-- Importante:
-- - delete físico sigue prohibido.
-- - inventory_movements sigue siendo inmutable.
-- - POS e inventario operativo se aplicarán en fases posteriores.

begin;

-- =========================================================
-- HELPER: APPLY CATALOG MUTATION
-- =========================================================

create or replace function private.apply_sync_catalog_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_payload jsonb;
  v_server_payload jsonb;
  v_result_payload jsonb;

  v_entity text;
  v_operation text;

  v_exists boolean := false;
  v_deleted boolean := false;

  v_server_version integer;
  v_new_version integer;

  v_name text;
  v_full_name text;

  v_category_id uuid;
  v_supplier_id uuid;
  v_master_product_id uuid;

  v_conflict_id uuid;
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
    sm.client_mutation_id,
    sm.client_sequence,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.before_payload,
    sm.base_version,
    sm.base_updated_at,
    sm.status,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  if v_mutation.deleted_at is not null then
    raise exception 'Cannot apply deleted sync mutation';
  end if;

  v_entity := lower(trim(v_mutation.entity_table));
  v_operation := lower(trim(v_mutation.operation));
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  if v_entity not in ('categories', 'products', 'customers', 'suppliers') then
    perform private.mark_sync_mutation_skipped(
      v_mutation.id,
      'Entity is not part of catalog apply phase.'
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'unsupported_entity_for_catalog_phase',
      'entity_table', v_entity
    );
  end if;

  if v_operation = 'delete' then
    v_server_payload := private.get_current_server_payload(
      v_entity,
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'business_rule_violation',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Hard delete is not allowed. Use soft_delete instead.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'rule', 'no_hard_delete'
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'hard_delete_not_allowed'
    );
  end if;

  if v_operation not in ('insert', 'update', 'upsert', 'soft_delete') then
    perform private.mark_sync_mutation_error(
      v_mutation.id,
      'unsupported_operation',
      'Unsupported catalog sync operation: ' || v_operation
    );

    return jsonb_build_object(
      'status', 'error',
      'reason', 'unsupported_operation'
    );
  end if;

  -- Defensa en profundidad: validar permiso otra vez dentro del apply helper.
  if not private.has_sync_entity_permission(
    v_mutation.business_id,
    v_mutation.branch_id,
    v_entity,
    v_operation
  ) then
    v_server_payload := private.get_current_server_payload(
      v_entity,
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'permission_denied',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Current user does not have permission to apply this catalog mutation.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'entity_table', v_entity,
        'operation', v_operation
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'permission_denied'
    );
  end if;

  v_server_payload := private.get_current_server_payload(
    v_entity,
    v_mutation.entity_id
  );

  v_exists := v_server_payload is not null;
  v_deleted := v_exists
    and v_server_payload ? 'deleted_at'
    and nullif(v_server_payload ->> 'deleted_at', '') is not null;

  if v_exists
     and v_server_payload ? 'version'
     and (v_server_payload ->> 'version') ~ '^[0-9]+$' then
    v_server_version := (v_server_payload ->> 'version')::integer;
  else
    v_server_version := null;
  end if;

  -- INSERT con ID ya existente debe ser conflicto.
  if v_operation = 'insert' and v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'duplicate_key',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Cannot insert catalog row because entity_id already exists on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'duplicate_key'
    );
  end if;

  -- UPDATE / SOFT_DELETE requieren fila existente.
  if v_operation in ('update', 'soft_delete') and not v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'missing_server_row',
      p_severity := 'medium',
      p_server_payload := null,
      p_error_message := 'Cannot update or soft_delete catalog row because it does not exist on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'missing_server_row'
    );
  end if;

  if v_operation in ('update', 'soft_delete') and v_deleted then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'deleted_on_server',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Cannot update catalog row because it is already deleted on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'deleted_on_server'
    );
  end if;

  -- Control optimista por version.
  if v_operation in ('update', 'upsert', 'soft_delete')
     and v_exists
     and not v_deleted
     and v_mutation.base_version is not null
     and v_server_version is not null
     and v_server_version > v_mutation.base_version then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'version_mismatch',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Server row version is newer than client base_version.',
      p_metadata := jsonb_build_object(
        'phase', '6.9',
        'entity_table', v_entity,
        'server_version', v_server_version,
        'client_base_version', v_mutation.base_version
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'version_mismatch'
    );
  end if;

  -- =========================================================
  -- CATEGORIES
  -- =========================================================

  if v_entity = 'categories' then
    if v_operation in ('insert', 'upsert') and not v_exists then
      v_name := nullif(trim(v_payload ->> 'name'), '');

      if v_name is null then
        raise exception 'categories.name is required';
      end if;

      insert into public.categories (
        id,
        business_id,
        name,
        description,
        created_by,
        updated_by,
        sync_status,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_name,
        nullif(v_payload ->> 'description', ''),
        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.categories c
      set
        name = case
          when v_payload ? 'name' then nullif(trim(v_payload ->> 'name'), '')
          else c.name
        end,
        description = case
          when v_payload ? 'description' then nullif(v_payload ->> 'description', '')
          else c.description
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where c.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.categories c
      set
        deleted_at = coalesce(c.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where c.id = v_mutation.entity_id;
    end if;
  end if;

  -- =========================================================
  -- CUSTOMERS
  -- =========================================================

  if v_entity = 'customers' then
    if v_operation in ('insert', 'upsert') and not v_exists then
      v_full_name := nullif(trim(v_payload ->> 'full_name'), '');

      if v_full_name is null then
        raise exception 'customers.full_name is required';
      end if;

      insert into public.customers (
        id,
        business_id,
        full_name,
        phone,
        email,
        address,
        created_by,
        updated_by,
        sync_status,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_full_name,
        nullif(v_payload ->> 'phone', ''),
        nullif(v_payload ->> 'email', ''),
        nullif(v_payload ->> 'address', ''),
        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.customers c
      set
        full_name = case
          when v_payload ? 'full_name' then nullif(trim(v_payload ->> 'full_name'), '')
          else c.full_name
        end,
        phone = case
          when v_payload ? 'phone' then nullif(v_payload ->> 'phone', '')
          else c.phone
        end,
        email = case
          when v_payload ? 'email' then nullif(v_payload ->> 'email', '')
          else c.email
        end,
        address = case
          when v_payload ? 'address' then nullif(v_payload ->> 'address', '')
          else c.address
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where c.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.customers c
      set
        deleted_at = coalesce(c.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where c.id = v_mutation.entity_id;
    end if;
  end if;

  -- =========================================================
  -- SUPPLIERS
  -- =========================================================

  if v_entity = 'suppliers' then
    if v_operation in ('insert', 'upsert') and not v_exists then
      v_name := nullif(trim(v_payload ->> 'name'), '');

      if v_name is null then
        raise exception 'suppliers.name is required';
      end if;

      insert into public.suppliers (
        id,
        business_id,
        name,
        contact_name,
        phone,
        email,
        address,
        created_by,
        updated_by,
        sync_status,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_name,
        nullif(v_payload ->> 'contact_name', ''),
        nullif(v_payload ->> 'phone', ''),
        nullif(v_payload ->> 'email', ''),
        nullif(v_payload ->> 'address', ''),
        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.suppliers s
      set
        name = case
          when v_payload ? 'name' then nullif(trim(v_payload ->> 'name'), '')
          else s.name
        end,
        contact_name = case
          when v_payload ? 'contact_name' then nullif(v_payload ->> 'contact_name', '')
          else s.contact_name
        end,
        phone = case
          when v_payload ? 'phone' then nullif(v_payload ->> 'phone', '')
          else s.phone
        end,
        email = case
          when v_payload ? 'email' then nullif(v_payload ->> 'email', '')
          else s.email
        end,
        address = case
          when v_payload ? 'address' then nullif(v_payload ->> 'address', '')
          else s.address
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where s.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.suppliers s
      set
        deleted_at = coalesce(s.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where s.id = v_mutation.entity_id;
    end if;
  end if;

  -- =========================================================
  -- PRODUCTS
  -- =========================================================

  if v_entity = 'products' then
    if v_payload ? 'category_id'
       and nullif(v_payload ->> 'category_id', '') is not null then
      v_category_id := (v_payload ->> 'category_id')::uuid;

      if not exists (
        select 1
        from public.categories c
        where c.id = v_category_id
          and c.business_id = v_mutation.business_id
          and c.deleted_at is null
      ) then
        raise exception 'products.category_id must belong to the same business';
      end if;
    else
      v_category_id := null;
    end if;

    if v_payload ? 'supplier_id'
       and nullif(v_payload ->> 'supplier_id', '') is not null then
      v_supplier_id := (v_payload ->> 'supplier_id')::uuid;

      if not exists (
        select 1
        from public.suppliers s
        where s.id = v_supplier_id
          and s.business_id = v_mutation.business_id
          and s.deleted_at is null
      ) then
        raise exception 'products.supplier_id must belong to the same business';
      end if;
    else
      v_supplier_id := null;
    end if;

    if v_payload ? 'master_product_id'
       and nullif(v_payload ->> 'master_product_id', '') is not null then
      v_master_product_id := (v_payload ->> 'master_product_id')::uuid;

      if not exists (
        select 1
        from public.master_products_catalog mpc
        where mpc.id = v_master_product_id
      ) then
        raise exception 'products.master_product_id does not exist';
      end if;
    else
      v_master_product_id := null;
    end if;

    if v_operation in ('insert', 'upsert') and not v_exists then
      v_name := nullif(trim(v_payload ->> 'name'), '');

      if v_name is null then
        raise exception 'products.name is required';
      end if;

      if not (v_payload ? 'sale_price') then
        raise exception 'products.sale_price is required';
      end if;

      insert into public.products (
        id,
        business_id,
        category_id,
        supplier_id,
        barcode,
        name,
        description,
        purchase_price,
        sale_price,
        stock_quantity,
        minimum_stock,
        unit,
        status,
        master_product_id,
        simple_category,
        created_by,
        updated_by,
        sync_status,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_category_id,
        v_supplier_id,
        nullif(v_payload ->> 'barcode', ''),
        v_name,
        nullif(v_payload ->> 'description', ''),
        coalesce((nullif(v_payload ->> 'purchase_price', ''))::numeric, 0),
        (v_payload ->> 'sale_price')::numeric,
        0,
        coalesce((nullif(v_payload ->> 'minimum_stock', ''))::integer, 0),
        coalesce(nullif(v_payload ->> 'unit', ''), 'unidad'),
        coalesce(nullif(v_payload ->> 'status', ''), 'active'),
        v_master_product_id,
        nullif(v_payload ->> 'simple_category', ''),
        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id,
          'stock_note', 'stock_quantity forced to 0; stock must move through inventory_movements'
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.products p
      set
        category_id = case
          when v_payload ? 'category_id' then v_category_id
          else p.category_id
        end,
        supplier_id = case
          when v_payload ? 'supplier_id' then v_supplier_id
          else p.supplier_id
        end,
        barcode = case
          when v_payload ? 'barcode' then nullif(v_payload ->> 'barcode', '')
          else p.barcode
        end,
        name = case
          when v_payload ? 'name' then nullif(trim(v_payload ->> 'name'), '')
          else p.name
        end,
        description = case
          when v_payload ? 'description' then nullif(v_payload ->> 'description', '')
          else p.description
        end,
        purchase_price = case
          when v_payload ? 'purchase_price' then coalesce((nullif(v_payload ->> 'purchase_price', ''))::numeric, 0)
          else p.purchase_price
        end,
        sale_price = case
          when v_payload ? 'sale_price' then (v_payload ->> 'sale_price')::numeric
          else p.sale_price
        end,
        minimum_stock = case
          when v_payload ? 'minimum_stock' then coalesce((nullif(v_payload ->> 'minimum_stock', ''))::integer, 0)
          else p.minimum_stock
        end,
        unit = case
          when v_payload ? 'unit' then coalesce(nullif(v_payload ->> 'unit', ''), 'unidad')
          else p.unit
        end,
        status = case
          when v_payload ? 'status' then coalesce(nullif(v_payload ->> 'status', ''), p.status)
          else p.status
        end,
        master_product_id = case
          when v_payload ? 'master_product_id' then v_master_product_id
          else p.master_product_id
        end,
        simple_category = case
          when v_payload ? 'simple_category' then nullif(v_payload ->> 'simple_category', '')
          else p.simple_category
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where p.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.products p
      set
        deleted_at = coalesce(p.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where p.id = v_mutation.entity_id;
    end if;
  end if;

  v_result_payload := private.get_current_server_payload(
    v_entity,
    v_mutation.entity_id
  );

  if v_result_payload is not null
     and v_result_payload ? 'version'
     and (v_result_payload ->> 'version') ~ '^[0-9]+$' then
    v_new_version := (v_result_payload ->> 'version')::integer;
  else
    v_new_version := null;
  end if;

  perform private.mark_sync_mutation_applied(
    v_mutation.id,
    v_new_version
  );

  return jsonb_build_object(
    'status', 'applied',
    'entity_table', v_entity,
    'entity_id', v_mutation.entity_id,
    'operation', v_operation,
    'server_entity_version', v_new_version
  );
end;
$$;

comment on function private.apply_sync_catalog_mutation(uuid)
is 'Applies insert/update/upsert/soft_delete sync mutations for catalog entities: categories, products, customers and suppliers.';

revoke all on function private.apply_sync_catalog_mutation(uuid) from public;
grant execute on function private.apply_sync_catalog_mutation(uuid) to authenticated, service_role;

-- =========================================================
-- UPDATE PUBLIC PROCESS SYNC BATCH
-- =========================================================

create or replace function public.process_sync_batch(
  p_sync_batch_id uuid,
  p_mode text default 'validate_only'
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_batch record;
  v_final_batch record;
  v_mutation record;

  v_mode text;

  v_processed_count integer := 0;
  v_permission_ok boolean;
  v_server_payload jsonb;
  v_conflict_id uuid;
  v_apply_result jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  v_mode := lower(trim(coalesce(p_mode, 'validate_only')));

  if v_mode not in ('validate_only', 'apply_catalog') then
    raise exception 'Unsupported process_sync_batch mode: %. Supported modes: validate_only, apply_catalog.', p_mode;
  end if;

  -- Bloquear batch para evitar doble procesamiento concurrente.
  select
    sb.id,
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.client_batch_id,
    sb.status,
    sb.deleted_at
  into v_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id
  for update;

  if v_batch.id is null then
    raise exception 'Sync batch not found';
  end if;

  if v_batch.deleted_at is not null then
    raise exception 'Cannot process deleted sync batch';
  end if;

  if v_batch.status in ('completed', 'partial', 'failed', 'cancelled') then
    return jsonb_build_object(
      'sync_batch_id', v_batch.id,
      'status', v_batch.status,
      'message', 'Batch already finalized',
      'processed_count', 0
    );
  end if;

  -- El usuario dueño del batch puede procesarlo.
  -- Admin/settings/security también puede procesarlo por soporte.
  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'settings.business')
       or private.has_business_permission(v_batch.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to process this sync batch';
  end if;

  -- Validar dispositivo activo.
  if not exists (
    select 1
    from public.app_devices ad
    where ad.id = v_batch.app_device_id
      and ad.business_id = v_batch.business_id
      and ad.profile_id = v_batch.profile_id
      and ad.status = 'active'
      and ad.deleted_at is null
  ) then
    raise exception 'Cannot process sync batch for inactive, blocked or deleted app_device';
  end if;

  perform private.mark_sync_batch_processing(p_sync_batch_id);

  -- Procesar mutaciones pendientes en orden estable.
  for v_mutation in
    select
      sm.id,
      sm.business_id,
      sm.sync_batch_id,
      sm.app_device_id,
      sm.profile_id,
      sm.branch_id,
      sm.client_mutation_id,
      sm.client_sequence,
      sm.entity_table,
      sm.entity_id,
      sm.operation,
      sm.payload,
      sm.before_payload,
      sm.base_version,
      sm.base_updated_at,
      sm.status,
      sm.idempotency_key
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and sm.status in ('pending', 'processing')
    order by sm.client_sequence asc, sm.created_at asc
    for update
  loop
    begin
      v_processed_count := v_processed_count + 1;

      update public.sync_mutations sm
      set
        status = 'processing',
        updated_at = now(),
        updated_by = coalesce(v_profile_id, sm.updated_by)
      where sm.id = v_mutation.id;

      -- Validar que la mutación pertenece realmente al batch.
      if v_mutation.business_id <> v_batch.business_id
         or v_mutation.app_device_id <> v_batch.app_device_id
         or v_mutation.profile_id <> v_batch.profile_id then
        perform private.mark_sync_mutation_error(
          v_mutation.id,
          'batch_mismatch',
          'Mutation does not match parent batch business/device/profile'
        );

        continue;
      end if;

      -- Prohibir hard delete por arquitectura.
      if v_mutation.operation = 'delete' then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'business_rule_violation',
          p_severity := 'high',
          p_server_payload := v_server_payload,
          p_error_message := 'Hard delete is not allowed. Use soft_delete instead.',
          p_metadata := jsonb_build_object(
            'phase', '6.9',
            'mode', v_mode,
            'rule', 'no_hard_delete'
          )
        );

        continue;
      end if;

      -- inventory_movements debe ser append-only.
      if lower(v_mutation.entity_table) = 'inventory_movements'
         and v_mutation.operation in ('update', 'soft_delete', 'delete') then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'business_rule_violation',
          p_severity := 'critical',
          p_server_payload := v_server_payload,
          p_error_message := 'inventory_movements is immutable. Updates or deletes are not allowed.',
          p_metadata := jsonb_build_object(
            'phase', '6.9',
            'mode', v_mode,
            'rule', 'inventory_movements_append_only'
          )
        );

        continue;
      end if;

      -- Validar permiso por entidad/operación.
      v_permission_ok := private.has_sync_entity_permission(
        v_mutation.business_id,
        v_mutation.branch_id,
        v_mutation.entity_table,
        v_mutation.operation
      );

      if not v_permission_ok then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'permission_denied',
          p_severity := 'high',
          p_server_payload := v_server_payload,
          p_error_message := 'Current user does not have permission to sync this entity/operation.',
          p_metadata := jsonb_build_object(
            'phase', '6.9',
            'mode', v_mode,
            'entity_table', v_mutation.entity_table,
            'operation', v_mutation.operation
          )
        );

        continue;
      end if;

      if v_mode = 'validate_only' then
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'Validated by process_sync_batch validate_only mode. No business data was changed.'
        );

        continue;
      end if;

      if v_mode = 'apply_catalog' then
        if lower(v_mutation.entity_table) in (
          'categories',
          'products',
          'customers',
          'suppliers'
        ) then
          v_apply_result := private.apply_sync_catalog_mutation(
            v_mutation.id
          );

          continue;
        else
          perform private.mark_sync_mutation_skipped(
            v_mutation.id,
            'Entity is not supported by apply_catalog mode yet.'
          );

          continue;
        end if;
      end if;

    exception
      when others then
        perform private.mark_sync_mutation_error(
          v_mutation.id,
          'exception',
          sqlerrm
        );
    end;
  end loop;

  perform private.finalize_sync_batch_from_counts(p_sync_batch_id);

  select
    sb.id,
    sb.status,
    sb.mutation_count,
    sb.applied_count,
    sb.skipped_count,
    sb.conflict_count,
    sb.error_count,
    sb.server_started_at,
    sb.server_completed_at
  into v_final_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id;

  return jsonb_build_object(
    'sync_batch_id', v_final_batch.id,
    'mode', v_mode,
    'status', v_final_batch.status,
    'processed_count', v_processed_count,
    'mutation_count', v_final_batch.mutation_count,
    'applied_count', v_final_batch.applied_count,
    'skipped_count', v_final_batch.skipped_count,
    'conflict_count', v_final_batch.conflict_count,
    'error_count', v_final_batch.error_count,
    'server_started_at', v_final_batch.server_started_at,
    'server_completed_at', v_final_batch.server_completed_at,
    'note', case
      when v_mode = 'apply_catalog'
        then 'Catalog mutations were applied when supported. Other entities were skipped.'
      else 'Validation only. No business data was changed.'
    end
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Processes a sync batch. Supports validate_only and apply_catalog modes. apply_catalog applies catalog mutations for categories, products, customers and suppliers.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;

commit;