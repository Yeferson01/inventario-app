-- Fase 3.10 - RLS businesses and devices with membership and permissions
-- Objetivo:
-- Migrar las últimas policies antiguas detectadas:
-- - businesses
-- - devices
--
-- También agregamos permisos específicos para devices/assets.
--
-- Nota:
-- legacy_users queda cerrado por defecto, sin SELECT policy.

begin;

-- =========================================================
-- 1. Agregar permisos específicos para devices/assets
-- =========================================================

insert into public.permissions (key, description)
values
  ('devices.read', 'Read business devices/assets.'),
  ('devices.create', 'Create business devices/assets.'),
  ('devices.update', 'Update business devices/assets.'),
  ('devices.soft_delete', 'Soft delete business devices/assets.')
on conflict (key) do update
set description = excluded.description;

-- Owner recibe todos los permisos nuevos.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in (
    'devices.read',
    'devices.create',
    'devices.update',
    'devices.soft_delete'
  )
where r.business_id is null
  and r.name = 'owner'
on conflict (role_id, permission_id) do nothing;

-- Admin recibe todos los permisos de devices.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in (
    'devices.read',
    'devices.create',
    'devices.update',
    'devices.soft_delete'
  )
where r.business_id is null
  and r.name = 'admin'
on conflict (role_id, permission_id) do nothing;

-- Technician puede leer y actualizar devices/assets.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in (
    'devices.read',
    'devices.update'
  )
where r.business_id is null
  and r.name = 'technician'
on conflict (role_id, permission_id) do nothing;

-- Warehouse puede leer devices/assets si están relacionados con inventario/activos.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p
  on p.key in (
    'devices.read'
  )
where r.business_id is null
  and r.name = 'warehouse'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 2. RLS businesses
-- =========================================================

alter table public.businesses enable row level security;

drop policy if exists businesses_select_by_owner on public.businesses;
drop policy if exists businesses_update_by_owner on public.businesses;

drop policy if exists businesses_select_allowed on public.businesses;
drop policy if exists businesses_insert_authenticated on public.businesses;
drop policy if exists businesses_update_allowed on public.businesses;
drop policy if exists businesses_delete_blocked on public.businesses;

-- Mantener compatibilidad con el flujo actual de creación de negocio.
-- Más adelante lo reemplazaremos por un RPC create_business que también cree:
-- business_members, branch principal y rol owner.
drop policy if exists authenticated_users_can_create_business on public.businesses;

create policy businesses_insert_authenticated
on public.businesses
for insert
to authenticated
with check (true);

-- Lectura para miembros activos del negocio.
create policy businesses_select_allowed
on public.businesses
for select
to authenticated
using (
  deleted_at is null
  and private.is_business_member(id)
);

-- Update de configuración de negocio.
create policy businesses_update_allowed
on public.businesses
for update
to authenticated
using (
  deleted_at is null
  and private.has_business_permission(id, 'settings.business')
)
with check (
  private.has_business_permission(id, 'settings.business')
);

-- No hard delete.
create policy businesses_delete_blocked
on public.businesses
for delete
to authenticated
using (false);

-- =========================================================
-- 3. RLS devices/assets
-- =========================================================

alter table public.devices enable row level security;

drop policy if exists devices_insert_by_business on public.devices;
drop policy if exists devices_select_by_business on public.devices;
drop policy if exists devices_update_by_business on public.devices;

drop policy if exists devices_select_allowed on public.devices;
drop policy if exists devices_insert_allowed on public.devices;
drop policy if exists devices_update_allowed on public.devices;
drop policy if exists devices_soft_delete_allowed on public.devices;
drop policy if exists devices_delete_blocked on public.devices;

-- SELECT: requiere devices.read.
create policy devices_select_allowed
on public.devices
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'devices.read')
);

-- INSERT: requiere devices.create.
create policy devices_insert_allowed
on public.devices
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'devices.create')
);

-- UPDATE normal: requiere devices.update.
create policy devices_update_allowed
on public.devices
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'devices.update')
)
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'devices.update')
);

-- SOFT DELETE: requiere devices.soft_delete.
create policy devices_soft_delete_allowed
on public.devices
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'devices.soft_delete')
)
with check (
  business_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'devices.soft_delete')
);

-- No hard delete.
create policy devices_delete_blocked
on public.devices
for delete
to authenticated
using (false);

commit;