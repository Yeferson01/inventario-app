begin;
select plan(49);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('52000000-0000-0000-0000-000000000001', 'authenticated',
  'authenticated', 's1a@example.test', '', now(), '{}', '{}', now(), now()),
  ('52000000-0000-0000-0000-000000000041', 'authenticated',
  'authenticated', 's1a-other@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status) values
  ('52000000-0000-0000-0000-000000000001', 'S1A', 'active'),
  ('52000000-0000-0000-0000-000000000041', 'S1A Other', 'active');
insert into public.businesses (id, name, status) values
  ('52000000-0000-0000-0000-000000000002', 'S1A', 'active'),
  ('52000000-0000-0000-0000-000000000042', 'S1A Other', 'active');
insert into public.branches (id, business_id, name, status) values
  ('52000000-0000-0000-0000-000000000003',
   '52000000-0000-0000-0000-000000000002', 'S1A', 'active'),
  ('52000000-0000-0000-0000-000000000013',
   '52000000-0000-0000-0000-000000000002', 'S1A B', 'active'),
  ('52000000-0000-0000-0000-000000000043',
   '52000000-0000-0000-0000-000000000042', 'S1A Other', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '52000000-0000-0000-0000-000000000011',
  '52000000-0000-0000-0000-000000000002',
  '52000000-0000-0000-0000-000000000001', null, id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '52000000-0000-0000-0000-000000000044',
  '52000000-0000-0000-0000-000000000042',
  '52000000-0000-0000-0000-000000000041', null, id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values
  ('52000000-0000-0000-0000-000000000004',
   '52000000-0000-0000-0000-000000000002',
   '52000000-0000-0000-0000-000000000001', null, 's1a-device', 'active'),
  ('52000000-0000-0000-0000-000000000045',
   '52000000-0000-0000-0000-000000000042',
   '52000000-0000-0000-0000-000000000041', null, 's1a-other-device', 'active');
insert into public.products (id, business_id, name, sale_price, purchase_price,
  stock_quantity, minimum_stock) values ('52000000-0000-0000-0000-000000000005',
  '52000000-0000-0000-0000-000000000002', 'S1A Product', 20, 10, 0, 0);

select set_config('s1a.batch',
  '{"id":"52000000-0000-0000-0000-000000000006","business_id":"52000000-0000-0000-0000-000000000002","app_device_id":"52000000-0000-0000-0000-000000000004","profile_id":"52000000-0000-0000-0000-000000000001","branch_id":"52000000-0000-0000-0000-000000000003","client_batch_id":"s1a-batch","direction":"upload","status":"pending","mutation_count":1,"metadata":{"source":"s1a-test"}}', true);
select set_config('s1a.mutation',
  '{"id":"52000000-0000-0000-0000-000000000007","business_id":"52000000-0000-0000-0000-000000000002","sync_batch_id":"52000000-0000-0000-0000-000000000006","app_device_id":"52000000-0000-0000-0000-000000000004","profile_id":"52000000-0000-0000-0000-000000000001","branch_id":"52000000-0000-0000-0000-000000000003","client_mutation_id":"s1a-mutation","client_sequence":1,"entity_table":"products","entity_id":"52000000-0000-0000-0000-000000000005","operation":"update","payload":{"sale_price":30},"status":"pending","idempotency_key":"s1a-key","metadata":{"source":"s1a-test"}}', true);

set local role authenticated;
select set_config('request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000001', true);

select throws_ok($$insert into public.sync_batches (id, business_id,
  app_device_id, profile_id, branch_id, client_batch_id)
  values ('52000000-0000-0000-0000-000000000020',
  '52000000-0000-0000-0000-000000000002',
  '52000000-0000-0000-0000-000000000004',
  '52000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000003', 'old-upsert')
  on conflict (business_id, app_device_id, client_batch_id)
  do update set status = 'pending'$$, '42P10', null,
  'old plain batch ON CONFLICT cannot infer the partial index');

select is(public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000006',
  'batch registration returns canonical id');
select is((select status from public.sync_batches
  where id = '52000000-0000-0000-0000-000000000006'), 'pending',
  'new batch is pending');
select is(public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"id":"52000000-0000-0000-0000-000000000008"}'::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000006',
  'identical batch retry reuses canonical row despite new proposed id');
select is(public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000006',
  'identical batch retry also tolerates the same proposed row id');
select is((select count(*) from public.sync_batches
  where client_batch_id = 's1a-batch'), 1::bigint,
  'batch retry does not duplicate');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
  '{"branch_id":"52000000-0000-0000-0000-000000000013"}'::jsonb)$$,
  'P0001', 'sync_batch_idempotency_conflict',
  'same batch key with different branch is an explicit conflict');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb || '{"mutation_count":2}'::jsonb)$$,
  'P0001', 'sync_batch_idempotency_conflict',
  'same batch key with different mutation count is an explicit conflict');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"client_batch_id":"different-key"}'::jsonb)$$,
  'P0001', 'sync_batch_idempotency_conflict',
  'same row id with different batch key is an explicit conflict');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb || '{"status":"completed"}'::jsonb)$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'batch registration rejects forged terminal status');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"server_completed_at":"2026-09-26T00:00:00Z"}'::jsonb)$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'batch registration rejects forged completion timestamp');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"app_device_id":"52000000-0000-0000-0000-000000000045"}'::jsonb)$$,
  '42501', 'sync_batch_device_invalid',
  'other device cannot register this batch');
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"business_id":"52000000-0000-0000-0000-000000000042", "branch_id":"52000000-0000-0000-0000-000000000043"}'::jsonb)$$,
  '42501', 'sync_batch_scope_denied',
  'cross-business batch registration is denied');
select set_config('request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000041', true);
select throws_ok($$select public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
    '{"profile_id":"52000000-0000-0000-0000-000000000041"}'::jsonb)$$,
  '42501', 'sync_batch_scope_denied',
  'user without membership cannot register batch');
select set_config('request.jwt.claim.sub',
  '52000000-0000-0000-0000-000000000001', true);

select throws_ok($$insert into public.sync_mutations (id, business_id,
  sync_batch_id, app_device_id, profile_id, branch_id, client_mutation_id,
  client_sequence, entity_table, entity_id, operation, payload,
  idempotency_key) values ('52000000-0000-0000-0000-000000000021',
  '52000000-0000-0000-0000-000000000002',
  '52000000-0000-0000-0000-000000000006',
  '52000000-0000-0000-0000-000000000004',
  '52000000-0000-0000-0000-000000000001',
  '52000000-0000-0000-0000-000000000003', 'old-upsert', 3,
  'products', '52000000-0000-0000-0000-000000000005', 'update',
  '{}', 'old-upsert-key')
  on conflict (business_id, idempotency_key)
  do update set status = 'pending'$$, '42P10', null,
  'old plain mutation ON CONFLICT cannot infer the partial index');
select is(public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000007',
  'mutation registration returns canonical id');
select is((select status from public.sync_mutations
  where id = '52000000-0000-0000-0000-000000000007'), 'pending',
  'new mutation is pending');
select is(public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"id":"52000000-0000-0000-0000-000000000009"}'::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000007',
  'identical mutation retry reuses canonical row');
select is(public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb) ->> 'id',
  '52000000-0000-0000-0000-000000000007',
  'identical mutation retry also tolerates the same proposed row id');
select is((select count(*) from public.sync_mutations
  where idempotency_key = 's1a-key'), 1::bigint,
  'mutation retry does not duplicate');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"payload":{"sale_price":1}}'::jsonb)$$,
  'P0001', 'sync_mutation_idempotency_conflict',
  'same key with different semantic payload is rejected');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"client_sequence":2}'::jsonb)$$,
  'P0001', 'sync_mutation_idempotency_conflict',
  'same key with different sequence is rejected');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"id":"52000000-0000-0000-0000-000000000012", "idempotency_key":"different-key"}'::jsonb)$$,
  'P0001', 'sync_mutation_idempotency_conflict',
  'same client mutation identity with different idempotency key is rejected');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb || '{"status":"applied"}'::jsonb)$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'mutation registration rejects forged applied status');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"server_processed_at":"2026-09-26T00:00:00Z"}'::jsonb)$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'mutation registration rejects forged result timestamp');
select throws_ok($$update public.sync_mutations
  set status = 'applied', server_processed_at = now()
  where id = '52000000-0000-0000-0000-000000000007'$$,
  '42501', 'sync_mutation_result_is_backend_owned',
  'S1 still denies client mutation promotion');
select throws_ok($$update public.sync_batches set status = 'completed',
  server_completed_at = now()
  where id = '52000000-0000-0000-0000-000000000006'$$,
  '42501', 'sync_batch_state_is_backend_owned',
  'S1 still denies client batch completion');
select is(public.process_sync_batch(
  '52000000-0000-0000-0000-000000000006', 'apply_catalog') ->> 'status',
  'completed', 'processor completes registered intent');
select is((select sale_price from public.products
  where id = '52000000-0000-0000-0000-000000000005'), 30::numeric,
  'processor applied registered mutation');
select is(public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb) ->> 'status', 'completed',
  'network-style retry preserves completed batch');
select is(public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb) ->> 'status', 'applied',
  'network-style retry preserves applied mutation');
select is(public.process_sync_batch(
  '52000000-0000-0000-0000-000000000006', 'apply_catalog') ->> 'status',
  'completed', 'network-style process retry preserves completed result');
select throws_ok($$select public.register_pending_sync_mutation(
  current_setting('s1a.mutation')::jsonb ||
    '{"id":"52000000-0000-0000-0000-000000000010", "idempotency_key":"new-after-close","client_mutation_id":"new-after-close"}'::jsonb)$$,
  'P0001', 'sync_batch_not_pending_for_registration',
  'new mutation cannot enter completed batch');
select is((select count(*) from public.sync_batches
  where client_batch_id = 's1a-batch'), 1::bigint,
  'one durable batch after processing and retry');
select is((select count(*) from public.sync_mutations
  where sync_batch_id = '52000000-0000-0000-0000-000000000006'), 1::bigint,
  'one durable mutation after processing and retry');

select is(public.register_pending_sync_batch(
  current_setting('s1a.batch')::jsonb ||
  '{"id":"52000000-0000-0000-0000-000000000030", "client_batch_id":"s1a-bulk", "mutation_count":2}'::jsonb
  ) ->> 'status', 'pending', 'bulk fixture batch is pending');
select is(jsonb_array_length(public.register_pending_sync_mutations(
  jsonb_build_array(
    current_setting('s1a.mutation')::jsonb ||
      '{"id":"52000000-0000-0000-0000-000000000031", "sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-1", "client_mutation_id":"s1a-bulk-1"}'::jsonb,
    current_setting('s1a.mutation')::jsonb ||
      '{"id":"52000000-0000-0000-0000-000000000032", "sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-2", "client_mutation_id":"s1a-bulk-2", "client_sequence":2}'::jsonb
  ))), 2, 'bulk registration returns both mutations');
select is((select count(*) from public.sync_mutations
  where sync_batch_id = '52000000-0000-0000-0000-000000000030'), 2::bigint,
  'bulk registration persists exactly two mutations');
select is(jsonb_array_length(public.register_pending_sync_mutations(
  jsonb_build_array(
    current_setting('s1a.mutation')::jsonb ||
      '{"sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-1", "client_mutation_id":"s1a-bulk-1"}'::jsonb,
    current_setting('s1a.mutation')::jsonb ||
      '{"sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-2", "client_mutation_id":"s1a-bulk-2", "client_sequence":2}'::jsonb
  ))), 2, 'bulk retry returns both canonical mutations');
select throws_ok($$select public.register_pending_sync_mutations(
  jsonb_build_array(current_setting('s1a.mutation')::jsonb ||
    '{"sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-3", "client_mutation_id":"s1a-bulk-3", "client_sequence":3}'::jsonb,
    current_setting('s1a.mutation')::jsonb ||
    '{"sync_batch_id":"52000000-0000-0000-0000-000000000030", "idempotency_key":"s1a-bulk-1", "client_mutation_id":"s1a-bulk-1", "payload":{"sale_price":999}}'::jsonb))$$,
  'P0001', 'sync_mutation_idempotency_conflict',
  'bulk conflict rejects transaction atomically');
select is((select count(*) from public.sync_mutations
  where idempotency_key = 's1a-bulk-3'), 0::bigint,
  'failed bulk registration leaves no partial intent');

select is(public.register_pending_sync_batch(jsonb_build_object(
  'id', '52000000-0000-0000-0000-000000000060',
  'business_id', '52000000-0000-0000-0000-000000000002',
  'app_device_id', '52000000-0000-0000-0000-000000000004',
  'profile_id', '52000000-0000-0000-0000-000000000001',
  'branch_id', '52000000-0000-0000-0000-000000000003',
  'client_batch_id', 's1a-exact-purchase', 'direction', 'upload',
  'mutation_count', 2)) ->> 'status', 'pending',
  'exact purchase batch is registered as pending');
select is(jsonb_array_length(public.register_pending_sync_mutations(
  jsonb_build_array(
    jsonb_build_object(
      'id', '52000000-0000-0000-0000-000000000063',
      'business_id', '52000000-0000-0000-0000-000000000002',
      'sync_batch_id', '52000000-0000-0000-0000-000000000060',
      'app_device_id', '52000000-0000-0000-0000-000000000004',
      'profile_id', '52000000-0000-0000-0000-000000000001',
      'branch_id', '52000000-0000-0000-0000-000000000003',
      'client_mutation_id', 's1a-purchase-header', 'client_sequence', 1,
      'entity_table', 'purchases',
      'entity_id', '52000000-0000-0000-0000-000000000061',
      'operation', 'insert', 'idempotency_key', 's1a-purchase-header-key',
      'payload', jsonb_build_object(
        'branch_id', '52000000-0000-0000-0000-000000000003',
        'total', 5001, 'status', 'completed',
        'metadata', jsonb_build_object('monetary_contract_version', 'exact_v1',
          'item_count', 1, 'total_cents', '500100'))),
    jsonb_build_object(
      'id', '52000000-0000-0000-0000-000000000064',
      'business_id', '52000000-0000-0000-0000-000000000002',
      'sync_batch_id', '52000000-0000-0000-0000-000000000060',
      'app_device_id', '52000000-0000-0000-0000-000000000004',
      'profile_id', '52000000-0000-0000-0000-000000000001',
      'branch_id', '52000000-0000-0000-0000-000000000003',
      'client_mutation_id', 's1a-purchase-item', 'client_sequence', 2,
      'entity_table', 'purchase_items',
      'entity_id', '52000000-0000-0000-0000-000000000062',
      'operation', 'insert', 'idempotency_key', 's1a-purchase-item-key',
      'payload', jsonb_build_object(
        'purchase_id', '52000000-0000-0000-0000-000000000061',
        'product_id', '52000000-0000-0000-0000-000000000005',
        'quantity', 2, 'unit_cost', 2500.50, 'subtotal', 5001,
        'metadata', jsonb_build_object('unit_cost_cents', '250050',
          'subtotal_cents', '500100')))
  ))), 2, 'exact purchase header and item register as pending');
select is(public.process_sync_batch(
  '52000000-0000-0000-0000-000000000060', 'apply_purchases') ->> 'status',
  'completed', 'processor completes registered exact purchase');
select ok((select total_cents = 500100
  and financial_finalized_at is not null
  from public.purchases
  where id = '52000000-0000-0000-0000-000000000061'),
  'registered purchase has authoritative exact-money finalization');
select ok(not has_function_privilege('anon',
  'public.register_pending_sync_batch(jsonb)', 'EXECUTE'),
  'anon has no batch registration execute');
select ok(not has_function_privilege('anon',
  'public.register_pending_sync_mutation(jsonb)', 'EXECUTE'),
  'anon has no mutation registration execute');
select ok(not has_function_privilege('anon',
  'public.register_pending_sync_mutations(jsonb)', 'EXECUTE'),
  'anon has no bulk registration execute');
select ok(has_function_privilege('authenticated',
  'public.register_pending_sync_batch(jsonb)', 'EXECUTE'),
  'authenticated may register pending intent');

select * from finish();
rollback;
