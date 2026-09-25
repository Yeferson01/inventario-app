-- P2.5X-A2: extend direct movement ACK to loss; preserve existing sources and ACL.
begin;

create or replace function public.lookup_inventory_movement_acknowledgements(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_operations jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_context jsonb;
  v_permissions jsonb;
  v_allowed boolean;
  v_operation jsonb;
  v_results jsonb := '[]'::jsonb;

  v_client_movement_id uuid;
  v_local_idempotency_key text;
  v_source_type text;
  v_source_id uuid;
  v_source_item_id uuid;
  v_product_id uuid;
  v_quantity_change integer;
  v_remote_idempotency_key text;
  v_item_metadata_key text;
  v_parent_entity_table text;

  v_candidate_ids uuid[];
  v_candidate record;
  v_terminal_status text;
  v_status text;
  v_result jsonb;
  v_checked_at timestamp with time zone := statement_timestamp();
begin
  v_context := private.authorize_operational_device_context(
    p_business_id,
    p_branch_id,
    p_app_device_id,
    true
  );
  v_permissions := v_context -> 'effective_permissions';

  select exists (
    select 1
    from jsonb_array_elements_text(v_permissions) permission_row(value)
    where permission_row.value = any(array[
      'sales.create',
      'inventory.read',
      'inventory.purchase',
      'inventory.adjust'
    ]::text[])
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Effective permissions do not authorize inventory acknowledgement lookup';
  end if;

  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'operations must be a JSON array';
  end if;

  if jsonb_array_length(p_operations) > 200 then
    raise exception 'operations exceeds the maximum of 200 entries';
  end if;

  for v_operation in
    select operation_row.value
    from jsonb_array_elements(p_operations) operation_row(value)
  loop
    if jsonb_typeof(v_operation) <> 'object' then
      raise exception 'Each acknowledgement operation must be an object';
    end if;

    begin
      v_client_movement_id := nullif(
        btrim(coalesce(v_operation ->> 'movement_id', '')),
        ''
      )::uuid;
      v_source_id := nullif(
        btrim(coalesce(v_operation ->> 'source_id', '')),
        ''
      )::uuid;
      v_source_item_id := nullif(
        btrim(coalesce(v_operation ->> 'source_item_id', '')),
        ''
      )::uuid;
      v_product_id := nullif(
        btrim(coalesce(v_operation ->> 'product_id', '')),
        ''
      )::uuid;
      v_quantity_change := nullif(
        btrim(coalesce(v_operation ->> 'quantity_change', '')),
        ''
      )::integer;
    exception when others then
      raise exception 'Invalid UUID or quantity in acknowledgement operation';
    end;

    v_local_idempotency_key := nullif(
      btrim(coalesce(v_operation ->> 'idempotency_key', '')),
      ''
    );
    v_source_type := lower(nullif(
      btrim(coalesce(v_operation ->> 'source_type', '')),
      ''
    ));

    if v_client_movement_id is null
       or v_local_idempotency_key is null
       or v_product_id is null
       or v_quantity_change is null
       or v_quantity_change = 0
       or v_source_type is null
    then
      raise exception 'movement_id, idempotency_key, source_type, product_id and non-zero quantity_change are required';
    end if;

    if length(v_local_idempotency_key) > 512 then
      raise exception 'idempotency_key exceeds 512 characters';
    end if;

    if v_source_type not in ('sale', 'purchase', 'manual_adjustment', 'loss') then
      raise exception 'Unsupported acknowledgement source_type: %', v_source_type;
    end if;

    if v_source_type = 'loss' and v_quantity_change >= 0 then
      raise exception 'loss quantity_change must be negative';
    end if;

    v_candidate_ids := null;
    v_terminal_status := null;
    v_remote_idempotency_key := v_local_idempotency_key;
    v_item_metadata_key := null;
    v_parent_entity_table := 'inventory_movements';

    if v_source_type in ('sale', 'purchase') then
      if v_source_id is null or v_source_item_id is null then
        raise exception 'source_id and source_item_id are required for sale or purchase acknowledgements';
      end if;

      v_remote_idempotency_key :=
        v_source_type || ':' || v_source_id::text || ':item:'
        || v_source_item_id::text;
      v_item_metadata_key := case
        when v_source_type = 'sale' then 'sale_item_id'
        else 'purchase_item_id'
      end;
      v_parent_entity_table := case
        when v_source_type = 'sale' then 'sale_items'
        else 'purchase_items'
      end;

      select array_agg(im.id order by im.id)
      into v_candidate_ids
      from public.inventory_movements im
      where im.business_id = p_business_id
        and im.branch_id = p_branch_id
        and (
          im.idempotency_key = v_remote_idempotency_key
          or (
            im.source_type = v_source_type
            and im.source_id = v_source_id
            and im.metadata ->> v_item_metadata_key = v_source_item_id::text
          )
        );
    else
      select array_agg(im.id order by im.id)
      into v_candidate_ids
      from public.inventory_movements im
      where im.business_id = p_business_id
        and im.branch_id = p_branch_id
        and (
          im.id = v_client_movement_id
          or im.idempotency_key = v_local_idempotency_key
        );
    end if;

    if coalesce(cardinality(v_candidate_ids), 0) > 1 then
      v_status := 'ambiguous';
      v_result := jsonb_build_object(
        'movement_id', v_client_movement_id,
        'status', v_status,
        'checked_at', v_checked_at
      );
    elsif coalesce(cardinality(v_candidate_ids), 0) = 1 then
      select
        im.id,
        im.product_id,
        im.movement_type,
        im.quantity_change,
        im.source_type,
        im.source_id,
        im.idempotency_key
      into v_candidate
      from public.inventory_movements im
      where im.id = v_candidate_ids[1];

      if v_candidate.product_id <> v_product_id
         or v_candidate.quantity_change <> v_quantity_change
         or v_candidate.source_type <> v_source_type
         or (
           v_source_type in ('sale', 'purchase')
           and v_candidate.source_id is distinct from v_source_id
         )
         or (
           v_source_type in ('manual_adjustment', 'loss')
           and (
             v_candidate.id <> v_client_movement_id
             or v_candidate.idempotency_key <> v_local_idempotency_key
           )
         )
         or (
           v_source_type = 'loss'
           and (
             v_candidate.movement_type::text is distinct from 'loss'
             or v_candidate.source_type is distinct from 'loss'
             or v_candidate.idempotency_key is distinct from v_local_idempotency_key
           )
         )
      then
        v_status := 'ambiguous';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'checked_at', v_checked_at
        );
      else
        v_status := 'applied';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'remote_movement_id', v_candidate.id,
          'remote_idempotency_key', v_candidate.idempotency_key,
          'checked_at', v_checked_at
        );
      end if;
    else
      if v_source_type in ('sale', 'purchase') then
        select sm.status
        into v_terminal_status
        from public.sync_mutations sm
        where sm.business_id = p_business_id
          and sm.branch_id = p_branch_id
          and sm.entity_table = v_parent_entity_table
          and sm.entity_id = v_source_item_id
          and sm.status in ('conflict', 'skipped')
          and sm.deleted_at is null
        order by sm.server_processed_at desc nulls last, sm.created_at desc
        limit 1;
      else
        select sm.status
        into v_terminal_status
        from public.sync_mutations sm
        where sm.business_id = p_business_id
          and sm.branch_id = p_branch_id
          and sm.entity_table = 'inventory_movements'
          and (
            sm.entity_id = v_client_movement_id
            or sm.idempotency_key = v_local_idempotency_key
          )
          and (
            v_source_type <> 'loss'
            or (
              sm.entity_id = v_client_movement_id
              and sm.idempotency_key = v_local_idempotency_key
              and sm.operation = 'insert'
              and sm.payload @> jsonb_build_object(
                'id', v_client_movement_id,
                'idempotency_key', v_local_idempotency_key,
                'business_id', p_business_id,
                'branch_id', p_branch_id,
                'product_id', v_product_id,
                'source_type', 'loss',
                'movement_type', 'loss',
                'quantity_change', v_quantity_change
              )
            )
          )
          and sm.status in ('conflict', 'skipped')
          and sm.deleted_at is null
        order by sm.server_processed_at desc nulls last, sm.created_at desc
        limit 1;
      end if;

      if v_terminal_status is not null then
        v_status := 'rejected';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'remote_evidence_status', v_terminal_status,
          'checked_at', v_checked_at
        );
      else
        v_status := 'not_found';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'checked_at', v_checked_at
        );
      end if;
    end if;

    v_results := v_results || jsonb_build_array(v_result);
  end loop;

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'app_device_id', p_app_device_id,
    'authorization_validated_at',
      v_context -> 'authorization_validated_at',
    'checked_at', v_checked_at,
    'acknowledgements', v_results
  );
end;
$$;

revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from public;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from anon;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from authenticated;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from service_role;

grant execute on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) to authenticated, service_role;

comment on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) is
'Returns minimal, tenant- and branch-scoped evidence that local inventory deltas are already represented by the immutable remote inventory ledger. Direct adjustments correlate by preserved movement ID and idempotency key; sale and purchase deltas correlate by their preserved parent/item IDs and canonical server idempotency key.';

commit;
