begin;

select plan(13);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  'f3000000-0000-0000-0000-000000000101',
  'authenticated', 'authenticated', 'sale-cost@example.test', '', now(),
  '{}', '{}', now(), now()
);

insert into public.profiles (id, full_name, role, status)
values (
  'f3000000-0000-0000-0000-000000000101',
  'Sale Cost Owner', 'owner', 'active'
);

insert into public.businesses (id, name, status)
values (
  'f3000000-0000-0000-0000-000000000001',
  'Sale Cost Business', 'active'
);

insert into public.branches (id, business_id, name, status)
values (
  'f3000000-0000-0000-0000-000000000011',
  'f3000000-0000-0000-0000-000000000001',
  'Principal', 'active'
);

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status
)
values (
  'f3000000-0000-0000-0000-000000000041',
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000101',
  null,
  (
    select id
    from public.roles
    where business_id is null
      and name = 'owner'
      and deleted_at is null
    limit 1
  ),
  'active'
);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values (
  'f3000000-0000-0000-0000-000000000051',
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000101',
  'f3000000-0000-0000-0000-000000000011',
  'sale-cost-device', 'active'
);

insert into public.cash_registers (id, business_id, branch_id, name, status)
values (
  'f3000000-0000-0000-0000-000000000061',
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000011',
  'Principal', 'active'
);

insert into public.cash_sessions (
  id, business_id, branch_id, cash_register_id, opened_by,
  opening_amount, status, opened_at
)
values (
  'f3000000-0000-0000-0000-000000000071',
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000011',
  'f3000000-0000-0000-0000-000000000061',
  'f3000000-0000-0000-0000-000000000101',
  0, 'open', now()
);

insert into public.products (
  id, business_id, name, purchase_price, sale_price, stock_quantity, status
)
values (
  'f3000000-0000-0000-0000-000000000081',
  'f3000000-0000-0000-0000-000000000001',
  'Sale Cost Product', 9999, 10000, 0, 'active'
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost
)
values (
  'f3000000-0000-0000-0000-000000000091',
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000011',
  'f3000000-0000-0000-0000-000000000081',
  20, 0, 9999
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count, metadata
)
select
  ('f3100000-0000-0000-0000-00000000000' || n)::uuid,
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000051',
  'f3000000-0000-0000-0000-000000000101',
  'f3000000-0000-0000-0000-000000000011',
  'sale-cost-' || n,
  'upload', 'pending', 2, '{"domain":"pos"}'::jsonb
from generate_series(1, 4) n;

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'f3200000-0000-0000-0000-000000000011',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-sale-known', 1, 'sales',
    'f3300000-0000-0000-0000-000000000001', 'insert',
    '{"branch_id":"f3000000-0000-0000-0000-000000000011","cash_register_id":"f3000000-0000-0000-0000-000000000061","cash_session_id":"f3000000-0000-0000-0000-000000000071","subtotal":10000,"total":10000,"payment_method":"cash","status":"completed"}',
    'pending', 'sale-cost-sale-known'
  ),
  (
    'f3200000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000001',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-item-known', 2, 'sale_items',
    'f3400000-0000-0000-0000-000000000001', 'insert',
    '{"sale_id":"f3300000-0000-0000-0000-000000000001","product_id":"f3000000-0000-0000-0000-000000000081","quantity":1,"unit_price":10000,"unit_cost_snapshot":6000,"subtotal":10000,"total":10000}',
    'pending', 'sale-cost-item-known'
  ),
  (
    'f3200000-0000-0000-0000-000000000021',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000002',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-sale-null', 1, 'sales',
    'f3300000-0000-0000-0000-000000000002', 'insert',
    '{"branch_id":"f3000000-0000-0000-0000-000000000011","cash_register_id":"f3000000-0000-0000-0000-000000000061","cash_session_id":"f3000000-0000-0000-0000-000000000071","subtotal":10000,"total":10000,"payment_method":"cash","status":"completed"}',
    'pending', 'sale-cost-sale-null'
  ),
  (
    'f3200000-0000-0000-0000-000000000022',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000002',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-item-null', 2, 'sale_items',
    'f3400000-0000-0000-0000-000000000002', 'insert',
    '{"sale_id":"f3300000-0000-0000-0000-000000000002","product_id":"f3000000-0000-0000-0000-000000000081","quantity":1,"unit_price":10000,"unit_cost_snapshot":null,"subtotal":10000,"total":10000}',
    'pending', 'sale-cost-item-null'
  ),
  (
    'f3200000-0000-0000-0000-000000000031',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000003',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-sale-zero', 1, 'sales',
    'f3300000-0000-0000-0000-000000000003', 'insert',
    '{"branch_id":"f3000000-0000-0000-0000-000000000011","cash_register_id":"f3000000-0000-0000-0000-000000000061","cash_session_id":"f3000000-0000-0000-0000-000000000071","subtotal":10000,"total":10000,"payment_method":"cash","status":"completed"}',
    'pending', 'sale-cost-sale-zero'
  ),
  (
    'f3200000-0000-0000-0000-000000000032',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000003',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-item-zero', 2, 'sale_items',
    'f3400000-0000-0000-0000-000000000003', 'insert',
    '{"sale_id":"f3300000-0000-0000-0000-000000000003","product_id":"f3000000-0000-0000-0000-000000000081","quantity":1,"unit_price":10000,"unit_cost_snapshot":0,"subtotal":10000,"total":10000}',
    'pending', 'sale-cost-item-zero'
  ),
  (
    'f3200000-0000-0000-0000-000000000041',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000004',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-sale-omitted', 1, 'sales',
    'f3300000-0000-0000-0000-000000000004', 'insert',
    '{"branch_id":"f3000000-0000-0000-0000-000000000011","cash_register_id":"f3000000-0000-0000-0000-000000000061","cash_session_id":"f3000000-0000-0000-0000-000000000071","subtotal":10000,"total":10000,"payment_method":"cash","status":"completed"}',
    'pending', 'sale-cost-sale-omitted'
  ),
  (
    'f3200000-0000-0000-0000-000000000042',
    'f3000000-0000-0000-0000-000000000001',
    'f3100000-0000-0000-0000-000000000004',
    'f3000000-0000-0000-0000-000000000051',
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000011',
    'sale-cost-item-omitted', 2, 'sale_items',
    'f3400000-0000-0000-0000-000000000004', 'insert',
    '{"sale_id":"f3300000-0000-0000-0000-000000000004","product_id":"f3000000-0000-0000-0000-000000000081","quantity":1,"unit_price":10000,"subtotal":10000,"total":10000}',
    'pending', 'sale-cost-item-omitted'
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000101',
  true
);

select public.process_sync_batch(
  ('f3100000-0000-0000-0000-00000000000' || n)::uuid,
  'apply_pos'
)
from generate_series(1, 4) n;

select is(
  (select unit_cost_snapshot from public.sale_items where id = 'f3400000-0000-0000-0000-000000000001'),
  6000::numeric,
  'FC-03A sale item preserves the known local cost instead of product purchase_price'
);
select is(
  (select unit_cost from public.inventory_movements where source_type = 'sale' and source_id = 'f3300000-0000-0000-0000-000000000001'),
  6000::numeric,
  'FC-03A inventory movement uses the preserved sale item cost'
);
select is(
  (select unit_cost_snapshot from public.sale_items where id = 'f3400000-0000-0000-0000-000000000002'),
  null::numeric,
  'FC-03B explicit null remains unknown on the sale item'
);
select is(
  (select unit_cost from public.inventory_movements where source_type = 'sale' and source_id = 'f3300000-0000-0000-0000-000000000002'),
  null::numeric,
  'FC-03B explicit null remains unknown on the inventory movement'
);
select is(
  (select unit_cost_snapshot from public.sale_items where id = 'f3400000-0000-0000-0000-000000000003'),
  0::numeric,
  'FC-03C explicit zero remains zero on the sale item'
);
select is(
  (select unit_cost from public.inventory_movements where source_type = 'sale' and source_id = 'f3300000-0000-0000-0000-000000000003'),
  0::numeric,
  'FC-03C explicit zero remains zero on the inventory movement'
);
select is(
  (select unit_cost_snapshot from public.sale_items where id = 'f3400000-0000-0000-0000-000000000004'),
  null::numeric,
  'FC-03D an older client that omits the key stores null'
);
select is(
  (select unit_cost from public.inventory_movements where source_type = 'sale' and source_id = 'f3300000-0000-0000-0000-000000000004'),
  null::numeric,
  'FC-03D omitted cost remains null on the inventory movement'
);

select throws_ok(
  $$update public.sale_items set unit_cost_snapshot = 6000 where id = 'f3400000-0000-0000-0000-000000000002'$$,
  'P0001',
  'sale_items.unit_cost_snapshot is immutable',
  'FC-03E null cannot be rewritten as a known cost'
);
select throws_ok(
  $$update public.sale_items set unit_cost_snapshot = null where id = 'f3400000-0000-0000-0000-000000000001'$$,
  'P0001',
  'sale_items.unit_cost_snapshot is immutable',
  'FC-03E a known cost cannot be rewritten as null'
);
select throws_ok(
  $$update public.sale_items set unit_cost_snapshot = 6500 where id = 'f3400000-0000-0000-0000-000000000001'$$,
  'P0001',
  'sale_items.unit_cost_snapshot is immutable',
  'FC-03E a known cost cannot be changed'
);
select throws_ok(
  $$update public.sale_items set unit_cost_snapshot = 1 where id = 'f3400000-0000-0000-0000-000000000003'$$,
  'P0001',
  'sale_items.unit_cost_snapshot is immutable',
  'FC-03E zero cannot be changed to another cost'
);
select lives_ok(
  $$update public.sale_items set unit_cost_snapshot = 6000 where id = 'f3400000-0000-0000-0000-000000000001'$$,
  'FC-03E writing the same cost remains allowed'
);

select * from finish();

rollback;
