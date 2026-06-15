-- Fase 1.7 - Foundation validate constraints
-- Objetivo:
-- Validar constraints creadas como NOT VALID durante Fase 1.
--
-- Esta migración no agrega columnas ni cambia datos.
-- Solo confirma que los datos existentes cumplen las reglas.

begin;

-- =========================================================
-- Catalog tables
-- =========================================================

alter table public.products
  validate constraint products_version_positive;

alter table public.products
  validate constraint products_sync_status_check;

alter table public.categories
  validate constraint categories_version_positive;

alter table public.categories
  validate constraint categories_sync_status_check;

alter table public.customers
  validate constraint customers_version_positive;

alter table public.customers
  validate constraint customers_sync_status_check;

alter table public.suppliers
  validate constraint suppliers_version_positive;

alter table public.suppliers
  validate constraint suppliers_sync_status_check;

-- =========================================================
-- Operational tables
-- =========================================================

alter table public.purchases
  validate constraint purchases_version_positive;

alter table public.purchases
  validate constraint purchases_sync_status_check;

alter table public.sales
  validate constraint sales_version_positive;

alter table public.sales
  validate constraint sales_sync_status_check;

alter table public.devices
  validate constraint devices_version_positive;

alter table public.devices
  validate constraint devices_sync_status_check;

alter table public.subscriptions
  validate constraint subscriptions_version_positive;

alter table public.subscriptions
  validate constraint subscriptions_sync_status_check;

-- =========================================================
-- Inventory ledger
-- =========================================================

alter table public.inventory_movements
  validate constraint inventory_movements_version_positive;

alter table public.inventory_movements
  validate constraint inventory_movements_sync_status_check;

alter table public.inventory_movements
  validate constraint inventory_movements_unit_cost_non_negative;

alter table public.inventory_movements
  validate constraint inventory_movements_no_self_reversal;

commit;