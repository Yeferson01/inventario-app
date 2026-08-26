-- ORG-1B - Focused pgTAP validation for private platform onboarding.
-- All fixtures and provisioning effects are rolled back.

begin;

select plan(21);

create temporary table org_1b_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    'f6100000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'org1b-owner@example.test',
    '',
    now(),
    '{}',
    '{"full_name":"ORG-1B Owner"}',
    now(),
    now()
  ),
  (
    'f6100000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'org1b-other@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f6100000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'org1b-multi@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f6100000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'org1b-failure@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  );

insert into public.profiles (
  id,
  business_id,
  full_name,
  role,
  status
)
values (
  'f6100000-0000-0000-0000-000000000003',
  null,
  'ORG-1B Existing Member',
  'cashier',
  'active'
);

insert into public.businesses (id, name, status)
values (
  'f6100000-0000-0000-0000-000000000101',
  'ORG-1B Existing Business A',
  'active'
);

insert into public.branches (id, business_id, name, status)
values (
  'f6100000-0000-0000-0000-000000000111',
  'f6100000-0000-0000-0000-000000000101',
  'Principal',
  'active'
);

insert into public.business_members (
  business_id,
  profile_id,
  branch_id,
  role_id,
  status
)
values (
  'f6100000-0000-0000-0000-000000000101',
  'f6100000-0000-0000-0000-000000000003',
  'f6100000-0000-0000-0000-000000000111',
  (
    select r.id
    from public.roles r
    where r.business_id is null
      and r.is_system_role = true
      and r.name = 'cashier'
      and r.deleted_at is null
    limit 1
  ),
  'active'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  '1. create_business is no longer a client-authenticated capability'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.admin_create_platform_business_invitation(text,text,text,text,timestamptz,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.admin_create_platform_business_invitation(text,text,text,text,timestamptz,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_create_platform_business_invitation(text,text,text,text,timestamptz,jsonb)',
    'EXECUTE'
  ),
  '2. only service_role can issue a platform business invitation'
);

select set_config('request.jwt.claim.role', 'service_role', true);

insert into org_1b_results (result_key, payload)
values
  (
    'matching',
    public.admin_create_platform_business_invitation(
      '  ORG1B-OWNER@EXAMPLE.TEST ',
      'ORG-1B Invited Business',
      'org-1b-matching',
      'Principal',
      null,
      '{"test":"matching"}'::jsonb
    )
  ),
  (
    'mismatch',
    public.admin_create_platform_business_invitation(
      'org1b-owner@example.test',
      'ORG-1B Mismatch Business',
      'org-1b-mismatch',
      'Principal'
    )
  ),
  (
    'expired',
    public.admin_create_platform_business_invitation(
      'org1b-owner@example.test',
      'ORG-1B Expired Business',
      'org-1b-expired',
      'Principal'
    )
  ),
  (
    'revoked',
    public.admin_create_platform_business_invitation(
      'org1b-owner@example.test',
      'ORG-1B Revoked Business',
      'org-1b-revoked',
      'Principal'
    )
  ),
  (
    'multi_business',
    public.admin_create_platform_business_invitation(
      'org1b-multi@example.test',
      'ORG-1B Explicit Business B',
      'org-1b-multi-business',
      'Principal'
    )
  ),
  (
    'failure',
    public.admin_create_platform_business_invitation(
      'org1b-failure@example.test',
      'ORG-1B Must Roll Back',
      'org-1b-failure',
      'Principal'
    )
  );

select ok(
  (
    select payload ->> 'normalized_email' = 'org1b-owner@example.test'
      and payload ->> 'invitation_id' is not null
      and payload ->> 'business_id' is not null
      and payload ->> 'branch_id' is not null
      and (payload ->> 'created')::boolean
    from org_1b_results
    where result_key = 'matching'
  ),
  '3. service-role issuance normalizes email and creates canonical invitation IDs'
);

insert into org_1b_results (result_key, payload)
values (
  'matching_retry',
  public.admin_create_platform_business_invitation(
    'org1b-owner@example.test',
    'ORG-1B Invited Business',
    'org-1b-matching',
    'Principal',
    null,
    '{"test":"matching"}'::jsonb
  )
);

select ok(
  (
    select first.payload ->> 'invitation_id' = retry.payload ->> 'invitation_id'
      and first.payload ->> 'business_id' = retry.payload ->> 'business_id'
      and first.payload ->> 'branch_id' = retry.payload ->> 'branch_id'
      and not (retry.payload ->> 'created')::boolean
    from org_1b_results first
    cross join org_1b_results retry
    where first.result_key = 'matching'
      and retry.result_key = 'matching_retry'
  ),
  '4. same issuance idempotency key returns the same invitation and tenant IDs'
);

select throws_ok(
  $$
    select public.admin_create_platform_business_invitation(
      'org1b-owner@example.test',
      'Incompatible Business Name',
      'org-1b-matching',
      'Principal'
    )
  $$,
  '23505',
  'idempotency_key was already used with an incompatible invitation payload',
  '5. incompatible reuse of an issuance idempotency key is rejected'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000001',
  true
);

select ok(
  (
    select jsonb_array_length(result -> 'invitations') = 4
      and not exists (
        select 1
        from jsonb_array_elements(result -> 'invitations') row(value)
        where row.value ->> 'business_name' = 'ORG-1B Explicit Business B'
      )
    from (
      select public.list_my_platform_business_invitations() as result
    ) listed
  ),
  '6. list_my_platform_business_invitations returns only the authenticated email scope'
);

insert into org_1b_results (result_key, payload)
select
  'accepted',
  public.accept_platform_business_invitation(
    (payload ->> 'invitation_id')::uuid
  )
from org_1b_results
where result_key = 'matching';

select ok(
  (
    select accepted.payload ->> 'business_id' = issued.payload ->> 'business_id'
      and accepted.payload ->> 'branch_id' = issued.payload ->> 'branch_id'
      and (accepted.payload ->> 'runtime_ready')::boolean
      and (accepted.payload ->> 'branch_is_primary')::boolean
    from org_1b_results accepted
    cross join org_1b_results issued
    where accepted.result_key = 'accepted'
      and issued.result_key = 'matching'
  ),
  '7. matching authenticated user atomically accepts canonical tenant IDs'
);

select ok(
  exists (
    select 1
    from org_1b_results issued
    join public.business_members bm
      on bm.business_id = (issued.payload ->> 'business_id')::uuid
    join public.roles r on r.id = bm.role_id
    where issued.result_key = 'matching'
      and bm.profile_id = 'f6100000-0000-0000-0000-000000000001'
      and bm.branch_id is null
      and bm.status = 'active'
      and bm.deleted_at is null
      and r.business_id is null
      and r.is_system_role = true
      and r.name = 'owner'
  ),
  '8. acceptance creates the active business-wide system Owner membership'
);

select ok(
  exists (
    select 1
    from org_1b_results issued
    join public.branches br
      on br.id = (issued.payload ->> 'branch_id')::uuid
     and br.business_id = (issued.payload ->> 'business_id')::uuid
    where issued.result_key = 'matching'
      and br.is_primary = true
      and br.status = 'active'
      and br.deleted_at is null
  ),
  '9. accepted onboarding creates an active formal primary branch'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.list_authorized_operational_contexts() -> 'contexts'
    ) context_row(value)
    join org_1b_results issued on issued.result_key = 'matching'
    where context_row.value ->> 'business_id' = issued.payload ->> 'business_id'
      and context_row.value ->> 'branch_id' = issued.payload ->> 'branch_id'
      and (context_row.value ->> 'branch_is_primary')::boolean
      and jsonb_array_length(context_row.value -> 'effective_permissions') > 0
  ),
  '10. discovery immediately returns the new primary context and Owner permissions'
);

insert into org_1b_results (result_key, payload)
select
  'accepted_retry',
  public.accept_platform_business_invitation(
    (payload ->> 'invitation_id')::uuid
  )
from org_1b_results
where result_key = 'matching';

select ok(
  (
    select first.payload = retry.payload
    from org_1b_results first
    cross join org_1b_results retry
    where first.result_key = 'accepted'
      and retry.result_key = 'accepted_retry'
  ),
  '11. lost-response retry returns the same durable acceptance result'
);

select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000002',
  true
);

select throws_ok(
  format(
    'select public.accept_platform_business_invitation(%L::uuid)',
    (
      select payload ->> 'invitation_id'
      from org_1b_results
      where result_key = 'mismatch'
    )
  ),
  '42501',
  'Platform invitation is not available for this user',
  '12. invitation email mismatch is denied without cross-email disclosure'
);

select throws_ok(
  format(
    'select public.accept_platform_business_invitation(%L::uuid)',
    (
      select payload ->> 'invitation_id'
      from org_1b_results
      where result_key = 'matching'
    )
  ),
  '42501',
  'Platform invitation is not available for this user',
  '13. an invitation accepted by one user cannot be replayed by another'
);

update private.platform_business_invitations invitation
set expires_at = now() - interval '1 second'
from org_1b_results issued
where issued.result_key = 'expired'
  and invitation.id = (issued.payload ->> 'invitation_id')::uuid;

select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000001',
  true
);

select throws_ok(
  format(
    'select public.accept_platform_business_invitation(%L::uuid)',
    (
      select payload ->> 'invitation_id'
      from org_1b_results
      where result_key = 'expired'
    )
  ),
  '42501',
  'Platform invitation has expired',
  '14. an expired invitation is denied without being consumed'
);

select set_config('request.jwt.claim.role', 'service_role', true);
select public.admin_revoke_platform_business_invitation(
  (
    select (payload ->> 'invitation_id')::uuid
    from org_1b_results
    where result_key = 'revoked'
  ),
  'test revocation'
);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  format(
    'select public.accept_platform_business_invitation(%L::uuid)',
    (
      select payload ->> 'invitation_id'
      from org_1b_results
      where result_key = 'revoked'
    )
  ),
  '42501',
  'Platform invitation has been revoked',
  '15. a revoked invitation cannot be consumed'
);

select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000003',
  true
);

insert into org_1b_results (result_key, payload)
select
  'multi_accepted',
  public.accept_platform_business_invitation(
    (payload ->> 'invitation_id')::uuid
  )
from org_1b_results
where result_key = 'multi_business';

select ok(
  exists (
    select 1
    from public.business_members bm
    where bm.profile_id = 'f6100000-0000-0000-0000-000000000003'
      and bm.business_id = 'f6100000-0000-0000-0000-000000000101'
      and bm.status = 'active'
  )
  and exists (
    select 1
    from org_1b_results issued
    join public.business_members bm
      on bm.business_id = (issued.payload ->> 'business_id')::uuid
    where issued.result_key = 'multi_business'
      and bm.profile_id = 'f6100000-0000-0000-0000-000000000003'
      and bm.branch_id is null
      and bm.status = 'active'
  ),
  '16. an existing member of Business A can accept an explicit invitation for B'
);

select throws_ok(
  format(
    'insert into public.branches (business_id, name, status, is_primary) '
    || 'values (%L::uuid, %L, %L, true)',
    (
      select payload ->> 'business_id'
      from org_1b_results
      where result_key = 'matching'
    ),
    'Second Primary',
    'active'
  ),
  '23505',
  null,
  '17. at most one non-deleted primary branch is allowed per Business'
);

select throws_ok(
  format(
    'update public.branches set status = %L where id = %L::uuid',
    'inactive',
    (
      select payload ->> 'branch_id'
      from org_1b_results
      where result_key = 'matching'
    )
  ),
  '23514',
  null,
  '18. a formal primary branch cannot be inactive'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000002',
  true
);
do $$
begin
  begin
    insert into public.businesses (name, status)
    values ('ORG-1B Forbidden Direct Insert', 'active');
    raise exception 'Case 19 failed: authenticated direct INSERT succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;
select pass('19. authenticated direct INSERT into businesses remains blocked by RLS');

update private.platform_business_invitations invitation
set branch_id = 'f6100000-0000-0000-0000-000000000111'
from org_1b_results issued
where issued.result_key = 'failure'
  and invitation.id = (issued.payload ->> 'invitation_id')::uuid;

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  'f6100000-0000-0000-0000-000000000004',
  true
);

do $$
declare
  v_invitation_id uuid := (
    select (payload ->> 'invitation_id')::uuid
    from org_1b_results
    where result_key = 'failure'
  );
begin
  begin
    perform public.accept_platform_business_invitation(v_invitation_id);
    raise exception 'Case 20 failed: incompatible canonical branch was accepted';
  exception when raise_exception then
    if sqlerrm = 'Case 20 failed: incompatible canonical branch was accepted'
       or position('Branch does not belong to this business' in sqlerrm) = 0
    then
      raise;
    end if;
  end;
end;
$$;
select pass('20. provisioning failure aborts atomic invitation acceptance');

select ok(
  (
    select invitation.status = 'pending'
      and invitation.accepted_user_id is null
      and not exists (
        select 1
        from public.businesses b
        where b.id = invitation.business_id
      )
    from private.platform_business_invitations invitation
    join org_1b_results issued
      on issued.result_key = 'failure'
     and invitation.id = (issued.payload ->> 'invitation_id')::uuid
  ),
  '21. failed provisioning leaves invitation pending and no partial Business'
);

select * from finish();

rollback;
