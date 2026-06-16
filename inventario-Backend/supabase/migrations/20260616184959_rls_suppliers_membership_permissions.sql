-- Fase 3.4 - RLS suppliers with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de suppliers basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- Esta migración solo afecta public.suppliers.

begin;

alter table public.suppliers enable row level security;

-- =========================================================
-- Drop old policies
-- =========================================================

drop policy if exists suppliers_insert_by_business on public.suppliers;
drop policy if exists suppliers_no_delete on public.suppliers;
drop policy if exists suppliers_select_by_business on public.suppliers;
drop policy if exists suppliers_update_by_business on public.suppliers;

-- También eliminamos nombres nuevos si se reintenta en local/staging.
drop policy if exists suppliers_select_allowed on public.suppliers;
drop policy if exists suppliers_insert_allowed on public.suppliers;
drop policy if exists suppliers_update_allowed on public.suppliers;
drop policy if exists suppliers_soft_delete_allowed on public.suppliers;
drop policy if exists suppliers_delete_blocked on public.suppliers;

-- =========================================================
-- SELECT
-- Lectura de proveedores requiere inventory.purchase o inventory.read.
-- inventory.purchase permite gestionar compras/reposición.
-- inventory.read permite consultar contexto de inventario.
-- =========================================================

create policy suppliers_select_allowed
on public.suppliers
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'inventory.purchase')
    or private.has_business_permission(business_id, 'inventory.read')
  )
);

-- =========================================================
-- INSERT
-- Crear proveedores requiere inventory.purchase.
-- =========================================================

create policy suppliers_insert_allowed
on public.suppliers
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'inventory.purchase')
);

-- =========================================================
-- UPDATE normal
-- Editar proveedores requiere inventory.purchase.
-- Esta policy no permite soft delete porque exige deleted_at is null.
-- =========================================================

create policy suppliers_update_allowed
on public.suppliers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'inventory.purchase')
)
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'inventory.purchase')
);

-- =========================================================
-- SOFT DELETE
-- Borrado lógico de proveedores requiere inventory.purchase.
-- Más adelante, si quieres separar este permiso, podemos agregar
-- suppliers.soft_delete o purchases.suppliers.manage.
-- =========================================================

create policy suppliers_soft_delete_allowed
on public.suppliers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'inventory.purchase')
)
with check (
  business_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'inventory.purchase')
);

-- =========================================================
-- DELETE bloqueado
-- No hard delete. Usar soft delete.
-- =========================================================

create policy suppliers_delete_blocked
on public.suppliers
for delete
to authenticated
using (false);

commit;