-- Fase 3.7 - RLS inventory_movements with membership and permissions
-- Objetivo:
-- Reemplazar policies antiguas de inventory_movements basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- inventory_movements es ledger inmutable:
-- - SELECT controlado por permisos.
-- - INSERT controlado por tipo de movimiento.
-- - UPDATE no permitido por RLS ni por trigger.
-- - DELETE bloqueado por RLS y por trigger.

begin;

alter table public.inventory_movements enable row level security;

-- =========================================================
-- Drop old policies
-- =========================================================

drop policy if exists inventory_movements_insert_by_business on public.inventory_movements;
drop policy if exists inventory_movements_select_by_business on public.inventory_movements;

-- También eliminamos nombres nuevos si se reintenta en local/staging.
drop policy if exists inventory_movements_select_allowed on public.inventory_movements;
drop policy if exists inventory_movements_insert_allowed on public.inventory_movements;
drop policy if exists inventory_movements_update_blocked on public.inventory_movements;
drop policy if exists inventory_movements_delete_blocked on public.inventory_movements;

-- =========================================================
-- SELECT
-- Ver movimientos requiere inventory.read o reports.inventory.
-- =========================================================

create policy inventory_movements_select_allowed
on public.inventory_movements
for select
to authenticated
using (
  business_id is not null
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

-- =========================================================
-- INSERT
-- Crear movimientos depende del tipo de origen.
--
-- Compatibilidad:
-- - movement_type existe en el esquema inicial.
-- - source_type fue agregado en Fase 1.6.
-- - Usamos coalesce(source_type, movement_type::text) para soportar ambos.
-- =========================================================

create policy inventory_movements_insert_allowed
on public.inventory_movements
for insert
to authenticated
with check (
  business_id is not null
  and (
    -- Venta POS: descuento de stock por venta.
    (
      coalesce(source_type, movement_type::text) = 'sale'
      and private.has_business_permission(business_id, 'sales.create')
    )

    or

    -- Compra/recepción de stock.
    (
      coalesce(source_type, movement_type::text) = 'purchase'
      and private.has_business_permission(business_id, 'inventory.purchase')
    )

    or

    -- Ajustes manuales, pérdidas o reversos.
    (
      coalesce(source_type, movement_type::text) in ('manual_adjustment', 'loss', 'reversal')
      and private.has_business_permission(business_id, 'inventory.adjust')
    )

    or

    -- Devoluciones/retornos.
    (
      coalesce(source_type, movement_type::text) = 'return'
      and (
        private.has_business_permission(business_id, 'sales.refund')
        or private.has_business_permission(business_id, 'inventory.adjust')
      )
    )

    or

    -- Conteos físicos futuros.
    (
      coalesce(source_type, movement_type::text) = 'stock_count'
      and private.has_business_permission(business_id, 'inventory.count')
    )

    or

    -- Transferencias futuras entre sucursales.
    (
      coalesce(source_type, movement_type::text) = 'transfer'
      and private.has_business_permission(business_id, 'inventory.transfer')
    )

    or

    -- Compatibilidad temporal para movimientos antiguos o inserts aún no adaptados.
    -- Más adelante eliminaremos esta rama cuando el backend/app siempre envíe source_type.
    (
      coalesce(source_type, movement_type::text) is null
      and (
        private.has_business_permission(business_id, 'inventory.adjust')
        or private.has_business_permission(business_id, 'inventory.purchase')
        or private.has_business_permission(business_id, 'sales.create')
      )
    )
  )
);

-- =========================================================
-- UPDATE bloqueado
-- No creamos policy UPDATE.
-- Además, ya existe trigger prevent_inventory_movements_update().
-- =========================================================

-- =========================================================
-- DELETE bloqueado
-- No hard delete.
-- Además, ya existe trigger prevent_inventory_movements_delete().
-- =========================================================

create policy inventory_movements_delete_blocked
on public.inventory_movements
for delete
to authenticated
using (false);

commit;