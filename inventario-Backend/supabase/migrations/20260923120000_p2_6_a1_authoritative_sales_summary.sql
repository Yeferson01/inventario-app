-- P2.6A1 - Authoritative branch sales summary.
--
-- Reports are calculated directly from remote sales. This contract does not
-- read or mutate sync cursors, local projections, or report snapshots.

begin;

create or replace function public.get_branch_sales_report_summary(
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
  gross_sales numeric,
  sale_count bigint,
  average_ticket numeric,
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
  v_business_is_active boolean := false;
  v_branch_is_active boolean := false;
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_business_id is null
     or p_branch_id is null
     or p_from is null
     or p_to is null
  then
    raise exception using
      errcode = '22023',
      message = 'business_id, branch_id, from and to are required';
  end if;

  if p_to <= p_from then
    raise exception using
      errcode = '22023',
      message = 'to timestamp must be greater than from timestamp';
  end if;

  select exists (
    select 1
    from public.businesses business
    where business.id = p_business_id
      and business.status = 'active'
      and business.deleted_at is null
  )
  into v_business_is_active;

  select exists (
    select 1
    from public.branches branch
    where branch.id = p_branch_id
      and branch.business_id = p_business_id
      and branch.status = 'active'
      and branch.deleted_at is null
  )
  into v_branch_is_active;

  if not v_business_is_active
     or not v_branch_is_active
     or not private.has_branch_permission(
       p_business_id,
       p_branch_id,
       'reports.sales'
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Sales report is not authorized for this branch';
  end if;

  return query
  select
    p_business_id as business_id,
    p_branch_id as branch_id,
    p_from as period_from,
    p_to as period_to,
    coalesce(sum(sale.total), 0::numeric) as gross_sales,
    count(*) as sale_count,
    case
      when count(*) = 0 then null::numeric
      else sum(sale.total) / count(*)
    end as average_ticket,
    v_authoritative_as_of as authoritative_as_of
  from public.sales sale
  where sale.business_id = p_business_id
    and sale.branch_id = p_branch_id
    and sale.status = 'completed'
    and sale.deleted_at is null
    and sale.voided_at is null
    and sale.created_at >= (p_from at time zone 'UTC')
    and sale.created_at < (p_to at time zone 'UTC');
end;
$$;

comment on function public.get_branch_sales_report_summary(
  uuid,
  uuid,
  timestamptz,
  timestamptz
) is
'Returns one authoritative branch sales summary for the semi-open created_at period [from, to). Only completed, non-voided, non-deleted sales count. Requires effective reports.sales permission for the active business/branch context.';

revoke all on function public.get_branch_sales_report_summary(
  uuid,
  uuid,
  timestamptz,
  timestamptz
) from public, anon;

grant execute on function public.get_branch_sales_report_summary(
  uuid,
  uuid,
  timestamptz,
  timestamptz
) to authenticated, service_role;

commit;
