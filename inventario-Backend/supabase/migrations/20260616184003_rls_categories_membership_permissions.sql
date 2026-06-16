-- Fase 3.1 - RLS categories with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de categories basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- Esta migración solo afecta public.categories.

begin;

alter table public.categories enable row level security;

-- =========================================================
-- Drop old policies
-- =========================================================

drop policy if exists categories_insert_by_business on public.categories;
drop policy if exists categories_no_delete on public.categories;
drop policy if exists categories_select_by_business on public.categories;
drop policy if exists categories_update_by_business on public.categories;

-- También eliminamos nombres nuevos si se reintenta en local/staging.
drop policy if exists categories_select_allowed on public.categories;
drop policy if exists categories_insert_allowed on public.categories;
drop policy if exists categories_update_allowed on public.categories;
drop policy if exists categories_delete_blocked on public.categories;

-- =========================================================
-- SELECT
-- Miembros del negocio pueden leer categorías activas.
-- También usuarios con products.read.
-- =========================================================

create policy categories_select_allowed
on public.categories
for select
to authenticated
using (
  deleted_at is null
  and (
    private.is_business_member(business_id)
    or private.has_business_permission(business_id, 'products.read')
  )
);

-- =========================================================
-- INSERT
-- Crear categorías requiere products.create.
-- =========================================================

create policy categories_insert_allowed
on public.categories
for insert
to authenticated
with check (
  business_id is not null
  and private.has_business_permission(business_id, 'products.create')
);

-- =========================================================
-- UPDATE
-- Editar categorías requiere products.update.
-- No se permite actualizar registros ya eliminados.
-- =========================================================

create policy categories_update_allowed
on public.categories
for update
to authenticated
using (
  deleted_at is null
  and private.has_business_permission(business_id, 'products.update')
)
with check (
  business_id is not null
  and private.has_business_permission(business_id, 'products.update')
);

-- =========================================================
-- DELETE bloqueado
-- No hard delete. Usar soft delete con deleted_at/deleted_by/delete_reason.
-- =========================================================

create policy categories_delete_blocked
on public.categories
for delete
to authenticated
using (false);

commit;