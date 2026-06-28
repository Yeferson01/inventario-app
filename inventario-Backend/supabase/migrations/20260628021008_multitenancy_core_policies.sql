-- Fase 2.6 - Multitenancy core policies
-- Objetivo:
-- Crear policies mínimas para las tablas nuevas de multitenancy:
-- branches, roles, permissions, role_permissions, business_members.
--
-- Nota:
-- No se reemplazan todavía las policies antiguas de products, sales, etc.
-- Esta fase solo abre acceso controlado a las tablas nuevas.

begin;

-- =========================================================
-- Ensure RLS is enabled
-- =========================================================

alter table public.branches enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.business_members enable row level security;

-- =========================================================
-- PERMISSIONS
-- Catálogo global de permisos.
-- Lectura permitida a usuarios autenticados.
-- Escritura solo por migraciones/service_role.
-- =========================================================

drop policy if exists permissions_select_authenticated on public.permissions;

create policy permissions_select_authenticated
on public.permissions
for select
to authenticated
using (true);

-- =========================================================
-- ROLES
-- Roles globales: visibles para autenticados.
-- Roles de negocio: visibles para miembros del negocio.
-- Crear/editar roles custom: requiere members.update_role o settings.business.
-- No se permite crear roles de sistema desde cliente.
-- =========================================================

drop policy if exists roles_select_allowed on public.roles;
drop policy if exists roles_insert_custom_allowed on public.roles;
drop policy if exists roles_update_custom_allowed on public.roles;

create policy roles_select_allowed
on public.roles
for select
to authenticated
using (
  deleted_at is null
  and (
    business_id is null
    or private.is_business_member(business_id)
  )
);

create policy roles_insert_custom_allowed
on public.roles
for insert
to authenticated
with check (
  business_id is not null
  and is_system_role = false
  and (
    private.has_business_permission(business_id, 'members.update_role')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

create policy roles_update_custom_allowed
on public.roles
for update
to authenticated
using (
  business_id is not null
  and deleted_at is null
  and is_system_role = false
  and (
    private.has_business_permission(business_id, 'members.update_role')
    or private.has_business_permission(business_id, 'settings.business')
  )
)
with check (
  business_id is not null
  and is_system_role = false
  and (
    private.has_business_permission(business_id, 'members.update_role')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

-- No policy DELETE para roles.
-- Los roles custom deben soft-deletearse con deleted_at en una fase futura/RPC controlada.

-- =========================================================
-- ROLE PERMISSIONS
-- Lectura:
-- - permisos de roles globales visibles para autenticados.
-- - permisos de roles custom visibles para miembros del negocio.
--
-- Escritura:
-- - solo para roles custom del negocio con members.update_role/settings.business.
-- =========================================================

drop policy if exists role_permissions_select_allowed on public.role_permissions;
drop policy if exists role_permissions_insert_allowed on public.role_permissions;
drop policy if exists role_permissions_delete_allowed on public.role_permissions;

create policy role_permissions_select_allowed
on public.role_permissions
for select
to authenticated
using (
  exists (
    select 1
    from public.roles r
    where r.id = role_permissions.role_id
      and r.deleted_at is null
      and (
        r.business_id is null
        or private.is_business_member(r.business_id)
      )
  )
);

create policy role_permissions_insert_allowed
on public.role_permissions
for insert
to authenticated
with check (
  exists (
    select 1
    from public.roles r
    where r.id = role_permissions.role_id
      and r.business_id is not null
      and r.deleted_at is null
      and r.is_system_role = false
      and (
        private.has_business_permission(r.business_id, 'members.update_role')
        or private.has_business_permission(r.business_id, 'settings.business')
      )
  )
);

create policy role_permissions_delete_allowed
on public.role_permissions
for delete
to authenticated
using (
  exists (
    select 1
    from public.roles r
    where r.id = role_permissions.role_id
      and r.business_id is not null
      and r.deleted_at is null
      and r.is_system_role = false
      and (
        private.has_business_permission(r.business_id, 'members.update_role')
        or private.has_business_permission(r.business_id, 'settings.business')
      )
  )
);

-- =========================================================
-- BRANCHES
-- Lectura: miembros activos del negocio.
-- Crear/editar: permiso settings.branches.
-- No DELETE físico.
-- =========================================================

drop policy if exists branches_select_members on public.branches;
drop policy if exists branches_insert_allowed on public.branches;
drop policy if exists branches_update_allowed on public.branches;

create policy branches_select_members
on public.branches
for select
to authenticated
using (
  deleted_at is null
  and private.is_business_member(business_id)
);

create policy branches_insert_allowed
on public.branches
for insert
to authenticated
with check (
  private.has_business_permission(business_id, 'settings.branches')
);

create policy branches_update_allowed
on public.branches
for update
to authenticated
using (
  deleted_at is null
  and private.has_business_permission(business_id, 'settings.branches')
)
with check (
  private.has_business_permission(business_id, 'settings.branches')
);

-- No policy DELETE para branches.
-- Usar soft delete con deleted_at/deleted_by/delete_reason.

-- =========================================================
-- BUSINESS MEMBERS
-- Lectura:
-- - cada usuario puede ver sus propias memberships.
-- - admins/owners pueden ver miembros si tienen permisos de gestión.
--
-- Insert:
-- - invitar/agregar miembros requiere members.invite.
--
-- Update:
-- - cambiar rol requiere members.update_role.
-- - suspender requiere members.suspend.
--
-- No DELETE físico.
-- =========================================================

drop policy if exists business_members_select_allowed on public.business_members;
drop policy if exists business_members_insert_allowed on public.business_members;
drop policy if exists business_members_update_allowed on public.business_members;

create policy business_members_select_allowed
on public.business_members
for select
to authenticated
using (
  deleted_at is null
  and (
    profile_id = auth.uid()
    or private.has_business_permission(business_id, 'members.invite')
    or private.has_business_permission(business_id, 'members.update_role')
    or private.has_business_permission(business_id, 'members.suspend')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

create policy business_members_insert_allowed
on public.business_members
for insert
to authenticated
with check (
  deleted_at is null
  and private.has_business_permission(business_id, 'members.invite')
);

create policy business_members_update_allowed
on public.business_members
for update
to authenticated
using (
  deleted_at is null
  and (
    private.has_business_permission(business_id, 'members.update_role')
    or private.has_business_permission(business_id, 'members.suspend')
    or private.has_business_permission(business_id, 'settings.business')
  )
)
with check (
  private.has_business_permission(business_id, 'members.update_role')
  or private.has_business_permission(business_id, 'members.suspend')
  or private.has_business_permission(business_id, 'settings.business')
);

-- No policy DELETE para business_members.
-- Usar status = 'removed' y deleted_at cuando corresponda.

commit;