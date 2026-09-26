-- C2 fixtures are local-only and rolled back with the pgTAP transaction.
begin;
select plan(46);

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values (md5('c2-owner')::uuid, 'authenticated', 'authenticated',
  'c2-owner@example.test', '{}', '{}');
insert into public.profiles (id, full_name, status)
values (md5('c2-owner')::uuid, 'C2 owner', 'active');
insert into public.businesses (id, name, status)
values (md5('c2-business')::uuid, 'C2', 'active'),
  (md5('c2-other-business')::uuid, 'Other', 'active');
insert into public.branches (id, business_id, name, status)
values (md5('c2-branch')::uuid, md5('c2-business')::uuid, 'Main', 'active'),
  (md5('c2-other-branch')::uuid, md5('c2-other-business')::uuid, 'Other', 'active');
insert into public.business_members (business_id, branch_id, profile_id, role_id, status)
select md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-owner')::uuid, id, 'active'
from public.roles where name = 'owner' and business_id is null
  and is_system_role and deleted_at is null;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status)
values (md5('c2-device')::uuid, md5('c2-business')::uuid,
  md5('c2-owner')::uuid, md5('c2-branch')::uuid, 'c2-installation', 'active');
insert into public.cash_registers (id, business_id, branch_id, name, status)
values (md5('c2-register')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, 'C2 Register', 'active');
insert into public.cash_sessions (id, business_id, branch_id, cash_register_id,
  opened_by, opening_amount, status)
values (md5('c2-session')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-register')::uuid,
  md5('c2-owner')::uuid, 100, 'open');

insert into public.sync_batches (id, business_id, branch_id, app_device_id,
  profile_id, client_batch_id, direction, status, mutation_count)
values (md5('c2-batch')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, 'c2-batch', 'upload', 'pending', 2),
  (md5('c2-late-batch')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, 'c2-late-batch', 'upload', 'pending', 1);

create function pg_temp.c2_payload(p_name text, p_direction text,
  p_category text, p_amount text) returns jsonb language sql as $$
  select jsonb_build_object(
    'id', md5(p_name)::uuid,
    'business_id', md5('c2-business')::uuid,
    'branch_id', md5('c2-branch')::uuid,
    'cash_register_id', md5('c2-register')::uuid,
    'cash_session_id', md5('c2-session')::uuid,
    'direction', p_direction, 'category', p_category,
    'amount', p_amount, 'currency', 'COP',
    'source_type', 'manual', 'source_id', null,
    'note', null, 'occurred_at', '2026-09-26T12:00:00Z',
    'idempotency_key', p_name, 'metadata', '{}'::jsonb);
$$;
insert into public.sync_mutations (id, business_id, branch_id, app_device_id,
  profile_id, sync_batch_id, client_mutation_id, client_sequence, entity_table,
  entity_id, operation, payload, status, idempotency_key)
values
  (md5('c2-out-mut')::uuid, md5('c2-business')::uuid,
   md5('c2-branch')::uuid, md5('c2-device')::uuid,
   md5('c2-owner')::uuid, md5('c2-batch')::uuid,
   'c2-out-mut', 1, 'cash_movements', md5('c2-out')::uuid,
   'insert', pg_temp.c2_payload('c2-out', 'outflow', 'utilities', '20.00'),
   'pending', 'c2-out'),
  (md5('c2-in-mut')::uuid, md5('c2-business')::uuid,
   md5('c2-branch')::uuid, md5('c2-device')::uuid,
   md5('c2-owner')::uuid, md5('c2-batch')::uuid,
   'c2-in-mut', 2, 'cash_movements', md5('c2-in')::uuid,
   'insert', pg_temp.c2_payload('c2-in', 'inflow', 'owner_contribution', '5.25'),
   'pending', 'c2-in'),
  (md5('c2-late-mut')::uuid, md5('c2-business')::uuid,
   md5('c2-branch')::uuid, md5('c2-device')::uuid,
   md5('c2-owner')::uuid, md5('c2-late-batch')::uuid,
   'c2-late-mut', 1, 'cash_movements', md5('c2-late')::uuid,
   'insert', pg_temp.c2_payload('c2-late', 'outflow', 'utilities', '1.00'),
   'pending', 'c2-late');

insert into public.roles (id, business_id, name)
values (md5('c2-receive-role')::uuid, md5('c2-business')::uuid, 'C2 receive'),
  (md5('c2-disburse-role')::uuid, md5('c2-business')::uuid, 'C2 disburse');
insert into public.role_permissions (role_id, permission_id)
select md5('c2-receive-role')::uuid, id from public.permissions
where key = 'cash.receive';
insert into public.role_permissions (role_id, permission_id)
select md5('c2-disburse-role')::uuid, id from public.permissions
where key = 'cash.disburse';
insert into public.sync_batches (id, business_id, branch_id, app_device_id,
  profile_id, client_batch_id, direction, status, mutation_count)
select md5(name)::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, name, 'upload', 'pending', 1
from (values ('c2-receive-in'), ('c2-receive-out'),
  ('c2-disburse-in'), ('c2-disburse-out'), ('c2-cashier-out')) as cases(name);
insert into public.sync_mutations (id, business_id, branch_id, app_device_id,
  profile_id, sync_batch_id, client_mutation_id, client_sequence,
  entity_table, entity_id, operation, payload, status, idempotency_key)
select md5(name || '-mutation')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, md5(name)::uuid, name, 1,
  'cash_movements', md5(name)::uuid, 'insert',
  pg_temp.c2_payload(name, direction, category, '1.00'), 'pending', name
from (values
  ('c2-receive-in', 'inflow', 'other_income'),
  ('c2-receive-out', 'outflow', 'utilities'),
  ('c2-disburse-in', 'inflow', 'other_income'),
  ('c2-disburse-out', 'outflow', 'utilities'),
  ('c2-cashier-out', 'outflow', 'utilities'))
  as cases(name, direction, category);
insert into public.sync_batches (id, business_id, branch_id, app_device_id,
  profile_id, client_batch_id, direction, status, mutation_count)
values (md5('c2-invalid-batch')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, 'c2-invalid-batch', 'upload', 'pending', 10);
insert into public.sync_mutations (id, business_id, branch_id, app_device_id,
  profile_id, sync_batch_id, client_mutation_id, client_sequence,
  entity_table, entity_id, operation, payload, status, idempotency_key)
select md5(name || '-mutation')::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-device')::uuid,
  md5('c2-owner')::uuid, md5('c2-invalid-batch')::uuid, name, ordinal,
  'cash_movements', md5(name)::uuid, 'insert',
  pg_temp.c2_payload(name, 'outflow', 'utilities', '1.00') || patch,
  'pending', name
from (values
  ('c2-zero', '{"amount":"0"}'::jsonb, 1),
  ('c2-negative', '{"amount":"-1.00"}'::jsonb, 2),
  ('c2-direction', '{"direction":"sideways"}'::jsonb, 3),
  ('c2-category', '{"category":"invalid"}'::jsonb, 4),
  ('c2-incompatible', '{"direction":"inflow"}'::jsonb, 5),
  ('c2-wrong-business', jsonb_build_object(
    'business_id', md5('c2-other-business')::uuid), 6),
  ('c2-wrong-branch', jsonb_build_object(
    'branch_id', md5('c2-other-branch')::uuid), 7),
  ('c2-wrong-register', jsonb_build_object(
    'cash_register_id', md5('c2-missing-register')::uuid), 8),
  ('c2-wrong-session', jsonb_build_object(
    'cash_session_id', md5('c2-missing-session')::uuid), 9),
  ('c2-wrong-key', '{"idempotency_key":"other"}'::jsonb, 10))
  as cases(name, patch, ordinal);
-- pgTAP wraps this entire fixture in one transaction. The productive writer's
-- statement_timestamp() is later than the RPC's transaction_timestamp() window;
-- these historical fixture rows exercise pagination without changing that
-- established R1.2 identity-cutoff contract.
insert into public.cash_movements (id, business_id, branch_id,
  cash_register_id, cash_session_id, direction, category, amount,
  currency, source_type, occurred_at, created_by, created_at, updated_at,
  idempotency_key)
select md5(name)::uuid, md5('c2-business')::uuid,
  md5('c2-branch')::uuid, md5('c2-register')::uuid,
  md5('c2-session')::uuid, direction, category, 1.00,
  'COP', 'manual', now() - interval '1 day', md5('c2-owner')::uuid,
  now() - interval '1 day', now() - interval '1 day', name
from (values ('c2-snapshot-in','inflow','other_income'),
  ('c2-snapshot-out','outflow','utilities'))
  as cases(name,direction,category);

select ok(not has_table_privilege('authenticated', 'public.cash_movements', 'INSERT'),
  'direct authenticated INSERT remains denied');
select ok(not has_function_privilege('anon',
  'public.lookup_cash_movement_acknowledgements(uuid,uuid,uuid,jsonb)', 'EXECUTE'),
  'anon cannot execute cash movement ACK');
select ok(has_function_privilege('authenticated',
  'public.lookup_cash_movement_acknowledgements(uuid,uuid,uuid,jsonb)', 'EXECUTE'),
  'authenticated can execute scoped ACK');
select throws_ok($$insert into public.cash_movements (id,business_id,branch_id,
  cash_register_id,cash_session_id,direction,category,amount,currency,
  source_type,occurred_at,created_by,idempotency_key)
  values (md5('c2-invalid')::uuid,md5('c2-business')::uuid,
  md5('c2-branch')::uuid,md5('c2-register')::uuid,md5('c2-session')::uuid,
  'inflow','supplier_purchase',1,'COP','manual',now(),
  md5('c2-owner')::uuid,'c2-invalid')$$, '23514', null,
  'direction/category impossible combination rejected');

select set_config('request.jwt.claim.sub', md5('c2-owner')::uuid::text, true);
set local role authenticated;
select is(public.process_sync_batch(md5('c2-batch')::uuid, 'apply_cash')->>'status',
  'completed', 'valid owner inflow and outflow apply');
select is((select count(*) from public.cash_movements
  where business_id = md5('c2-business')::uuid), 4::bigint,
  'two mutations materialized once beside two historical fixtures');
select is((select sum(case when direction = 'inflow' then amount else -amount end)
  from public.cash_movements where cash_session_id=md5('c2-session')::uuid),
  (-14.75)::numeric, 'net cash movement is exact');
select is(public.process_cash_sync_batch(md5('c2-batch')::uuid)->>'status',
  'completed', 'batch retry succeeds idempotently');
select is((select count(*) from public.cash_movements
  where cash_session_id=md5('c2-session')::uuid), 4::bigint,
  'retry creates no duplicate');
select is(public.lookup_cash_movement_acknowledgements(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, jsonb_build_array(jsonb_build_object(
    'id',md5('c2-out')::uuid,'idempotency_key','c2-out',
    'cash_register_id',md5('c2-register')::uuid,
    'cash_session_id',md5('c2-session')::uuid,'direction','outflow',
    'category','utilities','currency','COP','amount','20.00')))
  ->0->>'state', 'applied', 'ACK uses exact movement identity and scope');
select is((public.pull_operational_bootstrap_snapshot(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, 'cash_pos', 'cash_movements', 1)
  #>> '{datasets,cash_movements,count}')::integer, 1,
  'cash movement snapshot page is capped to requested size');
select is(jsonb_typeof(public.pull_operational_bootstrap_snapshot(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, 'cash_pos', 'cash_movements', 1)
  #> '{datasets,cash_movements,rows,0,amount}'), 'string',
  'cash movement snapshot transmits numeric as exact decimal text');
with first_page as (
  select public.pull_operational_bootstrap_snapshot(
    md5('c2-business')::uuid, md5('c2-branch')::uuid,
    md5('c2-device')::uuid, 'cash_pos', 'cash_movements', 1) as page
)
select is((public.pull_operational_bootstrap_snapshot(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, 'cash_pos', 'cash_movements', 1,
  first_page.page #>> '{datasets,cash_movements,next_page_token}')
  #>> '{datasets,cash_movements,count}')::integer, 1,
  'cash movement snapshot continuation advances within same window')
from first_page;
select throws_ok($q$select public.lookup_cash_movement_acknowledgements(
  md5('c2-other-business')::uuid, md5('c2-other-branch')::uuid,
  md5('c2-device')::uuid, '[]'::jsonb)$q$, 'P0001', null,
  'cross-business ACK denied');
reset role;
update public.sync_mutations set
  payload = jsonb_set(payload, '{amount}', '"99.00"'::jsonb),
  status = 'pending'
where id = md5('c2-out-mut')::uuid;
set local role authenticated;
select is(public.process_cash_sync_batch(md5('c2-batch')::uuid)->>'status',
  'partial', 'same key with changed amount cannot replay as a new intent');
select is((select error_code from public.sync_mutations
  where id=md5('c2-out-mut')::uuid), 'idempotency_conflict',
  'semantic idempotency conflict has stable error code');
select is((select amount from public.cash_movements
  where id=md5('c2-out')::uuid), 20.00::numeric,
  'conflicting retry leaves original ledger amount intact');
select is(public.process_cash_sync_batch(md5('c2-invalid-batch')::uuid)->>'status',
  'partial', 'invalid movement batch remains partial');
select is((select error_code from public.sync_mutations where id =
  md5('c2-zero-mutation')::uuid), 'invalid_payload', 'zero rejected by applicator');
select is((select error_code from public.sync_mutations where id =
  md5('c2-negative-mutation')::uuid), 'invalid_payload', 'negative rejected by applicator');
select is((select error_code from public.sync_mutations where id =
  md5('c2-direction-mutation')::uuid), 'invalid_payload', 'direction rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-category-mutation')::uuid), 'invalid_payload', 'category rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-incompatible-mutation')::uuid), 'invalid_payload',
  'direction/category combination rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-wrong-business-mutation')::uuid), 'invalid_payload',
  'cross-business payload rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-wrong-branch-mutation')::uuid), 'invalid_payload',
  'cross-branch payload rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-wrong-register-mutation')::uuid), 'invalid_scope',
  'wrong register rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-wrong-session-mutation')::uuid), 'invalid_scope',
  'wrong session rejected');
select is((select error_code from public.sync_mutations where id =
  md5('c2-wrong-key-mutation')::uuid), 'invalid_payload',
  'mutation and payload idempotency key must agree');
reset role;
update public.business_members set role_id = md5('c2-receive-role')::uuid
where profile_id = md5('c2-owner')::uuid;
set local role authenticated;
select is(public.process_cash_sync_batch(md5('c2-receive-in')::uuid)->>'status',
  'completed', 'receive-only role may apply inflow');
select is(public.process_cash_sync_batch(md5('c2-receive-out')::uuid)->>'status',
  'partial', 'receive-only role cannot apply outflow');
select is((select error_code from public.sync_mutations
  where id = md5('c2-receive-out-mutation')::uuid), 'permission_denied',
  'outflow capability rejection is explicit');
reset role;
update public.business_members set role_id = md5('c2-disburse-role')::uuid
where profile_id = md5('c2-owner')::uuid;
set local role authenticated;
select is(public.process_cash_sync_batch(md5('c2-disburse-out')::uuid)->>'status',
  'completed', 'disburse-only role may apply outflow');
select is(public.process_cash_sync_batch(md5('c2-disburse-in')::uuid)->>'status',
  'partial', 'disburse-only role cannot apply inflow');
select is((select error_code from public.sync_mutations
  where id = md5('c2-disburse-in-mutation')::uuid), 'permission_denied',
  'inflow capability rejection is explicit');
reset role;
update public.business_members set role_id = (
  select id from public.roles where name = 'cashier' and business_id is null
    and deleted_at is null limit 1)
where profile_id = md5('c2-owner')::uuid;
set local role authenticated;
select is(public.process_cash_sync_batch(md5('c2-cashier-out')::uuid)->>'status',
  'partial', 'cashier default cannot apply ordinary outflow');
reset role;
update public.business_members set role_id = (
  select id from public.roles where name = 'owner' and business_id is null
    and deleted_at is null limit 1)
where profile_id = md5('c2-owner')::uuid;
set local role authenticated;
select is((select count(*) from public.cash_movements
  where cash_session_id = md5('c2-session')::uuid), 6::bigint,
  'only authorized custom-role directions were materialized');
select is((select sum(case when direction = 'inflow' then amount else -amount end)
  from public.cash_movements where cash_session_id=md5('c2-session')::uuid),
  (-14.75)::numeric, 'authorized custom-role movements net to zero');
select is((public.close_cash_session_authoritatively(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-register')::uuid, md5('c2-session')::uuid, 85.25)
  ->>'expected_cash_amount')::numeric, 85.25::numeric,
  'close includes exact ordinary cash movement net');
select is((select difference_amount from public.cash_sessions
  where id=md5('c2-session')::uuid), 0::numeric,
  'difference is zero for exact actual');
select is(public.process_cash_sync_batch(md5('c2-late-batch')::uuid)->>'status',
  'partial', 'other-device-like late movement is rejected after close');
select is((select error_code from public.sync_mutations
  where id=md5('c2-late-mut')::uuid), 'cash_session_closed',
  'closed-session error code is stable');
select is((select count(*) from public.cash_movements
  where id=md5('c2-late')::uuid), 0::bigint,
  'rejected late movement was not applied or reassigned');
select is(public.lookup_cash_movement_acknowledgements(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, jsonb_build_array(jsonb_build_object(
    'id',md5('c2-late')::uuid,'idempotency_key','c2-late',
    'cash_register_id',md5('c2-register')::uuid,
    'cash_session_id',md5('c2-session')::uuid,'direction','outflow',
    'category','utilities','currency','COP','amount','1.00')))
  ->0->>'state', 'rejected', 'ACK returns terminal rejection evidence');
reset role;
select is((select count(*) from public.cash_movements), 6::bigint,
  'close and rejection did not mutate the movement ledger');
update public.app_devices set status = 'blocked'
where id = md5('c2-device')::uuid;
set local role authenticated;
select throws_ok($q$select public.lookup_cash_movement_acknowledgements(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, '[]'::jsonb)$q$, 'P0001', null,
  'blocked device cannot query movement ACK');
reset role;
update public.app_devices set status = 'active'
where id = md5('c2-device')::uuid;
update public.business_members set deleted_at = now()
where profile_id = md5('c2-owner')::uuid;
set local role authenticated;
select throws_ok($q$select public.lookup_cash_movement_acknowledgements(
  md5('c2-business')::uuid, md5('c2-branch')::uuid,
  md5('c2-device')::uuid, '[]'::jsonb)$q$, 'P0001', null,
  'revoked membership cannot query movement ACK');
reset role;
select * from finish();
rollback;
