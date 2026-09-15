-- P2.2C1 - Preserve the locally captured sale cost snapshot through normal POS sync.

begin;

create or replace function private.fill_sale_item_snapshots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product_name text;
  v_barcode text;
begin
  if new.product_id is not null then
    select p.name, p.barcode
    into v_product_name, v_barcode
    from public.products p
    where p.id = new.product_id
      and p.business_id = new.business_id
    limit 1;

    new.product_name_snapshot := coalesce(new.product_name_snapshot, v_product_name);
    new.barcode_snapshot := coalesce(new.barcode_snapshot, v_barcode);
  end if;

  new.discount_amount := coalesce(new.discount_amount, 0);
  new.tax_amount := coalesce(new.tax_amount, 0);

  if new.subtotal is null then
    new.subtotal := new.quantity * new.unit_price;
  end if;

  if new.total is null or new.total = 0 then
    new.total := greatest(
      coalesce(new.subtotal, new.quantity * new.unit_price)
      - new.discount_amount
      + new.tax_amount,
      0
    );
  end if;

  return new;
end;
$$;

comment on function private.fill_sale_item_snapshots()
is 'Fills product name/barcode snapshots and item totals without fabricating historical unit cost.';

create or replace function private.prevent_sale_item_cost_snapshot_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.unit_cost_snapshot is distinct from new.unit_cost_snapshot then
    raise exception 'sale_items.unit_cost_snapshot is immutable';
  end if;

  return new;
end;
$$;

comment on function private.prevent_sale_item_cost_snapshot_change()
is 'Rejects changes to the historical sale item unit cost snapshot after insert.';

drop trigger if exists trg_sale_items_prevent_cost_snapshot_change
on public.sale_items;

create trigger trg_sale_items_prevent_cost_snapshot_change
before update of unit_cost_snapshot
on public.sale_items
for each row
execute function private.prevent_sale_item_cost_snapshot_change();

do $$
begin
  if to_regprocedure(
    'private.apply_sync_pos_mutation_before_sale_cost_snapshot(uuid)'
  ) is null then
    execute 'alter function private.apply_sync_pos_mutation_before_cash_session_guard(uuid) '
      || 'rename to apply_sync_pos_mutation_before_sale_cost_snapshot';
  end if;
end;
$$;

create or replace function private.apply_sync_sale_item_cost_snapshot_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_payload jsonb;
  v_operation text;
  v_result_payload jsonb;
  v_sale_id uuid;
  v_product_id uuid;
  v_quantity integer;
  v_unit_price numeric;
  v_unit_cost_snapshot numeric;
  v_discount_amount numeric;
  v_tax_amount numeric;
  v_subtotal numeric;
  v_current_unit_cost_snapshot numeric;
  v_new_version integer;
begin
  select
    sm.id,
    sm.business_id,
    sm.profile_id,
    sm.branch_id,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.status,
    sm.idempotency_key,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);
  v_operation := lower(trim(v_mutation.operation));

  if lower(trim(v_mutation.entity_table)) <> 'sale_items' then
    return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
      p_sync_mutation_id
    );
  end if;

  select si.unit_cost_snapshot
  into v_current_unit_cost_snapshot
  from public.sale_items si
  where si.id = v_mutation.entity_id;

  if found then
    if v_payload ? 'unit_cost_snapshot'
       and v_current_unit_cost_snapshot is distinct from
         (nullif(v_payload ->> 'unit_cost_snapshot', ''))::numeric then
      raise exception 'sale_items.unit_cost_snapshot is immutable';
    end if;

    return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
      p_sync_mutation_id
    );
  end if;

  if v_operation not in ('insert', 'upsert') then
    return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
      p_sync_mutation_id
    );
  end if;

  if v_mutation.deleted_at is not null then
    raise exception 'Cannot apply deleted sync mutation';
  end if;

  if not private.has_sync_entity_permission(
    v_mutation.business_id,
    v_mutation.branch_id,
    'sale_items',
    v_operation
  ) then
    return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
      p_sync_mutation_id
    );
  end if;

  if v_payload ? 'sale_id'
     and nullif(v_payload ->> 'sale_id', '') is not null then
    v_sale_id := (v_payload ->> 'sale_id')::uuid;
  else
    raise exception 'sale_items.sale_id is required';
  end if;

  if not exists (
    select 1
    from public.sales s
    where s.id = v_sale_id
      and s.business_id = v_mutation.business_id
      and s.deleted_at is null
  ) then
    raise exception 'sale_items.sale_id must belong to the same business';
  end if;

  if v_payload ? 'product_id'
     and nullif(v_payload ->> 'product_id', '') is not null then
    v_product_id := (v_payload ->> 'product_id')::uuid;
  else
    raise exception 'sale_items.product_id is required';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = v_product_id
      and p.business_id = v_mutation.business_id
      and p.deleted_at is null
  ) then
    raise exception 'sale_items.product_id must belong to the same business';
  end if;

  v_quantity := coalesce(
    (nullif(v_payload ->> 'quantity', ''))::integer,
    1
  );
  v_unit_price := coalesce(
    (nullif(v_payload ->> 'unit_price', ''))::numeric,
    0
  );
  v_unit_cost_snapshot :=
    (nullif(v_payload ->> 'unit_cost_snapshot', ''))::numeric;
  v_discount_amount := coalesce(
    (nullif(v_payload ->> 'discount_amount', ''))::numeric,
    0
  );
  v_tax_amount := coalesce(
    (nullif(v_payload ->> 'tax_amount', ''))::numeric,
    0
  );
  v_subtotal := coalesce(
    (nullif(v_payload ->> 'subtotal', ''))::numeric,
    v_quantity * v_unit_price
  );

  if v_quantity <= 0 then
    raise exception 'sale_items.quantity must be positive';
  end if;

  if v_unit_price < 0 then
    raise exception 'sale_items.unit_price must be non-negative';
  end if;

  insert into public.sale_items (
    id,
    business_id,
    sale_id,
    product_id,
    quantity,
    unit_price,
    unit_cost_snapshot,
    subtotal,
    discount_amount,
    tax_amount,
    created_by,
    updated_by,
    sync_status,
    idempotency_key,
    metadata
  )
  values (
    v_mutation.entity_id,
    v_mutation.business_id,
    v_sale_id,
    v_product_id,
    v_quantity,
    v_unit_price,
    v_unit_cost_snapshot,
    v_subtotal,
    v_discount_amount,
    v_tax_amount,
    v_mutation.profile_id,
    v_mutation.profile_id,
    'synced',
    coalesce(
      nullif(v_payload ->> 'idempotency_key', ''),
      v_mutation.idempotency_key
    ),
    jsonb_build_object(
      'created_by_sync', true,
      'sync_mutation_id', v_mutation.id,
      'phase', 'P2.2C1'
    )
  );

  v_result_payload := private.get_current_server_payload(
    'sale_items',
    v_mutation.entity_id
  );

  if v_result_payload is not null
     and v_result_payload ? 'version'
     and (v_result_payload ->> 'version') ~ '^[0-9]+$' then
    v_new_version := (v_result_payload ->> 'version')::integer;
  else
    v_new_version := null;
  end if;

  perform private.mark_sync_mutation_applied(
    v_mutation.id,
    v_new_version
  );

  return jsonb_build_object(
    'status', 'applied',
    'entity_table', 'sale_items',
    'entity_id', v_mutation.entity_id,
    'operation', v_operation,
    'server_entity_version', v_new_version
  );
end;
$$;

comment on function private.apply_sync_sale_item_cost_snapshot_mutation(uuid)
is 'Applies new sale_items while preserving the nullable local unit cost snapshot exactly.';

revoke all on function private.apply_sync_sale_item_cost_snapshot_mutation(uuid)
from public;
grant execute on function private.apply_sync_sale_item_cost_snapshot_mutation(uuid)
to authenticated, service_role;

create or replace function private.apply_sync_pos_mutation_before_cash_session_guard(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
begin
  select lower(trim(sm.entity_table))
  into v_entity
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id;

  if v_entity = 'sale_items' then
    return private.apply_sync_sale_item_cost_snapshot_mutation(
      p_sync_mutation_id
    );
  end if;

  return private.apply_sync_pos_mutation_before_sale_cost_snapshot(
    p_sync_mutation_id
  );
end;
$$;

comment on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
is 'Routes sale_items through the P2.2C1 historical cost contract and preserves the prior POS mapper for other entities.';

revoke all on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
from public;
grant execute on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
to authenticated, service_role;

commit;
