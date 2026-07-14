-- Fase 5.6 - Apply sales and purchases to inventory
-- Objetivo:
-- Crear funciones explícitas para generar inventory_movements desde:
-- - sales / sale_items
-- - purchases / purchase_items
--
-- Nota:
-- No usamos triggers automáticos todavía para evitar duplicados durante desarrollo.
-- La app/backend debe llamar estas funciones cuando la venta/compra esté lista.

begin;

-- =========================================================
-- 1. Función: aplicar movimientos de inventario de una venta
-- =========================================================

create or replace function public.apply_sale_inventory_movements(
  p_sale_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_sale record;
  v_item record;
  v_count integer := 0;
  v_idempotency_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_sale_id is null then
    raise exception 'p_sale_id is required';
  end if;

  select
    s.id,
    s.business_id,
    s.branch_id,
    s.deleted_at,
    s.voided_at
  into v_sale
  from public.sales s
  where s.id = p_sale_id
  for update;

  if v_sale.id is null then
    raise exception 'Sale not found';
  end if;

  if v_sale.deleted_at is not null then
    raise exception 'Cannot apply inventory for deleted sale';
  end if;

  if v_sale.voided_at is not null then
    raise exception 'Cannot apply inventory for voided sale';
  end if;

  if v_sale.business_id is null then
    raise exception 'Sale business_id is required';
  end if;

  if v_sale.branch_id is null then
    raise exception 'Sale branch_id is required';
  end if;

  if not private.has_branch_permission(v_sale.business_id, v_sale.branch_id, 'sales.create') then
    raise exception 'Insufficient permission to apply sale inventory movements';
  end if;

  for v_item in
    select
      si.id,
      si.product_id,
      si.quantity,
      si.unit_cost_snapshot
    from public.sale_items si
    where si.sale_id = p_sale_id
      and si.deleted_at is null
      and si.product_id is not null
      and si.quantity > 0
  loop
    v_idempotency_key := 'sale:' || p_sale_id::text || ':item:' || v_item.id::text;

    perform public.create_inventory_movement(
      p_business_id := v_sale.business_id,
      p_branch_id := v_sale.branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'sale',
      p_quantity_change := -1 * v_item.quantity,
      p_unit_cost := v_item.unit_cost_snapshot,
      p_source_type := 'sale',
      p_source_id := p_sale_id,
      p_reference_type := 'sale',
      p_reference_id := p_sale_id,
      p_notes := 'Inventory movement generated from sale',
      p_idempotency_key := v_idempotency_key,
      p_occurred_at := now(),
      p_metadata := jsonb_build_object(
        'sale_id', p_sale_id,
        'sale_item_id', v_item.id,
        'generated_by', 'apply_sale_inventory_movements'
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

comment on function public.apply_sale_inventory_movements(uuid)
is 'Generates inventory movements for sale_items of a sale, using idempotency to avoid duplicate stock deductions.';

revoke all on function public.apply_sale_inventory_movements(uuid) from public;
grant execute on function public.apply_sale_inventory_movements(uuid) to authenticated;
grant execute on function public.apply_sale_inventory_movements(uuid) to service_role;

-- =========================================================
-- 2. Función: aplicar movimientos de inventario de una compra
-- =========================================================

create or replace function public.apply_purchase_inventory_movements(
  p_purchase_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_purchase record;
  v_item record;
  v_count integer := 0;
  v_idempotency_key text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_purchase_id is null then
    raise exception 'p_purchase_id is required';
  end if;

  select
    p.id,
    p.business_id,
    p.branch_id,
    p.deleted_at
  into v_purchase
  from public.purchases p
  where p.id = p_purchase_id
  for update;

  if v_purchase.id is null then
    raise exception 'Purchase not found';
  end if;

  if v_purchase.deleted_at is not null then
    raise exception 'Cannot apply inventory for deleted purchase';
  end if;

  if v_purchase.business_id is null then
    raise exception 'Purchase business_id is required';
  end if;

  if v_purchase.branch_id is null then
    raise exception 'Purchase branch_id is required';
  end if;

  if not private.has_branch_permission(v_purchase.business_id, v_purchase.branch_id, 'inventory.purchase') then
    raise exception 'Insufficient permission to apply purchase inventory movements';
  end if;

  for v_item in
    select
      pi.id,
      pi.product_id,
      pi.quantity,
      pi.unit_cost
    from public.purchase_items pi
    where pi.purchase_id = p_purchase_id
      and pi.product_id is not null
      and pi.quantity > 0
  loop
    v_idempotency_key := 'purchase:' || p_purchase_id::text || ':item:' || v_item.id::text;

    perform public.create_inventory_movement(
      p_business_id := v_purchase.business_id,
      p_branch_id := v_purchase.branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'purchase',
      p_quantity_change := v_item.quantity,
      p_unit_cost := v_item.unit_cost,
      p_source_type := 'purchase',
      p_source_id := p_purchase_id,
      p_reference_type := 'purchase',
      p_reference_id := p_purchase_id,
      p_notes := 'Inventory movement generated from purchase',
      p_idempotency_key := v_idempotency_key,
      p_occurred_at := now(),
      p_metadata := jsonb_build_object(
        'purchase_id', p_purchase_id,
        'purchase_item_id', v_item.id,
        'generated_by', 'apply_purchase_inventory_movements'
      )
    );

    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

comment on function public.apply_purchase_inventory_movements(uuid)
is 'Generates inventory movements for purchase_items of a purchase, using idempotency to avoid duplicate stock additions.';

revoke all on function public.apply_purchase_inventory_movements(uuid) from public;
grant execute on function public.apply_purchase_inventory_movements(uuid) to authenticated;
grant execute on function public.apply_purchase_inventory_movements(uuid) to service_role;

commit;