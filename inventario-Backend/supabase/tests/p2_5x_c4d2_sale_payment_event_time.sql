begin;
set local timezone = 'UTC';
select plan(21);

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values (md5('et-owner')::uuid, 'authenticated', 'authenticated',
  'et-owner@example.test', '{}', '{}');
insert into public.profiles (id, full_name, status)
values (md5('et-owner')::uuid, 'Event Time Owner', 'active');
insert into public.businesses (id, name, status)
values (md5('et-business')::uuid, 'Event Time Business', 'active');
insert into public.branches (id, business_id, name, status)
values (md5('et-branch')::uuid, md5('et-business')::uuid, 'Principal', 'active');
insert into public.business_members (business_id, branch_id, profile_id, role_id, status)
select md5('et-business')::uuid, null, md5('et-owner')::uuid, id, 'active'
from public.roles where name = 'owner' and business_id is null
  and is_system_role and deleted_at is null;
insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
) values (
  md5('et-device')::uuid, md5('et-business')::uuid, md5('et-owner')::uuid,
  md5('et-branch')::uuid, 'event-time-device', 'active'
);
insert into public.sales (id, business_id, branch_id, total, status)
select md5('et-sale-' || n)::uuid, md5('et-business')::uuid,
  md5('et-branch')::uuid, 25, 'completed'
from generate_series(1, 3) n;
insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count, metadata
)
select md5('et-batch-' || n)::uuid, md5('et-business')::uuid,
  md5('et-device')::uuid, md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-' || n, 'upload', 'pending', 1, '{"domain":"pos"}'::jsonb
from generate_series(1, 3) n;

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key, created_at
)
select md5('et-mutation-' || n)::uuid, md5('et-business')::uuid,
  md5('et-batch-' || n)::uuid, md5('et-device')::uuid,
  md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-payment-' || n, 1, 'sale_payments',
  md5('et-payment-' || n)::uuid, 'insert',
  jsonb_build_object(
    'sale_id', md5('et-sale-' || n)::uuid,
    'payment_method', case when n = 3 then 'card' else 'cash' end,
    'amount', 25,
    'status', 'completed',
    'payment_event_time_contract', 'v1',
    'paid_at', case when n = 1 then '2026-11-01T04:58:00Z'
      when n = 2 then '2026-10-05T17:00:00Z'
      else '2026-11-01T05:00:00Z' end,
    'created_at', case when n = 1 then '2026-11-01T04:58:00Z'
      when n = 2 then '2026-10-05T17:00:00Z'
      else '2026-11-01T05:00:00Z' end
  ), 'pending', 'event-time-payment-' || n,
  '2026-11-01T13:15:00Z'::timestamptz
from generate_series(1, 3) n;

select throws_ok($$
  insert into public.sync_mutations (
    id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
    client_mutation_id, client_sequence, entity_table, entity_id, operation,
    payload, status, idempotency_key
  ) values (
    md5('et-invalid-missing')::uuid, md5('et-business')::uuid,
    md5('et-batch-1')::uuid, md5('et-device')::uuid,
    md5('et-owner')::uuid, md5('et-branch')::uuid,
    'et-invalid-missing', 2, 'sale_payments', md5('et-invalid-missing')::uuid,
    'insert', '{"payment_event_time_contract":"v1","created_at":"2026-10-31T23:58:00Z"}',
    'pending', 'et-invalid-missing'
  )
$$, '22023', 'Sale payment event time must be explicit UTC',
  'ET-01 new contract rejects missing paid_at');
select throws_ok($$
  insert into public.sync_mutations (
    id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
    client_mutation_id, client_sequence, entity_table, entity_id, operation,
    payload, status, idempotency_key
  ) values (
    md5('et-invalid-different')::uuid, md5('et-business')::uuid,
    md5('et-batch-1')::uuid, md5('et-device')::uuid,
    md5('et-owner')::uuid, md5('et-branch')::uuid,
    'et-invalid-different', 2, 'sale_payments', md5('et-invalid-different')::uuid,
    'insert', '{"payment_event_time_contract":"v1","paid_at":"2026-10-31T23:58:00Z","created_at":"2026-11-01T00:00:00Z"}',
    'pending', 'et-invalid-different'
  )
$$, '22023', 'Sale payment event time differs from local creation time',
  'ET-02 new contract rejects mismatched event time');

set local role authenticated;
select set_config('request.jwt.claim.sub', md5('et-owner')::uuid::text, true);
select is((public.process_sync_batch(md5('et-batch-1')::uuid, 'apply_pos') ->> 'status'),
  'completed', 'ET-03 delayed October cash payment applies');
select is((select paid_at from public.sale_payments
  where id = md5('et-payment-1')::uuid),
  '2026-11-01 04:58:00'::timestamp,
  'ET-04 persisted paid_at is event time, not mutation receipt time');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-10-01T05:00:00Z', '2026-11-01T05:00:00Z')),
  '2500', 'ET-05 Oct 31 local cash belongs to October');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-11-01T05:00:00Z', '2026-12-01T05:00:00Z')),
  '0', 'ET-06 delayed sync does not move October cash into November');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-11-01T04:58:00Z', '2026-11-01T05:00:00Z')),
  '2500', 'ET-07 exact lower bound is inclusive');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-10-01T05:00:00Z', '2026-11-01T04:58:00Z')),
  '0', 'ET-08 exact upper bound is exclusive');
select is((public.process_sync_batch(md5('et-batch-1')::uuid, 'apply_pos') ->> 'status'),
  'completed', 'ET-09 retry returns canonical finalized batch');
select is((select count(*)::int from public.sale_payments
  where id = md5('et-payment-1')::uuid), 1,
  'ET-10 retry leaves exactly one payment');
select is((select paid_at from public.sale_payments
  where id = md5('et-payment-1')::uuid),
  '2026-11-01 04:58:00'::timestamp,
  'ET-11 retry retains original paid_at');
select is((public.process_sync_batch(md5('et-batch-2')::uuid, 'apply_pos') ->> 'status'),
  'completed', 'ET-12 day-5 payment applies after delayed upload');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-10-05T17:00:00Z', '2026-10-05T17:01:00Z')),
  '2500', 'ET-13 day-5 payment stays on day 5');
select is((public.process_sync_batch(md5('et-batch-3')::uuid, 'apply_pos') ->> 'status'),
  'completed', 'ET-14 noncash payment still applies');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('et-business')::uuid, md5('et-branch')::uuid,
  '2026-11-01T05:00:00Z', '2026-12-01T05:00:00Z')),
  '0', 'ET-15 card does not affect cash report');

reset role;
select throws_ok($$
  update public.sale_payments set paid_at = '2026-11-01 04:59:00'
  where id = md5('et-payment-1')::uuid
$$, '23514', 'sale_payments.paid_at is immutable',
  'ET-16 direct update cannot rewrite payment event time');

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count, metadata
) values (
  md5('et-batch-upsert')::uuid, md5('et-business')::uuid,
  md5('et-device')::uuid, md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-upsert', 'upload', 'pending', 1, '{"domain":"pos"}'::jsonb
);
insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
) values (
  md5('et-mutation-upsert')::uuid, md5('et-business')::uuid,
  md5('et-batch-upsert')::uuid, md5('et-device')::uuid,
  md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-upsert', 1, 'sale_payments', md5('et-payment-1')::uuid,
  'upsert', jsonb_build_object(
    'sale_id', md5('et-sale-1')::uuid,
    'payment_method', 'cash', 'amount', 25, 'status', 'completed',
    'payment_event_time_contract', 'v1',
    'paid_at', '2026-11-01T04:59:00Z',
    'created_at', '2026-11-01T04:59:00Z'
  ), 'pending', 'event-time-upsert'
);
set local role authenticated;
select is((public.process_sync_batch(md5('et-batch-upsert')::uuid, 'apply_pos') ->> 'status'),
  'failed', 'ET-17 same payment identity with different event time fails closed');
select is((select paid_at from public.sale_payments
  where id = md5('et-payment-1')::uuid),
  '2026-11-01 04:58:00'::timestamp,
  'ET-18 rejected upsert did not alter canonical time');
reset role;

select throws_ok($$
  insert into public.sync_mutations (
    id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
    client_mutation_id, client_sequence, entity_table, entity_id, operation,
    payload, status, idempotency_key
  ) values (
    md5('et-invalid-format')::uuid, md5('et-business')::uuid,
    md5('et-batch-1')::uuid, md5('et-device')::uuid,
    md5('et-owner')::uuid, md5('et-branch')::uuid,
    'et-invalid-format', 2, 'sale_payments', md5('et-invalid-format')::uuid,
    'insert', '{"payment_event_time_contract":"v1","paid_at":"2026-10-31 23:58:00","created_at":"2026-10-31 23:58:00"}',
    'pending', 'et-invalid-format'
  )
$$, '22023', 'Sale payment event time must be explicit UTC',
  'ET-19 non-UTC event timestamp is rejected');

insert into public.sales (id, business_id, branch_id, total, status)
values (md5('et-sale-legacy')::uuid, md5('et-business')::uuid,
  md5('et-branch')::uuid, 10, 'completed');
insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count, metadata
) values (
  md5('et-batch-legacy')::uuid, md5('et-business')::uuid,
  md5('et-device')::uuid, md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-legacy', 'upload', 'pending', 1, '{"domain":"pos"}'::jsonb
);
insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
) values (
  md5('et-mutation-legacy')::uuid, md5('et-business')::uuid,
  md5('et-batch-legacy')::uuid, md5('et-device')::uuid,
  md5('et-owner')::uuid, md5('et-branch')::uuid,
  'event-time-legacy', 1, 'sale_payments', md5('et-payment-legacy')::uuid,
  'insert', jsonb_build_object('sale_id', md5('et-sale-legacy')::uuid,
    'payment_method', 'cash', 'amount', 10), 'pending', 'event-time-legacy'
);
set local role authenticated;
select is((public.process_sync_batch(md5('et-batch-legacy')::uuid, 'apply_pos') ->> 'status'),
  'completed', 'ET-20 unmarked legacy mutation remains compatible');
select ok((select paid_at is not null from public.sale_payments
  where id = md5('et-payment-legacy')::uuid),
  'ET-21 legacy row retains its historical server-time behavior');

select * from finish();
rollback;
