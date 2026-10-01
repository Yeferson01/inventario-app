begin;

-- Quantity remains integer: UNIT counts pieces; WEIGHT counts grams. Existing
-- rows are UNIT regardless of the legacy products.unit/package description.
alter table public.products
  add column sale_mode text not null default 'unit',
  add column sale_price_cents bigint generated always as ((sale_price * 100)::bigint) stored;
alter table public.products add constraint products_sale_mode_allowed
  check (sale_mode in ('unit', 'weight'));
comment on column public.products.sale_mode is
  'UNIT quantity counts items; WEIGHT quantity counts grams. WEIGHT sale_price is per commercial 500 g pound.';

-- sale_price is already exact numeric(12,2) in Hosted. Its generated cents
-- mirror the stored price exactly and cannot become stale when an old client
-- updates sale_price. They do not attest the original pre-storage input.
comment on column public.products.sale_price_cents is
  'Exact cents of stored sale_price; UNIT is per item, WEIGHT is per 500 grams. Derived from numeric(12,2), not proof of original input precision.';

alter table public.sale_items
  add column sale_mode_snapshot text not null default 'unit',
  add column price_basis_quantity_snapshot integer not null default 1,
  add column price_cents_snapshot bigint,
  add column line_total_cents bigint,
  add column cogs_cents bigint;
alter table public.sale_items add constraint sale_items_weight_snapshot_contract
  check ((sale_mode_snapshot = 'unit' and price_basis_quantity_snapshot = 1) or
         (sale_mode_snapshot = 'weight' and price_basis_quantity_snapshot = 500));
comment on column public.sale_items.price_basis_quantity_snapshot is
  'Historical price basis: 1 item for UNIT, 500 grams for WEIGHT; never inferred from the current product.';
alter table public.sale_items add constraint sale_items_exact_money_range
  check ((price_cents_snapshot is null or price_cents_snapshot between 0 and 999999999999) and
         (line_total_cents is null or line_total_cents between 0 and 99999999999999) and
         (cogs_cents is null or cogs_cents between 0 and 99999999999999));
comment on column public.sale_items.line_total_cents is
  'Immutable exact line total when known; NULL for legacy rows without a verified exact-money snapshot.';
comment on column public.sale_items.cogs_cents is
  'Final authoritative line COGS; NULL means legacy or not yet authoritatively determined.';

-- Existing unit_cost_cents is the quoted unit cost for UNIT; for future
-- WEIGHT it will be the quoted cost per cost_basis_quantity_snapshot grams.
-- The current exact_v1 purchase processor only handles UNIT. W5 must extend
-- its calculation/constraint before WEIGHT purchase processing is enabled.
alter table public.purchase_items
  add column sale_mode_snapshot text not null default 'unit',
  add column cost_basis_quantity_snapshot integer not null default 1;
alter table public.purchase_items add constraint purchase_items_weight_snapshot_contract
  check ((sale_mode_snapshot = 'unit' and cost_basis_quantity_snapshot = 1) or
         (sale_mode_snapshot = 'weight' and cost_basis_quantity_snapshot in (500, 1000)));
comment on column public.purchase_items.cost_basis_quantity_snapshot is
  'Historical quoted cost basis: 1 item for UNIT; 500 or 1000 grams for future WEIGHT.';
comment on column public.purchase_items.unit_cost_cents is
  'Quoted exact cost cents per cost_basis_quantity_snapshot (1 UNIT; future WEIGHT 500 or 1000 grams). Legacy stored numeric conversion is marked legacy_stored.';

-- NULL preserves unknown historical cost. Do not derive a historical pool from
-- today's average cost or rewrite any historical movement/quantity.
alter table public.product_stock_balances
  add column cost_basis_cents bigint;
alter table public.product_stock_balances add constraint product_stock_balances_cost_basis_nonnegative
  check (cost_basis_cents is null or cost_basis_cents >= 0);
comment on column public.product_stock_balances.cost_basis_cents is
  'Total remaining inventory cost in exact cents, not cost per unit or gram; NULL means legacy/unknown.';

alter table public.inventory_movements
  add column cost_effect_cents bigint;
alter table public.inventory_movements add constraint inventory_movements_cost_effect_direction
  check (cost_effect_cents is null or
         (quantity_change > 0 and cost_effect_cents >= 0) or
         (quantity_change < 0 and cost_effect_cents <= 0));
comment on column public.inventory_movements.cost_effect_cents is
  'Signed exact cents: positive adds inventory value, negative removes it, NULL is legacy/undetermined.';

-- Existing server apply functions are UNIT-only. Until W4/W5/W7 install the
-- versioned WEIGHT processors, fail closed rather than silently applying a
-- gram quantity as a unit count. No WEIGHT catalog activation for old clients.
create function private.guard_unimplemented_weight_operation()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
begin
  select p.sale_mode into v_mode from public.products p where p.id = new.product_id;
  if v_mode = 'weight' then
    raise exception using errcode = 'P0001', message = 'weight_operation_requires_versioned_sync';
  end if;
  if tg_table_name in ('sale_items', 'purchase_items') then
    if new.sale_mode_snapshot = 'weight' then
      raise exception using errcode = 'P0001', message = 'weight_operation_requires_versioned_sync';
    end if;
  end if;
  return new;
end;
$$;
create trigger trg_sale_items_weight_version_guard
  before insert or update of product_id, quantity, sale_mode_snapshot on public.sale_items
  for each row execute function private.guard_unimplemented_weight_operation();
create trigger trg_purchase_items_weight_version_guard
  before insert or update of product_id, quantity, sale_mode_snapshot on public.purchase_items
  for each row execute function private.guard_unimplemented_weight_operation();
create trigger trg_inventory_movements_weight_version_guard
  before insert on public.inventory_movements
  for each row execute function private.guard_unimplemented_weight_operation();

create function private.guard_weight_sale_item_snapshots()
returns trigger language plpgsql
set search_path = public, private, extensions as $$
begin
  if new.sale_mode_snapshot is distinct from old.sale_mode_snapshot or
     new.price_basis_quantity_snapshot is distinct from old.price_basis_quantity_snapshot or
     new.price_cents_snapshot is distinct from old.price_cents_snapshot or
     new.line_total_cents is distinct from old.line_total_cents or
     (old.cogs_cents is not null and new.cogs_cents is distinct from old.cogs_cents) then
    raise exception using errcode = 'P0001', message = 'sale_item_weight_snapshot_immutable';
  end if;
  return new;
end;
$$;
create trigger trg_sale_items_weight_snapshots_immutable
  before update on public.sale_items
  for each row execute function private.guard_weight_sale_item_snapshots();

create function private.guard_weight_purchase_item_snapshots()
returns trigger language plpgsql
set search_path = public, private, extensions as $$
begin
  if new.sale_mode_snapshot is distinct from old.sale_mode_snapshot or
     new.cost_basis_quantity_snapshot is distinct from old.cost_basis_quantity_snapshot then
    raise exception using errcode = 'P0001', message = 'purchase_item_weight_snapshot_immutable';
  end if;
  return new;
end;
$$;
create trigger trg_purchase_items_weight_snapshots_immutable
  before update on public.purchase_items
  for each row execute function private.guard_weight_purchase_item_snapshots();

revoke all on function private.guard_unimplemented_weight_operation() from public;
revoke all on function private.guard_weight_sale_item_snapshots() from public;
revoke all on function private.guard_weight_purchase_item_snapshots() from public;

commit;
