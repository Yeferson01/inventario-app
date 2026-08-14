-- R1.1b - Repair the administrative business runtime setup contract.
--
-- The historical function attempted to infer an owner from optional
-- businesses.owner_id / businesses.created_by columns. Neither column exists
-- in the current schema. Runtime creation now requires an existing active
-- membership with the seeded settings.business capability and an explicit
-- branch id. This RPC never creates or upgrades memberships.

begin;

drop function if exists public.ensure_business_runtime_setup(
  uuid,
  text,
  text,
  text,
  jsonb
);

create or replace function public.ensure_business_runtime_setup(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid default null,
  p_metadata jsonb default '{}'::jsonb,
  p_branch_name text default null,
  p_default_cash_register_name text default 'Caja Principal',
  p_receipt_prefix text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_membership_id uuid;

  v_branch public.branches%rowtype;
  v_branch_created boolean := false;
  v_branch_name text;

  v_cash_register public.cash_registers%rowtype;
  v_cash_register_created boolean := false;
  v_cash_register_name text;

  v_receipt_sequence public.receipt_sequences%rowtype;
  v_receipt_sequence_created boolean := false;
  v_receipt_prefix text;

  v_metadata jsonb;
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

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  v_branch_name := nullif(btrim(coalesce(p_branch_name, '')), '');
  v_cash_register_name := nullif(
    btrim(coalesce(p_default_cash_register_name, '')),
    ''
  );

  if v_cash_register_name is null then
    v_cash_register_name := 'Caja Principal';
  end if;

  v_receipt_prefix := upper(
    nullif(btrim(coalesce(p_receipt_prefix, '')), '')
  );

  if v_receipt_prefix is null then
    v_receipt_prefix := 'POS';
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  )
  then
    raise exception 'Business does not exist or is not active';
  end if;

  if not private.is_business_member(p_business_id) then
    raise exception 'Active business membership is required for runtime setup';
  end if;

  if p_app_device_id is not null
     and not exists (
       select 1
       from public.app_devices ad
       where ad.id = p_app_device_id
         and ad.business_id = p_business_id
         and ad.profile_id = v_profile_id
         and ad.status = 'active'
         and ad.deleted_at is null
     )
  then
    raise exception 'app_device is not active for this user and business';
  end if;

  -- Serialize setup for a business/branch pair. This closes the select/insert
  -- race while retaining the existing unique indexes as the final guard.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_business_id::text || ':' || p_branch_id::text,
      0
    )
  );

  select br.*
  into v_branch
  from public.branches br
  where br.id = p_branch_id;

  if v_branch.id is not null then
    if v_branch.business_id <> p_business_id then
      raise exception 'Branch does not belong to this business';
    end if;

    if v_branch.deleted_at is not null
       or coalesce(v_branch.status, 'active') <> 'active'
    then
      raise exception 'Branch is inactive or deleted';
    end if;

    if not private.has_branch_access(p_business_id, p_branch_id) then
      raise exception 'Active membership does not grant access to this branch';
    end if;

    if not private.has_branch_permission(
      p_business_id,
      p_branch_id,
      'settings.business'
    )
    then
      raise exception 'Insufficient permission to initialize business runtime';
    end if;
  else
    if v_branch_name is null then
      raise exception 'branch_name is required to create the explicit branch_id';
    end if;

    if not exists (
      select 1
      from public.business_members bm
      join public.roles r
        on r.id = bm.role_id
      join public.role_permissions rp
        on rp.role_id = r.id
      join public.permissions p
        on p.id = rp.permission_id
      where bm.business_id = p_business_id
        and bm.profile_id = v_profile_id
        and bm.branch_id is null
        and bm.status = 'active'
        and bm.deleted_at is null
        and r.deleted_at is null
        and (r.business_id is null or r.business_id = p_business_id)
        and p.key = 'settings.business'
    )
    then
      raise exception 'Insufficient permission to initialize business runtime';
    end if;

    if exists (
      select 1
      from public.branches br
      where br.business_id = p_business_id
        and br.deleted_at is null
        and lower(br.name) = lower(v_branch_name)
    )
    then
      raise exception 'An equivalent branch already exists; use its branch_id';
    end if;

    insert into public.branches (
      id,
      business_id,
      name,
      status,
      sync_status,
      version,
      created_by,
      updated_by
    )
    values (
      p_branch_id,
      p_business_id,
      v_branch_name,
      'active',
      'synced',
      1,
      v_profile_id,
      v_profile_id
    )
    returning *
    into v_branch;

    v_branch_created := true;
  end if;

  select bm.id
  into v_membership_id
  from public.business_members bm
  join public.roles r
    on r.id = bm.role_id
  join public.role_permissions rp
    on rp.role_id = r.id
  join public.permissions p
    on p.id = rp.permission_id
  where bm.business_id = p_business_id
    and bm.profile_id = v_profile_id
    and bm.status = 'active'
    and bm.deleted_at is null
    and r.deleted_at is null
    and (r.business_id is null or r.business_id = p_business_id)
    and p.key = 'settings.business'
    and (
      bm.branch_id is null
      or bm.branch_id = v_branch.id
    )
  order by bm.branch_id nulls first, bm.created_at, bm.id
  limit 1;

  -- Reuse the same canonical cash-register rule as resolve_business_runtime:
  -- prefer Caja Principal, then the oldest active register in the branch.
  select cr.*
  into v_cash_register
  from public.cash_registers cr
  where cr.business_id = p_business_id
    and cr.branch_id = v_branch.id
    and cr.deleted_at is null
    and coalesce(cr.status, 'active') = 'active'
  order by
    case when lower(cr.name) = lower('Caja Principal') then 0 else 1 end,
    cr.created_at,
    cr.id
  limit 1;

  if v_cash_register.id is null then
    if exists (
      select 1
      from public.cash_registers cr
      where cr.business_id = p_business_id
        and cr.branch_id = v_branch.id
        and cr.deleted_at is null
        and lower(cr.name) = lower(v_cash_register_name)
    )
    then
      raise exception 'Canonical cash register exists but is not active';
    end if;

    insert into public.cash_registers (
      business_id,
      branch_id,
      name,
      status,
      sync_status,
      version,
      created_by,
      updated_by
    )
    values (
      p_business_id,
      v_branch.id,
      v_cash_register_name,
      'active',
      'synced',
      1,
      v_profile_id,
      v_profile_id
    )
    returning *
    into v_cash_register;

    v_cash_register_created := true;
  end if;

  select rs.*
  into v_receipt_sequence
  from public.receipt_sequences rs
  where rs.business_id = p_business_id
    and rs.branch_id = v_branch.id
    and rs.deleted_at is null
    and coalesce(rs.status, 'active') = 'active'
  order by rs.created_at, rs.id
  limit 1;

  if v_receipt_sequence.id is null then
    if exists (
      select 1
      from public.receipt_sequences rs
      where rs.business_id = p_business_id
        and rs.branch_id = v_branch.id
        and rs.deleted_at is null
        and lower(rs.prefix) = lower(v_receipt_prefix)
    )
    then
      raise exception 'Equivalent receipt sequence exists but is not active';
    end if;

    insert into public.receipt_sequences (
      business_id,
      branch_id,
      name,
      prefix,
      current_number,
      padding,
      status,
      sync_status,
      version,
      metadata,
      created_by,
      updated_by
    )
    values (
      p_business_id,
      v_branch.id,
      'Recibos ' || v_branch.name,
      v_receipt_prefix,
      0,
      6,
      'active',
      'synced',
      1,
      v_metadata || jsonb_build_object(
        'created_via', 'public.ensure_business_runtime_setup',
        'runtime_role', 'default_receipt_sequence',
        'phase', 'R1.1b'
      ),
      v_profile_id,
      v_profile_id
    )
    returning *
    into v_receipt_sequence;

    v_receipt_sequence_created := true;
  end if;

  return jsonb_build_object(
    'business_id', p_business_id,
    'profile_id', v_profile_id,
    'membership_id', v_membership_id,
    'owner_membership_id', v_membership_id,
    'owner_membership_created', false,
    'app_device_id', p_app_device_id,
    'required_permission', 'settings.business',
    'branch_id', v_branch.id,
    'branch_name', v_branch.name,
    'branch_created', v_branch_created,
    'cash_register_id', v_cash_register.id,
    'cash_register_name', v_cash_register.name,
    'cash_register_created', v_cash_register_created,
    'receipt_sequence_id', v_receipt_sequence.id,
    'receipt_prefix', v_receipt_sequence.prefix,
    'receipt_sequence_created', v_receipt_sequence_created,
    'runtime_ready',
      v_branch.id is not null
      and v_cash_register.id is not null
      and v_receipt_sequence.id is not null,
    'created_anything',
      v_branch_created
      or v_cash_register_created
      or v_receipt_sequence_created
  );
end;
$$;

revoke all on function public.ensure_business_runtime_setup(
  uuid,
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from public;

revoke all on function public.ensure_business_runtime_setup(
  uuid,
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) from anon;

grant execute on function public.ensure_business_runtime_setup(
  uuid,
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) to authenticated, service_role;

comment on function public.ensure_business_runtime_setup(
  uuid,
  uuid,
  uuid,
  jsonb,
  text,
  text,
  text
) is
'Idempotently creates missing runtime for an explicit branch. Requires auth.uid(), active membership, and settings.business; never creates memberships.';

commit;
