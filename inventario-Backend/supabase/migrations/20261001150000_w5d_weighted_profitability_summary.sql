-- W5D: preserve UNIT historical cost and use authoritative WEIGHT line COGS.
begin;

create or replace function public.get_branch_profitability_report_summary(
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
  known_net_sales numeric,
  known_cogs numeric,
  known_gross_profit numeric,
  known_gross_margin numeric,
  unknown_cost_item_count bigint,
  unknown_cost_net_sales numeric,
  cost_coverage_complete boolean,
  authoritative_as_of timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_authoritative_as_of timestamptz := now();
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null or p_branch_id is null or p_from is null or p_to is null then
    raise exception using errcode = '22023',
      message = 'business_id, branch_id, from and to are required';
  end if;

  if p_to <= p_from then
    raise exception using errcode = '22023',
      message = 'to timestamp must be greater than from timestamp';
  end if;

  if not exists (
    select 1 from public.businesses business
    where business.id = p_business_id
      and business.status = 'active' and business.deleted_at is null
  ) or not exists (
    select 1 from public.branches branch
    where branch.id = p_branch_id and branch.business_id = p_business_id
      and branch.status = 'active' and branch.deleted_at is null
  ) or not private.has_branch_permission(p_business_id, p_branch_id, 'reports.sales')
    or not private.has_branch_permission(p_business_id, p_branch_id, 'sales.view_costs')
  then
    raise exception using errcode = '42501',
      message = 'Profitability report is not authorized for this branch';
  end if;

  return query
  with eligible_items as (
    select
      item.subtotal - item.discount_amount as net_revenue,
      case
        when item.sale_mode_snapshot = 'weight' then
          item.cogs_cents::numeric / 100
        else item.quantity * item.unit_cost_snapshot
      end as historical_cost
    from public.sales sale
    join public.sale_items item on item.sale_id = sale.id
      and item.business_id = p_business_id and item.deleted_at is null
    where sale.business_id = p_business_id
      and sale.branch_id = p_branch_id
      and sale.status = 'completed'
      and sale.deleted_at is null
      and sale.voided_at is null
      and sale.created_at >= (p_from at time zone 'UTC')
      and sale.created_at < (p_to at time zone 'UTC')
  ), item_totals as (
    select
      coalesce(sum(item.net_revenue) filter (where item.historical_cost is not null), 0::numeric) as known_revenue,
      coalesce(sum(item.historical_cost) filter (where item.historical_cost is not null), 0::numeric) as known_cost,
      count(*) filter (where item.historical_cost is null) as unknown_items,
      coalesce(sum(item.net_revenue) filter (where item.historical_cost is null), 0::numeric) as unknown_revenue
    from eligible_items item
  )
  select
    p_business_id, p_branch_id, p_from, p_to,
    totals.known_revenue, totals.known_cost,
    totals.known_revenue - totals.known_cost,
    (totals.known_revenue - totals.known_cost) / nullif(totals.known_revenue, 0),
    totals.unknown_items, totals.unknown_revenue,
    totals.unknown_items = 0,
    v_authoritative_as_of
  from item_totals totals;
end;
$$;

comment on function public.get_branch_profitability_report_summary(
  uuid, uuid, timestamptz, timestamptz
) is
'Returns completed-sale profitability from historical UNIT unit_cost_snapshot or authoritative WEIGHT cogs_cents. WEIGHT cents are converted to currency units without rounding; NULL remains unknown and zero remains known. Requires effective reports.sales and sales.view_costs permissions.';

revoke all on function public.get_branch_profitability_report_summary(
  uuid, uuid, timestamptz, timestamptz
) from public, anon;
grant execute on function public.get_branch_profitability_report_summary(
  uuid, uuid, timestamptz, timestamptz
) to authenticated, service_role;

commit;
