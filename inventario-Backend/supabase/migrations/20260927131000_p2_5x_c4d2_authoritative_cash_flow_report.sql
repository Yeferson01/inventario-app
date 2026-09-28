-- C4D2: branch-scoped cash activity, not accrual profit or session expected cash.
-- Cash sales are sourced only from sale_payments; ordinary movements are
-- sourced only from cash_movements. Opening, closing and reconciliation
-- adjustments are intentionally outside this period flow.
begin;

create function public.get_branch_cash_flow_report_summary(
  p_business_id uuid,
  p_branch_id uuid,
  p_from timestamptz,
  p_to timestamptz
)
returns table (
  business_id uuid,
  branch_id uuid,
  period_from timestamptz,
  period_to timestamptz,
  cash_sales_cents text,
  additional_cash_inflows_cents text,
  total_cash_inflows_cents text,
  total_cash_outflows_cents text,
  net_cash_flow_cents text,
  inventory_acquisition_outflows_cents text,
  operating_expenses_cents text,
  owner_withdrawals_cents text,
  other_outflows_cents text,
  outflow_by_category jsonb,
  authoritative_as_of timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_as_of timestamptz := pg_catalog.transaction_timestamp();
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_business_id is null or p_branch_id is null or p_from is null or p_to is null
  then
    raise exception using errcode = '22023', message = 'Cash report scope and period are required';
  end if;
  if p_to <= p_from then
    raise exception using errcode = '22023', message = 'to timestamp must be greater than from timestamp';
  end if;
  if not exists (
    select 1 from public.businesses b where b.id = p_business_id
      and b.status = 'active' and b.deleted_at is null
  ) or not exists (
    select 1 from public.branches b where b.id = p_branch_id
      and b.business_id = p_business_id and b.status = 'active'
      and b.deleted_at is null
  ) or not private.has_branch_permission(p_business_id, p_branch_id, 'reports.cash')
  then
    raise exception using errcode = '42501',
      message = 'Cash report is not authorized for this branch';
  end if;

  return query
  with cash_sale_total as (
    select coalesce(sum(pg_catalog.trunc(payment.amount * 100, 0)), 0::numeric) as cents
    from public.sale_payments payment
    join public.sales sale on sale.id = payment.sale_id
      and sale.business_id = payment.business_id
    where payment.business_id = p_business_id
      and sale.branch_id = p_branch_id
      and sale.status = 'completed' and sale.deleted_at is null
      and sale.voided_at is null
      and payment.status = 'completed' and payment.deleted_at is null
      and payment.payment_method = 'cash'
      and payment.paid_at >= (p_from at time zone 'UTC')
      and payment.paid_at < (p_to at time zone 'UTC')
  ), movement_rows as (
    select movement.direction, movement.category,
      pg_catalog.trunc(movement.amount * 100, 0) as cents
    from public.cash_movements movement
    where movement.business_id = p_business_id
      and movement.branch_id = p_branch_id
      and movement.occurred_at >= p_from and movement.occurred_at < p_to
      -- The productive ordinary writer uses source_type=manual. Do not count
      -- a future sale-linked movement again alongside its sale_payment.
      and movement.source_type <> 'sale'
      -- A reversal pair is an audit correction, not an extra physical flow.
      and movement.reversed_movement_id is null
      and not exists (
        select 1 from public.cash_movements reversal
        where reversal.reversed_movement_id = movement.id
      )
  ), movement_totals as (
    select
      coalesce(sum(cents) filter (where direction = 'inflow'), 0::numeric) as inflows,
      coalesce(sum(cents) filter (where direction = 'outflow'), 0::numeric) as outflows,
      coalesce(sum(cents) filter (where direction = 'outflow'
        and category = 'supplier_purchase'), 0::numeric) as acquisition,
      coalesce(sum(cents) filter (where direction = 'outflow' and category in (
        'payroll', 'utilities', 'rent', 'maintenance', 'repairs',
        'transport', 'infrastructure', 'cleaning', 'office_supplies'
      )), 0::numeric) as operating,
      coalesce(sum(cents) filter (where direction = 'outflow'
        and category = 'owner_withdrawal'), 0::numeric) as owner,
      coalesce(sum(cents) filter (where direction = 'outflow'
        and category = 'other'), 0::numeric) as other
    from movement_rows
  ), category_totals as (
    select category, count(*) as movement_count, sum(cents) as cents
    from movement_rows where direction = 'outflow' group by category
  ), category_json as (
    select coalesce(pg_catalog.jsonb_object_agg(category,
      pg_catalog.jsonb_build_object('count', movement_count,
        'total_cents', cents::text)), '{}'::jsonb) as items
    from category_totals
  )
  select p_business_id, p_branch_id, p_from, p_to,
    sales.cents::text,
    movements.inflows::text,
    (sales.cents + movements.inflows)::text,
    movements.outflows::text,
    (sales.cents + movements.inflows - movements.outflows)::text,
    movements.acquisition::text,
    movements.operating::text,
    movements.owner::text,
    movements.other::text,
    categories.items,
    v_as_of
  from cash_sale_total sales cross join movement_totals movements
    cross join category_json categories;
end;
$$;

comment on function public.get_branch_cash_flow_report_summary(
  uuid, uuid, timestamptz, timestamptz
) is 'Authoritative branch cash activity in [from,to): completed cash sale payments plus ordinary cash movements. Opening, closing and reconciliation adjustments are excluded. Monetary results are exact integer cents encoded as text. Requires reports.cash.';

revoke all on function public.get_branch_cash_flow_report_summary(
  uuid, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.get_branch_cash_flow_report_summary(
  uuid, uuid, timestamptz, timestamptz
) to authenticated, service_role;

commit;
