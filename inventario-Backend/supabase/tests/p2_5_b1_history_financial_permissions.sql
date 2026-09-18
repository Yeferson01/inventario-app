-- P2.5B1 focused validation for history financial permissions.
-- The transaction always rolls back fixture data.

begin;

select plan(10);

select ok(
  exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'owner'
      and role.deleted_at is null
      and permission.key = 'sales.view_costs'
  ),
  'FP-01 owner has sales.view_costs'
);

select ok(
  exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'owner'
      and role.deleted_at is null
      and permission.key = 'inventory.view_costs'
  ),
  'FP-02 owner has inventory.view_costs'
);

select is(
  (
    select count(*)
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'admin'
      and role.deleted_at is null
      and permission.key in ('inventory.view_costs', 'sales.view_costs')
  ),
  2::bigint,
  'FP-03 admin has both financial permissions'
);

select ok(
  not exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'warehouse'
      and role.deleted_at is null
      and permission.key = 'sales.view_costs'
  ),
  'FP-04 warehouse does not receive sales.view_costs automatically'
);

select ok(
  not exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'warehouse'
      and role.deleted_at is null
      and permission.key = 'inventory.view_costs'
  ),
  'FP-05 warehouse does not receive inventory.view_costs automatically'
);

select ok(
  not exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'cashier'
      and role.deleted_at is null
      and permission.key = 'sales.view_costs'
  ),
  'FP-06 cashier does not receive sales.view_costs automatically'
);

select ok(
  not exists (
    select 1
    from public.roles role
    join public.role_permissions role_permission
      on role_permission.role_id = role.id
    join public.permissions permission
      on permission.id = role_permission.permission_id
    where role.business_id is null
      and role.name = 'cashier'
      and role.deleted_at is null
      and permission.key = 'inventory.view_costs'
  ),
  'FP-07 cashier does not receive inventory.view_costs automatically'
);

select is(
  (
    select count(*)
    from public.permissions permission
    where permission.key in ('inventory.view_costs', 'sales.view_costs')
  ),
  2::bigint,
  'FP-08 both financial permissions exist exactly once'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'b5100000-0000-0000-0000-000000000101',
    'authenticated', 'authenticated', 'p25b1-a@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'b5100000-0000-0000-0000-000000000102',
    'authenticated', 'authenticated', 'p25b1-b@example.test', '', now(),
    '{}', '{}', now(), now()
  );

insert into public.profiles (id, full_name, role, status)
values
  (
    'b5100000-0000-0000-0000-000000000101',
    'P2.5B1 Cost Viewer A', 'cashier', 'active'
  ),
  (
    'b5100000-0000-0000-0000-000000000102',
    'P2.5B1 Cost Viewer B', 'cashier', 'active'
  );

insert into public.businesses (id, name, status)
values
  (
    'b5100000-0000-0000-0000-000000000001',
    'P2.5B1 Business A', 'active'
  ),
  (
    'b5100000-0000-0000-0000-000000000002',
    'P2.5B1 Business B', 'active'
  );

insert into public.roles (
  id, business_id, name, description, is_system_role
)
values
  (
    'b5100000-0000-0000-0000-000000000031',
    'b5100000-0000-0000-0000-000000000001',
    'p25b1-cost-viewer-a', 'P2.5B1 scoped cost viewer A', false
  ),
  (
    'b5100000-0000-0000-0000-000000000032',
    'b5100000-0000-0000-0000-000000000002',
    'p25b1-cost-viewer-b', 'P2.5B1 scoped cost viewer B', false
  );

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
cross join public.permissions permission
where role.id in (
    'b5100000-0000-0000-0000-000000000031',
    'b5100000-0000-0000-0000-000000000032'
  )
  and permission.key = 'sales.view_costs';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  (
    'b5100000-0000-0000-0000-000000000041',
    'b5100000-0000-0000-0000-000000000001',
    'b5100000-0000-0000-0000-000000000101',
    null,
    'b5100000-0000-0000-0000-000000000031',
    'active', null
  ),
  (
    'b5100000-0000-0000-0000-000000000042',
    'b5100000-0000-0000-0000-000000000002',
    'b5100000-0000-0000-0000-000000000102',
    null,
    'b5100000-0000-0000-0000-000000000032',
    'active', null
  );

reset role;
select set_config(
  'request.jwt.claim.sub',
  'b5100000-0000-0000-0000-000000000101',
  true
);

select ok(
  private.has_business_permission(
    'b5100000-0000-0000-0000-000000000001',
    'sales.view_costs'
  ),
  'FP-09 has_business_permission recognizes an explicitly granted capability'
);

select set_config(
  'request.jwt.claim.sub',
  'b5100000-0000-0000-0000-000000000102',
  true
);

select is(
  private.has_business_permission(
    'b5100000-0000-0000-0000-000000000001',
    'sales.view_costs'
  ),
  false,
  'FP-10 a capability granted in another tenant remains fail-closed'
);

reset role;

select * from finish();

rollback;
