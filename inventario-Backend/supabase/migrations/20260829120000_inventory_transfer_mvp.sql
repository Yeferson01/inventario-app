-- Inventory Transfer MVP - atomic, idempotent cross-branch transfer.
--
-- The historical inventory_transfers model and completion RPC already own the
-- ledger/cost rules. This migration exposes one authenticated operation that
-- creates the one-item transfer and completes both ledger legs in one server
-- transaction. Direct authenticated writes remain closed so clients cannot
-- bypass the cost snapshot or leave a partially prepared transfer.

begin;

create or replace function public.create_and_complete_inventory_transfer(
  p_business_id uuid,
  p_from_branch_id uuid,
  p_to_branch_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_transfer_id uuid,
  p_transfer_item_id uuid,
  p_idempotency_key text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_idempotency_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_transfer public.inventory_transfers%rowtype;
  v_item public.inventory_transfer_items%rowtype;
  v_source_balance public.product_stock_balances%rowtype;
  v_destination_balance public.product_stock_balances%rowtype;
  v_source_movement public.inventory_movements%rowtype;
  v_destination_movement public.inventory_movements%rowtype;
  v_source_movement_key text;
  v_destination_movement_key text;
  v_generated_movements integer := 0;
  v_idempotent_replay boolean := false;
begin
  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null
     or p_from_branch_id is null
     or p_to_branch_id is null
     or p_product_id is null
     or p_transfer_id is null
     or p_transfer_item_id is null
  then
    raise exception 'business, branches, product and transfer identities are required';
  end if;

  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Transfer quantity must be greater than zero';
  end if;

  if p_from_branch_id = p_to_branch_id then
    raise exception 'Origin and destination branches must be different';
  end if;

  if v_idempotency_key is null then
    raise exception 'idempotency_key is required';
  end if;

  if char_length(v_idempotency_key) > 200 then
    raise exception 'idempotency_key exceeds 200 characters';
  end if;

  if not exists (
    select 1
    from public.businesses business
    where business.id = p_business_id
      and business.status = 'active'
      and business.deleted_at is null
  ) then
    raise exception 'Business is not active';
  end if;

  if not exists (
    select 1
    from public.branches branch
    where branch.id = p_from_branch_id
      and branch.business_id = p_business_id
      and branch.status = 'active'
      and branch.deleted_at is null
  ) then
    raise exception 'Origin branch is not active in the requested business';
  end if;

  if not exists (
    select 1
    from public.branches branch
    where branch.id = p_to_branch_id
      and branch.business_id = p_business_id
      and branch.status = 'active'
      and branch.deleted_at is null
  ) then
    raise exception 'Destination branch is not active in the requested business';
  end if;

  if not exists (
    select 1
    from public.products product
    where product.id = p_product_id
      and product.business_id = p_business_id
      and product.status = 'active'
      and product.deleted_at is null
  ) then
    raise exception 'Product is not active in the requested business';
  end if;

  if not private.has_branch_permission(
    p_business_id,
    p_from_branch_id,
    'inventory.transfer'
  ) then
    raise exception 'Insufficient inventory.transfer permission for origin branch';
  end if;

  if not private.has_branch_permission(
    p_business_id,
    p_to_branch_id,
    'inventory.transfer'
  ) then
    raise exception 'Insufficient inventory.transfer permission for destination branch';
  end if;

  -- Serialize the same logical request before checking its durable identity.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_business_id::text || ':' || v_idempotency_key,
      0
    )
  );

  select transfer.*
  into v_transfer
  from public.inventory_transfers transfer
  where transfer.idempotency_key = v_idempotency_key
  for update;

  if v_transfer.id is not null then
    if v_transfer.business_id <> p_business_id
       or v_transfer.id <> p_transfer_id
       or v_transfer.from_branch_id <> p_from_branch_id
       or v_transfer.to_branch_id <> p_to_branch_id
       or v_transfer.metadata ->> 'created_via'
          <> 'create_and_complete_inventory_transfer'
    then
      raise exception 'idempotency_key was already used with an incompatible transfer payload';
    end if;

    select item.*
    into v_item
    from public.inventory_transfer_items item
    where item.inventory_transfer_id = v_transfer.id
      and item.deleted_at is null
    limit 1;

    if v_item.id is null
       or v_item.id <> p_transfer_item_id
       or v_item.product_id <> p_product_id
       or v_item.quantity <> p_quantity
    then
      raise exception 'idempotency_key was already used with an incompatible transfer item';
    end if;

    if v_transfer.status <> 'completed' then
      raise exception 'Existing idempotent transfer is not complete';
    end if;

    v_idempotent_replay := true;
  else
    -- Ensure both balance rows exist, then lock them in deterministic order.
    insert into public.product_stock_balances (
      business_id,
      branch_id,
      product_id,
      quantity_on_hand,
      quantity_reserved,
      average_cost,
      created_by,
      updated_by
    )
    values (
      p_business_id,
      p_to_branch_id,
      p_product_id,
      0,
      0,
      null,
      v_profile_id,
      v_profile_id
    )
    on conflict (business_id, branch_id, product_id) do nothing;

    perform balance.id
    from public.product_stock_balances balance
    where balance.business_id = p_business_id
      and balance.branch_id in (p_from_branch_id, p_to_branch_id)
      and balance.product_id = p_product_id
      and balance.deleted_at is null
    order by balance.branch_id
    for update;

    select balance.*
    into v_source_balance
    from public.product_stock_balances balance
    where balance.business_id = p_business_id
      and balance.branch_id = p_from_branch_id
      and balance.product_id = p_product_id
      and balance.deleted_at is null;

    if v_source_balance.id is null then
      raise exception 'Origin stock balance does not exist';
    end if;

    select balance.*
    into v_destination_balance
    from public.product_stock_balances balance
    where balance.business_id = p_business_id
      and balance.branch_id = p_to_branch_id
      and balance.product_id = p_product_id
      and balance.deleted_at is null;

    if v_destination_balance.id is null then
      raise exception 'Destination stock balance is not active';
    end if;

    if v_source_balance.quantity_available < p_quantity then
      raise exception 'Insufficient available stock for transfer. Available: %, requested: %',
        v_source_balance.quantity_available,
        p_quantity;
    end if;

    insert into public.inventory_transfers (
      id,
      business_id,
      from_branch_id,
      to_branch_id,
      status,
      requested_by,
      requested_at,
      notes,
      idempotency_key,
      created_by,
      updated_by,
      metadata
    )
    values (
      p_transfer_id,
      p_business_id,
      p_from_branch_id,
      p_to_branch_id,
      'draft',
      v_profile_id,
      now(),
      nullif(btrim(coalesce(p_notes, '')), ''),
      v_idempotency_key,
      v_profile_id,
      v_profile_id,
      jsonb_build_object(
        'created_via', 'create_and_complete_inventory_transfer',
        'mvp', true
      )
    )
    returning * into v_transfer;

    insert into public.inventory_transfer_items (
      id,
      business_id,
      inventory_transfer_id,
      product_id,
      quantity,
      unit_cost_snapshot,
      created_by,
      updated_by,
      metadata
    )
    values (
      p_transfer_item_id,
      p_business_id,
      p_transfer_id,
      p_product_id,
      p_quantity,
      v_source_balance.average_cost,
      v_profile_id,
      v_profile_id,
      jsonb_build_object(
        'created_via', 'create_and_complete_inventory_transfer',
        'cost_source', 'origin_average_cost'
      )
    )
    returning * into v_item;

    v_generated_movements := public.complete_inventory_transfer(p_transfer_id);
  end if;

  v_source_movement_key :=
    'transfer:' || p_transfer_id::text || ':item:'
    || p_transfer_item_id::text || ':out';
  v_destination_movement_key :=
    'transfer:' || p_transfer_id::text || ':item:'
    || p_transfer_item_id::text || ':in';

  select movement.*
  into v_source_movement
  from public.inventory_movements movement
  where movement.business_id = p_business_id
    and movement.branch_id = p_from_branch_id
    and movement.idempotency_key = v_source_movement_key;

  select movement.*
  into v_destination_movement
  from public.inventory_movements movement
  where movement.business_id = p_business_id
    and movement.branch_id = p_to_branch_id
    and movement.idempotency_key = v_destination_movement_key;

  if v_source_movement.id is null or v_destination_movement.id is null then
    raise exception 'Completed transfer is missing correlated inventory movements';
  end if;

  select balance.*
  into v_source_balance
  from public.product_stock_balances balance
  where balance.business_id = p_business_id
    and balance.branch_id = p_from_branch_id
    and balance.product_id = p_product_id
    and balance.deleted_at is null;

  select balance.*
  into v_destination_balance
  from public.product_stock_balances balance
  where balance.business_id = p_business_id
    and balance.branch_id = p_to_branch_id
    and balance.product_id = p_product_id
    and balance.deleted_at is null;

  return jsonb_build_object(
    'transfer_id', p_transfer_id,
    'transfer_item_id', p_transfer_item_id,
    'business_id', p_business_id,
    'from_branch_id', p_from_branch_id,
    'to_branch_id', p_to_branch_id,
    'product_id', p_product_id,
    'quantity', p_quantity,
    'status', 'completed',
    'idempotent_replay', v_idempotent_replay,
    'generated_movement_count', v_generated_movements,
    'unit_cost_snapshot', v_item.unit_cost_snapshot,
    'source_movement', to_jsonb(v_source_movement),
    'destination_movement', to_jsonb(v_destination_movement),
    'source_balance', to_jsonb(v_source_balance),
    'destination_balance', to_jsonb(v_destination_balance)
  );
end;
$$;

comment on function public.create_and_complete_inventory_transfer(
  uuid, uuid, uuid, uuid, integer, uuid, uuid, text, text
) is
'Atomically creates and completes one cross-branch inventory transfer. The origin average cost is preserved as the destination inbound cost basis and retries are idempotent.';

-- End users must use the atomic contract. The historical completion helper
-- remains available to trusted backend code only.
revoke insert, update, delete on public.inventory_transfers
from public, anon, authenticated;
revoke insert, update, delete on public.inventory_transfer_items
from public, anon, authenticated;

revoke execute on function public.complete_inventory_transfer(uuid)
from public, anon, authenticated;

revoke all on function public.create_and_complete_inventory_transfer(
  uuid, uuid, uuid, uuid, integer, uuid, uuid, text, text
) from public, anon;
grant execute on function public.create_and_complete_inventory_transfer(
  uuid, uuid, uuid, uuid, integer, uuid, uuid, text, text
) to authenticated, service_role;

commit;
