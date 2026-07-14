-- Fase 2.1 - Multitenancy core tables
-- Objetivo:
-- Crear la base profesional de multitenancy:
-- branches, roles, permissions, role_permissions, business_members.
--
-- Nota:
-- No se reemplazan policies existentes todavía.
-- No se elimina profiles.business_id ni profiles.role todavía.

begin;

-- =========================================================
-- BRANCHES
-- =========================================================

create table if not exists public.branches (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete restrict,
  name text not null,
  address text,
  phone text,
  status text not null default 'active',
  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,
  version integer not null default 1,
  sync_status text not null default 'synced',

  constraint branches_status_check
    check (status in ('active', 'inactive')),

  constraint branches_version_positive
    check (version >= 1),

  constraint branches_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

create unique index if not exists branches_business_name_active_unique
on public.branches (business_id, lower(name))
where deleted_at is null;

comment on table public.branches
is 'Business branches or physical locations for POS, inventory and cash operations.';

comment on column public.branches.business_id
is 'Business tenant that owns this branch.';

comment on column public.branches.status
is 'Branch lifecycle status. Soft delete uses deleted_at.';

-- =========================================================
-- ROLES
-- =========================================================

create table if not exists public.roles (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid references public.businesses(id) on delete cascade,
  name text not null,
  description text,
  is_system_role boolean not null default false,
  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  constraint roles_name_not_blank
    check (length(trim(name)) > 0)
);

create unique index if not exists roles_business_name_active_unique
on public.roles (coalesce(business_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(name))
where deleted_at is null;

comment on table public.roles
is 'Roles for system-level and business-specific authorization.';

comment on column public.roles.business_id
is 'Null means global/system role. Non-null means custom role for a business.';

comment on column public.roles.is_system_role
is 'True for roles managed by the platform.';

-- =========================================================
-- PERMISSIONS
-- =========================================================

create table if not exists public.permissions (
  id uuid primary key default extensions.gen_random_uuid(),
  key text not null unique,
  description text,
  created_at timestamp without time zone default now(),

  constraint permissions_key_not_blank
    check (length(trim(key)) > 0)
);

comment on table public.permissions
is 'Global permission catalog. Users should not edit this table directly.';

comment on column public.permissions.key
is 'Stable permission key, e.g. products.read or sales.create.';

-- =========================================================
-- ROLE PERMISSIONS
-- =========================================================

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  created_at timestamp without time zone default now(),
  created_by uuid references public.profiles(id) on delete set null,

  primary key (role_id, permission_id)
);

comment on table public.role_permissions
is 'Many-to-many relationship between roles and permissions.';

-- =========================================================
-- BUSINESS MEMBERS
-- =========================================================

create table if not exists public.business_members (
  id uuid primary key default extensions.gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  role_id uuid not null references public.roles(id) on delete restrict,
  status text not null default 'active',
  invited_by uuid references public.profiles(id) on delete set null,
  invited_at timestamp without time zone,
  accepted_at timestamp without time zone,
  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  constraint business_members_status_check
    check (status in ('invited', 'active', 'suspended', 'removed'))
);

create unique index if not exists business_members_unique_active
on public.business_members (
  business_id,
  profile_id,
  coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid)
)
where deleted_at is null
  and status <> 'removed';

comment on table public.business_members
is 'Memberships connecting profiles to businesses, optional branches and roles.';

comment on column public.business_members.branch_id
is 'Null means membership applies at business level. Non-null limits membership to a branch.';

comment on column public.business_members.status
is 'Membership lifecycle status. Removed memberships should remain for audit/history.';

-- =========================================================
-- UPDATED_AT TRIGGERS
-- =========================================================

drop trigger if exists trg_branches_updated_at on public.branches;
create trigger trg_branches_updated_at
before update on public.branches
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_roles_updated_at on public.roles;
create trigger trg_roles_updated_at
before update on public.roles
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_business_members_updated_at on public.business_members;
create trigger trg_business_members_updated_at
before update on public.business_members
for each row
execute function public.update_updated_at_column();

-- =========================================================
-- VERSION TRIGGERS
-- =========================================================

drop trigger if exists trg_branches_increment_version on public.branches;
create trigger trg_branches_increment_version
before update on public.branches
for each row
execute function public.increment_row_version();

commit;