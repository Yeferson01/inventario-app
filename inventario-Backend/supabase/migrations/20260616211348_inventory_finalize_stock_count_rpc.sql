-- Fase 5.9 - Finalize stock count RPC
-- Objetivo:
-- Crear RPC para finalizar conteos físicos y generar movimientos de ajuste.
--
-- Modelo:
-- stock_counts / stock_count_items = proceso de conteo físico.
-- inventory_movements = ajustes históricos generados por diferencias.
-- product_stock_balances = saldo actualizado por trigger.

begin;

-- =========================================================
-- RPC: finalize_stock_count
-- =========================================================

create or replace function public.finalize_stock_count(
  p_stock_count_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_count record;
  v_item record;
  v_current_quantity integer;
  v_adjustment integer;
  v_generated_movements integer := 0;
  v_idempotency_key text;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_stock_count_id is null then
    raise exception 'p_stock_count_id is required';
  end if;

  -- Bloquear el stock count para evitar doble finalización.
  select
    sc.id,
    sc.business_id,
    sc.branch_id,
    sc.status,
    sc.deleted_at
  into v_count
  from public.stock_counts sc
  where sc.id = p_stock_count_id
  for update;

  if v_count.id is null then
    raise exception 'Stock count not found';
  end if;

  if v_count.deleted_at is not null then
    raise exception 'Cannot finalize deleted stock count';
  end if;

  if v_count.status = 'completed' then
    raise exception 'Stock count is already completed';
  end if;

  if v_count.status = 'cancelled' then
    raise exception 'Cannot finalize cancelled stock count';
  end if;

  if v_count.business_id is null then
    raise exception 'Stock count business_id is required';
  end if;

  if v_count.branch_id is null then
    raise exception 'Stock count branch_id is required';
  end if;

  if not private.has_branch_permission(v_count.business_id, v_count.branch_id, 'inventory.count') then
    raise exception 'Insufficient permission to finalize stock count';
  end if;

  -- Debe tener items.
  if not exists (
    select 1
    from public.stock_count_items sci
    where sci.stock_count_id = p_stock_count_id
      and sci.deleted_at is null
  ) then
    raise exception 'Stock count has no items';
  end if;

  -- Todos los items activos deben estar contados.
  if exists (
    select 1
    from public.stock_count_items sci
    where sci.stock_count_id = p_stock_count_id
      and sci.deleted_at is null
      and sci.counted_quantity is null
  ) then
    raise exception 'All stock count items must have counted_quantity before finalizing';
  end if;

  -- Generar ajustes.
  for v_item in
    select
      sci.id,
      sci.product_id,
      sci.expected_quantity,
      sci.counted_quantity,
      sci.unit_cost_snapshot
    from public.stock_count_items sci
    where sci.stock_count_id = p_stock_count_id
      and sci.deleted_at is null
    order by sci.created_at asc
  loop
    -- Bloquear balance actual para calcular ajuste contra saldo real actual.
    select
      psb.quantity_on_hand
    into v_current_quantity
    from public.product_stock_balances psb
    where psb.business_id = v_count.business_id
      and psb.branch_id = v_count.branch_id
      and psb.product_id = v_item.product_id
      and psb.deleted_at is null
    for update;

    v_current_quantity := coalesce(v_current_quantity, 0);
    v_adjustment := v_item.counted_quantity - v_current_quantity;

    if v_adjustment <> 0 then
      v_idempotency_key :=
        'stock_count:' || p_stock_count_id::text || ':item:' || v_item.id::text;

      perform public.create_inventory_movement(
        p_business_id := v_count.business_id,
        p_branch_id := v_count.branch_id,
        p_product_id := v_item.product_id,
        p_movement_type := 'stock_count',
        p_quantity_change := v_adjustment,
        p_unit_cost := v_item.unit_cost_snapshot,
        p_source_type := 'stock_count',
        p_source_id := p_stock_count_id,
        p_reference_type := 'stock_count',
        p_reference_id := p_stock_count_id,
        p_notes := 'Inventory adjustment generated from stock count finalization',
        p_idempotency_key := v_idempotency_key,
        p_occurred_at := now(),
        p_metadata := jsonb_build_object(
          'stock_count_id', p_stock_count_id,
          'stock_count_item_id', v_item.id,
          'expected_quantity', v_item.expected_quantity,
          'current_quantity_at_finalize', v_current_quantity,
          'counted_quantity', v_item.counted_quantity,
          'adjustment_quantity', v_adjustment,
          'generated_by', 'finalize_stock_count'
        )
      );

      v_generated_movements := v_generated_movements + 1;
    end if;
  end loop;

  update public.stock_counts sc
  set
    status = 'completed',
    completed_by = v_profile_id,
    completed_at = now(),
    updated_by = v_profile_id
  where sc.id = p_stock_count_id;

  return v_generated_movements;
end;
$$;

comment on function public.finalize_stock_count(uuid)
is 'Finalizes a physical stock count and generates inventory adjustment movements for differences.';

revoke all on function public.finalize_stock_count(uuid) from public;
grant execute on function public.finalize_stock_count(uuid) to authenticated;
grant execute on function public.finalize_stock_count(uuid) to service_role;

commit;