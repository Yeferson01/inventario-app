-- P2.6B1: profitability uses only historical, known sale-item costs.
begin;
set local timezone = 'UTC';
select plan(42);

select is(
  has_function_privilege('anon',
    'public.get_branch_profitability_report_summary(uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'), false, 'PR-01 anon has no EXECUTE privilege'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select ('b6100000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', 'pr-' || n || '@example.test', '',
  now(), '{}', '{}', now(), now()
from generate_series(101, 112) n;

insert into public.profiles (id, full_name, role, status)
select ('b6100000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'PR fixture ' || n, 'cashier', 'active'
from generate_series(101, 112) n;

insert into public.businesses (id, name, status)
values
  ('b6100000-0000-0000-0000-000000000001', 'PR business A', 'active'),
  ('b6100000-0000-0000-0000-000000000002', 'PR business B', 'active'),
  ('b6100000-0000-0000-0000-000000000003', 'PR inactive business', 'inactive');

insert into public.branches (id, business_id, name, status)
values
  ('b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000001', 'PR A1', 'active'),
  ('b6100000-0000-0000-0000-000000000012', 'b6100000-0000-0000-0000-000000000001', 'PR A2', 'active'),
  ('b6100000-0000-0000-0000-000000000013', 'b6100000-0000-0000-0000-000000000001', 'PR inactive', 'inactive'),
  ('b6100000-0000-0000-0000-000000000021', 'b6100000-0000-0000-0000-000000000002', 'PR B1', 'active'),
  ('b6100000-0000-0000-0000-000000000031', 'b6100000-0000-0000-0000-000000000003', 'PR inactive business branch', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('b6100000-0000-0000-0000-000000000041', 'b6100000-0000-0000-0000-000000000001', 'pr-reports-only', 'Reports only', false),
  ('b6100000-0000-0000-0000-000000000042', 'b6100000-0000-0000-0000-000000000001', 'pr-costs-only', 'Costs only', false),
  ('b6100000-0000-0000-0000-000000000043', 'b6100000-0000-0000-0000-000000000001', 'pr-both', 'Both permissions', false),
  ('b6100000-0000-0000-0000-000000000044', 'b6100000-0000-0000-0000-000000000001', 'pr-read-export', 'Read and export only', false);

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
join public.permissions permission on (
  (role.name = 'pr-reports-only' and permission.key = 'reports.sales')
  or (role.name = 'pr-costs-only' and permission.key = 'sales.view_costs')
  or (role.name = 'pr-both' and permission.key in ('reports.sales', 'sales.view_costs'))
  or (role.name = 'pr-read-export' and permission.key in ('sales.read', 'reports.export'))
)
where role.id in (
  'b6100000-0000-0000-0000-000000000041',
  'b6100000-0000-0000-0000-000000000042',
  'b6100000-0000-0000-0000-000000000043',
  'b6100000-0000-0000-0000-000000000044'
);

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  ('b6100000-0000-0000-0000-000000000051', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000101', null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('b6100000-0000-0000-0000-000000000052', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000102', null,
    (select id from public.roles where business_id is null and name = 'admin' and deleted_at is null limit 1), 'active', null),
  ('b6100000-0000-0000-0000-000000000053', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000103', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000041', 'active', null),
  ('b6100000-0000-0000-0000-000000000054', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000104', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000042', 'active', null),
  ('b6100000-0000-0000-0000-000000000055', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000105', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000043', 'active', null),
  ('b6100000-0000-0000-0000-000000000056', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000106', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000044', 'active', null),
  ('b6100000-0000-0000-0000-000000000057', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000107', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000043', 'suspended', null),
  ('b6100000-0000-0000-0000-000000000058', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000108', 'b6100000-0000-0000-0000-000000000011', 'b6100000-0000-0000-0000-000000000043', 'active', now()),
  ('b6100000-0000-0000-0000-000000000059', 'b6100000-0000-0000-0000-000000000002', 'b6100000-0000-0000-0000-000000000109', null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('b6100000-0000-0000-0000-000000000060', 'b6100000-0000-0000-0000-000000000003', 'b6100000-0000-0000-0000-000000000101', null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1), 'active', null),
  ('b6100000-0000-0000-0000-000000000061', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000110', 'b6100000-0000-0000-0000-000000000011',
    (select id from public.roles where business_id is null and name = 'cashier' and deleted_at is null limit 1), 'active', null),
  ('b6100000-0000-0000-0000-000000000062', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000111', 'b6100000-0000-0000-0000-000000000011',
    (select id from public.roles where business_id is null and name = 'warehouse' and deleted_at is null limit 1), 'active', null);

insert into public.sales (
  id, business_id, branch_id, total, payment_method, status, created_at
)
values
  ('b6100000-0000-0000-0000-000000000201', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 190, 'cash', 'completed', '2026-09-01T00:00:00Z'),
  ('b6100000-0000-0000-0000-000000000202', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 50, 'cash', 'completed', '2026-09-01T01:00:00Z'),
  ('b6100000-0000-0000-0000-000000000203', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 60, 'cash', 'completed', '2026-09-01T02:00:00Z'),
  ('b6100000-0000-0000-0000-000000000204', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 20, 'cash', 'completed', '2026-09-01T03:00:00Z'),
  ('b6100000-0000-0000-0000-000000000205', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 30, 'cash', 'completed', '2026-09-01T04:00:00Z'),
  ('b6100000-0000-0000-0000-000000000206', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 40, 'cash', 'pending', '2026-09-01T05:00:00Z'),
  ('b6100000-0000-0000-0000-000000000207', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000012', 50, 'cash', 'completed', '2026-09-01T06:00:00Z'),
  ('b6100000-0000-0000-0000-000000000208', 'b6100000-0000-0000-0000-000000000002', 'b6100000-0000-0000-0000-000000000021', 60, 'cash', 'completed', '2026-09-01T07:00:00Z'),
  ('b6100000-0000-0000-0000-000000000209', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 90, 'cash', 'completed', '2026-09-01T10:00:00Z'),
  ('b6100000-0000-0000-0000-000000000210', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 100, 'cash', 'completed', '2026-08-31T23:59:59Z'),
  ('b6100000-0000-0000-0000-000000000211', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011', 80, 'cash', 'completed', '2026-09-01T08:00:00Z');

insert into public.sale_items (
  id, business_id, sale_id, quantity, unit_price, subtotal,
  discount_amount, tax_amount, total, unit_cost_snapshot
)
values
  ('b6100000-0000-0000-0000-000000000301', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000201', 2, 100, 200, 20, 10, 190, 40),
  ('b6100000-0000-0000-0000-000000000302', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000202', 1, 50, 50, 0, 0, 50, 0),
  ('b6100000-0000-0000-0000-000000000303', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000203', 1, 70, 70, 10, 0, 60, null),
  ('b6100000-0000-0000-0000-000000000304', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000204', 1, 20, 20, 0, 0, 20, 10),
  ('b6100000-0000-0000-0000-000000000305', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000205', 1, 30, 30, 0, 0, 30, 5),
  ('b6100000-0000-0000-0000-000000000306', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000206', 1, 40, 40, 0, 0, 40, 5),
  ('b6100000-0000-0000-0000-000000000307', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000207', 1, 50, 50, 0, 0, 50, 5),
  ('b6100000-0000-0000-0000-000000000308', 'b6100000-0000-0000-0000-000000000002', 'b6100000-0000-0000-0000-000000000208', 1, 60, 60, 0, 0, 60, 5),
  ('b6100000-0000-0000-0000-000000000309', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000209', 1, 90, 90, 0, 0, 90, 5),
  ('b6100000-0000-0000-0000-000000000310', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000210', 1, 100, 100, 0, 0, 100, 5),
  ('b6100000-0000-0000-0000-000000000311', 'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000211', 1, 80, 80, 0, 0, 80, 5);

update public.sale_items set deleted_at = '2026-09-01T03:30:00Z'
where id = 'b6100000-0000-0000-0000-000000000304';
update public.sales set voided_at = '2026-09-01T04:30:00Z',
  voided_by = 'b6100000-0000-0000-0000-000000000101',
  void_reason = 'fixture'
where id = 'b6100000-0000-0000-0000-000000000205';
update public.sales set deleted_at = '2026-09-01T08:30:00Z'
where id = 'b6100000-0000-0000-0000-000000000211';

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Authentication required', 'PR-02 authenticated role without identity rejected');

select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000103', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-03 reports.sales alone rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000104', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-04 sales.view_costs alone rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000106', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-05 sales.read and reports.export insufficient');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000107', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-06 inactive membership rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000108', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-07 deleted membership rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000109', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-08 cross-business denied');

select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000112', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-40 profile without membership rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000110', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-41 system cashier rejected');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000111', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-42 system warehouse rejected');

select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000101', true);
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 230::numeric, 'PR-09 owner permitted, revenue excludes tax and discount once');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000102', true);
select is((select known_cogs from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 80::numeric, 'PR-10 admin permitted, quantity times historical cost');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000105', true);
select is((select known_gross_profit from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 150::numeric, 'PR-11 custom role with both capabilities permitted');
select is((select known_gross_margin from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 150::numeric / 230::numeric, 'PR-12 exact margin ratio, unrounded');
select is((select unknown_cost_item_count from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 1::bigint, 'PR-13 NULL cost counted as unknown item');
select is((select unknown_cost_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 60::numeric, 'PR-14 unknown-cost net revenue separated');
select is((select cost_coverage_complete from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), false, 'PR-15 mixed costs yield incomplete coverage');
select ok((select authoritative_as_of is not null from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 'PR-16 server timestamp returned');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T01:00:00Z', '2026-09-01T02:00:00Z')), 50::numeric, 'PR-17 zero historical cost is known, not unknown');
select is((select unknown_cost_item_count from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T01:00:00Z', '2026-09-01T02:00:00Z')), 0::bigint, 'PR-18 zero cost does not reduce coverage');
select is((select cost_coverage_complete from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T02:00:00Z')), true, 'PR-19 known-only period has complete cost coverage');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T02:00:00Z', '2026-09-01T03:00:00Z')), 0::numeric, 'PR-20 NULL-only cost has no known revenue');
select is((select unknown_cost_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T02:00:00Z', '2026-09-01T03:00:00Z')), 60::numeric, 'PR-21 NULL-only cost retains unknown revenue');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T03:00:00Z', '2026-09-01T04:00:00Z')), 0::numeric, 'PR-22 deleted item excluded');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T04:00:00Z', '2026-09-01T05:00:00Z')), 0::numeric, 'PR-23 voided sale excluded');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T05:00:00Z', '2026-09-01T06:00:00Z')), 0::numeric, 'PR-24 pending sale excluded');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T08:00:00Z', '2026-09-01T09:00:00Z')), 0::numeric, 'PR-25 deleted sale excluded');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T01:00:00Z')), 180::numeric, 'PR-26 from inclusive, to exclusive');
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T10:00:00Z', '2026-09-01T11:00:00Z')), 90::numeric, 'PR-27 sale exactly at next from included');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000101', true);
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000012',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 50::numeric, 'PR-28 other branch has isolated totals');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000109', true);
select is((select known_net_sales from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000002', 'b6100000-0000-0000-0000-000000000021',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 60::numeric, 'PR-29 other business has isolated totals');
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000101', true);
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000021',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-30 cross-business branch rejected');
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000013',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-31 inactive branch rejected');
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000003', 'b6100000-0000-0000-0000-000000000031',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '42501', 'Profitability report is not authorized for this branch', 'PR-32 inactive business rejected');
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  null, 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')$$,
  '22023', 'business_id, branch_id, from and to are required', 'PR-33 null scope rejected');
select throws_ok($$select * from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T10:00:00Z', '2026-09-01T00:00:00Z')$$,
  '22023', 'to timestamp must be greater than from timestamp', 'PR-34 inverted period rejected');
select ok((select known_net_sales = 0 and known_cogs = 0 and known_gross_profit = 0
    and known_gross_margin is null and unknown_cost_item_count = 0
    and unknown_cost_net_sales = 0 and cost_coverage_complete
  from public.get_branch_profitability_report_summary(
    'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
    '2026-09-02T00:00:00Z', '2026-09-03T00:00:00Z')),
  'PR-35 empty period is zero with NULL margin and complete coverage');
select ok((select known_net_sales = 0 and known_gross_margin is null
  from public.get_branch_profitability_report_summary(
    'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
    '2026-09-01T02:00:00Z', '2026-09-01T03:00:00Z')),
  'PR-36 unknown-only period has no valid known margin denominator');
select is((select unknown_cost_item_count from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')), 1::bigint,
  'PR-37 other branches and businesses cannot contaminate unknown count');

-- A stale sale resolved as did_not_occur is a conflict, not a completed sale.
reset role;
insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
) values (
  'b6100000-0000-0000-0000-000000000401',
  'b6100000-0000-0000-0000-000000000001',
  'b6100000-0000-0000-0000-000000000101',
  'b6100000-0000-0000-0000-000000000011', 'pr-did-not-occur-device', 'active'
);
insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count
) values (
  'b6100000-0000-0000-0000-000000000411',
  'b6100000-0000-0000-0000-000000000001',
  'b6100000-0000-0000-0000-000000000401',
  'b6100000-0000-0000-0000-000000000101',
  'b6100000-0000-0000-0000-000000000011',
  'pr-did-not-occur', 'upload', 'pending', 1
);
insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
) values (
  'b6100000-0000-0000-0000-000000000421',
  'b6100000-0000-0000-0000-000000000001',
  'b6100000-0000-0000-0000-000000000411',
  'b6100000-0000-0000-0000-000000000401',
  'b6100000-0000-0000-0000-000000000101',
  'b6100000-0000-0000-0000-000000000011',
  'pr-did-not-occur-sale', 1, 'sales',
  'b6100000-0000-0000-0000-000000000431', 'insert',
  '{"id":"b6100000-0000-0000-0000-000000000431"}', 'pending',
  'pr-did-not-occur-sale'
);
insert into public.sync_conflicts (
  id, business_id, sync_batch_id, sync_mutation_id, app_device_id,
  profile_id, branch_id, entity_table, entity_id, operation,
  client_mutation_id, client_sequence, conflict_type, severity, status,
  client_payload, metadata
) values (
  'b6100000-0000-0000-0000-000000000441',
  'b6100000-0000-0000-0000-000000000001',
  'b6100000-0000-0000-0000-000000000411',
  'b6100000-0000-0000-0000-000000000421',
  'b6100000-0000-0000-0000-000000000401',
  'b6100000-0000-0000-0000-000000000101',
  'b6100000-0000-0000-0000-000000000011',
  'sales', 'b6100000-0000-0000-0000-000000000431', 'insert',
  'pr-did-not-occur-sale', 1, 'business_rule_violation', 'high', 'open',
  '{}',
  '{"rule":"sale_cash_session_invalid","reason":"closed","sale_id":"b6100000-0000-0000-0000-000000000431"}'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b6100000-0000-0000-0000-000000000101', true);
select public.resolve_unmaterialized_sale_did_not_occur(
  'b6100000-0000-0000-0000-000000000001',
  'b6100000-0000-0000-0000-000000000011',
  'b6100000-0000-0000-0000-000000000401',
  'b6100000-0000-0000-0000-000000000431',
  'b6100000-0000-0000-0000-000000000441',
  'pr-report-did-not-occur', 'Sale did not occur.'
);
select ok(
  not exists (select 1 from public.sales where id = 'b6100000-0000-0000-0000-000000000431')
  and exists (select 1 from public.sync_conflicts where id = 'b6100000-0000-0000-0000-000000000441'
    and status = 'resolved' and resolution_strategy = 'sale_did_not_occur')
  and (select known_net_sales = 230 and unknown_cost_item_count = 1
    from public.get_branch_profitability_report_summary(
      'b6100000-0000-0000-0000-000000000001',
      'b6100000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z')),
  'PR-38 resolved did-not-occur stale sale cannot enter profitability'
);
select is((select count(*) from public.get_branch_profitability_report_summary(
  'b6100000-0000-0000-0000-000000000001', 'b6100000-0000-0000-0000-000000000011',
  '2026-09-02T00:00:00Z', '2026-09-03T00:00:00Z')), 1::bigint,
  'PR-39 empty period returns exactly one summary row');

reset role;
select * from finish();
rollback;
