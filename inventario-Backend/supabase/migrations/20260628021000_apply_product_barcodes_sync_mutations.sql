-- Apply product_barcodes mutations in catalog sync mode.
--
-- Why:
-- process_sync_batch now recognizes product_barcodes, but the generic
-- private.apply_sync_catalog_mutation still skips it. This dedicated handler
-- keeps barcode logic isolated and avoids risking existing product/category logic.

create or replace function private.apply_sync_product_barcode_mutation(
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
  v_scope text;
  v_product_id uuid;
  v_master_product_id uuid;
  v_barcode text;
  v_barcode_normalized text;
  v_barcode_type text;
  v_status text;
  v_source text;
  v_deleted_at timestamp with time zone;
  v_applied_id uuid;
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

  if lower(trim(coalesce(v_mutation.entity_table, ''))) <> 'product_barcodes' then
    perform private.mark_sync_mutation_skipped(
      p_sync_mutation_id,
      'Unsupported entity for product barcode applier: ' || coalesce(v_mutation.entity_table, '')
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'Unsupported entity'
    );
  end if;

  v_operation := lower(trim(coalesce(v_mutation.operation, '')));
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  if v_operation = 'delete' then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'business_rule_violation',
      'Hard delete is not allowed for product_barcodes. Use soft_delete.',
      null,
      'client_retry',
      jsonb_build_object(
        'entity_table', 'product_barcodes',
        'operation', v_operation
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'Hard delete is not allowed'
    );
  end if;

  v_scope := lower(trim(coalesce(v_payload->>'scope', 'business')));

  if v_scope <> 'business' then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'business_rule_violation',
      'Offline sync can only create/update business-scoped product_barcodes',
      null,
      'client_retry',
      jsonb_build_object(
        'entity_table', 'product_barcodes',
        'scope', v_scope
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'Only business scope is allowed'
    );
  end if;

  v_product_id := nullif(v_payload->>'product_id', '')::uuid;
  v_master_product_id := nullif(v_payload->>'master_product_id', '')::uuid;
  v_barcode := nullif(v_payload->>'barcode', '');
  v_barcode_normalized := coalesce(
    nullif(v_payload->>'barcode_normalized', ''),
    v_barcode
  );
  v_barcode_type := coalesce(nullif(v_payload->>'barcode_type', ''), 'unknown');
  v_status := coalesce(nullif(v_payload->>'status', ''), 'active');
  v_source := coalesce(nullif(v_payload->>'source', ''), 'offline_sync');
  v_deleted_at := nullif(v_payload->>'deleted_at', '')::timestamp with time zone;

  if v_product_id is null then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'validation_error',
      'product_barcodes payload requires product_id',
      null,
      'client_retry',
      jsonb_build_object('payload', v_payload)
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'product_id is required'
    );
  end if;

  if v_barcode_normalized is null then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id,
      'validation_error',
      'product_barcodes payload requires barcode or barcode_normalized',
      null,
      'client_retry',
      jsonb_build_object('payload', v_payload)
    );

    return jsonb_build_object(
      'status', 'conflict',
      'reason', 'barcode_normalized is required'
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

  if v_operation in ('insert', 'update', 'upsert') then
    insert into public.product_barcodes (
      id,
      scope,
      business_id,
      product_id,
      master_product_id,
      barcode,
      barcode_normalized,
      barcode_type,
      status,
      source,
      created_at,
      updated_at,
      deleted_at
    )
    values (
      v_mutation.entity_id,
      'business',
      v_mutation.business_id,
      v_product_id,
      v_master_product_id,
      coalesce(v_barcode, v_barcode_normalized),
      v_barcode_normalized,
      v_barcode_type,
      v_status,
      v_source,
      coalesce(nullif(v_payload->>'created_at', '')::timestamp with time zone, now()),
      now(),
      v_deleted_at
    )
    on conflict (id) do update set
      scope = excluded.scope,
      business_id = excluded.business_id,
      product_id = excluded.product_id,
      master_product_id = excluded.master_product_id,
      barcode = excluded.barcode,
      barcode_normalized = excluded.barcode_normalized,
      barcode_type = excluded.barcode_type,
      status = excluded.status,
      source = excluded.source,
      updated_at = now(),
      deleted_at = excluded.deleted_at
    returning id
    into v_applied_id;

    perform private.mark_sync_mutation_applied(
      p_sync_mutation_id,
      null
    );

    return jsonb_build_object(
      'status', 'applied',
      'entity_table', 'product_barcodes',
      'entity_id', v_applied_id
    );

  elsif v_operation = 'soft_delete' then
    update public.product_barcodes pb
    set
      deleted_at = coalesce(v_deleted_at, now()),
      status = coalesce(nullif(v_payload->>'status', ''), pb.status),
      updated_at = now()
    where pb.id = v_mutation.entity_id
      and pb.business_id = v_mutation.business_id
      and pb.scope = 'business'
    returning pb.id
    into v_applied_id;

    if v_applied_id is null then
      perform private.create_sync_conflict_for_mutation(
        p_sync_mutation_id,
        'entity_not_found',
        'Cannot soft delete product_barcodes because the entity was not found',
        null,
        'client_retry',
        jsonb_build_object(
          'entity_id', v_mutation.entity_id,
          'business_id', v_mutation.business_id
        )
      );

      return jsonb_build_object(
        'status', 'conflict',
        'reason', 'Entity not found for soft_delete'
      );
    end if;

    perform private.mark_sync_mutation_applied(
      p_sync_mutation_id,
      null
    );

    return jsonb_build_object(
      'status', 'applied',
      'entity_table', 'product_barcodes',
      'entity_id', v_applied_id,
      'operation', 'soft_delete'
    );

  else
    perform private.mark_sync_mutation_skipped(
      p_sync_mutation_id,
      'Unsupported product_barcodes operation: ' || v_operation
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'Unsupported operation',
      'operation', v_operation
    );
  end if;
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

  if v_mode not in ('validate_only', 'apply_catalog', 'apply_pos', 'apply_purchases') then
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
      when v_mode = 'apply_purchases' then 'Purchases and purchase_items mutations were applied when supported. Inventory is applied separately.'
      when v_mode = 'apply_pos' then 'POS sales, sale_items and sale_payments mutations were applied when supported. Other entities were skipped.'
      when v_mode = 'apply_catalog' then 'Catalog mutations, products, product_barcodes, customers and suppliers were applied when supported. Other entities were skipped.'
      else 'Mutations were validated and skipped without applying changes.'
    end
  );
end;
$function$;
