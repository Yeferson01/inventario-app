-- Fase 3.6 - RLS sales and sale_items with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de sales y sale_items basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- Esta migración solo afecta public.sales y public.sale_items.
-- No implementa todavía caja, pagos separados, recibos, devoluciones ni branch_id.

begin;

-- =========================================================
-- Helper: private.sale_business_id
-- =========================================================

create or replace function private.sale_business_id(
  p_sale_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.business_id
  from public.sales s
  where s.id = p_sale_id
  limit 1;
$$;

comment on function private.sale_business_id(uuid)
is 'Returns the business_id for a sale. Used by RLS policies on sale_items.';

revoke all on function private.sale_business_id(uuid) from public;
grant execute on function private.sale_business_id(uuid) to authenticated;
grant execute on function private.sale_business_id(uuid) to service_role;

-- =========================================================
-- Enable RLS
-- =========================================================

alter table public.sales enable row level security;
alter table public.sale_items enable row level security;

-- =========================================================
-- Drop old policies: sales
-- =========================================================

drop policy if exists sales_insert_by_business on public.sales;
drop policy if exists sales_no_delete on public.sales;
drop policy if exists sales_select_by_business on public.sales;
drop policy if exists sales_update_by_business on public.sales;

drop policy if exists sales_select_allowed on public.sales;
drop policy if exists sales_insert_allowed on public.sales;
drop policy if exists sales_update_allowed on public.sales;
drop policy if exists sales_soft_delete_allowed on public.sales;
drop policy if exists sales_delete_blocked on public.sales;

-- =========================================================
-- Drop old policies: sale_items
-- =========================================================

drop policy if exists sale_items_insert_by_business on public.sale_items;
drop policy if exists sale_items_select_by_business on public.sale_items;

drop policy if exists sale_items_select_allowed on public.sale_items;
drop policy if exists sale_items_insert_allowed on public.sale_items;
drop policy if exists sale_items_update_allowed on public.sale_items;
drop policy if exists sale_items_delete_blocked on public.sale_items;

-- =========================================================
-- SALES: SELECT
-- Ver ventas requiere sales.read, reports.sales o cash.read.
-- sales.create también permite ver ventas propias/operativas desde POS.
-- =========================================================

create policy sales_select_allowed
on public.sales
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'sales.read')
    or private.has_business_permission(business_id, 'reports.sales')
    or private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- =========================================================
-- SALES: INSERT
-- Crear ventas requiere sales.create.
-- =========================================================

create policy sales_insert_allowed
on public.sales
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'sales.create')
);

-- =========================================================
-- SALES: UPDATE
-- Por ahora permitimos updates controlados a roles con sales.void,
-- sales.refund o sales.create.
--
-- Esto conserva compatibilidad durante desarrollo.
-- Más adelante, cuando existan cash_sessions, sale_payments, voided_at,
-- sale_returns y receipt_sequences, restringiremos esta policy.
-- =========================================================

create policy sales_update_allowed
on public.sales
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'sales.create')
  )
)
with check (
  business_id is not null
  and (
    private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- =========================================================
-- SALES: SOFT DELETE
-- No es el flujo final recomendado para ventas.
-- En POS profesional se usará anulación/devolución.
-- Mientras tanto, solo sales.void puede marcar deleted_at.
-- =========================================================

create policy sales_soft_delete_allowed
on public.sales
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'sales.void')
)
with check (
  business_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'sales.void')
);

-- =========================================================
-- SALES: DELETE bloqueado
-- No hard delete.
-- =========================================================

create policy sales_delete_blocked
on public.sales
for delete
to authenticated
using (false);

-- =========================================================
-- SALE_ITEMS: SELECT
-- Ver items requiere permiso sobre el negocio de la venta.
-- =========================================================

create policy sale_items_select_allowed
on public.sale_items
for select
to authenticated
using (
  sale_id is not null
  and (
    private.has_business_permission(private.sale_business_id(sale_id), 'sales.read')
    or private.has_business_permission(private.sale_business_id(sale_id), 'reports.sales')
    or private.has_business_permission(private.sale_business_id(sale_id), 'cash.read')
    or private.has_business_permission(private.sale_business_id(sale_id), 'sales.create')
  )
);

-- =========================================================
-- SALE_ITEMS: INSERT
-- Crear items de venta requiere sales.create sobre el negocio de la venta.
-- =========================================================

create policy sale_items_insert_allowed
on public.sale_items
for insert
to authenticated
with check (
  sale_id is not null
  and private.has_business_permission(private.sale_business_id(sale_id), 'sales.create')
);

-- =========================================================
-- SALE_ITEMS: UPDATE
-- Permitimos update temporal durante desarrollo para sales.create,
-- sales.void o sales.refund.
-- Más adelante se restringirá: una venta finalizada no debe editarse;
-- se debe anular, devolver o crear ajuste.
-- =========================================================

create policy sale_items_update_allowed
on public.sale_items
for update
to authenticated
using (
  sale_id is not null
  and (
    private.has_business_permission(private.sale_business_id(sale_id), 'sales.create')
    or private.has_business_permission(private.sale_business_id(sale_id), 'sales.void')
    or private.has_business_permission(private.sale_business_id(sale_id), 'sales.refund')
  )
)
with check (
  sale_id is not null
  and (
    private.has_business_permission(private.sale_business_id(sale_id), 'sales.create')
    or private.has_business_permission(private.sale_business_id(sale_id), 'sales.void')
    or private.has_business_permission(private.sale_business_id(sale_id), 'sales.refund')
  )
);

-- =========================================================
-- SALE_ITEMS: DELETE bloqueado
-- No hard delete.
-- =========================================================

create policy sale_items_delete_blocked
on public.sale_items
for delete
to authenticated
using (false);

commit;