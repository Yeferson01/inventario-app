begin;

select plan(13);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('b7000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'retry-buyer@example.test', '', now(), '{}', '{}', now(), now()),
  ('b7000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'retry-viewer@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status) values
  ('b7000000-0000-0000-0000-000000000101', 'Retry Buyer', 'cashier', 'active'),
  ('b7000000-0000-0000-0000-000000000102', 'Retry Viewer', 'cashier', 'active');

insert into public.businesses (id, name, status) values
  ('b7000000-0000-0000-0000-000000000001', 'Retry Business A', 'active'),
  ('b7000000-0000-0000-0000-000000000002', 'Retry Business B', 'active');

insert into public.branches (id, business_id, name, status) values
  ('b7000000-0000-0000-0000-000000000011', 'b7000000-0000-0000-0000-000000000001', 'Retry Branch A', 'active'),
  ('b7000000-0000-0000-0000-000000000021', 'b7000000-0000-0000-0000-000000000002', 'Retry Branch B', 'active');

insert into public.roles (id, business_id, name, description, is_system_role) values
  ('b7000000-0000-0000-0000-000000000031', 'b7000000-0000-0000-0000-000000000001', 'retry-buyer', 'Can purchase', false),
  ('b7000000-0000-0000-0000-000000000032', 'b7000000-0000-0000-0000-000000000001', 'retry-viewer', 'Cannot purchase', false);

insert into public.role_permissions (role_id, permission_id)
select 'b7000000-0000-0000-0000-000000000031', id
from public.permissions where key = 'inventory.purchase';
insert into public.role_permissions (role_id, permission_id)
select 'b7000000-0000-0000-0000-000000000032', id
from public.permissions where key = 'inventory.read';

insert into public.business_members (id, business_id, profile_id, branch_id, role_id, status) values
  ('b7000000-0000-0000-0000-000000000041', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'b7000000-0000-0000-0000-000000000031', 'active'),
  ('b7000000-0000-0000-0000-000000000042', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000102', 'b7000000-0000-0000-0000-000000000011', 'b7000000-0000-0000-0000-000000000032', 'active');

insert into public.app_devices (id, business_id, profile_id, branch_id, installation_id, status) values
  ('b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'retry-device', 'active'),
  ('b7000000-0000-0000-0000-000000000052', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000102', 'b7000000-0000-0000-0000-000000000011', 'viewer-device', 'active');

insert into public.products (id, business_id, name, sale_price, purchase_price, stock_quantity, minimum_stock)
values ('b7000000-0000-0000-0000-000000000201', 'b7000000-0000-0000-0000-000000000001', 'Retry Product', 1500, 1000, 0, 0);
insert into public.product_stock_balances (id, business_id, branch_id, product_id, quantity_on_hand, quantity_reserved, average_cost)
values ('b7000000-0000-0000-0000-000000000211', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011', 'b7000000-0000-0000-0000-000000000201', 18, 0, 0);

insert into public.sync_batches (id, business_id, app_device_id, profile_id, branch_id, client_batch_id, direction, status)
values ('b7000000-0000-0000-0000-000000000301', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'historical-batch', 'upload', 'pending');

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
) values
  ('b7000000-0000-0000-0000-000000000321', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000301', 'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'retry-purchase', 1, 'purchases', 'b7000000-0000-0000-0000-000000000401', 'insert', '{"branch_id":"b7000000-0000-0000-0000-000000000011","total":2000,"status":"completed"}', 'pending', 'retry-purchase-key'),
  ('b7000000-0000-0000-0000-000000000322', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000301', 'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'retry-item', 2, 'purchase_items', 'b7000000-0000-0000-0000-000000000402', 'insert', '{"purchase_id":"b7000000-0000-0000-0000-000000000401","product_id":"b7000000-0000-0000-0000-000000000201","quantity":2,"unit_cost":1000,"subtotal":2000}', 'pending', 'retry-item-key');

select private.create_sync_conflict_for_mutation('b7000000-0000-0000-0000-000000000321', 'permission_denied', 'high', null, 'historical denial', '{}');
select private.create_sync_conflict_for_mutation('b7000000-0000-0000-0000-000000000322', 'permission_denied', 'high', null, 'historical denial', '{}');
update public.sync_batches set status = 'partial' where id = 'b7000000-0000-0000-0000-000000000301';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000101', true);

select ok(
  (public.inspect_retriable_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401'
  ) ->> 'safe_to_retry')::boolean,
  '1. exact historical permission_denied conflicts are retriable while remote evidence is absent'
);

select throws_ok(
  $$select public.finalize_retried_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401')$$,
  '23514', 'Retried Purchase evidence is incomplete or incompatible',
  '2. finalization rejects non-applied mutations and an absent Purchase'
);

select throws_ok(
  $$select public.inspect_retriable_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000002', 'b7000000-0000-0000-0000-000000000021',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401')$$,
  '42501', 'inventory.purchase permission is required',
  '3. cross-business scope is denied without leakage'
);

select throws_ok(
  $$select public.inspect_retriable_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000052', 'b7000000-0000-0000-0000-000000000401')$$,
  '42501', 'app_device is not active for this profile and branch',
  '4. a device belonging to another profile is denied'
);

select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000102', true);
select throws_ok(
  $$select public.inspect_retriable_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000052', 'b7000000-0000-0000-0000-000000000401')$$,
  '42501', 'inventory.purchase permission is required',
  '5. inventory.read cannot authorize a Purchase retry'
);

reset role;
insert into public.sync_batches (id, business_id, app_device_id, profile_id, branch_id, client_batch_id, direction, status)
values ('b7000000-0000-0000-0000-000000000302', 'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000101', 'b7000000-0000-0000-0000-000000000011', 'retry-batch', 'upload', 'pending');
update public.sync_mutations set sync_batch_id = 'b7000000-0000-0000-0000-000000000302', status = 'pending', error_code = null, error_message = null
where id in ('b7000000-0000-0000-0000-000000000321', 'b7000000-0000-0000-0000-000000000322');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000101', true);
select lives_ok(
  $$select public.process_sync_batch('b7000000-0000-0000-0000-000000000302', 'apply_purchases')$$,
  '6. the same mutation identities can be retried in a new batch'
);

select ok(
  (public.inspect_retriable_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401'
  ) ->> 'finalizable')::boolean,
  '7. applied mutations, exact entities and one exact movement per item are finalizable'
);

select lives_ok(
  $$select public.finalize_retried_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401')$$,
  '8. Purchase and PurchaseItem historical conflicts finalize atomically'
);

reset role;
select is(
  (select count(*) from public.sync_conflicts where entity_id in (
    'b7000000-0000-0000-0000-000000000401', 'b7000000-0000-0000-0000-000000000402'
  ) and status = 'resolved' and resolution_strategy = 'retry_after_permission_fix'),
  2::bigint,
  '9. both historical conflicts are resolved by the specialized strategy'
);

select is(
  (select count(*) from public.sync_mutations where id in (
    'b7000000-0000-0000-0000-000000000321', 'b7000000-0000-0000-0000-000000000322'
  ) and status = 'applied'),
  2::bigint,
  '10. finalization does not downgrade applied mutations'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7000000-0000-0000-0000-000000000101', true);
select ok(
  (public.finalize_retried_purchase_permission_conflicts(
    'b7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000011',
    'b7000000-0000-0000-0000-000000000051', 'b7000000-0000-0000-0000-000000000401'
  ) ->> 'idempotent')::boolean,
  '11. repeated conflict finalization is idempotent'
);

reset role;
select is(
  (select count(*) from public.inventory_movements where source_type = 'purchase' and source_id = 'b7000000-0000-0000-0000-000000000401'),
  1::bigint,
  '12. retry and finalization create exactly one inventory movement'
);

select ok(
  not has_function_privilege('anon', 'public.finalize_retried_purchase_permission_conflicts(uuid,uuid,uuid,uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.finalize_retried_purchase_permission_conflicts(uuid,uuid,uuid,uuid)', 'EXECUTE'),
  '13. finalization ACL is authenticated-only'
);

select * from finish();
rollback;
