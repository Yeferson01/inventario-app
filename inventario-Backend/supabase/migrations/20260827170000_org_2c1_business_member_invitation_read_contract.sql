-- ORG-2C.1 - Server-authoritative read contracts for member invitations.
--
-- The client receives canonical delegable role IDs and only the Branch scopes
-- currently administered by auth.uid(). Invitation authority remains entirely
-- in the ORG-2C write helpers and RPCs.

begin;

-- =========================================================
-- INVITATION FORM OPTIONS
-- =========================================================

create or replace function public.list_business_member_invitation_options(
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
  v_can_invite_business_wide boolean;
  v_delegable_roles jsonb;
  v_invitable_branches jsonb;
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
    from public.businesses business
    where business.id = p_business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  v_can_invite_business_wide := private.has_business_wide_permission(
    p_business_id,
    'members.invite'
  );

  if not v_can_invite_business_wide
     and not exists (
       select 1
       from public.branches branch
       where branch.business_id = p_business_id
         and branch.status = 'active'
         and branch.deleted_at is null
         and private.has_branch_permission(
           p_business_id,
           branch.id,
           'members.invite'
         )
     )
  then
    raise exception using
      errcode = '42501',
      message = 'members.invite permission is required for this Business';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'role_id', role.id,
        'role_name', role.name
      )
      order by
        case role.name
          when 'cashier' then 1
          when 'warehouse' then 2
          when 'technician' then 3
          else 4
        end,
        role.id
    ),
    '[]'::jsonb
  )
  into v_delegable_roles
  from public.roles role
  where private.is_delegable_business_member_role(role.id);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'branch_id', branch.id,
        'name', branch.name,
        'is_primary', branch.is_primary
      )
      order by branch.is_primary desc, lower(branch.name), branch.id
    ),
    '[]'::jsonb
  )
  into v_invitable_branches
  from public.branches branch
  where branch.business_id = p_business_id
    and branch.status = 'active'
    and branch.deleted_at is null
    and private.has_branch_permission(
      p_business_id,
      branch.id,
      'members.invite'
    );

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', p_business_id,
    'can_invite_business_wide', v_can_invite_business_wide,
    'delegable_roles', v_delegable_roles,
    'invitable_branches', v_invitable_branches
  );
end;
$$;

revoke all on function public.list_business_member_invitation_options(uuid)
from public, anon, service_role;

grant execute on function public.list_business_member_invitation_options(uuid)
to authenticated;

comment on function public.list_business_member_invitation_options(uuid) is
'Returns canonical ORG-2C target roles and active Branch scopes currently administered by auth.uid() through members.invite. p_business_id is context, never authority.';

-- =========================================================
-- SCOPE-AWARE ADMINISTRATIVE LISTING
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
  v_can_invite_business_wide boolean;
  v_invitations jsonb;
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
    from public.businesses business
    where business.id = p_business_id
      and business.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
  ) then
    raise exception 'Business does not exist or is not active';
  end if;

  v_can_invite_business_wide := private.has_business_wide_permission(
    p_business_id,
    'members.invite'
  );

  if not v_can_invite_business_wide
     and not exists (
       select 1
       from public.branches branch
       where branch.business_id = p_business_id
         and branch.status = 'active'
         and branch.deleted_at is null
         and private.has_branch_permission(
           p_business_id,
           branch.id,
           'members.invite'
         )
     )
  then
    raise exception using
      errcode = '42501',
      message = 'members.invite permission is required for this Business';
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
  where invitation.business_id = p_business_id
    and (
      v_can_invite_business_wide
      or (
        invitation.branch_id is not null
        and exists (
          select 1
          from public.branches branch
          where branch.id = invitation.branch_id
            and branch.business_id = p_business_id
            and branch.status = 'active'
            and branch.deleted_at is null
            and private.has_branch_permission(
              p_business_id,
              branch.id,
              'members.invite'
            )
        )
      )
    );

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business_id', p_business_id,
    'can_invite_business_wide', v_can_invite_business_wide,
    'invitations', v_invitations,
    'generated_at', now()
  );
end;
$$;

revoke all on function public.list_business_member_invitations(uuid)
from public, anon, service_role;

grant execute on function public.list_business_member_invitations(uuid)
to authenticated;

comment on function public.list_business_member_invitations(uuid) is
'Lists all Business invitations for business-wide members.invite authority, or only active Branch scopes currently administered by a branch-scoped actor.';

commit;
