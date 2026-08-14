-- R1.1c - Atomic server-side onboarding for a new business tenant.
--
-- The authenticated user supplies stable client-generated business and branch
-- ids. The server derives the creator exclusively from auth.uid(), guarantees
-- that creator's minimal profile, assigns the seeded global owner role, and
-- delegates branch/runtime creation to the R1.1b setup contract.

begin;

-- Productive business creation now goes through create_business. service_role
-- keeps its table privilege and BYPASSRLS behavior for administrative work.
drop policy if exists businesses_insert_authenticated on public.businesses;
drop policy if exists authenticated_users_can_create_business on public.businesses;

create or replace function public.create_business(
  p_business_id uuid,
  p_branch_id uuid,
  p_business_name text,
  p_branch_name text,
  p_default_cash_register_name text default 'Caja Principal',
  p_receipt_prefix text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_auth_full_name text;
  v_profile public.profiles%rowtype;
  v_inserted_profile_id uuid;
  v_profile_created boolean := false;

  v_owner_role_id uuid;
  v_owner_role_count bigint;

  v_business public.businesses%rowtype;
  v_business_created boolean := false;
  v_membership public.business_members%rowtype;
  v_membership_created boolean := false;

  v_business_name text;
  v_branch_name text;
  v_cash_register_name text;
  v_metadata jsonb;

  v_setup jsonb;
  v_discovery jsonb;
  v_context jsonb;
  v_context_count bigint;
  v_runtime jsonb;
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

  v_business_name := nullif(btrim(coalesce(p_business_name, '')), '');
  v_branch_name := nullif(btrim(coalesce(p_branch_name, '')), '');
  v_cash_register_name := nullif(
    btrim(coalesce(p_default_cash_register_name, '')),
    ''
  );
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_business_name is null then
    raise exception 'business_name is required';
  end if;

  if char_length(v_business_name) > 255 then
    raise exception 'business_name exceeds 255 characters';
  end if;

  if v_branch_name is null then
    raise exception 'branch_name is required';
  end if;

  if v_cash_register_name is null then
    v_cash_register_name := 'Caja Principal';
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  -- A JWT subject alone is not enough to satisfy the profiles FK. Confirm the
  -- authenticated identity exists and is not deleted before provisioning only
  -- that user's own minimal profile.
  select left(
    coalesce(
      nullif(btrim(au.raw_user_meta_data ->> 'full_name'), ''),
      nullif(btrim(au.email), '')
    ),
    255
  )
  into v_auth_full_name
  from auth.users au
  where au.id = v_profile_id
    and au.deleted_at is null;

  if not found then
    raise exception 'Authenticated user does not exist or is deleted';
  end if;

  insert into public.profiles (
    id,
    full_name,
    status
  )
  values (
    v_profile_id,
    v_auth_full_name,
    'active'
  )
  on conflict (id) do nothing
  returning id
  into v_inserted_profile_id;

  v_profile_created := v_inserted_profile_id is not null;

  select p.*
  into v_profile
  from public.profiles p
  where p.id = v_profile_id;

  if v_profile.id is null then
    raise exception 'Unable to provision authenticated profile';
  end if;

  -- The seed has no immutable owner-role UUID. The exact global system-role
  -- identity below is therefore the current server-side contract.
  select
    count(*),
    (array_agg(r.id order by r.id))[1]
  into
    v_owner_role_count,
    v_owner_role_id
  from public.roles r
  where r.business_id is null
    and r.is_system_role = true
    and r.name = 'owner'
    and r.deleted_at is null;

  if v_owner_role_count <> 1 then
    raise exception 'Exactly one active global owner system role is required';
  end if;

  -- Serialize only callers that target the same business id. R1.1b adds its
  -- own business/branch lock for runtime creation; unique indexes remain the
  -- final guards against duplicate memberships and runtime rows.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'create_business:' || p_business_id::text,
      0
    )
  );

  select b.*
  into v_business
  from public.businesses b
  where b.id = p_business_id
  for update;

  if v_business.id is null then
    insert into public.businesses (
      id,
      name,
      status
    )
    values (
      p_business_id,
      v_business_name,
      'active'
    )
    returning *
    into v_business;

    v_business_created := true;

    insert into public.business_members (
      business_id,
      profile_id,
      branch_id,
      role_id,
      status,
      accepted_at,
      created_by,
      updated_by
    )
    values (
      v_business.id,
      v_profile_id,
      null,
      v_owner_role_id,
      'active',
      now(),
      v_profile_id,
      v_profile_id
    )
    returning *
    into v_membership;

    v_membership_created := true;
  else
    if v_business.deleted_at is not null
       or coalesce(v_business.status, 'active') <> 'active'
    then
      raise exception 'Business already exists but is inactive or deleted';
    end if;

    -- Never claim an existing or orphan business. A retry is legitimate only
    -- when this caller already owns it through the exact business-level owner
    -- membership established by this contract.
    select bm.*
    into v_membership
    from public.business_members bm
    where bm.business_id = v_business.id
      and bm.profile_id = v_profile_id
      and bm.branch_id is null
      and bm.role_id = v_owner_role_id
      and bm.status = 'active'
      and bm.deleted_at is null
    order by bm.created_at, bm.id
    limit 1;

    if v_membership.id is null then
      raise exception 'Existing business is not owned by the authenticated user';
    end if;
  end if;

  v_setup := public.ensure_business_runtime_setup(
    v_business.id,
    p_branch_id,
    null,
    v_metadata,
    v_branch_name,
    v_cash_register_name,
    p_receipt_prefix
  );

  if not coalesce((v_setup ->> 'runtime_ready')::boolean, false)
     or v_setup ->> 'branch_id' is null
     or v_setup ->> 'cash_register_id' is null
     or v_setup ->> 'receipt_sequence_id' is null
  then
    raise exception 'Business runtime setup did not produce a complete runtime';
  end if;

  v_discovery := public.list_authorized_operational_contexts();

  select count(*)
  into v_context_count
  from jsonb_array_elements(v_discovery -> 'contexts') context_row(value)
  where context_row.value ->> 'business_id' = v_business.id::text
    and context_row.value ->> 'branch_id' = p_branch_id::text;

  select context_row.value
  into v_context
  from jsonb_array_elements(v_discovery -> 'contexts') context_row(value)
  where context_row.value ->> 'business_id' = v_business.id::text
    and context_row.value ->> 'branch_id' = p_branch_id::text
  limit 1;

  if v_context_count <> 1 or v_context is null then
    raise exception 'Created business context is not uniquely discoverable';
  end if;

  v_runtime := public.resolve_business_runtime(v_business.id, p_branch_id);

  if not coalesce((v_runtime ->> 'runtime_ready')::boolean, false)
     or v_runtime ->> 'cash_register_id' <> v_setup ->> 'cash_register_id'
     or v_runtime ->> 'receipt_sequence_id' <> v_setup ->> 'receipt_sequence_id'
  then
    raise exception 'Created business runtime is not resolvable consistently';
  end if;

  return jsonb_build_object(
    'profile_id', v_profile.id,
    'profile_created', v_profile_created,
    'business_id', v_business.id,
    'business_name', v_business.name,
    'business_created', v_business_created,
    'owner_role_id', v_owner_role_id,
    'owner_membership_id', v_membership.id,
    'owner_membership_created', v_membership_created,
    'branch_id', v_setup ->> 'branch_id',
    'branch_name', v_setup ->> 'branch_name',
    'branch_created', (v_setup ->> 'branch_created')::boolean,
    'cash_register_id', v_setup ->> 'cash_register_id',
    'cash_register_name', v_setup ->> 'cash_register_name',
    'cash_register_created', (v_setup ->> 'cash_register_created')::boolean,
    'receipt_sequence_id', v_setup ->> 'receipt_sequence_id',
    'receipt_prefix', v_setup ->> 'receipt_prefix',
    'receipt_sequence_created',
      (v_setup ->> 'receipt_sequence_created')::boolean,
    'runtime_ready', true,
    'operational_context', v_context,
    'resolved_runtime', v_runtime,
    'created_anything',
      v_profile_created
      or v_business_created
      or v_membership_created
      or coalesce((v_setup ->> 'created_anything')::boolean, false)
  );
end;
$$;

revoke all on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) from public;

revoke all on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) from anon;

grant execute on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) to authenticated, service_role;

comment on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) is
'Atomically provisions auth.uid() profile, business-level owner membership, explicit initial branch, cash register, receipt sequence, and resolvable operational context.';

commit;
