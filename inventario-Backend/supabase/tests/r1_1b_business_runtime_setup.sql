-- R1.1b - Focused pgTAP validation for administrative runtime setup.

begin;

select plan(16);

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
  ('f2000000-0000-0000-0000-000000000201', 'authenticated', 'authenticated', 'r11b-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000202', 'authenticated', 'authenticated', 'r11b-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000203', 'authenticated', 'authenticated', 'r11b-cashier@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000204', 'authenticated', 'authenticated', 'r11b-warehouse@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000205', 'authenticated', 'authenticated', 'r11b-technician@example.test', '', now(), '{}', '{}', now(), now()),
  ('f2000000-0000-0000-0000-000000000206', 'authenticated', 'authenticated', 'r11b-outsider@example.test', '', now(), '{}', '{}', now(), now());

-- The legacy profile.role column is not the authorization authority. Keep a
-- value accepted by both historical profile constraints and authorize only
-- through business_members -> roles -> permissions below.
insert into public.profiles (id, full_name, role, status)
values
  ('f2000000-0000-0000-0000-000000000201', 'R1.1b Owner', 'cashier', 'active'),
  ('f2000000-0000-0000-0000-000000000202', 'R1.1b Admin', 'cashier', 'active'),
  ('f2000000-0000-0000-0000-000000000203', 'R1.1b Cashier', 'cashier', 'active'),
  ('f2000000-0000-0000-0000-000000000204', 'R1.1b Warehouse', 'cashier', 'active'),
  ('f2000000-0000-0000-0000-000000000205', 'R1.1b Technician', 'cashier', 'active'),
  ('f2000000-0000-0000-0000-000000000206', 'R1.1b Outsider', 'cashier', 'active')
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    status = excluded.status;

insert into public.businesses (id, name, status)
values
  ('f2000000-0000-0000-0000-000000000001', 'R1.1b Business A', 'active'),
  ('f2000000-0000-0000-0000-000000000002', 'R1.1b Business B', 'active');

insert into public.branches (id, business_id, name, status, deleted_at)
values
  ('f2000000-0000-0000-0000-000000000011', 'f2000000-0000-0000-0000-000000000001', 'Owner Runtime', 'active', null),
  ('f2000000-0000-0000-0000-000000000012', 'f2000000-0000-0000-0000-000000000001', 'Existing Runtime', 'active', null),
  ('f2000000-0000-0000-0000-000000000013', 'f2000000-0000-0000-0000-000000000001', 'Cashier Missing', 'active', null),
  ('f2000000-0000-0000-0000-000000000014', 'f2000000-0000-0000-0000-000000000001', 'Warehouse Missing', 'active', null),
  ('f2000000-0000-0000-0000-000000000015', 'f2000000-0000-0000-0000-000000000001', 'Technician Missing', 'active', null),
  ('f2000000-0000-0000-0000-000000000016', 'f2000000-0000-0000-0000-000000000001', 'Inactive Branch', 'inactive', null),
  ('f2000000-0000-0000-0000-000000000017', 'f2000000-0000-0000-0000-000000000001', 'Deleted Branch', 'active', now()),
  ('f2000000-0000-0000-0000-000000000019', 'f2000000-0000-0000-0000-000000000001', 'Atomic Failure', 'active', null),
  ('f2000000-0000-0000-0000-000000000021', 'f2000000-0000-0000-0000-000000000002', 'Other Business', 'active', null);

insert into public.business_members (
  id,
  business_id,
  profile_id,
  branch_id,
  role_id,
  status
)
values
  (
    'f2000000-0000-0000-0000-000000000041',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000201',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000042',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000202',
    null,
    (select id from public.roles where business_id is null and name = 'admin' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000043',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000203',
    'f2000000-0000-0000-0000-000000000013',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000044',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000204',
    'f2000000-0000-0000-0000-000000000014',
    (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000045',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000205',
    'f2000000-0000-0000-0000-000000000015',
    (select id from public.roles where business_id is null and name = 'technician' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000046',
    'f2000000-0000-0000-0000-000000000002',
    'f2000000-0000-0000-0000-000000000206',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000047',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000203',
    'f2000000-0000-0000-0000-000000000011',
    (select id from public.roles where business_id is null and name = 'admin' and deleted_at is null limit 1),
    'active'
  );

insert into public.cash_registers (
  id,
  business_id,
  branch_id,
  name,
  status
)
values (
  'f2000000-0000-0000-0000-000000000051',
  'f2000000-0000-0000-0000-000000000001',
  'f2000000-0000-0000-0000-000000000012',
  'Caja Principal',
  'active'
);

insert into public.receipt_sequences (
  id,
  business_id,
  branch_id,
  name,
  prefix,
  status
)
values
  (
    'f2000000-0000-0000-0000-000000000052',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000012',
    'Existing Receipts',
    'EX',
    'active'
  ),
  (
    'f2000000-0000-0000-0000-000000000059',
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000019',
    'Inactive POS',
    'POS',
    'inactive'
  );

-- 1. Owner capability creates missing register and sequence for an existing branch.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000201', true);
do $$
declare
  v_result jsonb := public.ensure_business_runtime_setup(
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000011',
    null,
    '{}'::jsonb
  );
begin
  if not coalesce((v_result->>'runtime_ready')::boolean, false)
     or coalesce((v_result->>'branch_created')::boolean, true)
     or not coalesce((v_result->>'cash_register_created')::boolean, false)
     or not coalesce((v_result->>'receipt_sequence_created')::boolean, false)
     or coalesce((v_result->>'owner_membership_created')::boolean, true)
  then
    raise exception 'Case 1 failed: owner runtime creation: %', v_result;
  end if;
end;
$$;

select pass('1. owner with settings.business creates missing runtime');

-- 2. Runtime setup cannot create an absent branch, even for an administrator.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000202', true);
select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000018',
      null, '{}'::jsonb, 'Admin Explicit Branch'
    )$$,
  '42501',
  'Runtime setup cannot create branches; use create_business_branch or private platform onboarding',
  '2. runtime setup cannot create an absent branch'
);

-- 3. Repeating owner setup returns the existing ids without duplication.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000201', true);
do $$
declare
  v_result jsonb;
  v_cash_id uuid;
  v_sequence_id uuid;
begin
  select id into v_cash_id
  from public.cash_registers
  where branch_id = 'f2000000-0000-0000-0000-000000000011';

  select id into v_sequence_id
  from public.receipt_sequences
  where branch_id = 'f2000000-0000-0000-0000-000000000011'
    and status = 'active';

  v_result := public.ensure_business_runtime_setup(
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000011'
  );

  if coalesce((v_result->>'created_anything')::boolean, true)
     or v_result->>'cash_register_id' <> v_cash_id::text
     or v_result->>'receipt_sequence_id' <> v_sequence_id::text
     or (select count(*) from public.cash_registers where branch_id = 'f2000000-0000-0000-0000-000000000011') <> 1
     or (select count(*) from public.receipt_sequences where branch_id = 'f2000000-0000-0000-0000-000000000011' and status = 'active') <> 1
  then
    raise exception 'Case 3 failed: owner idempotence: %', v_result;
  end if;
end;
$$;

select pass('3. second owner call is idempotent');

-- 4. A rejected absent-branch request leaves no organizational or runtime rows.
select ok(
  not exists (
    select 1 from public.branches
    where id = 'f2000000-0000-0000-0000-000000000018'
  )
  and not exists (
    select 1 from public.cash_registers
    where branch_id = 'f2000000-0000-0000-0000-000000000018'
  )
  and not exists (
    select 1 from public.receipt_sequences
    where branch_id = 'f2000000-0000-0000-0000-000000000018'
  ),
  '4. rejected absent branch leaves no branch or runtime artifacts'
);

-- 5-7. Non-administrative seeded roles cannot create runtime. The cashier has
-- settings.business on another branch, proving that capability does not leak
-- across branch scopes.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000203', true);
do $$
begin
  if not private.has_business_permission(
       'f2000000-0000-0000-0000-000000000001',
       'settings.business'
     )
     or private.has_branch_permission(
       'f2000000-0000-0000-0000-000000000001',
       'f2000000-0000-0000-0000-000000000013',
       'settings.business'
     )
  then
    raise exception 'Case 5 fixture failed: expected cross-branch permission split';
  end if;

  begin
    perform public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000013'
    );
    raise exception 'Case 5 failed: cashier setup succeeded';
  exception when raise_exception then
    if position('Insufficient permission' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;
select pass('5. cashier cannot create runtime');

select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000204', true);
do $$
begin
  begin
    perform public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000014'
    );
    raise exception 'Case 6 failed: warehouse setup succeeded';
  exception when raise_exception then
    if position('Insufficient permission' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;
select pass('6. warehouse cannot create runtime without administrative capability');

select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000205', true);
do $$
begin
  begin
    perform public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000015'
    );
    raise exception 'Case 7 failed: technician setup succeeded';
  exception when raise_exception then
    if position('Insufficient permission' in sqlerrm) = 0 then raise; end if;
  end;
end;
$$;
select pass('7. technician cannot create runtime without administrative capability');

-- 8. A member of another business cannot bootstrap itself into business A.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000206', true);
select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000011'
    )$$,
  'P0001',
  'Active membership does not grant access to this branch',
  '8. user from another business cannot execute setup'
);

-- 9-11. Only an existing, active, non-deleted branch of the business is a
-- valid runtime target. The common denial also avoids leaking branch details.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000201', true);
select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000021'
    )$$,
  '42501',
  'Runtime setup cannot create branches; use create_business_branch or private platform onboarding',
  '9. branch from another business is rejected without disclosure'
);

select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000016'
    )$$,
  '42501',
  'Runtime setup cannot create branches; use create_business_branch or private platform onboarding',
  '10. inactive branch is rejected without disclosure'
);

select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000017'
    )$$,
  '42501',
  'Runtime setup cannot create branches; use create_business_branch or private platform onboarding',
  '11. deleted branch is rejected without disclosure'
);

-- 12. Existing canonical runtime ids are returned unchanged.
do $$
declare
  v_result jsonb := public.ensure_business_runtime_setup(
    'f2000000-0000-0000-0000-000000000001',
    'f2000000-0000-0000-0000-000000000012'
  );
begin
  if v_result->>'cash_register_id' <> 'f2000000-0000-0000-0000-000000000051'
     or v_result->>'receipt_sequence_id' <> 'f2000000-0000-0000-0000-000000000052'
     or coalesce((v_result->>'created_anything')::boolean, true)
  then
    raise exception 'Case 12 failed: existing runtime changed: %', v_result;
  end if;
end;
$$;
select pass('12. existing runtime returns the same canonical ids');

-- 13. The repaired body contains no businesses.owner_id dependency.
select ok(
  position(
    'businesses.owner_id'
    in lower(
      pg_get_functiondef(
        'public.ensure_business_runtime_setup(uuid,uuid,uuid,jsonb,text,text,text)'::regprocedure
      )
    )
  ) = 0,
  '13. repaired function has no businesses.owner_id reference'
);

-- 14. Exactly one unambiguous public signature remains.
select is(
  (
    select count(*)::bigint
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'ensure_business_runtime_setup'
  ),
  1::bigint,
  '14. exactly one public ensure_business_runtime_setup signature exists'
);

-- 15. Supabase direct anon grant is explicitly removed.
select ok(
  has_function_privilege(
    'authenticated',
    'public.ensure_business_runtime_setup(uuid,uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.ensure_business_runtime_setup(uuid,uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  ),
  '15. authenticated can execute and anon cannot'
);

-- 16. A late failure rolls back register creation and never creates membership.
select set_config('request.jwt.claim.sub', 'f2000000-0000-0000-0000-000000000202', true);
do $$
declare
  v_memberships_before bigint;
  v_memberships_after bigint;
begin
  select count(*) into v_memberships_before from public.business_members;

  begin
    perform public.ensure_business_runtime_setup(
      'f2000000-0000-0000-0000-000000000001',
      'f2000000-0000-0000-0000-000000000019'
    );
    raise exception 'Case 16 failed: expected late receipt-sequence failure';
  exception when raise_exception then
    if position('Equivalent receipt sequence exists but is not active' in sqlerrm) = 0 then
      raise;
    end if;
  end;

  select count(*) into v_memberships_after from public.business_members;

  if exists (
       select 1 from public.cash_registers
       where branch_id = 'f2000000-0000-0000-0000-000000000019'
     )
     or v_memberships_before <> v_memberships_after
  then
    raise exception 'Case 16 failed: partial infrastructure or membership remained';
  end if;
end;
$$;
select pass('16. failure leaves no partial infrastructure or membership');

select * from finish();

rollback;
