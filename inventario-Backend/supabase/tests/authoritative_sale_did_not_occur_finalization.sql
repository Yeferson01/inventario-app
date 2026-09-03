begin;

select plan(4);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  'dd000000-0000-0000-0000-000000000001',
  'authenticated', 'authenticated', 'did-not-occur@example.test', '', now(),
  '{}', '{}', now(), now()
);

insert into public.profiles (id, full_name, role, status)
values (
  'dd000000-0000-0000-0000-000000000001',
  'Did Not Occur Owner', 'owner', 'active'
);

insert into public.businesses (id, name, status)
values (
  'dd000000-0000-0000-0000-000000000101',
  'Did Not Occur Business', 'active'
);

insert into public.branches (id, business_id, name, status)
values (
  'dd000000-0000-0000-0000-000000000111',
  'dd000000-0000-0000-0000-000000000101',
  'Principal', 'active'
);

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values (
  'dd000000-0000-0000-0000-000000000121',
  'dd000000-0000-0000-0000-000000000101',
  'dd000000-0000-0000-0000-000000000001',
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
  'dd000000-0000-0000-0000-000000000131',
  'dd000000-0000-0000-0000-000000000101',
  'dd000000-0000-0000-0000-000000000001',
  'dd000000-0000-0000-0000-000000000111',
  'did-not-occur-device', 'active'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count
)
values
  (
    'dd000000-0000-0000-0000-000000000141',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-a', 'upload', 'pending', 3
  ),
  (
    'dd000000-0000-0000-0000-000000000142',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-b', 'upload', 'pending', 1
  ),
  (
    'dd000000-0000-0000-0000-000000000143',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-d', 'upload', 'pending', 1
  );

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'dd000000-0000-0000-0000-000000000151',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000141',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-sale-a', 1, 'sales',
    'dd000000-0000-0000-0000-000000000201', 'insert',
    '{"id":"dd000000-0000-0000-0000-000000000201"}',
    'pending', 'did-not-occur-sale-a'
  ),
  (
    'dd000000-0000-0000-0000-000000000152',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000141',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-item-a', 2, 'sale_items',
    'dd000000-0000-0000-0000-000000000211', 'insert',
    '{"sale_id":"dd000000-0000-0000-0000-000000000201"}',
    'pending', 'did-not-occur-item-a'
  ),
  (
    'dd000000-0000-0000-0000-000000000153',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000141',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-payment-a', 3, 'sale_payments',
    'dd000000-0000-0000-0000-000000000221', 'insert',
    '{"sale_id":"dd000000-0000-0000-0000-000000000201"}',
    'pending', 'did-not-occur-payment-a'
  ),
  (
    'dd000000-0000-0000-0000-000000000154',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000142',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-sale-b', 1, 'sales',
    'dd000000-0000-0000-0000-000000000202', 'insert',
    '{"id":"dd000000-0000-0000-0000-000000000202"}',
    'pending', 'did-not-occur-sale-b'
  ),
  (
    'dd000000-0000-0000-0000-000000000155',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000143',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'did-not-occur-sale-d', 1, 'sales',
    'dd000000-0000-0000-0000-000000000203', 'insert',
    '{"id":"dd000000-0000-0000-0000-000000000203"}',
    'pending', 'did-not-occur-sale-d'
  );

insert into public.sync_conflicts (
  id, business_id, sync_batch_id, sync_mutation_id, app_device_id,
  profile_id, branch_id, entity_table, entity_id, operation,
  client_mutation_id, client_sequence, conflict_type, severity, status,
  client_payload, metadata
)
values
  (
    'dd000000-0000-0000-0000-000000000161',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000141',
    'dd000000-0000-0000-0000-000000000151',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'sales', 'dd000000-0000-0000-0000-000000000201', 'insert',
    'did-not-occur-sale-a', 1, 'business_rule_violation', 'high', 'open',
    '{}',
    '{"rule":"sale_cash_session_invalid","reason":"closed","sale_id":"dd000000-0000-0000-0000-000000000201"}'
  ),
  (
    'dd000000-0000-0000-0000-000000000162',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000142',
    'dd000000-0000-0000-0000-000000000154',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'sales', 'dd000000-0000-0000-0000-000000000202', 'insert',
    'did-not-occur-sale-b', 1, 'business_rule_violation', 'high', 'open',
    '{}',
    '{"rule":"sale_cash_session_invalid","reason":"closed","sale_id":"dd000000-0000-0000-0000-000000000202"}'
  ),
  (
    'dd000000-0000-0000-0000-000000000163',
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000143',
    'dd000000-0000-0000-0000-000000000155',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000001',
    'dd000000-0000-0000-0000-000000000111',
    'sales', 'dd000000-0000-0000-0000-000000000203', 'insert',
    'did-not-occur-sale-d', 1, 'business_rule_violation', 'high', 'open',
    '{}',
    '{"rule":"sale_cash_session_invalid","reason":"closed","sale_id":"dd000000-0000-0000-0000-000000000203"}'
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'dd000000-0000-0000-0000-000000000001',
  true
);

select public.resolve_unmaterialized_sale_did_not_occur(
  'dd000000-0000-0000-0000-000000000101',
  'dd000000-0000-0000-0000-000000000111',
  'dd000000-0000-0000-0000-000000000131',
  'dd000000-0000-0000-0000-000000000201',
  'dd000000-0000-0000-0000-000000000161',
  'did-not-occur:a',
  'The Sale did not occur.'
);

reset role;

select ok(
  not exists (
    select 1 from public.sales
    where id = 'dd000000-0000-0000-0000-000000000201'
  )
  and (
    select status = 'resolved'
      and resolution_strategy = 'sale_did_not_occur'
      and metadata ->> 'sale_did_not_occur' = 'true'
    from public.sync_conflicts
    where id = 'dd000000-0000-0000-0000-000000000161'
  )
  and (
    select count(*) = 3
    from public.sync_mutations
    where sync_batch_id = 'dd000000-0000-0000-0000-000000000141'
      and status = 'skipped'
  )
  and exists (
    select 1 from public.activity_logs
    where record_id = 'dd000000-0000-0000-0000-000000000161'
      and action = 'SALE_DID_NOT_OCCUR_CONFIRMED'
  )
  and not has_function_privilege(
    'anon',
    'public.resolve_unmaterialized_sale_did_not_occur(uuid,uuid,uuid,uuid,uuid,text,text)',
    'execute'
  ),
  'A. valid did-not-occur finalization resolves the conflict without creating a Sale'
);

insert into public.sales (
  id, business_id, branch_id, total, payment_method, status
)
values (
  'dd000000-0000-0000-0000-000000000202',
  'dd000000-0000-0000-0000-000000000101',
  'dd000000-0000-0000-0000-000000000111',
  1, 'cash', 'completed'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'dd000000-0000-0000-0000-000000000001',
  true
);

select throws_ok(
  $$select public.resolve_unmaterialized_sale_did_not_occur(
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000111',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000202',
    'dd000000-0000-0000-0000-000000000162',
    'did-not-occur:b',
    'The Sale did not occur.'
  )$$,
  '23514',
  'Remote Sale evidence exists; did-not-occur finalization rejected',
  'B. any remote Sale evidence rejects finalization and leaves the conflict open'
);

select is(
  (
    public.resolve_unmaterialized_sale_did_not_occur(
      'dd000000-0000-0000-0000-000000000101',
      'dd000000-0000-0000-0000-000000000111',
      'dd000000-0000-0000-0000-000000000131',
      'dd000000-0000-0000-0000-000000000201',
      'dd000000-0000-0000-0000-000000000161',
      'did-not-occur:a',
      'The Sale did not occur.'
    ) ->> 'idempotent'
  )::boolean,
  true,
  'C. an identical retry returns the existing authoritative decision'
);

reset role;

update public.sync_conflicts
set
  status = 'resolved',
  resolved_at = now(),
  resolution_strategy = 'reconcile_to_open_cash_session'
where id = 'dd000000-0000-0000-0000-000000000163';

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'dd000000-0000-0000-0000-000000000001',
  true
);

select throws_ok(
  $$select public.resolve_unmaterialized_sale_did_not_occur(
    'dd000000-0000-0000-0000-000000000101',
    'dd000000-0000-0000-0000-000000000111',
    'dd000000-0000-0000-0000-000000000131',
    'dd000000-0000-0000-0000-000000000203',
    'dd000000-0000-0000-0000-000000000163',
    'did-not-occur:d',
    'The Sale did not occur.'
  )$$,
  '23505',
  'Sale conflict was already resolved by another decision',
  'D. a real-Sale reconciliation decision cannot become did-not-occur'
);

select * from finish();
rollback;
