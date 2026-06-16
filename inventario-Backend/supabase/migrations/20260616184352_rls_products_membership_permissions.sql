-- Fase 3.2 - RLS products with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de products basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- Esta migración solo afecta public.products.
-- No cambia todavía stock_quantity ni modelo de inventario.

begin;

alter table public.products enable row level security;

-- =========================================================
-- Drop old policies
-- =========================================================

drop policy if exists products_insert_by_business on public.products;
drop policy if exists products_no_delete on public.products;
drop policy if exists products_select_by_business on public.products;
drop policy if exists products_update_by_business on public.products;

-- También eliminamos nombres nuevos si se reintenta en local/staging.
drop policy if exists products_select_allowed on public.products;
drop policy if exists products_insert_allowed on public.products;
drop policy if exists products_update_allowed on public.products;
drop policy if exists products_soft_delete_allowed on public.products;
drop policy if exists products_delete_blocked on public.products;

-- =========================================================
-- SELECT
-- Lectura permitida a miembros con permiso products.read.
-- También permitimos lectura a roles con sales.create para POS,
-- aunque actualmente cashier ya tiene products.read.
-- =========================================================

create policy products_select_allowed
on public.products
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'products.read')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- =========================================================
-- INSERT
-- Crear productos requiere products.create.
-- =========================================================

create policy products_insert_allowed
on public.products
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'products.create')
);

-- =========================================================
-- UPDATE normal
-- Editar productos requiere products.update.
-- Esta policy NO permite soft delete porque exige deleted_at is null
-- también en WITH CHECK.
-- =========================================================

create policy products_update_allowed
on public.products
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'products.update')
)
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'products.update')
);

-- =========================================================
-- SOFT DELETE
-- Marcar deleted_at/deleted_by/delete_reason requiere products.soft_delete.
-- No hay hard delete.
-- =========================================================

create policy products_soft_delete_allowed
on public.products
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'products.soft_delete')
)
with check (
  business_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'products.soft_delete')
);

-- =========================================================
-- DELETE bloqueado
-- No hard delete. Usar soft delete.
-- =========================================================

create policy products_delete_blocked
on public.products
for delete
to authenticated
using (false);

commit;