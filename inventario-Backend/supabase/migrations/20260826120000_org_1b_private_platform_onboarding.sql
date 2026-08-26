-- ORG-1B - Private platform invitation and atomic tenant acceptance.
--
-- New tenant creation is authorized by a durable service-role-issued
-- invitation. The existing R1.1c create_business function remains the single
-- provisioning engine, but it is no longer a client capability.

begin;

-- =========================================================
-- FORMAL PRIMARY BRANCH IDENTITY
-- =========================================================

alter table public.branches
  add column if not exists is_primary boolean not null default false;

comment on column public.branches.is_primary is
'True for the formal primary branch of a business. At most one non-deleted primary branch may exist per business.';

-- Existing businesses prefer their active, non-deleted branch named
-- Principal. Because active branch names are already unique per business,
-- that candidate is unambiguous. Otherwise the oldest active branch wins.
with ranked_primary_candidates as (
  select
    br.id,
    row_number() over (
      partition by br.business_id
      order by
        case when lower(btrim(br.name)) = 'principal' then 0 else 1 end,
        br.created_at nulls last,
        br.id
    ) as candidate_order
  from public.branches br
  where br.deleted_at is null
    and br.status = 'active'
)
update public.branches br
set is_primary = true
from ranked_primary_candidates candidate
where candidate.id = br.id
  and candidate.candidate_order = 1;

alter table public.branches
  drop constraint if exists branches_primary_must_be_active;

alter table public.branches
  add constraint branches_primary_must_be_active
  check (
    not is_primary
    or (status = 'active' and deleted_at is null)
  );

create unique index if not exists branches_business_primary_active_unique
on public.branches (business_id)
where is_primary = true
  and deleted_at is null;

create or replace function private.assign_first_active_branch_as_primary()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'active' or new.deleted_at is not null then
    return new;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'primary_branch:' || new.business_id::text,
      0
    )
  );

  if new.is_primary then
    return new;
  end if;

  if not exists (
    select 1
    from public.branches br
    where br.business_id = new.business_id
      and br.is_primary = true
      and br.deleted_at is null
  ) then
    new.is_primary := true;
  end if;

  return new;
end;
$$;

revoke all on function private.assign_first_active_branch_as_primary()
from public, anon, authenticated, service_role;

drop trigger if exists trg_branches_assign_first_primary
on public.branches;

create trigger trg_branches_assign_first_primary
before insert on public.branches
for each row
execute function private.assign_first_active_branch_as_primary();

-- =========================================================
-- DURABLE PRIVATE PLATFORM INVITATIONS
-- =========================================================

create table if not exists private.platform_business_invitations (
  id uuid primary key default extensions.gen_random_uuid(),

  email text not null,
  normalized_email text generated always as (lower(btrim(email))) stored,

  status text not null default 'pending',
  delivery_status text not null default 'pending',

  expires_at timestamptz not null,

  business_id uuid not null,
  branch_id uuid not null,
  business_name text not null,
  branch_name text not null default 'Principal',

  idempotency_key text not null,
  issuer_authority text not null default 'service_role',

  accepted_user_id uuid references auth.users(id) on delete restrict,
  acceptance_result jsonb,

  delivery_attempted_at timestamptz,
  delivery_error_code text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,

  metadata jsonb not null default '{}'::jsonb,

  constraint platform_business_invitations_email_not_blank
    check (length(btrim(email)) > 0 and length(btrim(email)) <= 320),
  constraint platform_business_invitations_email_shape
    check (normalized_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  constraint platform_business_invitations_business_name_not_blank
    check (length(btrim(business_name)) > 0 and length(btrim(business_name)) <= 255),
  constraint platform_business_invitations_branch_name_not_blank
    check (length(btrim(branch_name)) > 0 and length(btrim(branch_name)) <= 255),
  constraint platform_business_invitations_idempotency_key_not_blank
    check (
      length(btrim(idempotency_key)) > 0
      and length(btrim(idempotency_key)) <= 200
    ),
  constraint platform_business_invitations_status_check
    check (status in ('pending', 'accepted', 'revoked')),
  constraint platform_business_invitations_delivery_status_check
    check (delivery_status in ('pending', 'sent', 'failed', 'unknown')),
  constraint platform_business_invitations_issuer_check
    check (issuer_authority = 'service_role'),
  constraint platform_business_invitations_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint platform_business_invitations_acceptance_consistency
    check (
      (
        status = 'accepted'
        and accepted_user_id is not null
        and accepted_at is not null
        and acceptance_result is not null
        and revoked_at is null
      )
      or (
        status <> 'accepted'
        and accepted_user_id is null
        and accepted_at is null
        and acceptance_result is null
      )
    ),
  constraint platform_business_invitations_revocation_consistency
    check (
      (status = 'revoked' and revoked_at is not null)
      or (status <> 'revoked' and revoked_at is null)
    )
);

comment on table private.platform_business_invitations is
'Durable service-role authority for private creation of one business and its canonical primary branch.';

comment on column private.platform_business_invitations.business_id is
'Canonical business UUID generated at invitation issuance and reused by every acceptance retry.';

comment on column private.platform_business_invitations.branch_id is
'Canonical initial primary-branch UUID generated at invitation issuance and reused by every acceptance retry.';

comment on column private.platform_business_invitations.delivery_status is
'External notification state. It does not grant or revoke onboarding authority.';

create unique index if not exists platform_business_invitations_idempotency_unique
on private.platform_business_invitations (idempotency_key);

create index if not exists platform_business_invitations_email_status_idx
on private.platform_business_invitations (normalized_email, status, created_at desc);

alter table private.platform_business_invitations enable row level security;

revoke all on table private.platform_business_invitations
from public, anon, authenticated, service_role;

create or replace function private.touch_platform_business_invitation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.touch_platform_business_invitation()
from public, anon, authenticated, service_role;

drop trigger if exists trg_platform_business_invitations_updated_at
on private.platform_business_invitations;

create trigger trg_platform_business_invitations_updated_at
before update on private.platform_business_invitations
for each row
execute function private.touch_platform_business_invitation();

-- =========================================================
-- SERVICE-ROLE ISSUANCE AND DELIVERY ADMINISTRATION
-- =========================================================

create or replace function public.admin_create_platform_business_invitation(
  p_email text,
  p_business_name text,
  p_idempotency_key text,
  p_branch_name text default 'Principal',
  p_expires_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_normalized_email text;
  v_business_name text;
  v_branch_name text;
  v_idempotency_key text;
  v_expires_at timestamptz;
  v_metadata jsonb;
  v_invitation private.platform_business_invitations%rowtype;
  v_created boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to issue platform invitations';
  end if;

  v_email := nullif(btrim(coalesce(p_email, '')), '');
  v_normalized_email := lower(v_email);
  v_business_name := nullif(btrim(coalesce(p_business_name, '')), '');
  v_branch_name := nullif(btrim(coalesce(p_branch_name, '')), '');
  v_idempotency_key := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_expires_at := coalesce(p_expires_at, now() + interval '7 days');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_email is null
     or v_normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception 'A valid invitation email is required';
  end if;

  if v_business_name is null then
    raise exception 'business_name is required';
  end if;

  if v_branch_name is null then
    v_branch_name := 'Principal';
  end if;

  if v_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  if v_expires_at <= now() then
    raise exception 'expires_at must be in the future';
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  insert into private.platform_business_invitations (
    email,
    expires_at,
    business_id,
    branch_id,
    business_name,
    branch_name,
    idempotency_key,
    issuer_authority,
    metadata
  )
  values (
    v_email,
    v_expires_at,
    extensions.gen_random_uuid(),
    extensions.gen_random_uuid(),
    v_business_name,
    v_branch_name,
    v_idempotency_key,
    'service_role',
    v_metadata
  )
  on conflict (idempotency_key) do nothing
  returning *
  into v_invitation;

  if v_invitation.id is not null then
    v_created := true;
  else
    select invitation.*
    into v_invitation
    from private.platform_business_invitations invitation
    where invitation.idempotency_key = v_idempotency_key
    for update;

    if v_invitation.normalized_email <> v_normalized_email
       or v_invitation.business_name <> v_business_name
       or v_invitation.branch_name <> v_branch_name
       or v_invitation.metadata <> v_metadata
       or (
         p_expires_at is not null
         and v_invitation.expires_at <> p_expires_at
       )
    then
      raise exception using
        errcode = '23505',
        message = 'idempotency_key was already used with an incompatible invitation payload';
    end if;
  end if;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'email', v_invitation.email,
    'normalized_email', v_invitation.normalized_email,
    'status', v_invitation.status,
    'delivery_status', v_invitation.delivery_status,
    'expires_at', v_invitation.expires_at,
    'business_id', v_invitation.business_id,
    'branch_id', v_invitation.branch_id,
    'business_name', v_invitation.business_name,
    'branch_name', v_invitation.branch_name,
    'created_at', v_invitation.created_at,
    'created', v_created
  );
end;
$$;

revoke all on function public.admin_create_platform_business_invitation(
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
) from public, anon, authenticated;

grant execute on function public.admin_create_platform_business_invitation(
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
) to service_role;

create or replace function public.admin_claim_platform_business_invitation_delivery(
  p_invitation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation private.platform_business_invitations%rowtype;
  v_claimed boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to deliver platform invitations';
  end if;

  select invitation.*
  into v_invitation
  from private.platform_business_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'Platform invitation not found';
  end if;

  if v_invitation.status = 'pending'
     and v_invitation.expires_at > now()
     and v_invitation.delivery_status = 'pending'
  then
    update private.platform_business_invitations invitation
    set
      delivery_status = 'unknown',
      delivery_attempted_at = now(),
      delivery_error_code = null
    where invitation.id = v_invitation.id
    returning *
    into v_invitation;

    v_claimed := true;
  end if;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'claimed', v_claimed,
    'status', v_invitation.status,
    'delivery_status', v_invitation.delivery_status,
    'email', v_invitation.email,
    'business_id', v_invitation.business_id,
    'branch_id', v_invitation.branch_id
  );
end;
$$;

revoke all on function public.admin_claim_platform_business_invitation_delivery(uuid)
from public, anon, authenticated;

grant execute on function public.admin_claim_platform_business_invitation_delivery(uuid)
to service_role;

create or replace function public.admin_update_platform_business_invitation_delivery(
  p_invitation_id uuid,
  p_delivery_status text,
  p_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery_status text;
  v_error_code text;
  v_invitation private.platform_business_invitations%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to update invitation delivery';
  end if;

  v_delivery_status := lower(nullif(btrim(coalesce(p_delivery_status, '')), ''));
  v_error_code := nullif(left(btrim(coalesce(p_error_code, '')), 200), '');

  if v_delivery_status is null
     or v_delivery_status not in ('sent', 'failed', 'unknown')
  then
    raise exception 'delivery_status must be sent, failed, or unknown';
  end if;

  select invitation.*
  into v_invitation
  from private.platform_business_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'Platform invitation not found';
  end if;

  if v_invitation.delivery_status = 'sent'
     and v_delivery_status <> 'sent'
  then
    raise exception 'A sent invitation delivery cannot be downgraded';
  end if;

  update private.platform_business_invitations invitation
  set
    delivery_status = v_delivery_status,
    delivery_attempted_at = coalesce(delivery_attempted_at, now()),
    delivery_error_code = case
      when v_delivery_status = 'sent' then null
      else v_error_code
    end
  where invitation.id = v_invitation.id
  returning *
  into v_invitation;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'delivery_status', v_invitation.delivery_status,
    'delivery_attempted_at', v_invitation.delivery_attempted_at,
    'delivery_error_code', v_invitation.delivery_error_code
  );
end;
$$;

revoke all on function public.admin_update_platform_business_invitation_delivery(
  uuid,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.admin_update_platform_business_invitation_delivery(
  uuid,
  text,
  text
) to service_role;

create or replace function public.admin_revoke_platform_business_invitation(
  p_invitation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text;
  v_invitation private.platform_business_invitations%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to revoke platform invitations';
  end if;

  v_reason := nullif(left(btrim(coalesce(p_reason, '')), 500), '');

  select invitation.*
  into v_invitation
  from private.platform_business_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'Platform invitation not found';
  end if;

  if v_invitation.status = 'accepted' then
    raise exception 'An accepted platform invitation cannot be revoked';
  end if;

  if v_invitation.status = 'pending' then
    update private.platform_business_invitations invitation
    set
      status = 'revoked',
      revoked_at = now(),
      revocation_reason = v_reason
    where invitation.id = v_invitation.id
    returning *
    into v_invitation;
  end if;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'status', v_invitation.status,
    'revoked_at', v_invitation.revoked_at
  );
end;
$$;

revoke all on function public.admin_revoke_platform_business_invitation(uuid, text)
from public, anon, authenticated;

grant execute on function public.admin_revoke_platform_business_invitation(uuid, text)
to service_role;

-- =========================================================
-- AUTHENTICATED INVITATION DISCOVERY AND ATOMIC ACCEPTANCE
-- =========================================================

create or replace function public.list_my_platform_business_invitations()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_normalized_email text;
  v_invitations jsonb;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(au.email))
  into v_normalized_email
  from auth.users au
  where au.id = v_user_id
    and au.deleted_at is null
    and nullif(btrim(coalesce(au.email, '')), '') is not null;

  if v_normalized_email is null then
    raise exception 'Authenticated user does not have a valid email';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'invitation_id', invitation.id,
        'status', invitation.status,
        'delivery_status', invitation.delivery_status,
        'expires_at', invitation.expires_at,
        'is_expired', invitation.expires_at <= now(),
        'business_id', invitation.business_id,
        'branch_id', invitation.branch_id,
        'business_name', invitation.business_name,
        'branch_name', invitation.branch_name,
        'created_at', invitation.created_at,
        'accepted_at', invitation.accepted_at
      )
      order by invitation.created_at desc, invitation.id
    ),
    '[]'::jsonb
  )
  into v_invitations
  from private.platform_business_invitations invitation
  where invitation.normalized_email = v_normalized_email
    and (
      invitation.status = 'pending'
      or (
        invitation.status = 'accepted'
        and invitation.accepted_user_id = v_user_id
      )
    );

  return jsonb_build_object(
    'user_id', v_user_id,
    'invitations', v_invitations,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_my_platform_business_invitations()
from public, anon;

grant execute on function public.list_my_platform_business_invitations()
to authenticated;

create or replace function public.accept_platform_business_invitation(
  p_invitation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_normalized_email text;
  v_invitation private.platform_business_invitations%rowtype;
  v_provisioning jsonb;
  v_result jsonb;
  v_branch_is_primary boolean;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select lower(btrim(au.email))
  into v_normalized_email
  from auth.users au
  where au.id = v_user_id
    and au.deleted_at is null
    and nullif(btrim(coalesce(au.email, '')), '') is not null;

  if v_normalized_email is null
     or v_normalized_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception 'Authenticated user does not have a valid email';
  end if;

  select invitation.*
  into v_invitation
  from private.platform_business_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception using
      errcode = '42501',
      message = 'Platform invitation is not available for this user';
  end if;

  if v_invitation.status = 'accepted' then
    if v_invitation.accepted_user_id <> v_user_id then
      raise exception using
        errcode = '42501',
        message = 'Platform invitation is not available for this user';
    end if;

    return v_invitation.acceptance_result;
  end if;

  if v_invitation.normalized_email <> v_normalized_email then
    raise exception using
      errcode = '42501',
      message = 'Platform invitation is not available for this user';
  end if;

  if v_invitation.status = 'revoked' then
    raise exception using
      errcode = '42501',
      message = 'Platform invitation has been revoked';
  end if;

  if v_invitation.expires_at <= now() then
    raise exception using
      errcode = '42501',
      message = 'Platform invitation has expired';
  end if;

  v_provisioning := public.create_business(
    v_invitation.business_id,
    v_invitation.branch_id,
    v_invitation.business_name,
    v_invitation.branch_name,
    'Caja Principal',
    null,
    v_invitation.metadata || jsonb_build_object(
      'created_via', 'public.accept_platform_business_invitation',
      'platform_invitation_id', v_invitation.id
    )
  );

  select br.is_primary
  into v_branch_is_primary
  from public.branches br
  where br.id = v_invitation.branch_id
    and br.business_id = v_invitation.business_id
    and br.deleted_at is null
    and br.status = 'active';

  if not coalesce(v_branch_is_primary, false) then
    raise exception 'Private onboarding did not produce an active primary branch';
  end if;

  v_result := v_provisioning || jsonb_build_object(
    'invitation_id', v_invitation.id,
    'invitation_status', 'accepted',
    'branch_is_primary', true
  );

  update private.platform_business_invitations invitation
  set
    status = 'accepted',
    accepted_user_id = v_user_id,
    accepted_at = now(),
    acceptance_result = v_result
  where invitation.id = v_invitation.id;

  return v_result;
end;
$$;

revoke all on function public.accept_platform_business_invitation(uuid)
from public, anon;

grant execute on function public.accept_platform_business_invitation(uuid)
to authenticated;

-- R1.1c remains the provisioning engine, but it is no longer directly
-- executable by client-authenticated users.
revoke all on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) from public, anon, authenticated;

grant execute on function public.create_business(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
) to service_role;

-- =========================================================
-- DISCOVERY EXPOSES FORMAL PRIMARY IDENTITY
-- =========================================================

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
      br.is_primary as branch_is_primary,
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
        'branch_is_primary', cr.branch_is_primary,
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

revoke all on function public.list_authorized_operational_contexts()
from public, anon;

grant execute on function public.list_authorized_operational_contexts()
to authenticated, service_role;

comment on function public.admin_create_platform_business_invitation(
  text,
  text,
  text,
  text,
  timestamptz,
  jsonb
) is
'Creates one durable private-platform invitation and canonical tenant IDs. EXECUTE is service-role only and idempotent by idempotency_key.';

comment on function public.list_my_platform_business_invitations() is
'Lists only pending or accepted platform-business invitations matching the authenticated user email; administrative metadata is not exposed.';

comment on function public.accept_platform_business_invitation(uuid) is
'Atomically consumes one matching private-platform invitation and reuses R1.1c create_business to provision the canonical tenant and primary branch.';

comment on function public.list_authorized_operational_contexts() is
'Lists concrete active business/branch contexts authorized for auth.uid(), including formal primary-branch identity, unioned effective permissions, and applicable memberships.';

commit;
