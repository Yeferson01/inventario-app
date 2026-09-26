-- Two authenticated connections race on each partial unique index.
-- Run only against the disposable local Supabase database.
\set ON_ERROR_STOP on

\if :{?p2_5x_s1a_dblink_dsn}
\else
  \echo 'ERROR: required psql variable p2_5x_s1a_dblink_dsn was not provided'
  do $$ begin
    raise exception 'required psql variable p2_5x_s1a_dblink_dsn was not provided';
  end $$;
\endif

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path = extensions, public, pg_catalog;

-- A failed run can commit only part of this fixture before psql stops. Refuse
-- to clean up if any deterministic ID was reused for non-harness data.
do $$ begin
  if exists (select 1 from auth.users
    where id = '53000000-0000-0000-0000-000000000001'
      and email is distinct from 's1a-concurrency@example.test')
    or exists (select 1 from auth.users
      where email = 's1a-concurrency@example.test'
        and id <> '53000000-0000-0000-0000-000000000001')
    or exists (select 1 from public.profiles
      where id = '53000000-0000-0000-0000-000000000001'
        and full_name is distinct from 'S1A Concurrent')
    or exists (select 1 from public.businesses
      where id = '53000000-0000-0000-0000-000000000002'
        and name is distinct from 'S1A Concurrent')
    or exists (select 1 from public.branches
      where id = '53000000-0000-0000-0000-000000000003'
        and (business_id is distinct from '53000000-0000-0000-0000-000000000002'::uuid
          or name is distinct from 'Concurrent'))
    or exists (select 1 from public.business_members
      where id = '53000000-0000-0000-0000-000000000011'
        and (business_id is distinct from '53000000-0000-0000-0000-000000000002'::uuid
          or profile_id is distinct from '53000000-0000-0000-0000-000000000001'::uuid))
    or exists (select 1 from public.app_devices
      where id = '53000000-0000-0000-0000-000000000004'
        and (business_id is distinct from '53000000-0000-0000-0000-000000000002'::uuid
          or profile_id is distinct from '53000000-0000-0000-0000-000000000001'::uuid
          or installation_id is distinct from 's1a-concurrent-device'))
    or exists (select 1 from public.sync_batches
      where id in ('53000000-0000-0000-0000-000000000006',
        '53000000-0000-0000-0000-000000000040',
        '53000000-0000-0000-0000-000000000041')
        and (business_id is distinct from '53000000-0000-0000-0000-000000000002'::uuid
          or client_batch_id is distinct from case
            when id = '53000000-0000-0000-0000-000000000006'::uuid
              then 's1a-concurrent' else 's1a-partial-race' end))
    or exists (select 1 from public.sync_mutations
      where id in ('53000000-0000-0000-0000-000000000008',
        '53000000-0000-0000-0000-000000000009')
        and (business_id is distinct from '53000000-0000-0000-0000-000000000002'::uuid
          or idempotency_key is distinct from 's1a-concurrent-key'))
    or exists (select 1 from public.sync_batches
      where business_id = '53000000-0000-0000-0000-000000000002'
        and id not in ('53000000-0000-0000-0000-000000000006',
          '53000000-0000-0000-0000-000000000040',
          '53000000-0000-0000-0000-000000000041'))
    or exists (select 1 from public.sync_mutations
      where business_id = '53000000-0000-0000-0000-000000000002'
        and id not in ('53000000-0000-0000-0000-000000000008',
          '53000000-0000-0000-0000-000000000009')) then
    raise exception 'S1A harness fixture identity mismatch; refusing cleanup';
  end if;
end $$;

delete from public.sync_mutations
where id in ('53000000-0000-0000-0000-000000000008',
  '53000000-0000-0000-0000-000000000009')
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.sync_batches
where id in ('53000000-0000-0000-0000-000000000006',
  '53000000-0000-0000-0000-000000000040',
  '53000000-0000-0000-0000-000000000041')
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.app_devices
where id = '53000000-0000-0000-0000-000000000004'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.business_members
where id = '53000000-0000-0000-0000-000000000011'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.branches
where id = '53000000-0000-0000-0000-000000000003'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.businesses
where id = '53000000-0000-0000-0000-000000000002'
  and name = 'S1A Concurrent';
delete from public.profiles
where id = '53000000-0000-0000-0000-000000000001'
  and full_name = 'S1A Concurrent';
delete from auth.users
where id = '53000000-0000-0000-0000-000000000001'
  and email = 's1a-concurrency@example.test';

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('53000000-0000-0000-0000-000000000001', 'authenticated',
  'authenticated', 's1a-concurrency@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status) values
  ('53000000-0000-0000-0000-000000000001', 'S1A Concurrent', 'active');
insert into public.businesses (id, name, status) values
  ('53000000-0000-0000-0000-000000000002', 'S1A Concurrent', 'active');
insert into public.branches (id, business_id, name, status) values
  ('53000000-0000-0000-0000-000000000003',
   '53000000-0000-0000-0000-000000000002', 'Concurrent', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '53000000-0000-0000-0000-000000000011',
  '53000000-0000-0000-0000-000000000002',
  '53000000-0000-0000-0000-000000000001', null, id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values
  ('53000000-0000-0000-0000-000000000004',
   '53000000-0000-0000-0000-000000000002',
   '53000000-0000-0000-0000-000000000001', null,
   's1a-concurrent-device', 'active');

select extensions.dblink_connect('s1a_a', :'p2_5x_s1a_dblink_dsn');
select extensions.dblink_connect('s1a_b', :'p2_5x_s1a_dblink_dsn');
\unset p2_5x_s1a_dblink_dsn
select extensions.dblink_exec('s1a_a',
  'set role authenticated; set request.jwt.claim.sub = ''53000000-0000-0000-0000-000000000001''');
select extensions.dblink_exec('s1a_b',
  'set role authenticated; set request.jwt.claim.sub = ''53000000-0000-0000-0000-000000000001''');

select extensions.dblink_send_query('s1a_a', $query$
  with registered as materialized (
    select public.register_pending_sync_batch(
      '{"id":"53000000-0000-0000-0000-000000000006","business_id":"53000000-0000-0000-0000-000000000002","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_batch_id":"s1a-concurrent","direction":"upload","mutation_count":1}'::jsonb) as value
  )
  select value::text from registered cross join lateral (select pg_sleep(2)) hold
$query$);
select extensions.dblink_send_query('s1a_b', $query$
  select public.register_pending_sync_batch(
    '{"id":"53000000-0000-0000-0000-000000000006","business_id":"53000000-0000-0000-0000-000000000002","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_batch_id":"s1a-concurrent","direction":"upload","mutation_count":1}'::jsonb)::text
$query$);
create temporary table s1a_results (kind text, caller text, payload jsonb);
insert into s1a_results select 'batch', 'a', value::jsonb
from extensions.dblink_get_result('s1a_a') as response(value text);
insert into s1a_results select 'batch', 'b', value::jsonb
from extensions.dblink_get_result('s1a_b') as response(value text);
-- Drain the async result stream before reusing either dblink connection.
select * from extensions.dblink_get_result('s1a_a') as response(value text);
select * from extensions.dblink_get_result('s1a_b') as response(value text);

select extensions.dblink_send_query('s1a_a', $query$
  with registered as materialized (
    select public.register_pending_sync_mutation(
      '{"id":"53000000-0000-0000-0000-000000000008","business_id":"53000000-0000-0000-0000-000000000002","sync_batch_id":"53000000-0000-0000-0000-000000000006","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_mutation_id":"s1a-concurrent-mutation","client_sequence":1,"entity_table":"products","entity_id":"53000000-0000-0000-0000-000000000099","operation":"update","payload":{},"idempotency_key":"s1a-concurrent-key"}'::jsonb) as value
  )
  select value::text from registered cross join lateral (select pg_sleep(2)) hold
$query$);
select extensions.dblink_send_query('s1a_b', $query$
  select public.register_pending_sync_mutation(
    '{"id":"53000000-0000-0000-0000-000000000009","business_id":"53000000-0000-0000-0000-000000000002","sync_batch_id":"53000000-0000-0000-0000-000000000006","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_mutation_id":"s1a-concurrent-mutation","client_sequence":1,"entity_table":"products","entity_id":"53000000-0000-0000-0000-000000000099","operation":"update","payload":{},"idempotency_key":"s1a-concurrent-key"}'::jsonb)::text
$query$);
insert into s1a_results select 'mutation', 'a', value::jsonb
from extensions.dblink_get_result('s1a_a') as response(value text);
insert into s1a_results select 'mutation', 'b', value::jsonb
from extensions.dblink_get_result('s1a_b') as response(value text);
select * from extensions.dblink_get_result('s1a_a') as response(value text);
select * from extensions.dblink_get_result('s1a_b') as response(value text);

-- A second batch race uses different proposed UUIDs, so only the partial
-- semantic unique index can make the two calls converge.
select extensions.dblink_send_query('s1a_a', $query$
  with registered as materialized (
    select public.register_pending_sync_batch(
      '{"id":"53000000-0000-0000-0000-000000000040","business_id":"53000000-0000-0000-0000-000000000002","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_batch_id":"s1a-partial-race","direction":"upload","mutation_count":0}'::jsonb) as value
  )
  select value::text from registered cross join lateral (select pg_sleep(2)) hold
$query$);
select extensions.dblink_send_query('s1a_b', $query$
  select public.register_pending_sync_batch(
    '{"id":"53000000-0000-0000-0000-000000000041","business_id":"53000000-0000-0000-0000-000000000002","app_device_id":"53000000-0000-0000-0000-000000000004","profile_id":"53000000-0000-0000-0000-000000000001","branch_id":"53000000-0000-0000-0000-000000000003","client_batch_id":"s1a-partial-race","direction":"upload","mutation_count":0}'::jsonb)::text
$query$);
insert into s1a_results select 'partial-batch', 'a', value::jsonb
from extensions.dblink_get_result('s1a_a') as response(value text);
insert into s1a_results select 'partial-batch', 'b', value::jsonb
from extensions.dblink_get_result('s1a_b') as response(value text);
select extensions.dblink_disconnect('s1a_a');
select extensions.dblink_disconnect('s1a_b');

select plan(3);
select ok((select count(*) = 2 and count(distinct payload ->> 'id') = 1
  from s1a_results where kind = 'batch')
  and (select count(*) = 1 from public.sync_batches
    where client_batch_id = 's1a-concurrent'),
  'concurrent batch registration converges to one canonical row');
select ok((select count(*) = 2 and count(distinct payload ->> 'id') = 1
  from s1a_results where kind = 'mutation')
  and (select count(*) = 1 from public.sync_mutations
    where idempotency_key = 's1a-concurrent-key'),
  'concurrent mutation registration converges to one canonical row');
select ok((select count(*) = 2 and count(distinct payload ->> 'id') = 1
  from s1a_results where kind = 'partial-batch')
  and (select count(*) = 1 from public.sync_batches
    where client_batch_id = 's1a-partial-race'),
  'partial batch index converges different proposed UUIDs');
select * from finish();

-- Fixture was committed only so independent dblink connections could see it.
delete from public.sync_mutations
where id in ('53000000-0000-0000-0000-000000000008',
  '53000000-0000-0000-0000-000000000009')
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.sync_batches
where id in ('53000000-0000-0000-0000-000000000006',
  '53000000-0000-0000-0000-000000000040',
  '53000000-0000-0000-0000-000000000041')
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.app_devices
where id = '53000000-0000-0000-0000-000000000004'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.business_members
where id = '53000000-0000-0000-0000-000000000011'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.branches
where id = '53000000-0000-0000-0000-000000000003'
  and business_id = '53000000-0000-0000-0000-000000000002';
delete from public.businesses
where id = '53000000-0000-0000-0000-000000000002'
  and name = 'S1A Concurrent';
delete from public.profiles
where id = '53000000-0000-0000-0000-000000000001'
  and full_name = 'S1A Concurrent';
delete from auth.users
where id = '53000000-0000-0000-0000-000000000001'
  and email = 's1a-concurrency@example.test';
