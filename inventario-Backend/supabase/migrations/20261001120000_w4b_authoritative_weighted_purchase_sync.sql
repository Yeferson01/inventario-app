begin;

-- W4B: a weighted item is accepted only while its exact registered mutation is
-- being processed. This trigger runs before the older WEIGHT fail-closed guard.
create function private.prepare_weight_purchase_item()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
  v_mutation public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_purchase public.purchases%rowtype;
  v_quote bigint;
  v_subtotal bigint;
  v_basis integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(new.product_id::text, 314159));
  select sale_mode into v_mode from public.products
    where id = new.product_id and business_id = new.business_id
      and deleted_at is null;
  if v_mode is distinct from 'weight' and new.sale_mode_snapshot <> 'weight'
     and (tg_op = 'INSERT' or old.sale_mode_snapshot <> 'weight') then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.purchase_id is distinct from old.purchase_id
       or new.business_id is distinct from old.business_id
       or new.branch_id is distinct from old.branch_id
       or new.product_id is distinct from old.product_id
       or new.quantity is distinct from old.quantity
       or new.unit_cost is distinct from old.unit_cost
       or new.subtotal is distinct from old.subtotal
       or new.unit_cost_cents is distinct from old.unit_cost_cents
       or new.subtotal_cents is distinct from old.subtotal_cents
       or new.sale_mode_snapshot is distinct from old.sale_mode_snapshot
       or new.cost_basis_quantity_snapshot is distinct from old.cost_basis_quantity_snapshot
       or new.idempotency_key is distinct from old.idempotency_key
       or new.monetary_contract_version is distinct from old.monetary_contract_version
       or new.metadata->>'unit_cost_cents' is distinct from old.metadata->>'unit_cost_cents'
       or new.metadata->>'subtotal_cents' is distinct from old.metadata->>'subtotal_cents'
       or new.deleted_at is distinct from old.deleted_at then
      raise exception using errcode = 'P0001',
        message = 'weighted_purchase_item_immutable';
    end if;
    return new;
  end if;
  select * into v_purchase from public.purchases
    where id = new.purchase_id for update;
  select * into v_mutation from public.sync_mutations
    where entity_table = 'purchase_items' and entity_id = new.id
      and business_id = new.business_id and deleted_at is null
      and operation = 'insert' and status in ('pending', 'error', 'conflict', 'skipped')
      and idempotency_key = new.idempotency_key
    order by created_at desc limit 1;
  if found then
    select * into v_batch from public.sync_batches
      where id = v_mutation.sync_batch_id and status = 'processing'
        and deleted_at is null;
  end if;
  if v_mutation.id is null then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  if v_mode is distinct from 'weight' or v_purchase.id is null
     or v_purchase.business_id is distinct from new.business_id
     or v_purchase.branch_id is distinct from new.branch_id
     or v_purchase.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_basis_v1'
     or v_mutation.id is null or v_batch.id is null
     or v_mutation.branch_id is distinct from new.branch_id
     or v_batch.business_id is distinct from new.business_id
     or v_batch.branch_id is distinct from new.branch_id
     or v_batch.app_device_id is distinct from v_mutation.app_device_id
     or v_batch.profile_id is distinct from v_mutation.profile_id
     or v_mutation.payload->>'contract_version'
          is distinct from 'weighted_purchase_v1'
     or v_mutation.payload->>'sale_mode' is distinct from 'weight'
     or v_mutation.payload->>'sale_mode_snapshot' is distinct from 'weight'
     or v_mutation.payload->>'purchase_id' is distinct from new.purchase_id::text
     or v_mutation.payload->>'product_id' is distinct from new.product_id::text
     or v_mutation.payload->>'quantity' !~ '^[1-9][0-9]*$'
     or v_mutation.payload->>'cost_basis_quantity' not in ('500', '1000')
     or v_mutation.payload->>'cost_basis_quantity_snapshot'
          is distinct from v_mutation.payload->>'cost_basis_quantity'
     or v_mutation.payload->>'unit_cost_cents' !~ '^[0-9]+$'
     or v_mutation.payload->>'subtotal_cents' !~ '^[0-9]+$' then
    raise exception using errcode = 'P0001',
      message = 'invalid_weighted_purchase_contract';
  end if;
  v_basis := (v_mutation.payload->>'cost_basis_quantity')::integer;
  v_quote := (v_mutation.payload->>'unit_cost_cents')::bigint;
  v_subtotal := (v_mutation.payload->>'subtotal_cents')::bigint;
  if v_quote > 999999999999 or v_subtotal > 999999999999
     or new.quantity is distinct from (v_mutation.payload->>'quantity')::integer
     or v_subtotal is distinct from private.calculate_basis_amount_cents(
        v_quote, new.quantity, v_basis)
     or new.unit_cost is distinct from v_quote::numeric / 100
     or new.subtotal is distinct from v_subtotal::numeric / 100
     or new.metadata->>'unit_cost_cents' is distinct from v_quote::text
     or new.metadata->>'subtotal_cents' is distinct from v_subtotal::text
     or new.metadata->>'sale_mode_snapshot' is distinct from 'weight'
     or new.metadata->>'cost_basis_quantity_snapshot' is distinct from v_basis::text
  then
    raise exception using errcode = 'P0001',
      message = 'weighted_purchase_money_mismatch';
  end if;
  new.sale_mode_snapshot := 'weight';
  new.cost_basis_quantity_snapshot := v_basis;
  new.metadata := new.metadata || jsonb_build_object(
    'w4b_verified_mutation_id', v_mutation.id);
  return new;
end;
$$;
create trigger trg_purchase_items_a_w4b_prepare
  before insert or update
  on public.purchase_items for each row
  execute function private.prepare_weight_purchase_item();

-- Legacy UNIT rows retain their old multiplication default. A gram receipt
-- has an exact quoted basis and must not be multiplied as 10,000 units.
create or replace function private.fill_purchase_item_defaults()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
begin
  new.quantity := coalesce(new.quantity, 1);
  new.unit_cost := coalesce(new.unit_cost, 0);
  new.subtotal := coalesce(new.subtotal, new.quantity * new.unit_cost);
  if new.sale_mode_snapshot = 'unit'
     and new.subtotal <> new.quantity * new.unit_cost then
    new.subtotal := new.quantity * new.unit_cost;
  end if;
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.version := greatest(coalesce(new.version, 1), 1);
  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Keep the W1/W3 guard for POS and for every non-versioned WEIGHT movement.
create or replace function private.guard_unimplemented_weight_operation()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
begin
  if new.product_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(new.product_id::text, 314159));
  end if;
  select sale_mode into v_mode from public.products where id = new.product_id;
  if tg_table_name = 'inventory_movements' then
    if v_mode = 'weight' then
      if new.metadata ? 'w4b_verified_purchase_item_id' then return new; end if;
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  elsif tg_table_name = 'purchase_items' then
    if v_mode = 'weight' or new.sale_mode_snapshot = 'weight' then
      if new.sale_mode_snapshot = 'weight'
         and new.metadata ? 'w4b_verified_mutation_id' then return new; end if;
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  elsif tg_table_name = 'sale_items' and
        (v_mode = 'weight' or new.sale_mode_snapshot = 'weight') then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  return new;
end;
$$;

alter table public.purchase_items drop constraint purchase_items_exact_cents;
alter table public.purchase_items add constraint purchase_items_exact_cents
  check ((unit_cost_cents is null and subtotal_cents is null) or
    (unit_cost_cents between 0 and 999999999999 and
     subtotal_cents between 0 and 999999999999 and
     ((sale_mode_snapshot = 'unit' and
       (subtotal_cents = unit_cost_cents * quantity or
        monetary_contract_version = 'legacy_stored')) or
      (sale_mode_snapshot = 'weight' and
       monetary_contract_version = 'exact_weight_basis_v1' and
       subtotal_cents = private.calculate_basis_amount_cents(
         unit_cost_cents, quantity, cost_basis_quantity_snapshot)))));

create or replace function private.guard_exact_purchase_item()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_purchase public.purchases%rowtype;
  v_unit bigint;
  v_subtotal bigint;
  v_contract text;
begin
  if tg_op = 'DELETE' then
    select * into v_purchase from public.purchases where id = old.purchase_id for update;
    if v_purchase.financial_finalized_at is not null then
      raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and new.purchase_id is distinct from old.purchase_id
     and exists (select 1 from public.purchases p where p.id = old.purchase_id
       and p.financial_finalized_at is not null) then
    raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
  end if;
  select * into v_purchase from public.purchases where id = new.purchase_id for update;
  if v_purchase.financial_finalized_at is not null then
    if tg_op = 'INSERT' or new.purchase_id is distinct from old.purchase_id
       or new.product_id is distinct from old.product_id
       or new.quantity is distinct from old.quantity
       or new.unit_cost is distinct from old.unit_cost
       or new.subtotal is distinct from old.subtotal
       or new.unit_cost_cents is distinct from old.unit_cost_cents
       or new.subtotal_cents is distinct from old.subtotal_cents
       or new.sale_mode_snapshot is distinct from old.sale_mode_snapshot
       or new.cost_basis_quantity_snapshot is distinct from old.cost_basis_quantity_snapshot
       or new.monetary_contract_version is distinct from old.monetary_contract_version
       or new.deleted_at is distinct from old.deleted_at then
      raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
    end if;
    return new;
  end if;
  v_contract := v_purchase.metadata->>'monetary_contract_version';
  if v_contract in ('exact_v1', 'exact_weight_basis_v1') then
    if coalesce(new.metadata->>'unit_cost_cents', '') !~ '^[0-9]+$'
       or coalesce(new.metadata->>'subtotal_cents', '') !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001', message = 'missing_exact_purchase_item_money';
    end if;
    v_unit := (new.metadata->>'unit_cost_cents')::bigint;
    v_subtotal := (new.metadata->>'subtotal_cents')::bigint;
    if v_unit > 999999999999 or v_subtotal > 999999999999
       or (new.sale_mode_snapshot = 'weight' and
         (v_contract <> 'exact_weight_basis_v1' or
          v_subtotal <> private.calculate_basis_amount_cents(
            v_unit, new.quantity, new.cost_basis_quantity_snapshot)))
       or (new.sale_mode_snapshot = 'unit' and v_subtotal <> v_unit * new.quantity)
       or new.unit_cost is distinct from v_unit::numeric / 100
       or new.subtotal is distinct from v_subtotal::numeric / 100 then
      raise exception using errcode = 'P0001', message = 'purchase_item_money_mismatch';
    end if;
    new.unit_cost_cents := v_unit;
    new.subtotal_cents := v_subtotal;
    new.monetary_contract_version := case when new.sale_mode_snapshot = 'weight'
      then 'exact_weight_basis_v1' else 'exact_v1' end;
  else
    new.unit_cost_cents := (new.unit_cost * 100)::bigint;
    new.subtotal_cents := (new.subtotal * 100)::bigint;
    new.monetary_contract_version := 'legacy_stored';
  end if;
  return new;
end;
$$;

-- Existing processor remains the canonical UNIT path; only versioned WEIGHT
-- inserts are handled here. D05S restrictions carry over to the renamed base.
alter function private.apply_sync_purchase_mutation(uuid)
  rename to apply_sync_purchase_mutation_base_before_w4b;
revoke all on function private.apply_sync_purchase_mutation_base_before_w4b(uuid)
  from public, anon, authenticated;
create function private.apply_sync_purchase_mutation(p_sync_mutation_id uuid)
returns void language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mutation public.sync_mutations%rowtype;
  v_item public.purchase_items%rowtype;
  v_parent public.purchases%rowtype;
  v_product public.products%rowtype;
  v_basis integer;
  v_quote bigint;
  v_subtotal bigint;
begin
  select * into v_mutation from public.sync_mutations
    where id = p_sync_mutation_id and deleted_at is null;
  if v_mutation.entity_table <> 'purchase_items' or
     coalesce(v_mutation.payload->>'sale_mode',
              v_mutation.payload->>'sale_mode_snapshot', '') <> 'weight' then
    perform private.apply_sync_purchase_mutation_base_before_w4b(p_sync_mutation_id);
    return;
  end if;
  if v_mutation.operation <> 'insert' or v_mutation.payload->>'contract_version'
       is distinct from 'weighted_purchase_v1'
     or v_mutation.payload->>'sale_mode_snapshot' is distinct from 'weight'
     or v_mutation.payload->>'quantity' !~ '^[1-9][0-9]*$'
     or v_mutation.payload->>'cost_basis_quantity' not in ('500','1000')
     or v_mutation.payload->>'cost_basis_quantity_snapshot'
          is distinct from v_mutation.payload->>'cost_basis_quantity'
     or v_mutation.payload->>'unit_cost_cents' !~ '^[0-9]+$'
     or v_mutation.payload->>'subtotal_cents' !~ '^[0-9]+$' then
    raise exception using errcode = 'P0001',
      message = 'invalid_weighted_purchase_contract';
  end if;
  v_basis := (v_mutation.payload->>'cost_basis_quantity')::integer;
  v_quote := (v_mutation.payload->>'unit_cost_cents')::bigint;
  v_subtotal := (v_mutation.payload->>'subtotal_cents')::bigint;
  if v_quote > 999999999999 or v_subtotal > 999999999999 or
     v_subtotal <> private.calculate_basis_amount_cents(v_quote,
       (v_mutation.payload->>'quantity')::bigint, v_basis) or
     (v_mutation.payload->>'unit_cost')::numeric is distinct from v_quote::numeric / 100 or
     (v_mutation.payload->>'subtotal')::numeric is distinct from v_subtotal::numeric / 100 then
    raise exception using errcode = 'P0001',
      message = 'weighted_purchase_money_mismatch';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    (v_mutation.payload->>'product_id'), 314159));
  select * into v_product from public.products
    where id = (v_mutation.payload->>'product_id')::uuid
      and business_id = v_mutation.business_id and deleted_at is null;
  select * into v_parent from public.purchases
    where id = (v_mutation.payload->>'purchase_id')::uuid for update;
  if v_product.id is null or v_product.sale_mode <> 'weight'
     or v_parent.id is null or v_parent.deleted_at is not null
     or v_parent.business_id is distinct from v_mutation.business_id
     or v_parent.branch_id is distinct from v_mutation.branch_id
     or v_parent.metadata->>'monetary_contract_version'
          is distinct from 'exact_weight_basis_v1' then
    raise exception using errcode = 'P0001', message = 'weighted_purchase_scope_mismatch';
  end if;
  select * into v_item from public.purchase_items
    where id = v_mutation.entity_id for update;
  if v_item.id is not null then
    if v_item.business_id is distinct from v_mutation.business_id
       or v_item.branch_id is distinct from v_mutation.branch_id
       or v_item.purchase_id is distinct from v_parent.id
       or v_item.product_id is distinct from v_product.id
       or v_item.quantity is distinct from (v_mutation.payload->>'quantity')::integer
       or v_item.sale_mode_snapshot <> 'weight'
       or v_item.cost_basis_quantity_snapshot is distinct from v_basis
       or v_item.unit_cost_cents is distinct from v_quote
       or v_item.subtotal_cents is distinct from v_subtotal
       or v_item.idempotency_key is distinct from v_mutation.idempotency_key
       or v_item.deleted_at is not null then
      raise exception using errcode = 'P0001',
        message = 'weighted_purchase_idempotency_conflict';
    end if;
    perform private.mark_sync_mutation_applied(v_mutation.id, v_item.version);
    return;
  end if;
  insert into public.purchase_items (id, business_id, branch_id, purchase_id,
    product_id, quantity, unit_cost, subtotal, idempotency_key, sync_status,
    created_by, updated_by, metadata)
  values (v_mutation.entity_id, v_mutation.business_id, v_mutation.branch_id,
    v_parent.id, v_product.id, (v_mutation.payload->>'quantity')::integer,
    v_quote::numeric / 100, v_subtotal::numeric / 100,
    v_mutation.idempotency_key, 'synced', v_mutation.profile_id,
    v_mutation.profile_id, v_mutation.payload->'metadata')
  returning * into v_item;
  perform private.mark_sync_mutation_applied(v_mutation.id, v_item.version);
end;
$$;
revoke all on function private.apply_sync_purchase_mutation(uuid)
  from public, anon, authenticated;
grant execute on function private.apply_sync_purchase_mutation(uuid) to service_role;

-- This trigger authenticates the canonical purchase-item-derived movement.
-- Every other WEIGHT movement still fails closed under W1/W3.
create function private.prepare_weight_purchase_movement()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
  v_item public.purchase_items%rowtype;
  v_purchase public.purchases%rowtype;
begin
  select sale_mode into v_mode from public.products where id = new.product_id;
  if v_mode is distinct from 'weight' then return new; end if;
  select * into v_item from public.purchase_items
    where id = nullif(new.metadata->>'purchase_item_id', '')::uuid;
  if v_item.id is null then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  select * into v_purchase from public.purchases where id = v_item.purchase_id;
  if new.source_type is distinct from 'purchase'
     or new.movement_type is distinct from 'purchase'
     or v_item.id is null or v_item.sale_mode_snapshot <> 'weight'
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
  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
    'w4b_verified_purchase_item_id', v_item.id);
  return new;
end;
$$;
create trigger trg_inventory_movements_a_w4b_prepare
  before insert on public.inventory_movements for each row
  execute function private.prepare_weight_purchase_movement();

-- The existing movement trigger holds this row FOR UPDATE and updates stock.
-- This subsequent trigger uses the same lock and W2B for the exact cost pool.
create function private.apply_weight_purchase_cost_basis()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_balance public.product_stock_balances%rowtype;
  v_receipt record;
begin
  if not (new.metadata ? 'w4b_verified_purchase_item_id') then return new; end if;
  select * into v_balance from public.product_stock_balances
    where business_id = new.business_id and branch_id = new.branch_id
      and product_id = new.product_id and deleted_at is null for update;
  select * into v_receipt from private.apply_costed_inventory_receipt(
    new.previous_stock, v_balance.cost_basis_cents,
    new.quantity_change, new.cost_effect_cents);
  if v_balance.quantity_on_hand is distinct from v_receipt.quantity_after then
    raise exception using errcode = 'P0001',
      message = 'weighted_purchase_balance_quantity_mismatch';
  end if;
  update public.product_stock_balances
    set cost_basis_cents = v_receipt.cost_basis_after_cents,
        average_cost = case when v_receipt.cost_basis_after_cents is null
          then null else round(v_receipt.cost_basis_after_cents::numeric /
            (100 * v_receipt.quantity_after), 2) end
    where id = v_balance.id;
  return new;
end;
$$;
create trigger trg_inventory_movements_z_w4b_cost_basis
  after insert on public.inventory_movements for each row
  execute function private.apply_weight_purchase_cost_basis();

-- Preserve the UNIT call path and its movement key. Weighted unit_cost is
-- informational per gram; exact valuation comes from the item snapshot.
create or replace function public.apply_purchase_inventory_movements(
  p_purchase_id uuid) returns integer language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_purchase public.purchases%rowtype;
  v_item public.purchase_items%rowtype;
  v_key text;
  v_existing public.inventory_movements%rowtype;
  v_count integer := 0;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  select * into v_purchase from public.purchases
    where id = p_purchase_id for update;
  if v_purchase.id is null or v_purchase.deleted_at is not null
     or v_purchase.branch_id is null
     or not private.has_branch_permission(v_purchase.business_id,
       v_purchase.branch_id, 'inventory.purchase') then
    raise exception using errcode = '42501',
      message = 'Purchase inventory scope or permission invalid';
  end if;
  for v_item in select * from public.purchase_items
    where purchase_id = p_purchase_id
      and product_id is not null and quantity > 0 order by id
  loop
    v_key := 'purchase:' || p_purchase_id::text || ':item:' || v_item.id::text;
    select * into v_existing from public.inventory_movements
      where business_id = v_purchase.business_id and idempotency_key = v_key;
    if found then
      if v_item.sale_mode_snapshot = 'weight' and
         (v_existing.branch_id is distinct from v_purchase.branch_id
          or v_existing.product_id is distinct from v_item.product_id
          or v_existing.quantity_change is distinct from v_item.quantity
          or v_existing.cost_effect_cents is distinct from v_item.subtotal_cents) then
        raise exception using errcode = 'P0001',
          message = 'weighted_purchase_movement_idempotency_conflict';
      end if;
      v_count := v_count + 1;
      continue;
    end if;
    perform public.create_inventory_movement(
      p_business_id := v_purchase.business_id,
      p_branch_id := v_purchase.branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'purchase',
      p_quantity_change := v_item.quantity,
      p_unit_cost := case when v_item.sale_mode_snapshot = 'weight'
        then v_item.subtotal_cents::numeric / (100 * v_item.quantity)
        else v_item.unit_cost end,
      p_source_type := 'purchase', p_source_id := p_purchase_id,
      p_reference_type := 'purchase', p_reference_id := p_purchase_id,
      p_notes := 'Inventory movement generated from purchase',
      p_idempotency_key := v_key, p_occurred_at := now(),
      p_metadata := jsonb_build_object('purchase_id', p_purchase_id,
        'purchase_item_id', v_item.id,
        'generated_by', 'apply_purchase_inventory_movements'));
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Exact completion manifest covers both original UNIT and W4B WEIGHT.
create or replace function private.finalize_exact_purchases_from_completed_batch()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_purchase public.purchases%rowtype;
  v_count integer;
  v_expected integer;
  v_total bigint;
  v_expected_total bigint;
  v_unmatched integer;
begin
  if new.status <> 'completed' or old.status is not distinct from new.status
     or new.direction <> 'upload' then return new; end if;
  for v_purchase in select p.* from public.sync_mutations m
    join public.purchases p on p.id = m.entity_id
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'purchases' and m.operation = 'insert'
      and m.status = 'applied' and p.business_id = new.business_id
      and p.metadata->>'monetary_contract_version'
        in ('exact_v1','exact_weight_basis_v1') for update of p
  loop
    if v_purchase.financial_finalized_at is not null then continue; end if;
    if coalesce(v_purchase.metadata->>'item_count','') !~ '^[1-9][0-9]*$'
       or coalesce(v_purchase.metadata->>'total_cents','') !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001',
        message = 'invalid_purchase_completion_manifest';
    end if;
    v_expected := (v_purchase.metadata->>'item_count')::integer;
    v_expected_total := (v_purchase.metadata->>'total_cents')::bigint;
    select count(*), coalesce(sum(pi.subtotal_cents),0) into v_count,v_total
      from public.purchase_items pi where pi.purchase_id = v_purchase.id
        and pi.deleted_at is null and pi.subtotal_cents is not null;
    select count(*) into v_unmatched from public.purchase_items pi
      where pi.purchase_id = v_purchase.id and pi.deleted_at is null
        and not exists (select 1 from public.sync_mutations m
          where m.sync_batch_id = new.id and m.deleted_at is null
            and m.entity_table = 'purchase_items' and m.operation = 'insert'
            and m.status = 'applied' and m.entity_id = pi.id
            and m.payload->>'purchase_id' = v_purchase.id::text);
    if v_expected <> v_count or v_unmatched <> 0
       or v_total <> v_expected_total
       or v_purchase.total is distinct from v_total::numeric / 100
       or v_expected <> (select count(*) from public.sync_mutations m
          where m.sync_batch_id = new.id and m.deleted_at is null
            and m.entity_table = 'purchase_items' and m.operation = 'insert'
            and m.status = 'applied'
            and m.payload->>'purchase_id' = v_purchase.id::text) then
      raise exception using errcode = 'P0001', message = 'purchase_money_not_complete';
    end if;
    update public.purchases set total_cents = v_total,
      monetary_contract_version =
        v_purchase.metadata->>'monetary_contract_version',
      financial_finalized_at = now()
      where id = v_purchase.id and financial_finalized_at is null;
  end loop;
  return new;
end;
$$;

-- Runs after legacy inventory auto-apply and exact financial finalization.
create function private.attach_weight_purchase_ack()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_ack jsonb;
  v_expected integer;
begin
  if new.status <> 'completed' or old.status is not distinct from new.status
     or new.direction <> 'upload' then return new; end if;
  select count(*) into v_expected from public.sync_mutations m
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'purchase_items' and m.status = 'applied'
      and m.payload->>'contract_version' = 'weighted_purchase_v1';
  if v_expected = 0 then return new; end if;
  select jsonb_agg(jsonb_build_object('purchase_id', pi.purchase_id,
      'purchase_item_id', pi.id, 'inventory_movement_id', im.id,
      'stock_quantity_grams', b.quantity_on_hand,
      'cost_basis_cents', b.cost_basis_cents,
      'cost_effect_cents', im.cost_effect_cents,
      'mutation_status', m.status) order by pi.id) into v_ack
    from public.sync_mutations m
    join public.purchase_items pi on pi.id = m.entity_id
    join public.inventory_movements im on im.business_id = pi.business_id
      and im.idempotency_key = 'purchase:' || pi.purchase_id::text
        || ':item:' || pi.id::text
    join public.product_stock_balances b on b.business_id = pi.business_id
      and b.branch_id = pi.branch_id and b.product_id = pi.product_id
      and b.deleted_at is null
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'purchase_items' and m.status = 'applied'
      and m.payload->>'contract_version' = 'weighted_purchase_v1';
  if coalesce(jsonb_array_length(v_ack),0) <> v_expected then
    raise exception using errcode = 'P0001',
      message = 'weighted_purchase_ack_incomplete';
  end if;
  update public.sync_batches set metadata = metadata ||
    jsonb_build_object('weighted_purchase_ack', v_ack) where id = new.id;
  return new;
end;
$$;
create trigger trg_sync_batches_zz_w4b_ack
  after update of status on public.sync_batches for each row
  execute function private.attach_weight_purchase_ack();

alter function public.process_sync_batch(uuid,text)
  rename to process_sync_batch_base_before_w4b;
revoke all on function public.process_sync_batch_base_before_w4b(uuid,text)
  from public, anon, authenticated;
create function public.process_sync_batch(p_sync_batch_id uuid,
  p_mode text default 'validate_only') returns jsonb language plpgsql
security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_ack jsonb;
begin
  v_result := public.process_sync_batch_base_before_w4b(p_sync_batch_id,p_mode);
  if lower(trim(p_mode)) = 'apply_purchases' then
    select metadata->'weighted_purchase_ack' into v_ack
      from public.sync_batches where id = p_sync_batch_id;
    if v_ack is not null then
      v_result := v_result || jsonb_build_object('weighted_purchase_ack',v_ack);
    end if;
  end if;
  return v_result;
end;
$$;
revoke all on function public.process_sync_batch(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch(uuid,text)
  to authenticated, service_role;

revoke all on function private.prepare_weight_purchase_item() from public, anon, authenticated;
revoke all on function private.prepare_weight_purchase_movement() from public, anon, authenticated;
revoke all on function private.apply_weight_purchase_cost_basis() from public, anon, authenticated;
revoke all on function private.attach_weight_purchase_ack() from public, anon, authenticated;

commit;
