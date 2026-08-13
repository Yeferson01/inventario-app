-- Reproducible R1.1 validation.
-- Run after all migrations against a disposable/local Supabase database:
--   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" \
--     -f supabase/tests/r1_1_operational_bootstrap_security.sql
--
-- The transaction always rolls back fixture data.

begin;

select plan(15);

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
  ('f1000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'r11-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('f1000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'r11-cashier@example.test', '', now(), '{}', '{}', now(), now()),
  ('f1000000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'r11-combined@example.test', '', now(), '{}', '{}', now(), now()),
  ('f1000000-0000-0000-0000-000000000104', 'authenticated', 'authenticated', 'r11-revoked@example.test', '', now(), '{}', '{}', now(), now()),
  ('f1000000-0000-0000-0000-000000000105', 'authenticated', 'authenticated', 'r11-runtime-cashier@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('f1000000-0000-0000-0000-000000000101', 'R1.1 Owner', 'cashier', 'active'),
  ('f1000000-0000-0000-0000-000000000102', 'R1.1 Cashier', 'cashier', 'active'),
  ('f1000000-0000-0000-0000-000000000103', 'R1.1 Combined', 'cashier', 'active'),
  ('f1000000-0000-0000-0000-000000000104', 'R1.1 Revoked', 'cashier', 'active'),
  ('f1000000-0000-0000-0000-000000000105', 'R1.1 Runtime Cashier', 'cashier', 'active')
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    status = excluded.status;

insert into public.businesses (id, name, status)
values
  ('f1000000-0000-0000-0000-000000000001', 'R1.1 Business A', 'active'),
  ('f1000000-0000-0000-0000-000000000002', 'R1.1 Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('f1000000-0000-0000-0000-000000000011', 'f1000000-0000-0000-0000-000000000001', 'A One', 'active'),
  ('f1000000-0000-0000-0000-000000000012', 'f1000000-0000-0000-0000-000000000001', 'A Two', 'active'),
  ('f1000000-0000-0000-0000-000000000013', 'f1000000-0000-0000-0000-000000000001', 'A Inactive', 'inactive'),
  ('f1000000-0000-0000-0000-000000000021', 'f1000000-0000-0000-0000-000000000002', 'B One', 'active');

insert into public.roles (
  id,
  business_id,
  name,
  description,
  is_system_role
)
values
  ('f1000000-0000-0000-0000-000000000031', 'f1000000-0000-0000-0000-000000000001', 'r11-adjust-a', 'R1.1 custom role A', false),
  ('f1000000-0000-0000-0000-000000000032', 'f1000000-0000-0000-0000-000000000002', 'r11-adjust-b', 'R1.1 custom role B', false);

insert into public.role_permissions (role_id, permission_id)
select 'f1000000-0000-0000-0000-000000000031', p.id
from public.permissions p
where p.key = 'inventory.adjust';

do $$
begin
  if not exists (
    select 1 from public.roles
    where business_id is null and name = 'owner' and deleted_at is null
  ) or not exists (
    select 1 from public.roles
    where business_id is null and name = 'cashier' and deleted_at is null
  ) then
    raise exception 'R1.1 fixture requires the seeded owner and cashier system roles';
  end if;
end;
$$;

insert into public.business_members (
  id,
  business_id,
  profile_id,
  branch_id,
  role_id,
  status,
  deleted_at
)
values
  (
    'f1000000-0000-0000-0000-000000000041',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000101',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000042',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000102',
    'f1000000-0000-0000-0000-000000000011',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000043',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000103',
    null,
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000044',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000103',
    'f1000000-0000-0000-0000-000000000011',
    'f1000000-0000-0000-0000-000000000031',
    'active',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000045',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000104',
    null,
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'suspended',
    null
  ),
  (
    'f1000000-0000-0000-0000-000000000046',
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000104',
    'f1000000-0000-0000-0000-000000000012',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active',
    now()
  ),
  (
    'f1000000-0000-0000-0000-000000000047',
    'f1000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000105',
    'f1000000-0000-0000-0000-000000000021',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active',
    null
  );

insert into public.cash_registers (
  id,
  business_id,
  branch_id,
  name,
  status
)
values (
  'f1000000-0000-0000-0000-000000000051',
  'f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000011',
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
values (
  'f1000000-0000-0000-0000-000000000052',
  'f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000011',
  'R1.1 Receipts',
  'R11',
  'active'
);

insert into public.cash_sessions (
  id,
  business_id,
  branch_id,
  cash_register_id,
  opened_by,
  status
)
values (
  'f1000000-0000-0000-0000-000000000053',
  'f1000000-0000-0000-0000-000000000001',
  'f1000000-0000-0000-0000-000000000011',
  'f1000000-0000-0000-0000-000000000051',
  'f1000000-0000-0000-0000-000000000102',
  'open'
);

-- 1 + 3. Owner/business-level membership expands to every active branch.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000101', true);
do $$
declare
  v_result jsonb := public.list_authorized_operational_contexts();
begin
  if jsonb_array_length(v_result->'contexts') <> 2
     or not (v_result->'contexts') @> '[{"branch_id":"f1000000-0000-0000-0000-000000000011"}]'::jsonb
     or not (v_result->'contexts') @> '[{"branch_id":"f1000000-0000-0000-0000-000000000012"}]'::jsonb
  then
    raise exception 'Cases 1/3 failed: owner business-level expansion: %', v_result;
  end if;
end;
$$;

select pass('1. owner business-level membership discovers authorized branches');
select pass('3. business-level membership expands to active branches of its business');

-- 2 + 7. A branch-specific cashier sees only that active branch.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000102', true);
do $$
declare
  v_result jsonb := public.list_authorized_operational_contexts();
begin
  if jsonb_array_length(v_result->'contexts') <> 1
     or v_result->'contexts'->0->>'branch_id' <> 'f1000000-0000-0000-0000-000000000011'
  then
    raise exception 'Cases 2/7 failed: branch-specific cashier: %', v_result;
  end if;
end;
$$;

select pass('2. branch-specific cashier discovers only its branch');
select pass('7. inactive branch is excluded from discovery');

-- 4. Business-level + branch membership returns one branch and unions permissions.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000103', true);
do $$
declare
  v_result jsonb := public.list_authorized_operational_contexts();
  v_branch jsonb;
begin
  select value
  into v_branch
  from jsonb_array_elements(v_result->'contexts')
  where value->>'branch_id' = 'f1000000-0000-0000-0000-000000000011';

  if v_branch is null
     or jsonb_array_length(v_branch->'membership_ids') <> 2
     or not (v_branch->'effective_permissions') ? 'sales.create'
     or not (v_branch->'effective_permissions') ? 'inventory.adjust'
  then
    raise exception 'Case 4 failed: deduplication/permission union: %', v_result;
  end if;
end;
$$;

select pass('4. overlapping memberships deduplicate branch and union permissions');

-- 5 + 6. Suspended and soft-deleted memberships produce no contexts.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000104', true);
do $$
declare
  v_result jsonb := public.list_authorized_operational_contexts();
begin
  if jsonb_array_length(v_result->'contexts') <> 0 then
    raise exception 'Cases 5/6 failed: revoked memberships: %', v_result;
  end if;
end;
$$;

select pass('5. inactive membership is excluded from discovery');
select pass('6. soft-deleted membership is excluded from discovery');

-- 8. A membership cannot point at a branch from another business.
do $$
begin
  begin
    insert into public.business_members (
      business_id,
      profile_id,
      branch_id,
      role_id,
      status
    )
    values (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000105',
      'f1000000-0000-0000-0000-000000000021',
      (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
      'active'
    );
    raise exception 'Case 8 failed: cross-business branch was accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.branches
    set business_id = 'f1000000-0000-0000-0000-000000000002'
    where id = 'f1000000-0000-0000-0000-000000000011';
    raise exception 'Case 8 failed: referenced branch ownership was changed';
  exception
    when check_violation then null;
  end;
end;
$$;

select pass('8. cross-business branch membership and ownership changes are rejected');

-- 9. A membership cannot use a custom role from another business.
do $$
begin
  begin
    insert into public.business_members (
      business_id,
      profile_id,
      branch_id,
      role_id,
      status
    )
    values (
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000105',
      'f1000000-0000-0000-0000-000000000012',
      'f1000000-0000-0000-0000-000000000032',
      'active'
    );
    raise exception 'Case 9 failed: cross-business custom role was accepted';
  exception
    when check_violation then null;
  end;

  begin
    update public.roles
    set business_id = 'f1000000-0000-0000-0000-000000000002'
    where id = 'f1000000-0000-0000-0000-000000000031';
    raise exception 'Case 9 failed: referenced custom role ownership was changed';
  exception
    when check_violation then null;
  end;
end;
$$;

select pass('9. cross-business custom role assignment and ownership changes are rejected');

-- 10. Existing runtime is resolvable by a branch-authorized cashier.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000102', true);
do $$
declare
  v_result jsonb := public.resolve_business_runtime(
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000011'
  );
begin
  if v_result->>'branch_id' <> 'f1000000-0000-0000-0000-000000000011'
     or v_result->>'cash_register_id' <> 'f1000000-0000-0000-0000-000000000051'
     or v_result->'open_cash_session'->>'cash_session_id' <> 'f1000000-0000-0000-0000-000000000053'
  then
    raise exception 'Case 10 failed: cashier runtime resolution: %', v_result;
  end if;
end;
$$;

select pass('10. cashier resolves existing runtime without administrative permission');

-- 11. A cashier cannot invoke the administrative creation contract.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000105', true);
do $$
begin
  begin
    perform public.ensure_business_runtime_setup(
      'f1000000-0000-0000-0000-000000000002'
    );
    raise exception 'Case 11 failed: cashier created administrative runtime';
  exception
    when raise_exception then
      if sqlerrm = 'Case 11 failed: cashier created administrative runtime' then
        raise;
      end if;
      if position('Insufficient permission to initialize business runtime' in sqlerrm) = 0 then
        raise;
      end if;
  end;
end;
$$;

select pass('11. cashier cannot create missing administrative runtime');

-- 12. Active device registration/update uses business + installation identity.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000102', true);
do $$
declare
  v_first jsonb;
  v_second jsonb;
begin
  v_first := public.register_or_update_app_device(
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000011',
    'r11-installation-001'
  );
  v_second := public.register_or_update_app_device(
    'f1000000-0000-0000-0000-000000000001',
    'f1000000-0000-0000-0000-000000000011',
    'r11-installation-001',
    'Updated R1.1 device'
  );

  if v_first->>'app_device_id' <> v_second->>'app_device_id'
     or v_first->>'created_or_updated' <> 'created'
     or v_second->>'created_or_updated' <> 'updated'
  then
    raise exception 'Case 12 failed: device identity/update: first=%, second=%', v_first, v_second;
  end if;
end;
$$;

select pass('12. active device registers and updates with stable installation identity');

-- 13. A blocked device cannot self-register back to active.
update public.app_devices
set status = 'blocked'
where business_id = 'f1000000-0000-0000-0000-000000000001'
  and installation_id = 'r11-installation-001';

do $$
begin
  begin
    perform public.register_or_update_app_device(
      'f1000000-0000-0000-0000-000000000001',
      'f1000000-0000-0000-0000-000000000011',
      'r11-installation-001'
    );
    raise exception 'Case 13 failed: blocked device was reactivated';
  exception
    when raise_exception then
      if sqlerrm = 'Case 13 failed: blocked device was reactivated' then
        raise;
      end if;
      if position('App device is blocked and cannot be reactivated' in sqlerrm) = 0 then
        raise;
      end if;
  end;

  if not exists (
    select 1
    from public.app_devices
    where business_id = 'f1000000-0000-0000-0000-000000000001'
      and installation_id = 'r11-installation-001'
      and status = 'blocked'
  ) then
    raise exception 'Case 13 failed: blocked status was not preserved';
  end if;
end;
$$;

select pass('13. blocked device cannot reactivate through self-registration');

-- 14. Arbitrary unauthorized business/branch UUIDs are rejected.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000102', true);
do $$
begin
  begin
    perform public.resolve_business_runtime(
      'f1000000-0000-0000-0000-000000000002',
      'f1000000-0000-0000-0000-000000000021'
    );
    raise exception 'Case 14 failed: unauthorized context was resolved';
  exception
    when raise_exception then
      if sqlerrm = 'Case 14 failed: unauthorized context was resolved' then
        raise;
      end if;
      if position('No active membership grants access' in sqlerrm) = 0 then
        raise;
      end if;
  end;

  begin
    perform public.register_or_update_app_device(
      'f1000000-0000-0000-0000-000000000002',
      'f1000000-0000-0000-0000-000000000021',
      'r11-unauthorized-installation'
    );
    raise exception 'Case 14 failed: unauthorized device was registered';
  exception
    when raise_exception then
      if sqlerrm = 'Case 14 failed: unauthorized device was registered' then
        raise;
      end if;
      if position('No active membership grants access' in sqlerrm) = 0 then
        raise;
      end if;
  end;
end;
$$;

select pass('14. unauthorized business and branch UUIDs are rejected');

-- Additional critical check. Missing runtime is reported without creation.
select set_config('request.jwt.claim.sub', 'f1000000-0000-0000-0000-000000000105', true);
do $$
declare
  v_result jsonb;
  v_registers_before bigint;
  v_registers_after bigint;
  v_sequences_before bigint;
  v_sequences_after bigint;
begin
  select count(*)
  into v_registers_before
  from public.cash_registers
  where business_id = 'f1000000-0000-0000-0000-000000000002'
    and branch_id = 'f1000000-0000-0000-0000-000000000021';

  select count(*)
  into v_sequences_before
  from public.receipt_sequences
  where business_id = 'f1000000-0000-0000-0000-000000000002'
    and branch_id = 'f1000000-0000-0000-0000-000000000021';

  v_result := public.resolve_business_runtime(
    'f1000000-0000-0000-0000-000000000002',
    'f1000000-0000-0000-0000-000000000021'
  );

  select count(*)
  into v_registers_after
  from public.cash_registers
  where business_id = 'f1000000-0000-0000-0000-000000000002'
    and branch_id = 'f1000000-0000-0000-0000-000000000021';

  select count(*)
  into v_sequences_after
  from public.receipt_sequences
  where business_id = 'f1000000-0000-0000-0000-000000000002'
    and branch_id = 'f1000000-0000-0000-0000-000000000021';

  if coalesce((v_result->>'runtime_ready')::boolean, true)
     or v_result->>'branch_id' <> 'f1000000-0000-0000-0000-000000000021'
     or v_result->>'cash_register_id' is not null
     or v_result->>'receipt_sequence_id' is not null
     or v_registers_before <> v_registers_after
     or v_sequences_before <> v_sequences_after
  then
    raise exception 'Additional runtime-missing case failed: result=%, register counts=%/%, sequence counts=%/%',
      v_result,
      v_registers_before,
      v_registers_after,
      v_sequences_before,
      v_sequences_after;
  end if;
end;
$$;

select pass('15. missing runtime resolves as not ready without creating infrastructure');

select * from finish();

rollback;
