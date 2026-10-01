begin;
select plan(21);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('a7300000-0000-0000-0000-000000000101', 'authenticated',
  'authenticated', 'w3@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, role, status)
values ('a7300000-0000-0000-0000-000000000101', 'W3 Owner', 'owner', 'active');
insert into public.businesses (id, name, status)
values ('a7300000-0000-0000-0000-000000000001', 'W3 Business', 'active');
insert into public.branches (id, business_id, name, status)
values ('a7300000-0000-0000-0000-000000000011',
  'a7300000-0000-0000-0000-000000000001', 'W3 Branch', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
values ('a7300000-0000-0000-0000-000000000041',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000101', null,
  (select id from public.roles where business_id is null and name = 'owner'
    and deleted_at is null limit 1), 'active');
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status)
values ('a7300000-0000-0000-0000-000000000051',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000101',
  'a7300000-0000-0000-0000-000000000011', 'w3-device', 'active');
select set_config('request.jwt.claim.sub',
  'a7300000-0000-0000-0000-000000000101', true);

insert into public.products (id, business_id, name, sale_price, unit)
select ('a7300000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'a7300000-0000-0000-0000-000000000001', 'W3 product ' || n,
  800.00, 'kg' from generate_series(201, 205) n;
select is((select sale_mode from public.products where id =
  'a7300000-0000-0000-0000-000000000201'), 'unit',
  'legacy kg label never selects WEIGHT');
select lives_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7300000-0000-0000-0000-000000000201'$$,
  'mode can change without stock or history');
select is((select sale_price_cents from public.products where id =
  'a7300000-0000-0000-0000-000000000201'), 80000::bigint,
  '500 g commercial price has exact cents');
select throws_ok($$update public.products set sale_price = 900
  where id = 'a7300000-0000-0000-0000-000000000201'$$,
  'P0001', 'weight_product_price_requires_versioned_sync',
  'old direct price edit cannot reinterpret weighted price');
select lives_ok($$update public.products set sale_mode = 'unit'
  where id = 'a7300000-0000-0000-0000-000000000201'$$,
  'WEIGHT to UNIT is permitted before history');

update public.products set stock_quantity = 1 where id =
  'a7300000-0000-0000-0000-000000000202';
select throws_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7300000-0000-0000-0000-000000000202'$$,
  'P0001', 'product_sale_mode_has_operational_history',
  'nonzero stock blocks reinterpretation');
insert into public.inventory_movements (id, business_id, branch_id, product_id,
  movement_type, quantity_change)
values ('a7300000-0000-0000-0000-000000000301',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000011',
  'a7300000-0000-0000-0000-000000000203', 'manual_adjustment', 1);
select throws_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7300000-0000-0000-0000-000000000203'$$,
  'P0001', 'product_sale_mode_has_operational_history',
  'movement blocks reinterpretation');
insert into public.sales (id, business_id, branch_id, total, status)
values ('a7300000-0000-0000-0000-000000000401',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000011', 0, 'completed');
insert into public.sale_items (id, sale_id, business_id, product_id,
  quantity, unit_price, subtotal)
values ('a7300000-0000-0000-0000-000000000402',
  'a7300000-0000-0000-0000-000000000401',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000204', 1, 800, 800);
select throws_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7300000-0000-0000-0000-000000000204'$$,
  'P0001', 'product_sale_mode_has_operational_history',
  'sale history blocks reinterpretation');
insert into public.purchases (id, business_id, branch_id, total, status)
values ('a7300000-0000-0000-0000-000000000501',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000011', 0, 'completed');
insert into public.purchase_items (id, purchase_id, business_id, branch_id,
  product_id, quantity, unit_cost, subtotal)
values ('a7300000-0000-0000-0000-000000000502',
  'a7300000-0000-0000-0000-000000000501',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000011',
  'a7300000-0000-0000-0000-000000000205', 1, 100, 100);
select throws_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7300000-0000-0000-0000-000000000205'$$,
  'P0001', 'product_sale_mode_has_operational_history',
  'purchase history blocks reinterpretation');

insert into public.sync_batches (id, business_id, app_device_id, profile_id,
  branch_id, client_batch_id, direction, status, mutation_count)
values ('a7300000-0000-0000-0000-000000000601',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000051',
  'a7300000-0000-0000-0000-000000000101',
  'a7300000-0000-0000-0000-000000000011', 'w3-batch',
  'upload', 'pending', 3);
insert into public.sync_mutations (id, business_id, sync_batch_id,
  app_device_id, profile_id, branch_id, client_mutation_id, client_sequence,
  entity_table, entity_id, operation, payload, status, idempotency_key)
values
  ('a7300000-0000-0000-0000-000000000611',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000601',
   'a7300000-0000-0000-0000-000000000051',
   'a7300000-0000-0000-0000-000000000101',
   'a7300000-0000-0000-0000-000000000011',
   'w3-insert', 1, 'products',
   'a7300000-0000-0000-0000-000000000206', 'insert',
   '{"name":"Papa","sale_mode":"weight","sale_price":"800.00","sale_price_cents":80000,"minimum_stock":0}'::jsonb,
   'pending', 'w3-insert-key'),
  ('a7300000-0000-0000-0000-000000000612',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000601',
   'a7300000-0000-0000-0000-000000000051',
   'a7300000-0000-0000-0000-000000000101',
   'a7300000-0000-0000-0000-000000000011',
   'w3-update', 2, 'products',
   'a7300000-0000-0000-0000-000000000206', 'update',
   '{"sale_mode":"weight","sale_price":"900.00","sale_price_cents":90000}'::jsonb,
   'pending', 'w3-update-key'),
  ('a7300000-0000-0000-0000-000000000613',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000601',
   'a7300000-0000-0000-0000-000000000051',
   'a7300000-0000-0000-0000-000000000101',
   'a7300000-0000-0000-0000-000000000011',
   'w3-mismatch', 3, 'products',
   'a7300000-0000-0000-0000-000000000206', 'update',
   '{"sale_mode":"weight","sale_price":"1000.00","sale_price_cents":90000}'::jsonb,
   'pending', 'w3-mismatch-key');

select is(private.apply_sync_catalog_mutation(
  'a7300000-0000-0000-0000-000000000611')->>'status', 'applied',
  'catalog insert projects WEIGHT');
select ok((select sale_mode = 'weight' and sale_price_cents = 80000
  from public.products where id = 'a7300000-0000-0000-0000-000000000206'),
  'insert retains explicit mode and exact 500 g price');
select ok((select m.server_entity_version = p.version
  from public.sync_mutations m join public.products p
    on p.id = m.entity_id
  where m.id = 'a7300000-0000-0000-0000-000000000611'),
  'post-mode version is reflected in ACK, not the pre-transition version');
select is(private.apply_sync_catalog_mutation(
  'a7300000-0000-0000-0000-000000000612')->>'status', 'applied',
  'catalog update accepts exact WEIGHT price');
select is((select sale_price_cents from public.products where id =
  'a7300000-0000-0000-0000-000000000206'), 90000::bigint,
  'WEIGHT edit remains exact');
select throws_ok($$select private.apply_sync_catalog_mutation(
  'a7300000-0000-0000-0000-000000000613')$$,
  'P0001', 'product_sale_price_cents_mismatch',
  'mismatched legacy price cannot override exact cents');
select is((select sale_price_cents from public.products where id =
  'a7300000-0000-0000-0000-000000000206'), 90000::bigint,
  'rejected price mutation preserves server price');
select throws_ok($$insert into public.sale_items (id, sale_id, business_id,
  product_id, quantity, unit_price, subtotal) values
  ('a7300000-0000-0000-0000-000000000702',
   'a7300000-0000-0000-0000-000000000401',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000206', 735, 900, 1323)$$,
  'P0001', 'weight_operation_requires_versioned_sync',
  'WEIGHT POS remains fail closed');
select throws_ok($$insert into public.purchase_items (id, purchase_id,
  business_id, branch_id, product_id, quantity, unit_cost, subtotal) values
  ('a7300000-0000-0000-0000-000000000703',
   'a7300000-0000-0000-0000-000000000501',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000011',
   'a7300000-0000-0000-0000-000000000206', 1000, 900, 1800)$$,
  'P0001', 'weight_operation_requires_versioned_sync',
  'WEIGHT purchase remains fail closed');

insert into public.sync_batches (id, business_id, app_device_id, profile_id,
  branch_id, client_batch_id, direction, status, mutation_count)
values ('a7300000-0000-0000-0000-000000000602',
  'a7300000-0000-0000-0000-000000000001',
  'a7300000-0000-0000-0000-000000000051',
  'a7300000-0000-0000-0000-000000000101',
  'a7300000-0000-0000-0000-000000000011', 'w3-public-batch',
  'upload', 'pending', 1);
insert into public.sync_mutations (id, business_id, sync_batch_id,
  app_device_id, profile_id, branch_id, client_mutation_id, client_sequence,
  entity_table, entity_id, operation, payload, status, idempotency_key)
values ('a7300000-0000-0000-0000-000000000614',
   'a7300000-0000-0000-0000-000000000001',
   'a7300000-0000-0000-0000-000000000602',
   'a7300000-0000-0000-0000-000000000051',
   'a7300000-0000-0000-0000-000000000101',
   'a7300000-0000-0000-0000-000000000011',
   'w3-public-insert', 1, 'products',
   'a7300000-0000-0000-0000-000000000207', 'insert',
   '{"name":"Papa public","sale_mode":"weight","sale_price":"800.00","sale_price_cents":80000}'::jsonb,
   'pending', 'w3-public-insert-key');
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'a7300000-0000-0000-0000-000000000101', true);
select lives_ok($$select public.process_sync_batch(
  'a7300000-0000-0000-0000-000000000602', 'apply_catalog')$$,
  'public authenticated catalog batch accepts WEIGHT configuration');
reset role;
select ok((select sale_mode = 'weight' and sale_price_cents = 80000
  from public.products where id = 'a7300000-0000-0000-0000-000000000207'),
  'public catalog path persisted WEIGHT and exact cents');
select ok((select m.status = 'applied' and m.server_entity_version = p.version
  from public.sync_mutations m join public.products p on p.id = m.entity_id
  where m.id = 'a7300000-0000-0000-0000-000000000614'),
  'public catalog ACK reports final product version');

select * from finish();
rollback;
