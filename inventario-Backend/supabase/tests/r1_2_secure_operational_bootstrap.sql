-- Reproducible R1.2 validation against a disposable/local Supabase database.
-- The transaction always rolls back fixture data.

begin;

select plan(52);

create temporary table r12_state (
  key text primary key,
  payload jsonb,
  token text
);

create function pg_temp.r12_rejects(p_sql text, p_message_fragment text)
returns boolean
language plpgsql
as $$
begin
  execute p_sql;
  return false;
exception when others then
  return position(p_message_fragment in sqlerrm) > 0;
end;
$$;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('a2000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'r12-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'r12-cashier@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'r12-warehouse@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000104', 'authenticated', 'authenticated', 'r12-technician@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000105', 'authenticated', 'authenticated', 'r12-no-permission@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000106', 'authenticated', 'authenticated', 'r12-custom@example.test', '', now(), '{}', '{}', now(), now()),
  ('a2000000-0000-0000-0000-000000000107', 'authenticated', 'authenticated', 'r12-other-device@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('a2000000-0000-0000-0000-000000000101', 'R1.2 Owner', 'cashier', 'active'),
  ('a2000000-0000-0000-0000-000000000102', 'R1.2 Cashier', 'owner', 'active'),
  ('a2000000-0000-0000-0000-000000000103', 'R1.2 Warehouse', 'cashier', 'active'),
  ('a2000000-0000-0000-0000-000000000104', 'R1.2 Technician', 'owner', 'active'),
  ('a2000000-0000-0000-0000-000000000105', 'R1.2 No Permission', 'owner', 'active'),
  ('a2000000-0000-0000-0000-000000000106', 'R1.2 Custom', 'cashier', 'active'),
  ('a2000000-0000-0000-0000-000000000107', 'R1.2 Other Device', 'cashier', 'active')
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    status = excluded.status;

insert into public.businesses (id, name, status)
values
  ('a2000000-0000-0000-0000-000000000001', 'R1.2 Business A', 'active'),
  ('a2000000-0000-0000-0000-000000000002', 'R1.2 Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000001', 'A One', 'active'),
  ('a2000000-0000-0000-0000-000000000012', 'a2000000-0000-0000-0000-000000000001', 'A Two', 'active'),
  ('a2000000-0000-0000-0000-000000000013', 'a2000000-0000-0000-0000-000000000001', 'A Inactive', 'inactive'),
  ('a2000000-0000-0000-0000-000000000021', 'a2000000-0000-0000-0000-000000000002', 'B One', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('a2000000-0000-0000-0000-000000000031', 'a2000000-0000-0000-0000-000000000001', 'r12-no-permission', 'No bundle capabilities', false),
  ('a2000000-0000-0000-0000-000000000032', 'a2000000-0000-0000-0000-000000000001', 'r12-product-custom', 'Custom inventory capability', false);

insert into public.role_permissions (role_id, permission_id)
select 'a2000000-0000-0000-0000-000000000032', p.id
from public.permissions p
where p.key = 'inventory.purchase';

do $$
begin
  if exists (
    select 1
    from (values ('owner'), ('cashier'), ('warehouse'), ('technician')) names(name)
    where not exists (
      select 1 from public.roles r
      where r.business_id is null
        and r.name = names.name
        and r.deleted_at is null
    )
  ) then
    raise exception 'R1.2 fixture requires seeded system roles';
  end if;
end;
$$;

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('a2000000-0000-0000-0000-000000000041', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000101', null, (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('a2000000-0000-0000-0000-000000000042', 'a2000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000101', null, (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('a2000000-0000-0000-0000-000000000043', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000102', 'a2000000-0000-0000-0000-000000000011', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1), 'active', null),
  ('a2000000-0000-0000-0000-000000000044', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000103', 'a2000000-0000-0000-0000-000000000011', (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null limit 1), 'active', null),
  ('a2000000-0000-0000-0000-000000000045', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000104', 'a2000000-0000-0000-0000-000000000011', (select id from public.roles where business_id is null and name = 'technician' and deleted_at is null limit 1), 'active', null),
  ('a2000000-0000-0000-0000-000000000046', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000105', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000031', 'active', null),
  ('a2000000-0000-0000-0000-000000000047', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000106', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000032', 'active', null),
  ('a2000000-0000-0000-0000-000000000048', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000107', 'a2000000-0000-0000-0000-000000000011', (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1), 'active', null);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values
  ('a2000000-0000-0000-0000-000000000051', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000101', 'a2000000-0000-0000-0000-000000000011', 'r12-owner-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000052', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000101', 'a2000000-0000-0000-0000-000000000012', 'r12-owner-a2', 'active'),
  ('a2000000-0000-0000-0000-000000000053', 'a2000000-0000-0000-0000-000000000002', 'a2000000-0000-0000-0000-000000000101', 'a2000000-0000-0000-0000-000000000021', 'r12-owner-b1', 'active'),
  ('a2000000-0000-0000-0000-000000000054', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000102', 'a2000000-0000-0000-0000-000000000011', 'r12-cashier-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000055', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000103', 'a2000000-0000-0000-0000-000000000011', 'r12-warehouse-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000056', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000104', 'a2000000-0000-0000-0000-000000000011', 'r12-technician-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000057', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000105', 'a2000000-0000-0000-0000-000000000011', 'r12-no-permission-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000058', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000106', 'a2000000-0000-0000-0000-000000000011', 'r12-custom-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000059', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000107', 'a2000000-0000-0000-0000-000000000011', 'r12-other-a1', 'active'),
  ('a2000000-0000-0000-0000-000000000060', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000101', 'a2000000-0000-0000-0000-000000000011', 'r12-blocked-a1', 'blocked');

insert into public.categories (id, business_id, name)
values
  ('a2000000-0000-0000-0000-000000000061', 'a2000000-0000-0000-0000-000000000001', 'R1.2 Active'),
  ('a2000000-0000-0000-0000-000000000062', 'a2000000-0000-0000-0000-000000000001', 'R1.2 Tombstone');

insert into public.products (
  id, business_id, category_id, name, sale_price, stock_quantity, minimum_stock
)
select
  md5('r12-product-' || g)::uuid,
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000061',
  'R1.2 Product ' || g,
  100 + g,
  999999,
  3
from generate_series(1, 1005) g;

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id, quantity_on_hand,
  quantity_reserved, average_cost
)
select
  md5('r12-balance-' || g)::uuid,
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000011',
  md5('r12-product-' || g)::uuid,
  g,
  0,
  10
from generate_series(1, 1005) g;

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id, quantity_on_hand
)
values (
  'a2000000-0000-0000-0000-000000000063',
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000012',
  md5('r12-product-1')::uuid,
  777
);

insert into public.product_barcodes (
  id, business_id, product_id, barcode, barcode_normalized, scope, is_primary
)
values (
  'a2000000-0000-0000-0000-000000000064',
  'a2000000-0000-0000-0000-000000000001',
  md5('r12-product-1')::uuid,
  'R12000001',
  'R12000001',
  'business',
  true
);

update public.categories
set deleted_at = now(), delete_reason = 'R1.2 tombstone fixture'
where id = 'a2000000-0000-0000-0000-000000000062';

update public.products
set deleted_at = now(), delete_reason = 'R1.2 tombstone fixture'
where id = md5('r12-product-1')::uuid;

update public.product_stock_balances
set deleted_at = now(), delete_reason = 'R1.2 tombstone fixture'
where id = md5('r12-balance-2')::uuid;

insert into public.cash_registers (id, business_id, branch_id, name, status)
values
  ('a2000000-0000-0000-0000-000000000071', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000011', 'A1 Register', 'active'),
  ('a2000000-0000-0000-0000-000000000072', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000012', 'A2 Register', 'active');

insert into public.cash_sessions (
  id, business_id, branch_id, cash_register_id, opened_by,
  closed_by, opening_amount, expected_closing_amount,
  actual_closing_amount, difference_amount, status, closed_at
)
values
  ('a2000000-0000-0000-0000-000000000073', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000071', 'a2000000-0000-0000-0000-000000000102', null, 50000, 60000, null, null, 'open', null),
  ('a2000000-0000-0000-0000-000000000074', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000071', 'a2000000-0000-0000-0000-000000000102', 'a2000000-0000-0000-0000-000000000102', 1000, 2000, 2000, 0, 'closed', now()),
  ('a2000000-0000-0000-0000-000000000075', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000012', 'a2000000-0000-0000-0000-000000000072', 'a2000000-0000-0000-0000-000000000101', null, 7000, 8000, null, null, 'open', null);

insert into public.sales (
  id, business_id, branch_id, user_id, cash_session_id, device_id,
  total, subtotal, paid_total, payment_method, status
)
values
  ('a2000000-0000-0000-0000-000000000081', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000102', 'a2000000-0000-0000-0000-000000000073', 'a2000000-0000-0000-0000-000000000054', 10000, 10000, 10000, 'cash', 'completed'),
  ('a2000000-0000-0000-0000-000000000082', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000011', 'a2000000-0000-0000-0000-000000000102', 'a2000000-0000-0000-0000-000000000074', 'a2000000-0000-0000-0000-000000000054', 2000, 2000, 2000, 'cash', 'completed'),
  ('a2000000-0000-0000-0000-000000000083', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000012', 'a2000000-0000-0000-0000-000000000101', 'a2000000-0000-0000-0000-000000000075', 'a2000000-0000-0000-0000-000000000052', 3000, 3000, 3000, 'cash', 'completed');

insert into public.sale_items (
  id, sale_id, business_id, product_id, product_name_snapshot,
  quantity, unit_price, subtotal, total
)
values
  ('a2000000-0000-0000-0000-000000000084', 'a2000000-0000-0000-0000-000000000081', 'a2000000-0000-0000-0000-000000000001', md5('r12-product-3')::uuid, 'Open sale item', 1, 10000, 10000, 10000),
  ('a2000000-0000-0000-0000-000000000085', 'a2000000-0000-0000-0000-000000000082', 'a2000000-0000-0000-0000-000000000001', md5('r12-product-4')::uuid, 'Closed sale item', 1, 2000, 2000, 2000);

insert into public.sale_payments (
  id, business_id, sale_id, payment_method, amount, status
)
values
  ('a2000000-0000-0000-0000-000000000086', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000081', 'cash', 10000, 'completed'),
  ('a2000000-0000-0000-0000-000000000087', 'a2000000-0000-0000-0000-000000000001', 'a2000000-0000-0000-0000-000000000082', 'cash', 2000, 'completed');

insert into public.sync_cursors (
  id, business_id, app_device_id, profile_id, branch_id, entity_table,
  last_pulled_at, cursor_token
)
values (
  'a2000000-0000-0000-0000-000000000091',
  'a2000000-0000-0000-0000-000000000001',
  'a2000000-0000-0000-0000-000000000051',
  'a2000000-0000-0000-0000-000000000101',
  'a2000000-0000-0000-0000-000000000011',
  'products',
  '2020-01-02 03:04:05',
  'r12-cursor-before'
);

-- 1-3. Installed contract and ACL.
select has_function(
  'public',
  'pull_operational_bootstrap_snapshot',
  array['uuid', 'uuid', 'uuid', 'text', 'text', 'integer', 'text'],
  '1. dedicated operational bootstrap RPC exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.pull_operational_bootstrap_snapshot(uuid,uuid,uuid,text,text,integer,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.pull_operational_bootstrap_snapshot(uuid,uuid,uuid,text,text,integer,text)',
    'EXECUTE'
  ),
  '2. bootstrap RPC is executable by authenticated but not anon'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.authorize_operational_device_context(uuid,uuid,uuid,boolean)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.pull_operational_bootstrap_dataset_page(text,uuid,uuid,timestamp with time zone,uuid,integer,uuid[])',
    'EXECUTE'
  ),
  '3. bootstrap implementation helpers remain private'
);

select set_config('request.jwt.claim.sub', '', true);
select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000051','core')$$,
    'Authentication required'
  ),
  '4. unauthenticated bootstrap is rejected'
);

-- 5-8. Core and capability-based bundle authorization.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000101', true);
insert into r12_state (key, payload)
values (
  'core-owner',
  public.pull_operational_bootstrap_snapshot(
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000051',
    'core'
  )
);

select is(
  (select payload->'datasets'->'context'->>'count' from r12_state where key = 'core-owner'),
  '1',
  '5. core bundle returns one revalidated operational context'
);

select is(
  (select payload->'datasets'->'context'->'rows'->0->>'profile_id' from r12_state where key = 'core-owner'),
  'a2000000-0000-0000-0000-000000000101',
  '6. core context derives profile identity from auth.uid()'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000104', true);
select lives_ok(
  $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000056','product_operational')$$,
  '7. technician capability authorizes product bundle regardless of profile role label'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000106', true);
select lives_ok(
  $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000058','product_operational')$$,
  '8. custom role capability authorizes product bundle without role-name comparison'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000105', true);
select lives_ok(
  $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000057','core')$$,
  '9. active member without bundle capability may still resolve core context'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000057','product_operational')$$,
    'do not authorize product_operational'
  ),
  '10. product bundle rejects a member without required capability'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000057','cash_pos')$$,
    'do not authorize cash_pos'
  ),
  '11. cash bundle rejects a member without required capability'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000103', true);
select lives_ok(
  $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000055','product_operational')$$,
  '12. warehouse inventory capability authorizes product bundle'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000055','cash_pos')$$,
    'do not authorize cash_pos'
  ),
  '13. warehouse role is denied cash bundle because its capabilities do not grant it'
);

-- 14-25. Product/balance completeness, paging, scope, tombstones and tokens.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000102', true);
select lives_ok(
  $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000054','product_operational')$$,
  '14. cashier sales/inventory capabilities authorize product bundle'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000101', true);
insert into r12_state (key, payload)
values (
  'product-initial',
  public.pull_operational_bootstrap_snapshot(
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000051',
    'product_operational',
    null,
    1000
  )
);

update r12_state
set token = payload->'datasets'->'products'->>'next_page_token'
where key = 'product-initial';

-- Create an identity after page one and after the fixed snapshot cutoff. Its
-- high UUID guarantees it would otherwise be visible on page two.
insert into public.products (
  id, business_id, name, sale_price, created_at
)
select
  'ffffffff-ffff-ffff-ffff-fffffffffff1',
  'a2000000-0000-0000-0000-000000000001',
  'Created after snapshot cutoff',
  1,
  (payload->>'snapshot_at')::timestamp without time zone + interval '1 second'
from r12_state
where key = 'product-initial';

insert into r12_state (key, payload)
select
  'product-second',
  public.pull_operational_bootstrap_snapshot(
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000051',
    'product_operational',
    'products',
    1,
    token
  )
from r12_state
where key = 'product-initial';

select is(
  (select payload->'datasets'->'products'->>'count' from r12_state where key = 'product-initial'),
  '1000',
  '15. first products page reaches the explicit 1000-row maximum without truncating the snapshot'
);

select ok(
  (select (payload->'datasets'->'products'->>'has_more')::boolean and token is not null from r12_state where key = 'product-initial'),
  '16. first products page returns a continuation token'
);

select is(
  (select payload->'datasets'->'products'->>'count' from r12_state where key = 'product-second'),
  '5',
  '17. second products page returns all remaining rows beyond 1000'
);

select is(
  (
    select count(*)::text
    from (
      select row->>'id' id
      from r12_state s,
           lateral jsonb_array_elements(s.payload->'datasets'->'products'->'rows') row
      where s.key in ('product-initial', 'product-second')
      group by row->>'id'
    ) distinct_products
  ),
  '1005',
  '18. complete products pagination has 1005 distinct rows'
);

select is(
  (select payload->>'snapshot_id' from r12_state where key = 'product-second'),
  (select payload->>'snapshot_id' from r12_state where key = 'product-initial'),
  '19. product continuation preserves the same snapshot identity'
);

update r12_state
set token = payload->'datasets'->'product_stock_balances'->>'next_page_token'
where key = 'product-initial';

insert into r12_state (key, payload)
select
  'balance-second',
  public.pull_operational_bootstrap_snapshot(
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000051',
    'product_operational',
    'product_stock_balances',
    1000,
    token
  )
from r12_state
where key = 'product-initial';

select is(
  (select payload->'datasets'->'product_stock_balances'->>'count' from r12_state where key = 'product-initial'),
  '1000',
  '20. first branch-balance page returns 1000 rows'
);

select is(
  (select payload->'datasets'->'product_stock_balances'->>'count' from r12_state where key = 'balance-second'),
  '5',
  '21. second branch-balance page returns all remaining rows'
);

select is(
  (
    select count(*)::text
    from (
      select row->>'id' id
      from r12_state s,
           lateral jsonb_array_elements(s.payload->'datasets'->'product_stock_balances'->'rows') row
      where s.key in ('product-initial', 'balance-second')
      group by row->>'id'
    ) distinct_balances
  ),
  '1005',
  '22. complete balance pagination has 1005 distinct branch-scoped rows'
);

select ok(
  not exists (
    select 1
    from r12_state s,
         lateral jsonb_array_elements(s.payload->'datasets'->'product_stock_balances'->'rows') row
    where s.key in ('product-initial', 'balance-second')
      and row->>'branch_id' <> 'a2000000-0000-0000-0000-000000000011'
  ),
  '23. product stock balances are restricted to the explicit branch'
);

select ok(
  exists (
    select 1
    from r12_state s,
         lateral jsonb_array_elements(s.payload->'datasets'->'products'->'rows') row
    where s.key in ('product-initial', 'product-second')
      and row->>'id' = md5('r12-product-1')::uuid::text
      and row->>'_bootstrap_record_state' = 'tombstone'
  ),
  '24. soft-deleted product is included as an explicit tombstone'
);

select ok(
  exists (
    select 1
    from r12_state s,
         lateral jsonb_array_elements(s.payload->'datasets'->'product_stock_balances'->'rows') row
    where s.key in ('product-initial', 'balance-second')
      and row->>'id' = md5('r12-balance-2')::uuid::text
      and row->>'_bootstrap_record_state' = 'tombstone'
  ),
  '25. soft-deleted stock balance is included as an explicit tombstone'
);

select ok(
  exists (
    select 1
    from r12_state s,
         lateral jsonb_array_elements(s.payload->'datasets'->'categories'->'rows') row
    where s.key = 'product-initial'
      and row->>'id' = 'a2000000-0000-0000-0000-000000000062'
      and row->>'_bootstrap_record_state' = 'tombstone'
  ),
  '26. soft-deleted category is included as an explicit tombstone'
);

select is(
  (select payload->'datasets'->'product_barcodes'->>'count' from r12_state where key = 'product-initial'),
  '1',
  '27. product bundle includes scoped barcode metadata'
);

select ok(
  pg_temp.r12_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000051','product_operational','product_stock_balances',1000,%L)$$,
      (select payload->'datasets'->'products'->>'next_page_token' from r12_state where key = 'product-initial')
    ),
    'scope mismatch'
  ),
  '28. product token cannot be reused for a different dataset'
);

select ok(
  pg_temp.r12_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000021','a2000000-0000-0000-0000-000000000053','product_operational','products',1000,%L)$$,
      (select payload->'datasets'->'products'->>'next_page_token' from r12_state where key = 'product-initial')
    ),
    'scope mismatch'
  ),
  '29. page token cannot cross business or branch scope'
);

select ok(
  pg_temp.r12_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000051','product_operational','products',1000,%L)$$,
      (select payload->'datasets'->'products'->>'next_page_token' || '0' from r12_state where key = 'product-initial')
    ),
    'Invalid operational bootstrap page token'
  ),
  '30. tampered page token is rejected by its signature'
);

-- 31-32. Fixed identity window: later identities stay out; cursors stay untouched.
select ok(
  not exists (
    select 1
    from r12_state s,
         lateral jsonb_array_elements(s.payload->'datasets'->'products'->'rows') row
    where s.key in ('product-initial', 'product-second')
      and row->>'id' = 'ffffffff-ffff-ffff-ffff-fffffffffff1'
  ),
  '31. identities created after snapshot cutoff are excluded from continuation pages'
);

select ok(
  exists (
    select 1 from public.sync_cursors sc
    where sc.id = 'a2000000-0000-0000-0000-000000000091'
      and sc.last_pulled_at = '2020-01-02 03:04:05'
      and sc.cursor_token = 'r12-cursor-before'
  )
  and (select (payload->>'sync_cursor_read')::boolean is false from r12_state where key = 'product-initial')
  and (select (payload->>'sync_cursor_advanced')::boolean is false from r12_state where key = 'product-initial'),
  '32. bootstrap neither reads nor advances incremental sync cursors'
);

-- 33-38. Cash/POS bundle contains only open-session operational dependencies.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000102', true);
insert into r12_state (key, payload)
values (
  'cash-cashier',
  public.pull_operational_bootstrap_snapshot(
    'a2000000-0000-0000-0000-000000000001',
    'a2000000-0000-0000-0000-000000000011',
    'a2000000-0000-0000-0000-000000000054',
    'cash_pos'
  )
);

select is(
  (select payload->'datasets'->'cash_registers'->>'count' from r12_state where key = 'cash-cashier'),
  '1',
  '33. cash bundle returns registers only for the explicit branch'
);

select is(
  (select payload->'datasets'->'open_cash_sessions'->>'count' from r12_state where key = 'cash-cashier'),
  '1',
  '34. cash bundle returns only currently open sessions in its fixed session set'
);

select is(
  (select (payload->'datasets'->'open_cash_sessions'->'rows'->0->>'opening_cash_amount')::numeric from r12_state where key = 'cash-cashier'),
  50000::numeric,
  '35. open-session payload supplies the opening cash amount needed by close calculations'
);

select is(
  (select payload->'datasets'->'session_sales'->'rows'->0->>'id' from r12_state where key = 'cash-cashier'),
  'a2000000-0000-0000-0000-000000000081',
  '36. cash bundle includes sales only from the frozen open session set'
);

select is(
  (select payload->'datasets'->'session_sale_items'->'rows'->0->>'id' from r12_state where key = 'cash-cashier'),
  'a2000000-0000-0000-0000-000000000084',
  '37. cash bundle includes the open session sale items'
);

select is(
  (select (payload->'datasets'->'session_sale_payments'->'rows'->0->>'amount')::numeric from r12_state where key = 'cash-cashier'),
  10000::numeric,
  '38. cash bundle includes completed cash payment data needed to calculate expected cash'
);

-- 39-43. Every call revalidates membership, branch, device and device owner.
update public.business_members set status = 'suspended'
where id = 'a2000000-0000-0000-0000-000000000043';

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000054','core')$$,
    'No active membership grants access'
  ),
  '39. inactive membership is rejected on a fresh bootstrap call'
);

update public.business_members set status = 'active', deleted_at = now()
where id = 'a2000000-0000-0000-0000-000000000043';

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000054','core')$$,
    'No active membership grants access'
  ),
  '40. deleted membership is rejected on a fresh bootstrap call'
);

update public.business_members set deleted_at = null
where id = 'a2000000-0000-0000-0000-000000000043';

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000013','a2000000-0000-0000-0000-000000000054','core')$$,
    'Branch is inactive or deleted'
  ),
  '41. inactive explicit branch is rejected'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000101', true);
select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000060','core')$$,
    'inactive, blocked, or deleted'
  ),
  '42. blocked device cannot bootstrap'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000052','core')$$,
    'not registered for the requested branch'
  ),
  '43. device registered to another branch cannot bootstrap the requested branch'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000059','core')$$,
    'does not belong to the authenticated profile'
  ),
  '44. bootstrap cannot use another profile device even in the same branch'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000053','core')$$,
    'does not belong to this business'
  ),
  '45. app device from another business is rejected'
);

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000021','a2000000-0000-0000-0000-000000000051','core')$$,
    'Branch does not belong to this business'
  ),
  '46. explicit branch from another business is rejected'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000102', true);
select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000021','a2000000-0000-0000-0000-000000000053','core')$$,
    'No active membership grants access'
  ),
  '47. authenticated profile without the requested context is rejected'
);

select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000101', true);
update public.business_members set status = 'suspended'
where id = 'a2000000-0000-0000-0000-000000000041';

select ok(
  pg_temp.r12_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000011','a2000000-0000-0000-0000-000000000051','product_operational','products',1000,%L)$$,
      (select payload->'datasets'->'products'->>'next_page_token' from r12_state where key = 'product-initial')
    ),
    'No active membership grants access'
  ),
  '48. membership revocation immediately blocks a bootstrap continuation page'
);

update public.business_members set status = 'active'
where id = 'a2000000-0000-0000-0000-000000000041';

update public.branches set deleted_at = now()
where id = 'a2000000-0000-0000-0000-000000000013';

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_operational_bootstrap_snapshot('a2000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000013','a2000000-0000-0000-0000-000000000051','core')$$,
    'Branch is inactive or deleted'
  ),
  '49. deleted branch is rejected'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.pull_sync_changes_v2(uuid,timestamp without time zone,text[],integer,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.pull_sync_changes_v2(uuid,timestamp without time zone,text[],integer,jsonb)',
    'EXECUTE'
  ),
  '50. hardened incremental V2 preserves authenticated and denies anon execute'
);

-- 51-52. Incremental V2 keeps its datasets but closes the revocation gap.
select set_config('request.jwt.claim.sub', 'a2000000-0000-0000-0000-000000000102', true);
select lives_ok(
  $$select public.pull_sync_changes_v2('a2000000-0000-0000-0000-000000000054','2020-01-01',array['products'],10,'{}'::jsonb)$$,
  '51. hardened incremental V2 remains callable for an active authorized device'
);

update public.business_members set status = 'suspended'
where id = 'a2000000-0000-0000-0000-000000000043';

select ok(
  pg_temp.r12_rejects(
    $$select public.pull_sync_changes_v2('a2000000-0000-0000-0000-000000000054','2020-01-01',array['products'],10,'{}'::jsonb)$$,
    'No active membership grants access'
  ),
  '52. hardened incremental V2 rejects a revoked membership even while device remains active'
);

select * from finish();

rollback;
