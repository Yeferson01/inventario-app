begin;

-- A mode is a quantity interpretation, not a catalog/package label. Once any
-- operational history exists, changing it would reinterpret historical rows.
create function private.guard_product_sale_mode_transition()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
begin
  -- Share the product lock with operational writes so history cannot arrive
  -- between this check and the committed mode transition.
  perform pg_advisory_xact_lock(hashtextextended(old.id::text, 314159));
  if old.sale_mode = 'weight' and new.sale_price is distinct from old.sale_price
     and nullif(current_setting('app.w3_verified_price_mutation', true), '') is null
  then
    raise exception using errcode = 'P0001',
      message = 'weight_product_price_requires_versioned_sync';
  end if;
  if new.sale_mode is not distinct from old.sale_mode then
    return new;
  end if;
  if old.stock_quantity <> 0 or new.stock_quantity <> 0 or
     exists (select 1 from public.product_stock_balances b
       where b.product_id = old.id and
         (b.quantity_on_hand <> 0 or b.quantity_reserved <> 0 or
          b.quantity_available <> 0)) or
     exists (select 1 from public.inventory_movements m
       where m.product_id = old.id) or
     exists (select 1 from public.sale_items i where i.product_id = old.id) or
     exists (select 1 from public.purchase_items i where i.product_id = old.id)
  then
    raise exception using errcode = 'P0001',
      message = 'product_sale_mode_has_operational_history';
  end if;
  return new;
end;
$$;
create trigger trg_product_sale_mode_transition
  before update of sale_mode, sale_price on public.products
  for each row execute function private.guard_product_sale_mode_transition();
revoke all on function private.guard_product_sale_mode_transition() from public;

-- W1A's existing operation guard remains the fail-closed gate for WEIGHT.
-- Take the same product lock before reading sale_mode; otherwise a concurrent
-- UNIT operation could race a mode transition and preserve the wrong unit.
create or replace function private.guard_unimplemented_weight_operation()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
begin
  if new.product_id is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(new.product_id::text, 314159));
  end if;
  select p.sale_mode into v_mode from public.products p where p.id = new.product_id;
  if v_mode = 'weight' then
    raise exception using errcode = 'P0001',
      message = 'weight_operation_requires_versioned_sync';
  end if;
  if tg_table_name in ('sale_items', 'purchase_items') then
    if new.sale_mode_snapshot = 'weight' then
      raise exception using errcode = 'P0001',
        message = 'weight_operation_requires_versioned_sync';
    end if;
  end if;
  return new;
end;
$$;

-- A nonzero balance is also mode history. Serialize its writes with the same
-- transition, including snapshots which do not insert an inventory movement.
create function private.lock_product_balance_for_sale_mode()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.product_id::text, 314159));
  return new;
end;
$$;
create trigger trg_product_balance_sale_mode_lock
  before insert or update of product_id, quantity_on_hand, quantity_reserved
  on public.product_stock_balances
  for each row execute function private.lock_product_balance_for_sale_mode();
revoke all on function private.lock_product_balance_for_sale_mode() from public;

-- The existing catalog applier predates W1A and does not know sale_mode.
-- Preserve its authorization/conflict behavior; only project the verified
-- product configuration after an applied catalog mutation.
alter function private.apply_sync_catalog_mutation(uuid)
  rename to apply_sync_catalog_mutation_base_before_w3;
revoke all on function private.apply_sync_catalog_mutation_base_before_w3(uuid)
  from public, anon, authenticated;

create function private.apply_sync_catalog_mutation(p_sync_mutation_id uuid)
returns jsonb language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mutation record;
  v_result jsonb;
  v_current_mode text;
  v_price_cents bigint;
  v_price numeric;
  v_server_version integer;
begin
  select entity_table, entity_id, operation, payload, business_id
    into v_mutation
    from public.sync_mutations where id = p_sync_mutation_id;
  if v_mutation.entity_table is distinct from 'products' or
     v_mutation.operation not in ('insert', 'update', 'upsert') then
    return private.apply_sync_catalog_mutation_base_before_w3(p_sync_mutation_id);
  end if;

  if v_mutation.payload ? 'sale_mode' and
     v_mutation.payload->>'sale_mode' not in ('unit', 'weight') then
    raise exception using errcode = 'P0001', message = 'invalid_product_sale_mode';
  end if;
  select sale_mode into v_current_mode from public.products
    where id = v_mutation.entity_id and business_id = v_mutation.business_id;

  if v_mutation.payload ? 'sale_price_cents' and
     v_mutation.payload->'sale_price_cents' <> 'null'::jsonb then
    if (v_mutation.payload->>'sale_price_cents') !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001',
        message = 'invalid_product_sale_price_cents';
    end if;
    v_price_cents := (v_mutation.payload->>'sale_price_cents')::bigint;
    if v_price_cents > 999999999999 or not (v_mutation.payload ? 'sale_price') then
      raise exception using errcode = 'P0001',
        message = 'product_sale_price_cents_requires_matching_price';
    end if;
    v_price := (v_mutation.payload->>'sale_price')::numeric;
    if v_price * 100 <> v_price_cents then
      raise exception using errcode = 'P0001',
        message = 'product_sale_price_cents_mismatch';
    end if;
  elsif coalesce(v_mutation.payload->>'sale_mode', v_current_mode, 'unit') = 'weight'
        and (v_mutation.payload ? 'sale_price' or v_current_mode is null or
             v_mutation.payload ? 'sale_mode') then
    raise exception using errcode = 'P0001',
      message = 'weight_product_price_requires_exact_cents';
  end if;

  if v_price_cents is not null then
    perform set_config('app.w3_verified_price_mutation',
      p_sync_mutation_id::text, true);
  end if;

  v_result := private.apply_sync_catalog_mutation_base_before_w3(p_sync_mutation_id);
  if v_result->>'status' = 'applied' and v_mutation.payload ? 'sale_mode' then
    update public.products set sale_mode = v_mutation.payload->>'sale_mode'
      where id = v_mutation.entity_id and business_id = v_mutation.business_id
        and sale_mode is distinct from v_mutation.payload->>'sale_mode';
    select version into v_server_version from public.products
      where id = v_mutation.entity_id and business_id = v_mutation.business_id;
    perform private.mark_sync_mutation_applied(p_sync_mutation_id,
      v_server_version);
    v_result := jsonb_set(v_result, '{server_entity_version}',
      to_jsonb(v_server_version), true);
  end if;
  return v_result;
end;
$$;
revoke all on function private.apply_sync_catalog_mutation(uuid)
  from public, anon, authenticated;
grant execute on function private.apply_sync_catalog_mutation(uuid) to service_role;

commit;
