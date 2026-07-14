-- Fase 3.5 - RLS purchases and purchase_items with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de purchases y purchase_items basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- purchase_items no tiene business_id directo, por eso resolvemos el business_id
-- desde public.purchases usando helper privado.

begin;

-- =========================================================
-- Helper: private.purchase_business_id
-- =========================================================

create or replace function private.purchase_business_id(
  p_purchase_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.business_id
  from public.purchases p
  where p.id = p_purchase_id
  limit 1;
$$;

comment on function private.purchase_business_id(uuid)
is 'Returns the business_id for a purchase. Used by RLS policies on purchase_items.';

revoke all on function private.purchase_business_id(uuid) from public;
grant execute on function private.purchase_business_id(uuid) to authenticated;
grant execute on function private.purchase_business_id(uuid) to service_role;

-- =========================================================
-- Enable RLS
-- =========================================================

alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;

-- =========================================================
-- Drop old policies: purchases
-- =========================================================

drop policy if exists purchases_insert_by_business on public.purchases;
drop policy if exists purchases_no_delete on public.purchases;
drop policy if exists purchases_select_by_business on public.purchases;
drop policy if exists purchases_update_by_business on public.purchases;

drop policy if exists purchases_select_allowed on public.purchases;
drop policy if exists purchases_insert_allowed on public.purchases;
drop policy if exists purchases_update_allowed on public.purchases;
drop policy if exists purchases_soft_delete_allowed on public.purchases;
drop policy if exists purchases_delete_blocked on public.purchases;

-- =========================================================
-- Drop old policies: purchase_items
-- =========================================================

drop policy if exists purchase_items_insert_by_business on public.purchase_items;
drop policy if exists purchase_items_select_by_business on public.purchase_items;

drop policy if exists purchase_items_select_allowed on public.purchase_items;
drop policy if exists purchase_items_insert_allowed on public.purchase_items;
drop policy if exists purchase_items_update_allowed on public.purchase_items;
drop policy if exists purchase_items_delete_blocked on public.purchase_items;

-- =========================================================
-- PURCHASES: SELECT
-- Ver compras requiere inventory.purchase o reports.inventory.
-- =========================================================

create policy purchases_select_allowed
on public.purchases
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'inventory.purchase')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

-- =========================================================
-- PURCHASES: INSERT
-- Crear compras requiere inventory.purchase.
-- =========================================================

create policy purchases_insert_allowed
on public.purchases
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'inventory.purchase')
);

-- =========================================================
-- PURCHASES: UPDATE normal
-- Editar compras requiere inventory.purchase.
-- Esta policy no permite soft delete porque exige deleted_at is null.
-- =========================================================

create policy purchases_update_allowed
on public.purchases
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
-- PURCHASES: SOFT DELETE
-- Borrado lógico de compras requiere inventory.purchase.
-- Más adelante podremos reemplazarlo por un flujo de anulación controlada.
-- =========================================================

create policy purchases_soft_delete_allowed
on public.purchases
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
-- PURCHASES: DELETE bloqueado
-- No hard delete.
-- =========================================================

create policy purchases_delete_blocked
on public.purchases
for delete
to authenticated
using (false);

-- =========================================================
-- PURCHASE_ITEMS: SELECT
-- Ver items requiere permiso sobre el negocio de la compra.
-- =========================================================

create policy purchase_items_select_allowed
on public.purchase_items
for select
to authenticated
using (
  purchase_id is not null
  and (
    private.has_business_permission(private.purchase_business_id(purchase_id), 'inventory.purchase')
    or private.has_business_permission(private.purchase_business_id(purchase_id), 'reports.inventory')
  )
);

-- =========================================================
-- PURCHASE_ITEMS: INSERT
-- Crear items requiere inventory.purchase sobre el negocio de la compra.
-- =========================================================

create policy purchase_items_insert_allowed
on public.purchase_items
for insert
to authenticated
with check (
  purchase_id is not null
  and private.has_business_permission(private.purchase_business_id(purchase_id), 'inventory.purchase')
);

-- =========================================================
-- PURCHASE_ITEMS: UPDATE
-- Permitimos update por ahora con inventory.purchase.
-- Más adelante, cuando implementemos estados/anulación de compras,
-- podemos restringirlo más.
-- =========================================================

create policy purchase_items_update_allowed
on public.purchase_items
for update
to authenticated
using (
  purchase_id is not null
  and private.has_business_permission(private.purchase_business_id(purchase_id), 'inventory.purchase')
)
with check (
  purchase_id is not null
  and private.has_business_permission(private.purchase_business_id(purchase_id), 'inventory.purchase')
);

-- =========================================================
-- PURCHASE_ITEMS: DELETE bloqueado
-- No hard delete. Las correcciones deben hacerse por anulación/ajuste.
-- =========================================================

create policy purchase_items_delete_blocked
on public.purchase_items
for delete
to authenticated
using (false);

commit;