-- R1.1 - Multitenancy invariants for operational bootstrap.
--
-- A business-level membership keeps branch_id null. A branch-scoped
-- membership must point to a branch owned by the same business. Global roles
-- (roles.business_id is null) remain valid for every business, while custom
-- roles must belong to the membership business.

begin;

-- Do not install stricter enforcement over inconsistent historical data.
-- The migration reports samples and aborts without changing or deleting rows.
do $$
declare
  v_cross_business_branch_count bigint;
  v_cross_business_role_count bigint;
  v_cross_business_branch_samples text;
  v_cross_business_role_samples text;
begin
  select count(*)
  into v_cross_business_branch_count
  from public.business_members bm
  join public.branches br on br.id = bm.branch_id
  where bm.branch_id is not null
    and br.business_id <> bm.business_id;

  select string_agg(x.membership_id::text, ', ' order by x.membership_id)
  into v_cross_business_branch_samples
  from (
    select bm.id as membership_id
    from public.business_members bm
    join public.branches br on br.id = bm.branch_id
    where bm.branch_id is not null
      and br.business_id <> bm.business_id
    order by bm.id
    limit 20
  ) x;

  select count(*)
  into v_cross_business_role_count
  from public.business_members bm
  join public.roles r on r.id = bm.role_id
  where r.business_id is not null
    and r.business_id <> bm.business_id;

  select string_agg(x.membership_id::text, ', ' order by x.membership_id)
  into v_cross_business_role_samples
  from (
    select bm.id as membership_id
    from public.business_members bm
    join public.roles r on r.id = bm.role_id
    where r.business_id is not null
      and r.business_id <> bm.business_id
    order by bm.id
    limit 20
  ) x;

  if v_cross_business_branch_count > 0
     or v_cross_business_role_count > 0
  then
    raise exception using
      errcode = '23514',
      message = 'Cannot install business_members scope invariants: existing rows violate tenant ownership',
      detail = format(
        'cross-business branches=%s (membership samples: %s); cross-business custom roles=%s (membership samples: %s)',
        v_cross_business_branch_count,
        coalesce(v_cross_business_branch_samples, 'none'),
        v_cross_business_role_count,
        coalesce(v_cross_business_role_samples, 'none')
      ),
      hint = 'Review and correct the reported development rows explicitly, then re-run this migration.';
  end if;
end;
$$;

create or replace function private.validate_business_member_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.branch_id is not null
     and not exists (
       select 1
       from public.branches br
       where br.id = new.branch_id
         and br.business_id = new.business_id
     )
  then
    raise exception using
      errcode = '23514',
      message = 'business_members.branch_id must belong to business_members.business_id';
  end if;

  if not exists (
    select 1
    from public.roles r
    where r.id = new.role_id
      and (
        r.business_id is null
        or r.business_id = new.business_id
      )
  )
  then
    raise exception using
      errcode = '23514',
      message = 'business_members.role_id must reference a global role or a custom role from the same business';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_business_member_scope() from public;

drop trigger if exists trg_business_members_validate_scope
on public.business_members;

create trigger trg_business_members_validate_scope
before insert or update of business_id, branch_id, role_id
on public.business_members
for each row
execute function private.validate_business_member_scope();

comment on function private.validate_business_member_scope()
is 'Enforces that branch-scoped memberships and custom roles stay inside the membership business.';

-- Keep the invariant intact when ownership is changed from the referenced
-- side. These guards do not prohibit a valid ownership change; they only
-- reject one that would strand existing memberships in another tenant.
create or replace function private.validate_branch_business_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.business_id is distinct from old.business_id
     and exists (
       select 1
       from public.business_members bm
       where bm.branch_id = new.id
         and bm.business_id <> new.business_id
     )
  then
    raise exception using
      errcode = '23514',
      message = 'branches.business_id change would invalidate existing business_members rows';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_branch_business_change() from public;

drop trigger if exists trg_branches_validate_membership_scope
on public.branches;

create trigger trg_branches_validate_membership_scope
before update of business_id
on public.branches
for each row
execute function private.validate_branch_business_change();

comment on function private.validate_branch_business_change()
is 'Prevents branch ownership changes that would make existing memberships cross-business.';

create or replace function private.validate_role_business_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.business_id is distinct from old.business_id
     and new.business_id is not null
     and exists (
       select 1
       from public.business_members bm
       where bm.role_id = new.id
         and bm.business_id <> new.business_id
     )
  then
    raise exception using
      errcode = '23514',
      message = 'roles.business_id change would invalidate existing business_members rows';
  end if;

  return new;
end;
$$;

revoke all on function private.validate_role_business_change() from public;

drop trigger if exists trg_roles_validate_membership_scope
on public.roles;

create trigger trg_roles_validate_membership_scope
before update of business_id
on public.roles
for each row
execute function private.validate_role_business_change();

comment on function private.validate_role_business_change()
is 'Prevents role ownership changes that would make existing memberships cross-business.';

commit;
