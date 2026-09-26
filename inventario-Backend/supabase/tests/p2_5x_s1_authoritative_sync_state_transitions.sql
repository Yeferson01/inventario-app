begin;
select plan(29);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('51000000-0000-0000-0000-000000000001', 'authenticated',
  'authenticated', 's1@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status)
values ('51000000-0000-0000-0000-000000000001', 'S1', 'active');
insert into public.businesses (id, name, status)
values ('51000000-0000-0000-0000-000000000002', 'S1', 'active');
insert into public.branches (id, business_id, name, status)
values ('51000000-0000-0000-0000-000000000003',
  '51000000-0000-0000-0000-000000000002', 'S1', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '51000000-0000-0000-0000-000000000011',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values ('51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 's1-device', 'active');
insert into public.products (id, business_id, name, sale_price, purchase_price,
  stock_quantity, minimum_stock) values ('51000000-0000-0000-0000-000000000005',
  '51000000-0000-0000-0000-000000000002', 'S1 Product', 20, 10, 0, 0);
insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('51000000-0000-0000-0000-000000000041', 'authenticated',
  'authenticated', 's1-other@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status)
values ('51000000-0000-0000-0000-000000000041', 'S1 Other', 'active');
insert into public.businesses (id, name, status)
values ('51000000-0000-0000-0000-000000000042', 'S1 Other', 'active');
insert into public.branches (id, business_id, name, status)
values ('51000000-0000-0000-0000-000000000043',
  '51000000-0000-0000-0000-000000000042', 'S1 Other', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '51000000-0000-0000-0000-000000000044',
  '51000000-0000-0000-0000-000000000042',
  '51000000-0000-0000-0000-000000000041',
  '51000000-0000-0000-0000-000000000043', id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values ('51000000-0000-0000-0000-000000000045',
  '51000000-0000-0000-0000-000000000042',
  '51000000-0000-0000-0000-000000000041',
  '51000000-0000-0000-0000-000000000043', 's1-other-device', 'active');

set local role authenticated;
select set_config('request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000001', true);

select lives_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id, direction, status,
  mutation_count) values ('51000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 's1-batch', 'upload', 'pending', 1)$$,
  'authenticated can insert an ordinary pending batch');
select lives_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload, status,
  idempotency_key) values ('51000000-0000-0000-0000-000000000007',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 's1-mutation', 1,
  'products', '51000000-0000-0000-0000-000000000005', 'update',
  '{"sale_price":30}', 'pending', 's1-idempotency')$$,
  'authenticated can insert an ordinary pending mutation');

select throws_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id, status)
  values ('51000000-0000-0000-0000-000000000021',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-complete', 'completed')$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot INSERT completed batch');
select throws_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id, status, server_started_at)
  values ('51000000-0000-0000-0000-000000000022',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-time', 'pending', now())$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot supply server_started_at');
select throws_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id, status, metadata)
  values ('51000000-0000-0000-0000-000000000025',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-result', 'pending',
  '{"purchase_inventory_auto_apply":{"result":"applied"}}')$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot pre-seed batch result metadata');
select throws_ok($$update public.sync_batches set status = 'completed',
  server_completed_at = now() where id = '51000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot complete pending batch');
select throws_ok($$update public.sync_batches set status = 'processing'
  where id = '51000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot claim processor state');
select throws_ok($$update public.sync_batches set applied_count = 1
  where id = '51000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot forge applied count');
select throws_ok($$update public.sync_batches set metadata = '{"forged":true}'
  where id = '51000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'client cannot rewrite pending batch metadata');
select throws_ok($$update public.sync_batches
  set app_device_id = '51000000-0000-0000-0000-000000000045'
  where id = '51000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'batch owner cannot switch to another tenant device');

select throws_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload, status,
  server_processed_at) values ('51000000-0000-0000-0000-000000000023',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-applied', 2,
  'products', '51000000-0000-0000-0000-000000000005', 'update',
  '{}', 'applied', now())$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot INSERT applied mutation');
select throws_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload, status,
  server_processed_at) values ('51000000-0000-0000-0000-000000000024',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-time', 2,
  'products', '51000000-0000-0000-0000-000000000005', 'update',
  '{}', 'pending', now())$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot supply server_processed_at');
select throws_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload, status,
  metadata) values ('51000000-0000-0000-0000-000000000026',
  '51000000-0000-0000-0000-000000000002',
  '51000000-0000-0000-0000-000000000006',
  '51000000-0000-0000-0000-000000000004',
  '51000000-0000-0000-0000-000000000001',
  '51000000-0000-0000-0000-000000000003', 'forged-result', 2,
  'products', '51000000-0000-0000-0000-000000000005', 'update',
  '{}', 'pending', '{"apply_cash_result":{"status":"applied"}}')$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot pre-seed mutation result metadata');
select throws_ok($$update public.sync_mutations
  set status = 'applied', server_processed_at = now()
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot mark mutation applied');
select throws_ok($$update public.sync_mutations
  set status = 'conflict', error_message = 'forged', server_processed_at = now()
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot mark mutation conflict');
select throws_ok($$update public.sync_mutations
  set status = 'skipped', server_processed_at = now()
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot mark mutation skipped');
select throws_ok($$update public.sync_mutations
  set status = 'error', error_message = 'forged', server_processed_at = now()
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot mark mutation error');
select throws_ok($$update public.sync_mutations set payload = '{"sale_price":1}'
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot change pending mutation intent');
select throws_ok($$update public.sync_mutations set metadata = '{"forged":true}'
  where id = '51000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'client cannot change pending mutation metadata');

select lives_ok($$update public.sync_batches set status = 'pending',
  mutation_count = 1, updated_at = now()
  where id = '51000000-0000-0000-0000-000000000006'$$,
  'unchanged pending batch retry UPDATE remains allowed');
select lives_ok($$update public.sync_mutations set status = 'pending',
  updated_at = now()
  where id = '51000000-0000-0000-0000-000000000007'$$,
  'unchanged pending mutation retry UPDATE remains allowed');

select ok(not has_function_privilege('authenticated',
  'private.create_sync_conflict_for_mutation(uuid,text,text,jsonb,text,jsonb)',
  'EXECUTE'), 'client cannot invoke private conflict-result helper');
select ok(not has_function_privilege('authenticated',
  'private.recalculate_sync_batch_counts(uuid)', 'EXECUTE'),
  'client cannot invoke private result-counter helper');
select ok(not has_function_privilege('authenticated',
  'private.apply_sync_purchase_mutation(uuid)', 'EXECUTE'),
  'client cannot directly invoke purchase applicator');
select ok(not has_function_privilege('authenticated',
  'private.apply_sync_cash_mutation(uuid)', 'EXECUTE'),
  'client cannot directly invoke cash applicator');
select lives_ok($$select public.process_sync_batch(
  '51000000-0000-0000-0000-000000000006', 'apply_catalog')$$,
  'authorized SECURITY DEFINER processor still applies pending batch');
reset role;
select ok((select sb.status = 'completed' and sm.status = 'applied'
  from public.sync_batches sb join public.sync_mutations sm
    on sm.sync_batch_id = sb.id
  where sb.id = '51000000-0000-0000-0000-000000000006'),
  'backend alone transitions batch and mutation to completed/applied');
select is((select sale_price from public.products
  where id = '51000000-0000-0000-0000-000000000005'), 30::numeric,
  'processor applied the semantic product update');
set local role authenticated;
select set_config('request.jwt.claim.sub',
  '51000000-0000-0000-0000-000000000041', true);
with attempted as (
  update public.sync_batches set status = 'pending'
  where id = '51000000-0000-0000-0000-000000000006'
  returning id
) select is((select count(*) from attempted), 0::bigint,
  'other business user cannot update tenant batch');
reset role;

select * from finish();
rollback;
