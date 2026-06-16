-- Fase 5.5 - Inventory validate constraints
-- Objetivo:
-- Validar constraints de inventario creadas como NOT VALID
-- después de confirmar que los datos cumplen las reglas.

begin;

alter table public.purchases
  validate constraint purchases_branch_required;

alter table public.inventory_movements
  validate constraint inventory_movements_branch_required;

alter table public.inventory_movements
  validate constraint inventory_movements_quantity_change_non_zero;

commit;