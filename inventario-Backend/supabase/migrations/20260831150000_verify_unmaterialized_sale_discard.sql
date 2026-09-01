begin;

create or replace function public.verify_unmaterialized_sale_discard(
  p_business_id uuid,
  p_branch_id uuid,
  p_sale_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_sale_exists boolean;
  v_items_exist boolean;
  v_payments_exist boolean;
  v_movements_exist boolean;
  v_expected_conflict_exists boolean;
  v_conflict_reasons jsonb;
begin
  if v_profile_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_business_id is null or p_branch_id is null or p_sale_id is null then
    raise exception using
      errcode = '22023',
      message = 'business_id, branch_id and sale_id are required';
  end if;

  if not exists (
    select 1
    from public.businesses business
    join public.branches branch
      on branch.business_id = business.id
    where business.id = p_business_id
      and branch.id = p_branch_id
      and business.deleted_at is null
      and branch.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
      and coalesce(branch.status, 'active') = 'active'
  ) or not private.has_branch_access(p_business_id, p_branch_id) then
    raise exception using
      errcode = '42501',
      message = 'Operational context is not available';
  end if;

  select exists (
    select 1
    from public.sales sale
    where sale.id = p_sale_id
      and sale.business_id = p_business_id
      and sale.branch_id = p_branch_id
  ) into v_sale_exists;

  select exists (
    select 1
    from public.sale_items item
    where item.sale_id = p_sale_id
      and item.business_id = p_business_id
  ) into v_items_exist;

  select exists (
    select 1
    from public.sale_payments payment
    where payment.sale_id = p_sale_id
      and payment.business_id = p_business_id
  ) into v_payments_exist;

  select exists (
    select 1
    from public.inventory_movements movement
    where movement.business_id = p_business_id
      and movement.branch_id = p_branch_id
      and movement.source_type = 'sale'
      and movement.source_id = p_sale_id
  ) into v_movements_exist;

  select
    exists (
      select 1
      from public.sync_conflicts conflict
      where conflict.business_id = p_business_id
        and conflict.branch_id = p_branch_id
        and conflict.profile_id = v_profile_id
        and conflict.entity_table = 'sales'
        and conflict.entity_id = p_sale_id
        and conflict.deleted_at is null
        and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
    ),
    coalesce(
      (
        select jsonb_agg(distinct conflict.metadata ->> 'reason')
        from public.sync_conflicts conflict
        where conflict.business_id = p_business_id
          and conflict.branch_id = p_branch_id
          and conflict.profile_id = v_profile_id
          and conflict.entity_table = 'sales'
          and conflict.entity_id = p_sale_id
          and conflict.deleted_at is null
          and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
          and nullif(conflict.metadata ->> 'reason', '') is not null
      ),
      '[]'::jsonb
    )
  into v_expected_conflict_exists, v_conflict_reasons;

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'sale_id', p_sale_id,
    'safe_to_discard',
      not v_sale_exists
      and not v_items_exist
      and not v_payments_exist
      and not v_movements_exist
      and v_expected_conflict_exists,
    'sale_exists', v_sale_exists,
    'items_exist', v_items_exist,
    'payments_exist', v_payments_exist,
    'movements_exist', v_movements_exist,
    'expected_conflict_exists', v_expected_conflict_exists,
    'conflict_reasons', v_conflict_reasons
  );
end;
$$;

comment on function public.verify_unmaterialized_sale_discard(uuid, uuid, uuid)
is 'Returns tenant-scoped, read-only evidence required before discarding a rejected local Sale that was never materialized remotely.';

revoke all on function public.verify_unmaterialized_sale_discard(uuid, uuid, uuid)
from public, anon, authenticated;
grant execute on function public.verify_unmaterialized_sale_discard(uuid, uuid, uuid)
to authenticated, service_role;

commit;
