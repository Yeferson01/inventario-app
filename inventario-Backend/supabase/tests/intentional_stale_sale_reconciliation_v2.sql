begin;

select plan(8);

create temporary table intentional_stale_sale_state (
  sale_id uuid primary key,
  conflict_id uuid not null
) on commit drop;

grant select, insert on intentional_stale_sale_state to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('aa000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'reconcile-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('aa000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'reconcile-cashier@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('aa000000-0000-0000-0000-000000000001', 'Reconciliation Owner', 'owner', 'active'),
  ('aa000000-0000-0000-0000-000000000002', 'Reconciliation Cashier', 'cashier', 'active');

insert into public.businesses (id, name, status)
values ('ab000000-0000-0000-0000-000000000001', 'Reconciliation Business', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('ac000000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'Main', 'active'),
  ('ac000000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000001', 'Other', 'active');

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status
)
values
  (
    'ad000000-0000-0000-0000-000000000001',
    'ab000000-0000-0000-0000-000000000001',
    'aa000000-0000-0000-0000-000000000001', null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active'
  ),
  (
    'ad000000-0000-0000-0000-000000000002',
    'ab000000-0000-0000-0000-000000000001',
    'aa000000-0000-0000-0000-000000000002',
    'ac000000-0000-0000-0000-000000000001',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1),
    'active'
  );

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values
  ('ad100000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'reconciliation-owner-device', 'active'),
  ('ad100000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000002', 'ac000000-0000-0000-0000-000000000001', 'reconciliation-cashier-device', 'active');

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, status
)
values (
  'ae000000-0000-0000-0000-000000000001',
  'ab000000-0000-0000-0000-000000000001',
  'Reconciliation Product', 10, 0, 'active'
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost
)
values (
  'ae010000-0000-0000-0000-000000000001',
  'ab000000-0000-0000-0000-000000000001',
  'ac000000-0000-0000-0000-000000000001',
  'ae000000-0000-0000-0000-000000000001',
  10, 0, 5
);

insert into public.cash_registers (id, business_id, branch_id, name, status)
values
  ('ae100000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'Register A', 'active'),
  ('ae100000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'Register B', 'active'),
  ('ae100000-0000-0000-0000-000000000003', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'Register C', 'active'),
  ('ae100000-0000-0000-0000-000000000004', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'Register D', 'active'),
  ('ae100000-0000-0000-0000-000000000005', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000002', 'Other Branch Register', 'active');

insert into public.cash_sessions (
  id, business_id, branch_id, cash_register_id, opened_by,
  opening_amount, status, opened_at, closed_at
)
values
  ('af000000-0000-0000-0000-000000000011', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 0, 'closed', now() - interval '4 hours', now() - interval '3 hours'),
  ('af000000-0000-0000-0000-000000000012', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 100, 'open', now() - interval '2 hours', null),
  ('af000000-0000-0000-0000-000000000021', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000001', 0, 'closed', now() - interval '4 hours', now() - interval '3 hours'),
  ('af000000-0000-0000-0000-000000000022', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000001', 110, 'open', now() - interval '2 hours', null),
  ('af000000-0000-0000-0000-000000000031', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000003', 'aa000000-0000-0000-0000-000000000001', 0, 'closed', now() - interval '4 hours', now() - interval '3 hours'),
  ('af000000-0000-0000-0000-000000000032', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000003', 'aa000000-0000-0000-0000-000000000001', 50, 'open', now() - interval '2 hours', null),
  ('af000000-0000-0000-0000-000000000041', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000004', 'aa000000-0000-0000-0000-000000000001', 0, 'closed', now() - interval '5 hours', now() - interval '4 hours'),
  ('af000000-0000-0000-0000-000000000042', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000004', 'aa000000-0000-0000-0000-000000000001', 100, 'closed', now() - interval '3 hours', now() - interval '2 hours'),
  ('af000000-0000-0000-0000-000000000043', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'ae100000-0000-0000-0000-000000000004', 'aa000000-0000-0000-0000-000000000001', 100, 'open', now() - interval '1 hour', null),
  ('af000000-0000-0000-0000-000000000051', 'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000002', 'ae100000-0000-0000-0000-000000000005', 'aa000000-0000-0000-0000-000000000001', 100, 'open', now() - interval '1 hour', null);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count
)
values
  ('b0000000-0000-0000-0000-000000000001', 'ab000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'reconcile-a', 'upload', 'pending', 3),
  ('b0000000-0000-0000-0000-000000000002', 'ab000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'reconcile-b', 'upload', 'pending', 3),
  ('b0000000-0000-0000-0000-000000000003', 'ab000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'reconcile-c', 'upload', 'pending', 3),
  ('b0000000-0000-0000-0000-000000000004', 'ab000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'reconcile-d', 'upload', 'pending', 3);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values
  ('b1000000-0000-0000-0000-000000000011', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'sale-a', 1, 'sales', 'c0000000-0000-0000-0000-000000000001', 'insert', '{"id":"c0000000-0000-0000-0000-000000000001","branch_id":"ac000000-0000-0000-0000-000000000001","cash_register_id":"ae100000-0000-0000-0000-000000000001","cash_session_id":"af000000-0000-0000-0000-000000000011","subtotal":10,"total":10,"payment_method":"cash","status":"completed","created_at":"2026-08-31T10:00:00Z"}', 'pending', 'sale-a'),
  ('b1000000-0000-0000-0000-000000000012', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'item-a', 2, 'sale_items', 'c1000000-0000-0000-0000-000000000001', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000001","product_id":"ae000000-0000-0000-0000-000000000001","quantity":1,"unit_price":10,"subtotal":10,"total":10,"created_at":"2026-08-31T10:00:00Z"}', 'pending', 'item-a'),
  ('b1000000-0000-0000-0000-000000000013', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000001', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'payment-a', 3, 'sale_payments', 'c2000000-0000-0000-0000-000000000001', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000001","payment_method":"cash","amount":10,"currency":"COP","status":"completed","created_at":"2026-08-31T10:00:00Z"}', 'pending', 'payment-a'),

  ('b1000000-0000-0000-0000-000000000021', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'sale-b', 1, 'sales', 'c0000000-0000-0000-0000-000000000002', 'insert', '{"id":"c0000000-0000-0000-0000-000000000002","branch_id":"ac000000-0000-0000-0000-000000000001","cash_register_id":"ae100000-0000-0000-0000-000000000002","cash_session_id":"af000000-0000-0000-0000-000000000021","subtotal":10,"total":10,"payment_method":"cash","status":"completed","created_at":"2026-08-31T10:01:00Z"}', 'pending', 'sale-b'),
  ('b1000000-0000-0000-0000-000000000022', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'item-b', 2, 'sale_items', 'c1000000-0000-0000-0000-000000000002', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000002","product_id":"ae000000-0000-0000-0000-000000000001","quantity":1,"unit_price":10,"subtotal":10,"total":10,"created_at":"2026-08-31T10:01:00Z"}', 'pending', 'item-b'),
  ('b1000000-0000-0000-0000-000000000023', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000002', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'payment-b', 3, 'sale_payments', 'c2000000-0000-0000-0000-000000000002', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000002","payment_method":"cash","amount":10,"currency":"COP","status":"completed","created_at":"2026-08-31T10:01:00Z"}', 'pending', 'payment-b'),

  ('b1000000-0000-0000-0000-000000000031', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'sale-c', 1, 'sales', 'c0000000-0000-0000-0000-000000000003', 'insert', '{"id":"c0000000-0000-0000-0000-000000000003","branch_id":"ac000000-0000-0000-0000-000000000001","cash_register_id":"ae100000-0000-0000-0000-000000000003","cash_session_id":"af000000-0000-0000-0000-000000000031","subtotal":10,"total":10,"payment_method":"card","status":"completed","created_at":"2026-08-31T10:02:00Z"}', 'pending', 'sale-c'),
  ('b1000000-0000-0000-0000-000000000032', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'item-c', 2, 'sale_items', 'c1000000-0000-0000-0000-000000000003', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000003","product_id":"ae000000-0000-0000-0000-000000000001","quantity":1,"unit_price":10,"subtotal":10,"total":10,"created_at":"2026-08-31T10:02:00Z"}', 'pending', 'item-c'),
  ('b1000000-0000-0000-0000-000000000033', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000003', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'payment-c', 3, 'sale_payments', 'c2000000-0000-0000-0000-000000000003', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000003","payment_method":"card","amount":10,"currency":"COP","status":"completed","created_at":"2026-08-31T10:02:00Z"}', 'pending', 'payment-c'),

  ('b1000000-0000-0000-0000-000000000041', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'sale-d', 1, 'sales', 'c0000000-0000-0000-0000-000000000004', 'insert', '{"id":"c0000000-0000-0000-0000-000000000004","branch_id":"ac000000-0000-0000-0000-000000000001","cash_register_id":"ae100000-0000-0000-0000-000000000004","cash_session_id":"af000000-0000-0000-0000-000000000041","subtotal":10,"total":10,"payment_method":"cash","status":"completed","created_at":"2026-08-31T10:03:00Z"}', 'pending', 'sale-d'),
  ('b1000000-0000-0000-0000-000000000042', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'item-d', 2, 'sale_items', 'c1000000-0000-0000-0000-000000000004', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000004","product_id":"ae000000-0000-0000-0000-000000000001","quantity":1,"unit_price":10,"subtotal":10,"total":10,"created_at":"2026-08-31T10:03:00Z"}', 'pending', 'item-d'),
  ('b1000000-0000-0000-0000-000000000043', 'ab000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-000000000004', 'ad100000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001', 'payment-d', 3, 'sale_payments', 'c2000000-0000-0000-0000-000000000004', 'insert', '{"sale_id":"c0000000-0000-0000-0000-000000000004","payment_method":"cash","amount":10,"currency":"COP","status":"completed","created_at":"2026-08-31T10:03:00Z"}', 'pending', 'payment-d');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);
select public.process_sync_batch('b0000000-0000-0000-0000-000000000001', 'apply_pos');
select public.process_sync_batch('b0000000-0000-0000-0000-000000000002', 'apply_pos');
select public.process_sync_batch('b0000000-0000-0000-0000-000000000003', 'apply_pos');
select public.process_sync_batch('b0000000-0000-0000-0000-000000000004', 'apply_pos');

insert into intentional_stale_sale_state (sale_id, conflict_id)
select conflict.entity_id, conflict.id
from public.sync_conflicts conflict
where conflict.entity_id in (
  'c0000000-0000-0000-0000-000000000001',
  'c0000000-0000-0000-0000-000000000002',
  'c0000000-0000-0000-0000-000000000003',
  'c0000000-0000-0000-0000-000000000004'
);

select public.reconcile_rejected_sale_to_open_cash_session(
  'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001',
  (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000001'),
  'af000000-0000-0000-0000-000000000012', 'd0000000-0000-0000-0000-000000000001',
  'reconciliation-a', 'Cash was not in opening', 'not_included_in_destination_opening'
);
select public.close_cash_session_authoritatively(
  'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  'ae100000-0000-0000-0000-000000000001', 'af000000-0000-0000-0000-000000000012', 110, 'test A'
);
select ok(
  exists (select 1 from public.sales where id = 'c0000000-0000-0000-0000-000000000001' and cash_session_id = 'af000000-0000-0000-0000-000000000012')
  and exists (select 1 from public.sale_items where sale_id = 'c0000000-0000-0000-0000-000000000001')
  and exists (select 1 from public.sale_payments where sale_id = 'c0000000-0000-0000-0000-000000000001')
  and exists (select 1 from public.inventory_movements where source_type = 'sale' and source_id = 'c0000000-0000-0000-0000-000000000001')
  and not exists (select 1 from public.cash_session_adjustments where reconciliation_id = 'd0000000-0000-0000-0000-000000000001')
  and (select expected_closing_amount = 110 and difference_amount = 0 from public.cash_sessions where id = 'af000000-0000-0000-0000-000000000012'),
  'A. not_included materializes the Sale and closes at opening plus cash payment'
);

select public.reconcile_rejected_sale_to_open_cash_session(
  'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002',
  (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000002'),
  'af000000-0000-0000-0000-000000000022', 'd0000000-0000-0000-0000-000000000002',
  'reconciliation-b', 'Cash was already in opening', 'already_included_in_destination_opening'
);
select public.close_cash_session_authoritatively(
  'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  'ae100000-0000-0000-0000-000000000002', 'af000000-0000-0000-0000-000000000022', 110, 'test B'
);
select ok(
  (select amount = -10 from public.cash_session_adjustments where reconciliation_id = 'd0000000-0000-0000-0000-000000000002')
  and (select cash_reconciled_total = 10 and cash_adjustment_total = -10
       from public.sale_reconciliations where id = 'd0000000-0000-0000-0000-000000000002')
  and (select expected_closing_amount = 110 and difference_amount = 0 from public.cash_sessions where id = 'af000000-0000-0000-0000-000000000022')
  and exists (select 1 from public.inventory_movements where source_type = 'sale' and source_id = 'c0000000-0000-0000-0000-000000000002'),
  'B. already_included creates one negative adjustment and avoids double cash'
);

select public.reconcile_rejected_sale_to_open_cash_session(
  'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
  'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003',
  (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000003'),
  'af000000-0000-0000-0000-000000000032', 'd0000000-0000-0000-0000-000000000003',
  'reconciliation-c', 'No cash payment', 'already_included_in_destination_opening'
);
select ok(
  exists (select 1 from public.sales where id = 'c0000000-0000-0000-0000-000000000003')
  and not exists (select 1 from public.cash_session_adjustments where reconciliation_id = 'd0000000-0000-0000-0000-000000000003')
  and (select cash_adjustment_total = 0 from public.sale_reconciliations where id = 'd0000000-0000-0000-0000-000000000003'),
  'C. a no-cash Sale creates no cash adjustment'
);

select is(
  (public.reconcile_rejected_sale_to_open_cash_session(
    'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
    'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002',
    (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000002'),
    'af000000-0000-0000-0000-000000000022', 'd0000000-0000-0000-0000-000000000002',
    'reconciliation-b', 'Cash was already in opening', 'already_included_in_destination_opening'
  ) ->> 'idempotent')::boolean,
  true,
  'D. an identical retry returns the existing completed result'
);

select throws_ok(
  $$select public.reconcile_rejected_sale_to_open_cash_session(
    'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
    'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002',
    (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000002'),
    'af000000-0000-0000-0000-000000000022', 'd0000000-0000-0000-0000-000000000002',
    'reconciliation-b', 'Changed treatment', 'not_included_in_destination_opening'
  )$$,
  '23505',
  'Sale was already reconciled with another identity, destination, or cash treatment',
  'E. a retry cannot change destination or cash treatment'
);

create function pg_temp.v2_guard_rejects(
  p_profile_id uuid,
  p_app_device_id uuid,
  p_destination_cash_session_id uuid,
  p_expected_message text
)
returns boolean
language plpgsql
as $$
declare
  v_conflict_id uuid;
begin
  perform set_config('request.jwt.claim.sub', p_profile_id::text, true);
  select conflict_id into v_conflict_id
  from intentional_stale_sale_state
  where sale_id = 'c0000000-0000-0000-0000-000000000004';

  perform public.reconcile_rejected_sale_to_open_cash_session(
    'ab000000-0000-0000-0000-000000000001',
    'ac000000-0000-0000-0000-000000000001',
    p_app_device_id,
    'c0000000-0000-0000-0000-000000000004',
    v_conflict_id,
    p_destination_cash_session_id,
    'd0000000-0000-0000-0000-000000000004',
    'reconciliation-d',
    'Security guard test',
    'not_included_in_destination_opening'
  );
  return false;
exception when others then
  return position(p_expected_message in sqlerrm) > 0;
end;
$$;

select ok(
  pg_temp.v2_guard_rejects(
    'aa000000-0000-0000-0000-000000000002',
    'ad100000-0000-0000-0000-000000000002',
    'af000000-0000-0000-0000-000000000043',
    'Stale Sale reconciliation is not authorized'
  )
  and pg_temp.v2_guard_rejects(
    'aa000000-0000-0000-0000-000000000001',
    'ad100000-0000-0000-0000-000000000001',
    'af000000-0000-0000-0000-000000000051',
    'destination_cash_session_required'
  )
  and pg_temp.v2_guard_rejects(
    'aa000000-0000-0000-0000-000000000001',
    'ad100000-0000-0000-0000-000000000001',
    'af000000-0000-0000-0000-000000000032',
    'destination_cash_session_required'
  ),
  'F. unauthorized, cross-branch and cross-register destinations are rejected'
);

select set_config('request.jwt.claim.sub', 'aa000000-0000-0000-0000-000000000001', true);
select throws_ok(
  $$select public.reconcile_rejected_sale_to_open_cash_session(
    'ab000000-0000-0000-0000-000000000001', 'ac000000-0000-0000-0000-000000000001',
    'ad100000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004',
    (select conflict_id from intentional_stale_sale_state where sale_id = 'c0000000-0000-0000-0000-000000000004'),
    'af000000-0000-0000-0000-000000000042', 'd0000000-0000-0000-0000-000000000004',
    'reconciliation-d', 'Closed destination', 'not_included_in_destination_opening'
  )$$,
  'P0001',
  'destination_cash_session_required',
  'G. a closed destination fails without materializing the Sale'
);

select ok(
  (select bool_and(status = 'skipped' and metadata ? 'superseded_by_sale_reconciliation')
   from public.sync_mutations where sync_batch_id = 'b0000000-0000-0000-0000-000000000001')
  and (select status = 'partial' and metadata ? 'sale_reconciliation_id'
       from public.sync_batches where id = 'b0000000-0000-0000-0000-000000000001')
  and (public.process_sync_batch('b0000000-0000-0000-0000-000000000001', 'apply_pos') ->> 'processed_count')::integer = 0,
  'H. superseded mutations remain historical and the finalized batch is not reprocessed'
);

select * from finish();
rollback;
