-- Focused validation for purchase sync authorization and inventory idempotency.
-- The transaction always rolls back fixture data.

begin;

select plan(29);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('a6000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'purchase-buyer@example.test', '', now(), '{}', '{}', now(), now()),
  ('a6000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'purchase-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('a6000000-0000-0000-0000-000000000101', 'Purchase Custom Buyer', 'cashier', 'active'),
  ('a6000000-0000-0000-0000-000000000102', 'Purchase Read Only', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('a6000000-0000-0000-0000-000000000001', 'Purchase Business A', 'active'),
  ('a6000000-0000-0000-0000-000000000002', 'Purchase Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('a6000000-0000-0000-0000-000000000011', 'a6000000-0000-0000-0000-000000000001', 'Purchase Branch A1', 'active'),
  ('a6000000-0000-0000-0000-000000000012', 'a6000000-0000-0000-0000-000000000001', 'Purchase Branch A2', 'active'),
  ('a6000000-0000-0000-0000-000000000021', 'a6000000-0000-0000-0000-000000000002', 'Purchase Branch B1', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('a6000000-0000-0000-0000-000000000031', 'a6000000-0000-0000-0000-000000000001', 'custom-stock-receiver', 'Custom purchase capability fixture', false),
  ('a6000000-0000-0000-0000-000000000032', 'a6000000-0000-0000-0000-000000000001', 'custom-stock-reader', 'Read-only inventory fixture', false);

insert into public.role_permissions (role_id, permission_id)
select 'a6000000-0000-0000-0000-000000000031', p.id
from public.permissions p
where p.key = 'inventory.purchase';

insert into public.role_permissions (role_id, permission_id)
select 'a6000000-0000-0000-0000-000000000032', p.id
from public.permissions p
where p.key = 'inventory.read';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('a6000000-0000-0000-0000-000000000041', 'a6000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000101', 'a6000000-0000-0000-0000-000000000011', 'a6000000-0000-0000-0000-000000000031', 'active', null),
  ('a6000000-0000-0000-0000-000000000042', 'a6000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000102', 'a6000000-0000-0000-0000-000000000011', 'a6000000-0000-0000-0000-000000000032', 'active', null);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values
  ('a6000000-0000-0000-0000-000000000051', 'a6000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000101', 'a6000000-0000-0000-0000-000000000011', 'purchase-buyer-device', 'active'),
  ('a6000000-0000-0000-0000-000000000052', 'a6000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000102', 'a6000000-0000-0000-0000-000000000011', 'purchase-viewer-device', 'active');

insert into public.products (
  id, business_id, name, sale_price, purchase_price, stock_quantity, minimum_stock
)
values (
  'a6000000-0000-0000-0000-000000000201',
  'a6000000-0000-0000-0000-000000000001',
  'Purchase Sync Product', 1500, 1000, 0, 0
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost
)
values (
  'a6000000-0000-0000-0000-000000000211',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000011',
  'a6000000-0000-0000-0000-000000000201',
  18, 0, 0
);

select ok(
  not exists (
    select 1 from public.permissions p where p.key = 'purchases.create'
  ),
  '1. purchases.create is not a seeded contractual capability'
);

select is(
  private.sync_entity_permission_candidates('purchases', 'insert'),
  array['inventory.purchase']::text[],
  '2. purchase INSERT maps to inventory.purchase'
);

select is(
  private.sync_entity_permission_candidates('purchase_items', 'insert'),
  array['inventory.purchase']::text[],
  '3. purchase_item INSERT maps to inventory.purchase'
);

select is(
  private.sync_entity_permission_candidates('purchases', 'upsert'),
  array['inventory.purchase']::text[],
  '4. purchase UPSERT maps to inventory.purchase'
);

select is(
  private.sync_entity_permission_candidates('purchases', 'update'),
  array['inventory.purchase']::text[],
  '5. purchase UPDATE maps to inventory.purchase'
);

select is(
  private.sync_entity_permission_candidates('purchase_items', 'soft_delete'),
  array['inventory.purchase']::text[],
  '6. purchase_item soft-delete maps to inventory.purchase'
);

select is(
  private.sync_entity_permission_candidates('purchases', 'delete'),
  array[]::text[],
  '7. purchase hard delete remains denied'
);

select is(
  private.sync_entity_permission_candidates('products', 'insert'),
  array['products.create']::text[],
  '8. Product authorization mapping is unchanged'
);

select is(
  private.sync_entity_permission_candidates('sales', 'insert'),
  array['sales.create']::text[],
  '9. Sale authorization mapping is unchanged'
);

select is(
  private.sync_entity_permission_candidates('cash_sessions', 'insert'),
  array['sales.create']::text[],
  '10. Cash authorization mapping is unchanged'
);

-- Private helpers deliberately have no authenticated EXECUTE grant. Evaluate
-- their auth.uid()-based semantics as the function owner, matching the pgTAP
-- pattern used by the CATALOG authorization tests.
reset role;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000101', true);

select ok(
  private.has_sync_entity_permission(
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000011',
    'purchases',
    'insert'
  ),
  '11. a custom role with inventory.purchase can sync a purchase'
);

select ok(
  private.has_sync_entity_permission(
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000011',
    'purchase_items',
    'insert'
  ),
  '12. the same custom role can sync its purchase items'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000102', true);

select is(
  private.has_sync_entity_permission(
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000011',
    'purchases',
    'insert'
  ),
  false,
  '13. inventory.read without inventory.purchase cannot sync a purchase'
);

select is(
  private.has_sync_entity_permission(
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000011',
    'purchase_items',
    'insert'
  ),
  false,
  '14. inventory.read without inventory.purchase cannot sync a purchase item'
);

select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000101', true);

select is(
  private.has_sync_entity_permission(
    'a6000000-0000-0000-0000-000000000002',
    'a6000000-0000-0000-0000-000000000021',
    'purchases',
    'insert'
  ),
  false,
  '15. inventory.purchase in Business A does not authorize Business B'
);

reset role;

select throws_ok(
  $$insert into public.sync_batches (
      id, business_id, app_device_id, profile_id, branch_id,
      client_batch_id, direction, status
    ) values (
      'a6000000-0000-0000-0000-000000000301',
      'a6000000-0000-0000-0000-000000000001',
      'a6000000-0000-0000-0000-000000000051',
      'a6000000-0000-0000-0000-000000000101',
      'a6000000-0000-0000-0000-000000000012',
      'purchase-cross-branch', 'upload', 'pending'
    )$$,
  'P0001',
  'sync_batches.branch_id must match app_devices.branch_id when device is branch-scoped',
  '16. a branch-scoped device cannot inject a purchase batch into another branch'
);

select throws_ok(
  $$insert into public.sync_batches (
      id, business_id, app_device_id, profile_id, branch_id,
      client_batch_id, direction, status
    ) values (
      'a6000000-0000-0000-0000-000000000302',
      'a6000000-0000-0000-0000-000000000002',
      'a6000000-0000-0000-0000-000000000051',
      'a6000000-0000-0000-0000-000000000101',
      'a6000000-0000-0000-0000-000000000021',
      'purchase-cross-business', 'upload', 'pending'
    )$$,
  'P0001',
  'sync_batches.business_id must match app_devices.business_id',
  '17. a device cannot inject a purchase batch into another business'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, metadata
)
values (
  'a6000000-0000-0000-0000-000000000311',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000051',
  'a6000000-0000-0000-0000-000000000101',
  'a6000000-0000-0000-0000-000000000011',
  'purchase-authorized-batch', 'upload', 'pending',
  '{"domain":"purchases"}'::jsonb
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'a6000000-0000-0000-0000-000000000321',
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000311',
    'a6000000-0000-0000-0000-000000000051',
    'a6000000-0000-0000-0000-000000000101',
    'a6000000-0000-0000-0000-000000000011',
    'purchase-authorized-mutation', 1,
    'purchases', 'a6000000-0000-0000-0000-000000000401', 'insert',
    '{"branch_id":"a6000000-0000-0000-0000-000000000011","total":2000,"status":"completed","processing_status":"completed"}'::jsonb,
    'pending', 'purchase-authorized-idempotency'
  ),
  (
    'a6000000-0000-0000-0000-000000000322',
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000311',
    'a6000000-0000-0000-0000-000000000051',
    'a6000000-0000-0000-0000-000000000101',
    'a6000000-0000-0000-0000-000000000011',
    'purchase-item-authorized-mutation', 2,
    'purchase_items', 'a6000000-0000-0000-0000-000000000402', 'insert',
    '{"purchase_id":"a6000000-0000-0000-0000-000000000401","product_id":"a6000000-0000-0000-0000-000000000201","quantity":2,"unit_cost":1000,"subtotal":2000}'::jsonb,
    'pending', 'purchase-item-authorized-idempotency'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000101', true);

select lives_ok(
  $$select public.process_sync_batch(
      'a6000000-0000-0000-0000-000000000311',
      'apply_purchases'
    )$$,
  '18. an inventory.purchase actor can process a purchase and item batch'
);

reset role;

select is(
  (select count(*) from public.purchases where id = 'a6000000-0000-0000-0000-000000000401'),
  1::bigint,
  '19. the purchase is materialized exactly once'
);

select is(
  (select count(*) from public.purchase_items where id = 'a6000000-0000-0000-0000-000000000402'),
  1::bigint,
  '20. the purchase item is materialized exactly once'
);

select ok(
  exists (
    select 1
    from public.inventory_movements im
    where im.business_id = 'a6000000-0000-0000-0000-000000000001'
      and im.branch_id = 'a6000000-0000-0000-0000-000000000011'
      and im.product_id = 'a6000000-0000-0000-0000-000000000201'
      and im.source_type = 'purchase'
      and im.source_id = 'a6000000-0000-0000-0000-000000000401'
      and im.quantity_change = 2
      and im.unit_cost = 1000
  ) and (
    select count(*) = 1
    from public.inventory_movements im
    where im.source_type = 'purchase'
      and im.source_id = 'a6000000-0000-0000-0000-000000000401'
  ),
  '21. one purchase inventory movement applies the exact quantity and cost'
);

select ok(
  exists (
    select 1
    from public.product_stock_balances psb
    where psb.business_id = 'a6000000-0000-0000-0000-000000000001'
      and psb.branch_id = 'a6000000-0000-0000-0000-000000000011'
      and psb.product_id = 'a6000000-0000-0000-0000-000000000201'
      and psb.quantity_on_hand = 20
      and psb.average_cost = 100
  ),
  '22. stock and weighted average cost converge from 18/0 to 20/100'
);

select ok(
  exists (
    select 1 from public.sync_batches sb
    where sb.id = 'a6000000-0000-0000-0000-000000000311'
      and sb.status = 'completed'
      and sb.applied_count = 2
      and sb.conflict_count = 0
      and sb.error_count = 0
  ) and (
    select count(*) = 2
    from public.sync_mutations sm
    where sm.sync_batch_id = 'a6000000-0000-0000-0000-000000000311'
      and sm.status = 'applied'
  ),
  '23. authorized mutations and batch finalize as applied/completed'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000101', true);

select lives_ok(
  $$select public.process_sync_batch(
      'a6000000-0000-0000-0000-000000000311',
      'apply_purchases'
    )$$,
  '24. retrying the completed backend batch is safe'
);

reset role;

select ok(
  (select count(*) = 1 from public.purchases where id = 'a6000000-0000-0000-0000-000000000401')
  and (select count(*) = 1 from public.purchase_items where id = 'a6000000-0000-0000-0000-000000000402')
  and (
    select count(*) = 1
    from public.inventory_movements im
    where im.source_type = 'purchase'
      and im.source_id = 'a6000000-0000-0000-0000-000000000401'
  ),
  '25. backend retry does not duplicate purchase, item or movement'
);

select ok(
  exists (
    select 1
    from public.product_stock_balances psb
    where psb.business_id = 'a6000000-0000-0000-0000-000000000001'
      and psb.branch_id = 'a6000000-0000-0000-0000-000000000011'
      and psb.product_id = 'a6000000-0000-0000-0000-000000000201'
      and psb.quantity_on_hand = 20
      and psb.average_cost = 100
  ),
  '26. backend retry does not double-apply stock or average cost'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, metadata
)
values (
  'a6000000-0000-0000-0000-000000000312',
  'a6000000-0000-0000-0000-000000000001',
  'a6000000-0000-0000-0000-000000000052',
  'a6000000-0000-0000-0000-000000000102',
  'a6000000-0000-0000-0000-000000000011',
  'purchase-denied-batch', 'upload', 'pending',
  '{"domain":"purchases"}'::jsonb
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'a6000000-0000-0000-0000-000000000323',
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000312',
    'a6000000-0000-0000-0000-000000000052',
    'a6000000-0000-0000-0000-000000000102',
    'a6000000-0000-0000-0000-000000000011',
    'purchase-denied-mutation', 1,
    'purchases', 'a6000000-0000-0000-0000-000000000411', 'insert',
    '{"branch_id":"a6000000-0000-0000-0000-000000000011","total":2000,"status":"completed"}'::jsonb,
    'pending', 'purchase-denied-idempotency'
  ),
  (
    'a6000000-0000-0000-0000-000000000324',
    'a6000000-0000-0000-0000-000000000001',
    'a6000000-0000-0000-0000-000000000312',
    'a6000000-0000-0000-0000-000000000052',
    'a6000000-0000-0000-0000-000000000102',
    'a6000000-0000-0000-0000-000000000011',
    'purchase-item-denied-mutation', 2,
    'purchase_items', 'a6000000-0000-0000-0000-000000000412', 'insert',
    '{"purchase_id":"a6000000-0000-0000-0000-000000000411","product_id":"a6000000-0000-0000-0000-000000000201","quantity":2,"unit_cost":1000,"subtotal":2000}'::jsonb,
    'pending', 'purchase-item-denied-idempotency'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-0000-0000-000000000102', true);

select lives_ok(
  $$select public.process_sync_batch(
      'a6000000-0000-0000-0000-000000000312',
      'apply_purchases'
    )$$,
  '27. unauthorized purchase mutations fail closed inside the batch contract'
);

reset role;

select ok(
  exists (
    select 1 from public.sync_batches sb
    where sb.id = 'a6000000-0000-0000-0000-000000000312'
      and sb.status = 'partial'
      and sb.applied_count = 0
      and sb.conflict_count = 2
  ) and (
    select count(*) = 2
    from public.sync_mutations sm
    join public.sync_conflicts sc on sc.sync_mutation_id = sm.id
    where sm.sync_batch_id = 'a6000000-0000-0000-0000-000000000312'
      and sm.status = 'conflict'
      and sc.conflict_type = 'permission_denied'
      and sc.deleted_at is null
  ),
  '28. actor without inventory.purchase receives permission_denied for both entities'
);

select ok(
  not exists (
    select 1 from public.purchases where id = 'a6000000-0000-0000-0000-000000000411'
  ) and not exists (
    select 1 from public.purchase_items where id = 'a6000000-0000-0000-0000-000000000412'
  ),
  '29. denied mutations do not materialize a purchase or purchase item'
);

select * from finish();

rollback;
