-- Fase 5.12 - Complete inventory transfer RPC
-- Objetivo:
-- Crear RPC para completar transferencias entre sucursales.
--
-- Al completar:
-- - Se descuenta stock de from_branch_id.
-- - Se suma stock a to_branch_id.
-- - Se generan inventory_movements auditables.
-- - Se actualizan product_stock_balances por trigger.
--
-- Nota:
-- La función usa idempotency_key por item/origen/destino
-- para evitar duplicar movimientos si se reintenta.

begin;

create or replace function public.complete_inventory_transfer(
  p_inventory_transfer_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_transfer record;
  v_item record;
  v_generated_movements integer := 0;
  v_out_key text;
  v_in_key text;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_inventory_transfer_id is null then
    raise exception 'p_inventory_transfer_id is required';
  end if;

  -- Bloquear transferencia para evitar doble finalización concurrente.
  select
    it.id,
    it.business_id,
    it.from_branch_id,
    it.to_branch_id,
    it.status,
    it.deleted_at
  into v_transfer
  from public.inventory_transfers it
  where it.id = p_inventory_transfer_id
  for update;

  if v_transfer.id is null then
    raise exception 'Inventory transfer not found';
  end if;

  if v_transfer.deleted_at is not null then
    raise exception 'Cannot complete deleted inventory transfer';
  end if;

  if v_transfer.status = 'completed' then
    return 0;
  end if;

  if v_transfer.status = 'cancelled' then
    raise exception 'Cannot complete cancelled inventory transfer';
  end if;

  if v_transfer.business_id is null then
    raise exception 'Inventory transfer business_id is required';
  end if;

  if v_transfer.from_branch_id is null then
    raise exception 'Inventory transfer from_branch_id is required';
  end if;

  if v_transfer.to_branch_id is null then
    raise exception 'Inventory transfer to_branch_id is required';
  end if;

  if v_transfer.from_branch_id = v_transfer.to_branch_id then
    raise exception 'Origin and destination branches must be different';
  end if;

  if not private.has_branch_permission(
    v_transfer.business_id,
    v_transfer.from_branch_id,
    'inventory.transfer'
  ) then
    raise exception 'Insufficient permission for origin branch transfer';
  end if;

  if not private.has_branch_permission(
    v_transfer.business_id,
    v_transfer.to_branch_id,
    'inventory.transfer'
  ) then
    raise exception 'Insufficient permission for destination branch transfer';
  end if;

  if not exists (
    select 1
    from public.inventory_transfer_items iti
    where iti.inventory_transfer_id = p_inventory_transfer_id
      and iti.deleted_at is null
  ) then
    raise exception 'Inventory transfer has no items';
  end if;

  for v_item in
    select
      iti.id,
      iti.product_id,
      iti.quantity,
      iti.unit_cost_snapshot
    from public.inventory_transfer_items iti
    where iti.inventory_transfer_id = p_inventory_transfer_id
      and iti.deleted_at is null
    order by iti.created_at asc
  loop
    if v_item.product_id is null then
      raise exception 'Transfer item product_id is required';
    end if;

    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'Transfer item quantity must be positive';
    end if;

    -- Movimiento de salida en sucursal origen.
    v_out_key :=
      'transfer:' || p_inventory_transfer_id::text || ':item:' || v_item.id::text || ':out';

    perform public.create_inventory_movement(
      p_business_id := v_transfer.business_id,
      p_branch_id := v_transfer.from_branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'transfer',
      p_quantity_change := -1 * v_item.quantity,
      p_unit_cost := v_item.unit_cost_snapshot,
      p_source_type := 'transfer',
      p_source_id := p_inventory_transfer_id,
      p_reference_type := 'inventory_transfer',
      p_reference_id := p_inventory_transfer_id,
      p_notes := 'Inventory transfer outbound movement',
      p_idempotency_key := v_out_key,
      p_occurred_at := now(),
      p_metadata := jsonb_build_object(
        'inventory_transfer_id', p_inventory_transfer_id,
        'inventory_transfer_item_id', v_item.id,
        'direction', 'out',
        'from_branch_id', v_transfer.from_branch_id,
        'to_branch_id', v_transfer.to_branch_id,
        'generated_by', 'complete_inventory_transfer'
      )
    );

    -- Movimiento de entrada en sucursal destino.
    v_in_key :=
      'transfer:' || p_inventory_transfer_id::text || ':item:' || v_item.id::text || ':in';

    perform public.create_inventory_movement(
      p_business_id := v_transfer.business_id,
      p_branch_id := v_transfer.to_branch_id,
      p_product_id := v_item.product_id,
      p_movement_type := 'transfer',
      p_quantity_change := v_item.quantity,
      p_unit_cost := v_item.unit_cost_snapshot,
      p_source_type := 'transfer',
      p_source_id := p_inventory_transfer_id,
      p_reference_type := 'inventory_transfer',
      p_reference_id := p_inventory_transfer_id,
      p_notes := 'Inventory transfer inbound movement',
      p_idempotency_key := v_in_key,
      p_occurred_at := now(),
      p_metadata := jsonb_build_object(
        'inventory_transfer_id', p_inventory_transfer_id,
        'inventory_transfer_item_id', v_item.id,
        'direction', 'in',
        'from_branch_id', v_transfer.from_branch_id,
        'to_branch_id', v_transfer.to_branch_id,
        'generated_by', 'complete_inventory_transfer'
      )
    );

    v_generated_movements := v_generated_movements + 2;
  end loop;

  update public.inventory_transfers it
  set
    status = 'completed',
    sent_by = coalesce(it.sent_by, v_profile_id),
    sent_at = coalesce(it.sent_at, now()),
    received_by = v_profile_id,
    received_at = now(),
    updated_by = v_profile_id
  where it.id = p_inventory_transfer_id;

  return v_generated_movements;
end;
$$;

comment on function public.complete_inventory_transfer(uuid)
is 'Completes an inventory transfer by generating outbound and inbound inventory movements for each transfer item.';

revoke all on function public.complete_inventory_transfer(uuid) from public;
grant execute on function public.complete_inventory_transfer(uuid) to authenticated;
grant execute on function public.complete_inventory_transfer(uuid) to service_role;

commit;