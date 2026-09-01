begin;

select plan(3);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'da100000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'discard-owner@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'da100000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'discard-outsider@example.test', '', now(),
    '{}', '{}', now(), now()
  );

insert into public.profiles (id, full_name, role, status)
values
  ('da100000-0000-0000-0000-000000000001', 'Discard Owner', 'owner', 'active'),
  ('da100000-0000-0000-0000-000000000002', 'Discard Outsider', 'cashier', 'active');

insert into public.businesses (id, name, status)
values ('da100000-0000-0000-0000-000000000101', 'Discard Business', 'active');

insert into public.branches (id, business_id, name, status)
values (
  'da100000-0000-0000-0000-000000000111',
  'da100000-0000-0000-0000-000000000101',
  'Principal',
  'active'
);

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values (
  'da100000-0000-0000-0000-000000000121',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000001',
  null,
  (
    select id
    from public.roles
    where business_id is null and name = 'owner' and deleted_at is null
    limit 1
  ),
  'active',
  null
);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values (
  'da100000-0000-0000-0000-000000000131',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000001',
  'da100000-0000-0000-0000-000000000111',
  'verify-discard-device',
  'active'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count
)
values (
  'da100000-0000-0000-0000-000000000141',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000131',
  'da100000-0000-0000-0000-000000000001',
  'da100000-0000-0000-0000-000000000111',
  'verify-discard-batch',
  'upload',
  'pending',
  1
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values (
  'da100000-0000-0000-0000-000000000151',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000141',
  'da100000-0000-0000-0000-000000000131',
  'da100000-0000-0000-0000-000000000001',
  'da100000-0000-0000-0000-000000000111',
  'verify-discard-mutation',
  1,
  'sales',
  'da100000-0000-0000-0000-000000000201',
  'insert',
  '{}',
  'pending',
  'verify-discard-mutation'
);

insert into public.sync_conflicts (
  id, business_id, sync_batch_id, sync_mutation_id, app_device_id,
  profile_id, branch_id, entity_table, entity_id, operation,
  client_mutation_id, client_sequence, conflict_type, severity, status,
  client_payload, metadata
)
values (
  'da100000-0000-0000-0000-000000000161',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000141',
  'da100000-0000-0000-0000-000000000151',
  'da100000-0000-0000-0000-000000000131',
  'da100000-0000-0000-0000-000000000001',
  'da100000-0000-0000-0000-000000000111',
  'sales',
  'da100000-0000-0000-0000-000000000201',
  'insert',
  'verify-discard-mutation',
  1,
  'business_rule_violation',
  'high',
  'open',
  '{}',
  '{"rule":"sale_cash_session_invalid","reason":"closed"}'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'da100000-0000-0000-0000-000000000001',
  true
);

select is(
  public.verify_unmaterialized_sale_discard(
    'da100000-0000-0000-0000-000000000101',
    'da100000-0000-0000-0000-000000000111',
    'da100000-0000-0000-0000-000000000201'
  ),
  jsonb_build_object(
    'business_id', 'da100000-0000-0000-0000-000000000101'::uuid,
    'branch_id', 'da100000-0000-0000-0000-000000000111'::uuid,
    'sale_id', 'da100000-0000-0000-0000-000000000201'::uuid,
    'safe_to_discard', true,
    'sale_exists', false,
    'items_exist', false,
    'payments_exist', false,
    'movements_exist', false,
    'expected_conflict_exists', true,
    'conflict_reasons', '["closed"]'::jsonb
  ),
  '1. expected rejection with no remote materialization is safe to discard'
);

reset role;

insert into public.sales (
  id, business_id, branch_id, total, payment_method, status
)
values (
  'da100000-0000-0000-0000-000000000201',
  'da100000-0000-0000-0000-000000000101',
  'da100000-0000-0000-0000-000000000111',
  1,
  'cash',
  'completed'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'da100000-0000-0000-0000-000000000001',
  true
);

select ok(
  not (
    public.verify_unmaterialized_sale_discard(
      'da100000-0000-0000-0000-000000000101',
      'da100000-0000-0000-0000-000000000111',
      'da100000-0000-0000-0000-000000000201'
    ) ->> 'safe_to_discard'
  )::boolean
  and (
    public.verify_unmaterialized_sale_discard(
      'da100000-0000-0000-0000-000000000101',
      'da100000-0000-0000-0000-000000000111',
      'da100000-0000-0000-0000-000000000201'
    ) ->> 'sale_exists'
  )::boolean,
  '2. any remote Sale evidence fails closed'
);

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'da100000-0000-0000-0000-000000000002',
  true
);

select throws_ok(
  $$select public.verify_unmaterialized_sale_discard(
      'da100000-0000-0000-0000-000000000101',
      'da100000-0000-0000-0000-000000000111',
      'da100000-0000-0000-0000-000000000201'
    )$$,
  '42501',
  'Operational context is not available',
  '3. cross-tenant caller is denied without remote evidence leakage'
);

select * from finish();
rollback;
