begin;
select plan(32);

-- The local PostgreSQL 17.6 stack can SIGSEGV before the body of a function
-- denied by EXECUTE. Assert anon denial through pg_proc/ACL instead of calling
-- a denied RPC; test the in-body guard through authenticated with no JWT sub.
select ok(not has_function_privilege('anon',
  'public.process_sync_batch(uuid,text)', 'EXECUTE'),
  'S-ANON-01 anon cannot execute the canonical batch processor');
select ok(not exists (
  select 1 from pg_proc p, aclexplode(p.proacl) acl
  where p.oid = 'public.process_sync_batch(uuid,text)'::regprocedure
    and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'),
  'PUBLIC has no implicit execute route');
select ok(has_function_privilege('authenticated',
  'public.process_sync_batch(uuid,text)', 'EXECUTE'),
  'authenticated retains canonical processor access');
select ok(has_function_privilege('service_role',
  'public.process_sync_batch(uuid,text)', 'EXECUTE'),
  'service_role retains canonical processor access');
select ok(not has_function_privilege('anon',
  'public.process_cash_sync_batch(uuid)', 'EXECUTE'),
  'S-WORKER-05 anon cannot call cash worker');
select ok(not has_function_privilege('authenticated',
  'public.process_cash_sync_batch(uuid)', 'EXECUTE'),
  'S-WORKER-05 authenticated must use canonical processor for cash');
select ok(has_function_privilege('service_role',
  'public.process_cash_sync_batch(uuid)', 'EXECUTE'),
  'cash worker remains callable by its trusted owner role');
select ok(not has_function_privilege('anon',
  'public.process_sync_batch_base_before_cash(uuid,text)', 'EXECUTE'),
  'anon cannot call pre-cash delegate');
select ok(not has_function_privilege('authenticated',
  'public.process_sync_batch_base_before_cash(uuid,text)', 'EXECUTE'),
  'authenticated must use canonical processor for non-cash modes');
select ok(has_function_privilege('service_role',
  'public.process_sync_batch_base_before_cash(uuid,text)', 'EXECUTE'),
  'pre-cash delegate remains callable by its trusted owner role');
select ok(has_function_privilege('authenticated',
  'public.register_pending_sync_batch(jsonb)', 'EXECUTE'),
  'S1A authenticated registration grant is preserved');
select ok(not has_function_privilege('anon',
  'public.register_pending_sync_batch(jsonb)', 'EXECUTE'),
  'S1A anonymous registration remains denied');

insert into auth.users (id, aud, role, email, raw_app_meta_data,
  raw_user_meta_data) values
  (md5('d05s-owner')::uuid, 'authenticated', 'authenticated',
   'd05s-owner@example.test', '{}', '{}'),
  (md5('d05s-other')::uuid, 'authenticated', 'authenticated',
   'd05s-other@example.test', '{}', '{}');
insert into public.profiles (id, full_name, status) values
  (md5('d05s-owner')::uuid, 'D05S owner', 'active'),
  (md5('d05s-other')::uuid, 'D05S other', 'active');
insert into public.businesses (id, name, status) values
  (md5('d05s-business')::uuid, 'D05S', 'active');
insert into public.branches (id, business_id, name, status) values
  (md5('d05s-branch')::uuid, md5('d05s-business')::uuid,
   'Main', 'active');
insert into public.business_members (business_id, branch_id, profile_id,
  role_id, status)
select md5('d05s-business')::uuid, md5('d05s-branch')::uuid,
  md5('d05s-owner')::uuid, id, 'active'
from public.roles where name = 'owner' and business_id is null
  and is_system_role and deleted_at is null;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values
  (md5('d05s-device')::uuid, md5('d05s-business')::uuid,
   md5('d05s-owner')::uuid, md5('d05s-branch')::uuid,
   'd05s-device', 'active');
insert into public.sync_batches (id, business_id, branch_id, app_device_id,
  profile_id, client_batch_id, direction, status, mutation_count) values
  (md5('d05s-allowed-batch')::uuid, md5('d05s-business')::uuid,
   md5('d05s-branch')::uuid, md5('d05s-device')::uuid,
   md5('d05s-owner')::uuid, 'd05s-allowed', 'upload', 'pending', 0),
  (md5('d05s-denied-batch')::uuid, md5('d05s-business')::uuid,
   md5('d05s-branch')::uuid, md5('d05s-device')::uuid,
   md5('d05s-owner')::uuid, 'd05s-denied', 'upload', 'pending', 0),
  (md5('d05s-service-batch')::uuid, md5('d05s-business')::uuid,
   md5('d05s-branch')::uuid, md5('d05s-device')::uuid,
   md5('d05s-owner')::uuid, 'd05s-service', 'upload', 'pending', 0);

set local role anon;
select ok(not has_function_privilege(current_user,
  'public.process_sync_batch(uuid,text)', 'EXECUTE'),
  'S-ANON-01 active anon role cannot execute canonical processor');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_cash')$$,
  '42501', 'Authentication required',
  'S-NULLAUTH-02 missing auth.uid fails before cash dispatch');
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'validate_only')$$,
  '42501', 'Authentication required',
  'missing auth.uid fails before validate-only delegate');
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_catalog')$$,
  '42501', 'Authentication required',
  'missing auth.uid fails before catalog delegate');
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_pos')$$,
  '42501', 'Authentication required',
  'missing auth.uid fails before POS lookup or delegate');
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_purchases')$$,
  '42501', 'Authentication required',
  'missing auth.uid fails before purchase delegate');
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_inventory')$$,
  '42501', 'Authentication required',
  'missing auth.uid fails before inventory delegate');
reset role;
select is((select status from public.sync_batches
  where id = md5('d05s-denied-batch')::uuid), 'pending',
  'S-NO-EFFECT-06 denied call leaves batch pending');
select is((select count(*) from public.sync_mutations
  where sync_batch_id = md5('d05s-denied-batch')::uuid), 0::bigint,
  'denied call creates no mutations');
select is((select count(*) from public.cash_movements
  where business_id = md5('d05s-business')::uuid), 0::bigint,
  'denied call creates no cash movements');
select is((select count(*) from public.sales
  where business_id = md5('d05s-business')::uuid), 0::bigint,
  'denied call creates no sales');
select is((select count(*) from public.purchases
  where business_id = md5('d05s-business')::uuid), 0::bigint,
  'denied call creates no purchases');
select is((select count(*) from public.inventory_movements
  where business_id = md5('d05s-business')::uuid), 0::bigint,
  'denied call creates no inventory movements');

set local role authenticated;
select set_config('request.jwt.claim.sub', md5('d05s-owner')::uuid::text, true);
select is(public.process_sync_batch(
  md5('d05s-allowed-batch')::uuid, 'apply_cash') ->> 'status',
  'completed', 'S-AUTH-03 valid owner/device batch completes via wrapper');
reset role;
select is((select status from public.sync_batches
  where id = md5('d05s-allowed-batch')::uuid), 'completed',
  'authorized completion is materialized');

set local role authenticated;
select set_config('request.jwt.claim.sub', md5('d05s-other')::uuid::text, true);
select throws_ok($$select public.process_sync_batch(
  md5('d05s-denied-batch')::uuid, 'apply_cash')$$,
  '42501', 'permission_denied',
  'S-CROSS-04 another profile cannot process the owner batch');
reset role;
select is((select status from public.sync_batches
  where id = md5('d05s-denied-batch')::uuid), 'pending',
  'cross-profile denial leaves batch pending');

set local role service_role;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select public.process_sync_batch(
  md5('d05s-service-batch')::uuid, 'apply_cash')$$,
  '42501', 'Authentication required',
  'service_role without a user identity also fails before dispatch');
select set_config('request.jwt.claim.sub', md5('d05s-owner')::uuid::text, true);
select is(public.process_sync_batch(
  md5('d05s-service-batch')::uuid, 'apply_cash') ->> 'status',
  'completed', 'service_role with a user identity retains wrapper access');
reset role;
select is((select status from public.sync_batches
  where id = md5('d05s-service-batch')::uuid), 'completed',
  'service_role completion is materialized');

select * from finish();
rollback;
