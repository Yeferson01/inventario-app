-- P2.4R3 - Focused pgTAP validation for secure self-service onboarding.
-- SB-10 uses the separate real-concurrency harness.

begin;

select plan(13);

create temporary table p2_4_r3_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert on table p2_4_r3_results to authenticated;

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
    'f2403000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'p24r3-owner@example.test',
    '',
    now(),
    '{}',
    '{"full_name":"P2.4R3 Fresh Owner"}',
    now(),
    now()
  ),
  (
    'f2403000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'p24r3-outsider@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f2403000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'p24r3-rollback@example.test',
    '',
    now(),
    '{}',
    '{"full_name":"P2.4R3 Rollback User"}',
    now(),
    now()
  );

-- SB-01: the function itself rejects a missing authenticated identity. The
-- denied anon ACL is asserted catalog-level in SB-13 because invoking a
-- no-EXECUTE function as anon crashes affected local Supabase stacks.
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select public.create_self_service_business(
      'Unauthenticated Business',
      'p2-4-r3-unauthenticated'
    )$$,
  '42501',
  'Authentication required',
  'SB-01 unauthenticated calls are rejected by the authoritative function'
);

-- SB-02: a fresh authenticated account can execute the public wrapper. An
-- explicit blank branch exercises the productive default normalization.
select set_config(
  'request.jwt.claim.sub',
  'f2403000-0000-0000-0000-000000000001',
  true
);
set local role authenticated;
insert into p2_4_r3_results (result_key, payload)
values (
  'first',
  public.create_self_service_business(
    '  P2.4R3 Fresh Business  ',
    'p2-4-r3-first',
    '   '
  )
);
reset role;

select ok(
  exists (
    select 1
    from public.businesses business
    join p2_4_r3_results result
      on business.id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and business.name = 'P2.4R3 Fresh Business'
      and business.status = 'active'
      and business.deleted_at is null
  )
  and exists (
    select 1
    from public.activity_logs log
    join p2_4_r3_results result
      on log.business_id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and log.user_id = 'f2403000-0000-0000-0000-000000000001'
      and log.action = 'BUSINESS_CREATED_SELF_SERVICE'
      and log.record_id = (result.payload ->> 'business_id')::uuid
  ),
  'SB-02 first request creates one active business and its audit event'
);

-- SB-03: authority is the seeded global owner role on a business-wide active
-- membership for auth.uid().
select ok(
  exists (
    select 1
    from p2_4_r3_results result
    join public.business_members member
      on member.business_id = (result.payload ->> 'business_id')::uuid
    join public.roles role on role.id = member.role_id
    where result.result_key = 'first'
      and member.profile_id = 'f2403000-0000-0000-0000-000000000001'
      and member.branch_id is null
      and member.status = 'active'
      and member.deleted_at is null
      and role.business_id is null
      and role.is_system_role = true
      and role.name = 'owner'
      and role.deleted_at is null
  ),
  'SB-03 caller receives exactly the global owner authority for the new business'
);

-- SB-04: the blank input became the single active primary branch.
select ok(
  (
    select count(*) = 1
    from p2_4_r3_results result
    join public.branches branch
      on branch.business_id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and branch.id = (result.payload ->> 'branch_id')::uuid
      and branch.name = 'Sucursal Principal'
      and branch.is_primary = true
      and branch.status = 'active'
      and branch.deleted_at is null
  ),
  'SB-04 exactly one active primary Sucursal Principal is created'
);

-- SB-05: create_business remains responsible for runtime infrastructure, and
-- onboarding does not open a cash session.
select ok(
  (
    select count(*) = 1
    from p2_4_r3_results result
    join public.cash_registers register
      on register.business_id = (result.payload ->> 'business_id')::uuid
     and register.branch_id = (result.payload ->> 'branch_id')::uuid
    where result.result_key = 'first'
      and register.status = 'active'
      and register.deleted_at is null
  )
  and (
    select count(*) = 1
    from p2_4_r3_results result
    join public.receipt_sequences sequence
      on sequence.business_id = (result.payload ->> 'business_id')::uuid
     and sequence.branch_id = (result.payload ->> 'branch_id')::uuid
    where result.result_key = 'first'
      and sequence.status = 'active'
      and sequence.deleted_at is null
  )
  and (
    select count(*) = 0
    from p2_4_r3_results result
    join public.cash_sessions session
      on session.business_id = (result.payload ->> 'business_id')::uuid
     and session.branch_id = (result.payload ->> 'branch_id')::uuid
    where result.result_key = 'first'
      and session.status = 'open'
  ),
  'SB-05 canonical register and receipt sequence exist without an open cash session'
);

-- SB-06: the existing engine provisions the missing profile.
select ok(
  exists (
    select 1
    from public.profiles profile
    where profile.id = 'f2403000-0000-0000-0000-000000000001'
      and profile.full_name = 'P2.4R3 Fresh Owner'
      and profile.status = 'active'
  ),
  'SB-06 a missing profile is materialized by create_business'
);

-- SB-07: the caller can immediately discover the new concrete context.
set local role authenticated;
select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.list_authorized_operational_contexts() -> 'contexts'
    ) context_row(value)
    join p2_4_r3_results result
      on context_row.value ->> 'business_id' = result.payload ->> 'business_id'
     and context_row.value ->> 'branch_id' = result.payload ->> 'branch_id'
    where result.result_key = 'first'
  ),
  'SB-07 discovery immediately exposes the new authorized context'
);
reset role;

-- SB-08: a normalized identical retry returns exactly the same minimal result
-- and creates no duplicate request, tenant, runtime, or audit event.
set local role authenticated;
insert into p2_4_r3_results (result_key, payload)
values (
  'retry',
  public.create_self_service_business(
    'P2.4R3 Fresh Business',
    '  p2-4-r3-first  ',
    'Sucursal Principal'
  )
);
reset role;

select ok(
  (select payload from p2_4_r3_results where result_key = 'first')
    =
  (select payload from p2_4_r3_results where result_key = 'retry')
  and (
    select count(*) = 1
    from private.self_service_business_creation_requests request
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000001'
      and request.idempotency_key = 'p2-4-r3-first'
      and request.status = 'completed'
  )
  and (
    select count(*) = 1
    from p2_4_r3_results result
    join public.businesses business
      on business.id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
  )
  and (
    select count(*) = 1
    from p2_4_r3_results result
    join public.branches branch
      on branch.business_id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and branch.deleted_at is null
  )
  and (
    select count(*) = 1
    from p2_4_r3_results result
    join public.activity_logs log
      on log.business_id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and log.action = 'BUSINESS_CREATED_SELF_SERVICE'
  ),
  'SB-08 identical retry returns canonical IDs without duplicate side effects'
);

-- SB-09: a reused key cannot be rebound to a different normalized payload.
set local role authenticated;
select throws_ok(
  $$select public.create_self_service_business(
      'P2.4R3 Different Business',
      'p2-4-r3-first',
      'Sucursal Principal'
    )$$,
  '23505',
  'self_service_business_creation_idempotency_conflict',
  'SB-09 same key with different payload is rejected recognizably'
);
reset role;

-- SB-11: another authenticated account receives neither membership nor
-- discovery access to the created tenant.
select set_config(
  'request.jwt.claim.sub',
  'f2403000-0000-0000-0000-000000000002',
  true
);
set local role authenticated;
select ok(
  not exists (
    select 1
    from public.business_members member
    join p2_4_r3_results result
      on member.business_id = (result.payload ->> 'business_id')::uuid
    where result.result_key = 'first'
      and member.profile_id = 'f2403000-0000-0000-0000-000000000002'
      and member.deleted_at is null
  )
  and not exists (
    select 1
    from jsonb_array_elements(
      public.list_authorized_operational_contexts() -> 'contexts'
    ) context_row(value)
    join p2_4_r3_results result
      on context_row.value ->> 'business_id' = result.payload ->> 'business_id'
    where result.result_key = 'first'
  ),
  'SB-11 another user receives no membership or discovery access'
);
reset role;

-- SB-12: the only public inputs are names and an opaque key. There is no
-- caller-selected tenant, actor, role, owner, runtime, or device identifier.
select ok(
  (
    select procedure.proargnames
      = array['p_business_name', 'p_idempotency_key', 'p_branch_name']::text[]
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'create_self_service_business'
  )
  and (
    select count(*) = 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'create_self_service_business'
  ),
  'SB-12 public API exposes one non-escalating signature only'
);

-- SB-13: authenticated and service_role may execute only the wrapper; anon
-- and PUBLIC cannot. No client role can access the durable private table.
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_self_service_business(text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.create_self_service_business(text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.create_self_service_business(text,text,text)',
    'EXECUTE'
  )
  and not exists (
    select 1
    from pg_proc procedure
    cross join lateral aclexplode(procedure.proacl) acl
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'create_self_service_business'
      and acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  )
  and not has_table_privilege(
    'authenticated',
    'private.self_service_business_creation_requests',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.self_service_business_creation_requests',
    'INSERT'
  )
  and not has_table_privilege(
    'service_role',
    'private.self_service_business_creation_requests',
    'SELECT'
  ),
  'SB-13 wrapper and private table ACLs expose only the intended capability'
);

-- SB-14: a controlled failure in the reused engine rolls back the request,
-- profile, tenant, runtime, and audit event. The role mutation belongs only to
-- this test transaction and is restored before the assertion completes.
do $$
declare
  v_failure_observed boolean := false;
begin
  update public.roles role
  set deleted_at = statement_timestamp()
  where role.business_id is null
    and role.is_system_role = true
    and role.name = 'owner'
    and role.deleted_at is null;

  begin
    perform set_config(
      'request.jwt.claim.sub',
      'f2403000-0000-0000-0000-000000000003',
      true
    );
    perform public.create_self_service_business(
      'P2.4R3 Must Roll Back',
      'p2-4-r3-rollback',
      'Sucursal Principal'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'Exactly one active global owner system role is required' then
      v_failure_observed := true;
    else
      raise;
    end if;
  end;

  update public.roles role
  set deleted_at = null
  where role.business_id is null
    and role.is_system_role = true
    and role.name = 'owner';

  if not v_failure_observed
     or exists (
       select 1
       from private.self_service_business_creation_requests request
       where request.actor_user_id = 'f2403000-0000-0000-0000-000000000003'
         and request.idempotency_key = 'p2-4-r3-rollback'
     )
     or exists (
       select 1
       from public.profiles profile
       where profile.id = 'f2403000-0000-0000-0000-000000000003'
     )
     or exists (
       select 1
       from public.businesses business
       where business.name = 'P2.4R3 Must Roll Back'
     )
     or exists (
       select 1
       from public.activity_logs log
       where log.user_id = 'f2403000-0000-0000-0000-000000000003'
         and log.action = 'BUSINESS_CREATED_SELF_SERVICE'
     ) then
    raise exception 'SB-14 failed: failure was not observed or partial state remained';
  end if;
end;
$$;
select pass('SB-14 controlled engine failure leaves no partial or falsely completed state');

select * from finish();

rollback;
