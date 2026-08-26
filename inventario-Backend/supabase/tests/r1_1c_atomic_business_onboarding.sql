-- R1.1c - Focused pgTAP validation for atomic business onboarding.
-- All fixtures and onboarding effects are rolled back.

begin;

select plan(29);

create temporary table r1_1c_results (
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
    'f3000000-0000-0000-0000-000000000301',
    'authenticated',
    'authenticated',
    'r11c-first@example.test',
    '',
    now(),
    '{}',
    '{"full_name":"R1.1c First Owner"}',
    now(),
    now()
  ),
  (
    'f3000000-0000-0000-0000-000000000302',
    'authenticated',
    'authenticated',
    'r11c-cashier@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f3000000-0000-0000-0000-000000000303',
    'authenticated',
    'authenticated',
    'r11c-outsider@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f3000000-0000-0000-0000-000000000304',
    'authenticated',
    'authenticated',
    'r11c-owner-missing@example.test',
    '',
    now(),
    '{}',
    '{}',
    now(),
    now()
  ),
  (
    'f3000000-0000-0000-0000-000000000305',
    'authenticated',
    'authenticated',
    'r11c-runtime-failure@example.test',
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
  'f3000000-0000-0000-0000-000000000302',
  null,
  'R1.1c Cashier',
  'cashier',
  'active'
);

insert into public.businesses (id, name, status)
values
  (
    'f3000000-0000-0000-0000-000000000001',
    'R1.1c Existing Business A',
    'active'
  ),
  (
    'f3000000-0000-0000-0000-000000000002',
    'R1.1c Branch Collision Business',
    'active'
  );

update public.profiles
set business_id = 'f3000000-0000-0000-0000-000000000001'
where id = 'f3000000-0000-0000-0000-000000000302';

insert into public.branches (id, business_id, name, status)
values
  (
    'f3000000-0000-0000-0000-000000000011',
    'f3000000-0000-0000-0000-000000000001',
    'Existing A Branch',
    'active'
  ),
  (
    'f3000000-0000-0000-0000-000000000012',
    'f3000000-0000-0000-0000-000000000002',
    'Reserved Branch Id',
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
  'f3000000-0000-0000-0000-000000000001',
  'f3000000-0000-0000-0000-000000000302',
  'f3000000-0000-0000-0000-000000000011',
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

-- 1. A brand-new authenticated account creates its first complete tenant.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000301',
  true
);

insert into r1_1c_results (result_key, payload)
values (
  'first',
  public.create_business(
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000111',
    'R1.1c First Business',
    'R1.1c First Branch',
    'R1.1c First Register',
    'R1C',
    '{"test":"r1.1c"}'::jsonb
  )
);

select ok(
  coalesce(
    (
      select (payload ->> 'runtime_ready')::boolean
      from r1_1c_results
      where result_key = 'first'
    ),
    false
  ),
  '1. authenticated user without businesses creates a complete first business'
);

-- 2. The RPC provisions only the caller's minimal profile.
select ok(
  exists (
    select 1
    from public.profiles p
    where p.id = 'f3000000-0000-0000-0000-000000000301'
      and p.full_name = 'R1.1c First Owner'
      and p.status = 'active'
      and p.business_id is null
      and p.role is null
  ),
  '2. onboarding guarantees the authenticated user profile without legacy authority fields'
);

-- 3. Business row is materialized with the client id.
select ok(
  exists (
    select 1
    from public.businesses b
    where b.id = 'f3000000-0000-0000-0000-000000000101'
      and b.name = 'R1.1c First Business'
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  ),
  '3. onboarding creates the business with the client-generated id'
);

-- 4. Ownership is a business-level active membership.
select ok(
  exists (
    select 1
    from public.business_members bm
    where bm.business_id = 'f3000000-0000-0000-0000-000000000101'
      and bm.profile_id = 'f3000000-0000-0000-0000-000000000301'
      and bm.branch_id is null
      and bm.status = 'active'
      and bm.deleted_at is null
  ),
  '4. onboarding creates an active business-level owner membership'
);

-- 5. The membership references the exact seeded global owner system role.
select ok(
  exists (
    select 1
    from public.business_members bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = 'f3000000-0000-0000-0000-000000000101'
      and bm.profile_id = 'f3000000-0000-0000-0000-000000000301'
      and bm.branch_id is null
      and r.business_id is null
      and r.is_system_role = true
      and r.name = 'owner'
      and r.deleted_at is null
  ),
  '5. owner membership uses the active global owner system role'
);

select ok(
  exists (
    select 1
    from public.branches br
    where br.id = 'f3000000-0000-0000-0000-000000000111'
      and br.business_id = 'f3000000-0000-0000-0000-000000000101'
      and br.name = 'R1.1c First Branch'
  ),
  '6. onboarding creates the explicit initial branch'
);

select ok(
  exists (
    select 1
    from public.cash_registers cr
    where cr.business_id = 'f3000000-0000-0000-0000-000000000101'
      and cr.branch_id = 'f3000000-0000-0000-0000-000000000111'
      and cr.name = 'R1.1c First Register'
      and cr.status = 'active'
  ),
  '7. onboarding creates the initial cash register'
);

select ok(
  exists (
    select 1
    from public.receipt_sequences rs
    where rs.business_id = 'f3000000-0000-0000-0000-000000000101'
      and rs.branch_id = 'f3000000-0000-0000-0000-000000000111'
      and rs.prefix = 'R1C'
      and rs.status = 'active'
  ),
  '8. onboarding creates the initial receipt sequence'
);

-- 9. A user with only this tenant discovers exactly its initial context.
do $$
declare
  v_discovery jsonb := public.list_authorized_operational_contexts();
begin
  if jsonb_array_length(v_discovery -> 'contexts') <> 1
     or v_discovery -> 'contexts' -> 0 ->> 'business_id'
       <> 'f3000000-0000-0000-0000-000000000101'
     or v_discovery -> 'contexts' -> 0 ->> 'branch_id'
       <> 'f3000000-0000-0000-0000-000000000111'
  then
    raise exception 'Case 9 failed: unexpected discovery result: %', v_discovery;
  end if;
end;
$$;
select pass('9. discovery returns exactly the newly created context');

-- 10. Read-only resolution immediately returns the same complete runtime.
do $$
declare
  v_runtime jsonb := public.resolve_business_runtime(
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000111'
  );
  v_created jsonb := (
    select payload from r1_1c_results where result_key = 'first'
  );
begin
  if not coalesce((v_runtime ->> 'runtime_ready')::boolean, false)
     or v_runtime ->> 'cash_register_id'
       <> v_created ->> 'cash_register_id'
     or v_runtime ->> 'receipt_sequence_id'
       <> v_created ->> 'receipt_sequence_id'
  then
    raise exception 'Case 10 failed: runtime=%, created=%', v_runtime, v_created;
  end if;
end;
$$;
select pass('10. resolve_business_runtime immediately returns runtime_ready');

-- 11-12. A retry with the same client ids returns the canonical ids and creates
-- no duplicate business, membership, branch, register, or sequence.
insert into r1_1c_results (result_key, payload)
values (
  'retry',
  public.create_business(
    'f3000000-0000-0000-0000-000000000101',
    'f3000000-0000-0000-0000-000000000111',
    'R1.1c First Business',
    'R1.1c First Branch',
    'R1.1c First Register',
    'R1C',
    '{"test":"r1.1c-retry"}'::jsonb
  )
);

do $$
declare
  v_first jsonb := (
    select payload from r1_1c_results where result_key = 'first'
  );
  v_retry jsonb := (
    select payload from r1_1c_results where result_key = 'retry'
  );
begin
  if v_first ->> 'business_id' <> v_retry ->> 'business_id'
     or v_first ->> 'owner_membership_id'
       <> v_retry ->> 'owner_membership_id'
     or v_first ->> 'branch_id' <> v_retry ->> 'branch_id'
     or v_first ->> 'cash_register_id' <> v_retry ->> 'cash_register_id'
     or v_first ->> 'receipt_sequence_id'
       <> v_retry ->> 'receipt_sequence_id'
     or coalesce((v_retry ->> 'created_anything')::boolean, true)
  then
    raise exception 'Case 11 failed: first=%, retry=%', v_first, v_retry;
  end if;
end;
$$;
select pass('11. retry with identical ids returns the same canonical ids');

do $$
begin
  if (
       select count(*) from public.businesses
       where id = 'f3000000-0000-0000-0000-000000000101'
     ) <> 1
     or (
       select count(*) from public.business_members
       where business_id = 'f3000000-0000-0000-0000-000000000101'
         and profile_id = 'f3000000-0000-0000-0000-000000000301'
         and branch_id is null
         and deleted_at is null
         and status <> 'removed'
     ) <> 1
     or (
       select count(*) from public.branches
       where id = 'f3000000-0000-0000-0000-000000000111'
     ) <> 1
     or (
       select count(*) from public.cash_registers
       where branch_id = 'f3000000-0000-0000-0000-000000000111'
         and deleted_at is null
     ) <> 1
     or (
       select count(*) from public.receipt_sequences
       where branch_id = 'f3000000-0000-0000-0000-000000000111'
         and deleted_at is null
         and status = 'active'
     ) <> 1
  then
    raise exception 'Case 12 failed: retry produced duplicate rows';
  end if;
end;
$$;
select pass('12. retry does not duplicate any onboarding entity');

-- 13. Platform-level tenant creation is independent of the user's role in A.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000302',
  true
);

insert into r1_1c_results (result_key, payload)
values (
  'cashier_creates_b',
  public.create_business(
    'f3000000-0000-0000-0000-000000000102',
    'f3000000-0000-0000-0000-000000000112',
    'R1.1c Cashier Owned Business B',
    'R1.1c Business B Branch'
  )
);

do $$
begin
  if not exists (
       select 1
       from public.business_members bm
       join public.roles r on r.id = bm.role_id
       where bm.business_id = 'f3000000-0000-0000-0000-000000000001'
         and bm.profile_id = 'f3000000-0000-0000-0000-000000000302'
         and r.name = 'cashier'
     )
     or not exists (
       select 1
       from public.business_members bm
       join public.roles r on r.id = bm.role_id
       where bm.business_id = 'f3000000-0000-0000-0000-000000000102'
         and bm.profile_id = 'f3000000-0000-0000-0000-000000000302'
         and bm.branch_id is null
         and r.business_id is null
         and r.is_system_role = true
         and r.name = 'owner'
     )
     or not exists (
       select 1 from public.profiles p
       where p.id = 'f3000000-0000-0000-0000-000000000302'
         and p.business_id = 'f3000000-0000-0000-0000-000000000001'
         and p.role = 'cashier'
     )
  then
    raise exception 'Case 13 failed: memberships or legacy profile changed';
  end if;
end;
$$;
select pass('13. provisioning engine preserves A while creating invited tenant B');

-- 14. An existing business id cannot be claimed by another authenticated user.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000303',
  true
);
do $$
begin
  begin
    perform public.create_business(
      'f3000000-0000-0000-0000-000000000101',
      'f3000000-0000-0000-0000-000000000111',
      'Attempted Claim',
      'Attempted Claim Branch'
    );
    raise exception 'Case 14 failed: existing business was claimed';
  exception when raise_exception then
    if sqlerrm = 'Case 14 failed: existing business was claimed'
       or position('not owned by the authenticated user' in sqlerrm) = 0
    then
      raise;
    end if;
  end;

  if exists (
    select 1 from public.business_members
    where business_id = 'f3000000-0000-0000-0000-000000000101'
      and profile_id = 'f3000000-0000-0000-0000-000000000303'
  ) then
    raise exception 'Case 14 failed: unauthorized membership remained';
  end if;
end;
$$;
select pass('14. another user cannot reuse and claim an existing business id');

-- 15 + 17. A branch id owned by another business causes a late runtime error;
-- the profile, business, and membership created earlier in the function all
-- roll back with it.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000305',
  true
);
do $$
begin
  begin
    perform public.create_business(
      'f3000000-0000-0000-0000-000000000105',
      'f3000000-0000-0000-0000-000000000012',
      'R1.1c Must Roll Back',
      'Conflicting Branch Id'
    );
    raise exception 'Cases 15/17 failed: cross-business branch was accepted';
  exception when raise_exception then
    if sqlerrm = 'Cases 15/17 failed: cross-business branch was accepted'
       or position('Branch does not belong to this business' in sqlerrm) = 0
    then
      raise;
    end if;
  end;

  if exists (
       select 1 from public.profiles
       where id = 'f3000000-0000-0000-0000-000000000305'
     )
     or exists (
       select 1 from public.businesses
       where id = 'f3000000-0000-0000-0000-000000000105'
     )
     or exists (
       select 1 from public.business_members
       where business_id = 'f3000000-0000-0000-0000-000000000105'
     )
  then
    raise exception 'Cases 15/17 failed: partial onboarding rows remained';
  end if;
end;
$$;
select pass('15. branch id belonging to another business is rejected');
select pass('17. late runtime failure rolls back profile, business, and membership');

-- 16. Owner seed loss is a configuration failure and rolls back provisioning.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000304',
  true
);
do $$
begin
  update public.roles r
  set deleted_at = now()
  where r.business_id is null
    and r.is_system_role = true
    and r.name = 'owner'
    and r.deleted_at is null;

  begin
    perform public.create_business(
      'f3000000-0000-0000-0000-000000000104',
      'f3000000-0000-0000-0000-000000000114',
      'R1.1c Missing Owner',
      'R1.1c Missing Owner Branch'
    );
    raise exception 'Case 16 failed: onboarding worked without owner role';
  exception when raise_exception then
    if sqlerrm = 'Case 16 failed: onboarding worked without owner role'
       or position('Exactly one active global owner system role' in sqlerrm) = 0
    then
      raise;
    end if;
  end;

  if exists (
       select 1 from public.profiles
       where id = 'f3000000-0000-0000-0000-000000000304'
     )
     or exists (
       select 1 from public.businesses
       where id = 'f3000000-0000-0000-0000-000000000104'
     )
     or exists (
       select 1 from public.business_members
       where business_id = 'f3000000-0000-0000-0000-000000000104'
     )
  then
    raise exception 'Case 16 failed: partial rows remained';
  end if;

  update public.roles r
  set deleted_at = null
  where r.business_id is null
    and r.is_system_role = true
    and r.name = 'owner';
end;
$$;
select pass('16. missing owner system role causes total rollback');

-- 18. Supabase's anon role cannot cross the RPC ACL boundary. Keep this
-- catalog-level: invoking a denied SECURITY DEFINER function from an anonymous
-- DO block destabilizes the disposable local test process on this toolchain.
select ok(
  not has_function_privilege(
    'anon',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  '18. anon cannot execute create_business'
);

-- 19. authenticated still has table INSERT privilege, but RLS has no policy
-- permitting direct business creation.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000303',
  true
);
do $$
begin
  begin
    insert into public.businesses (id, name, status)
    values (
      'f3000000-0000-0000-0000-000000000900',
      'Forbidden Direct Insert',
      'active'
    );
    raise exception 'Case 19 failed: authenticated direct INSERT succeeded';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;
select pass('19. direct authenticated INSERT into businesses is blocked by RLS');

-- 20. service_role retains the existing administrative BYPASSRLS behavior.
set local role service_role;
insert into public.businesses (id, name, status)
values (
  'f3000000-0000-0000-0000-000000000901',
  'Service Role Administrative Business',
  'active'
);
reset role;
select ok(
  exists (
    select 1 from public.businesses
    where id = 'f3000000-0000-0000-0000-000000000901'
  ),
  '20. service_role retains administrative direct INSERT behavior'
);

-- 21. The response itself contains the same immediately discoverable context.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000301',
  true
);
select ok(
  (
    select payload -> 'operational_context' ->> 'business_id'
      = 'f3000000-0000-0000-0000-000000000101'
      and payload -> 'operational_context' ->> 'branch_id'
        = 'f3000000-0000-0000-0000-000000000111'
    from r1_1c_results
    where result_key = 'first'
  ),
  '21. newly created business is immediately represented by discovery context'
);

-- 22. Legacy profile fields neither authorize nor get rewritten by onboarding.
select ok(
  (
    select p.business_id is null and p.role is null
    from public.profiles p
    where p.id = 'f3000000-0000-0000-0000-000000000301'
  )
  and (
    select p.business_id = 'f3000000-0000-0000-0000-000000000001'
      and p.role = 'cashier'
    from public.profiles p
    where p.id = 'f3000000-0000-0000-0000-000000000302'
  ),
  '22. onboarding has no authority dependency on profiles.business_id or profiles.role'
);

select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'create_business'
  ),
  1::bigint,
  '23. exactly one public create_business signature exists'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'service_role',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  ),
  '24. final create_business ACL is service-role only after ORG-1B'
);

select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname like 'create_business%'
  ),
  0::bigint,
  '25. R1.1c creates no accidentally exposed private helper'
);

select ok(
  position(
    'pg_advisory_xact_lock'
    in pg_get_functiondef(
      'public.create_business(uuid,uuid,text,text,text,text,jsonb)'::regprocedure
    )
  ) > 0
  and to_regclass('public.business_members_unique_active') is not null
  and to_regclass('public.branches_pkey') is not null
  and to_regclass(
    'public.cash_registers_business_branch_name_active_unique'
  ) is not null
  and to_regclass(
    'public.receipt_sequences_business_branch_prefix_active_unique'
  ) is not null,
  '26. scoped advisory locking and uniqueness guards protect concurrent retries'
);

-- 27. Early input failure also leaves no provisioning artifacts.
select set_config(
  'request.jwt.claim.sub',
  'f3000000-0000-0000-0000-000000000303',
  true
);
do $$
begin
  begin
    perform public.create_business(
      'f3000000-0000-0000-0000-000000000106',
      'f3000000-0000-0000-0000-000000000116',
      'Invalid Metadata Business',
      'Invalid Metadata Branch',
      'Caja Principal',
      'INV',
      '[]'::jsonb
    );
    raise exception 'Case 27 failed: invalid metadata was accepted';
  exception when raise_exception then
    if sqlerrm = 'Case 27 failed: invalid metadata was accepted'
       or position('metadata must be a JSON object' in sqlerrm) = 0
    then
      raise;
    end if;
  end;

  if exists (
    select 1 from public.businesses
    where id = 'f3000000-0000-0000-0000-000000000106'
  ) then
    raise exception 'Case 27 failed: invalid onboarding left a business';
  end if;
end;
$$;
select pass('27. invalid metadata is rejected without partial provisioning');

select is(
  (
    select count(*)::bigint
    from pg_policy p
    where p.polrelid = 'public.businesses'::regclass
      and p.polcmd = 'a'
      and 'authenticated'::regrole = any(p.polroles)
  ),
  0::bigint,
  '28. no authenticated INSERT policy remains on businesses'
);

select ok(
  position(
    'p_profile'
    in lower(
      pg_get_function_arguments(
        'public.create_business(uuid,uuid,text,text,text,text,jsonb)'::regprocedure
      )
    )
  ) = 0
  and position(
    'p_owner'
    in lower(
      pg_get_function_arguments(
        'public.create_business(uuid,uuid,text,text,text,text,jsonb)'::regprocedure
      )
    )
  ) = 0
  and position(
    'p_role'
    in lower(
      pg_get_function_arguments(
        'public.create_business(uuid,uuid,text,text,text,text,jsonb)'::regprocedure
      )
    )
  ) = 0,
  '29. public contract accepts no profile, owner, or role authority input'
);

select * from finish();

rollback;
