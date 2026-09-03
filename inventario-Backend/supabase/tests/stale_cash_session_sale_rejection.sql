begin;

select plan(9);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  'd1000000-0000-0000-0000-000000000101',
  'authenticated', 'authenticated', 'stale-sale@example.test', '', now(),
  '{}', '{}', now(), now()
);

insert into public.profiles (id, full_name, role, status)
values (
  'd1000000-0000-0000-0000-000000000101',
  'Stale Sale Owner', 'owner', 'active'
);

insert into public.businesses (id, name, status)
values ('d1000000-0000-0000-0000-000000000001', 'Stale Sale', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('d1000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000001', 'Principal', 'active'),
  ('d1000000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000001', 'Secondary', 'active');

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values (
  'd1000000-0000-0000-0000-000000000041',
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000101',
  null,
  (
    select id from public.roles
    where business_id is null and name = 'owner' and deleted_at is null
    limit 1
  ),
  'active', null
);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values (
  'd1000000-0000-0000-0000-000000000051',
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000101',
  'd1000000-0000-0000-0000-000000000011',
  'stale-sale-device', 'active'
);

insert into public.cash_registers (id, business_id, branch_id, name, status)
values
  ('d1000000-0000-0000-0000-000000000061', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000011', 'Principal', 'active'),
  ('d1000000-0000-0000-0000-000000000062', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000012', 'Secondary', 'active');

insert into public.cash_sessions (
  id, business_id, branch_id, cash_register_id, opened_by,
  opening_amount, status, opened_at, closed_at
)
values
  ('d1000000-0000-0000-0000-000000000071', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000061', 'd1000000-0000-0000-0000-000000000101', 100, 'open', now(), null),
  ('d1000000-0000-0000-0000-000000000072', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000011', 'd1000000-0000-0000-0000-000000000061', 'd1000000-0000-0000-0000-000000000101', 100, 'closed', now() - interval '1 hour', now()),
  ('d1000000-0000-0000-0000-000000000073', 'd1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000012', 'd1000000-0000-0000-0000-000000000062', 'd1000000-0000-0000-0000-000000000101', 100, 'open', now(), null);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id, client_batch_id,
  direction, status, mutation_count
)
select
  ('d1000000-0000-0000-0000-00000000008' || suffix)::uuid,
  'd1000000-0000-0000-0000-000000000001',
  'd1000000-0000-0000-0000-000000000051',
  'd1000000-0000-0000-0000-000000000101',
  'd1000000-0000-0000-0000-000000000011',
  'stale-sale-' || suffix,
  'upload', 'pending', 1
from generate_series(1, 5) suffix;

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'd1000000-0000-0000-0000-000000000091',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000081',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000011',
    'stale-sale-valid', 1, 'sales',
    'd1000000-0000-0000-0000-000000000201', 'insert',
    '{"id":"d1000000-0000-0000-0000-000000000201","branch_id":"d1000000-0000-0000-0000-000000000011","cash_register_id":"d1000000-0000-0000-0000-000000000061","cash_session_id":"d1000000-0000-0000-0000-000000000071","total":10,"status":"completed"}',
    'pending', 'stale-sale-valid'
  ),
  (
    'd1000000-0000-0000-0000-000000000092',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000082',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000011',
    'stale-sale-closed', 1, 'sales',
    'd1000000-0000-0000-0000-000000000202', 'insert',
    '{"id":"d1000000-0000-0000-0000-000000000202","branch_id":"d1000000-0000-0000-0000-000000000011","cash_register_id":"d1000000-0000-0000-0000-000000000061","cash_session_id":"d1000000-0000-0000-0000-000000000072","total":10,"status":"completed"}',
    'pending', 'stale-sale-closed'
  ),
  (
    'd1000000-0000-0000-0000-000000000093',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000083',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000011',
    'stale-sale-register', 1, 'sales',
    'd1000000-0000-0000-0000-000000000203', 'insert',
    '{"id":"d1000000-0000-0000-0000-000000000203","branch_id":"d1000000-0000-0000-0000-000000000011","cash_register_id":"d1000000-0000-0000-0000-000000000062","cash_session_id":"d1000000-0000-0000-0000-000000000071","total":10,"status":"completed"}',
    'pending', 'stale-sale-register'
  ),
  (
    'd1000000-0000-0000-0000-000000000094',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000084',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000011',
    'stale-sale-branch', 1, 'sales',
    'd1000000-0000-0000-0000-000000000204', 'insert',
    '{"id":"d1000000-0000-0000-0000-000000000204","branch_id":"d1000000-0000-0000-0000-000000000011","cash_register_id":"d1000000-0000-0000-0000-000000000062","cash_session_id":"d1000000-0000-0000-0000-000000000073","total":10,"status":"completed"}',
    'pending', 'stale-sale-branch'
  ),
  (
    'd1000000-0000-0000-0000-000000000095',
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000085',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000101',
    'd1000000-0000-0000-0000-000000000011',
    'stale-sale-missing', 1, 'sales',
    'd1000000-0000-0000-0000-000000000205', 'insert',
    '{"id":"d1000000-0000-0000-0000-000000000205","branch_id":"d1000000-0000-0000-0000-000000000011","cash_register_id":"d1000000-0000-0000-0000-000000000061","cash_session_id":"d1000000-0000-0000-0000-000000000079","total":10,"status":"completed"}',
    'pending', 'stale-sale-missing'
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'd1000000-0000-0000-0000-000000000101',
  true
);

select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000081',
  'apply_pos'
);
select is(
  (
    select cash_session_id::text from public.sales
    where id = 'd1000000-0000-0000-0000-000000000201'
  ),
  'd1000000-0000-0000-0000-000000000071',
  '1. valid open scoped session is assigned directly to the Sale'
);

select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000082',
  'apply_pos'
);
select ok(
  not exists (
    select 1 from public.sales
    where id = 'd1000000-0000-0000-0000-000000000202'
  )
  and exists (
    select 1 from public.sync_conflicts
    where sync_mutation_id = 'd1000000-0000-0000-0000-000000000092'
      and conflict_type = 'business_rule_violation'
      and metadata ->> 'rule' = 'sale_cash_session_invalid'
      and metadata ->> 'reason' = 'closed'
      and status = 'open'
  ),
  '2. closed session rejects the Sale and persists a structured conflict'
);

select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000083',
  'apply_pos'
);
select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000084',
  'apply_pos'
);
select ok(
  (
    select metadata ->> 'reason' from public.sync_conflicts
    where sync_mutation_id = 'd1000000-0000-0000-0000-000000000093'
  ) = 'wrong_register'
  and (
    select metadata ->> 'reason' from public.sync_conflicts
    where sync_mutation_id = 'd1000000-0000-0000-0000-000000000094'
  ) = 'wrong_branch'
  and not exists (
    select 1 from public.sales
    where id in (
      'd1000000-0000-0000-0000-000000000203',
      'd1000000-0000-0000-0000-000000000204'
    )
  ),
  '3. wrong register and wrong branch are rejected without materializing Sales'
);

select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000085',
  'apply_pos'
);
select ok(
  not exists (
    select 1 from public.sales
    where id = 'd1000000-0000-0000-0000-000000000205'
  )
  and (
    select metadata ->> 'reason' from public.sync_conflicts
    where sync_mutation_id = 'd1000000-0000-0000-0000-000000000095'
  ) = 'missing',
  '4. invalid session reference never becomes a Sale with null cash_session_id'
);

select public.process_sync_batch(
  'd1000000-0000-0000-0000-000000000082',
  'apply_pos'
);
select is(
  (
    select count(*)::integer from public.sync_conflicts
    where sync_mutation_id = 'd1000000-0000-0000-0000-000000000092'
      and metadata ->> 'rule' = 'sale_cash_session_invalid'
  ),
  1,
  '5. retry preserves the same rejection without duplicate Sale or conflict'
);

select is(
  public.lookup_open_closed_cash_session_sale_conflict(
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000011',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000202'
  ) ->> 'status',
  'found',
  '6. historical lookup finds the unique scoped closed-session conflict'
);

select is(
  public.lookup_open_closed_cash_session_sale_conflict(
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000011',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000299'
  ) ->> 'status',
  'not_found',
  '7. historical lookup reports no evidence without exposing another Sale'
);

select throws_ok(
  $$select public.lookup_open_closed_cash_session_sale_conflict(
    'd1000000-0000-0000-0000-000000000001',
    'd1000000-0000-0000-0000-000000000012',
    'd1000000-0000-0000-0000-000000000051',
    'd1000000-0000-0000-0000-000000000202'
  )$$,
  '42501',
  'app_device is not active for this profile and branch',
  '8. historical lookup rejects a device outside the requested branch scope'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.lookup_open_closed_cash_session_sale_conflict(uuid,uuid,uuid,uuid)',
    'execute'
  ),
  '9. anon cannot execute the historical conflict lookup'
);

select * from finish();
rollback;
