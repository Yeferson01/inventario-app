-- ORG-2C - Focused pgTAP validation for secure business-member invitations.
-- All fixtures and invitation/membership effects are rolled back.

begin;

select plan(44);

create temporary table org_2c_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert, update on org_2c_results
to authenticated, service_role;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('fc200000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'org2c-wide-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'org2c-scoped-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'org2c-limited-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'org2c-wide-b@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000010', 'authenticated', 'authenticated', 'new-member@example.test', '', now(), '{}', '{"full_name":"New ORG-2C Member"}', now(), now()),
  ('fc200000-0000-0000-0000-000000000011', 'authenticated', 'authenticated', 'wrong-account@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000012', 'authenticated', 'authenticated', 'same-scope@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000013', 'authenticated', 'authenticated', 'wide-coverage@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000014', 'authenticated', 'authenticated', 'role-conflict@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000015', 'authenticated', 'authenticated', 'multi-branch@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000016', 'authenticated', 'authenticated', 'wide-expansion@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000017', 'authenticated', 'authenticated', 'scoped-new@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000018', 'authenticated', 'authenticated', 'wide-new@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000019', 'authenticated', 'authenticated', 'expired@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000020', 'authenticated', 'authenticated', 'revoked@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000021', 'authenticated', 'authenticated', 'corrupt@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc200000-0000-0000-0000-000000000022', 'authenticated', 'authenticated', 'delivery@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('fc200000-0000-0000-0000-000000000001', 'ORG-2C Wide A', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000002', 'ORG-2C Scoped A', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000003', 'ORG-2C Limited A', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000004', 'ORG-2C Wide B', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000012', 'ORG-2C Same Scope', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000013', 'ORG-2C Wide Coverage', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000014', 'ORG-2C Role Conflict', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000015', 'ORG-2C Multi Branch', 'cashier', 'active'),
  ('fc200000-0000-0000-0000-000000000016', 'ORG-2C Wide Expansion', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('fc200000-0000-0000-0000-000000000101', 'ORG-2C Business A', 'active'),
  ('fc200000-0000-0000-0000-000000000102', 'ORG-2C Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('fc200000-0000-0000-0000-000000000111', 'fc200000-0000-0000-0000-000000000101', 'A Principal', 'active'),
  ('fc200000-0000-0000-0000-000000000112', 'fc200000-0000-0000-0000-000000000101', 'A Norte', 'active'),
  ('fc200000-0000-0000-0000-000000000121', 'fc200000-0000-0000-0000-000000000102', 'B Principal', 'active');

insert into public.roles (
  id, business_id, name, description, is_system_role
)
values
  ('fc200000-0000-0000-0000-000000000201', 'fc200000-0000-0000-0000-000000000101', 'org2c_member_inviter_a', 'ORG-2C capability fixture A', false),
  ('fc200000-0000-0000-0000-000000000202', 'fc200000-0000-0000-0000-000000000102', 'org2c_member_inviter_b', 'ORG-2C capability fixture B', false),
  ('fc200000-0000-0000-0000-000000000203', 'fc200000-0000-0000-0000-000000000101', 'org2c_custom_target', 'ORG-2C forbidden target fixture', false);

insert into public.role_permissions (role_id, permission_id)
select fixture.role_id, permission.id
from (
  values
    ('fc200000-0000-0000-0000-000000000201'::uuid),
    ('fc200000-0000-0000-0000-000000000202'::uuid)
) fixture(role_id)
cross join public.permissions permission
where permission.key = 'members.invite';

insert into public.business_members (
  business_id, profile_id, branch_id, role_id, status, accepted_at
)
values
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000001', null, 'fc200000-0000-0000-0000-000000000201', 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000002', 'fc200000-0000-0000-0000-000000000111', 'fc200000-0000-0000-0000-000000000201', 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000003', null, (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'active', now()),
  ('fc200000-0000-0000-0000-000000000102', 'fc200000-0000-0000-0000-000000000004', null, 'fc200000-0000-0000-0000-000000000202', 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000012', 'fc200000-0000-0000-0000-000000000111', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000013', null, (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null), 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000014', 'fc200000-0000-0000-0000-000000000111', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000015', 'fc200000-0000-0000-0000-000000000111', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'active', now()),
  ('fc200000-0000-0000-0000-000000000101', 'fc200000-0000-0000-0000-000000000016', 'fc200000-0000-0000-0000-000000000111', (select id from public.roles where business_id is null and name = 'technician' and deleted_at is null), 'active', now());

select ok(
  (select relrowsecurity from pg_class where oid = 'private.business_member_invitations'::regclass)
  and not has_table_privilege('authenticated', 'private.business_member_invitations', 'SELECT')
  and not has_table_privilege('authenticated', 'private.business_member_invitations', 'INSERT')
  and not has_table_privilege('anon', 'private.business_member_invitations', 'SELECT')
  and not has_table_privilege('service_role', 'private.business_member_invitations', 'SELECT'),
  '1. private invitation storage has RLS and no direct client or service-role table access'
);

select ok(
  has_table_privilege('authenticated', 'public.business_members', 'SELECT')
  and not has_table_privilege('authenticated', 'public.business_members', 'INSERT')
  and not has_table_privilege('authenticated', 'public.business_members', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.business_members', 'DELETE')
  and not has_table_privilege('authenticated', 'public.business_members', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.business_members', 'REFERENCES')
  and not has_table_privilege('authenticated', 'public.business_members', 'TRIGGER')
  and (
    select count(*)
    from pg_policy policy
    where policy.polrelid = 'public.business_members'::regclass
      and policy.polcmd in ('a', 'w', 'd')
  ) = 0,
  '2. authenticated keeps SELECT only and membership write policies are closed'
);

select ok(
  has_function_privilege('authenticated', 'public.create_business_member_invitation(uuid,text,uuid,uuid,text,timestamptz,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_business_member_invitations(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_my_business_member_invitations()', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.accept_business_member_invitation(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.revoke_business_member_invitation(uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.admin_claim_business_member_invitation_delivery(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.admin_update_business_member_invitation_delivery(uuid,text,text)', 'EXECUTE'),
  '3. authenticated and service-only RPC ACL boundaries are explicit'
);

select ok(
  not has_function_privilege('authenticated', 'public.create_business(uuid,uuid,text,text,text,text,jsonb)', 'EXECUTE')
  and (
    select array_agg(functions.proname order by functions.proname)
    from pg_proc functions
    join pg_namespace namespace on namespace.oid = functions.pronamespace
    where namespace.nspname = 'public'
      and functions.prokind = 'f'
      and position('insert into public.business_members' in lower(pg_get_functiondef(functions.oid))) > 0
      and has_function_privilege('authenticated', functions.oid, 'EXECUTE')
  ) = array['accept_business_member_invitation']::name[],
  '4. acceptance is the sole authenticated function that inserts a membership'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
insert into org_2c_results values (
  'main',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000101',
    '  NEW-MEMBER@EXAMPLE.TEST ',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null),
    'fc200000-0000-0000-0000-000000000112',
    'org-2c-main',
    null,
    '{"source":"pgTAP"}'::jsonb
  )
);
reset role;

select ok(
  (select (payload ->> 'created')::boolean and payload ->> 'scope' = 'branch' from org_2c_results where result_key = 'main'),
  '5. business-wide members.invite issues a branch-scoped invitation'
);

select ok(
  (select payload ->> 'email' = 'NEW-MEMBER@EXAMPLE.TEST' and payload ->> 'role_name' = 'cashier' and payload ->> 'branch_name' = 'A Norte' from org_2c_results where result_key = 'main')
  and (select normalized_email = 'new-member@example.test' from private.business_member_invitations where id = (select (payload ->> 'invitation_id')::uuid from org_2c_results where result_key = 'main')),
  '6. issuance normalizes email server-side and returns safe target labels'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
insert into org_2c_results values (
  'business-wide',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000101', 'wide-new@example.test',
    (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null),
    null, 'org-2c-business-wide'
  )
);
reset role;

select ok(
  (select payload ->> 'scope' = 'business' and payload ->> 'branch_id' is null from org_2c_results where result_key = 'business-wide'),
  '7. business-wide members.invite issues a business-wide invitation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000002', true);
insert into org_2c_results values (
  'scoped',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000101', 'scoped-new@example.test',
    (select id from public.roles where business_id is null and name = 'technician' and deleted_at is null),
    'fc200000-0000-0000-0000-000000000111', 'org-2c-scoped'
  )
);
reset role;

select ok(
  (select payload ->> 'branch_id' = 'fc200000-0000-0000-0000-000000000111' from org_2c_results where result_key = 'scoped'),
  '8. branch-specific members.invite issues for its own branch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-wide@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),null,'org-2c-deny-wide')$$,
  '42501', 'Business-wide members.invite permission is required',
  '9. branch-specific inviter cannot issue business-wide'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-other-branch@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000112','org-2c-deny-other-branch')$$,
  '42501', 'members.invite permission is required for this branch',
  '10. branch-specific inviter cannot issue for another branch'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-no-permission@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),null,'org-2c-no-permission')$$,
  '42501', 'Business-wide members.invite permission is required',
  '11. a member without members.invite is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000102','deny-cross-business@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),null,'org-2c-cross-business')$$,
  '42501', 'Business-wide members.invite permission is required',
  '12. actor from Business A cannot issue in Business B'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-cross-branch@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000121','org-2c-cross-branch')$$,
  '42501', 'Branch is not active for this business',
  '13. a Branch from another Business is rejected before issuance'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-owner@example.test',(select id from public.roles where business_id is null and name='owner' and deleted_at is null),null,'org-2c-owner')$$,
  '42501', 'Target role is not delegable by business member invitations',
  '14. Owner target role is denied'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-admin@example.test',(select id from public.roles where business_id is null and name='admin' and deleted_at is null),null,'org-2c-admin')$$,
  '42501', 'Target role is not delegable by business member invitations',
  '15. Admin target role is denied'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','deny-custom@example.test','fc200000-0000-0000-0000-000000000203',null,'org-2c-custom')$$,
  '42501', 'Target role is not delegable by business member invitations',
  '16. custom target role is denied'
);
reset role;

select set_eq(
  $$select distinct role.name from private.business_member_invitations invitation join public.roles role on role.id=invitation.role_id where invitation.id in ((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='main'),(select (payload->>'invitation_id')::uuid from org_2c_results where result_key='business-wide'),(select (payload->>'invitation_id')::uuid from org_2c_results where result_key='scoped'))$$,
  $$values ('cashier'::text),('warehouse'::text),('technician'::text)$$,
  '17. cashier, warehouse, and technician are the allowed target roles'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
insert into org_2c_results values (
  'main-retry',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000101', 'new-member@example.test',
    (select id from public.roles where business_id is null and name='cashier' and deleted_at is null),
    'fc200000-0000-0000-0000-000000000112', 'org-2c-main', null,
    '{"source":"pgTAP"}'::jsonb
  )
);
reset role;

select ok(
  (select first.payload->>'invitation_id'=retry.payload->>'invitation_id' and not (retry.payload->>'created')::boolean from org_2c_results first join org_2c_results retry on retry.result_key='main-retry' where first.result_key='main'),
  '18. same idempotency key and payload returns the same invitation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','new-member@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000112','org-2c-main',null,'{"source":"changed"}'::jsonb)$$,
  '23505', 'idempotency_key was already used with an incompatible member invitation payload',
  '19. incompatible reuse of an idempotency key conflicts'
);
select throws_ok(
  $$select public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','new-member@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000112','org-2c-equivalent')$$,
  '23505', 'An equivalent pending business member invitation already exists',
  '20. a second equivalent pending invitation is rejected'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
select ok(
  jsonb_array_length(public.list_business_member_invitations('fc200000-0000-0000-0000-000000000101')->'invitations') >= 3,
  '21. business-wide inviter can list administrative invitations for its Business'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000002', true);
select ok(
  (
    select jsonb_array_length(response -> 'invitations') = 1
      and response -> 'invitations' -> 0 ->> 'branch_id'
        = 'fc200000-0000-0000-0000-000000000111'
    from (
      select public.list_business_member_invitations(
        'fc200000-0000-0000-0000-000000000101'
      ) response
    ) listed
  ),
  '22. branch-specific inviter lists only invitations from its Branch'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000010', true);
select is(
  jsonb_array_length(public.list_my_business_member_invitations()->'invitations'),
  1,
  '23. self-listing exposes only pending invitations matching auth.users.email'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000011', true);
select throws_ok(
  format('select public.accept_business_member_invitation(%L)', (select payload->>'invitation_id' from org_2c_results where result_key='main')),
  '42501', 'Business member invitation is not available for this user',
  '24. wrong account cannot accept an invitation'
);
reset role;

insert into private.business_member_invitations (
  id,business_id,email,role_id,branch_id,expires_at,invited_by_profile_id,
  idempotency_key,request_payload,created_at,metadata
)
values (
  'fc200000-0000-0000-0000-000000000301',
  'fc200000-0000-0000-0000-000000000101','expired@example.test',
  (select id from public.roles where business_id is null and name='cashier' and deleted_at is null),
  'fc200000-0000-0000-0000-000000000111',now()-interval '1 day',
  'fc200000-0000-0000-0000-000000000001','org-2c-expired','{}'::jsonb,
  now()-interval '2 days','{}'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000019', true);
select throws_ok(
  $$select public.accept_business_member_invitation('fc200000-0000-0000-0000-000000000301')$$,
  '42501', 'Business member invitation has expired',
  '25. expired invitation cannot be accepted'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
insert into org_2c_results values (
  'revoked',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000101','revoked@example.test',
    (select id from public.roles where business_id is null and name='cashier' and deleted_at is null),
    'fc200000-0000-0000-0000-000000000112','org-2c-revoked'
  )
);
insert into org_2c_results values (
  'revoked-result',
  public.revoke_business_member_invitation(
    (select (payload->>'invitation_id')::uuid from org_2c_results where result_key='revoked'),
    'test revocation'
  )
);
reset role;

select ok(
  (select payload->>'status'='revoked' and payload->>'revoked_at' is not null from org_2c_results where result_key='revoked-result'),
  '26. authorized inviter revokes a pending invitation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000020', true);
do $$
begin
  if jsonb_array_length(
    public.list_my_business_member_invitations() -> 'invitations'
  ) <> 0 then
    raise exception 'Revoked invitation remained visible';
  end if;

  begin
    perform public.accept_business_member_invitation(
      (
        select (payload ->> 'invitation_id')::uuid
        from org_2c_results
        where result_key = 'revoked'
      )
    );
    raise exception 'Revoked invitation was accepted';
  exception when insufficient_privilege then
    if sqlerrm <> 'Business member invitation has been revoked' then
      raise;
    end if;
  end;
end;
$$;
select pass('27. revoked invitation is hidden from self-list and cannot be accepted');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000002', true);
select throws_ok(
  format('select public.revoke_business_member_invitation(%L)', (select payload->>'invitation_id' from org_2c_results where result_key='main')),
  '42501', 'members.invite permission is required for this invitation scope',
  '28. branch-specific inviter cannot revoke an invitation for another branch'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000010', true);
insert into org_2c_results values (
  'main-accepted',
  public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='main'))
);
reset role;

select ok(
  exists (select 1 from public.profiles where id='fc200000-0000-0000-0000-000000000010' and full_name='New ORG-2C Member' and status='active')
  and (select (payload->>'profile_created')::boolean from org_2c_results where result_key='main-accepted'),
  '29. acceptance creates a missing profile from authenticated user data'
);

select ok(
  exists (
    select 1 from public.business_members member
    join org_2c_results result on result.result_key='main-accepted' and member.id=(result.payload->>'membership_id')::uuid
    where member.business_id='fc200000-0000-0000-0000-000000000101'
      and member.profile_id='fc200000-0000-0000-0000-000000000010'
      and member.branch_id='fc200000-0000-0000-0000-000000000112'
      and member.status='active'
      and member.invited_by='fc200000-0000-0000-0000-000000000001'
      and member.accepted_at is not null
  ),
  '30. acceptance creates the active scoped membership with invitation audit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
insert into org_2c_results values ('same-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','same-scope@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000111','org-2c-same'));
insert into org_2c_results values ('coverage-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','wide-coverage@example.test',(select id from public.roles where business_id is null and name='warehouse' and deleted_at is null),'fc200000-0000-0000-0000-000000000112','org-2c-coverage'));
insert into org_2c_results values ('conflict-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','role-conflict@example.test',(select id from public.roles where business_id is null and name='warehouse' and deleted_at is null),'fc200000-0000-0000-0000-000000000111','org-2c-conflict'));
insert into org_2c_results values ('multi-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','multi-branch@example.test',(select id from public.roles where business_id is null and name='warehouse' and deleted_at is null),'fc200000-0000-0000-0000-000000000112','org-2c-multi'));
insert into org_2c_results values ('expand-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','wide-expansion@example.test',(select id from public.roles where business_id is null and name='technician' and deleted_at is null),null,'org-2c-expand'));
insert into org_2c_results values ('delivery-invite',public.create_business_member_invitation('fc200000-0000-0000-0000-000000000101','delivery@example.test',(select id from public.roles where business_id is null and name='cashier' and deleted_at is null),'fc200000-0000-0000-0000-000000000111','org-2c-delivery'));
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000012', true);
insert into org_2c_results values ('same-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='same-invite')));
reset role;
select ok(
  (select not (payload->>'membership_created')::boolean and (payload->>'membership_reused')::boolean from org_2c_results where result_key='same-accepted')
  and (select payload->>'existing_membership_id' is not null from org_2c_results where result_key='same-invite')
  and (select count(*)=1 from public.business_members where business_id='fc200000-0000-0000-0000-000000000101' and profile_id='fc200000-0000-0000-0000-000000000012' and branch_id='fc200000-0000-0000-0000-000000000111' and deleted_at is null),
  '31. issuance detects and acceptance reuses same-role same-scope membership'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000013', true);
insert into org_2c_results values ('coverage-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='coverage-invite')));
reset role;
select ok(
  (select (payload->>'membership_reused_by_business_wide_coverage')::boolean and payload->>'membership_scope_branch_id' is null from org_2c_results where result_key='coverage-accepted'),
  '32. business-wide same-role membership covers a narrower invitation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000014', true);
select throws_ok(
  format('select public.accept_business_member_invitation(%L)',(select payload->>'invitation_id' from org_2c_results where result_key='conflict-invite')),
  '23505','A membership already exists at this scope with a different or non-active role',
  '33. same scope with a different role is a conflict'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000015', true);
insert into org_2c_results values ('multi-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='multi-invite')));
reset role;
select ok(
  (select count(*)=2 from public.business_members where business_id='fc200000-0000-0000-0000-000000000101' and profile_id='fc200000-0000-0000-0000-000000000015' and status='active' and deleted_at is null)
  and exists (select 1 from public.business_members where profile_id='fc200000-0000-0000-0000-000000000015' and branch_id='fc200000-0000-0000-0000-000000000111')
  and exists (select 1 from public.business_members where profile_id='fc200000-0000-0000-0000-000000000015' and branch_id='fc200000-0000-0000-0000-000000000112'),
  '34. accepting another Branch creates a second membership and preserves the first'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000016', true);
insert into org_2c_results values ('expand-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='expand-invite')));
reset role;
select ok(
  (select count(*)=2 from public.business_members where business_id='fc200000-0000-0000-0000-000000000101' and profile_id='fc200000-0000-0000-0000-000000000016' and status='active' and deleted_at is null)
  and exists (select 1 from public.business_members where profile_id='fc200000-0000-0000-0000-000000000016' and branch_id is null)
  and exists (select 1 from public.business_members where profile_id='fc200000-0000-0000-0000-000000000016' and branch_id='fc200000-0000-0000-0000-000000000111'),
  '35. business-wide expansion preserves prior branch memberships'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000010', true);
insert into org_2c_results values ('main-accept-retry',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='main')));
reset role;
select ok(
  (select first.payload->>'membership_id'=retry.payload->>'membership_id' and first.payload=retry.payload from org_2c_results first join org_2c_results retry on retry.result_key='main-accept-retry' where first.result_key='main-accepted'),
  '36. acceptance retry returns the same membership and logical response'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000017', true);
insert into org_2c_results values ('scoped-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='scoped')));
select is(
  (select count(*) from jsonb_array_elements(public.list_authorized_operational_contexts()->'contexts') context(value) where context.value->>'business_id'='fc200000-0000-0000-0000-000000000101'),
  1::bigint,
  '37. branch-specific acceptance exposes only its covered Branch in discovery'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000018', true);
insert into org_2c_results values ('business-wide-accepted',public.accept_business_member_invitation((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='business-wide')));
select is(
  (select count(*) from jsonb_array_elements(public.list_authorized_operational_contexts()->'contexts') context(value) where context.value->>'business_id'='fc200000-0000-0000-0000-000000000101'),
  2::bigint,
  '38. business-wide acceptance expands discovery to all active Branches'
);
reset role;

select is(
  (select count(*)::bigint from public.app_devices where profile_id in ('fc200000-0000-0000-0000-000000000010','fc200000-0000-0000-0000-000000000017','fc200000-0000-0000-0000-000000000018')),
  0::bigint,
  '39. acceptance creates no app_device or operational bootstrap state'
);

select ok(
  has_function_privilege('service_role','public.admin_claim_business_member_invitation_delivery(uuid)','EXECUTE')
  and has_function_privilege('service_role','public.admin_update_business_member_invitation_delivery(uuid,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.admin_claim_business_member_invitation_delivery(uuid)','EXECUTE'),
  '40. delivery state RPCs are service-role only'
);

select set_config('request.jwt.claim.role', 'service_role', true);
set local role service_role;
insert into org_2c_results values ('delivery-claim',public.admin_claim_business_member_invitation_delivery((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='delivery-invite')));
insert into org_2c_results values ('delivery-failed',public.admin_update_business_member_invitation_delivery((select (payload->>'invitation_id')::uuid from org_2c_results where result_key='delivery-invite'),'failed','test_delivery_failure'));
reset role;
select ok(
  (select (payload->>'claimed')::boolean from org_2c_results where result_key='delivery-claim')
  and (select payload->>'delivery_status'='failed' and payload->>'delivery_error_code'='test_delivery_failure' from org_2c_results where result_key='delivery-failed')
  and exists (select 1 from private.business_member_invitations where id=(select (payload->>'invitation_id')::uuid from org_2c_results where result_key='delivery-invite') and status='pending'),
  '41. delivery failure is recorded without revoking durable invitation authority'
);

insert into private.business_member_invitations (
  id,business_id,email,role_id,branch_id,expires_at,invited_by_profile_id,
  idempotency_key,request_payload,metadata
)
values (
  'fc200000-0000-0000-0000-000000000302',
  'fc200000-0000-0000-0000-000000000101','corrupt@example.test',
  (select id from public.roles where business_id is null and name='cashier' and deleted_at is null),
  'fc200000-0000-0000-0000-000000000121',now()+interval '7 days',
  'fc200000-0000-0000-0000-000000000001','org-2c-corrupt','{}'::jsonb,'{}'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000021', true);
select throws_ok(
  $$select public.accept_business_member_invitation('fc200000-0000-0000-0000-000000000302')$$,
  '42501','Invitation branch is not active for this business',
  '42. acceptance fails closed for internally corrupted cross-business scope'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000004', true);
insert into org_2c_results values (
  'business-b-invite',
  public.create_business_member_invitation(
    'fc200000-0000-0000-0000-000000000102',
    'business-b-target@example.test',
    (select id from public.roles where business_id is null and name='cashier' and deleted_at is null),
    'fc200000-0000-0000-0000-000000000121',
    'org-2c-business-b'
  )
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc200000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.list_business_member_invitations('fc200000-0000-0000-0000-000000000102')$$,
  '42501', 'members.invite permission is required for this Business',
  '43. Business A inviter cannot list Business B invitations'
);
select throws_ok(
  format(
    'select public.revoke_business_member_invitation(%L)',
    (
      select payload ->> 'invitation_id'
      from org_2c_results
      where result_key = 'business-b-invite'
    )
  ),
  '42501', 'members.invite permission is required for this invitation scope',
  '44. Business A inviter cannot revoke a Business B invitation'
);
reset role;

select * from finish();

rollback;
