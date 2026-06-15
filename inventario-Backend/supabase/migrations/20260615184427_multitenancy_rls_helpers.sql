-- Fase 2.5 - Multitenancy RLS helpers
-- Objetivo:
-- Crear funciones helper para policies RLS basadas en:
-- business_members, roles, permissions y branches.
--
-- Nota:
-- No reemplazamos policies existentes todavía.
-- Estas funciones serán usadas en Fase 3 para migrar RLS gradualmente.

begin;

-- =========================================================
-- PRIVATE SCHEMA
-- =========================================================

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to authenticated;
grant usage on schema private to service_role;

comment on schema private
is 'Private schema for internal authorization helpers and security definer functions.';

-- =========================================================
-- Helper: current_profile_id
-- =========================================================

create or replace function private.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid();
$$;

comment on function private.current_profile_id()
is 'Returns the authenticated user id from Supabase Auth. Used as current profile id.';

-- =========================================================
-- Helper: is_business_member
-- =========================================================

create or replace function private.is_business_member(
  p_business_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_business_id is not null
    and auth.uid() is not null
    and exists (
      select 1
      from public.business_members bm
      where bm.business_id = p_business_id
        and bm.profile_id = auth.uid()
        and bm.status = 'active'
        and bm.deleted_at is null
    );
$$;

comment on function private.is_business_member(uuid)
is 'Returns true when the authenticated user is an active member of the given business.';

-- =========================================================
-- Helper: has_business_permission
-- =========================================================

create or replace function private.has_business_permission(
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
      join public.role_permissions rp
        on rp.role_id = r.id
      join public.permissions p
        on p.id = rp.permission_id
      where bm.business_id = p_business_id
        and bm.profile_id = auth.uid()
        and bm.status = 'active'
        and bm.deleted_at is null
        and r.deleted_at is null
        and (r.business_id is null or r.business_id = p_business_id)
        and p.key = p_permission_key
    );
$$;

comment on function private.has_business_permission(uuid, text)
is 'Returns true when the authenticated user has a permission in the given business through active membership and role_permissions.';

-- =========================================================
-- Helper: has_branch_access
-- =========================================================

create or replace function private.has_branch_access(
  p_business_id uuid,
  p_branch_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_business_id is not null
    and auth.uid() is not null
    and exists (
      select 1
      from public.business_members bm
      where bm.business_id = p_business_id
        and bm.profile_id = auth.uid()
        and bm.status = 'active'
        and bm.deleted_at is null
        and (
          bm.branch_id is null
          or bm.branch_id = p_branch_id
        )
    );
$$;

comment on function private.has_branch_access(uuid, uuid)
is 'Returns true when the authenticated user has business-level access or access to the given branch.';

-- =========================================================
-- Helper: has_branch_permission
-- =========================================================

create or replace function private.has_branch_permission(
  p_business_id uuid,
  p_branch_id uuid,
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
      join public.role_permissions rp
        on rp.role_id = r.id
      join public.permissions p
        on p.id = rp.permission_id
      where bm.business_id = p_business_id
        and bm.profile_id = auth.uid()
        and bm.status = 'active'
        and bm.deleted_at is null
        and r.deleted_at is null
        and (r.business_id is null or r.business_id = p_business_id)
        and p.key = p_permission_key
        and (
          bm.branch_id is null
          or bm.branch_id = p_branch_id
        )
    );
$$;

comment on function private.has_branch_permission(uuid, uuid, text)
is 'Returns true when the authenticated user has a permission in a business and either business-level or branch-level access.';

-- =========================================================
-- Function privileges
-- =========================================================

revoke all on function private.current_profile_id() from public;
revoke all on function private.is_business_member(uuid) from public;
revoke all on function private.has_business_permission(uuid, text) from public;
revoke all on function private.has_branch_access(uuid, uuid) from public;
revoke all on function private.has_branch_permission(uuid, uuid, text) from public;

grant execute on function private.current_profile_id() to authenticated;
grant execute on function private.is_business_member(uuid) to authenticated;
grant execute on function private.has_business_permission(uuid, text) to authenticated;
grant execute on function private.has_branch_access(uuid, uuid) to authenticated;
grant execute on function private.has_branch_permission(uuid, uuid, text) to authenticated;

grant execute on function private.current_profile_id() to service_role;
grant execute on function private.is_business_member(uuid) to service_role;
grant execute on function private.has_business_permission(uuid, text) to service_role;
grant execute on function private.has_branch_access(uuid, uuid) to service_role;
grant execute on function private.has_branch_permission(uuid, uuid, text) to service_role;

commit;