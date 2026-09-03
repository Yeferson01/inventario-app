begin;

create or replace function public.lookup_open_closed_cash_session_sale_conflict(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_sale_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_conflict_ids uuid[];
  v_conflict_count integer;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null
     or p_branch_id is null
     or p_app_device_id is null
     or p_sale_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'business_id, branch_id, app_device_id and sale_id are required';
  end if;

  if not exists (
    select 1
    from public.businesses business
    join public.branches branch on branch.business_id = business.id
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

  if not exists (
    select 1
    from public.app_devices device
    where device.id = p_app_device_id
      and device.business_id = p_business_id
      and device.branch_id = p_branch_id
      and device.profile_id = v_profile_id
      and device.status = 'active'
      and device.deleted_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'app_device is not active for this profile and branch';
  end if;

  select array_agg(conflict.id order by conflict.created_at, conflict.id)
  into v_conflict_ids
  from public.sync_conflicts conflict
  where conflict.business_id = p_business_id
    and conflict.branch_id = p_branch_id
    and conflict.profile_id = v_profile_id
    and conflict.entity_table = 'sales'
    and conflict.entity_id = p_sale_id
    and conflict.status = 'open'
    and conflict.deleted_at is null
    and conflict.metadata ->> 'sale_id' = p_sale_id::text
    and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
    and conflict.metadata ->> 'reason' = 'closed';

  v_conflict_count := coalesce(cardinality(v_conflict_ids), 0);

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'sale_id', p_sale_id,
    'status', case
      when v_conflict_count = 0 then 'not_found'
      when v_conflict_count = 1 then 'found'
      else 'ambiguous'
    end,
    'conflict_count', v_conflict_count,
    'conflict_id', case
      when v_conflict_count = 1 then v_conflict_ids[1]
      else null
    end
  );
end;
$$;

comment on function public.lookup_open_closed_cash_session_sale_conflict(
  uuid, uuid, uuid, uuid
)
is 'Returns only the uniquely matching open closed-session Sale conflict for an authenticated operational scope.';

revoke all on function public.lookup_open_closed_cash_session_sale_conflict(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;

grant execute on function public.lookup_open_closed_cash_session_sale_conflict(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

commit;
