-- ORG-2C.1 - Focused pgTAP for server-authoritative invitation reads.
-- Fixtures and effects are transactionally rolled back.

begin;

select plan(24);

create temporary table org_2c1_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert, update on org_2c1_results to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('fc210000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'org2c1-wide@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc210000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'org2c1-scoped@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc210000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'org2c1-limited@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc210000-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'org2c1-multi@example.test', '', now(), '{}', '{}', now(), now()),
  ('fc210000-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'org2c1-other@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('fc210000-0000-0000-0000-000000000001', 'ORG-2C.1 Wide', 'cashier', 'active'),
  ('fc210000-0000-0000-0000-000000000002', 'ORG-2C.1 Scoped', 'cashier', 'active'),
  ('fc210000-0000-0000-0000-000000000003', 'ORG-2C.1 Limited', 'cashier', 'active'),
  ('fc210000-0000-0000-0000-000000000004', 'ORG-2C.1 Multi', 'cashier', 'active'),
  ('fc210000-0000-0000-0000-000000000005', 'ORG-2C.1 Other', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('fc210000-0000-0000-0000-000000000101', 'ORG-2C.1 Business A', 'active'),
  ('fc210000-0000-0000-0000-000000000102', 'ORG-2C.1 Business B', 'active');

insert into public.branches (
  id, business_id, name, status, is_primary, deleted_at
)
values
  ('fc210000-0000-0000-0000-000000000111', 'fc210000-0000-0000-0000-000000000101', 'A Principal', 'active', true, null),
  ('fc210000-0000-0000-0000-000000000112', 'fc210000-0000-0000-0000-000000000101', 'B Centro', 'active', false, null),
  ('fc210000-0000-0000-0000-000000000113', 'fc210000-0000-0000-0000-000000000101', 'C Norte', 'active', false, null),
  ('fc210000-0000-0000-0000-000000000114', 'fc210000-0000-0000-0000-000000000101', 'D Inactiva', 'inactive', false, null),
  ('fc210000-0000-0000-0000-000000000115', 'fc210000-0000-0000-0000-000000000101', 'E Eliminada', 'active', false, now()),
  ('fc210000-0000-0000-0000-000000000121', 'fc210000-0000-0000-0000-000000000102', 'Otra Principal', 'active', true, null);

insert into public.roles (
  id, business_id, name, description, is_system_role
)
values
  ('fc210000-0000-0000-0000-000000000201', 'fc210000-0000-0000-0000-000000000101', 'org2c1_inviter', 'members.invite only', false),
  ('fc210000-0000-0000-0000-000000000202', 'fc210000-0000-0000-0000-000000000101', 'org2c1_limited', 'no invite permission', false),
  ('fc210000-0000-0000-0000-000000000203', 'fc210000-0000-0000-0000-000000000102', 'org2c1_other_inviter', 'other Business invite permission', false),
  ('fc210000-0000-0000-0000-000000000204', 'fc210000-0000-0000-0000-000000000101', 'org2c1_custom_target', 'forbidden custom target', false);

insert into public.role_permissions (role_id, permission_id)
select fixture.role_id, permission.id
from (
  values
    ('fc210000-0000-0000-0000-000000000201'::uuid),
    ('fc210000-0000-0000-0000-000000000203'::uuid)
) fixture(role_id)
cross join public.permissions permission
where permission.key = 'members.invite';

insert into public.business_members (
  business_id, profile_id, branch_id, role_id, status, accepted_at
)
values
  ('fc210000-0000-0000-0000-000000000101', 'fc210000-0000-0000-0000-000000000001', null, 'fc210000-0000-0000-0000-000000000201', 'active', now()),
  ('fc210000-0000-0000-0000-000000000101', 'fc210000-0000-0000-0000-000000000002', 'fc210000-0000-0000-0000-000000000111', 'fc210000-0000-0000-0000-000000000201', 'active', now()),
  ('fc210000-0000-0000-0000-000000000101', 'fc210000-0000-0000-0000-000000000003', null, 'fc210000-0000-0000-0000-000000000202', 'active', now()),
  ('fc210000-0000-0000-0000-000000000101', 'fc210000-0000-0000-0000-000000000004', 'fc210000-0000-0000-0000-000000000111', 'fc210000-0000-0000-0000-000000000201', 'active', now()),
  ('fc210000-0000-0000-0000-000000000101', 'fc210000-0000-0000-0000-000000000004', 'fc210000-0000-0000-0000-000000000113', 'fc210000-0000-0000-0000-000000000201', 'active', now()),
  ('fc210000-0000-0000-0000-000000000102', 'fc210000-0000-0000-0000-000000000005', null, 'fc210000-0000-0000-0000-000000000203', 'active', now());

insert into private.business_member_invitations (
  id, business_id, email, role_id, branch_id, expires_at,
  invited_by_profile_id, idempotency_key, request_payload, metadata
)
values
  ('fc210000-0000-0000-0000-000000000301', 'fc210000-0000-0000-0000-000000000101', 'wide-target@example.test', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), null, now() + interval '7 days', 'fc210000-0000-0000-0000-000000000001', 'org-2c1-wide', '{}', '{}'),
  ('fc210000-0000-0000-0000-000000000302', 'fc210000-0000-0000-0000-000000000101', 'a-target@example.test', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'fc210000-0000-0000-0000-000000000111', now() + interval '7 days', 'fc210000-0000-0000-0000-000000000001', 'org-2c1-a', '{}', '{}'),
  ('fc210000-0000-0000-0000-000000000303', 'fc210000-0000-0000-0000-000000000101', 'b-target@example.test', (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null), 'fc210000-0000-0000-0000-000000000112', now() + interval '7 days', 'fc210000-0000-0000-0000-000000000001', 'org-2c1-b', '{}', '{}'),
  ('fc210000-0000-0000-0000-000000000304', 'fc210000-0000-0000-0000-000000000101', 'c-target@example.test', (select id from public.roles where business_id is null and name = 'technician' and deleted_at is null), 'fc210000-0000-0000-0000-000000000113', now() + interval '7 days', 'fc210000-0000-0000-0000-000000000001', 'org-2c1-c', '{}', '{}'),
  ('fc210000-0000-0000-0000-000000000305', 'fc210000-0000-0000-0000-000000000102', 'other-target@example.test', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null), 'fc210000-0000-0000-0000-000000000121', now() + interval '7 days', 'fc210000-0000-0000-0000-000000000005', 'org-2c1-other', '{}', '{}');

select ok(
  has_function_privilege('authenticated', 'public.list_business_member_invitation_options(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_business_member_invitations(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_business_member_invitation_options(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_business_member_invitations(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_business_member_invitation_options(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role', 'public.list_business_member_invitations(uuid)', 'EXECUTE'),
  '1. invitation read RPC ACLs are authenticated-only'
);

select ok(
  (select prosecdef from pg_proc where oid = 'public.list_business_member_invitation_options(uuid)'::regprocedure)
  and (select proconfig = array['search_path=""'] from pg_proc where oid = 'public.list_business_member_invitation_options(uuid)'::regprocedure)
  and (select prosecdef from pg_proc where oid = 'public.list_business_member_invitations(uuid)'::regprocedure)
  and (select proconfig = array['search_path=""'] from pg_proc where oid = 'public.list_business_member_invitations(uuid)'::regprocedure),
  '2. read RPCs are SECURITY DEFINER with an empty search_path'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000001', true);
insert into org_2c1_results values (
  'wide-options',
  public.list_business_member_invitation_options('fc210000-0000-0000-0000-000000000101')
);
reset role;

select ok(
  (select payload ->> 'profile_id' = 'fc210000-0000-0000-0000-000000000001' from org_2c1_results where result_key = 'wide-options'),
  '3. authenticated members.invite actor can execute options and identity comes from auth.uid()'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000003', true);
select throws_ok(
  $$select public.list_business_member_invitation_options('fc210000-0000-0000-0000-000000000101')$$,
  '42501', 'members.invite permission is required for this Business',
  '4. actor without members.invite is denied options'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.list_business_member_invitation_options('fc210000-0000-0000-0000-000000000102')$$,
  '42501', 'members.invite permission is required for this Business',
  '5. cross-Business options are denied'
);
reset role;

select set_eq(
  $$select role ->> 'role_name' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'delegable_roles') role where result.result_key = 'wide-options'$$,
  $$values ('cashier'::text), ('warehouse'::text), ('technician'::text)$$,
  '6. options returns exactly cashier, warehouse, and technician'
);

select ok(
  not exists (
    select 1
    from org_2c1_results result
    cross join lateral jsonb_array_elements(result.payload -> 'delegable_roles') role
    where result.result_key = 'wide-options'
      and role ->> 'role_name' in ('owner', 'admin', 'org2c1_custom_target')
  ),
  '7. owner, admin, and custom roles are excluded'
);

select ok(
  not exists (
    select 1
    from org_2c1_results result
    cross join lateral jsonb_array_elements(result.payload -> 'delegable_roles') role
    where result.result_key = 'wide-options'
      and not private.is_delegable_business_member_role((role ->> 'role_id')::uuid)
  ),
  '8. every returned role ID is accepted by the ORG-2C allowlist helper'
);

select ok(
  (select (payload ->> 'can_invite_business_wide')::boolean from org_2c1_results where result_key = 'wide-options'),
  '9. business-wide members.invite produces can_invite_business_wide=true'
);

select set_eq(
  $$select branch ->> 'branch_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitable_branches') branch where result.result_key = 'wide-options'$$,
  $$values ('fc210000-0000-0000-0000-000000000111'::text), ('fc210000-0000-0000-0000-000000000112'::text), ('fc210000-0000-0000-0000-000000000113'::text)$$,
  '10. business-wide actor receives every active non-deleted Branch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000002', true);
insert into org_2c1_results values (
  'scoped-options',
  public.list_business_member_invitation_options('fc210000-0000-0000-0000-000000000101')
);
reset role;

select ok(
  not (select (payload ->> 'can_invite_business_wide')::boolean from org_2c1_results where result_key = 'scoped-options'),
  '11. branch-specific membership never produces business-wide authority'
);

select set_eq(
  $$select branch ->> 'branch_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitable_branches') branch where result.result_key = 'scoped-options'$$,
  $$values ('fc210000-0000-0000-0000-000000000111'::text)$$,
  '12. branch-specific actor receives only its authorized Branch'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000004', true);
insert into org_2c1_results values (
  'multi-options',
  public.list_business_member_invitation_options('fc210000-0000-0000-0000-000000000101')
);
reset role;

select set_eq(
  $$select branch ->> 'branch_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitable_branches') branch where result.result_key = 'multi-options'$$,
  $$values ('fc210000-0000-0000-0000-000000000111'::text), ('fc210000-0000-0000-0000-000000000113'::text)$$,
  '13. multi-Branch actor receives A and C but not B'
);

select ok(
  not exists (
    select 1
    from org_2c1_results result
    cross join lateral jsonb_array_elements(result.payload -> 'invitable_branches') branch
    where result.result_key = 'wide-options'
      and branch ->> 'branch_id' in (
        'fc210000-0000-0000-0000-000000000114',
        'fc210000-0000-0000-0000-000000000115'
      )
  ),
  '14. inactive and deleted Branches are excluded'
);

select ok(
  not exists (
    select 1
    from public.role_permissions role_permission
    join public.permissions permission on permission.id = role_permission.permission_id
    where role_permission.role_id = 'fc210000-0000-0000-0000-000000000201'
      and permission.key = 'settings.branches'
  ),
  '15. options requires members.invite without settings.branches'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000001', true);
insert into org_2c1_results values (
  'wide-list',
  public.list_business_member_invitations('fc210000-0000-0000-0000-000000000101')
);
reset role;

select set_eq(
  $$select invitation ->> 'invitation_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitations') invitation where result.result_key = 'wide-list'$$,
  $$values ('fc210000-0000-0000-0000-000000000301'::text), ('fc210000-0000-0000-0000-000000000302'::text), ('fc210000-0000-0000-0000-000000000303'::text), ('fc210000-0000-0000-0000-000000000304'::text)$$,
  '16. business-wide administrative list sees every invitation in its Business'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000002', true);
insert into org_2c1_results values (
  'scoped-list',
  public.list_business_member_invitations('fc210000-0000-0000-0000-000000000101')
);
reset role;

select set_eq(
  $$select invitation ->> 'invitation_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitations') invitation where result.result_key = 'scoped-list'$$,
  $$values ('fc210000-0000-0000-0000-000000000302'::text)$$,
  '17. branch-scoped list exposes only invitations from the actor Branch'
);

select ok(
  not exists (
    select 1
    from org_2c1_results result
    cross join lateral jsonb_array_elements(result.payload -> 'invitations') invitation
    where result.result_key = 'scoped-list'
      and invitation ->> 'branch_id' is null
  ),
  '18. branch-scoped list never exposes business-wide invitations'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000004', true);
insert into org_2c1_results values (
  'multi-list',
  public.list_business_member_invitations('fc210000-0000-0000-0000-000000000101')
);
reset role;

select set_eq(
  $$select invitation ->> 'invitation_id' from org_2c1_results result cross join lateral jsonb_array_elements(result.payload -> 'invitations') invitation where result.result_key = 'multi-list'$$,
  $$values ('fc210000-0000-0000-0000-000000000302'::text), ('fc210000-0000-0000-0000-000000000304'::text)$$,
  '19. multi-Branch list exposes A and C but not B'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.list_business_member_invitations('fc210000-0000-0000-0000-000000000102')$$,
  '42501', 'members.invite permission is required for this Business',
  '20. cross-Business administrative list is denied'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000002', true);
insert into org_2c1_results values (
  'scoped-revoke',
  public.revoke_business_member_invitation(
    'fc210000-0000-0000-0000-000000000302',
    'ORG-2C.1 coherence'
  )
);
reset role;

select ok(
  (select payload ->> 'status' = 'revoked' from org_2c1_results where result_key = 'scoped-revoke'),
  '21. a pending invitation returned by scoped list is revocable under the same authority'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000002', true);
insert into org_2c1_results values (
  'scoped-issue',
  public.create_business_member_invitation(
    'fc210000-0000-0000-0000-000000000101',
    'options-compatible@example.test',
    (
      select (role ->> 'role_id')::uuid
      from org_2c1_results result
      cross join lateral jsonb_array_elements(result.payload -> 'delegable_roles') role
      where result.result_key = 'scoped-options'
      order by role ->> 'role_name'
      limit 1
    ),
    (
      select (branch ->> 'branch_id')::uuid
      from org_2c1_results result
      cross join lateral jsonb_array_elements(result.payload -> 'invitable_branches') branch
      where result.result_key = 'scoped-options'
      limit 1
    ),
    'org-2c1-options-compatible'
  )
);
reset role;

select ok(
  (select (payload ->> 'created')::boolean from org_2c1_results where result_key = 'scoped-issue'),
  '22. role and Branch returned by options are accepted by issuance'
);

update public.business_members
set status = 'suspended'
where business_id = 'fc210000-0000-0000-0000-000000000101'
  and profile_id = 'fc210000-0000-0000-0000-000000000002';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'fc210000-0000-0000-0000-000000000002', true);
select throws_ok(
  $$select public.list_business_member_invitations('fc210000-0000-0000-0000-000000000101')$$,
  '42501', 'members.invite permission is required for this Business',
  '23. administrative listing reflects current authority after revocation'
);
reset role;

select ok(
  (select payload ->> 'business_id' = 'fc210000-0000-0000-0000-000000000101' from org_2c1_results where result_key = 'wide-options')
  and not ((select payload from org_2c1_results where result_key = 'wide-options') ? 'membership_ids')
  and not ((select payload from org_2c1_results where result_key = 'wide-options') ? 'permissions'),
  '24. options returns UI-safe scope data without membership or permission internals'
);

select * from finish();

rollback;
