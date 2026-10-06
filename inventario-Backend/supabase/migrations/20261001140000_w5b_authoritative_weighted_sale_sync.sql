begin;

-- W5B extends the existing POS mutation and inventory-completion path. A
-- weighted sale is accepted only from an exact, registered POS upload batch.
-- The old UNIT mapper and stale-cash-session guard remain in place.
create function private.apply_sync_exact_weight_sale_item_mutation(
  p_sync_mutation_id uuid
) returns jsonb language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mutation public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_sale public.sales%rowtype;
  v_sale_mutation public.sync_mutations%rowtype;
  v_product public.products%rowtype;
  v_existing public.sale_items%rowtype;
  v_payload jsonb;
  v_mode text;
  v_quantity integer;
  v_basis integer;
  v_price bigint;
  v_total bigint;
  v_discount numeric;
  v_tax numeric;
  v_expected bigint;
  v_version integer;
begin
  select * into v_mutation from public.sync_mutations
    where id = p_sync_mutation_id and deleted_at is null for update;
  if v_mutation.id is null or v_mutation.entity_table <> 'sale_items'
     or v_mutation.operation <> 'insert' then
    raise exception using errcode = 'P0001', message = 'invalid_weighted_sale_mutation';
  end if;
  if auth.uid() is null or not private.has_branch_permission(
      v_mutation.business_id, v_mutation.branch_id, 'sales.create') then
    raise exception using errcode = '42501', message = 'weighted_sale_permission_denied';
  end if;
  select * into v_batch from public.sync_batches
    where id = v_mutation.sync_batch_id and status = 'processing'
      and business_id = v_mutation.business_id
      and branch_id = v_mutation.branch_id
      and app_device_id = v_mutation.app_device_id
      and profile_id = v_mutation.profile_id;
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);
  if v_batch.id is null or v_batch.direction <> 'upload'
     or v_batch.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_payload->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_payload->>'quantity' !~ '^[1-9][0-9]*$'
     or v_payload->>'price_cents_snapshot' !~ '^[0-9]+$'
     or v_payload->>'line_total_cents' !~ '^[0-9]+$'
     or v_payload->>'sale_mode_snapshot' not in ('unit', 'weight')
     or nullif(v_payload->>'sale_id', '') is null
     or nullif(v_payload->>'product_id', '') is null then
    raise exception using errcode = 'P0001', message = 'invalid_weighted_sale_contract';
  end if;
  v_mode := v_payload->>'sale_mode_snapshot';
  v_quantity := (v_payload->>'quantity')::integer;
  v_basis := (v_payload->>'price_basis_quantity_snapshot')::integer;
  v_price := (v_payload->>'price_cents_snapshot')::bigint;
  v_total := (v_payload->>'line_total_cents')::bigint;
  v_discount := coalesce((v_payload->>'discount_amount')::numeric, 0);
  v_tax := coalesce((v_payload->>'tax_amount')::numeric, 0);
  if v_price > 999999999999 or v_total > 99999999999999
     or v_discount < 0 or v_tax < 0
     or (v_mode = 'weight' and (v_basis <> 500
       or v_discount <> 0 or v_tax <> 0))
     or (v_mode = 'unit' and v_basis <> 1) then
    raise exception using errcode = 'P0001', message = 'invalid_weighted_sale_contract';
  end if;
  v_expected := private.calculate_basis_amount_cents(
    v_price, v_quantity, v_basis);
  if v_expected - (v_discount * 100)::bigint
       + (v_tax * 100)::bigint <> v_total
     or (v_payload->>'unit_price')::numeric is distinct from v_price::numeric / 100
     or (v_payload->>'subtotal')::numeric is distinct from v_expected::numeric / 100
     or (v_payload->>'total')::numeric is distinct from v_total::numeric / 100
     or v_discount * 100 <> trunc(v_discount * 100)
     or v_tax * 100 <> trunc(v_tax * 100) then
    raise exception using errcode = 'P0001', message = 'weighted_sale_money_mismatch';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_payload->>'product_id', 314159));
  select * into v_product from public.products
    where id = (v_payload->>'product_id')::uuid
      and business_id = v_mutation.business_id and deleted_at is null;
  select * into v_sale from public.sales
    where id = (v_payload->>'sale_id')::uuid for update;
  select * into v_sale_mutation from public.sync_mutations
    where sync_batch_id = v_mutation.sync_batch_id and entity_table = 'sales'
      and entity_id = v_sale.id and status = 'applied'
      and deleted_at is null limit 1;
  if v_product.id is null or v_product.sale_mode is distinct from v_mode
     or v_sale.id is null or v_sale.deleted_at is not null
     or v_sale.business_id is distinct from v_mutation.business_id
     or v_sale.branch_id is distinct from v_mutation.branch_id
     or v_sale_mutation.id is null
     or v_sale_mutation.payload->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_sale_mutation.payload->'metadata'->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1' then
    raise exception using errcode = 'P0001', message = 'weighted_sale_scope_mismatch';
  end if;
  select * into v_existing from public.sale_items
    where id = v_mutation.entity_id for update;
  if v_existing.id is not null then
    if v_existing.business_id is distinct from v_mutation.business_id
       or v_existing.sale_id is distinct from v_sale.id
       or v_existing.product_id is distinct from v_product.id
       or v_existing.quantity is distinct from v_quantity
       or v_existing.sale_mode_snapshot is distinct from v_mode
       or v_existing.price_basis_quantity_snapshot is distinct from v_basis
       or v_existing.price_cents_snapshot is distinct from v_price
       or v_existing.line_total_cents is distinct from v_total
       or v_existing.idempotency_key is distinct from v_mutation.idempotency_key
       or v_existing.deleted_at is not null then
      raise exception using errcode = 'P0001',
        message = 'weighted_sale_item_idempotency_conflict';
    end if;
    perform private.mark_sync_mutation_applied(v_mutation.id, v_existing.version);
    return jsonb_build_object('status','applied','entity_table','sale_items',
      'entity_id',v_existing.id,'server_entity_version',v_existing.version);
  end if;
  insert into public.sale_items (id, business_id, sale_id, product_id,
    product_name_snapshot, barcode_snapshot, quantity, unit_price,
    unit_cost_snapshot, subtotal, discount_amount, tax_amount, total,
    sale_mode_snapshot, price_basis_quantity_snapshot, price_cents_snapshot,
    line_total_cents, created_by, updated_by, sync_status,
    idempotency_key, metadata)
  values (v_mutation.entity_id, v_mutation.business_id, v_sale.id, v_product.id,
    nullif(v_payload->>'product_name_snapshot',''),
    nullif(v_payload->>'barcode_snapshot',''), v_quantity,
    v_price::numeric / 100,
    (v_payload->>'unit_cost_snapshot')::numeric,
    v_expected::numeric / 100, v_discount, v_tax, v_total::numeric / 100,
    v_mode, v_basis, v_price, v_total,
    v_mutation.profile_id, v_mutation.profile_id, 'synced',
    v_mutation.idempotency_key,
    coalesce(v_payload->'metadata','{}'::jsonb) || jsonb_build_object(
      'w5b_verified_mutation_id',v_mutation.id,
      'monetary_contract_version','exact_weight_sale_v1'))
  returning version into v_version;
  perform private.mark_sync_mutation_applied(v_mutation.id, v_version);
  return jsonb_build_object('status','applied','entity_table','sale_items',
    'entity_id',v_mutation.entity_id,'server_entity_version',v_version);
end;
$$;
revoke all on function private.apply_sync_exact_weight_sale_item_mutation(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.apply_sync_exact_weight_sale_item_mutation(uuid)
  to service_role;

-- The already-installed mapper retains all UNIT and legacy behavior. Exact
-- mixed sales route both UNIT and WEIGHT items through the snapshot mapper.
create or replace function private.apply_sync_pos_mutation_before_cash_session_guard(
  p_sync_mutation_id uuid
) returns jsonb language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mutation public.sync_mutations%rowtype;
begin
  select * into v_mutation from public.sync_mutations
    where id = p_sync_mutation_id;
  if v_mutation.entity_table = 'sale_items'
     and v_mutation.payload->>'monetary_contract_version'
          = 'exact_weight_sale_v1' then
    return private.apply_sync_exact_weight_sale_item_mutation(p_sync_mutation_id);
  end if;
  if v_mutation.entity_table = 'sale_items' then
    return private.apply_sync_sale_item_cost_snapshot_mutation(
      p_sync_mutation_id);
  end if;
  return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
    p_sync_mutation_id);
end;
$$;
revoke all on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
  to service_role;

-- The older W1/W4 guards still fail closed. Only the W5B processor can attest
-- the item and the sale-item-derived movement.
create or replace function private.guard_unimplemented_weight_operation()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
begin
  if new.product_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(new.product_id::text,314159));
  end if;
  select sale_mode into v_mode from public.products where id = new.product_id;
  if tg_table_name = 'inventory_movements' then
    if v_mode = 'weight' and not (new.metadata ? 'w4b_verified_purchase_item_id'
      or new.metadata ? 'w5b_verified_sale_item_id') then
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  elsif tg_table_name = 'purchase_items' then
    if (v_mode = 'weight' or new.sale_mode_snapshot = 'weight') and not
       (new.sale_mode_snapshot = 'weight'
        and new.metadata ? 'w4b_verified_mutation_id') then
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  elsif tg_table_name = 'sale_items' then
    if (v_mode = 'weight' or new.sale_mode_snapshot = 'weight') and not
       (v_mode = 'weight' and new.sale_mode_snapshot = 'weight'
        and new.metadata ? 'w5b_verified_mutation_id') then
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  end if;
  return new;
end;
$$;

-- W4B's first BEFORE trigger must defer a sale to W5B's later, stricter
-- movement validator; purchase and every other source retain W4B behavior.
create or replace function private.prepare_weight_purchase_movement()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
  v_item public.purchase_items%rowtype;
  v_purchase public.purchases%rowtype;
begin
  select sale_mode into v_mode from public.products where id = new.product_id;
  if v_mode is distinct from 'weight' then return new; end if;
  if new.source_type = 'sale' and new.movement_type = 'sale'
     and new.metadata ? 'sale_item_id' then
    return new;
  end if;
  select * into v_item from public.purchase_items
    where id = nullif(new.metadata->>'purchase_item_id','')::uuid;
  if v_item.id is null then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  select * into v_purchase from public.purchases where id = v_item.purchase_id;
  if new.source_type is distinct from 'purchase'
     or new.movement_type is distinct from 'purchase'
     or v_item.sale_mode_snapshot <> 'weight'
     or v_item.monetary_contract_version <> 'exact_weight_basis_v1'
     or v_item.deleted_at is not null
     or v_purchase.id is null or v_purchase.status <> 'completed'
     or v_purchase.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_basis_v1'
     or not exists (select 1 from public.sync_mutations sm
       join public.sync_batches sb on sb.id = sm.sync_batch_id
       where sm.entity_id = v_item.id and sm.entity_table = 'purchase_items'
         and sm.operation = 'insert' and sm.status = 'applied'
         and sm.deleted_at is null and sb.status = 'completed'
         and sb.business_id = v_item.business_id
         and sb.branch_id = v_item.branch_id)
     or new.business_id is distinct from v_item.business_id
     or new.branch_id is distinct from v_item.branch_id
     or new.product_id is distinct from v_item.product_id
     or new.source_id is distinct from v_purchase.id
     or new.quantity_change is distinct from v_item.quantity
     or new.idempotency_key is distinct from
       ('purchase:' || v_purchase.id::text || ':item:' || v_item.id::text) then
    raise exception using errcode = 'P0001',
      message = 'invalid_weighted_purchase_movement';
  end if;
  new.cost_effect_cents := v_item.subtotal_cents;
  new.metadata := coalesce(new.metadata,'{}'::jsonb) ||
    jsonb_build_object('w4b_verified_purchase_item_id',v_item.id);
  return new;
end;
$$;

-- A marker alone is insufficient: the item must match its registered,
-- processing mutation and its already-applied parent sale.
create function private.prepare_weight_sale_item()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
  v_mutation public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
begin
  select sale_mode into v_mode from public.products
    where id = new.product_id and business_id = new.business_id
      and deleted_at is null;
  if v_mode is distinct from 'weight' and new.sale_mode_snapshot <> 'weight'
    then return new; end if;
  if nullif(new.metadata->>'w5b_verified_mutation_id','') is null then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  if tg_op = 'UPDATE' then
    if new.sale_id is distinct from old.sale_id
       or new.product_id is distinct from old.product_id
       or new.quantity is distinct from old.quantity
       or new.unit_price is distinct from old.unit_price
       or new.subtotal is distinct from old.subtotal
       or new.discount_amount is distinct from old.discount_amount
       or new.tax_amount is distinct from old.tax_amount
       or new.total is distinct from old.total
       or new.idempotency_key is distinct from old.idempotency_key
       or new.deleted_at is distinct from old.deleted_at then
      raise exception using errcode = 'P0001',
        message = 'weighted_sale_item_immutable';
    end if;
    return new;
  end if;
  select * into v_mutation from public.sync_mutations
    where id = nullif(new.metadata->>'w5b_verified_mutation_id','')::uuid
      and entity_table = 'sale_items' and operation = 'insert'
      and entity_id = new.id and business_id = new.business_id
      and idempotency_key = new.idempotency_key
      and status in ('pending','error','conflict','skipped')
      and deleted_at is null;
  select * into v_batch from public.sync_batches
    where id = v_mutation.sync_batch_id and status = 'processing'
      and business_id = new.business_id;
  if v_mode is distinct from 'weight'
     or new.sale_mode_snapshot is distinct from 'weight'
     or v_mutation.id is null or v_batch.id is null
     or v_mutation.branch_id is distinct from v_batch.branch_id
     or v_mutation.profile_id is distinct from v_batch.profile_id
     or v_mutation.app_device_id is distinct from v_batch.app_device_id
     or v_mutation.payload->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_mutation.payload->>'sale_id' is distinct from new.sale_id::text
     or v_mutation.payload->>'product_id' is distinct from new.product_id::text
     or v_mutation.payload->>'quantity' is distinct from new.quantity::text
     or v_mutation.payload->>'price_cents_snapshot'
          is distinct from new.price_cents_snapshot::text
     or v_mutation.payload->>'line_total_cents'
          is distinct from new.line_total_cents::text
     or new.price_basis_quantity_snapshot <> 500 then
    raise exception using errcode = 'P0001',
      message = 'invalid_weighted_sale_contract';
  end if;
  return new;
end;
$$;
create trigger trg_sale_items_a_w5b_prepare
  before insert or update on public.sale_items for each row
  execute function private.prepare_weight_sale_item();
revoke all on function private.prepare_weight_sale_item()
  from public, anon, authenticated, service_role;

-- The generic movement preparation has already locked the balance row. W2B
-- reads precisely that locked remote state, never a client-sent balance/COGS.
create function private.prepare_weight_sale_movement()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_product public.products%rowtype;
  v_item public.sale_items%rowtype;
  v_sale public.sales%rowtype;
  v_balance public.product_stock_balances%rowtype;
  v_issue record;
begin
  select * into v_product from public.products where id = new.product_id;
  if v_product.sale_mode is distinct from 'weight'
     or new.source_type is distinct from 'sale' then return new; end if;
  select * into v_item from public.sale_items
    where id = nullif(new.metadata->>'sale_item_id','')::uuid;
  select * into v_sale from public.sales where id = v_item.sale_id;
  if v_item.id is null or v_item.sale_mode_snapshot <> 'weight'
     or v_item.price_basis_quantity_snapshot <> 500
     or v_item.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_item.deleted_at is not null
     or v_sale.id is null or v_sale.status <> 'completed'
     or v_sale.deleted_at is not null or v_sale.voided_at is not null
     or new.source_type is distinct from 'sale'
     or new.movement_type is distinct from 'sale'
     or new.business_id is distinct from v_item.business_id
     or new.branch_id is distinct from v_sale.branch_id
     or new.product_id is distinct from v_item.product_id
     or new.source_id is distinct from v_sale.id
     or new.quantity_change is distinct from -v_item.quantity
     or new.idempotency_key is distinct from
       ('sale:' || v_sale.id::text || ':item:' || v_item.id::text)
     or not exists (select 1 from public.sync_mutations sm
       join public.sync_batches sb on sb.id = sm.sync_batch_id
       where sm.id = nullif(v_item.metadata->>'w5b_verified_mutation_id','')::uuid
         and sm.entity_id = v_item.id and sm.entity_table = 'sale_items'
         and sm.status = 'applied' and sb.status = 'completed'
         and sb.business_id = v_item.business_id
         and sb.branch_id = v_sale.branch_id) then
    raise exception using errcode = 'P0001',
      message = 'invalid_weighted_sale_movement';
  end if;
  select * into v_balance from public.product_stock_balances
    where business_id = new.business_id and branch_id = new.branch_id
      and product_id = new.product_id and deleted_at is null for update;
  if v_balance.id is null or v_balance.quantity_available < v_item.quantity
     or new.previous_stock is distinct from v_balance.quantity_on_hand
     or new.new_stock is distinct from
       v_balance.quantity_on_hand - v_item.quantity then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_insufficient_available_stock';
  end if;
  select * into v_issue from private.apply_costed_inventory_issue(
    v_balance.quantity_on_hand, v_balance.cost_basis_cents,
    v_item.quantity);
  new.cost_effect_cents := v_issue.cost_effect_cents;
  new.metadata := coalesce(new.metadata,'{}'::jsonb) ||
    jsonb_build_object('w5b_verified_sale_item_id',v_item.id);
  return new;
end;
$$;
create trigger trg_inventory_movements_q_w5b_prepare
  before insert on public.inventory_movements for each row
  execute function private.prepare_weight_sale_movement();
revoke all on function private.prepare_weight_sale_movement()
  from public, anon, authenticated, service_role;

-- The existing AFTER trigger has changed grams under the same row lock.
-- Finalize the exact W2B cost pool and immutable COGS in that transaction.
create function private.apply_weight_sale_cost_basis()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_balance public.product_stock_balances%rowtype;
  v_issue record;
  v_item_id uuid;
begin
  v_item_id := nullif(new.metadata->>'w5b_verified_sale_item_id','')::uuid;
  if v_item_id is null then return new; end if;
  select * into v_balance from public.product_stock_balances
    where business_id = new.business_id and branch_id = new.branch_id
      and product_id = new.product_id and deleted_at is null for update;
  select * into v_issue from private.apply_costed_inventory_issue(
    new.previous_stock, v_balance.cost_basis_cents,
    -new.quantity_change);
  if v_balance.quantity_on_hand is distinct from v_issue.quantity_after
     or new.cost_effect_cents is distinct from v_issue.cost_effect_cents then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_balance_cost_mismatch';
  end if;
  update public.product_stock_balances
    set cost_basis_cents = v_issue.cost_basis_after_cents,
        average_cost = case
          when v_issue.cost_basis_after_cents is null
            or v_issue.quantity_after = 0 then null
          else round(v_issue.cost_basis_after_cents::numeric /
            (100 * v_issue.quantity_after),2) end
    where id = v_balance.id;
  update public.sale_items set cogs_cents = v_issue.cogs_cents
    where id = v_item_id and cogs_cents is null;
  return new;
end;
$$;
create trigger trg_inventory_movements_z_w5b_cost_basis
  after insert on public.inventory_movements for each row
  execute function private.apply_weight_sale_cost_basis();
revoke all on function private.apply_weight_sale_cost_basis()
  from public, anon, authenticated, service_role;

-- Preserve the exact UNIT path. The weighted branch uses the same ledger,
-- source key and movement RPC, with W2B applied by the W5B triggers above.
create or replace function public.apply_sale_inventory_movements(
  p_sale_id uuid
) returns integer language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_sale public.sales%rowtype;
  v_item public.sale_items%rowtype;
  v_existing public.inventory_movements%rowtype;
  v_key text;
  v_count integer := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  select * into v_sale from public.sales where id = p_sale_id for update;
  if v_sale.id is null or v_sale.deleted_at is not null
     or v_sale.voided_at is not null or v_sale.branch_id is null
     or not private.has_branch_permission(v_sale.business_id,
       v_sale.branch_id,'sales.create') then
    raise exception using errcode = '42501',
      message = 'Sale inventory scope or permission invalid';
  end if;
  for v_item in select * from public.sale_items
    where sale_id = p_sale_id and deleted_at is null
      and product_id is not null and quantity > 0 order by id
  loop
    v_key := 'sale:' || p_sale_id::text || ':item:' || v_item.id::text;
    select * into v_existing from public.inventory_movements
      where business_id = v_sale.business_id and idempotency_key = v_key;
    if v_existing.id is not null then
      if v_item.sale_mode_snapshot = 'weight'
         and (v_existing.branch_id is distinct from v_sale.branch_id
           or v_existing.product_id is distinct from v_item.product_id
           or v_existing.quantity_change is distinct from -v_item.quantity
           or v_existing.cost_effect_cents is distinct from
             case when v_item.cogs_cents is null then null
               else -v_item.cogs_cents end) then
        raise exception using errcode = 'P0001',
          message = 'weighted_sale_movement_idempotency_conflict';
      end if;
      v_count := v_count + 1;
      continue;
    end if;
    perform public.create_inventory_movement(
      p_business_id := v_sale.business_id,
      p_branch_id := v_sale.branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'sale',
      p_quantity_change := -v_item.quantity,
      p_unit_cost := case when v_item.sale_mode_snapshot = 'weight'
        then null else v_item.unit_cost_snapshot end,
      p_source_type := 'sale', p_source_id := p_sale_id,
      p_reference_type := 'sale', p_reference_id := p_sale_id,
      p_notes := 'Inventory movement generated from sale',
      p_idempotency_key := v_key, p_occurred_at := now(),
      p_metadata := jsonb_build_object('sale_id',p_sale_id,
        'sale_item_id',v_item.id,
        'generated_by','apply_sale_inventory_movements'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create function private.validate_weight_sale_completion(p_batch_id uuid)
returns void language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_batch public.sync_batches%rowtype;
  v_sale_mutation public.sync_mutations%rowtype;
  v_sale public.sales%rowtype;
  v_item_count integer;
  v_payment_count integer;
  v_item_total bigint;
  v_payment_total bigint;
  v_expected_total bigint;
  v_expected_items integer;
  v_expected_payments integer;
begin
  select * into v_batch from public.sync_batches where id = p_batch_id;
  if v_batch.metadata->>'monetary_contract_version'
       is distinct from 'exact_weight_sale_v1' then return; end if;
  select * into v_sale_mutation from public.sync_mutations
    where sync_batch_id = p_batch_id and entity_table = 'sales'
      and operation = 'insert' and status = 'applied'
      and deleted_at is null;
  if v_sale_mutation.id is null or (select count(*) from public.sync_mutations
      where sync_batch_id = p_batch_id and entity_table = 'sales'
        and deleted_at is null) <> 1
     or v_sale_mutation.payload->>'total_cents' !~ '^[0-9]+$'
     or v_batch.metadata->>'item_count' !~ '^[1-9][0-9]*$'
     or v_batch.metadata->>'payment_count' !~ '^[1-9][0-9]*$' then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_completion_manifest_invalid';
  end if;
  v_expected_total := (v_sale_mutation.payload->>'total_cents')::bigint;
  v_expected_items := (v_batch.metadata->>'item_count')::integer;
  v_expected_payments := (v_batch.metadata->>'payment_count')::integer;
  select * into v_sale from public.sales
    where id = v_sale_mutation.entity_id and business_id = v_batch.business_id
      and branch_id = v_batch.branch_id and deleted_at is null for update;
  if v_sale.id is null or v_sale.status <> 'completed'
     or v_sale.total is distinct from v_expected_total::numeric / 100
     or v_sale_mutation.payload->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1' then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_completion_manifest_invalid';
  end if;
  select count(*), coalesce(sum(si.line_total_cents),0)
    into v_item_count,v_item_total from public.sale_items si
    where si.sale_id = v_sale.id and si.deleted_at is null;
  select count(*), coalesce(sum(sp.amount * 100),0)::bigint
    into v_payment_count,v_payment_total from public.sale_payments sp
    where sp.sale_id = v_sale.id and sp.deleted_at is null;
  if v_item_count <> v_expected_items or v_payment_count <> v_expected_payments
     or v_item_total <> v_expected_total
     or v_payment_total <> v_expected_total
     or (select count(*) from public.sale_items si
       where si.sale_id = v_sale.id and si.deleted_at is null
         and (si.line_total_cents is null or si.price_cents_snapshot is null
           or si.metadata->>'monetary_contract_version'
             is distinct from 'exact_weight_sale_v1')) <> 0
     or (select count(*) from public.sync_mutations sm
       where sm.sync_batch_id = p_batch_id and sm.entity_table = 'sale_items'
         and sm.status = 'applied' and sm.deleted_at is null
         and sm.payload->>'sale_id' = v_sale.id::text) <> v_expected_items
     or (select count(*) from public.sync_mutations sm
       where sm.sync_batch_id = p_batch_id and sm.entity_table = 'sale_payments'
         and sm.status = 'applied' and sm.deleted_at is null
         and sm.payload->>'sale_id' = v_sale.id::text) <> v_expected_payments
     or exists (select 1 from public.sync_mutations sm
       join public.sale_payments sp on sp.id = sm.entity_id
       where sm.sync_batch_id = p_batch_id and sm.entity_table = 'sale_payments'
         and (sm.payload->>'amount_cents' !~ '^[0-9]+$'
           or sp.amount is distinct from
             (sm.payload->>'amount_cents')::numeric / 100)) then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_money_not_complete';
  end if;
  if not exists (select 1 from public.sale_items si
      where si.sale_id = v_sale.id and si.sale_mode_snapshot = 'weight'
        and si.deleted_at is null) then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_missing_weight_item';
  end if;
end;
$$;
revoke all on function private.validate_weight_sale_completion(uuid)
  from public, anon, authenticated, service_role;
grant execute on function private.validate_weight_sale_completion(uuid)
  to service_role;

-- Same trigger, with strict completion for a W5B batch. The legacy UNIT
-- branch keeps its established partial-error reporting.
create or replace function private.apply_pos_inventory_after_sync_batch_completed()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_is_pos_batch boolean;
  v_is_weight_batch boolean;
  v_result jsonb;
begin
  if pg_trigger_depth() > 1 or new.direction is distinct from 'upload'
     or new.deleted_at is not null or new.status is distinct from 'completed'
     or old.status is not distinct from new.status then return new; end if;
  v_is_pos_batch := lower(coalesce(new.metadata->>'domain','')) = 'pos'
    or lower(coalesce(new.metadata->>'sync_domain','')) = 'pos'
    or lower(coalesce(new.metadata->>'batch_domain','')) = 'pos'
    or exists (select 1 from public.sync_mutations sm
      where sm.sync_batch_id = new.id and sm.deleted_at is null
        and sm.entity_table in ('sales','sale_items','sale_payments'));
  if not v_is_pos_batch then return new; end if;
  v_is_weight_batch := new.metadata->>'monetary_contract_version'
    = 'exact_weight_sale_v1';
  if v_is_weight_batch then
    perform private.validate_weight_sale_completion(new.id);
  end if;
  v_result := public.apply_pos_batch_inventory_movements(new.id);
  if v_is_weight_batch and (v_result->>'error_count')::integer <> 0 then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_inventory_not_complete';
  end if;
  update public.sync_batches sb set
    metadata = coalesce(sb.metadata,'{}'::jsonb) || jsonb_build_object(
      'pos_inventory_auto_apply',jsonb_build_object(
        'triggered_at',now(),'trigger_name',tg_name,'result',v_result)),
    updated_at = now() where sb.id = new.id;
  return new;
end;
$$;

-- Attach immutable authoritative results after the inventory trigger. This
-- metadata is part of the existing batch result, not a new transport.
create function private.attach_weight_sale_ack()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_ack jsonb;
  v_expected integer;
begin
  if new.status <> 'completed' or old.status is not distinct from new.status
     or new.direction <> 'upload'
     or new.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1' then return new; end if;
  select count(*) into v_expected from public.sync_mutations m
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'sale_items' and m.status = 'applied'
      and m.payload->>'sale_mode_snapshot' = 'weight';
  select jsonb_agg(jsonb_build_object(
    'sale_id',si.sale_id,'sale_item_id',si.id,
    'inventory_movement_id',im.id,
    'stock_quantity_grams',b.quantity_on_hand,
    'cost_basis_cents',b.cost_basis_cents,
    'cogs_cents',si.cogs_cents,
    'cost_effect_cents',im.cost_effect_cents,
    'mutation_status',m.status) order by si.id) into v_ack
    from public.sync_mutations m
    join public.sale_items si on si.id = m.entity_id
    join public.sales s on s.id = si.sale_id
    join public.inventory_movements im on im.business_id = si.business_id
      and im.idempotency_key = 'sale:' || si.sale_id::text
        || ':item:' || si.id::text
    join public.product_stock_balances b on b.business_id = si.business_id
      and b.branch_id = s.branch_id and b.product_id = si.product_id
      and b.deleted_at is null
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'sale_items' and m.status = 'applied'
      and si.sale_mode_snapshot = 'weight';
  if v_expected = 0 or coalesce(jsonb_array_length(v_ack),0) <> v_expected then
    raise exception using errcode = 'P0001',
      message = 'weighted_sale_ack_incomplete';
  end if;
  update public.sync_batches set metadata = metadata ||
    jsonb_build_object('weighted_sale_ack',v_ack) where id = new.id;
  return new;
end;
$$;
create trigger trg_sync_batches_zy_w5b_ack
  after update of status on public.sync_batches for each row
  execute function private.attach_weight_sale_ack();
revoke all on function private.attach_weight_sale_ack()
  from public, anon, authenticated, service_role;

-- A partial weighted apply may hold a sale item without inventory. Roll it
-- back, while preserving a stale-session rejection (no item was applied).
alter function public.process_sync_batch(uuid,text)
  rename to process_sync_batch_base_before_w5b;
revoke all on function public.process_sync_batch_base_before_w5b(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch_base_before_w5b(uuid,text)
  to service_role;
create function public.process_sync_batch(p_sync_batch_id uuid,
  p_mode text default 'validate_only') returns jsonb language plpgsql
security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_ack jsonb;
  v_weight_batch boolean;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  select metadata->>'monetary_contract_version' = 'exact_weight_sale_v1'
    into v_weight_batch from public.sync_batches
    where id = p_sync_batch_id;
  v_result := public.process_sync_batch_base_before_w5b(
    p_sync_batch_id,p_mode);
  if lower(trim(p_mode)) = 'apply_pos' and coalesce(v_weight_batch,false) then
    if v_result->>'status' <> 'completed' and exists (
      select 1 from public.sync_mutations m
      where m.sync_batch_id = p_sync_batch_id
        and m.entity_table = 'sale_items' and m.status = 'applied'
        and m.payload->>'monetary_contract_version' = 'exact_weight_sale_v1') then
      raise exception using errcode = 'P0001',
        message = 'weighted_sale_partial_apply_rolled_back';
    end if;
    select metadata->'weighted_sale_ack' into v_ack
      from public.sync_batches where id = p_sync_batch_id;
    if v_result->>'status' = 'completed' and v_ack is null then
      raise exception using errcode = 'P0001',
        message = 'weighted_sale_ack_missing';
    end if;
    if v_ack is not null then
      v_result := v_result || jsonb_build_object('weighted_sale_ack',v_ack);
    end if;
  end if;
  return v_result;
end;
$$;
revoke all on function public.process_sync_batch(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch(uuid,text)
  to authenticated, service_role;

-- Frontend capability negotiation: old Hosted has no such RPC and therefore
-- keeps the W5A guard closed. No mutation or data disclosure occurs here.
create function public.weighted_sale_sync_capability()
returns text language sql stable security invoker
set search_path = '' as $$
  select 'exact_weight_sale_v1'::text;
$$;
revoke all on function public.weighted_sale_sync_capability()
  from public, anon, authenticated, service_role;
grant execute on function public.weighted_sale_sync_capability()
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- W5B stale-sale reconciliation proof
--
-- A WEIGHT sale item may now have exactly one of two trusted provenances:
--
-- 1. Normal W5B upload:
--      w5b_verified_mutation_id
--
-- 2. Intentional stale-sale reconciliation:
--      w5b_stale_reconciliation_id
--      original_sync_mutation_id
--
-- The stale markers are NOT sufficient on their own. The trigger verifies the
-- reconciliation row, original batch, original sale mutation and original
-- sale-item mutation before accepting the item.
-- ---------------------------------------------------------------------------

create or replace function private.guard_unimplemented_weight_operation()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mode text;
  v_metadata jsonb := coalesce(new.metadata, '{}'::jsonb);
begin
  if new.product_id is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(new.product_id::text, 314159)
    );
  end if;

  select sale_mode
  into v_mode
  from public.products
  where id = new.product_id;

  if tg_table_name = 'inventory_movements' then
    if v_mode = 'weight'
       and not (
         v_metadata ? 'w4b_verified_purchase_item_id'
         or v_metadata ? 'w5b_verified_sale_item_id'
       )
    then
      raise exception using
        errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;

  elsif tg_table_name = 'purchase_items' then
    if (v_mode = 'weight' or new.sale_mode_snapshot = 'weight')
       and not (
         new.sale_mode_snapshot = 'weight'
         and v_metadata ? 'w4b_verified_mutation_id'
       )
    then
      raise exception using
        errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;

  elsif tg_table_name = 'sale_items' then
    if (v_mode = 'weight' or new.sale_mode_snapshot = 'weight')
       and not (
         v_mode = 'weight'
         and new.sale_mode_snapshot = 'weight'
         and (
           v_metadata ? 'w5b_verified_mutation_id'
           or (
             v_metadata ? 'w5b_stale_reconciliation_id'
             and v_metadata ? 'original_sync_mutation_id'
           )
         )
       )
    then
      raise exception using
        errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  end if;

  return new;
end;
$$;


create or replace function private.prepare_weight_sale_item()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mode text;
  v_mutation public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_reconciliation public.sale_reconciliations%rowtype;
  v_sale public.sales%rowtype;
  v_metadata jsonb := coalesce(new.metadata, '{}'::jsonb);
  v_normal_proof boolean := false;
  v_stale_proof boolean := false;
  v_expected bigint;
begin
  select sale_mode
  into v_mode
  from public.products
  where id = new.product_id
    and business_id = new.business_id
    and deleted_at is null;

  if v_mode is distinct from 'weight'
     and new.sale_mode_snapshot <> 'weight'
  then
    return new;
  end if;

  v_normal_proof := v_metadata ? 'w5b_verified_mutation_id';

  v_stale_proof :=
    v_metadata ? 'w5b_stale_reconciliation_id'
    and v_metadata ? 'original_sync_mutation_id';

  -- Exactly one proof route must be selected.
  if v_normal_proof = v_stale_proof then
    raise exception using
      errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;

  if tg_op = 'UPDATE' then
    if new.sale_id is distinct from old.sale_id
       or new.product_id is distinct from old.product_id
       or new.quantity is distinct from old.quantity
       or new.unit_price is distinct from old.unit_price
       or new.subtotal is distinct from old.subtotal
       or new.discount_amount is distinct from old.discount_amount
       or new.tax_amount is distinct from old.tax_amount
       or new.total is distinct from old.total
       or new.idempotency_key is distinct from old.idempotency_key
       or new.deleted_at is distinct from old.deleted_at
    then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_sale_item_immutable';
    end if;

    return new;
  end if;

  -- -----------------------------------------------------------------------
  -- Normal W5B sync proof.
  -- -----------------------------------------------------------------------
  if v_normal_proof then
    select *
    into v_mutation
    from public.sync_mutations
    where id =
        nullif(v_metadata ->> 'w5b_verified_mutation_id', '')::uuid
      and entity_table = 'sale_items'
      and operation = 'insert'
      and entity_id = new.id
      and business_id = new.business_id
      and idempotency_key = new.idempotency_key
      and status in ('pending', 'error', 'conflict', 'skipped')
      and deleted_at is null;

    select *
    into v_batch
    from public.sync_batches
    where id = v_mutation.sync_batch_id
      and status = 'processing'
      and business_id = new.business_id;

    if v_mode is distinct from 'weight'
       or new.sale_mode_snapshot is distinct from 'weight'
       or v_mutation.id is null
       or v_batch.id is null
       or v_mutation.branch_id is distinct from v_batch.branch_id
       or v_mutation.profile_id is distinct from v_batch.profile_id
       or v_mutation.app_device_id is distinct from v_batch.app_device_id
       or v_mutation.payload ->> 'monetary_contract_version'
            is distinct from 'exact_weight_sale_v1'
       or v_mutation.payload ->> 'sale_id'
            is distinct from new.sale_id::text
       or v_mutation.payload ->> 'product_id'
            is distinct from new.product_id::text
       or v_mutation.payload ->> 'quantity'
            is distinct from new.quantity::text
       or v_mutation.payload ->> 'price_cents_snapshot'
            is distinct from new.price_cents_snapshot::text
       or v_mutation.payload ->> 'line_total_cents'
            is distinct from new.line_total_cents::text
       or new.price_basis_quantity_snapshot <> 500
    then
      raise exception using
        errcode = 'P0001',
        message = 'invalid_weighted_sale_contract';
    end if;

    return new;
  end if;

  -- -----------------------------------------------------------------------
  -- Intentional stale-sale reconciliation proof.
  -- -----------------------------------------------------------------------
  select *
  into v_reconciliation
  from public.sale_reconciliations
  where id =
      nullif(v_metadata ->> 'w5b_stale_reconciliation_id', '')::uuid
    and deleted_at is null;

  select *
  into v_mutation
  from public.sync_mutations
  where id =
      nullif(v_metadata ->> 'original_sync_mutation_id', '')::uuid
    and deleted_at is null;

  select *
  into v_sale
  from public.sales
  where id = new.sale_id
    and deleted_at is null;

  if v_reconciliation.id is null
     or v_reconciliation.status is distinct from 'processing'
     or v_reconciliation.business_id is distinct from new.business_id
     or v_reconciliation.sale_id is distinct from new.sale_id
     or v_sale.id is null
     or v_sale.business_id is distinct from new.business_id
     or v_sale.branch_id is distinct from v_reconciliation.branch_id
     or v_sale.cash_session_id
          is distinct from v_reconciliation.destination_cash_session_id

     -- The item must be the exact original mutation from the rejected batch.
     or v_mutation.id is null
     or v_mutation.sync_batch_id
          is distinct from v_reconciliation.original_sync_batch_id
     or v_mutation.business_id is distinct from new.business_id
     or v_mutation.branch_id is distinct from v_reconciliation.branch_id
     or v_mutation.entity_table is distinct from 'sale_items'
     or v_mutation.operation is distinct from 'insert'
     or v_mutation.entity_id is distinct from new.id
     or v_mutation.idempotency_key is distinct from new.idempotency_key
     or v_mutation.app_device_id
          is distinct from v_reconciliation.original_app_device_id

     -- The reconciliation must itself point back to the original Sale
     -- mutation from the same batch.
     or not exists (
       select 1
       from public.sync_mutations sale_mutation
       where sale_mutation.id =
             v_reconciliation.original_sync_mutation_id
         and sale_mutation.sync_batch_id =
             v_reconciliation.original_sync_batch_id
         and sale_mutation.business_id = new.business_id
         and sale_mutation.branch_id is not distinct from
             v_reconciliation.branch_id
         and sale_mutation.entity_table = 'sales'
         and sale_mutation.entity_id = new.sale_id
         and sale_mutation.deleted_at is null
     )

     -- Exact WEIGHT contract from the original item mutation.
     or v_mode is distinct from 'weight'
     or new.sale_mode_snapshot is distinct from 'weight'
     or v_mutation.payload ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_mutation.payload ->> 'sale_mode_snapshot'
          is distinct from 'weight'
     or v_mutation.payload ->> 'sale_id'
          is distinct from new.sale_id::text
     or v_mutation.payload ->> 'product_id'
          is distinct from new.product_id::text
     or v_mutation.payload ->> 'quantity'
          is distinct from new.quantity::text
     or v_mutation.payload ->> 'price_basis_quantity_snapshot'
          is distinct from '500'
     or v_mutation.payload ->> 'price_cents_snapshot'
          is distinct from new.price_cents_snapshot::text
     or v_mutation.payload ->> 'line_total_cents'
          is distinct from new.line_total_cents::text
     or new.price_basis_quantity_snapshot <> 500
     or v_metadata ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or coalesce(new.discount_amount, 0) <> 0
     or coalesce(new.tax_amount, 0) <> 0
  then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_weighted_stale_reconciliation_contract';
  end if;

  v_expected := private.calculate_basis_amount_cents(
    new.price_cents_snapshot,
    new.quantity,
    new.price_basis_quantity_snapshot
  );

  if new.line_total_cents is distinct from v_expected
     or new.unit_price is distinct from
          new.price_cents_snapshot::numeric / 100
     or new.subtotal is distinct from
          v_expected::numeric / 100
     or new.total is distinct from
          new.line_total_cents::numeric / 100
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_sale_money_mismatch';
  end if;

  return new;
end;
$$;


create or replace function private.prepare_weight_sale_movement()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_product public.products%rowtype;
  v_item public.sale_items%rowtype;
  v_sale public.sales%rowtype;
  v_balance public.product_stock_balances%rowtype;
  v_issue record;
  v_normal_proof boolean := false;
  v_stale_proof boolean := false;
begin
  select *
  into v_product
  from public.products
  where id = new.product_id;

  if v_product.sale_mode is distinct from 'weight'
     or new.source_type is distinct from 'sale'
  then
    return new;
  end if;

  select *
  into v_item
  from public.sale_items
  where id = nullif(new.metadata ->> 'sale_item_id', '')::uuid;

  select *
  into v_sale
  from public.sales
  where id = v_item.sale_id;

  if v_item.id is not null then
    select exists (
      select 1
      from public.sync_mutations sm
      join public.sync_batches sb
        on sb.id = sm.sync_batch_id
      where sm.id =
            nullif(
              v_item.metadata ->> 'w5b_verified_mutation_id',
              ''
            )::uuid
        and sm.entity_id = v_item.id
        and sm.entity_table = 'sale_items'
        and sm.status = 'applied'
        and sb.status = 'completed'
        and sb.business_id = v_item.business_id
        and sb.branch_id = v_sale.branch_id
    )
    into v_normal_proof;

    select exists (
      select 1
      from public.sale_reconciliations reconciliation
      join public.sync_mutations item_mutation
        on item_mutation.id =
          nullif(
            v_item.metadata ->> 'original_sync_mutation_id',
            ''
          )::uuid
      join public.sync_mutations sale_mutation
        on sale_mutation.id = reconciliation.original_sync_mutation_id
      where reconciliation.id =
            nullif(
              v_item.metadata ->> 'w5b_stale_reconciliation_id',
              ''
            )::uuid
        and reconciliation.status = 'processing'
        and reconciliation.deleted_at is null

        and reconciliation.business_id = v_item.business_id
        and reconciliation.branch_id = v_sale.branch_id
        and reconciliation.sale_id = v_sale.id
        and reconciliation.destination_cash_session_id =
            v_sale.cash_session_id

        and item_mutation.sync_batch_id =
            reconciliation.original_sync_batch_id
        and item_mutation.business_id = v_item.business_id
        and item_mutation.branch_id is not distinct from v_sale.branch_id
        and item_mutation.entity_table = 'sale_items'
        and item_mutation.operation = 'insert'
        and item_mutation.entity_id = v_item.id
        and item_mutation.idempotency_key = v_item.idempotency_key
        and item_mutation.app_device_id =
            reconciliation.original_app_device_id
        and item_mutation.deleted_at is null

        and item_mutation.payload ->> 'monetary_contract_version'
            = 'exact_weight_sale_v1'
        and item_mutation.payload ->> 'sale_mode_snapshot' = 'weight'
        and item_mutation.payload ->> 'sale_id' = v_sale.id::text
        and item_mutation.payload ->> 'product_id' =
            v_item.product_id::text
        and item_mutation.payload ->> 'quantity' =
            v_item.quantity::text
        and item_mutation.payload ->> 'price_basis_quantity_snapshot' =
            '500'
        and item_mutation.payload ->> 'price_cents_snapshot' =
            v_item.price_cents_snapshot::text
        and item_mutation.payload ->> 'line_total_cents' =
            v_item.line_total_cents::text

        and sale_mutation.sync_batch_id =
            reconciliation.original_sync_batch_id
        and sale_mutation.business_id = v_item.business_id
        and sale_mutation.branch_id is not distinct from v_sale.branch_id
        and sale_mutation.entity_table = 'sales'
        and sale_mutation.entity_id = v_sale.id
        and sale_mutation.deleted_at is null
    )
    into v_stale_proof;
  end if;

  if v_item.id is null
     or v_item.sale_mode_snapshot <> 'weight'
     or v_item.price_basis_quantity_snapshot <> 500
     or v_item.metadata ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_item.deleted_at is not null
     or v_sale.id is null
     or v_sale.status <> 'completed'
     or v_sale.deleted_at is not null
     or v_sale.voided_at is not null
     or new.source_type is distinct from 'sale'
     or new.movement_type is distinct from 'sale'
     or new.business_id is distinct from v_item.business_id
     or new.branch_id is distinct from v_sale.branch_id
     or new.product_id is distinct from v_item.product_id
     or new.source_id is distinct from v_sale.id
     or new.quantity_change is distinct from -v_item.quantity
     or new.idempotency_key is distinct from
          (
            'sale:'
            || v_sale.id::text
            || ':item:'
            || v_item.id::text
          )
     or v_normal_proof = v_stale_proof
  then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_weighted_sale_movement';
  end if;

  select *
  into v_balance
  from public.product_stock_balances
  where business_id = new.business_id
    and branch_id = new.branch_id
    and product_id = new.product_id
    and deleted_at is null
  for update;

  if v_balance.id is null
     or v_balance.quantity_available < v_item.quantity
     or new.previous_stock is distinct from v_balance.quantity_on_hand
     or new.new_stock is distinct from
          v_balance.quantity_on_hand - v_item.quantity
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_sale_insufficient_available_stock';
  end if;

  select *
  into v_issue
  from private.apply_costed_inventory_issue(
    v_balance.quantity_on_hand,
    v_balance.cost_basis_cents,
    v_item.quantity
  );

  new.cost_effect_cents := v_issue.cost_effect_cents;

  new.metadata :=
    coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'w5b_verified_sale_item_id',
      v_item.id
    );

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- W5B intentional stale-sale WEIGHT reconciliation
--
-- Keep the historical reconciliation transaction intact. WEIGHT items are
-- upgraded to exact_weight_sale_v1 before the existing INSERT reaches the W5B
-- guards. The original client unit-cost snapshot may remain as historical
-- evidence on sale_items, but inventory COGS is always authoritative W2B.
-- ---------------------------------------------------------------------------

create function private.hydrate_stale_weight_sale_item()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mode text;
  v_reconciliation public.sale_reconciliations%rowtype;
  v_mutation public.sync_mutations%rowtype;
  v_payload jsonb;
  v_quantity integer;
  v_basis integer;
  v_price bigint;
  v_line_total bigint;
  v_expected bigint;
begin
  select sale_mode
  into v_mode
  from public.products
  where id = new.product_id
    and business_id = new.business_id
    and deleted_at is null;

  if v_mode is distinct from 'weight' then
    return new;
  end if;

  -- Normal W5B upload already has its own trusted proof and snapshots.
  if coalesce(new.metadata, '{}'::jsonb) ? 'w5b_verified_mutation_id' then
    return new;
  end if;

  -- The historical stale RPC already writes these two identifiers into the
  -- item metadata. A random marker without both values remains fail-closed.
  if not (
    coalesce(new.metadata, '{}'::jsonb) ? 'reconciliation_id'
    and coalesce(new.metadata, '{}'::jsonb) ? 'original_sync_mutation_id'
  ) then
    return new;
  end if;

  select *
  into v_reconciliation
  from public.sale_reconciliations
  where id = nullif(new.metadata ->> 'reconciliation_id', '')::uuid
    and deleted_at is null
  for update;

  select *
  into v_mutation
  from public.sync_mutations
  where id = nullif(new.metadata ->> 'original_sync_mutation_id', '')::uuid
    and deleted_at is null;

  if v_reconciliation.id is null
     or v_reconciliation.status is distinct from 'processing'
     or v_reconciliation.business_id is distinct from new.business_id
     or v_reconciliation.sale_id is distinct from new.sale_id
     or v_mutation.id is null
     or v_mutation.sync_batch_id
          is distinct from v_reconciliation.original_sync_batch_id
     or v_mutation.business_id is distinct from new.business_id
     or v_mutation.branch_id
          is distinct from v_reconciliation.branch_id
     or v_mutation.entity_table is distinct from 'sale_items'
     or v_mutation.operation is distinct from 'insert'
     or v_mutation.entity_id is distinct from new.id
     or v_mutation.idempotency_key is distinct from new.idempotency_key
     or v_mutation.app_device_id
          is distinct from v_reconciliation.original_app_device_id
  then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_weighted_stale_reconciliation_contract';
  end if;

  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  if nullif(v_payload ->> 'monetary_contract_version', '')
       is distinct from 'exact_weight_sale_v1'
     or nullif(v_payload ->> 'sale_mode_snapshot', '')
       is distinct from 'weight'
     or v_payload ->> 'sale_id' is distinct from new.sale_id::text
     or v_payload ->> 'product_id' is distinct from new.product_id::text
     or v_payload ->> 'quantity' !~ '^[1-9][0-9]*$'
     or v_payload ->> 'price_basis_quantity_snapshot' !~ '^[1-9][0-9]*$'
     or v_payload ->> 'price_cents_snapshot' !~ '^[0-9]+$'
     or v_payload ->> 'line_total_cents' !~ '^[0-9]+$'
  then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_weighted_stale_reconciliation_contract';
  end if;

  v_quantity := (v_payload ->> 'quantity')::integer;
  v_basis := (v_payload ->> 'price_basis_quantity_snapshot')::integer;
  v_price := (v_payload ->> 'price_cents_snapshot')::bigint;
  v_line_total := (v_payload ->> 'line_total_cents')::bigint;

  if v_basis <> 500
     or v_quantity <> new.quantity
     or coalesce(new.discount_amount, 0) <> 0
     or coalesce(new.tax_amount, 0) <> 0
  then
    raise exception using
      errcode = 'P0001',
      message = 'invalid_weighted_stale_reconciliation_contract';
  end if;

  v_expected := private.calculate_basis_amount_cents(
    v_price,
    v_quantity,
    v_basis
  );

  if v_expected <> v_line_total
     or new.unit_price is distinct from v_price::numeric / 100
     or new.subtotal is distinct from v_expected::numeric / 100
     or new.total is distinct from v_line_total::numeric / 100
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_sale_money_mismatch';
  end if;

  new.sale_mode_snapshot := 'weight';
  new.price_basis_quantity_snapshot := 500;
  new.price_cents_snapshot := v_price;
  new.line_total_cents := v_line_total;

  new.metadata :=
    coalesce(new.metadata, '{}'::jsonb)
    || jsonb_build_object(
      'w5b_stale_reconciliation_id',
      v_reconciliation.id,
      'monetary_contract_version',
      'exact_weight_sale_v1'
    );

  return new;
end;
$$;

create trigger trg_sale_items_00_w5b_stale_hydrate
  before insert on public.sale_items
  for each row
  execute function private.hydrate_stale_weight_sale_item();

revoke all on function private.hydrate_stale_weight_sale_item()
  from public, anon, authenticated, service_role;


-- The historical stale RPC passes the old unit_cost_snapshot to
-- create_inventory_movement(). For WEIGHT it must never become authoritative
-- movement cost. W2B below derives cost_effect_cents from the locked pool.
create function private.clear_weight_sale_movement_unit_cost()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mode text;
begin
  select sale_mode
  into v_mode
  from public.products
  where id = new.product_id
    and deleted_at is null;

  if v_mode = 'weight'
     and new.source_type = 'sale'
     and new.movement_type = 'sale'
  then
    new.unit_cost := null;
  end if;

  return new;
end;
$$;

create trigger trg_inventory_movements_p_w5b_clear_sale_unit_cost
  before insert on public.inventory_movements
  for each row
  execute function private.clear_weight_sale_movement_unit_cost();

revoke all on function private.clear_weight_sale_movement_unit_cost()
  from public, anon, authenticated, service_role;


-- Validate the materialized reconciliation against the immutable original
-- sync payload. This runs inside the same transaction as the historical RPC;
-- any mismatch rolls the complete reconciliation back.
create function private.validate_stale_weight_sale_reconciliation(
  p_reconciliation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_reconciliation public.sale_reconciliations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_sale_mutation public.sync_mutations%rowtype;
  v_sale public.sales%rowtype;
  v_mutation record;
  v_payload jsonb;
  v_product_mode text;
  v_mode text;
  v_quantity integer;
  v_basis integer;
  v_price bigint;
  v_line_total bigint;
  v_expected bigint;
  v_discount numeric;
  v_tax numeric;
  v_expected_total bigint;
  v_item_total bigint := 0;
  v_payment_total bigint := 0;
  v_item_count integer := 0;
  v_payment_count integer := 0;
  v_expected_items integer;
  v_expected_payments integer;
  v_has_weight boolean := false;
begin
  select *
  into v_reconciliation
  from public.sale_reconciliations
  where id = p_reconciliation_id
    and deleted_at is null;

  if v_reconciliation.id is null
     or v_reconciliation.status <> 'completed'
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_stale_reconciliation_incomplete';
  end if;

  select *
  into v_batch
  from public.sync_batches
  where id = v_reconciliation.original_sync_batch_id
    and deleted_at is null;

  select *
  into v_sale_mutation
  from public.sync_mutations
  where id = v_reconciliation.original_sync_mutation_id
    and deleted_at is null;

  select *
  into v_sale
  from public.sales
  where id = v_reconciliation.sale_id
    and deleted_at is null;

  if v_batch.id is null
     or v_sale_mutation.id is null
     or v_sale.id is null
     or v_batch.business_id is distinct from v_reconciliation.business_id
     or v_batch.branch_id is distinct from v_reconciliation.branch_id
     or v_sale_mutation.sync_batch_id is distinct from v_batch.id
     or v_sale_mutation.entity_table is distinct from 'sales'
     or v_sale_mutation.entity_id is distinct from v_sale.id
     or v_sale.business_id is distinct from v_reconciliation.business_id
     or v_sale.branch_id is distinct from v_reconciliation.branch_id
     or v_sale.cash_session_id
          is distinct from v_reconciliation.destination_cash_session_id
     or v_batch.metadata ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_sale_mutation.payload ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_sale_mutation.payload -> 'metadata'
          ->> 'monetary_contract_version'
          is distinct from 'exact_weight_sale_v1'
     or v_sale_mutation.payload ->> 'total_cents' !~ '^[0-9]+$'
     or v_batch.metadata ->> 'item_count' !~ '^[1-9][0-9]*$'
     or v_batch.metadata ->> 'payment_count' !~ '^[1-9][0-9]*$'
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_stale_reconciliation_manifest_invalid';
  end if;

  v_expected_total :=
    (v_sale_mutation.payload ->> 'total_cents')::bigint;
  v_expected_items :=
    (v_batch.metadata ->> 'item_count')::integer;
  v_expected_payments :=
    (v_batch.metadata ->> 'payment_count')::integer;

  if v_sale.total is distinct from v_expected_total::numeric / 100 then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_stale_reconciliation_money_mismatch';
  end if;

  for v_mutation in
    select mutation.*
    from public.sync_mutations mutation
    where mutation.sync_batch_id = v_batch.id
      and mutation.entity_table = 'sale_items'
      and mutation.payload ->> 'sale_id' = v_sale.id::text
      and mutation.deleted_at is null
    order by mutation.client_sequence, mutation.id
  loop
    v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

    if v_payload ->> 'monetary_contract_version'
         is distinct from 'exact_weight_sale_v1'
       or v_payload ->> 'sale_mode_snapshot'
         not in ('unit', 'weight')
       or v_payload ->> 'quantity' !~ '^[1-9][0-9]*$'
       or v_payload ->> 'price_basis_quantity_snapshot'
         !~ '^[1-9][0-9]*$'
       or v_payload ->> 'price_cents_snapshot' !~ '^[0-9]+$'
       or v_payload ->> 'line_total_cents' !~ '^[0-9]+$'
    then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_item_invalid';
    end if;

    v_mode := v_payload ->> 'sale_mode_snapshot';
    v_quantity := (v_payload ->> 'quantity')::integer;
    v_basis := (v_payload ->> 'price_basis_quantity_snapshot')::integer;
    v_price := (v_payload ->> 'price_cents_snapshot')::bigint;
    v_line_total := (v_payload ->> 'line_total_cents')::bigint;
    v_discount :=
      coalesce(nullif(v_payload ->> 'discount_amount', '')::numeric, 0);
    v_tax :=
      coalesce(nullif(v_payload ->> 'tax_amount', '')::numeric, 0);

    select sale_mode
    into v_product_mode
    from public.products
    where id = nullif(v_payload ->> 'product_id', '')::uuid
      and business_id = v_reconciliation.business_id
      and deleted_at is null;

    if v_product_mode is distinct from v_mode
       or (v_mode = 'weight' and (
         v_basis <> 500
         or v_discount <> 0
         or v_tax <> 0
       ))
       or (v_mode = 'unit' and v_basis <> 1)
       or v_discount < 0
       or v_tax < 0
       or v_discount * 100 <> trunc(v_discount * 100)
       or v_tax * 100 <> trunc(v_tax * 100)
    then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_item_invalid';
    end if;

    v_expected := private.calculate_basis_amount_cents(
      v_price,
      v_quantity,
      v_basis
    );

    if v_expected - (v_discount * 100)::bigint
         + (v_tax * 100)::bigint <> v_line_total
    then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_money_mismatch';
    end if;

    if not exists (
      select 1
      from public.sale_items item
      where item.id = v_mutation.entity_id
        and item.business_id = v_reconciliation.business_id
        and item.sale_id = v_sale.id
        and item.product_id =
            nullif(v_payload ->> 'product_id', '')::uuid
        and item.quantity = v_quantity
        and item.unit_price = v_price::numeric / 100
        and item.subtotal = v_expected::numeric / 100
        and item.discount_amount = v_discount
        and item.tax_amount = v_tax
        and item.total = v_line_total::numeric / 100
        and item.idempotency_key = v_mutation.idempotency_key
        and item.deleted_at is null
        and (
          v_mode <> 'weight'
          or (
            item.sale_mode_snapshot = 'weight'
            and item.price_basis_quantity_snapshot = 500
            and item.price_cents_snapshot = v_price
            and item.line_total_cents = v_line_total
            and item.metadata ->> 'monetary_contract_version'
                = 'exact_weight_sale_v1'
            and item.metadata ->> 'w5b_stale_reconciliation_id'
                = v_reconciliation.id::text
            and item.metadata ->> 'original_sync_mutation_id'
                = v_mutation.id::text
          )
        )
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_projection_mismatch';
    end if;

    if v_mode = 'weight' then
      v_has_weight := true;

      if not exists (
        select 1
        from public.sale_items item
        join public.inventory_movements movement
          on movement.business_id = item.business_id
         and movement.idempotency_key =
             'sale:' || item.sale_id::text
             || ':item:' || item.id::text
        where item.id = v_mutation.entity_id
          and movement.branch_id = v_reconciliation.branch_id
          and movement.product_id = item.product_id
          and movement.source_type = 'sale'
          and movement.source_id = item.sale_id
          and movement.movement_type = 'sale'
          and movement.quantity_change = -item.quantity
          and movement.unit_cost is null
          and (
            (
              item.cogs_cents is null
              and movement.cost_effect_cents is null
            )
            or movement.cost_effect_cents = -item.cogs_cents
          )
      ) then
        raise exception using
          errcode = 'P0001',
          message = 'weighted_stale_reconciliation_inventory_mismatch';
      end if;
    end if;

    v_item_total := v_item_total + v_line_total;
    v_item_count := v_item_count + 1;
  end loop;

  for v_mutation in
    select mutation.*
    from public.sync_mutations mutation
    where mutation.sync_batch_id = v_batch.id
      and mutation.entity_table = 'sale_payments'
      and mutation.payload ->> 'sale_id' = v_sale.id::text
      and mutation.deleted_at is null
    order by mutation.client_sequence, mutation.id
  loop
    v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

    if v_payload ->> 'amount_cents' !~ '^[0-9]+$' then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_payment_invalid';
    end if;

    v_line_total := (v_payload ->> 'amount_cents')::bigint;

    if not exists (
      select 1
      from public.sale_payments payment
      where payment.id = v_mutation.entity_id
        and payment.business_id = v_reconciliation.business_id
        and payment.sale_id = v_sale.id
        and payment.amount = v_line_total::numeric / 100
        and payment.deleted_at is null
    ) then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_payment_invalid';
    end if;

    v_payment_total := v_payment_total + v_line_total;
    v_payment_count := v_payment_count + 1;
  end loop;

  if not v_has_weight
     or v_item_count <> v_expected_items
     or v_payment_count <> v_expected_payments
     or v_item_total <> v_expected_total
     or v_payment_total <> v_expected_total
  then
    raise exception using
      errcode = 'P0001',
      message = 'weighted_stale_reconciliation_manifest_invalid';
  end if;
end;
$$;

revoke all on function private.validate_stale_weight_sale_reconciliation(uuid)
  from public, anon, authenticated, service_role;


-- Preserve the historical RPC as the transactional implementation. Its
-- advisory locks, conflict validation, cash treatment, superseding of original
-- mutations and completed-retry behavior remain unchanged.
alter function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
rename to reconcile_rejected_sale_to_open_cash_session_pre_w5b;

revoke all on function public.reconcile_rejected_sale_to_open_cash_session_pre_w5b(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
from public, anon, authenticated, service_role;


create function public.reconcile_rejected_sale_to_open_cash_session(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_sale_id uuid,
  p_sync_conflict_id uuid,
  p_destination_cash_session_id uuid,
  p_reconciliation_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_cash_treatment text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_result jsonb;
  v_reconciliation public.sale_reconciliations%rowtype;
  v_has_weight boolean;
  v_weight_results jsonb;
  v_expected_weight_count integer;
begin
  v_result :=
    public.reconcile_rejected_sale_to_open_cash_session_pre_w5b(
      p_business_id,
      p_branch_id,
      p_app_device_id,
      p_sale_id,
      p_sync_conflict_id,
      p_destination_cash_session_id,
      p_reconciliation_id,
      p_idempotency_key,
      p_reason,
      p_cash_treatment
    );

  select exists (
    select 1
    from public.sale_items item
    where item.business_id = p_business_id
      and item.sale_id = p_sale_id
      and item.sale_mode_snapshot = 'weight'
      and item.deleted_at is null
  )
  into v_has_weight;

  if not coalesce(v_has_weight, false) then
    return v_result;
  end if;

  perform private.validate_stale_weight_sale_reconciliation(
    p_reconciliation_id
  );

  select *
  into v_reconciliation
  from public.sale_reconciliations
  where id = p_reconciliation_id
    and business_id = p_business_id
    and sale_id = p_sale_id
    and deleted_at is null
  for update;

  v_weight_results :=
    v_reconciliation.metadata -> 'weighted_sale_reconciliation_results';

  if v_weight_results is null then
    select count(*)
    into v_expected_weight_count
    from public.sale_items item
    where item.business_id = p_business_id
      and item.sale_id = p_sale_id
      and item.sale_mode_snapshot = 'weight'
      and item.deleted_at is null;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'sale_id', item.sale_id,
          'sale_item_id', item.id,
          'product_id', item.product_id,
          'quantity_grams', item.quantity,
          'inventory_movement_id', movement.id,
          'stock_quantity_grams', balance.quantity_on_hand,
          'cost_basis_cents', balance.cost_basis_cents,
          'cogs_cents', item.cogs_cents,
          'cost_effect_cents', movement.cost_effect_cents,
          'original_sync_mutation_id',
            item.metadata ->> 'original_sync_mutation_id',
          'original_mutation_status', 'skipped',
          'original_mutation_error_code',
            'superseded_by_sale_reconciliation'
        )
        order by item.id
      ),
      '[]'::jsonb
    )
    into v_weight_results
    from public.sale_items item
    join public.sales sale
      on sale.id = item.sale_id
    join public.inventory_movements movement
      on movement.business_id = item.business_id
     and movement.idempotency_key =
         'sale:' || item.sale_id::text || ':item:' || item.id::text
    join public.product_stock_balances balance
      on balance.business_id = item.business_id
     and balance.branch_id = sale.branch_id
     and balance.product_id = item.product_id
     and balance.deleted_at is null
    where item.business_id = p_business_id
      and item.sale_id = p_sale_id
      and item.sale_mode_snapshot = 'weight'
      and item.deleted_at is null;

    if coalesce(jsonb_array_length(v_weight_results), 0)
         <> v_expected_weight_count
    then
      raise exception using
        errcode = 'P0001',
        message = 'weighted_stale_reconciliation_result_incomplete';
    end if;

    update public.sale_reconciliations
    set metadata =
          coalesce(metadata, '{}'::jsonb)
          || jsonb_build_object(
            'weighted_sale_reconciliation_results',
            v_weight_results,
            'weighted_sale_contract_version',
            'exact_weight_sale_v1'
          ),
        updated_at = statement_timestamp()
    where id = p_reconciliation_id;
  end if;

  return v_result
    || jsonb_build_object(
      'weighted_sale_reconciliation_results',
      v_weight_results
    );
end;
$$;

comment on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
is 'Reconciles an intentional stale Sale, including exact WEIGHT items with authoritative W2B COGS/cost-basis results.';

revoke all on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
from public;

grant execute on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
to authenticated, service_role;

commit;
