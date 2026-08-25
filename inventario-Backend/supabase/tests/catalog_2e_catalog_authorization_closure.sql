-- Focused CATALOG-2E authorization checks.
-- Run after migrations through CATALOG-2F on a disposable database.

begin;

select plan(19);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('e2000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'c2e-products@example.test', '', now(), '{}', '{}', now(), now()),
  ('e2000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'c2e-settings@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('e2000000-0000-0000-0000-000000000101', 'C2E Products', 'cashier', 'active'),
  ('e2000000-0000-0000-0000-000000000102', 'C2E Settings', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('e2000000-0000-0000-0000-000000000001', 'C2E Business A', 'active'),
  ('e2000000-0000-0000-0000-000000000002', 'C2E Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('e2000000-0000-0000-0000-000000000011', 'e2000000-0000-0000-0000-000000000001', 'C2E Branch A', 'active'),
  ('e2000000-0000-0000-0000-000000000021', 'e2000000-0000-0000-0000-000000000002', 'C2E Branch B', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('e2000000-0000-0000-0000-000000000031', 'e2000000-0000-0000-0000-000000000001', 'c2e-product-editor', 'Product-only fixture', false),
  ('e2000000-0000-0000-0000-000000000032', 'e2000000-0000-0000-0000-000000000001', 'c2e-settings-only', 'Settings-only fixture', false);

insert into public.role_permissions (role_id, permission_id)
select 'e2000000-0000-0000-0000-000000000031', p.id
from public.permissions p
where p.key in ('products.read', 'products.create', 'products.update', 'products.soft_delete');

insert into public.role_permissions (role_id, permission_id)
select 'e2000000-0000-0000-0000-000000000032', p.id
from public.permissions p
where p.key = 'settings.business';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('e2000000-0000-0000-0000-000000000041', 'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000101', 'e2000000-0000-0000-0000-000000000011', 'e2000000-0000-0000-0000-000000000031', 'active', null),
  ('e2000000-0000-0000-0000-000000000042', 'e2000000-0000-0000-0000-000000000001', 'e2000000-0000-0000-0000-000000000102', 'e2000000-0000-0000-0000-000000000011', 'e2000000-0000-0000-0000-000000000032', 'active', null);

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock
)
values (
  'e2000000-0000-0000-0000-000000000202',
  'e2000000-0000-0000-0000-000000000002',
  'C2E Product B', 10, 0, 0
);

insert into public.master_products_catalog (
  id, barcode, gtin, barcode_normalized, name, product_name, source
)
values (
  'e2000000-0000-0000-0000-000000000301',
  '7700000000002',
  '7700000000002',
  '7700000000002',
  'C2E Existing Master',
  'C2E Existing Master',
  'test'
);

select is(
  private.sync_entity_permission_candidates('products', 'insert'),
  array['products.create']::text[],
  '1. Product insert maps exactly to products.create'
);

select is(
  private.sync_entity_permission_candidates('product_barcodes', 'insert'),
  array['products.create', 'products.update']::text[],
  '2. business ProductBarcode insert accepts coherent Product create/update capability'
);

select is(
  private.sync_entity_permission_candidates('future_catalog_entity', 'insert'),
  array[]::text[],
  '3. unknown sync entity fails closed'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000101', true);

select lives_ok(
  $$insert into public.products (
      id, business_id, name, sale_price, stock_quantity, minimum_stock
    ) values (
      'e2000000-0000-0000-0000-000000000201',
      'e2000000-0000-0000-0000-000000000001',
      'C2E Product A', 10, 0, 0
    )$$,
  '4. products.create user can create its business Product'
);

select throws_ok(
  $$insert into public.product_barcodes (
      id, business_id, product_id, master_product_id, barcode,
      barcode_normalized, barcode_type, scope
    ) values (
      'e2000000-0000-0000-0000-000000000211',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000201',
      'e2000000-0000-0000-0000-000000000301',
      'C2E-A-001', 'C2EA001', 'internal', 'business'
    )$$,
  '42501', null,
  '5. tenant ProductBarcode writes use sync instead of direct table DML'
);

reset role;

select ok(
  private.has_sync_entity_permission(
    'e2000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000011',
    'product_barcodes',
    'insert'
  ),
  '6. legitimate Product creator passes ProductBarcode sync authorization'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000101', true);

select throws_ok(
  $$insert into public.product_barcodes (
      business_id, product_id, barcode, barcode_normalized, barcode_type, scope
    ) values (
      'e2000000-0000-0000-0000-000000000002',
      'e2000000-0000-0000-0000-000000000202',
      'C2E-B-001', 'C2EB001', 'internal', 'business'
    )$$,
  '42501', null,
  '7. tenant user cannot create a barcode for another business'
);

reset role;
set local role service_role;

select throws_ok(
  $$insert into public.product_barcodes (
      business_id, product_id, barcode, barcode_normalized, barcode_type, scope
    ) values (
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000202',
      'C2E-A-CROSS-PRODUCT', 'C2EACROSSPRODUCT', 'internal', 'business'
    )$$,
  'P0001', 'product_id does not belong to barcode business_id',
  '8. business barcode cannot reference a Product owned by another business'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000101', true);

select throws_ok(
  $$insert into public.product_barcodes (
      master_product_id, barcode, barcode_normalized, barcode_type, scope
    ) values (
      'e2000000-0000-0000-0000-000000000301',
      '7700000000011', '7700000000011', 'ean13', 'global'
    )$$,
  '42501', null,
  '9. tenant user cannot create a global barcode'
);

select throws_ok(
  $$update public.master_products_catalog
    set name = 'Tenant overwrite'
    where id = 'e2000000-0000-0000-0000-000000000301'$$,
  '42501', null,
  '10. tenant product permission cannot update MasterProduct directly'
);

select lives_ok(
  $$select public.submit_product_catalog_contribution(
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000011',
      'e2000000-0000-0000-0000-000000000201',
      null,
      'new_product',
      '7700000000028',
      'ean13',
      'C2E Submitted Product'
    )$$,
  '11. product-capable tenant can submit a contribution in its authorized context'
);

select set_config('request.jwt.claim.sub', 'e2000000-0000-0000-0000-000000000102', true);

reset role;

select is(
  private.has_sync_entity_permission(
    'e2000000-0000-0000-0000-000000000001',
    'e2000000-0000-0000-0000-000000000011',
    'product_barcodes',
    'insert'
  ),
  false,
  '12. settings.business alone does not authorize ProductBarcode sync'
);

reset role;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$insert into public.product_catalog_contributions (
      id, business_id, branch_id, profile_id, local_product_id,
      contribution_type, suggested_name
    ) values (
      'e2000000-0000-0000-0000-000000000401',
      'e2000000-0000-0000-0000-000000000001',
      'e2000000-0000-0000-0000-000000000011',
      'e2000000-0000-0000-0000-000000000101',
      'e2000000-0000-0000-0000-000000000202',
      'new_product', 'Cross-business attempt'
    )$$,
  'P0001', 'local_product_id does not belong to contribution business_id',
  '13. contribution from Business A cannot target Product B'
);

insert into public.product_catalog_contributions (
  id, business_id, branch_id, profile_id, local_product_id,
  contribution_type, barcode, barcode_type, suggested_name
)
values (
  'e2000000-0000-0000-0000-000000000402',
  'e2000000-0000-0000-0000-000000000001',
  'e2000000-0000-0000-0000-000000000011',
  'e2000000-0000-0000-0000-000000000101',
  'e2000000-0000-0000-0000-000000000201',
  'new_product', '7700000000035', 'ean13', 'C2E Accepted Product'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)',
    'EXECUTE'
  ),
  '14. settings.business/products.update users cannot execute global review'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)',
    'EXECUTE'
  ),
  '15. service_role can execute global review'
);

select is(
  private.can_review_product_catalog_contribution(
    'e2000000-0000-0000-0000-000000000001'
  ),
  false,
  '16. legacy tenant review helper is deny-by-default'
);

set local role service_role;

select lives_ok(
  $$select public.review_product_catalog_contribution(
      'e2000000-0000-0000-0000-000000000402',
      'accept_new_product',
      'CATALOG-2E test'
    )$$,
  '17. trusted service_role can accept a contribution'
);

reset role;

select ok(
  exists (
    select 1
    from public.products p
    join public.product_catalog_contributions pcc
      on pcc.local_product_id = p.id
     and pcc.accepted_master_product_id = p.master_product_id
    where p.id = 'e2000000-0000-0000-0000-000000000201'
      and p.business_id = 'e2000000-0000-0000-0000-000000000001'
      and pcc.id = 'e2000000-0000-0000-0000-000000000402'
      and pcc.status = 'accepted'
      and pcc.reviewed_at is not null
      and pcc.metadata->>'review_actor_authority' = 'service_role'
  )
  and not exists (
    select 1
    from public.products p
    where p.id = 'e2000000-0000-0000-0000-000000000202'
      and p.master_product_id is not null
  ),
  '18. accepted contribution links only its same-business Product UUID'
);

set local role service_role;

select throws_ok(
  $$insert into public.product_barcodes (
      master_product_id, barcode, barcode_normalized, barcode_type, scope
    ) values (
      'e2000000-0000-0000-0000-000000000301',
      'C2E-INTERNAL-GLOBAL', 'C2EINTERNALGLOBAL', 'internal', 'global'
    )$$,
  '23514', null,
  '19. internal/local code cannot become a global barcode'
);

reset role;

select * from finish();

rollback;
