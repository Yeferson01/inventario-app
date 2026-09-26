begin;

alter table public.purchases
  add column total_cents bigint,
  add column financial_finalized_at timestamptz,
  add column monetary_contract_version text;
alter table public.purchase_items
  add column unit_cost_cents bigint,
  add column subtotal_cents bigint,
  add column monetary_contract_version text;

alter table public.purchases add constraint purchases_total_cents_range
  check (total_cents is null or total_cents between 0 and 999999999999);
alter table public.purchase_items add constraint purchase_items_exact_cents
  check ((unit_cost_cents is null and subtotal_cents is null) or
    (unit_cost_cents between 0 and 999999999999 and
     subtotal_cents between 0 and 999999999999 and
     (subtotal_cents = unit_cost_cents * quantity or
      monetary_contract_version = 'legacy_stored')));
alter table public.purchases add constraint purchases_financial_finalization_pair
  check (financial_finalized_at is null or
    (total_cents is not null and monetary_contract_version is not null));

-- Numeric(12,2) makes the stored Hosted value exactly convertible. This does
-- not reconstruct the original pre-quantization input or attest completeness.
update public.purchase_items
set unit_cost_cents = (unit_cost * 100)::bigint,
    subtotal_cents = (subtotal * 100)::bigint,
    monetary_contract_version = 'legacy_stored';
update public.purchases
set total_cents = (total * 100)::bigint,
    monetary_contract_version = 'legacy_stored';

create function private.guard_exact_purchase_item()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_purchase public.purchases%rowtype;
  v_unit bigint;
  v_subtotal bigint;
begin
  if tg_op = 'DELETE' then
    select * into v_purchase from public.purchases where id = old.purchase_id for update;
    if v_purchase.financial_finalized_at is not null then
      raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and new.purchase_id is distinct from old.purchase_id
     and exists (select 1 from public.purchases p where p.id = old.purchase_id
       and p.financial_finalized_at is not null) then
    raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
  end if;

  select * into v_purchase from public.purchases where id = new.purchase_id for update;
  if v_purchase.financial_finalized_at is not null then
    if tg_op = 'INSERT' or new.purchase_id is distinct from old.purchase_id
       or new.product_id is distinct from old.product_id
       or new.quantity is distinct from old.quantity
       or new.unit_cost is distinct from old.unit_cost
       or new.subtotal is distinct from old.subtotal
       or new.unit_cost_cents is distinct from old.unit_cost_cents
       or new.subtotal_cents is distinct from old.subtotal_cents
       or new.monetary_contract_version is distinct from old.monetary_contract_version
       or new.deleted_at is distinct from old.deleted_at then
      raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
    end if;
    return new;
  end if;

  if v_purchase.metadata ->> 'monetary_contract_version' = 'exact_v1' then
    if coalesce(new.metadata ->> 'unit_cost_cents', '') !~ '^[0-9]+$'
       or coalesce(new.metadata ->> 'subtotal_cents', '') !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001', message = 'missing_exact_purchase_item_money';
    end if;
    v_unit := (new.metadata ->> 'unit_cost_cents')::bigint;
    v_subtotal := (new.metadata ->> 'subtotal_cents')::bigint;
    if v_unit < 0 or v_unit > 999999999999 or
       v_subtotal < 0 or v_subtotal > 999999999999 or
       v_subtotal <> v_unit * new.quantity or
       new.unit_cost <> v_unit::numeric / 100 or
       new.subtotal <> v_subtotal::numeric / 100 then
      raise exception using errcode = 'P0001', message = 'purchase_item_money_mismatch';
    end if;
    new.unit_cost_cents := v_unit;
    new.subtotal_cents := v_subtotal;
    new.monetary_contract_version := 'exact_v1';
  else
    -- Keep legacy documents editable under their existing contract. These
    -- cents describe only the stored numeric(12,2) values, not original input.
    new.unit_cost_cents := (new.unit_cost * 100)::bigint;
    new.subtotal_cents := (new.subtotal * 100)::bigint;
    new.monetary_contract_version := 'legacy_stored';
  end if;
  return new;
end;
$$;

create trigger trg_purchase_items_z_exact_money
before insert or update or delete on public.purchase_items
for each row execute function private.guard_exact_purchase_item();

create function private.guard_finalized_purchase_total()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
begin
  if tg_op = 'INSERT' then
    if new.total_cents is not null or new.financial_finalized_at is not null
       or new.monetary_contract_version is not null then
      raise exception using errcode = 'P0001', message = 'purchase_money_requires_batch_finalization';
    end if;
    return new;
  end if;
  if old.financial_finalized_at is null and
     (new.total_cents is distinct from old.total_cents or
      new.financial_finalized_at is distinct from old.financial_finalized_at or
      new.monetary_contract_version is distinct from old.monetary_contract_version)
     and pg_trigger_depth() < 2 then
    raise exception using errcode = 'P0001', message = 'purchase_money_requires_batch_finalization';
  end if;
  if old.financial_finalized_at is not null and
     (new.total is distinct from old.total or
      new.total_cents is distinct from old.total_cents or
      new.financial_finalized_at is distinct from old.financial_finalized_at or
      new.monetary_contract_version is distinct from old.monetary_contract_version or
      new.deleted_at is distinct from old.deleted_at) then
    raise exception using errcode = 'P0001', message = 'purchase_financially_finalized';
  end if;
  return new;
end;
$$;
create trigger trg_purchases_z_guard_final_total
before insert or update on public.purchases
for each row execute function private.guard_finalized_purchase_total();

create function private.finalize_exact_purchases_from_completed_batch()
returns trigger language plpgsql security definer
set search_path = public, private, extensions as $$
declare
  v_purchase public.purchases%rowtype;
  v_expected_count integer;
  v_expected_total bigint;
  v_item_mutations integer;
  v_item_count integer;
  v_exact_count integer;
  v_total bigint;
  v_unmatched_count integer;
begin
  if new.status <> 'completed' or old.status is not distinct from new.status
     or new.direction <> 'upload' then
    return new;
  end if;

  for v_purchase in
    select p.* from public.sync_mutations m
    join public.purchases p on p.id = m.entity_id
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'purchases' and m.operation = 'insert'
      and m.status = 'applied' and p.business_id = new.business_id
      and p.metadata ->> 'monetary_contract_version' = 'exact_v1'
    for update of p
  loop
    if v_purchase.financial_finalized_at is not null then
      continue;
    end if;
    if coalesce(v_purchase.metadata ->> 'item_count', '') !~ '^[1-9][0-9]*$'
       or coalesce(v_purchase.metadata ->> 'total_cents', '') !~ '^[0-9]+$' then
      raise exception using errcode = 'P0001', message = 'invalid_purchase_completion_manifest';
    end if;
    v_expected_count := (v_purchase.metadata ->> 'item_count')::integer;
    v_expected_total := (v_purchase.metadata ->> 'total_cents')::bigint;

    select count(*) into v_item_mutations
    from public.sync_mutations m
    where m.sync_batch_id = new.id and m.deleted_at is null
      and m.entity_table = 'purchase_items' and m.operation = 'insert'
      and m.status = 'applied'
      and m.payload ->> 'purchase_id' = v_purchase.id::text;
    select count(*), count(subtotal_cents), coalesce(sum(subtotal_cents), 0)
    into v_item_count, v_exact_count, v_total
    from public.purchase_items
    where purchase_id = v_purchase.id and deleted_at is null;
    select count(*) into v_unmatched_count
    from public.purchase_items pi
    where pi.purchase_id = v_purchase.id and pi.deleted_at is null
      and not exists (
        select 1 from public.sync_mutations m
        where m.sync_batch_id = new.id and m.deleted_at is null
          and m.entity_table = 'purchase_items' and m.operation = 'insert'
          and m.status = 'applied' and m.entity_id = pi.id
          and m.payload ->> 'purchase_id' = v_purchase.id::text
      );

    if v_expected_count <> v_item_mutations or
       v_expected_count <> v_item_count or
       v_expected_count <> v_exact_count or
       v_unmatched_count <> 0 or
       v_total <> v_expected_total or
       v_purchase.total <> v_total::numeric / 100 then
      raise exception using errcode = 'P0001', message = 'purchase_money_not_complete';
    end if;
    update public.purchases
    set total_cents = v_total, monetary_contract_version = 'exact_v1',
        financial_finalized_at = now()
    where id = v_purchase.id and financial_finalized_at is null;
  end loop;
  return new;
end;
$$;
create trigger trg_sync_batches_z_finalize_exact_purchase_money
after update of status on public.sync_batches
for each row execute function private.finalize_exact_purchases_from_completed_batch();

revoke all on function private.guard_exact_purchase_item() from public;
revoke all on function private.guard_finalized_purchase_total() from public;
revoke all on function private.finalize_exact_purchases_from_completed_batch() from public;

commit;
