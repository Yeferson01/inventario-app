begin;

-- W3's catalog applier inserts a product with the legacy UNIT default and
-- projects sale_mode afterward. Project the validated mutation's initial mode
-- during INSERT instead, so the later W3 UPDATE is a no-op. This does not
-- permit any existing product to change modes.
create function private.project_product_sale_mode_on_sync_insert()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_mode text;
begin
  if new.metadata->>'created_by_sync' is distinct from 'true' or
     new.metadata->>'sync_mutation_id' is null then
    return new;
  end if;
  select m.payload->>'sale_mode' into v_mode
    from public.sync_mutations m
    where m.id = (new.metadata->>'sync_mutation_id')::uuid
      and m.entity_table = 'products'
      and m.operation in ('insert', 'upsert')
      and m.entity_id = new.id
      and m.business_id = new.business_id;
  if v_mode is not null then
    if v_mode not in ('unit', 'weight') then
      raise exception using errcode = 'P0001',
        message = 'invalid_product_sale_mode';
    end if;
    new.sale_mode := v_mode;
  end if;
  return new;
end;
$$;
create trigger trg_product_sale_mode_on_sync_insert
  before insert on public.products
  for each row execute function private.project_product_sale_mode_on_sync_insert();
revoke all on function private.project_product_sale_mode_on_sync_insert()
  from public, anon, authenticated;

-- A product's sale mode defines the unit of every future quantity. Never
-- reinterpret an existing product, including one without operational history.
create or replace function private.guard_product_sale_mode_transition()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(old.id::text, 314159));
  if old.sale_mode is distinct from new.sale_mode then
    raise exception using errcode = 'P0001',
      message = 'product_sale_mode_immutable_after_creation';
  end if;
  if old.sale_mode = 'weight' and new.sale_price is distinct from old.sale_price
     and nullif(current_setting('app.w3_verified_price_mutation', true), '') is null
  then
    raise exception using errcode = 'P0001',
      message = 'weight_product_price_requires_versioned_sync';
  end if;
  return new;
end;
$$;

commit;
