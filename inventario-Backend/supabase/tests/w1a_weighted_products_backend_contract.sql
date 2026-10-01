begin;
select plan(32);

insert into public.businesses (id, name, status) values
  ('a6000000-0000-0000-0000-000000000001', 'W1A', 'active');
insert into public.branches (id, business_id, name, status) values
  ('a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000001', 'W1A', 'active');
insert into public.products (id, business_id, name, sale_price, unit) values
  ('a6000000-0000-0000-0000-000000000003',
   'a6000000-0000-0000-0000-000000000001', 'Legacy UNIT with kg label', 120.01, 'kg'),
  ('a6000000-0000-0000-0000-000000000004',
   'a6000000-0000-0000-0000-000000000001', 'Explicit WEIGHT', 12000.00, 'unidad');
update public.products set sale_mode = 'weight'
where id = 'a6000000-0000-0000-0000-000000000004';

select is((select sale_mode from public.products
  where id = 'a6000000-0000-0000-0000-000000000003'), 'unit',
  'legacy product defaults to UNIT even when unit label says kg');
select is((select sale_mode from public.products
  where id = 'a6000000-0000-0000-0000-000000000004'), 'weight',
  'WEIGHT is explicit and independent of unit label');
select throws_ok($$update public.products set sale_mode = 'volume'
  where id = 'a6000000-0000-0000-0000-000000000003'$$,
  '23514', null, 'unsupported mode is rejected');
select throws_ok($$update public.products set sale_mode = null
  where id = 'a6000000-0000-0000-0000-000000000003'$$,
  '23502', null, 'sale mode is required');
select is((select sale_price_cents from public.products
  where id = 'a6000000-0000-0000-0000-000000000003'), 12001::bigint,
  'stored numeric sale price has exact generated cents');
select is((select sale_price_cents from public.products
  where id = 'a6000000-0000-0000-0000-000000000004'), 1200000::bigint,
  'WEIGHT price is exact cents per 500 grams');
select lives_ok($$update public.products set sale_price = 120.02
  where id = 'a6000000-0000-0000-0000-000000000003'$$,
  'legacy price update remains accepted');
select is((select sale_price_cents from public.products
  where id = 'a6000000-0000-0000-0000-000000000003'), 12002::bigint,
  'generated cents cannot become stale after legacy update');
select throws_ok($$update public.products set sale_price_cents = 1
  where id = 'a6000000-0000-0000-0000-000000000003'$$,
  '428C9', null, 'generated exact cents cannot be forged');

select is((select data_type from information_schema.columns
  where table_schema = 'public' and table_name = 'sale_items'
    and column_name = 'quantity'), 'integer', 'sale quantity remains integer');
select is((select data_type from information_schema.columns
  where table_schema = 'public' and table_name = 'purchase_items'
    and column_name = 'quantity'), 'integer', 'purchase quantity remains integer');
select is((select data_type from information_schema.columns
  where table_schema = 'public' and table_name = 'inventory_movements'
    and column_name = 'quantity_change'), 'integer',
  'inventory movement quantity remains integer');

insert into public.sales (id, business_id, branch_id, total, status) values
  ('a6000000-0000-0000-0000-000000000005',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002', 0, 'completed');
insert into public.sale_items (id, sale_id, business_id, product_id,
  quantity, unit_price, subtotal) values
  ('a6000000-0000-0000-0000-000000000006',
   'a6000000-0000-0000-0000-000000000005',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000003', 2, 120.02, 240.04);
select ok((select quantity = 2 and sale_mode_snapshot = 'unit'
  and price_basis_quantity_snapshot = 1 from public.sale_items
  where id = 'a6000000-0000-0000-0000-000000000006'),
  'legacy sale line keeps quantity and UNIT basis');
select ok((select price_cents_snapshot is null and line_total_cents is null
  and cogs_cents is null from public.sale_items
  where id = 'a6000000-0000-0000-0000-000000000006'),
  'legacy sale line is not falsely certified as exact money');
select throws_ok($$update public.sale_items set price_basis_quantity_snapshot = 500
  where id = 'a6000000-0000-0000-0000-000000000006'$$,
  'P0001', 'sale_item_weight_snapshot_immutable',
  'sale basis snapshot cannot be rewritten');
select throws_ok($$update public.sale_items set cogs_cents = -1
  where id = 'a6000000-0000-0000-0000-000000000006'$$,
  '23514', null, 'negative line COGS is invalid');
select throws_ok($$insert into public.sale_items
  (id, sale_id, business_id, product_id, quantity, unit_price, subtotal,
   price_basis_quantity_snapshot)
  values ('a6000000-0000-0000-0000-000000000015',
  'a6000000-0000-0000-0000-000000000005',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000003', 1, 120.02, 120.02, 500)$$,
  '23514', null, 'UNIT sale cannot claim a gram price basis');
select throws_ok($$insert into public.sale_items
  (id, sale_id, business_id, product_id, quantity, unit_price, subtotal)
  values ('a6000000-0000-0000-0000-000000000007',
  'a6000000-0000-0000-0000-000000000005',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000004', 735, 12000, 12000)$$,
  'P0001', 'weight_operation_requires_versioned_sync',
  'old sale insert cannot treat grams as UNIT');

insert into public.purchases (id, business_id, branch_id, total, status) values
  ('a6000000-0000-0000-0000-000000000008',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002', 0, 'completed');
insert into public.purchase_items (id, purchase_id, business_id, branch_id,
  product_id, quantity, unit_cost, subtotal) values
  ('a6000000-0000-0000-0000-000000000009',
   'a6000000-0000-0000-0000-000000000008',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000003', 2, 12.50, 25.00);
select ok((select quantity = 2 and sale_mode_snapshot = 'unit'
  and cost_basis_quantity_snapshot = 1 from public.purchase_items
  where id = 'a6000000-0000-0000-0000-000000000009'),
  'legacy purchase line keeps quantity and UNIT basis');
select ok((select unit_cost_cents = 1250 and subtotal_cents = 2500
  and monetary_contract_version = 'legacy_stored' from public.purchase_items
  where id = 'a6000000-0000-0000-0000-000000000009'),
  'existing legacy purchase cents semantics are reused');
select throws_ok($$update public.purchase_items set cost_basis_quantity_snapshot = 500
  where id = 'a6000000-0000-0000-0000-000000000009'$$,
  'P0001', 'purchase_item_weight_snapshot_immutable',
  'purchase basis snapshot cannot be rewritten');
select throws_ok($$insert into public.purchase_items
  (id, purchase_id, business_id, branch_id, product_id, quantity,
   unit_cost, subtotal, cost_basis_quantity_snapshot)
  values ('a6000000-0000-0000-0000-000000000016',
  'a6000000-0000-0000-0000-000000000008',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000002',
  'a6000000-0000-0000-0000-000000000003', 1, 12.50, 12.50, 500)$$,
  '23514', null, 'UNIT purchase cannot claim a gram cost basis');
select throws_ok($$insert into public.purchase_items
  (id, purchase_id, business_id, branch_id, product_id, quantity, unit_cost, subtotal)
  values ('a6000000-0000-0000-0000-000000000010',
  'a6000000-0000-0000-0000-000000000008',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000002',
  'a6000000-0000-0000-0000-000000000004', 735, 12000, 12000)$$,
  'P0001', 'weight_operation_requires_versioned_sync',
  'old purchase insert cannot treat grams as UNIT');

insert into public.product_stock_balances (id, business_id, branch_id,
  product_id, quantity_on_hand, cost_basis_cents) values
  ('a6000000-0000-0000-0000-000000000011',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000003', 2, 18000000);
select is((select cost_basis_cents from public.product_stock_balances
  where id = 'a6000000-0000-0000-0000-000000000011'), 18000000::bigint,
  'balance stores exact total remaining cost cents');
select throws_ok($$update public.product_stock_balances set cost_basis_cents = -1
  where id = 'a6000000-0000-0000-0000-000000000011'$$,
  '23514', null, 'negative remaining cost is invalid');
select lives_ok($$insert into public.inventory_movements
  (id, business_id, branch_id, product_id, movement_type, quantity_change,
   cost_effect_cents) values ('a6000000-0000-0000-0000-000000000012',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000003', 'manual_adjustment', 1, 500)$$,
  'positive exact cost effect can add inventory value');
select lives_ok($$insert into public.inventory_movements
  (id, business_id, branch_id, product_id, movement_type, quantity_change,
   cost_effect_cents) values ('a6000000-0000-0000-0000-000000000013',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000003', 'manual_adjustment', -1, -500)$$,
  'negative exact cost effect can remove inventory value');
select throws_ok($$insert into public.inventory_movements
  (id, business_id, branch_id, product_id, movement_type, quantity_change,
   cost_effect_cents) values ('a6000000-0000-0000-0000-000000000017',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000003', 'manual_adjustment', -1, 500)$$,
  '23514', null, 'cost effect cannot add value while removing stock');
select throws_ok($$insert into public.inventory_movements
  (id, business_id, branch_id, product_id, movement_type, quantity_change)
  values ('a6000000-0000-0000-0000-000000000014',
   'a6000000-0000-0000-0000-000000000001',
   'a6000000-0000-0000-0000-000000000002',
   'a6000000-0000-0000-0000-000000000004', 'manual_adjustment', 735)$$,
  'P0001', 'weight_operation_requires_versioned_sync',
  'old inventory flow cannot apply grams as UNIT stock');
select is((select data_type from information_schema.columns
  where table_schema = 'public' and table_name = 'inventory_movements'
    and column_name = 'cost_effect_cents'), 'bigint',
  'movement has signed exact cents field');
select ok((select is_nullable = 'YES' from information_schema.columns
  where table_schema = 'public' and table_name = 'inventory_movements'
    and column_name = 'cost_effect_cents'),
  'historical movement cost effect remains unknown/NULL');
select ok((select is_nullable = 'YES' from information_schema.columns
  where table_schema = 'public' and table_name = 'product_stock_balances'
    and column_name = 'cost_basis_cents'),
  'historical balance cost basis remains unknown/NULL');

select * from finish();
rollback;
