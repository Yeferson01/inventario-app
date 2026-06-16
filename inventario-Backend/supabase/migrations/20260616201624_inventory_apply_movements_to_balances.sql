-- Fase 5.3 - Apply inventory movements to stock balances
-- Objetivo:
-- Conectar inventory_movements con product_stock_balances.
--
-- Modelo:
-- inventory_movements = ledger inmutable
-- product_stock_balances = saldo actual por producto/sucursal
--
-- Nota:
-- Esta migración aplica movimientos futuros mediante trigger AFTER INSERT.
-- Los movimientos existentes ya fueron considerados en el backfill de Fase 5.2.

begin;

-- =========================================================
-- 1. Constraint: movimientos no pueden ser cero
-- =========================================================

alter table public.inventory_movements
  add constraint inventory_movements_quantity_change_non_zero
  check (quantity_change <> 0)
  not valid;

-- =========================================================
-- 2. Validar que product_id pertenezca al mismo business_id
-- =========================================================

create or replace function private.validate_inventory_movement_product_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if new.product_id is not null then
    if not exists (
      select 1
      from public.products p
      where p.id = new.product_id
        and p.business_id = new.business_id
        and p.deleted_at is null
    ) then
      raise exception 'inventory_movements.product_id must belong to the same business_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_inventory_movement_product_consistency()
is 'Ensures inventory_movements.product_id belongs to the same business_id.';

drop trigger if exists trg_inventory_movements_validate_product_consistency
on public.inventory_movements;

create trigger trg_inventory_movements_validate_product_consistency
before insert or update of business_id, product_id
on public.inventory_movements
for each row
execute function private.validate_inventory_movement_product_consistency();

-- =========================================================
-- 3. Aplicar movimiento al balance
-- =========================================================

create or replace function private.apply_inventory_movement_to_balance()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_balance public.product_stock_balances%rowtype;
  v_new_quantity integer;
  v_new_average_cost numeric(14,2);
  v_movement_at timestamp without time zone;
begin
  if new.business_id is null then
    raise exception 'inventory_movements.business_id is required';
  end if;

  if new.branch_id is null then
    raise exception 'inventory_movements.branch_id is required';
  end if;

  if new.product_id is null then
    raise exception 'inventory_movements.product_id is required';
  end if;

  if new.quantity_change is null or new.quantity_change = 0 then
    raise exception 'inventory_movements.quantity_change must be different from zero';
  end if;

  -- Crear balance si todavía no existe.
  insert into public.product_stock_balances (
    business_id,
    branch_id,
    product_id,
    quantity_on_hand,
    quantity_reserved,
    average_cost,
    last_movement_at,
    created_by,
    updated_by
  )
  values (
    new.business_id,
    new.branch_id,
    new.product_id,
    0,
    0,
    null,
    null,
    new.created_by,
    new.created_by
  )
  on conflict (business_id, branch_id, product_id) do nothing;

  -- Bloquear fila de balance para evitar carreras de concurrencia.
  select *
  into v_balance
  from public.product_stock_balances psb
  where psb.business_id = new.business_id
    and psb.branch_id = new.branch_id
    and psb.product_id = new.product_id
    and psb.deleted_at is null
  for update;

  if v_balance.id is null then
    raise exception 'product_stock_balances row could not be created or found';
  end if;

  v_new_quantity := v_balance.quantity_on_hand + new.quantity_change;

  if v_new_quantity < 0 then
    raise exception 'Insufficient stock for product %. Current: %, movement: %, resulting: %',
      new.product_id,
      v_balance.quantity_on_hand,
      new.quantity_change,
      v_new_quantity;
  end if;

  v_new_average_cost := v_balance.average_cost;

  -- Costo promedio ponderado solo para entradas con unit_cost.
  if new.quantity_change > 0 and new.unit_cost is not null then
    if v_balance.quantity_on_hand <= 0 or v_balance.average_cost is null then
      v_new_average_cost := new.unit_cost;
    else
      v_new_average_cost := round(
        (
          (v_balance.quantity_on_hand::numeric * v_balance.average_cost)
          + (new.quantity_change::numeric * new.unit_cost)
        ) / v_new_quantity::numeric,
        2
      );
    end if;
  end if;

  v_movement_at := coalesce(new.occurred_at, now())::timestamp without time zone;

  update public.product_stock_balances psb
  set
    quantity_on_hand = v_new_quantity,
    average_cost = v_new_average_cost,
    last_movement_at = case
      when psb.last_movement_at is null then v_movement_at
      when v_movement_at > psb.last_movement_at then v_movement_at
      else psb.last_movement_at
    end,
    updated_by = coalesce(new.created_by, psb.updated_by),
    sync_status = 'synced'
  where psb.id = v_balance.id;

  return new;
end;
$$;

comment on function private.apply_inventory_movement_to_balance()
is 'Applies inserted inventory_movements to product_stock_balances with concurrency locking and negative stock protection.';

-- =========================================================
-- 4. Trigger AFTER INSERT en inventory_movements
-- =========================================================

drop trigger if exists trg_inventory_movements_apply_to_balance
on public.inventory_movements;

create trigger trg_inventory_movements_apply_to_balance
after insert on public.inventory_movements
for each row
execute function private.apply_inventory_movement_to_balance();

commit;