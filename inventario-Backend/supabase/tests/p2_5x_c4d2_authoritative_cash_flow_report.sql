begin;
set local timezone = 'UTC';
select plan(33);

select is(has_function_privilege('anon',
  'public.get_branch_cash_flow_report_summary(uuid,uuid,timestamptz,timestamptz)',
  'EXECUTE'), false, 'CF-01 anon has no execute');
select is(has_function_privilege('authenticated',
  'public.get_branch_cash_flow_report_summary(uuid,uuid,timestamptz,timestamptz)',
  'EXECUTE'), true, 'CF-02 authenticated may execute guarded RPC');

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values (md5('cf-owner')::uuid, 'authenticated', 'authenticated', 'cf-owner@example.test', '{}', '{}'),
  (md5('cf-reader')::uuid, 'authenticated', 'authenticated', 'cf-reader@example.test', '{}', '{}'),
  (md5('cf-stranger')::uuid, 'authenticated', 'authenticated', 'cf-stranger@example.test', '{}', '{}');
insert into public.profiles (id, full_name, status)
values (md5('cf-owner')::uuid, 'CF Owner', 'active'),
  (md5('cf-reader')::uuid, 'CF Reader', 'active'),
  (md5('cf-stranger')::uuid, 'CF Stranger', 'active');
insert into public.businesses (id, name, status)
values (md5('cf-business-a')::uuid, 'CF A', 'active'),
  (md5('cf-business-b')::uuid, 'CF B', 'active');
insert into public.branches (id, business_id, name, status)
values (md5('cf-branch-a1')::uuid, md5('cf-business-a')::uuid, 'CF A1', 'active'),
  (md5('cf-branch-a2')::uuid, md5('cf-business-a')::uuid, 'CF A2', 'active'),
  (md5('cf-branch-b1')::uuid, md5('cf-business-b')::uuid, 'CF B1', 'active');
insert into public.roles (id, business_id, name)
values (md5('cf-report-role')::uuid, md5('cf-business-a')::uuid, 'CF custom report');
insert into public.role_permissions (role_id, permission_id)
select md5('cf-report-role')::uuid, id from public.permissions where key='reports.cash';
insert into public.business_members (business_id, branch_id, profile_id, role_id, status)
select md5('cf-business-a')::uuid, null, md5('cf-owner')::uuid, id, 'active'
from public.roles where name='owner' and business_id is null and is_system_role
  and deleted_at is null;
insert into public.business_members (business_id, branch_id, profile_id, role_id, status)
values (md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  md5('cf-reader')::uuid, md5('cf-report-role')::uuid, 'active');

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok($$select * from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')$$,
  '42501', 'Authentication required', 'CF-03 missing auth rejected');
select set_config('request.jwt.claim.sub', md5('cf-stranger')::uuid::text, true);
select throws_ok($$select * from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')$$,
  '42501', 'Cash report is not authorized for this branch',
  'CF-04 unrelated profile denied');
select set_config('request.jwt.claim.sub', md5('cf-reader')::uuid::text, true);
select throws_ok($$select * from public.get_branch_cash_flow_report_summary(
  md5('cf-business-b')::uuid, md5('cf-branch-b1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')$$,
  '42501', 'Cash report is not authorized for this branch',
  'CF-05 cross-business denied');
select throws_ok($$select * from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a2')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')$$,
  '42501', 'Cash report is not authorized for this branch',
  'CF-06 cross-branch denied');
select is((select total_cash_inflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')),
  '0', 'CF-07 empty period returns zero');
select throws_ok($$select * from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-02T00:00:00Z', '2026-09-01T00:00:00Z')$$,
  '22023', 'to timestamp must be greater than from timestamp',
  'CF-08 invalid period denied');
reset role;

insert into public.cash_registers (id, business_id, branch_id, name, status)
values (md5('cf-register-a1')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, 'CF register A1', 'active'),
  (md5('cf-register-a2')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a2')::uuid, 'CF register A2', 'active'),
  (md5('cf-register-b1')::uuid, md5('cf-business-b')::uuid,
  md5('cf-branch-b1')::uuid, 'CF register B1', 'active');
insert into public.cash_sessions (id, business_id, branch_id, cash_register_id,
  opened_by, opening_amount, status)
values (md5('cf-session-a1')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, md5('cf-register-a1')::uuid,
  md5('cf-owner')::uuid, 500, 'open'),
  (md5('cf-session-a2')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a2')::uuid, md5('cf-register-a2')::uuid,
  md5('cf-owner')::uuid, 900, 'open'),
  (md5('cf-session-b1')::uuid, md5('cf-business-b')::uuid,
  md5('cf-branch-b1')::uuid, md5('cf-register-b1')::uuid,
  md5('cf-owner')::uuid, 800, 'open');

insert into public.sales (id, business_id, branch_id, total, payment_method,
  status, created_at, voided_at, voided_by, deleted_at)
values (md5('cf-sale-cash')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, 100, 'cash', 'completed',
  '2026-09-01T10:00:00Z', null, null, null),
  (md5('cf-sale-card')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, 50, 'card', 'completed',
  '2026-09-01T11:00:00Z', null, null, null),
  (md5('cf-sale-void')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, 25, 'cash', 'completed',
  '2026-09-01T12:00:00Z', '2026-09-01T13:00:00Z', md5('cf-owner')::uuid, null),
  (md5('cf-sale-a2')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a2')::uuid, 77, 'cash', 'completed',
  '2026-09-01T10:00:00Z', null, null, null),
  (md5('cf-sale-b1')::uuid, md5('cf-business-b')::uuid,
  md5('cf-branch-b1')::uuid, 88, 'cash', 'completed',
  '2026-09-01T10:00:00Z', null, null, null),
  (md5('cf-sale-upper')::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, 11, 'cash', 'completed',
  '2026-09-02T00:00:00Z', null, null, null);
insert into public.sale_payments (id, business_id, sale_id, payment_method,
  amount, status, paid_at, created_at)
select md5(name || '-payment')::uuid, business_id, id, payment_method,
  total, 'completed', created_at, created_at
from (select id, business_id, payment_method, total, created_at,
  case id when md5('cf-sale-cash')::uuid then 'cf-sale-cash'
    when md5('cf-sale-card')::uuid then 'cf-sale-card'
    when md5('cf-sale-void')::uuid then 'cf-sale-void'
    when md5('cf-sale-a2')::uuid then 'cf-sale-a2'
    when md5('cf-sale-b1')::uuid then 'cf-sale-b1'
    else 'cf-sale-upper' end as name
  from public.sales where id in (
    md5('cf-sale-cash')::uuid, md5('cf-sale-card')::uuid,
    md5('cf-sale-void')::uuid, md5('cf-sale-a2')::uuid,
    md5('cf-sale-b1')::uuid, md5('cf-sale-upper')::uuid)) fixtures;

insert into public.cash_movements (id, business_id, branch_id,
  cash_register_id, cash_session_id, direction, category, amount, currency,
  source_type, occurred_at, created_by, idempotency_key)
select md5(name)::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, md5('cf-register-a1')::uuid,
  md5('cf-session-a1')::uuid, direction, category, amount, 'COP', 'manual',
  occurred_at::timestamptz, md5('cf-owner')::uuid, name
from (values
  ('cf-owner-in', 'inflow', 'owner_contribution', 30.00, '2026-09-01T09:00:00Z'),
  ('cf-supplier', 'outflow', 'supplier_purchase', 40.00, '2026-09-01T00:00:00Z'),
  ('cf-payroll', 'outflow', 'payroll', 10.00, '2026-09-01T10:00:00Z'),
  ('cf-utilities', 'outflow', 'utilities', 5.00, '2026-09-01T11:00:00Z'),
  ('cf-owner-out', 'outflow', 'owner_withdrawal', 7.00, '2026-09-01T12:00:00Z'),
  ('cf-other-out', 'outflow', 'other', 3.00, '2026-09-01T13:00:00Z'),
  ('cf-upper-out', 'outflow', 'other', 12.00, '2026-09-02T00:00:00Z'),
  ('cf-before-out', 'outflow', 'other', 15.00, '2026-08-31T23:59:59Z')
) as rows(name, direction, category, amount, occurred_at);

-- Every remaining C4D1 operating category is covered independently, with a
-- one-cent amount so the report must preserve exact minor units.
insert into public.cash_movements (id, business_id, branch_id,
  cash_register_id, cash_session_id, direction, category, amount, currency,
  source_type, occurred_at, created_by, idempotency_key)
select md5('cf-operating-' || category)::uuid, md5('cf-business-a')::uuid,
  md5('cf-branch-a1')::uuid, md5('cf-register-a1')::uuid,
  md5('cf-session-a1')::uuid, 'outflow', category, 0.01, 'COP', 'manual',
  '2026-09-03T10:00:00Z', md5('cf-owner')::uuid,
  'cf-operating-' || category
from unnest(array['rent','maintenance','repairs','transport',
  'infrastructure','cleaning','office_supplies']) as category;

set local role authenticated;
select set_config('request.jwt.claim.sub', md5('cf-reader')::uuid::text, true);

select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '10000',
  'CF-09 cash sale included once; card, void and other scopes excluded');
select is((select additional_cash_inflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '3000',
  'CF-10 manual inflow separate from sale');
select is((select total_cash_inflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '13000',
  'CF-11 total inflows do not double count cash sale');
select is((select total_cash_outflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '6500',
  'CF-12 all valid outflow categories total exactly');
select is((select net_cash_flow_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '6500',
  'CF-13 net cash flow exact');
select is((select inventory_acquisition_outflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '4000',
  'CF-14 supplier purchase is inventory acquisition');
select is((select operating_expenses_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '1500',
  'CF-15 supplier purchase and owner withdrawal are not operating expense');
select is((select owner_withdrawals_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '700',
  'CF-16 owner withdrawal separate');
select is((select other_outflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '300',
  'CF-17 other outflows separate');
select is((select outflow_by_category #>> '{supplier_purchase,total_cents}'
  from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '4000',
  'CF-18 category breakdown exact');
select is((select outflow_by_category #>> '{supplier_purchase,count}'
  from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '1',
  'CF-19 category count exact');
select is((select total_cash_outflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-01T00:00:01Z')), '4000',
  'CF-20 lower bound included');
select is((select total_cash_inflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-01T00:00:01Z')), '0',
  'CF-21 upper bound excludes later transactions');
select is((select total_cash_outflows_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-02T00:00:00Z', '2026-09-03T00:00:00Z')), '1200',
  'CF-22 exact upper-bound row belongs to following period');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-02T00:00:00Z', '2026-09-03T00:00:00Z')), '1100',
  'CF-23 cash payment paid at upper bound belongs to following period');
select is((select net_cash_flow_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-01T00:00:00Z', '2026-09-02T00:00:00Z')), '6500',
  'CF-24 opening amount does not enter period flow');
select is((select cash_sales_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-08-31T00:00:00Z', '2026-09-01T00:00:00Z')), '0',
  'CF-25 cash sale not leaked into previous period');

select is((select operating_expenses_cents from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '7',
  'CF-26 all seven additional operating categories preserve one cent each');
select is((select outflow_by_category #>> '{rent,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-27 rent is operating');
select is((select outflow_by_category #>> '{maintenance,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-28 maintenance is operating');
select is((select outflow_by_category #>> '{repairs,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-29 repairs are operating');
select is((select outflow_by_category #>> '{transport,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-30 transport is operating');
select is((select outflow_by_category #>> '{infrastructure,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-31 infrastructure is operating');
select is((select outflow_by_category #>> '{cleaning,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-32 cleaning is operating');
select is((select outflow_by_category #>> '{office_supplies,total_cents}' from public.get_branch_cash_flow_report_summary(
  md5('cf-business-a')::uuid, md5('cf-branch-a1')::uuid,
  '2026-09-03T00:00:00Z', '2026-09-04T00:00:00Z')), '1', 'CF-33 office supplies are operating');

select * from finish();
rollback;
