-- ORG-2B - Secure, online branch administration.
--
-- Branch creation is a server-authoritative organizational operation. A
-- business-wide membership with settings.branches is required, the server
-- generates the branch id, and one durable private request maps retries to the
-- same branch and runtime. Client DML and the historical branch-creation path
-- in ensure_business_runtime_setup are closed.

begin;

-- =========================================================
-- DURABLE ADMINISTRATIVE IDEMPOTENCY
-- =========================================================

create table if not exists private.business_branch_creation_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid not null
    references public.businesses(id) on delete restrict,
  idempotency_key text not null,
  actor_profile_id uuid not null
    references public.profiles(id) on delete restrict,
  branch_id uuid not null,
  request_payload jsonb not null,
  created_at timestamptz not null default now(),
  completed_at timestamptz,

  constraint business_branch_creation_requests_key_not_blank
    check (
      length(btrim(idempotency_key)) > 0
      and length(btrim(idempotency_key)) <= 200
    ),
  constraint business_branch_creation_requests_payload_object
    check (jsonb_typeof(request_payload) = 'object'),
  constraint business_branch_creation_requests_business_key_unique
    unique (business_id, idempotency_key),
  constraint business_branch_creation_requests_branch_unique
    unique (branch_id),
  constraint business_branch_creation_requests_branch_fkey
    foreign key (branch_id)
    references public.branches(id)
    on delete restrict
    deferrable initially deferred
);

comment on table private.business_branch_creation_requests is
'Durably maps one business-scoped administrative idempotency key to the canonical branch created by ORG-2B. It is not a sync outbox.';

revoke all on table private.business_branch_creation_requests
from public, anon, authenticated;

-- =========================================================
-- BUSINESS-WIDE CAPABILITY AUTHORITY
-- =========================================================

create or replace function private.has_business_wide_permission(
  p_business_id uuid,
  p_permission_key text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_business_id is not null
    and p_permission_key is not null
    and auth.uid() is not null
    and exists (
      select 1
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
      where bm.business_id = p_business_id
        and bm.profile_id = auth.uid()
        and bm.branch_id is null
        and bm.status = 'active'
        and bm.deleted_at is null
        and p.key = p_permission_key
    );
$$;

revoke all on function private.has_business_wide_permission(uuid, text)
from public, anon, authenticated;

comment on function private.has_business_wide_permission(uuid, text) is
'Checks that auth.uid() receives a capability from an active, non-deleted business-level membership. Branch-scoped memberships never satisfy it.';

-- =========================================================
-- INTERNAL RUNTIME DEFAULTS
-- =========================================================

create or replace function private.ensure_branch_runtime_defaults(
  p_business_id uuid,
  p_branch_id uuid,
  p_actor_profile_id uuid,
  p_metadata jsonb default '{}'::jsonb,
  p_cash_register_name text default 'Caja Principal',
  p_receipt_prefix text default 'POS'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch public.branches%rowtype;
  v_cash_register public.cash_registers%rowtype;
  v_cash_register_created boolean := false;
  v_receipt_sequence public.receipt_sequences%rowtype;
  v_receipt_sequence_created boolean := false;
  v_cash_register_name text;
  v_receipt_prefix text;
  v_metadata jsonb;
begin
  v_metadata := coalesce(p_metadata, '{}'::jsonb);
  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  v_cash_register_name := coalesce(
    nullif(btrim(coalesce(p_cash_register_name, '')), ''),
    'Caja Principal'
  );
  v_receipt_prefix := coalesce(
    upper(nullif(btrim(coalesce(p_receipt_prefix, '')), '')),
    'POS'
  );

  select br.*
  into v_branch
  from public.branches br
  where br.id = p_branch_id
    and br.business_id = p_business_id
    and br.status = 'active'
    and br.deleted_at is null;

  if v_branch.id is null then
    raise exception 'Branch does not exist or is not active for this business';
  end if;

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

  if v_cash_register.id is null then
    if exists (
      select 1
      from public.cash_registers cr
      where cr.business_id = p_business_id
        and cr.branch_id = p_branch_id
        and cr.deleted_at is null
        and lower(cr.name) = lower(v_cash_register_name)
    ) then
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
      p_branch_id,
      v_cash_register_name,
      'active',
      'synced',
      1,
      p_actor_profile_id,
      p_actor_profile_id
    )
    returning * into v_cash_register;

    v_cash_register_created := true;
  end if;

  select rs.*
  into v_receipt_sequence
  from public.receipt_sequences rs
  where rs.business_id = p_business_id
    and rs.branch_id = p_branch_id
    and rs.deleted_at is null
    and coalesce(rs.status, 'active') = 'active'
  order by rs.created_at, rs.id
  limit 1;

  if v_receipt_sequence.id is null then
    if exists (
      select 1
      from public.receipt_sequences rs
      where rs.business_id = p_business_id
        and rs.branch_id = p_branch_id
        and rs.deleted_at is null
        and lower(rs.prefix) = lower(v_receipt_prefix)
    ) then
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
      p_branch_id,
      'Recibos ' || v_branch.name,
      v_receipt_prefix,
      0,
      6,
      'active',
      'synced',
      1,
      v_metadata || jsonb_build_object(
        'created_via', 'private.ensure_branch_runtime_defaults',
        'runtime_role', 'default_receipt_sequence'
      ),
      p_actor_profile_id,
      p_actor_profile_id
    )
    returning * into v_receipt_sequence;

    v_receipt_sequence_created := true;
  end if;

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', v_branch.id,
    'branch_name', v_branch.name,
    'cash_register_id', v_cash_register.id,
    'cash_register_name', v_cash_register.name,
    'cash_register_created', v_cash_register_created,
    'receipt_sequence_id', v_receipt_sequence.id,
    'receipt_prefix', v_receipt_sequence.prefix,
    'receipt_sequence_created', v_receipt_sequence_created,
    'runtime_ready',
      v_cash_register.id is not null
      and v_receipt_sequence.id is not null,
    'created_anything',
      v_cash_register_created
      or v_receipt_sequence_created
  );
end;
$$;

revoke all on function private.ensure_branch_runtime_defaults(
  uuid,
  uuid,
  uuid,
  jsonb,
  text,
  text
) from public, anon, authenticated;

-- =========================================================
-- EXISTING-RUNTIME ENSURE: NO BRANCH CREATION
-- =========================================================

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
  v_runtime jsonb;
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

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  ) then
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
    raise exception using
      errcode = '42501',
      message = 'Runtime setup cannot create branches; use create_business_branch or private platform onboarding';
  end if;

  if not private.has_branch_access(p_business_id, p_branch_id) then
    raise exception 'Active membership does not grant access to this branch';
  end if;

  if not private.has_branch_permission(
    p_business_id,
    p_branch_id,
    'settings.business'
  ) then
    raise exception 'Insufficient permission to initialize business runtime';
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
     ) then
    raise exception 'app_device is not active for this user and business';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_business_id::text || ':' || p_branch_id::text,
      0
    )
  );

  select bm.id
  into v_membership_id
  from public.business_members bm
  join public.roles r on r.id = bm.role_id
  join public.role_permissions rp on rp.role_id = r.id
  join public.permissions p on p.id = rp.permission_id
  where bm.business_id = p_business_id
    and bm.profile_id = v_profile_id
    and bm.status = 'active'
    and bm.deleted_at is null
    and r.deleted_at is null
    and (r.business_id is null or r.business_id = p_business_id)
    and p.key = 'settings.business'
    and (bm.branch_id is null or bm.branch_id = p_branch_id)
  order by bm.branch_id nulls first, bm.created_at, bm.id
  limit 1;

  v_runtime := private.ensure_branch_runtime_defaults(
    p_business_id,
    p_branch_id,
    v_profile_id,
    v_metadata || jsonb_build_object(
      'source', 'public.ensure_business_runtime_setup'
    ),
    p_default_cash_register_name,
    p_receipt_prefix
  );

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
    'branch_created', false,
    'cash_register_id', v_runtime ->> 'cash_register_id',
    'cash_register_name', v_runtime ->> 'cash_register_name',
    'cash_register_created',
      (v_runtime ->> 'cash_register_created')::boolean,
    'receipt_sequence_id', v_runtime ->> 'receipt_sequence_id',
    'receipt_prefix', v_runtime ->> 'receipt_prefix',
    'receipt_sequence_created',
      (v_runtime ->> 'receipt_sequence_created')::boolean,
    'runtime_ready', (v_runtime ->> 'runtime_ready')::boolean,
    'created_anything', (v_runtime ->> 'created_anything')::boolean
  );
end;
$$;

revoke all on function public.ensure_business_runtime_setup(
  uuid, uuid, uuid, jsonb, text, text, text
) from public, anon;
grant execute on function public.ensure_business_runtime_setup(
  uuid, uuid, uuid, jsonb, text, text, text
) to authenticated, service_role;

comment on function public.ensure_business_runtime_setup(
  uuid, uuid, uuid, jsonb, text, text, text
) is
'Idempotently creates missing runtime only for an existing, explicitly authorized active branch. It cannot create branches.';

-- =========================================================
-- R1.1c ONBOARDING INSERTS ITS EXPLICIT FIRST BRANCH
-- =========================================================

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
  v_branch public.branches%rowtype;
  v_branch_created boolean := false;
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

  insert into public.profiles (id, full_name, status)
  values (v_profile_id, v_auth_full_name, 'active')
  on conflict (id) do nothing
  returning id into v_inserted_profile_id;

  v_profile_created := v_inserted_profile_id is not null;

  select p.* into v_profile
  from public.profiles p
  where p.id = v_profile_id;

  if v_profile.id is null then
    raise exception 'Unable to provision authenticated profile';
  end if;

  select count(*), (array_agg(r.id order by r.id))[1]
  into v_owner_role_count, v_owner_role_id
  from public.roles r
  where r.business_id is null
    and r.is_system_role = true
    and r.name = 'owner'
    and r.deleted_at is null;

  if v_owner_role_count <> 1 then
    raise exception 'Exactly one active global owner system role is required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'create_business:' || p_business_id::text,
      0
    )
  );

  select b.* into v_business
  from public.businesses b
  where b.id = p_business_id
  for update;

  if v_business.id is null then
    insert into public.businesses (id, name, status)
    values (p_business_id, v_business_name, 'active')
    returning * into v_business;

    v_business_created := true;

    insert into public.business_members (
      business_id, profile_id, branch_id, role_id, status,
      accepted_at, created_by, updated_by
    )
    values (
      v_business.id, v_profile_id, null, v_owner_role_id, 'active',
      now(), v_profile_id, v_profile_id
    )
    returning * into v_membership;

    v_membership_created := true;
  else
    if v_business.deleted_at is not null
       or coalesce(v_business.status, 'active') <> 'active' then
      raise exception 'Business already exists but is inactive or deleted';
    end if;

    select bm.* into v_membership
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

  select br.* into v_branch
  from public.branches br
  where br.id = p_branch_id;

  if v_branch.id is null then
    if exists (
      select 1
      from public.branches br
      where br.business_id = p_business_id
        and br.deleted_at is null
        and lower(br.name) = lower(v_branch_name)
    ) then
      raise exception 'An equivalent branch already exists; use its branch_id';
    end if;

    insert into public.branches (
      id, business_id, name, status, sync_status, version,
      created_by, updated_by
    )
    values (
      p_branch_id, p_business_id, v_branch_name, 'active', 'synced', 1,
      v_profile_id, v_profile_id
    )
    returning * into v_branch;

    v_branch_created := true;
  else
    if v_branch.business_id <> p_business_id then
      raise exception 'Branch does not belong to this business';
    end if;
    if v_branch.deleted_at is not null
       or coalesce(v_branch.status, 'active') <> 'active' then
      raise exception 'Branch is inactive or deleted';
    end if;
  end if;

  v_setup := public.ensure_business_runtime_setup(
    v_business.id,
    v_branch.id,
    null,
    v_metadata,
    null,
    v_cash_register_name,
    p_receipt_prefix
  );

  if not coalesce((v_setup ->> 'runtime_ready')::boolean, false)
     or v_setup ->> 'branch_id' is null
     or v_setup ->> 'cash_register_id' is null
     or v_setup ->> 'receipt_sequence_id' is null then
    raise exception 'Business runtime setup did not produce a complete runtime';
  end if;

  v_discovery := public.list_authorized_operational_contexts();

  select count(*) into v_context_count
  from jsonb_array_elements(v_discovery -> 'contexts') context_row(value)
  where context_row.value ->> 'business_id' = v_business.id::text
    and context_row.value ->> 'branch_id' = p_branch_id::text;

  select context_row.value into v_context
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
     or v_runtime ->> 'receipt_sequence_id' <> v_setup ->> 'receipt_sequence_id' then
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
    'branch_id', v_branch.id,
    'branch_name', v_branch.name,
    'branch_created', v_branch_created,
    'cash_register_id', v_setup ->> 'cash_register_id',
    'cash_register_name', v_setup ->> 'cash_register_name',
    'cash_register_created',
      (v_setup ->> 'cash_register_created')::boolean,
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
      or v_branch_created
      or coalesce((v_setup ->> 'created_anything')::boolean, false)
  );
end;
$$;

revoke all on function public.create_business(
  uuid, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.create_business(
  uuid, uuid, text, text, text, text, jsonb
) to service_role;

-- =========================================================
-- SECURE BRANCH CREATION
-- =========================================================

create or replace function public.create_business_branch(
  p_business_id uuid,
  p_name text,
  p_address text default null,
  p_phone text default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_name text;
  v_address text;
  v_phone text;
  v_idempotency_key text;
  v_request_payload jsonb;
  v_request private.business_branch_creation_requests%rowtype;
  v_branch public.branches%rowtype;
  v_branch_id uuid;
  v_primary_count bigint;
  v_runtime jsonb;
begin
  v_profile_id := auth.uid();
  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;
  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  v_name := nullif(btrim(coalesce(p_name, '')), '');
  v_address := nullif(btrim(coalesce(p_address, '')), '');
  v_phone := nullif(btrim(coalesce(p_phone, '')), '');
  v_idempotency_key := nullif(
    btrim(coalesce(p_idempotency_key, '')),
    ''
  );

  if v_name is null then
    raise exception 'name is required';
  end if;
  if char_length(v_name) > 255 then
    raise exception 'name exceeds 255 characters';
  end if;
  if v_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;
  if char_length(v_idempotency_key) > 200 then
    raise exception 'idempotency_key exceeds 200 characters';
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  if not private.has_business_wide_permission(
    p_business_id,
    'settings.branches'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Business-wide settings.branches permission is required';
  end if;

  v_request_payload := jsonb_build_object(
    'name', v_name,
    'address', v_address,
    'phone', v_phone
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'create_business_branch:' || p_business_id::text,
      0
    )
  );

  select request.* into v_request
  from private.business_branch_creation_requests request
  where request.business_id = p_business_id
    and request.idempotency_key = v_idempotency_key
  for update;

  if v_request.id is not null then
    if v_request.request_payload <> v_request_payload then
      raise exception using
        errcode = '23505',
        message = 'idempotency_key was already used with an incompatible branch payload';
    end if;

    if v_request.completed_at is null then
      raise exception 'Branch creation request is incomplete';
    end if;

    select br.* into v_branch
    from public.branches br
    where br.id = v_request.branch_id
      and br.business_id = p_business_id
      and br.deleted_at is null;

    if v_branch.id is null then
      raise exception 'Completed branch creation request has no canonical branch';
    end if;

    v_runtime := private.ensure_branch_runtime_defaults(
      p_business_id,
      v_branch.id,
      v_profile_id,
      jsonb_build_object('source', 'public.create_business_branch_retry'),
      'Caja Principal',
      'POS'
    );
  else
    select count(*) into v_primary_count
    from public.branches br
    where br.business_id = p_business_id
      and br.is_primary = true
      and br.status = 'active'
      and br.deleted_at is null;

    if v_primary_count <> 1 then
      raise exception using
        errcode = '23514',
        message = 'Business must have exactly one active primary branch before creating an additional branch';
    end if;

    v_branch_id := extensions.gen_random_uuid();

    insert into private.business_branch_creation_requests (
      business_id,
      idempotency_key,
      actor_profile_id,
      branch_id,
      request_payload
    )
    values (
      p_business_id,
      v_idempotency_key,
      v_profile_id,
      v_branch_id,
      v_request_payload
    )
    returning * into v_request;

    insert into public.branches (
      id,
      business_id,
      name,
      address,
      phone,
      status,
      is_primary,
      sync_status,
      version,
      created_by,
      updated_by
    )
    values (
      v_branch_id,
      p_business_id,
      v_name,
      v_address,
      v_phone,
      'active',
      false,
      'synced',
      1,
      v_profile_id,
      v_profile_id
    )
    returning * into v_branch;

    if v_branch.is_primary then
      raise exception 'Additional branch cannot become primary';
    end if;

    v_runtime := private.ensure_branch_runtime_defaults(
      p_business_id,
      v_branch.id,
      v_profile_id,
      jsonb_build_object(
        'source', 'public.create_business_branch',
        'branch_creation_request_id', v_request.id
      ),
      'Caja Principal',
      'POS'
    );

    if not coalesce((v_runtime ->> 'runtime_ready')::boolean, false) then
      raise exception 'Branch runtime setup did not produce a complete runtime';
    end if;

    update private.business_branch_creation_requests request
    set completed_at = now()
    where request.id = v_request.id
    returning * into v_request;
  end if;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', p_business_id,
    'branch_id', v_branch.id,
    'name', v_branch.name,
    'address', v_branch.address,
    'phone', v_branch.phone,
    'status', v_branch.status,
    'is_primary', v_branch.is_primary,
    'cash_register_id', v_runtime ->> 'cash_register_id',
    'cash_register_name', v_runtime ->> 'cash_register_name',
    'receipt_sequence_id', v_runtime ->> 'receipt_sequence_id',
    'receipt_prefix', v_runtime ->> 'receipt_prefix',
    'runtime_ready', (v_runtime ->> 'runtime_ready')::boolean,
    'idempotency_key', v_request.idempotency_key,
    'creation_request_id', v_request.id,
    'created_at', v_branch.created_at
  );
end;
$$;

revoke all on function public.create_business_branch(
  uuid, text, text, text, text
) from public, anon;
grant execute on function public.create_business_branch(
  uuid, text, text, text, text
) to authenticated, service_role;

comment on function public.create_business_branch(
  uuid, text, text, text, text
) is
'Creates one secondary branch and canonical runtime atomically. Requires auth.uid(), a business-wide active membership with settings.branches, and a durable business-scoped idempotency key.';

-- =========================================================
-- SECURE ADMINISTRATIVE LISTING
-- =========================================================

create or replace function public.list_business_branches(
  p_business_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_branches jsonb;
begin
  v_profile_id := auth.uid();
  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;
  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  if not private.has_business_wide_permission(
    p_business_id,
    'settings.branches'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Business-wide settings.branches permission is required';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', br.id,
        'business_id', br.business_id,
        'name', br.name,
        'address', br.address,
        'phone', br.phone,
        'status', br.status,
        'is_primary', br.is_primary,
        'cash_register_id', cr.id,
        'cash_register_name', cr.name,
        'receipt_sequence_id', rs.id,
        'receipt_prefix', rs.prefix,
        'runtime_ready', cr.id is not null and rs.id is not null,
        'created_at', br.created_at,
        'updated_at', br.updated_at
      )
      order by br.is_primary desc, lower(br.name), br.id
    ),
    '[]'::jsonb
  )
  into v_branches
  from public.branches br
  left join lateral (
    select candidate.id, candidate.name
    from public.cash_registers candidate
    where candidate.business_id = br.business_id
      and candidate.branch_id = br.id
      and candidate.deleted_at is null
      and coalesce(candidate.status, 'active') = 'active'
    order by
      case when lower(candidate.name) = lower('Caja Principal') then 0 else 1 end,
      candidate.created_at,
      candidate.id
    limit 1
  ) cr on true
  left join lateral (
    select candidate.id, candidate.prefix
    from public.receipt_sequences candidate
    where candidate.business_id = br.business_id
      and candidate.branch_id = br.id
      and candidate.deleted_at is null
      and coalesce(candidate.status, 'active') = 'active'
    order by candidate.created_at, candidate.id
    limit 1
  ) rs on true
  where br.business_id = p_business_id
    and br.deleted_at is null;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', p_business_id,
    'branches', v_branches,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_business_branches(uuid)
from public, anon;
grant execute on function public.list_business_branches(uuid)
to authenticated, service_role;

comment on function public.list_business_branches(uuid) is
'Lists non-deleted branches and minimal runtime readiness for a business-wide active member with settings.branches.';

-- =========================================================
-- CLOSE DIRECT CLIENT DML
-- =========================================================

drop policy if exists branches_insert_allowed on public.branches;
drop policy if exists branches_update_allowed on public.branches;

revoke all on table public.branches from anon, authenticated;
grant select on table public.branches to authenticated;

commit;
