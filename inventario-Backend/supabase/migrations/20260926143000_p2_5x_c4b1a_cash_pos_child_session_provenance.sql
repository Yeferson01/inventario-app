begin;

-- Preserve the existing, scoped/keyset implementation and enrich only the
-- two child datasets. The base function remains private and unexecutable by
-- API roles; the public bootstrap RPC retains its single existing signature.
alter function private.pull_operational_bootstrap_dataset_page(
  text, uuid, uuid, timestamptz, uuid, integer, uuid[]
) rename to pull_operational_bootstrap_dataset_page_base;

create function private.pull_operational_bootstrap_dataset_page(
  p_dataset text,
  p_business_id uuid,
  p_branch_id uuid,
  p_snapshot_at timestamptz,
  p_after_id uuid,
  p_limit integer,
  p_cash_session_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_page jsonb;
  v_rows jsonb;
begin
  v_page := private.pull_operational_bootstrap_dataset_page_base(
    p_dataset, p_business_id, p_branch_id, p_snapshot_at,
    p_after_id, p_limit, p_cash_session_ids);
  if p_dataset not in ('session_sale_items', 'session_sale_payments') then
    return v_page;
  end if;

  -- Recheck the parent sale's tenant, branch and snapshot session window.
  -- Never trust duplicated scope supplied by the child/client. In the current
  -- session-scoped dataset the base query itself uses an inner join, so a
  -- missing remote parent cannot become a cross-tenant orphan disclosure.
  select coalesce(jsonb_agg(
      child.value || jsonb_build_object(
        '_parent_sale_scope_status',
          case
            when sale.id is null then 'unresolved'
            when sale.cash_session_id is null then 'resolved_no_session'
            when session.id is null then 'unresolved'
            else 'resolved_session'
          end,
        '_parent_sale_business_id', sale.business_id,
        '_parent_sale_branch_id', sale.branch_id,
        '_parent_sale_cash_session_id', sale.cash_session_id,
        '_parent_sale_cash_register_id', session.cash_register_id
      ) order by child.ordinality), '[]'::jsonb)
  into v_rows
  from jsonb_array_elements(v_page -> 'rows')
       with ordinality as child(value, ordinality)
  left join public.sales sale
    on sale.id = (child.value ->> 'sale_id')::uuid
   and sale.business_id = p_business_id
   and sale.branch_id = p_branch_id
   and sale.cash_session_id = any(coalesce(p_cash_session_ids, array[]::uuid[]))
  left join public.cash_sessions session
    on session.id = sale.cash_session_id
   and session.business_id = p_business_id
   and session.branch_id = p_branch_id;

  return jsonb_set(v_page, '{rows}', v_rows);
end;
$$;

revoke all on function private.pull_operational_bootstrap_dataset_page_base(
  text, uuid, uuid, timestamptz, uuid, integer, uuid[]
) from public, anon, authenticated, service_role;
revoke all on function private.pull_operational_bootstrap_dataset_page(
  text, uuid, uuid, timestamptz, uuid, integer, uuid[]
) from public, anon, authenticated, service_role;

commit;
