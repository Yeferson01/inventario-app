-- Reproducible R1.3b validation against a disposable/local Supabase database.
-- The transaction always rolls back fixture data.

begin;

select plan(30);

create temporary table r13b_state (
  key text primary key,
  payload jsonb,
  token text
);

create function pg_temp.r13b_rejects(p_sql text, p_message_fragment text)
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
  ('b3000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'r13b-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('b3000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'r13b-no-permission@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('b3000000-0000-0000-0000-000000000101', 'R1.3b Owner', 'cashier', 'active'),
  ('b3000000-0000-0000-0000-000000000102', 'R1.3b No Permission', 'owner', 'active')
on conflict (id) do update
set full_name = excluded.full_name,
    role = excluded.role,
    status = excluded.status;

insert into public.businesses (id, name, status)
values
  ('b3000000-0000-0000-0000-000000000001', 'R1.3b Business A', 'active'),
  ('b3000000-0000-0000-0000-000000000002', 'R1.3b Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('b3000000-0000-0000-0000-000000000011', 'b3000000-0000-0000-0000-000000000001', 'A One', 'active'),
  ('b3000000-0000-0000-0000-000000000012', 'b3000000-0000-0000-0000-000000000001', 'A Two', 'active'),
  ('b3000000-0000-0000-0000-000000000021', 'b3000000-0000-0000-0000-000000000002', 'B One', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values (
  'b3000000-0000-0000-0000-000000000031',
  'b3000000-0000-0000-0000-000000000001',
  'r13b-no-permission',
  'No bootstrap or inventory capabilities',
  false
);

do $$
begin
  if not exists (
    select 1 from public.roles r
    where r.business_id is null
      and r.name = 'owner'
      and r.deleted_at is null
  ) then
    raise exception 'R1.3b fixture requires the seeded owner system role';
  end if;
end;
$$;

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('b3000000-0000-0000-0000-000000000041', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000101', null, (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('b3000000-0000-0000-0000-000000000042', 'b3000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000101', null, (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('b3000000-0000-0000-0000-000000000043', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000102', 'b3000000-0000-0000-0000-000000000011', 'b3000000-0000-0000-0000-000000000031', 'active', null);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values
  ('b3000000-0000-0000-0000-000000000051', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000101', 'b3000000-0000-0000-0000-000000000011', 'r13b-owner-a1', 'active'),
  ('b3000000-0000-0000-0000-000000000052', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000101', 'b3000000-0000-0000-0000-000000000012', 'r13b-owner-a2', 'active'),
  ('b3000000-0000-0000-0000-000000000053', 'b3000000-0000-0000-0000-000000000002', 'b3000000-0000-0000-0000-000000000101', 'b3000000-0000-0000-0000-000000000021', 'r13b-owner-b1', 'active'),
  ('b3000000-0000-0000-0000-000000000054', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000101', 'b3000000-0000-0000-0000-000000000011', 'r13b-blocked-a1', 'blocked'),
  ('b3000000-0000-0000-0000-000000000055', 'b3000000-0000-0000-0000-000000000001', 'b3000000-0000-0000-0000-000000000102', 'b3000000-0000-0000-0000-000000000011', 'r13b-no-permission-a1', 'active');

insert into public.categories (id, business_id, name)
values (
  'b3000000-0000-0000-0000-000000000061',
  'b3000000-0000-0000-0000-000000000001',
  'R1.3b Category'
);

insert into public.products (
  id, business_id, category_id, name, sale_price, stock_quantity, minimum_stock
)
select
  md5('r13b-product-' || g)::uuid,
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000061',
  'R1.3b Product ' || g,
  100 + g,
  0,
  3
from generate_series(1, 1005) g;

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock
)
values (
  'b3000000-0000-0000-0000-000000000062',
  'b3000000-0000-0000-0000-000000000002',
  'R1.3b Foreign Product',
  100,
  0,
  0
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id, quantity_on_hand,
  quantity_reserved, average_cost
)
select
  md5('r13b-balance-' || g)::uuid,
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  md5('r13b-product-' || g)::uuid,
  100,
  0,
  10
from generate_series(1, 1005) g;

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id, quantity_on_hand,
  quantity_reserved, average_cost
)
values (
  'b3000000-0000-0000-0000-000000000063',
  'b3000000-0000-0000-0000-000000000002',
  'b3000000-0000-0000-0000-000000000021',
  'b3000000-0000-0000-0000-000000000062',
  10,
  0,
  10
);

insert into public.sync_cursors (
  id, business_id, app_device_id, profile_id, branch_id, entity_table,
  last_pulled_at, cursor_token
)
values (
  'b3000000-0000-0000-0000-000000000071',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000051',
  'b3000000-0000-0000-0000-000000000101',
  'b3000000-0000-0000-0000-000000000011',
  'product_stock_balances',
  '2020-01-02 03:04:05',
  'r13b-cursor-before'
);

select set_config('request.jwt.claim.sub', 'b3000000-0000-0000-0000-000000000101', true);

-- Direct/manual movement: sync preserves both local ID and idempotency key.
insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type, quantity_change,
  created_by, source_type, idempotency_key, sync_status, occurred_at, metadata
)
values (
  'b3000000-0000-0000-0000-000000000081',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  md5('r13b-product-1')::uuid,
  'manual_adjustment',
  5,
  'b3000000-0000-0000-0000-000000000101',
  'manual_adjustment',
  'r13b-local:inventory_movements:manual-1',
  'synced',
  now(),
  '{"fixture":"manual"}'::jsonb
);

-- Sale/POS movement: the backend generates a different movement ID and a
-- canonical key from the preserved sale and sale_item IDs.
insert into public.sales (
  id, business_id, branch_id, user_id, total, subtotal, paid_total,
  payment_method, status
)
values (
  'b3000000-0000-0000-0000-000000000082',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  'b3000000-0000-0000-0000-000000000101',
  200,
  200,
  200,
  'cash',
  'completed'
);

insert into public.sale_items (
  id, sale_id, business_id, product_id, product_name_snapshot,
  quantity, unit_price, subtotal, total
)
values (
  'b3000000-0000-0000-0000-000000000083',
  'b3000000-0000-0000-0000-000000000082',
  'b3000000-0000-0000-0000-000000000001',
  md5('r13b-product-2')::uuid,
  'R1.3b Sale Product',
  2,
  100,
  200,
  200
);

select public.apply_sale_inventory_movements(
  'b3000000-0000-0000-0000-000000000082'
);

-- Purchase movement: same parent/item correlation contract as POS.
insert into public.purchases (
  id, business_id, branch_id, user_id, total, status, processing_status
)
values (
  'b3000000-0000-0000-0000-000000000084',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  'b3000000-0000-0000-0000-000000000101',
  30,
  'completed',
  'completed'
);

insert into public.purchase_items (
  id, purchase_id, business_id, branch_id, product_id,
  quantity, unit_cost, subtotal
)
values (
  'b3000000-0000-0000-0000-000000000085',
  'b3000000-0000-0000-0000-000000000084',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  md5('r13b-product-3')::uuid,
  3,
  10,
  30
);

select public.apply_purchase_inventory_movements(
  'b3000000-0000-0000-0000-000000000084'
);

-- A partial transport state must not hide authoritative ledger evidence.
insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type, quantity_change,
  created_by, source_type, idempotency_key, sync_status, occurred_at, metadata
)
values (
  'b3000000-0000-0000-0000-000000000086',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000011',
  md5('r13b-product-4')::uuid,
  'manual_adjustment',
  4,
  'b3000000-0000-0000-0000-000000000101',
  'manual_adjustment',
  'r13b-local:inventory_movements:partial-applied',
  'synced',
  now(),
  '{"fixture":"partial"}'::jsonb
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id, client_batch_id,
  direction, status, mutation_count
)
values (
  'b3000000-0000-0000-0000-000000000087',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000051',
  'b3000000-0000-0000-0000-000000000101',
  'b3000000-0000-0000-0000-000000000011',
  'r13b-partial-applied',
  'upload',
  'pending',
  1
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, server_processed_at, server_entity_version,
  idempotency_key
)
values (
  'b3000000-0000-0000-0000-000000000088',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000087',
  'b3000000-0000-0000-0000-000000000051',
  'b3000000-0000-0000-0000-000000000101',
  'b3000000-0000-0000-0000-000000000011',
  'r13b-partial-applied-mutation',
  1,
  'inventory_movements',
  'b3000000-0000-0000-0000-000000000086',
  'insert',
  '{}'::jsonb,
  'applied',
  now(),
  1,
  'r13b-local:inventory_movements:partial-applied'
);

update public.sync_batches
set status = 'partial', applied_count = 1
where id = 'b3000000-0000-0000-0000-000000000087';

-- Terminal conflict evidence without a ledger row.
insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id, client_batch_id,
  direction, status, mutation_count
)
values (
  'b3000000-0000-0000-0000-000000000089',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000051',
  'b3000000-0000-0000-0000-000000000101',
  'b3000000-0000-0000-0000-000000000011',
  'r13b-conflict',
  'upload',
  'pending',
  1
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, server_processed_at, error_code, error_message,
  idempotency_key
)
values (
  'b3000000-0000-0000-0000-000000000090',
  'b3000000-0000-0000-0000-000000000001',
  'b3000000-0000-0000-0000-000000000089',
  'b3000000-0000-0000-0000-000000000051',
  'b3000000-0000-0000-0000-000000000101',
  'b3000000-0000-0000-0000-000000000011',
  'r13b-conflict-mutation',
  1,
  'inventory_movements',
  'b3000000-0000-0000-0000-000000000091',
  'insert',
  '{}'::jsonb,
  'conflict',
  now(),
  'validation_error',
  'Rejected fixture',
  'r13b-local:inventory_movements:rejected'
);

update public.sync_batches
set status = 'partial', conflict_count = 1
where id = 'b3000000-0000-0000-0000-000000000089';

-- Foreign-tenant idempotency evidence must be indistinguishable from missing.
insert into public.inventory_movements (
  id, business_id, branch_id, product_id, movement_type, quantity_change,
  created_by, source_type, idempotency_key, sync_status, occurred_at, metadata
)
values (
  'b3000000-0000-0000-0000-000000000092',
  'b3000000-0000-0000-0000-000000000002',
  'b3000000-0000-0000-0000-000000000021',
  'b3000000-0000-0000-0000-000000000062',
  'manual_adjustment',
  2,
  'b3000000-0000-0000-0000-000000000101',
  'manual_adjustment',
  'r13b-foreign-secret-key',
  'synced',
  now(),
  '{"fixture":"foreign"}'::jsonb
);

-- 1-2. Installed contracts and ACL.
select has_function(
  'public',
  'lookup_inventory_movement_acknowledgements',
  array['uuid', 'uuid', 'uuid', 'jsonb'],
  '1. inventory acknowledgement RPC exists'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.lookup_inventory_movement_acknowledgements(uuid,uuid,uuid,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.lookup_inventory_movement_acknowledgements(uuid,uuid,uuid,jsonb)',
    'EXECUTE'
  ),
  '2. acknowledgement ACL grants authenticated and denies anon'
);

-- 3-11. Real correlation and remote-authoritative classification.
insert into r13b_state (key, payload)
values (
  'manual',
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000081',
      'idempotency_key', 'r13b-local:inventory_movements:manual-1',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-1')::uuid,
      'quantity_change', 5
    ))
  )
);

select is(
  (select payload->'acknowledgements'->0->>'status' from r13b_state where key = 'manual'),
  'applied',
  '3. directly synced movement is acknowledged as applied'
);

select is(
  (select payload->'acknowledgements'->0->>'remote_movement_id' from r13b_state where key = 'manual'),
  'b3000000-0000-0000-0000-000000000081',
  '4. direct adjustment preserves the local movement ID remotely'
);

insert into r13b_state (key, payload)
values (
  'purchase',
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000093',
      'idempotency_key', 'local-purchase-movement-key',
      'source_type', 'purchase',
      'source_id', 'b3000000-0000-0000-0000-000000000084',
      'source_item_id', 'b3000000-0000-0000-0000-000000000085',
      'product_id', md5('r13b-product-3')::uuid,
      'quantity_change', 3
    ))
  )
);

select is(
  (select payload->'acknowledgements'->0->>'status' from r13b_state where key = 'purchase'),
  'applied',
  '5. purchase delta correlates through preserved purchase and item IDs'
);

select isnt(
  (select payload->'acknowledgements'->0->>'remote_movement_id' from r13b_state where key = 'purchase'),
  'b3000000-0000-0000-0000-000000000093',
  '6. purchase acknowledgement does not pretend the local movement ID was preserved'
);

insert into r13b_state (key, payload)
values (
  'sale',
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000094',
      'idempotency_key', 'local-sale-movement-key',
      'source_type', 'sale',
      'source_id', 'b3000000-0000-0000-0000-000000000082',
      'source_item_id', 'b3000000-0000-0000-0000-000000000083',
      'product_id', md5('r13b-product-2')::uuid,
      'quantity_change', -2
    ))
  )
);

select is(
  (select payload->'acknowledgements'->0->>'status' from r13b_state where key = 'sale'),
  'applied',
  '7. POS delta correlates through preserved sale and item IDs'
);

select is(
  (
    select payload->'acknowledgements'->0->>'remote_idempotency_key'
    from r13b_state where key = 'sale'
  ),
  'sale:b3000000-0000-0000-0000-000000000082:item:b3000000-0000-0000-0000-000000000083',
  '8. POS acknowledgement returns the canonical remote key'
);

select is(
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000095',
      'idempotency_key', 'r13b-local:not-found',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-5')::uuid,
      'quantity_change', 1
    ))
  )->'acknowledgements'->0->>'status',
  'not_found',
  '9. absent remote ledger evidence is not_found'
);

select is(
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000081',
      'idempotency_key', 'r13b-local:inventory_movements:manual-1',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-1')::uuid,
      'quantity_change', 999
    ))
  )->'acknowledgements'->0->>'status',
  'ambiguous',
  '10. mismatched delta is never falsely acknowledged as applied'
);

select is(
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000091',
      'idempotency_key', 'r13b-local:inventory_movements:rejected',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-5')::uuid,
      'quantity_change', 1
    ))
  )->'acknowledgements'->0->>'status',
  'rejected',
  '11. terminal remote conflict is classified as rejected'
);

select is(
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000086',
      'idempotency_key', 'r13b-local:inventory_movements:partial-applied',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-4')::uuid,
      'quantity_change', 4
    ))
  )->'acknowledgements'->0->>'status',
  'applied',
  '12. existing movement remains applied even when its transport batch is partial'
);

-- 13-17. Scope, revocation and no information disclosure.
select ok(
  pg_temp.r13b_rejects(
    $$select public.lookup_inventory_movement_acknowledgements('b3000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000021','b3000000-0000-0000-0000-000000000051','[]'::jsonb)$$,
    'does not belong to this business'
  ),
  '13. cross-business acknowledgement call is rejected'
);

select ok(
  pg_temp.r13b_rejects(
    $$select public.lookup_inventory_movement_acknowledgements('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000012','b3000000-0000-0000-0000-000000000051','[]'::jsonb)$$,
    'not registered for the requested branch'
  ),
  '14. cross-branch acknowledgement call is rejected'
);

update public.business_members set status = 'suspended'
where id = 'b3000000-0000-0000-0000-000000000041';

select ok(
  pg_temp.r13b_rejects(
    $$select public.lookup_inventory_movement_acknowledgements('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000051','[]'::jsonb)$$,
    'No active membership grants access'
  ),
  '15. revoked membership blocks acknowledgement lookup'
);

update public.business_members set status = 'active'
where id = 'b3000000-0000-0000-0000-000000000041';

select ok(
  pg_temp.r13b_rejects(
    $$select public.lookup_inventory_movement_acknowledgements('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000054','[]'::jsonb)$$,
    'inactive, blocked, or deleted'
  ),
  '16. blocked app device cannot perform acknowledgement lookup'
);

select is(
  public.lookup_inventory_movement_acknowledgements(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    jsonb_build_array(jsonb_build_object(
      'movement_id', 'b3000000-0000-0000-0000-000000000096',
      'idempotency_key', 'r13b-foreign-secret-key',
      'source_type', 'manual_adjustment',
      'product_id', md5('r13b-product-5')::uuid,
      'quantity_change', 2
    ))
  )->'acknowledgements'->0->>'status',
  'not_found',
  '17. foreign-tenant idempotency key leaks no movement evidence'
);

-- 18-30. Fresh dataset snapshots, paging and unchanged sync cursor.
insert into r13b_state (key, payload)
values (
  'legacy',
  public.pull_operational_bootstrap_snapshot(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    'product_operational'
  )
);

select is(
  (
    select count(*)::text
    from r13b_state s,
         lateral jsonb_object_keys(s.payload->'datasets') dataset_name
    where s.key = 'legacy'
  ),
  '4',
  '18. legacy call without dataset still starts the complete bundle'
);

insert into r13b_state (key, payload)
values (
  'products-focused',
  public.pull_operational_bootstrap_snapshot(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    'product_operational',
    'products',
    1000
  )
);

select ok(
  (select payload->'datasets' ? 'products' from r13b_state where key = 'products-focused')
  and (
    select count(*) = 1
    from r13b_state s,
         lateral jsonb_object_keys(s.payload->'datasets') dataset_name
    where s.key = 'products-focused'
  ),
  '19. focused products snapshot returns only products'
);

insert into r13b_state (key, payload)
values (
  'balances-first',
  public.pull_operational_bootstrap_snapshot(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    'product_operational',
    'product_stock_balances',
    1000
  )
);

update r13b_state
set token = payload->'datasets'->'product_stock_balances'->>'next_page_token'
where key = 'balances-first';

select is(
  (select payload->'datasets'->'product_stock_balances'->>'count' from r13b_state where key = 'balances-first'),
  '1000',
  '20. focused balance refresh returns the first 1000 rows'
);

select ok(
  (select token is not null from r13b_state where key = 'balances-first')
  and not (select (payload->'datasets'->'product_stock_balances'->>'complete')::boolean from r13b_state where key = 'balances-first'),
  '21. incomplete focused balance page returns a continuation token'
);

insert into r13b_state (key, payload)
select
  'balances-second',
  public.pull_operational_bootstrap_snapshot(
    'b3000000-0000-0000-0000-000000000001',
    'b3000000-0000-0000-0000-000000000011',
    'b3000000-0000-0000-0000-000000000051',
    'product_operational',
    'product_stock_balances',
    1,
    token
  )
from r13b_state
where key = 'balances-first';

select is(
  (select payload->'datasets'->'product_stock_balances'->>'count' from r13b_state where key = 'balances-second'),
  '5',
  '22. focused balance continuation returns all rows beyond 1000'
);

select ok(
  (select (payload->'datasets'->'product_stock_balances'->>'complete')::boolean from r13b_state where key = 'balances-second')
  and (select payload->'datasets'->'product_stock_balances'->>'next_page_token' is null from r13b_state where key = 'balances-second'),
  '23. final focused balance page reports complete with no next token'
);

select is(
  (select payload->>'snapshot_id' from r13b_state where key = 'balances-second'),
  (select payload->>'snapshot_id' from r13b_state where key = 'balances-first'),
  '24. focused continuation preserves snapshot identity'
);

select ok(
  pg_temp.r13b_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000051','product_operational','products',1000,%L)$$,
      (select token from r13b_state where key = 'balances-first')
    ),
    'scope mismatch'
  ),
  '25. focused token cannot cross datasets'
);

select ok(
  pg_temp.r13b_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('b3000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000021','b3000000-0000-0000-0000-000000000053','product_operational','product_stock_balances',1000,%L)$$,
      (select token from r13b_state where key = 'balances-first')
    ),
    'scope mismatch'
  ),
  '26. focused token cannot cross business or branch scope'
);

update public.business_members set status = 'suspended'
where id = 'b3000000-0000-0000-0000-000000000041';

select ok(
  pg_temp.r13b_rejects(
    format(
      $$select public.pull_operational_bootstrap_snapshot('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000051','product_operational','product_stock_balances',1000,%L)$$,
      (select token from r13b_state where key = 'balances-first')
    ),
    'No active membership grants access'
  ),
  '27. membership revocation blocks a focused continuation page'
);

update public.business_members set status = 'active'
where id = 'b3000000-0000-0000-0000-000000000041';

select ok(
  exists (
    select 1 from public.sync_cursors sc
    where sc.id = 'b3000000-0000-0000-0000-000000000071'
      and sc.last_pulled_at = '2020-01-02 03:04:05'
      and sc.cursor_token = 'r13b-cursor-before'
  )
  and (select (payload->>'sync_cursor_read')::boolean is false from r13b_state where key = 'balances-first')
  and (select (payload->>'sync_cursor_advanced')::boolean is false from r13b_state where key = 'balances-second'),
  '28. focused refresh neither reads nor advances sync cursors'
);

select ok(
  pg_temp.r13b_rejects(
    $$select public.pull_operational_bootstrap_snapshot('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000051','product_operational','cash_registers')$$,
    'does not belong to the requested bootstrap bundle'
  ),
  '29. fresh focused dataset must belong to its authorized bundle'
);

select set_config('request.jwt.claim.sub', 'b3000000-0000-0000-0000-000000000102', true);

select ok(
  pg_temp.r13b_rejects(
    $$select public.pull_operational_bootstrap_snapshot('b3000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000011','b3000000-0000-0000-0000-000000000055','product_operational','products')$$,
    'do not authorize product_operational'
  ),
  '30. focused dataset cannot bypass bundle capability authorization'
);

select * from finish();

rollback;
