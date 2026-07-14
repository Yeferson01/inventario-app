-- Fase 2.8 - Multitenancy RLS indexes
-- Objetivo:
-- Agregar índices de soporte para helpers RLS y consultas frecuentes
-- sobre business_members, roles, branches y role_permissions.

begin;

-- =========================================================
-- business_members
-- Usado por:
-- private.is_business_member()
-- private.has_business_permission()
-- private.has_branch_access()
-- private.has_branch_permission()
-- =========================================================

create index if not exists business_members_profile_business_active_idx
on public.business_members (profile_id, business_id)
where deleted_at is null
  and status = 'active';

create index if not exists business_members_business_profile_active_idx
on public.business_members (business_id, profile_id)
where deleted_at is null
  and status = 'active';

create index if not exists business_members_business_branch_active_idx
on public.business_members (business_id, branch_id)
where deleted_at is null
  and status = 'active';

-- =========================================================
-- roles
-- Usado para resolver roles globales/custom y validar role_id.
-- =========================================================

create index if not exists roles_id_business_active_idx
on public.roles (id, business_id)
where deleted_at is null;

create index if not exists roles_business_active_idx
on public.roles (business_id)
where deleted_at is null;

-- =========================================================
-- role_permissions
-- La PK cubre (role_id, permission_id), pero este índice ayuda
-- cuando se busca desde permission_id hacia roles.
-- =========================================================

create index if not exists role_permissions_permission_role_idx
on public.role_permissions (permission_id, role_id);

-- =========================================================
-- branches
-- Usado por consultas por negocio y selector de sucursal.
-- =========================================================

create index if not exists branches_business_active_idx
on public.branches (business_id, status)
where deleted_at is null;

commit;