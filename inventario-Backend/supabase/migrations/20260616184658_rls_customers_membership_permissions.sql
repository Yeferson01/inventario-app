-- Fase 3.3 - RLS customers with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de customers basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- Esta migración solo afecta public.customers.

begin;

alter table public.customers enable row level security;

-- =========================================================
-- Drop old policies
-- =========================================================

drop policy if exists customers_insert_by_business on public.customers;
drop policy if exists customers_no_delete on public.customers;
drop policy if exists customers_select_by_business on public.customers;
drop policy if exists customers_update_by_business on public.customers;

-- También eliminamos nombres nuevos si se reintenta en local/staging.
drop policy if exists customers_select_allowed on public.customers;
drop policy if exists customers_insert_allowed on public.customers;
drop policy if exists customers_update_allowed on public.customers;
drop policy if exists customers_soft_delete_allowed on public.customers;
drop policy if exists customers_delete_blocked on public.customers;

-- =========================================================
-- SELECT
-- Lectura de clientes requiere customers.read.
-- También permitimos sales.create para POS, porque el cajero
-- puede necesitar buscar/seleccionar cliente durante una venta.
-- =========================================================

create policy customers_select_allowed
on public.customers
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'customers.read')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- =========================================================
-- INSERT
-- Crear clientes requiere customers.create.
-- También permitimos sales.create para crear cliente rápido en POS.
-- =========================================================

create policy customers_insert_allowed
on public.customers
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and (
    private.has_business_permission(business_id, 'customers.create')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- =========================================================
-- UPDATE normal
-- Editar clientes requiere customers.update.
-- Esta policy no permite soft delete porque exige deleted_at is null.
-- =========================================================

create policy customers_update_allowed
on public.customers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'customers.update')
)
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'customers.update')
);

-- =========================================================
-- SOFT DELETE
-- Marcar deleted_at/deleted_by/delete_reason requiere customers.soft_delete.
-- =========================================================

create policy customers_soft_delete_allowed
on public.customers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'customers.soft_delete')
)
with check (
  business_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'customers.soft_delete')
);

-- =========================================================
-- DELETE bloqueado
-- No hard delete. Usar soft delete.
-- =========================================================

create policy customers_delete_blocked
on public.customers
for delete
to authenticated
using (false);

commit;