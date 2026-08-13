-- R1.1 - Secure discovery and read-only runtime resolution contracts.

begin;

create or replace function public.list_authorized_operational_contexts()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_contexts jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  with authorized_branches as (
    select distinct
      b.id as business_id,
      b.name as business_name,
      b.status as business_status,
      b.updated_at as business_updated_at,
      br.id as branch_id,
      br.name as branch_name,
      br.status as branch_status,
      br.updated_at as branch_updated_at
    from public.business_members bm
    join public.businesses b
      on b.id = bm.business_id
    join public.branches br
      on br.business_id = bm.business_id
     and (
       bm.branch_id is null
       or bm.branch_id = br.id
     )
    where bm.profile_id = v_profile_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
      and br.deleted_at is null
      and coalesce(br.status, 'active') = 'active'
  ),
  context_rows as (
    select
      ab.*,
      (
        select coalesce(
          jsonb_agg(m.membership_id order by m.created_at, m.membership_id),
          '[]'::jsonb
        )
        from (
          select bm.id as membership_id, bm.created_at
          from public.business_members bm
          where bm.profile_id = v_profile_id
            and bm.business_id = ab.business_id
            and bm.status = 'active'
            and bm.deleted_at is null
            and (
              bm.branch_id is null
              or bm.branch_id = ab.branch_id
            )
        ) m
      ) as membership_ids,
      (
        select max(bm.updated_at)
        from public.business_members bm
        where bm.profile_id = v_profile_id
          and bm.business_id = ab.business_id
          and bm.status = 'active'
          and bm.deleted_at is null
          and (
            bm.branch_id is null
            or bm.branch_id = ab.branch_id
          )
      ) as memberships_updated_at,
      (
        select coalesce(
          jsonb_agg(role_rows.role_payload order by role_rows.role_name, role_rows.role_id),
          '[]'::jsonb
        )
        from (
          select
            r.id as role_id,
            r.name as role_name,
            jsonb_build_object(
              'role_id', r.id,
              'role_name', r.name,
              'is_system_role', r.is_system_role,
              'membership_ids', jsonb_agg(
                bm.id
                order by bm.created_at, bm.id
              )
            ) as role_payload
          from public.business_members bm
          join public.roles r
            on r.id = bm.role_id
           and r.deleted_at is null
           and (
             r.business_id is null
             or r.business_id = bm.business_id
           )
          where bm.profile_id = v_profile_id
            and bm.business_id = ab.business_id
            and bm.status = 'active'
            and bm.deleted_at is null
            and (
              bm.branch_id is null
              or bm.branch_id = ab.branch_id
            )
          group by r.id, r.name, r.is_system_role
        ) role_rows
      ) as effective_roles,
      (
        select coalesce(
          jsonb_agg(permission_rows.permission_key order by permission_rows.permission_key),
          '[]'::jsonb
        )
        from (
          select distinct p.key as permission_key
          from public.business_members bm
          join public.roles r
            on r.id = bm.role_id
           and r.deleted_at is null
           and (
             r.business_id is null
             or r.business_id = bm.business_id
           )
          join public.role_permissions rp
            on rp.role_id = r.id
          join public.permissions p
            on p.id = rp.permission_id
          where bm.profile_id = v_profile_id
            and bm.business_id = ab.business_id
            and bm.status = 'active'
            and bm.deleted_at is null
            and (
              bm.branch_id is null
              or bm.branch_id = ab.branch_id
            )
        ) permission_rows
      ) as effective_permissions
    from authorized_branches ab
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'profile_id', v_profile_id,
        'business_id', cr.business_id,
        'business_name', cr.business_name,
        'business_status', cr.business_status,
        'business_updated_at', cr.business_updated_at,
        'branch_id', cr.branch_id,
        'branch_name', cr.branch_name,
        'branch_status', cr.branch_status,
        'branch_updated_at', cr.branch_updated_at,
        'membership_ids', cr.membership_ids,
        'memberships_updated_at', cr.memberships_updated_at,
        'effective_roles', cr.effective_roles,
        'effective_permissions', cr.effective_permissions
      )
      order by cr.business_name, cr.business_id, cr.branch_name, cr.branch_id
    ),
    '[]'::jsonb
  )
  into v_contexts
  from context_rows cr;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'contexts', v_contexts,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_authorized_operational_contexts() from public;
revoke all on function public.list_authorized_operational_contexts() from anon;
grant execute on function public.list_authorized_operational_contexts()
to authenticated, service_role;

comment on function public.list_authorized_operational_contexts()
is 'Lists concrete active business/branch contexts authorized for auth.uid(), with unioned effective permissions and applicable memberships.';

create or replace function public.resolve_business_runtime(
  p_business_id uuid,
  p_branch_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_business public.businesses%rowtype;
  v_branch public.branches%rowtype;
  v_cash_register public.cash_registers%rowtype;
  v_receipt_sequence public.receipt_sequences%rowtype;
  v_cash_session public.cash_sessions%rowtype;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if p_branch_id is null then
    raise exception 'branch_id is required';
  end if;

  select b.*
  into v_business
  from public.businesses b
  where b.id = p_business_id
    and b.deleted_at is null
    and coalesce(b.status, 'active') = 'active';

  if v_business.id is null then
    raise exception 'Business does not exist or is not active';
  end if;

  select br.*
  into v_branch
  from public.branches br
  where br.id = p_branch_id
    and br.business_id = p_business_id
    and br.deleted_at is null
    and coalesce(br.status, 'active') = 'active';

  if v_branch.id is null then
    raise exception 'Branch does not exist or is not active for this business';
  end if;

  if not exists (
    select 1
    from public.business_members bm
    where bm.profile_id = v_profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (
        bm.branch_id is null
        or bm.branch_id = p_branch_id
      )
  )
  then
    raise exception 'No active membership grants access to this business and branch';
  end if;

  -- The existing setup contract creates "Caja Principal". Prefer that active
  -- register inside the explicitly requested branch, with a deterministic
  -- fallback for businesses that predate the setup RPC.
  select cr.*
  into v_cash_register
  from public.cash_registers cr
  where cr.business_id = p_business_id
    and cr.branch_id = p_branch_id
    and cr.deleted_at is null
    and coalesce(cr.status, 'active') = 'active'
  order by
    case when lower(cr.name) = lower('Caja Principal') then 0 else 1 end,
    cr.created_at,
    cr.id
  limit 1;

  select rs.*
  into v_receipt_sequence
  from public.receipt_sequences rs
  where rs.business_id = p_business_id
    and rs.branch_id = p_branch_id
    and rs.deleted_at is null
    and coalesce(rs.status, 'active') = 'active'
  order by rs.created_at, rs.id
  limit 1;

  if v_cash_register.id is not null then
    select cs.*
    into v_cash_session
    from public.cash_sessions cs
    where cs.business_id = p_business_id
      and cs.branch_id = p_branch_id
      and cs.cash_register_id = v_cash_register.id
      and cs.status = 'open'
      and cs.deleted_at is null
    order by cs.opened_at desc, cs.created_at desc, cs.id
    limit 1;
  end if;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', v_business.id,
    'business_name', v_business.name,
    'branch_id', v_branch.id,
    'branch_name', v_branch.name,
    'cash_register_id', v_cash_register.id,
    'cash_register_name', v_cash_register.name,
    'receipt_sequence_id', v_receipt_sequence.id,
    'receipt_sequence_name', v_receipt_sequence.name,
    'receipt_prefix', v_receipt_sequence.prefix,
    'open_cash_session', case
      when v_cash_session.id is null then null
      else jsonb_build_object(
        'cash_session_id', v_cash_session.id,
        'cash_register_id', v_cash_session.cash_register_id,
        'status', v_cash_session.status,
        'opened_by', v_cash_session.opened_by,
        'opened_at', v_cash_session.opened_at
      )
    end,
    'runtime_ready',
      v_cash_register.id is not null
      and v_receipt_sequence.id is not null,
    'resolved_at', now()
  );
end;
$$;

revoke all on function public.resolve_business_runtime(uuid, uuid) from public;
revoke all on function public.resolve_business_runtime(uuid, uuid) from anon;
grant execute on function public.resolve_business_runtime(uuid, uuid)
to authenticated, service_role;

comment on function public.resolve_business_runtime(uuid, uuid)
is 'Resolves existing runtime for an explicitly authorized active branch. It never creates branches, registers, sequences, or sessions.';

commit;
