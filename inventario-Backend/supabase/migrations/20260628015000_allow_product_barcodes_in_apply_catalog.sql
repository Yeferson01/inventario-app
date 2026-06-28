-- Allow product_barcodes mutations to be processed in apply_catalog mode.
-- Context:
-- Flutter creates a local product from master catalog and produces two catalog
-- mutations:
--   1. products
--   2. product_barcodes
--
-- process_sync_batch previously skipped product_barcodes with:
-- "Entity is not supported by mode apply_catalog".

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
            and v_entity in (
              'categories',
              'products',
              'product_barcodes',
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
