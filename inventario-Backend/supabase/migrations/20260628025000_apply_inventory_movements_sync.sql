-- Apply inventory_movements mutations through offline sync.
--
-- Inventory is append-only:
--   - insert is allowed
--   - update / soft_delete / delete are rejected by process_sync_batch
--
-- Stock balances are not updated directly here. The existing inventory triggers
-- are responsible for updating product_stock_balances after insert.

create or replace function private.apply_sync_inventory_movement_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $function$
declare
  v_mutation record;
  v_payload jsonb;

  v_operation text;
  v_product_id uuid;
  v_quantity_change integer;
  v_movement_type text;
  v_unit_cost numeric;
  v_source_type text;
  v_source_id uuid;
  v_reference_type text;
  v_reference_id uuid;
  v_notes text;
  v_idempotency_key text;
  v_occurred_at timestamp with time zone;
  v_metadata jsonb;

  v_existing_id uuid;
  v_applied_id uuid;
  v_server_version integer;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  select
    sm.id,
    sm.business_id,
    sm.branch_id,
    sm.profile_id,
    sm.entity_id,
    sm.entity_table,
    sm.operation,
    sm.payload,
    sm.idempotency_key,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  if v_mutation.deleted_at is not null then
    perform private.mark_sync_mutation_skipped(
      p_sync_mutation_id,
      'Cannot apply deleted sync mutation'
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'Cannot apply deleted sync mutation'
    );
  end if;

  if lower(trim(coalesce(v_mutation.entity_table, ''))) <> 'inventory_movements' then
    perform private.mark_sync_mutation_skipped(
      p_sync_mutation_id,
      'Unsupported entity for inventory applier: ' || coalesce(v_mutation.entity_table, '')
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'Unsupported entity'
    );
  end if;

  v_operation := lower(trim(coalesce(v_mutation.operation, '')));

  if v_operation <> 'insert' then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'business_rule_violation',
      'inventory_movements only supports insert through sync',
      null,
      'server_wins',
      jsonb_build_object(
        'entity_table', 'inventory_movements',
        'operation', v_operation
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'inventory_movements only supports insert'
    );
  end if;

  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  v_product_id := nullif(v_payload->>'product_id', '')::uuid;
  v_quantity_change := nullif(v_payload->>'quantity_change', '')::integer;
  v_movement_type := coalesce(nullif(v_payload->>'movement_type', ''), 'adjustment');
  v_unit_cost := nullif(v_payload->>'unit_cost', '')::numeric;
  v_source_type := coalesce(nullif(v_payload->>'source_type', ''), 'offline_sync');
  v_source_id := nullif(v_payload->>'source_id', '')::uuid;
  v_reference_type := nullif(v_payload->>'reference_type', '');
  v_reference_id := nullif(v_payload->>'reference_id', '')::uuid;
  v_notes := nullif(v_payload->>'notes', '');
  v_idempotency_key := coalesce(
    nullif(v_payload->>'idempotency_key', ''),
    nullif(v_mutation.idempotency_key, '')
  );
  v_occurred_at := coalesce(
    nullif(v_payload->>'occurred_at', '')::timestamp with time zone,
    now()
  );
  v_metadata := coalesce(v_payload->'metadata', '{}'::jsonb);

  if v_product_id is null then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'validation_error',
      'inventory_movements payload requires product_id',
      null,
      'client_retry',
      jsonb_build_object('payload', v_payload)
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'product_id is required'
    );
  end if;

  if v_quantity_change is null or v_quantity_change = 0 then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'validation_error',
      'inventory_movements payload requires non-zero quantity_change',
      null,
      'client_retry',
      jsonb_build_object('payload', v_payload)
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'quantity_change must be non-zero'
    );
  end if;

  if v_idempotency_key is null then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'validation_error',
      'inventory_movements payload requires idempotency_key',
      null,
      'client_retry',
      jsonb_build_object('payload', v_payload)
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'idempotency_key is required'
    );
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = v_product_id
      and p.business_id = v_mutation.business_id
      and p.deleted_at is null
  ) then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'parent_not_found',
      'Referenced product does not exist for this business',
      null,
      'client_retry',
      jsonb_build_object(
        'product_id', v_product_id,
        'business_id', v_mutation.business_id
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'Referenced product does not exist'
    );
  end if;

  -- Idempotency: if this movement was already inserted, just mark the mutation
  -- as applied. Do not insert a second ledger row.
  select im.id
  into v_existing_id
  from public.inventory_movements im
  where im.business_id = v_mutation.business_id
    and im.idempotency_key = v_idempotency_key
  limit 1;

  if v_existing_id is not null then
    select im.version
    into v_server_version
    from public.inventory_movements im
    where im.id = v_existing_id;

    perform private.mark_sync_mutation_applied(
      p_sync_mutation_id,
      v_server_version
    );

    return jsonb_build_object(
      'status', 'applied',
      'entity_table', 'inventory_movements',
      'entity_id', v_existing_id,
      'idempotent_replay', true
    );
  end if;

  insert into public.inventory_movements (
    id,
    business_id,
    branch_id,
    product_id,
    movement_type,
    quantity_change,
    reference_id,
    reference_type,
    notes,
    created_at,
    created_by,
    source_type,
    source_id,
    unit_cost,
    idempotency_key,
    sync_status,
    version,
    occurred_at,
    metadata
  )
  values (
    v_mutation.entity_id,
    v_mutation.business_id,
    v_mutation.branch_id,
    v_product_id,
    v_movement_type,
    v_quantity_change,
    v_reference_id,
    v_reference_type,
    v_notes,
    now(),
    v_mutation.profile_id,
    v_source_type,
    v_source_id,
    v_unit_cost,
    v_idempotency_key,
    'synced',
    1,
    v_occurred_at,
    v_metadata || jsonb_build_object(
      'sync_mutation_id', p_sync_mutation_id,
      'applied_from_sync', true
    )
  )
  returning id, version
  into v_applied_id, v_server_version;

  perform private.mark_sync_mutation_applied(
    p_sync_mutation_id,
    v_server_version
  );

  return jsonb_build_object(
    'status', 'applied',
    'entity_table', 'inventory_movements',
    'entity_id', v_applied_id,
    'quantity_change', v_quantity_change
  );
end;
$function$;


create or replace function public.process_sync_batch(
  p_sync_batch_id uuid,
  p_mode text default 'validate_only'::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'private', 'extensions'
as $function$
declare
  v_profile_id uuid;
  v_batch record;
  v_mutation record;

  v_mode text := lower(trim(coalesce(p_mode, 'validate_only')));
  v_processed_count integer := 0;

  v_started_at timestamp without time zone := now();
  v_completed_at timestamp without time zone;

  v_entity text;
  v_operation text;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  if v_mode not in (
    'validate_only',
    'apply_catalog',
    'apply_pos',
    'apply_purchases',
    'apply_inventory'
  ) then
    raise exception 'Unsupported sync processing mode: %', v_mode;
  end if;

  select
    sb.id,
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.direction,
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

  if v_batch.direction <> 'upload' then
    raise exception 'Only upload sync batches can be processed';
  end if;

  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'settings.business')
       or private.has_business_permission(v_batch.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to process this sync batch';
  end if;

  perform private.mark_sync_batch_processing(p_sync_batch_id);

  for v_mutation in
    select
      sm.id,
      sm.business_id,
      sm.branch_id,
      sm.entity_table,
      sm.entity_id,
      sm.operation,
      sm.status,
      sm.deleted_at
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and sm.status in ('pending', 'error', 'conflict', 'skipped')
    order by sm.client_sequence asc nulls last, sm.created_at asc
  loop
    v_processed_count := v_processed_count + 1;
    v_entity := lower(trim(v_mutation.entity_table));
    v_operation := lower(trim(v_mutation.operation));

    begin
      if v_operation = 'delete' then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'business_rule_violation',
          'Hard delete is not allowed through sync. Use soft_delete.',
          null,
          'client_retry',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if v_entity = 'inventory_movements'
         and v_operation in ('update', 'soft_delete', 'delete') then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'business_rule_violation',
          'inventory_movements is an append-only ledger and cannot be updated or deleted',
          null,
          'server_wins',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if not private.has_sync_entity_permission(
        v_batch.business_id,
        v_batch.branch_id,
        v_entity,
        v_operation
      ) then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'permission_denied',
          'Current user does not have permission to apply this mutation',
          null,
          'client_retry',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if v_mode = 'validate_only' then
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'validate_only mode'
        );

      elsif v_mode = 'apply_inventory'
            and v_entity = 'inventory_movements' then
        perform private.apply_sync_inventory_movement_mutation(v_mutation.id);

      elsif v_mode = 'apply_catalog'
            and v_entity = 'product_barcodes' then
        perform private.apply_sync_product_barcode_mutation(v_mutation.id);

      elsif v_mode = 'apply_catalog'
            and v_entity in (
              'categories',
              'products',
              'customers',
              'suppliers'
            ) then
        perform private.apply_sync_catalog_mutation(v_mutation.id);

      elsif v_mode = 'apply_pos'
            and v_entity in ('sales', 'sale_items') then
        perform private.apply_sync_pos_mutation(v_mutation.id);

      elsif v_mode = 'apply_pos'
            and v_entity = 'sale_payments' then
        perform private.apply_sync_sale_payment_mutation(v_mutation.id);

      elsif v_mode = 'apply_purchases'
            and v_entity in ('purchases', 'purchase_items') then
        perform private.apply_sync_purchase_mutation(v_mutation.id);

      else
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'Entity is not supported by mode ' || v_mode
        );
      end if;

    exception when others then
      perform private.mark_sync_mutation_error(
        v_mutation.id,
        'unexpected_error',
        sqlerrm
      );
    end;
  end loop;

  perform private.recalculate_sync_batch_counts(p_sync_batch_id);
  perform private.finalize_sync_batch_from_counts(p_sync_batch_id);

  v_completed_at := now();

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'mode', v_mode,
    'status', (
      select sb.status
      from public.sync_batches sb
      where sb.id = p_sync_batch_id
    ),
    'mutation_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
    ),
    'processed_count', v_processed_count,
    'applied_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
    ),
    'skipped_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'skipped'
    ),
    'conflict_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'conflict'
    ),
    'error_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'error'
    ),
    'server_started_at', v_started_at,
    'server_completed_at', v_completed_at,
    'note', case
      when v_mode = 'apply_inventory' then 'Inventory movement mutations were applied when supported. Stock balances are updated by inventory triggers.'
      when v_mode = 'apply_purchases' then 'Purchases and purchase_items mutations were applied when supported. Inventory is applied separately.'
      when v_mode = 'apply_pos' then 'POS sales, sale_items and sale_payments mutations were applied when supported. Other entities were skipped.'
      when v_mode = 'apply_catalog' then 'Catalog mutations, products, product_barcodes, customers and suppliers were applied when supported. Other entities were skipped.'
      else 'Mutations were validated and skipped without applying changes.'
    end
  );
end;
$function$;
