-- Fase 5.4 - Inventory create movement RPC
-- Objetivo:
-- Centralizar creación de movimientos de inventario en una función RPC segura.
--
-- Modelo:
-- - La app llama public.create_inventory_movement(...)
-- - La función valida permisos, negocio, sucursal, producto e idempotencia.
-- - El trigger BEFORE INSERT llena previous_stock/new_stock.
-- - El trigger AFTER INSERT actualiza product_stock_balances.

begin;

-- =========================================================
-- 1. Preparar movimiento antes de insertar
-- Llena previous_stock y new_stock de forma consistente.
-- =========================================================

create or replace function private.prepare_inventory_movement_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_balance public.product_stock_balances%rowtype;
  v_previous_stock integer;
  v_new_stock integer;
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

  new.created_by := coalesce(new.created_by, auth.uid());
  new.source_type := coalesce(new.source_type, new.movement_type::text);
  new.occurred_at := coalesce(new.occurred_at, now());
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.version := coalesce(new.version, 1);

  -- Crear balance si no existe todavía.
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

  -- Bloquear saldo para evitar carreras.
  select *
  into v_balance
  from public.product_stock_balances psb
  where psb.business_id = new.business_id
    and psb.branch_id = new.branch_id
    and psb.product_id = new.product_id
    and psb.deleted_at is null
  for update;

  if v_balance.id is null then
    raise exception 'product_stock_balances row could not be found';
  end if;

  v_previous_stock := v_balance.quantity_on_hand;
  v_new_stock := v_previous_stock + new.quantity_change;

  if v_new_stock < 0 then
    raise exception 'Insufficient stock for product %. Current: %, movement: %, resulting: %',
      new.product_id,
      v_previous_stock,
      new.quantity_change,
      v_new_stock;
  end if;

  new.previous_stock := coalesce(new.previous_stock, v_previous_stock);
  new.new_stock := coalesce(new.new_stock, v_new_stock);

  return new;
end;
$$;

comment on function private.prepare_inventory_movement_before_insert()
is 'Prepares inventory_movements before insert by filling previous_stock and new_stock with locked stock balance.';

drop trigger if exists trg_inventory_movements_prepare_before_insert
on public.inventory_movements;

create trigger trg_inventory_movements_prepare_before_insert
before insert on public.inventory_movements
for each row
execute function private.prepare_inventory_movement_before_insert();

-- =========================================================
-- 2. RPC pública segura
-- =========================================================

create or replace function public.create_inventory_movement(
  p_business_id uuid,
  p_branch_id uuid,
  p_product_id uuid,
  p_movement_type text,
  p_quantity_change integer,
  p_unit_cost numeric default null,
  p_source_type text default null,
  p_source_id uuid default null,
  p_reference_type text default null,
  p_reference_id uuid default null,
  p_notes text default null,
  p_idempotency_key text default null,
  p_occurred_at timestamptz default now(),
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_source_type text;
  v_movement_type text;
  v_existing_id uuid;
  v_new_id uuid;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'p_business_id is required';
  end if;

  if p_branch_id is null then
    raise exception 'p_branch_id is required';
  end if;

  if p_product_id is null then
    raise exception 'p_product_id is required';
  end if;

  if p_quantity_change is null or p_quantity_change = 0 then
    raise exception 'p_quantity_change must be different from zero';
  end if;

  if p_unit_cost is not null and p_unit_cost < 0 then
    raise exception 'p_unit_cost cannot be negative';
  end if;

  v_source_type := lower(trim(coalesce(p_source_type, p_movement_type)));

  if v_source_type not in (
    'sale',
    'purchase',
    'manual_adjustment',
    'loss',
    'return',
    'reversal',
    'stock_count',
    'transfer'
  ) then
    raise exception 'Invalid source_type or movement_type: %', v_source_type;
  end if;

  -- movement_type mantiene compatibilidad con el CHECK existente.
  v_movement_type := case
    when v_source_type in ('sale', 'purchase', 'manual_adjustment', 'loss', 'return')
      then v_source_type
    when v_source_type in ('reversal', 'stock_count', 'transfer')
      then 'manual_adjustment'
    else 'manual_adjustment'
  end;

  -- Reglas de signo.
  if v_source_type in ('sale', 'loss') and p_quantity_change > 0 then
    raise exception '% movements must use negative quantity_change', v_source_type;
  end if;

  if v_source_type in ('purchase', 'return') and p_quantity_change < 0 then
    raise exception '% movements must use positive quantity_change', v_source_type;
  end if;

  -- Idempotencia: si ya existe, devolver el movimiento existente.
  if p_idempotency_key is not null then
    select im.id
    into v_existing_id
    from public.inventory_movements im
    where im.business_id = p_business_id
      and im.idempotency_key = p_idempotency_key
    limit 1;

    if v_existing_id is not null then
      return v_existing_id;
    end if;
  end if;

  -- Validar permisos por tipo.
  if v_source_type = 'sale' then
    if not private.has_branch_permission(p_business_id, p_branch_id, 'sales.create') then
      raise exception 'Insufficient permission for sale inventory movement';
    end if;

  elsif v_source_type = 'purchase' then
    if not private.has_branch_permission(p_business_id, p_branch_id, 'inventory.purchase') then
      raise exception 'Insufficient permission for purchase inventory movement';
    end if;

  elsif v_source_type in ('manual_adjustment', 'loss', 'reversal') then
    if not private.has_branch_permission(p_business_id, p_branch_id, 'inventory.adjust') then
      raise exception 'Insufficient permission for inventory adjustment movement';
    end if;

  elsif v_source_type = 'return' then
    if not (
      private.has_branch_permission(p_business_id, p_branch_id, 'sales.refund')
      or private.has_branch_permission(p_business_id, p_branch_id, 'inventory.adjust')
    ) then
      raise exception 'Insufficient permission for return inventory movement';
    end if;

  elsif v_source_type = 'stock_count' then
    if not private.has_branch_permission(p_business_id, p_branch_id, 'inventory.count') then
      raise exception 'Insufficient permission for stock count movement';
    end if;

  elsif v_source_type = 'transfer' then
    if not private.has_branch_permission(p_business_id, p_branch_id, 'inventory.transfer') then
      raise exception 'Insufficient permission for inventory transfer movement';
    end if;
  end if;

  insert into public.inventory_movements (
    business_id,
    branch_id,
    product_id,
    movement_type,
    quantity_change,
    reference_id,
    reference_type,
    notes,
    created_by,
    device_id,
    source_type,
    source_id,
    unit_cost,
    idempotency_key,
    sync_status,
    occurred_at,
    metadata
  )
  values (
    p_business_id,
    p_branch_id,
    p_product_id,
    v_movement_type,
    p_quantity_change,
    p_reference_id,
    p_reference_type,
    p_notes,
    v_profile_id,
    null,
    v_source_type,
    p_source_id,
    p_unit_cost,
    p_idempotency_key,
    'synced',
    coalesce(p_occurred_at, now()),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_new_id;

  return v_new_id;
end;
$$;

comment on function public.create_inventory_movement(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  numeric,
  text,
  uuid,
  text,
  uuid,
  text,
  text,
  timestamptz,
  jsonb
)
is 'Creates inventory movements through a controlled RPC with permission checks, idempotency and automatic stock balance updates.';

revoke all on function public.create_inventory_movement(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  numeric,
  text,
  uuid,
  text,
  uuid,
  text,
  text,
  timestamptz,
  jsonb
) from public;

grant execute on function public.create_inventory_movement(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  numeric,
  text,
  uuid,
  text,
  uuid,
  text,
  text,
  timestamptz,
  jsonb
) to authenticated;

grant execute on function public.create_inventory_movement(
  uuid,
  uuid,
  uuid,
  text,
  integer,
  numeric,
  text,
  uuid,
  text,
  uuid,
  text,
  text,
  timestamptz,
  jsonb
) to service_role;

commit;