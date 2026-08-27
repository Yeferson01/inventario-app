-- ORG-2C - Secure business-member invitations.
--
-- Business membership authority is durable and server-authoritative. Email
-- delivery remains a separate, retryable concern and never grants access by
-- itself. Direct client DML on business_members is closed in favor of the
-- invitation RPCs below.

begin;

-- =========================================================
-- DURABLE PRIVATE INVITATIONS
-- =========================================================

create table private.business_member_invitations (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null
    references public.businesses(id) on delete restrict,
  email text not null,
  normalized_email text generated always as (lower(btrim(email))) stored,
  role_id uuid not null
    references public.roles(id) on delete restrict,
  branch_id uuid
    references public.branches(id) on delete restrict,

  status text not null default 'pending',
  delivery_status text not null default 'pending',
  expires_at timestamptz not null,

  invited_by_profile_id uuid not null
    references public.profiles(id) on delete restrict,
  accepted_user_id uuid
    references auth.users(id) on delete restrict,
  accepted_membership_id uuid
    references public.business_members(id) on delete restrict,

  idempotency_key text not null,
  request_payload jsonb not null,
  acceptance_result jsonb,

  delivery_attempted_at timestamptz,
  delivery_sent_at timestamptz,
  delivery_error_code text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  accepted_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,
  metadata jsonb not null default '{}'::jsonb,

  constraint business_member_invitations_email_not_blank
    check (length(btrim(email)) > 0 and length(btrim(email)) <= 320),
  constraint business_member_invitations_email_shape
    check (
      normalized_email
        ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    ),
  constraint business_member_invitations_status_check
    check (status in ('pending', 'accepted', 'revoked')),
  constraint business_member_invitations_delivery_status_check
    check (delivery_status in ('pending', 'sent', 'failed', 'unknown')),
  constraint business_member_invitations_expiration_check
    check (expires_at > created_at),
  constraint business_member_invitations_idempotency_key_not_blank
    check (
      length(btrim(idempotency_key)) > 0
      and length(btrim(idempotency_key)) <= 200
    ),
  constraint business_member_invitations_payload_object
    check (jsonb_typeof(request_payload) = 'object'),
  constraint business_member_invitations_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  constraint business_member_invitations_acceptance_consistency
    check (
      (
        status = 'accepted'
        and accepted_user_id is not null
        and accepted_membership_id is not null
        and accepted_at is not null
        and acceptance_result is not null
        and revoked_at is null
      )
      or (
        status <> 'accepted'
        and accepted_user_id is null
        and accepted_membership_id is null
        and accepted_at is null
        and acceptance_result is null
      )
    ),
  constraint business_member_invitations_revocation_consistency
    check (
      (status = 'revoked' and revoked_at is not null)
      or (status <> 'revoked' and revoked_at is null)
    ),
  constraint business_member_invitations_delivery_sent_consistency
    check (
      (delivery_status = 'sent' and delivery_sent_at is not null)
      or (delivery_status <> 'sent' and delivery_sent_at is null)
    )
);

comment on table private.business_member_invitations is
'Durable authority to add one authenticated user to an existing business. It is distinct from private platform onboarding invitations and is never an email-delivery authority.';

comment on column private.business_member_invitations.branch_id is
'NULL grants business-wide scope. A UUID grants only that active branch and is revalidated at acceptance.';

comment on column private.business_member_invitations.delivery_status is
'External notification state. It never grants, revokes, or changes membership authority.';

create unique index business_member_invitations_business_key_unique
on private.business_member_invitations (business_id, idempotency_key);

create unique index business_member_invitations_pending_equivalent_unique
on private.business_member_invitations (
  business_id,
  normalized_email,
  role_id,
  coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid)
)
where status = 'pending';

create index business_member_invitations_email_status_idx
on private.business_member_invitations (
  normalized_email,
  status,
  created_at desc
);

create index business_member_invitations_business_status_idx
on private.business_member_invitations (
  business_id,
  status,
  created_at desc
);

alter table private.business_member_invitations enable row level security;

revoke all on table private.business_member_invitations
from public, anon, authenticated, service_role;

create or replace function private.touch_business_member_invitation()
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

revoke all on function private.touch_business_member_invitation()
from public, anon, authenticated, service_role;

create trigger trg_business_member_invitations_updated_at
before update on private.business_member_invitations
for each row
execute function private.touch_business_member_invitation();

-- =========================================================
-- PRIVATE AUTHORIZATION AND RESPONSE HELPERS
-- =========================================================

create or replace function private.is_delegable_business_member_role(
  p_role_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_role_id is not null
    and exists (
      select 1
      from public.roles r
      where r.id = p_role_id
        and r.business_id is null
        and r.is_system_role = true
        and r.deleted_at is null
        and r.name in ('cashier', 'warehouse', 'technician')
    );
$$;

revoke all on function private.is_delegable_business_member_role(uuid)
from public, anon, authenticated, service_role;

create or replace function private.can_administer_business_member_invitation(
  p_business_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_branch_id is null then
      private.has_business_wide_permission(
        p_business_id,
        'members.invite'
      )
    else
      private.has_branch_permission(
        p_business_id,
        p_branch_id,
        'members.invite'
      )
  end;
$$;

revoke all on function private.can_administer_business_member_invitation(
  uuid,
  uuid
) from public, anon, authenticated, service_role;

create or replace function private.business_member_invitation_response(
  p_invitation_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'invitation_id', invitation.id,
    'business_id', invitation.business_id,
    'business_name', business.name,
    'email', invitation.email,
    'role_id', invitation.role_id,
    'role_name', role.name,
    'branch_id', invitation.branch_id,
    'branch_name', branch.name,
    'scope', case
      when invitation.branch_id is null then 'business'
      else 'branch'
    end,
    'status', invitation.status,
    'delivery_status', invitation.delivery_status,
    'expires_at', invitation.expires_at,
    'is_expired', invitation.expires_at <= now(),
    'accepted_membership_id', invitation.accepted_membership_id,
    'created_at', invitation.created_at,
    'updated_at', invitation.updated_at,
    'accepted_at', invitation.accepted_at,
    'revoked_at', invitation.revoked_at,
    'delivery_attempted_at', invitation.delivery_attempted_at,
    'delivery_sent_at', invitation.delivery_sent_at,
    'delivery_error_code', invitation.delivery_error_code
  )
  from private.business_member_invitations invitation
  join public.businesses business
    on business.id = invitation.business_id
  join public.roles role
    on role.id = invitation.role_id
  left join public.branches branch
    on branch.id = invitation.branch_id
  where invitation.id = p_invitation_id;
$$;

revoke all on function private.business_member_invitation_response(uuid)
from public, anon, authenticated, service_role;

-- =========================================================
-- AUTHENTICATED ISSUANCE
-- =========================================================

create or replace function public.create_business_member_invitation(
  p_business_id uuid,
  p_email text,
  p_role_id uuid,
  p_branch_id uuid,
  p_idempotency_key text,
  p_expires_at timestamptz default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_profile_id uuid;
  v_email text;
  v_normalized_email text;
  v_idempotency_key text;
  v_expires_at timestamptz;
  v_metadata jsonb;
  v_request_payload jsonb;
  v_invitation private.business_member_invitations%rowtype;
  v_existing_pending_id uuid;
  v_existing_user_id uuid;
  v_existing_membership_id uuid;
  v_created boolean := false;
begin
  v_actor_profile_id := auth.uid();
  if v_actor_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = v_actor_profile_id
  ) then
    raise exception 'Authenticated profile is required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if not exists (
    select 1
    from public.businesses business
    where business.id = p_business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  if not private.is_delegable_business_member_role(p_role_id) then
    raise exception using
      errcode = '42501',
      message = 'Target role is not delegable by business member invitations';
  end if;

  if p_branch_id is not null
     and not exists (
       select 1
       from public.branches branch
       where branch.id = p_branch_id
         and branch.business_id = p_business_id
         and branch.status = 'active'
         and branch.deleted_at is null
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Branch is not active for this business';
  end if;

  if not private.can_administer_business_member_invitation(
    p_business_id,
    p_branch_id
  ) then
    raise exception using
      errcode = '42501',
      message = case
        when p_branch_id is null then
          'Business-wide members.invite permission is required'
        else
          'members.invite permission is required for this branch'
      end;
  end if;

  v_email := nullif(btrim(coalesce(p_email, '')), '');
  v_normalized_email := lower(v_email);
  v_idempotency_key := nullif(
    btrim(coalesce(p_idempotency_key, '')),
    ''
  );
  v_expires_at := coalesce(p_expires_at, now() + interval '7 days');
  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if v_email is null
     or v_normalized_email
       !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception 'A valid invitation email is required';
  end if;

  if v_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;
  if char_length(v_idempotency_key) > 200 then
    raise exception 'idempotency_key exceeds 200 characters';
  end if;
  if v_expires_at <= now() then
    raise exception 'expires_at must be in the future';
  end if;
  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  -- This is diagnostic only. Email never becomes a membership foreign key and
  -- an existing user/membership does not bypass acceptance revalidation.
  select auth_user.id
  into v_existing_user_id
  from auth.users auth_user
  where auth_user.deleted_at is null
    and lower(btrim(auth_user.email)) = v_normalized_email
  order by auth_user.created_at, auth_user.id
  limit 1;

  if v_existing_user_id is not null then
    select member.id
    into v_existing_membership_id
    from public.business_members member
    where member.business_id = p_business_id
      and member.profile_id = v_existing_user_id
      and member.role_id = p_role_id
      and member.status = 'active'
      and member.deleted_at is null
      and (
        member.branch_id is not distinct from p_branch_id
        or (p_branch_id is not null and member.branch_id is null)
      )
    order by
      case
        when member.branch_id is not distinct from p_branch_id then 0
        else 1
      end,
      member.created_at,
      member.id
    limit 1;
  end if;

  v_request_payload := jsonb_build_object(
    'normalized_email', v_normalized_email,
    'role_id', p_role_id,
    'branch_id', p_branch_id,
    'requested_expires_at', p_expires_at,
    'metadata', v_metadata
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'business_member_invitation:'
        || p_business_id::text
        || ':'
        || v_normalized_email,
      0
    )
  );

  select invitation.*
  into v_invitation
  from private.business_member_invitations invitation
  where invitation.business_id = p_business_id
    and invitation.idempotency_key = v_idempotency_key
  for update;

  if v_invitation.id is not null then
    if v_invitation.request_payload <> v_request_payload then
      raise exception using
        errcode = '23505',
        message = 'idempotency_key was already used with an incompatible member invitation payload';
    end if;

    return private.business_member_invitation_response(v_invitation.id)
      || jsonb_build_object(
        'created', false,
        'existing_auth_user', v_existing_user_id is not null,
        'existing_membership_id', v_existing_membership_id
      );
  end if;

  -- An expired invitation is no longer authority. Marking it revoked only
  -- when a replacement is requested frees the partial uniqueness guard
  -- without requiring an expiration job.
  update private.business_member_invitations invitation
  set
    status = 'revoked',
    revoked_at = now(),
    revocation_reason = 'expired_superseded'
  where invitation.business_id = p_business_id
    and invitation.normalized_email = v_normalized_email
    and invitation.role_id = p_role_id
    and invitation.branch_id is not distinct from p_branch_id
    and invitation.status = 'pending'
    and invitation.expires_at <= now();

  select invitation.id
  into v_existing_pending_id
  from private.business_member_invitations invitation
  where invitation.business_id = p_business_id
    and invitation.normalized_email = v_normalized_email
    and invitation.role_id = p_role_id
    and invitation.branch_id is not distinct from p_branch_id
    and invitation.status = 'pending'
    and invitation.expires_at > now()
  limit 1;

  if v_existing_pending_id is not null then
    raise exception using
      errcode = '23505',
      message = 'An equivalent pending business member invitation already exists';
  end if;

  insert into private.business_member_invitations (
    business_id,
    email,
    role_id,
    branch_id,
    expires_at,
    invited_by_profile_id,
    idempotency_key,
    request_payload,
    metadata
  )
  values (
    p_business_id,
    v_email,
    p_role_id,
    p_branch_id,
    v_expires_at,
    v_actor_profile_id,
    v_idempotency_key,
    v_request_payload,
    v_metadata
  )
  returning * into v_invitation;

  v_created := true;

  return private.business_member_invitation_response(v_invitation.id)
    || jsonb_build_object(
      'created', v_created,
      'existing_auth_user', v_existing_user_id is not null,
      'existing_membership_id', v_existing_membership_id
    );
end;
$$;

revoke all on function public.create_business_member_invitation(
  uuid,
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  jsonb
) from public, anon;

grant execute on function public.create_business_member_invitation(
  uuid,
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  jsonb
) to authenticated;

comment on function public.create_business_member_invitation(
  uuid,
  text,
  uuid,
  uuid,
  text,
  timestamptz,
  jsonb
) is
'Issues a durable employee invitation. Authority is auth.uid() plus active members.invite capability at the requested business-wide or branch scope.';

-- =========================================================
-- ADMINISTRATIVE AND SELF LISTING
-- =========================================================

create or replace function public.list_business_member_invitations(
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
  v_invitations jsonb;
begin
  v_profile_id := auth.uid();
  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1
    from public.businesses business
    where business.id = p_business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  if not private.has_business_wide_permission(
    p_business_id,
    'members.invite'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Business-wide members.invite permission is required';
  end if;

  select coalesce(
    jsonb_agg(
      private.business_member_invitation_response(invitation.id)
      order by invitation.created_at desc, invitation.id
    ),
    '[]'::jsonb
  )
  into v_invitations
  from private.business_member_invitations invitation
  where invitation.business_id = p_business_id;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', p_business_id,
    'invitations', v_invitations,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_business_member_invitations(uuid)
from public, anon;

grant execute on function public.list_business_member_invitations(uuid)
to authenticated;

create or replace function public.list_my_business_member_invitations()
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

  select lower(btrim(auth_user.email))
  into v_normalized_email
  from auth.users auth_user
  where auth_user.id = v_user_id
    and auth_user.deleted_at is null
    and nullif(btrim(coalesce(auth_user.email, '')), '') is not null;

  if v_normalized_email is null then
    raise exception 'Authenticated user does not have a valid email';
  end if;

  select coalesce(
    jsonb_agg(
      private.business_member_invitation_response(invitation.id)
      order by invitation.created_at desc, invitation.id
    ),
    '[]'::jsonb
  )
  into v_invitations
  from private.business_member_invitations invitation
  join public.businesses business
    on business.id = invitation.business_id
   and business.deleted_at is null
   and coalesce(business.status, 'active') = 'active'
  join public.roles role
    on role.id = invitation.role_id
   and role.business_id is null
   and role.is_system_role = true
   and role.deleted_at is null
   and role.name in ('cashier', 'warehouse', 'technician')
  left join public.branches branch
    on branch.id = invitation.branch_id
  where invitation.normalized_email = v_normalized_email
    and invitation.status = 'pending'
    and invitation.expires_at > now()
    and (
      invitation.branch_id is null
      or (
        branch.business_id = invitation.business_id
        and branch.status = 'active'
        and branch.deleted_at is null
      )
    );

  return jsonb_build_object(
    'user_id', v_user_id,
    'invitations', v_invitations,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_my_business_member_invitations()
from public, anon;

grant execute on function public.list_my_business_member_invitations()
to authenticated;

-- =========================================================
-- ATOMIC ACCEPTANCE
-- =========================================================

create or replace function public.accept_business_member_invitation(
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
  v_auth_full_name text;
  v_invitation private.business_member_invitations%rowtype;
  v_membership public.business_members%rowtype;
  v_profile_created boolean := false;
  v_membership_created boolean := false;
  v_membership_reused_by_coverage boolean := false;
  v_inserted_profile_id uuid;
  v_result jsonb;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  select
    lower(btrim(auth_user.email)),
    left(
      coalesce(
        nullif(btrim(auth_user.raw_user_meta_data ->> 'full_name'), ''),
        nullif(btrim(auth_user.email), '')
      ),
      255
    )
  into v_normalized_email, v_auth_full_name
  from auth.users auth_user
  where auth_user.id = v_user_id
    and auth_user.deleted_at is null
    and nullif(btrim(coalesce(auth_user.email, '')), '') is not null;

  if v_normalized_email is null
     or v_normalized_email
       !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  then
    raise exception 'Authenticated user does not have a valid email';
  end if;

  select invitation.*
  into v_invitation
  from private.business_member_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception using
      errcode = '42501',
      message = 'Business member invitation is not available for this user';
  end if;

  if v_invitation.status = 'accepted' then
    if v_invitation.accepted_user_id <> v_user_id then
      raise exception using
        errcode = '42501',
        message = 'Business member invitation is not available for this user';
    end if;

    return v_invitation.acceptance_result;
  end if;

  if v_invitation.normalized_email <> v_normalized_email then
    raise exception using
      errcode = '42501',
      message = 'Business member invitation is not available for this user';
  end if;

  if v_invitation.status = 'revoked' then
    raise exception using
      errcode = '42501',
      message = 'Business member invitation has been revoked';
  end if;

  if v_invitation.expires_at <= now() then
    raise exception using
      errcode = '42501',
      message = 'Business member invitation has expired';
  end if;

  if not exists (
    select 1
    from public.businesses business
    where business.id = v_invitation.business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Invitation business is not active';
  end if;

  if not private.is_delegable_business_member_role(v_invitation.role_id) then
    raise exception using
      errcode = '42501',
      message = 'Invitation target role is no longer delegable';
  end if;

  if v_invitation.branch_id is not null
     and not exists (
       select 1
       from public.branches branch
       where branch.id = v_invitation.branch_id
         and branch.business_id = v_invitation.business_id
         and branch.status = 'active'
         and branch.deleted_at is null
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Invitation branch is not active for this business';
  end if;

  insert into public.profiles (
    id,
    full_name,
    role,
    status
  )
  values (
    v_user_id,
    v_auth_full_name,
    'cashier',
    'active'
  )
  on conflict (id) do nothing
  returning id into v_inserted_profile_id;

  v_profile_created := v_inserted_profile_id is not null;

  if not exists (
    select 1
    from public.profiles profile
    where profile.id = v_user_id
  ) then
    raise exception 'Unable to provision authenticated profile';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'accept_business_member_invitation:'
        || v_invitation.business_id::text
        || ':'
        || v_user_id::text,
      0
    )
  );

  select member.*
  into v_membership
  from public.business_members member
  where member.business_id = v_invitation.business_id
    and member.profile_id = v_user_id
    and member.branch_id is not distinct from v_invitation.branch_id
    and member.role_id = v_invitation.role_id
    and member.status = 'active'
    and member.deleted_at is null
  order by member.created_at, member.id
  limit 1
  for update;

  if v_membership.id is null and v_invitation.branch_id is not null then
    select member.*
    into v_membership
    from public.business_members member
    where member.business_id = v_invitation.business_id
      and member.profile_id = v_user_id
      and member.branch_id is null
      and member.role_id = v_invitation.role_id
      and member.status = 'active'
      and member.deleted_at is null
    order by member.created_at, member.id
    limit 1
    for update;

    v_membership_reused_by_coverage := v_membership.id is not null;
  end if;

  if v_membership.id is null
     and exists (
       select 1
       from public.business_members member
       where member.business_id = v_invitation.business_id
         and member.profile_id = v_user_id
         and member.branch_id is not distinct from v_invitation.branch_id
         and member.status <> 'removed'
         and member.deleted_at is null
     )
  then
    raise exception using
      errcode = '23505',
      message = 'A membership already exists at this scope with a different or non-active role';
  end if;

  if v_membership.id is null then
    insert into public.business_members (
      business_id,
      profile_id,
      branch_id,
      role_id,
      status,
      invited_by,
      invited_at,
      accepted_at,
      created_by,
      updated_by
    )
    values (
      v_invitation.business_id,
      v_user_id,
      v_invitation.branch_id,
      v_invitation.role_id,
      'active',
      v_invitation.invited_by_profile_id,
      v_invitation.created_at,
      now(),
      v_invitation.invited_by_profile_id,
      v_user_id
    )
    returning * into v_membership;

    v_membership_created := true;
  end if;

  v_result := jsonb_build_object(
    'invitation_id', v_invitation.id,
    'invitation_status', 'accepted',
    'profile_id', v_user_id,
    'profile_created', v_profile_created,
    'business_id', v_invitation.business_id,
    'branch_id', v_invitation.branch_id,
    'role_id', v_invitation.role_id,
    'membership_id', v_membership.id,
    'membership_scope_branch_id', v_membership.branch_id,
    'membership_created', v_membership_created,
    'membership_reused', not v_membership_created,
    'membership_reused_by_business_wide_coverage',
      v_membership_reused_by_coverage,
    'accepted_at', now()
  );

  update private.business_member_invitations invitation
  set
    status = 'accepted',
    accepted_user_id = v_user_id,
    accepted_membership_id = v_membership.id,
    accepted_at = now(),
    acceptance_result = v_result
  where invitation.id = v_invitation.id;

  return v_result;
end;
$$;

revoke all on function public.accept_business_member_invitation(uuid)
from public, anon;

grant execute on function public.accept_business_member_invitation(uuid)
to authenticated;

-- =========================================================
-- AUTHORIZED REVOCATION
-- =========================================================

create or replace function public.revoke_business_member_invitation(
  p_invitation_id uuid,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_profile_id uuid;
  v_reason text;
  v_invitation private.business_member_invitations%rowtype;
begin
  v_actor_profile_id := auth.uid();
  if v_actor_profile_id is null then
    raise exception 'Authentication required';
  end if;

  select invitation.*
  into v_invitation
  from private.business_member_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception using
      errcode = '42501',
      message = 'Business member invitation is not available';
  end if;

  if not exists (
    select 1
    from public.businesses business
    where business.id = v_invitation.business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Invitation business is not active';
  end if;

  if v_invitation.branch_id is not null
     and not exists (
       select 1
       from public.branches branch
       where branch.id = v_invitation.branch_id
         and branch.business_id = v_invitation.business_id
         and branch.status = 'active'
         and branch.deleted_at is null
     )
  then
    raise exception 'Invitation branch is not active for this business';
  end if;

  if not private.can_administer_business_member_invitation(
    v_invitation.business_id,
    v_invitation.branch_id
  ) then
    raise exception using
      errcode = '42501',
      message = 'members.invite permission is required for this invitation scope';
  end if;

  if v_invitation.status = 'accepted' then
    raise exception 'An accepted business member invitation cannot be revoked';
  end if;

  v_reason := nullif(left(btrim(coalesce(p_reason, '')), 500), '');

  if v_invitation.status = 'pending' then
    update private.business_member_invitations invitation
    set
      status = 'revoked',
      revoked_at = now(),
      revocation_reason = v_reason
    where invitation.id = v_invitation.id
    returning * into v_invitation;
  end if;

  return private.business_member_invitation_response(v_invitation.id);
end;
$$;

revoke all on function public.revoke_business_member_invitation(uuid, text)
from public, anon;

grant execute on function public.revoke_business_member_invitation(uuid, text)
to authenticated;

-- =========================================================
-- SERVICE-ROLE DELIVERY STATE
-- =========================================================

create or replace function public.admin_claim_business_member_invitation_delivery(
  p_invitation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation private.business_member_invitations%rowtype;
  v_claimed boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to deliver business member invitations';
  end if;

  select invitation.*
  into v_invitation
  from private.business_member_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'Business member invitation not found';
  end if;

  if v_invitation.status = 'pending'
     and v_invitation.expires_at > now()
     and v_invitation.delivery_status = 'pending'
  then
    update private.business_member_invitations invitation
    set
      delivery_status = 'unknown',
      delivery_attempted_at = now(),
      delivery_error_code = null
    where invitation.id = v_invitation.id
    returning * into v_invitation;

    v_claimed := true;
  end if;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'claimed', v_claimed,
    'status', v_invitation.status,
    'delivery_status', v_invitation.delivery_status,
    'email', v_invitation.email
  );
end;
$$;

revoke all on function public.admin_claim_business_member_invitation_delivery(
  uuid
) from public, anon, authenticated;

grant execute on function public.admin_claim_business_member_invitation_delivery(
  uuid
) to service_role;

create or replace function public.admin_update_business_member_invitation_delivery(
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
  v_invitation private.business_member_invitations%rowtype;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service-role authority is required to update member invitation delivery';
  end if;

  v_delivery_status := lower(
    nullif(btrim(coalesce(p_delivery_status, '')), '')
  );
  v_error_code := nullif(left(btrim(coalesce(p_error_code, '')), 200), '');

  if v_delivery_status is null
     or v_delivery_status not in ('sent', 'failed', 'unknown')
  then
    raise exception 'delivery_status must be sent, failed, or unknown';
  end if;

  select invitation.*
  into v_invitation
  from private.business_member_invitations invitation
  where invitation.id = p_invitation_id
  for update;

  if v_invitation.id is null then
    raise exception 'Business member invitation not found';
  end if;

  if v_invitation.delivery_status = 'sent'
     and v_delivery_status <> 'sent'
  then
    raise exception 'A sent invitation delivery cannot be downgraded';
  end if;

  update private.business_member_invitations invitation
  set
    delivery_status = v_delivery_status,
    delivery_attempted_at = coalesce(delivery_attempted_at, now()),
    delivery_sent_at = case
      when v_delivery_status = 'sent' then coalesce(delivery_sent_at, now())
      else null
    end,
    delivery_error_code = case
      when v_delivery_status = 'sent' then null
      else v_error_code
    end
  where invitation.id = v_invitation.id
  returning * into v_invitation;

  return jsonb_build_object(
    'invitation_id', v_invitation.id,
    'delivery_status', v_invitation.delivery_status,
    'delivery_attempted_at', v_invitation.delivery_attempted_at,
    'delivery_sent_at', v_invitation.delivery_sent_at,
    'delivery_error_code', v_invitation.delivery_error_code
  );
end;
$$;

revoke all on function public.admin_update_business_member_invitation_delivery(
  uuid,
  text,
  text
) from public, anon, authenticated;

grant execute on function public.admin_update_business_member_invitation_delivery(
  uuid,
  text,
  text
) to service_role;

-- =========================================================
-- CLOSE DIRECT CLIENT MEMBERSHIP DML
-- =========================================================

drop policy if exists business_members_insert_allowed
on public.business_members;

drop policy if exists business_members_update_allowed
on public.business_members;

revoke all on table public.business_members from anon, authenticated;
grant select on table public.business_members to authenticated;

comment on function public.accept_business_member_invitation(uuid) is
'Atomically accepts a matching, valid invitation using auth.users.email and creates or safely reuses a scoped business membership without replacing another role.';

comment on function public.revoke_business_member_invitation(uuid, text) is
'Revokes only a pending invitation when auth.uid() still has members.invite at the invitation scope. Accepted memberships are untouched.';

commit;
