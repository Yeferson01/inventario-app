-- P2.5B2A focused validation for inventory movement history.
-- The transaction always rolls back fixture data.

begin;

select plan(20);

select is(
  has_function_privilege(
    'anon',
    'public.list_inventory_movement_history(uuid,uuid,uuid,text,timestamptz,timestamptz,timestamptz,uuid,integer)',
    'EXECUTE'
  ),
  false,
  'IH-01 anon cannot execute inventory history'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('b5200000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'ih-reader@example.test', '', now(), '{}', '{}', now(), now()),
  ('b5200000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'ih-cost-reader@example.test', '', now(), '{}', '{}', now(), now()),
  ('b5200000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'ih-no-read@example.test', '', now(), '{}', '{}', now(), now()),
  ('b5200000-0000-0000-0000-000000000104', 'authenticated', 'authenticated', 'ih-foreign-reader@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('b5200000-0000-0000-0000-000000000101', 'IH Branch Reader', 'cashier', 'active'),
  ('b5200000-0000-0000-0000-000000000102', 'IH Business Cost Reader', 'cashier', 'active'),
  ('b5200000-0000-0000-0000-000000000103', 'IH No Read', 'cashier', 'active'),
  ('b5200000-0000-0000-0000-000000000104', 'IH Foreign Reader', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('b5200000-0000-0000-0000-000000000001', 'IH Business A', 'active'),
  ('b5200000-0000-0000-0000-000000000002', 'IH Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000001', 'IH A One', 'active'),
  ('b5200000-0000-0000-0000-000000000012', 'b5200000-0000-0000-0000-000000000001', 'IH A Two', 'active'),
  ('b5200000-0000-0000-0000-000000000013', 'b5200000-0000-0000-0000-000000000001', 'IH A Inactive', 'inactive'),
  ('b5200000-0000-0000-0000-000000000021', 'b5200000-0000-0000-0000-000000000002', 'IH B One', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('b5200000-0000-0000-0000-000000000031', 'b5200000-0000-0000-0000-000000000001', 'ih-reader-a', 'Inventory history reader A', false),
  ('b5200000-0000-0000-0000-000000000032', 'b5200000-0000-0000-0000-000000000001', 'ih-cost-reader-a', 'Inventory history cost reader A', false),
  ('b5200000-0000-0000-0000-000000000033', 'b5200000-0000-0000-0000-000000000001', 'ih-no-read-a', 'No inventory read capability', false),
  ('b5200000-0000-0000-0000-000000000034', 'b5200000-0000-0000-0000-000000000002', 'ih-reader-b', 'Inventory history reader B', false);

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
join public.permissions permission
  on permission.key = 'inventory.read'
where role.id in (
  'b5200000-0000-0000-0000-000000000031',
  'b5200000-0000-0000-0000-000000000032',
  'b5200000-0000-0000-0000-000000000034'
);

insert into public.role_permissions (role_id, permission_id)
select 'b5200000-0000-0000-0000-000000000032', permission.id
from public.permissions permission
where permission.key = 'inventory.view_costs';

insert into public.role_permissions (role_id, permission_id)
select 'b5200000-0000-0000-0000-000000000033', permission.id
from public.permissions permission
where permission.key = 'products.read';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('b5200000-0000-0000-0000-000000000041', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000031', 'active', null),
  ('b5200000-0000-0000-0000-000000000042', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000102', null, 'b5200000-0000-0000-0000-000000000032', 'active', null),
  ('b5200000-0000-0000-0000-000000000043', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000103', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000033', 'active', null),
  ('b5200000-0000-0000-0000-000000000044', 'b5200000-0000-0000-0000-000000000002', 'b5200000-0000-0000-0000-000000000104', null, 'b5200000-0000-0000-0000-000000000034', 'active', null);

insert into public.products (
  id, business_id, name, purchase_price, sale_price,
  stock_quantity, minimum_stock
)
values
  ('b5200000-0000-0000-0000-000000000201', 'b5200000-0000-0000-0000-000000000001', 'IH Product A One', 12.50, 20, 0, 0),
  ('b5200000-0000-0000-0000-000000000202', 'b5200000-0000-0000-0000-000000000001', 'IH Product A Two', 4, 8, 0, 0),
  ('b5200000-0000-0000-0000-000000000203', 'b5200000-0000-0000-0000-000000000002', 'IH Product B', 3, 6, 0, 0);

insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type,
  quantity_change, source_type, source_id, reference_type, reference_id,
  created_by, device_id, unit_cost, idempotency_key, occurred_at
)
values (
  'b5200000-0000-0000-0000-000000000101',
  'b5200000-0000-0000-0000-000000000001',
  'b5200000-0000-0000-0000-000000000011',
  'b5200000-0000-0000-0000-000000000201',
  'purchase', 20, 'purchase', 'b5200000-0000-0000-0000-000000000701',
  'purchase', 'b5200000-0000-0000-0000-000000000701',
  'b5200000-0000-0000-0000-000000000101',
  'b5200000-0000-0000-0000-000000000501',
  12.50, 'ih-purchase-a1', '2026-09-10T10:00:00Z'
);

insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type,
  quantity_change, source_type, source_id, reference_type, reference_id,
  created_by, device_id, unit_cost, idempotency_key, occurred_at
)
values
  ('b5200000-0000-0000-0000-000000000102', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000201', 'sale', -1, 'sale', 'b5200000-0000-0000-0000-000000000702', 'sale', 'b5200000-0000-0000-0000-000000000702', 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000502', 12.50, 'ih-sale-a1', '2026-09-10T10:00:00Z'),
  ('b5200000-0000-0000-0000-000000000103', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000201', 'manual_adjustment', 2, 'transfer', 'b5200000-0000-0000-0000-000000000703', 'inventory_transfer', 'b5200000-0000-0000-0000-000000000703', 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000501', 12.50, 'ih-transfer-a1', '2026-09-10T09:00:00Z'),
  ('b5200000-0000-0000-0000-000000000104', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000201', 'manual_adjustment', 3, 'manual_adjustment', null, 'manual_initial_stock', null, 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000501', null, 'ih-initial-a1', '2026-09-10T08:00:00Z'),
  ('b5200000-0000-0000-0000-000000000105', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000201', 'manual_adjustment', 1, 'manual_adjustment', null, 'manual_adjustment', null, 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000501', 0, 'ih-adjust-a1', '2026-09-10T07:00:00Z');

insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type,
  quantity_change, source_type, reference_type, created_by, device_id,
  unit_cost, idempotency_key, occurred_at, reversed_movement_id
)
values (
  'b5200000-0000-0000-0000-000000000106',
  'b5200000-0000-0000-0000-000000000001',
  'b5200000-0000-0000-0000-000000000011',
  'b5200000-0000-0000-0000-000000000201',
  'manual_adjustment', -1, 'reversal', 'inventory_reversal',
  'b5200000-0000-0000-0000-000000000101',
  'b5200000-0000-0000-0000-000000000501',
  0, 'ih-reversal-a1', '2026-09-10T06:00:00Z',
  'b5200000-0000-0000-0000-000000000105'
);

insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type,
  quantity_change, source_type, created_by, device_id,
  unit_cost, idempotency_key, occurred_at
)
values
  ('b5200000-0000-0000-0000-000000000201', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000011', 'b5200000-0000-0000-0000-000000000202', 'purchase', 5, 'purchase', 'b5200000-0000-0000-0000-000000000101', 'b5200000-0000-0000-0000-000000000501', 4, 'ih-product-two', '2026-09-10T11:00:00Z'),
  ('b5200000-0000-0000-0000-000000000301', 'b5200000-0000-0000-0000-000000000001', 'b5200000-0000-0000-0000-000000000012', 'b5200000-0000-0000-0000-000000000201', 'purchase', 4, 'purchase', 'b5200000-0000-0000-0000-000000000102', 'b5200000-0000-0000-0000-000000000503', 12.50, 'ih-business-wide', '2026-09-10T12:00:00Z'),
  ('b5200000-0000-0000-0000-000000000401', 'b5200000-0000-0000-0000-000000000002', 'b5200000-0000-0000-0000-000000000021', 'b5200000-0000-0000-0000-000000000203', 'purchase', 7, 'purchase', 'b5200000-0000-0000-0000-000000000104', 'b5200000-0000-0000-0000-000000000504', 3, 'ih-foreign-business', '2026-09-10T13:00:00Z');

insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type,
  quantity_change, source_type, created_by, device_id,
  unit_cost, idempotency_key, occurred_at
)
select
  md5('p2-5-b2a-bulk-' || series.value::text)::uuid,
  'b5200000-0000-0000-0000-000000000001'::uuid,
  'b5200000-0000-0000-0000-000000000011'::uuid,
  'b5200000-0000-0000-0000-000000000202'::uuid,
  'purchase',
  1,
  'purchase',
  'b5200000-0000-0000-0000-000000000101'::uuid,
  'b5200000-0000-0000-0000-000000000501'::uuid,
  4,
  'ih-bulk-' || series.value::text,
  '2026-08-01T00:00:00Z'::timestamptz + make_interval(secs => series.value)
from generate_series(1, 205) as series(value);

create temporary table p2_5_b2a_read_guard as
select
  (select count(*) from public.inventory_movements) as movement_count,
  (
    select coalesce(sum(balance.quantity_on_hand), 0)
    from public.product_stock_balances balance
  ) as total_quantity_on_hand;

reset role;
select set_config('request.jwt.claim.sub', 'b5200000-0000-0000-0000-000000000103', true);

select throws_ok(
  $$select * from public.list_inventory_movement_history(
      'b5200000-0000-0000-0000-000000000001',
      'b5200000-0000-0000-0000-000000000011'
    )$$,
  '42501',
  'Inventory history is not authorized for this branch',
  'IH-02 user without inventory.read is rejected'
);

select set_config('request.jwt.claim.sub', 'b5200000-0000-0000-0000-000000000101', true);

select ok(
  exists (
    select 1 from public.list_inventory_movement_history(
      'b5200000-0000-0000-0000-000000000001',
      'b5200000-0000-0000-0000-000000000011'
    )
  ),
  'IH-03 inventory.read can list movements in its branch'
);

select throws_ok(
  $$select * from public.list_inventory_movement_history(
      'b5200000-0000-0000-0000-000000000002',
      'b5200000-0000-0000-0000-000000000021'
    )$$,
  '42501',
  'Inventory history is not authorized for this branch',
  'IH-04 caller cannot read another business'
);

select throws_ok(
  $$select * from public.list_inventory_movement_history(
      'b5200000-0000-0000-0000-000000000001',
      'b5200000-0000-0000-0000-000000000012'
    )$$,
  '42501',
  'Inventory history is not authorized for this branch',
  'IH-05 branch-specific membership cannot read another branch'
);

select set_config('request.jwt.claim.sub', 'b5200000-0000-0000-0000-000000000102', true);

select is(
  (
    select count(*)
    from public.list_inventory_movement_history(
      'b5200000-0000-0000-0000-000000000001',
      'b5200000-0000-0000-0000-000000000012'
    )
  ),
  1::bigint,
  'IH-06 business-wide membership can read an active authorized branch'
);

select set_config('request.jwt.claim.sub', 'b5200000-0000-0000-0000-000000000101', true);

select is(
  (
    select history.unit_cost
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_source_type => 'purchase'
    ) history
    limit 1
  ),
  null::numeric,
  'IH-07 base history is visible while unit_cost remains protected'
);

select set_config('request.jwt.claim.sub', 'b5200000-0000-0000-0000-000000000102', true);

select is(
  (
    select history.unit_cost
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_source_type => 'purchase'
    ) history
    limit 1
  ),
  12.50::numeric,
  'IH-08 inventory.view_costs reveals historical unit_cost'
);

select is(
  (
    select history.unit_cost
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_source_type => 'initial_stock'
    ) history
    limit 1
  ),
  null::numeric,
  'IH-09 unknown historical cost remains NULL with permission'
);

select is(
  (
    select history.unit_cost
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_source_type => 'manual_adjustment'
    ) history
    limit 1
  ),
  0::numeric,
  'IH-10 known zero historical cost remains zero'
);

select is(
  (
    select history.id
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_limit => 3
    ) history
    limit 1
  ),
  'b5200000-0000-0000-0000-000000000102'::uuid,
  'IH-11 first page is ordered by occurred_at DESC, id DESC'
);

select is(
  (
    select array_agg(history.id)
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_cursor_occurred_at => '2026-09-10T10:00:00Z',
      p_cursor_id => 'b5200000-0000-0000-0000-000000000101',
      p_limit => 2
    ) history
  ),
  array[
    'b5200000-0000-0000-0000-000000000103'::uuid,
    'b5200000-0000-0000-0000-000000000104'::uuid
  ],
  'IH-12 cursor returns the next page without duplicates'
);

select is(
  (
    select history.id
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_cursor_occurred_at => '2026-09-10T10:00:00Z',
      p_cursor_id => 'b5200000-0000-0000-0000-000000000102',
      p_limit => 1
    ) history
    limit 1
  ),
  'b5200000-0000-0000-0000-000000000101'::uuid,
  'IH-13 equal timestamps use id DESC as deterministic tie-breaker'
);

select ok(
  (
    select count(*) = 50
       and bool_and(
         history.product_id = 'b5200000-0000-0000-0000-000000000202'
       )
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000202'
    ) history
  ),
  'IH-14 product_id filter returns only the requested product'
);

select is(
  (
    select history.effective_type
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_source_type => 'transfer'
    ) history
    limit 1
  ),
  'transfer'::text,
  'IH-15 source filter uses effective movement semantics'
);

select is(
  (
    select count(*)
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201',
      p_from => '2026-09-10T08:30:00Z',
      p_to => '2026-09-10T09:30:00Z'
    )
  ),
  1::bigint,
  'IH-16 temporal range filter is applied to occurred_at'
);

select is(
  (
    select count(*)
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000202',
      p_limit => 500
    )
  ),
  200::bigint,
  'IH-17 requested limits above the maximum are clamped to 200'
);

select ok(
  exists (
    select 1
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201'
    ) history
    where history.device_id = 'b5200000-0000-0000-0000-000000000502'
  ),
  'IH-18 authoritative history includes a movement from another device'
);

select is(
  (
    select array_agg(history.effective_type order by history.id)
    from public.list_inventory_movement_history(
      p_business_id => 'b5200000-0000-0000-0000-000000000001',
      p_branch_id => 'b5200000-0000-0000-0000-000000000011',
      p_product_id => 'b5200000-0000-0000-0000-000000000201'
    ) history
    where history.id in (
      'b5200000-0000-0000-0000-000000000103',
      'b5200000-0000-0000-0000-000000000104',
      'b5200000-0000-0000-0000-000000000106'
    )
  ),
  array['transfer', 'initial_stock', 'reversal']::text[],
  'IH-19 reversal and extended source types preserve display semantics'
);

select ok(
  (
    select guard.movement_count = (
        select count(*) from public.inventory_movements
      )
      and guard.total_quantity_on_hand = (
        select coalesce(sum(balance.quantity_on_hand), 0)
        from public.product_stock_balances balance
      )
    from p2_5_b2a_read_guard guard
  ),
  'IH-20 inventory history does not modify ledger rows or balances'
);

reset role;

select * from finish();

rollback;
