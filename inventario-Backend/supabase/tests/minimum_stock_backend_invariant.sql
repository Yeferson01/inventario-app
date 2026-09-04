-- Focused validation for the authoritative Products minimum-stock invariant.
-- The transaction always rolls back fixture data.

begin;

select plan(14);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values (
  'a5000000-0000-0000-0000-000000000101',
  'authenticated',
  'authenticated',
  'minimum-stock@example.test',
  '',
  now(),
  '{}',
  '{}',
  now(),
  now()
);

insert into public.profiles (id, full_name, role, status)
values (
  'a5000000-0000-0000-0000-000000000101',
  'Minimum Stock Owner',
  'owner',
  'active'
);

insert into public.businesses (id, name, status)
values (
  'a5000000-0000-0000-0000-000000000001',
  'Minimum Stock Business',
  'active'
);

insert into public.branches (id, business_id, name, status)
values (
  'a5000000-0000-0000-0000-000000000011',
  'a5000000-0000-0000-0000-000000000001',
  'Minimum Stock Branch',
  'active'
);

do $$
begin
  if not exists (
    select 1
    from public.roles r
    where r.business_id is null
      and r.name = 'owner'
      and r.deleted_at is null
  ) then
    raise exception 'Minimum-stock fixture requires the seeded owner system role';
  end if;
end;
$$;

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values (
  'a5000000-0000-0000-0000-000000000041',
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000101',
  null,
  (
    select r.id
    from public.roles r
    where r.business_id is null
      and r.name = 'owner'
      and r.deleted_at is null
    limit 1
  ),
  'active',
  null
);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values (
  'a5000000-0000-0000-0000-000000000051',
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000101',
  'a5000000-0000-0000-0000-000000000011',
  'minimum-stock-device',
  'active'
);

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock
)
values
  (
    'a5000000-0000-0000-0000-000000000204',
    'a5000000-0000-0000-0000-000000000001',
    'Minimum Stock Update Guard', 10, 0, 5
  ),
  (
    'a5000000-0000-0000-0000-000000000205',
    'a5000000-0000-0000-0000-000000000001',
    'Minimum Stock Negative Sync', 10, 0, 4
  ),
  (
    'a5000000-0000-0000-0000-000000000206',
    'a5000000-0000-0000-0000-000000000001',
    'Minimum Stock Zero Sync', 10, 0, 8
  ),
  (
    'a5000000-0000-0000-0000-000000000207',
    'a5000000-0000-0000-0000-000000000001',
    'Minimum Stock Positive Sync', 10, 0, 8
  );

select ok(
  exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.products'::regclass
      and c.conname = 'products_minimum_stock_non_negative'
      and c.contype = 'c'
      and c.convalidated
      and lower(pg_get_constraintdef(c.oid)) like '%minimum_stock is null%'
      and lower(pg_get_constraintdef(c.oid)) like '%minimum_stock >= 0%'
  ),
  '1. minimum-stock CHECK exists, is validated and preserves NULL'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a5000000-0000-0000-0000-000000000101',
  true
);

select lives_ok(
  $$insert into public.products (
      id, business_id, name, sale_price, stock_quantity, minimum_stock
    ) values (
      'a5000000-0000-0000-0000-000000000201',
      'a5000000-0000-0000-0000-000000000001',
      'Minimum Stock Null', 10, 0, null
    )$$,
  '2. NULL minimum_stock remains allowed'
);

select lives_ok(
  $$insert into public.products (
      id, business_id, name, sale_price, stock_quantity, minimum_stock
    ) values (
      'a5000000-0000-0000-0000-000000000202',
      'a5000000-0000-0000-0000-000000000001',
      'Minimum Stock Zero', 10, 0, 0
    )$$,
  '3. zero minimum_stock remains allowed'
);

select lives_ok(
  $$insert into public.products (
      id, business_id, name, sale_price, stock_quantity, minimum_stock
    ) values (
      'a5000000-0000-0000-0000-000000000203',
      'a5000000-0000-0000-0000-000000000001',
      'Minimum Stock Positive', 10, 0, 9
    )$$,
  '4. positive minimum_stock remains allowed'
);

select throws_ok(
  $$insert into public.products (
      id, business_id, name, sale_price, stock_quantity, minimum_stock
    ) values (
      'a5000000-0000-0000-0000-000000000208',
      'a5000000-0000-0000-0000-000000000001',
      'Minimum Stock Invalid', 10, 0, -1
    )$$,
  '23514',
  null,
  '5. direct INSERT rejects negative minimum_stock'
);

select throws_ok(
  $$update public.products
    set minimum_stock = -1
    where id = 'a5000000-0000-0000-0000-000000000204'$$,
  '23514',
  null,
  '6. direct UPDATE rejects negative minimum_stock'
);

reset role;

select is(
  (
    select p.minimum_stock
    from public.products p
    where p.id = 'a5000000-0000-0000-0000-000000000204'
  ),
  5,
  '7. rejected UPDATE preserves the previous minimum_stock'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id, client_batch_id,
  direction, status, mutation_count
)
values (
  'a5000000-0000-0000-0000-000000000301',
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000051',
  'a5000000-0000-0000-0000-000000000101',
  'a5000000-0000-0000-0000-000000000011',
  'minimum-stock-negative',
  'upload',
  'pending',
  1
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values (
  'a5000000-0000-0000-0000-000000000311',
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000301',
  'a5000000-0000-0000-0000-000000000051',
  'a5000000-0000-0000-0000-000000000101',
  'a5000000-0000-0000-0000-000000000011',
  'minimum-stock-negative-mutation',
  1,
  'products',
  'a5000000-0000-0000-0000-000000000205',
  'update',
  '{"minimum_stock":-1}'::jsonb,
  'pending',
  'minimum-stock-negative-idempotency'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a5000000-0000-0000-0000-000000000101',
  true
);

select lives_ok(
  $$select public.process_sync_batch(
      'a5000000-0000-0000-0000-000000000301',
      'apply_catalog'
    )$$,
  '8. negative catalog sync is handled by the existing fail-closed batch contract'
);

reset role;

select is(
  (
    select p.minimum_stock
    from public.products p
    where p.id = 'a5000000-0000-0000-0000-000000000205'
  ),
  4,
  '9. rejected negative sync leaves the Product unchanged'
);

select ok(
  exists (
    select 1
    from public.sync_mutations sm
    where sm.id = 'a5000000-0000-0000-0000-000000000311'
      and sm.status = 'error'
      and sm.error_code = 'unexpected_error'
      and sm.error_message like '%products_minimum_stock_non_negative%'
  ),
  '10. negative sync mutation records the constraint failure as error'
);

select ok(
  exists (
    select 1
    from public.sync_batches sb
    where sb.id = 'a5000000-0000-0000-0000-000000000301'
      and sb.status = 'failed'
      and sb.error_count = 1
      and sb.applied_count = 0
  ),
  '11. all-error negative sync batch finalizes as failed'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id, client_batch_id,
  direction, status, mutation_count
)
values (
  'a5000000-0000-0000-0000-000000000302',
  'a5000000-0000-0000-0000-000000000001',
  'a5000000-0000-0000-0000-000000000051',
  'a5000000-0000-0000-0000-000000000101',
  'a5000000-0000-0000-0000-000000000011',
  'minimum-stock-valid',
  'upload',
  'pending',
  2
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  (
    'a5000000-0000-0000-0000-000000000312',
    'a5000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000302',
    'a5000000-0000-0000-0000-000000000051',
    'a5000000-0000-0000-0000-000000000101',
    'a5000000-0000-0000-0000-000000000011',
    'minimum-stock-zero-mutation',
    1,
    'products',
    'a5000000-0000-0000-0000-000000000206',
    'update',
    '{"minimum_stock":0}'::jsonb,
    'pending',
    'minimum-stock-zero-idempotency'
  ),
  (
    'a5000000-0000-0000-0000-000000000313',
    'a5000000-0000-0000-0000-000000000001',
    'a5000000-0000-0000-0000-000000000302',
    'a5000000-0000-0000-0000-000000000051',
    'a5000000-0000-0000-0000-000000000101',
    'a5000000-0000-0000-0000-000000000011',
    'minimum-stock-positive-mutation',
    2,
    'products',
    'a5000000-0000-0000-0000-000000000207',
    'update',
    '{"minimum_stock":12}'::jsonb,
    'pending',
    'minimum-stock-positive-idempotency'
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'a5000000-0000-0000-0000-000000000101',
  true
);

select lives_ok(
  $$select public.process_sync_batch(
      'a5000000-0000-0000-0000-000000000302',
      'apply_catalog'
    )$$,
  '12. valid zero and positive catalog sync mutations still process normally'
);

reset role;

select ok(
  (
    select p.minimum_stock = 0
    from public.products p
    where p.id = 'a5000000-0000-0000-0000-000000000206'
  )
  and (
    select p.minimum_stock = 12
    from public.products p
    where p.id = 'a5000000-0000-0000-0000-000000000207'
  ),
  '13. valid sync applies both zero and positive thresholds'
);

select ok(
  (
    select count(*) = 2
    from public.sync_mutations sm
    where sm.sync_batch_id = 'a5000000-0000-0000-0000-000000000302'
      and sm.status = 'applied'
  )
  and exists (
    select 1
    from public.sync_batches sb
    where sb.id = 'a5000000-0000-0000-0000-000000000302'
      and sb.status = 'completed'
      and sb.applied_count = 2
      and sb.error_count = 0
  ),
  '14. valid catalog sync mutations and batch finalize as applied/completed'
);

select * from finish();

rollback;
