begin;
select plan(28);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('c4000000-0000-0000-0000-000000000001', 'authenticated',
  'authenticated', 'c4a1@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status)
values ('c4000000-0000-0000-0000-000000000001', 'C4A1', 'active');
insert into public.businesses (id, name, status)
values ('c4000000-0000-0000-0000-000000000002', 'C4A1', 'active');
insert into public.branches (id, business_id, name, status)
values ('c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000002', 'C4A1', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select 'c4000000-0000-0000-0000-000000000011',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000003', id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values ('c4000000-0000-0000-0000-000000000004',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000003', 'c4a1-device', 'active');
insert into public.products (id, business_id, name, sale_price, purchase_price,
  stock_quantity, minimum_stock) values ('c4000000-0000-0000-0000-000000000005',
  'c4000000-0000-0000-0000-000000000002', 'C4A1 Product', 3000, 2500.50, 0, 0);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  'c4000000-0000-0000-0000-000000000001', true);
select throws_ok($$insert into public.purchases
  (id, business_id, branch_id, user_id, total, total_cents)
  values ('c4000000-0000-0000-0000-000000000021',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000001', 1, 100)$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated INSERT cannot forge total_cents');
select throws_ok($$insert into public.purchases
  (id, business_id, branch_id, user_id, total, financial_finalized_at)
  values ('c4000000-0000-0000-0000-000000000022',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000001', 1, now())$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated INSERT cannot forge financial_finalized_at');
select throws_ok($$insert into public.purchases
  (id, business_id, branch_id, user_id, total, monetary_contract_version)
  values ('c4000000-0000-0000-0000-000000000023',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000001', 1, 'exact_v1')$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated INSERT cannot forge monetary_contract_version');

select lives_ok($$insert into public.purchases
  (id, business_id, branch_id, user_id, total, status, metadata)
  values ('c4000000-0000-0000-0000-000000000006',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000001', 5001.00, 'completed',
  '{"monetary_contract_version":"exact_v1","item_count":1,"total_cents":"500100"}')$$,
  'authenticated ordinary purchase INSERT remains allowed');
select throws_ok($$update public.purchases set total_cents = 500100
  where id = 'c4000000-0000-0000-0000-000000000006'$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated pre-finalization UPDATE cannot forge total_cents');
select throws_ok($$update public.purchases set financial_finalized_at = now()
  where id = 'c4000000-0000-0000-0000-000000000006'$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated pre-finalization UPDATE cannot forge finalization time');
select throws_ok($$update public.purchases
  set monetary_contract_version = 'exact_v1'
  where id = 'c4000000-0000-0000-0000-000000000006'$$,
  'P0001', 'purchase_money_requires_batch_finalization',
  'authenticated pre-finalization UPDATE cannot forge contract version');
select lives_ok($$update public.purchases set supplier_name = 'Supplier'
  where id = 'c4000000-0000-0000-0000-000000000006'$$,
  'authenticated ordinary pre-finalization UPDATE remains allowed');
reset role;
select ok((select financial_finalized_at is null and total_cents is null
  from public.purchases where id = 'c4000000-0000-0000-0000-000000000006'),
  '1. header alone is not financially finalized');

insert into public.purchase_items (id, purchase_id, business_id, branch_id,
  product_id, quantity, unit_cost, subtotal, metadata)
values ('c4000000-0000-0000-0000-000000000007',
  'c4000000-0000-0000-0000-000000000006',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000003',
  'c4000000-0000-0000-0000-000000000005', 2, 2500.50, 5001.00,
  '{"unit_cost_cents":"250050","subtotal_cents":"500100"}');
select is((select unit_cost_cents from public.purchase_items
  where id = 'c4000000-0000-0000-0000-000000000007'), 250050::bigint,
  '2. item unit cost is exact cents');
select is((select subtotal_cents from public.purchase_items
  where id = 'c4000000-0000-0000-0000-000000000007'), 500100::bigint,
  '3. item subtotal is exact multiplication');
select ok((select financial_finalized_at is null from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000006'),
  '4. item alone does not finalize purchase');

insert into public.sync_batches (id, business_id, app_device_id, profile_id,
  branch_id, client_batch_id, direction, status)
values ('c4000000-0000-0000-0000-000000000008',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000004',
  'c4000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000003', 'c4a1-batch', 'upload', 'pending');
insert into public.sync_mutations (id, business_id, sync_batch_id,
  app_device_id, profile_id, branch_id, client_mutation_id, client_sequence,
  entity_table, entity_id, operation, payload, status) values
  ('c4000000-0000-0000-0000-000000000009',
   'c4000000-0000-0000-0000-000000000002',
   'c4000000-0000-0000-0000-000000000008',
   'c4000000-0000-0000-0000-000000000004',
   'c4000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000003',
   'c4a1-header', 1, 'purchases',
   'c4000000-0000-0000-0000-000000000006', 'insert', '{}', 'applied'),
  ('c4000000-0000-0000-0000-000000000010',
   'c4000000-0000-0000-0000-000000000002',
   'c4000000-0000-0000-0000-000000000008',
   'c4000000-0000-0000-0000-000000000004',
   'c4000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000003',
   'c4a1-item', 2, 'purchase_items',
   'c4000000-0000-0000-0000-000000000007', 'insert',
   '{"purchase_id":"c4000000-0000-0000-0000-000000000006"}', 'applied');
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'c4000000-0000-0000-0000-000000000001', true);
select throws_ok($$update public.sync_batches
  set status = 'completed', mutation_count = 2, applied_count = 2,
    server_completed_at = now()
  where id = 'c4000000-0000-0000-0000-000000000008'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'authenticated cannot trigger C4A1 purchase finalization through batch status');
reset role;
select ok((select financial_finalized_at is null from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000006'),
  'forged completion leaves purchase unfinalized');
select set_config('request.jwt.claim.sub',
  'c4000000-0000-0000-0000-000000000001', true);
update public.sync_batches set status = 'completed', mutation_count = 2,
  applied_count = 2 where id = 'c4000000-0000-0000-0000-000000000008';
select ok((select financial_finalized_at is not null from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000006'),
  '5. complete applied batch finalizes purchase');
select is((select total_cents from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000006'), 500100::bigint,
  '6. server derives final total from items');
update public.sync_batches set status = 'completed'
where id = 'c4000000-0000-0000-0000-000000000008';
select is((select total_cents from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000006'), 500100::bigint,
  '7. completion retry leaves total unchanged');
select throws_ok($$update public.purchase_items set quantity = 3
  where id = 'c4000000-0000-0000-0000-000000000007'$$,
  'P0001', 'purchase_financially_finalized',
  '8. semantic item update is rejected after finalization');
update public.purchase_items set quantity = quantity
where id = 'c4000000-0000-0000-0000-000000000007';
select ok((select quantity = 2 from public.purchase_items
  where id = 'c4000000-0000-0000-0000-000000000007'),
  '9. identical item retry is allowed');
select throws_ok($$update public.purchases set total_cents = 1
  where id = 'c4000000-0000-0000-0000-000000000006'$$,
  'P0001', 'purchase_financially_finalized',
  '10. finalized header total cannot change');

-- S1 regression: neither mutation nor batch result is client-owned. The same
-- pending intent must still finalize through the real processor.
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'c4000000-0000-0000-0000-000000000001', true);
select lives_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id, direction, status,
  mutation_count) values ('c4000000-0000-0000-0000-000000000031',
  'c4000000-0000-0000-0000-000000000002',
  'c4000000-0000-0000-0000-000000000004',
  'c4000000-0000-0000-0000-000000000001',
  'c4000000-0000-0000-0000-000000000003', 'c4a1-real-process', 'upload',
  'pending', 2)$$, 'authenticated can create pending purchase batch');
select lives_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload, status,
  idempotency_key) values
  ('c4000000-0000-0000-0000-000000000032',
   'c4000000-0000-0000-0000-000000000002',
   'c4000000-0000-0000-0000-000000000031',
   'c4000000-0000-0000-0000-000000000004',
   'c4000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000003',
   'c4a1-real-header', 1, 'purchases',
   'c4000000-0000-0000-0000-000000000030', 'insert',
   '{"branch_id":"c4000000-0000-0000-0000-000000000003","total":5001,"status":"completed","metadata":{"monetary_contract_version":"exact_v1","item_count":1,"total_cents":"500100"}}',
   'pending', 'c4a1-real-header-key'),
  ('c4000000-0000-0000-0000-000000000033',
   'c4000000-0000-0000-0000-000000000002',
   'c4000000-0000-0000-0000-000000000031',
   'c4000000-0000-0000-0000-000000000004',
   'c4000000-0000-0000-0000-000000000001',
   'c4000000-0000-0000-0000-000000000003',
   'c4a1-real-item', 2, 'purchase_items',
   'c4000000-0000-0000-0000-000000000034', 'insert',
   '{"purchase_id":"c4000000-0000-0000-0000-000000000030","product_id":"c4000000-0000-0000-0000-000000000005","quantity":2,"unit_cost":2500.50,"subtotal":5001,"metadata":{"unit_cost_cents":"250050","subtotal_cents":"500100"}}',
   'pending', 'c4a1-real-item-key')$$,
  'authenticated can create pending purchase mutations');
select throws_ok($$update public.sync_mutations
  set status = 'applied', server_processed_at = now()
  where id = 'c4000000-0000-0000-0000-000000000033'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'authenticated cannot forge applied purchase item');
select throws_ok($$update public.sync_batches
  set status = 'completed', applied_count = 2, server_completed_at = now()
  where id = 'c4000000-0000-0000-0000-000000000031'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'authenticated cannot indirectly finalize purchase');
reset role;
select ok(not exists (select 1 from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000030'),
  'forged mutation and batch results do not materialize purchase');
set local role authenticated;
select set_config('request.jwt.claim.sub',
  'c4000000-0000-0000-0000-000000000001', true);
select lives_ok($$select public.process_sync_batch(
  'c4000000-0000-0000-0000-000000000031', 'apply_purchases')$$,
  'real purchase processor can apply pending intent');
reset role;
select ok((select financial_finalized_at is not null from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000030'),
  'backend completion legitimately finalizes purchase');
select is((select total_cents from public.purchases
  where id = 'c4000000-0000-0000-0000-000000000030'), 500100::bigint,
  'legitimate processor preserves exact purchase cents');

select * from finish();
rollback;
