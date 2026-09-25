-- P2.6A1 focused validation for the authoritative branch sales summary.
-- The transaction always rolls back fixture data.

begin;

set local timezone = 'UTC';

select plan(27);

select is(
  has_function_privilege(
    'anon',
    'public.get_branch_sales_report_summary(uuid,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ),
  false,
  'SR-01 anon cannot execute the sales summary RPC'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('b6000000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'sr-owner@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'sr-admin@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'sr-sales-reader@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000104', 'authenticated', 'authenticated', 'sr-no-membership@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000105', 'authenticated', 'authenticated', 'sr-foreign@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000106', 'authenticated', 'authenticated', 'sr-branch@example.test', '', now(), '{}', '{}', now(), now()),
  ('b6000000-0000-0000-0000-000000000107', 'authenticated', 'authenticated', 'sr-inactive-member@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('b6000000-0000-0000-0000-000000000101', 'SR Owner', 'owner', 'active'),
  ('b6000000-0000-0000-0000-000000000102', 'SR Admin', 'admin', 'active'),
  ('b6000000-0000-0000-0000-000000000103', 'SR Sales Reader', 'cashier', 'active'),
  ('b6000000-0000-0000-0000-000000000104', 'SR No Membership', 'cashier', 'active'),
  ('b6000000-0000-0000-0000-000000000105', 'SR Foreign Reporter', 'owner', 'active'),
  ('b6000000-0000-0000-0000-000000000106', 'SR Branch Reporter', 'cashier', 'active'),
  ('b6000000-0000-0000-0000-000000000107', 'SR Inactive Member', 'cashier', 'active');

insert into public.businesses (id, name, status)
values
  ('b6000000-0000-0000-0000-000000000001', 'SR Business A', 'active'),
  ('b6000000-0000-0000-0000-000000000002', 'SR Business B', 'active'),
  ('b6000000-0000-0000-0000-000000000003', 'SR Inactive Business', 'inactive');

insert into public.branches (id, business_id, name, status)
values
  ('b6000000-0000-0000-0000-000000000011', 'b6000000-0000-0000-0000-000000000001', 'SR A One', 'active'),
  ('b6000000-0000-0000-0000-000000000012', 'b6000000-0000-0000-0000-000000000001', 'SR A Two', 'active'),
  ('b6000000-0000-0000-0000-000000000013', 'b6000000-0000-0000-0000-000000000001', 'SR A Inactive', 'inactive'),
  ('b6000000-0000-0000-0000-000000000021', 'b6000000-0000-0000-0000-000000000002', 'SR B One', 'active'),
  ('b6000000-0000-0000-0000-000000000031', 'b6000000-0000-0000-0000-000000000003', 'SR Inactive Business Branch', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values
  ('b6000000-0000-0000-0000-000000000041', 'b6000000-0000-0000-0000-000000000001', 'sr-sales-reader-export-a', 'Sales read and export without reports.sales', false),
  ('b6000000-0000-0000-0000-000000000042', 'b6000000-0000-0000-0000-000000000001', 'sr-branch-reporter-a', 'Branch-scoped sales reporter', false);

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
join public.permissions permission
  on permission.key in ('sales.read', 'reports.export')
where role.id = 'b6000000-0000-0000-0000-000000000041';

insert into public.role_permissions (role_id, permission_id)
select 'b6000000-0000-0000-0000-000000000042', permission.id
from public.permissions permission
where permission.key = 'reports.sales';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  (
    'b6000000-0000-0000-0000-000000000051',
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000101',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active', null
  ),
  (
    'b6000000-0000-0000-0000-000000000052',
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000102',
    null,
    (select id from public.roles where business_id is null and name = 'admin' and deleted_at is null limit 1),
    'active', null
  ),
  ('b6000000-0000-0000-0000-000000000053', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000103', 'b6000000-0000-0000-0000-000000000011', 'b6000000-0000-0000-0000-000000000041', 'active', null),
  (
    'b6000000-0000-0000-0000-000000000054',
    'b6000000-0000-0000-0000-000000000002',
    'b6000000-0000-0000-0000-000000000105',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active', null
  ),
  ('b6000000-0000-0000-0000-000000000055', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000106', 'b6000000-0000-0000-0000-000000000011', 'b6000000-0000-0000-0000-000000000042', 'active', null),
  ('b6000000-0000-0000-0000-000000000056', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000107', 'b6000000-0000-0000-0000-000000000011', 'b6000000-0000-0000-0000-000000000042', 'suspended', null),
  (
    'b6000000-0000-0000-0000-000000000057',
    'b6000000-0000-0000-0000-000000000003',
    'b6000000-0000-0000-0000-000000000101',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active', null
  );

insert into public.sales (
  id, business_id, branch_id, total, payment_method, status,
  created_at, voided_at, voided_by, void_reason, deleted_at
)
values
  ('b6000000-0000-0000-0000-000000000201', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 100.00, 'cash', 'completed', '2026-09-01T00:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000202', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 200.00, 'card', 'completed', '2026-09-01T01:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000203', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 999.00, 'cash', 'completed', '2026-09-01T10:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000204', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 40.00, 'cash', 'completed', '2026-09-01T04:00:00Z', '2026-09-01T04:30:00Z', 'b6000000-0000-0000-0000-000000000101', 'Voided fixture', null),
  ('b6000000-0000-0000-0000-000000000205', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 50.00, 'cash', 'completed', '2026-09-01T05:00:00Z', null, null, null, '2026-09-01T05:30:00Z'),
  ('b6000000-0000-0000-0000-000000000206', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 60.00, 'cash', 'pending', '2026-09-01T06:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000207', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 70.00, 'cash', 'draft', '2026-09-01T07:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000208', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 80.00, 'cash', 'cancelled', '2026-09-01T08:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000209', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000012', 300.00, 'cash', 'completed', '2026-09-01T02:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000210', 'b6000000-0000-0000-0000-000000000002', 'b6000000-0000-0000-0000-000000000021', 400.00, 'cash', 'completed', '2026-09-01T03:00:00Z', null, null, null, null),
  ('b6000000-0000-0000-0000-000000000211', 'b6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000011', 25.00, 'cash', 'completed', '2026-08-31T23:59:59Z', null, null, null, null);

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Authentication required',
  'SR-02 the function body rejects a missing authenticated identity'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000104', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-03 authenticated caller without membership is rejected'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000107', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-04 inactive membership is rejected'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000105', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-05 membership in another business is rejected'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000101', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000021',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-06 branch from another business is rejected'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000103', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-07 sales.read plus reports.export does not grant reports.sales'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000101', true);
select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  2::bigint,
  'SR-08 owner with reports.sales is authorized'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000102', true);
select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  2::bigint,
  'SR-09 admin with reports.sales is authorized'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000106', true);
select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  2::bigint,
  'SR-10 branch-scoped reports.sales membership can query its branch'
);

select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000012',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-11 branch-scoped membership cannot query another branch'
);

select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000101', true);
select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      null,
      '2026-09-01T10:00:00Z'
    )$$,
  '22023',
  'business_id, branch_id, from and to are required',
  'SR-12 null report parameters fail closed'
);

select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T10:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '22023',
  'to timestamp must be greater than from timestamp',
  'SR-13 empty or reversed periods fail closed'
);

select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  2::bigint,
  'SR-14 only valid completed sales count'
);

select is(
  (select summary.gross_sales from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  300.00::numeric,
  'SR-15 multiple completed sales sum exactly as numeric'
);

select is(
  (select summary.average_ticket from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  150.00::numeric,
  'SR-16 average ticket is gross sales divided by sale count'
);

select is(
  (select summary.gross_sales from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T00:00:01Z'
  ) summary),
  100.00::numeric,
  'SR-17 from boundary is inclusive'
);

select is(
  (select summary.gross_sales from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  300.00::numeric,
  'SR-18 to boundary is exclusive'
);

select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T04:00:00Z', '2026-09-01T04:01:00Z'
  ) summary),
  0::bigint,
  'SR-19 voided completed sale does not count'
);

select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T05:00:00Z', '2026-09-01T05:01:00Z'
  ) summary),
  0::bigint,
  'SR-20 soft-deleted completed sale does not count'
);

select is(
  (select summary.sale_count from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T06:00:00Z', '2026-09-01T09:00:00Z'
  ) summary),
  0::bigint,
  'SR-21 pending, draft and cancelled sales do not count'
);

select ok(
  (
    select summary.gross_sales = 0::numeric
       and summary.sale_count = 0
       and summary.average_ticket is null
    from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-02T00:00:00Z', '2026-09-03T00:00:00Z'
    ) summary
  ),
  'SR-22 an empty period returns zero gross/count and null average ticket'
);

select ok(
  (
    select summary.business_id = 'b6000000-0000-0000-0000-000000000001'
       and summary.branch_id = 'b6000000-0000-0000-0000-000000000011'
       and summary.period_from = '2026-09-01T00:00:00Z'::timestamptz
       and summary.period_to = '2026-09-01T10:00:00Z'::timestamptz
       and summary.authoritative_as_of is not null
    from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
    ) summary
  ),
  'SR-23 result echoes scope/period and includes authoritative timestamp'
);

select is(
  (select summary.gross_sales from public.get_branch_sales_report_summary(
    'b6000000-0000-0000-0000-000000000001',
    'b6000000-0000-0000-0000-000000000011',
    '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
  ) summary),
  300.00::numeric,
  'SR-24 sales from another branch or business do not contaminate the result'
);

select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000013',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-25 inactive branch is rejected'
);

select throws_ok(
  $$select * from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000003',
      'b6000000-0000-0000-0000-000000000031',
      '2026-09-01T00:00:00Z',
      '2026-09-01T10:00:00Z'
    )$$,
  '42501',
  'Sales report is not authorized for this branch',
  'SR-26 inactive business is rejected'
);

reset role;

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values (
  'b6000000-0000-0000-0000-000000000301',
  'b6000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000101',
  'b6000000-0000-0000-0000-000000000011',
  'sr-did-not-occur-device',
  'active'
);

insert into public.sync_batches (
  id, business_id, app_device_id, profile_id, branch_id,
  client_batch_id, direction, status, mutation_count
)
values (
  'b6000000-0000-0000-0000-000000000311',
  'b6000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000301',
  'b6000000-0000-0000-0000-000000000101',
  'b6000000-0000-0000-0000-000000000011',
  'sr-did-not-occur', 'upload', 'pending', 1
);

insert into public.sync_mutations (
  id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
  client_mutation_id, client_sequence, entity_table, entity_id, operation,
  payload, status, idempotency_key
)
values (
  'b6000000-0000-0000-0000-000000000321',
  'b6000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000311',
  'b6000000-0000-0000-0000-000000000301',
  'b6000000-0000-0000-0000-000000000101',
  'b6000000-0000-0000-0000-000000000011',
  'sr-did-not-occur-sale', 1, 'sales',
  'b6000000-0000-0000-0000-000000000331', 'insert',
  '{"id":"b6000000-0000-0000-0000-000000000331"}',
  'pending', 'sr-did-not-occur-sale'
);

insert into public.sync_conflicts (
  id, business_id, sync_batch_id, sync_mutation_id, app_device_id,
  profile_id, branch_id, entity_table, entity_id, operation,
  client_mutation_id, client_sequence, conflict_type, severity, status,
  client_payload, metadata
)
values (
  'b6000000-0000-0000-0000-000000000341',
  'b6000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000311',
  'b6000000-0000-0000-0000-000000000321',
  'b6000000-0000-0000-0000-000000000301',
  'b6000000-0000-0000-0000-000000000101',
  'b6000000-0000-0000-0000-000000000011',
  'sales', 'b6000000-0000-0000-0000-000000000331', 'insert',
  'sr-did-not-occur-sale', 1, 'business_rule_violation', 'high', 'open',
  '{}',
  '{"rule":"sale_cash_session_invalid","reason":"closed","sale_id":"b6000000-0000-0000-0000-000000000331"}'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b6000000-0000-0000-0000-000000000101', true);

select public.resolve_unmaterialized_sale_did_not_occur(
  'b6000000-0000-0000-0000-000000000001',
  'b6000000-0000-0000-0000-000000000011',
  'b6000000-0000-0000-0000-000000000301',
  'b6000000-0000-0000-0000-000000000331',
  'b6000000-0000-0000-0000-000000000341',
  'sr-report-did-not-occur',
  'Sale did not occur.'
);

select ok(
  not exists (
    select 1 from public.sales
    where id = 'b6000000-0000-0000-0000-000000000331'
  )
  and (
    select conflict.status = 'resolved'
       and conflict.resolution_strategy = 'sale_did_not_occur'
    from public.sync_conflicts conflict
    where conflict.id = 'b6000000-0000-0000-0000-000000000341'
  )
  and (
    select summary.gross_sales = 300.00::numeric
       and summary.sale_count = 2
    from public.get_branch_sales_report_summary(
      'b6000000-0000-0000-0000-000000000001',
      'b6000000-0000-0000-0000-000000000011',
      '2026-09-01T00:00:00Z', '2026-09-01T10:00:00Z'
    ) summary
  ),
  'SR-27 an authoritative did-not-occur stale sale never enters the report'
);

reset role;
select * from finish();
rollback;
