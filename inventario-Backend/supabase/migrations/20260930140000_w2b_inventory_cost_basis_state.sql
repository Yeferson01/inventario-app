-- W2B: pure inventory cost-basis transitions. No table writes or locks.
-- Hosted will own the authoritative balance/COGS transaction in W4/W5.
create or replace function private.apply_costed_inventory_receipt(
  p_quantity_before bigint,
  p_cost_basis_before_cents bigint,
  p_incoming_quantity bigint,
  p_incoming_cost_cents bigint
) returns table (
  quantity_after bigint,
  cost_basis_after_cents bigint,
  cost_effect_cents bigint
)
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $$
declare
  v_quantity_after numeric;
  v_cost_after numeric;
begin
  if p_quantity_before is null or p_quantity_before < 0
     or p_incoming_quantity is null or p_incoming_quantity <= 0
     or p_incoming_cost_cents is null or p_incoming_cost_cents < 0
     or (p_cost_basis_before_cents is not null
         and p_cost_basis_before_cents < 0)
     or (p_quantity_before = 0 and p_cost_basis_before_cents > 0) then
    raise exception 'Invalid inventory receipt cost-basis state'
      using errcode = '22023';
  end if;

  v_quantity_after := p_quantity_before::numeric + p_incoming_quantity::numeric;
  if v_quantity_after > 9223372036854775807::numeric then
    raise exception 'Inventory receipt quantity exceeds BIGINT range'
      using errcode = '22003';
  end if;

  if p_quantity_before = 0 then
    -- No unknown stock remains, even if the empty legacy basis was NULL.
    v_cost_after := p_incoming_cost_cents;
  elsif p_cost_basis_before_cents is null then
    -- Known receipt cost does not make the mixed aggregate cost known.
    v_cost_after := null;
  else
    v_cost_after := p_cost_basis_before_cents::numeric
      + p_incoming_cost_cents::numeric;
    if v_cost_after > 9223372036854775807::numeric then
      raise exception 'Inventory receipt cost exceeds BIGINT range'
        using errcode = '22003';
    end if;
  end if;

  quantity_after := v_quantity_after::bigint;
  cost_basis_after_cents := v_cost_after::bigint;
  cost_effect_cents := p_incoming_cost_cents;
  return next;
end;
$$;

create or replace function private.apply_costed_inventory_issue(
  p_quantity_before bigint,
  p_cost_basis_before_cents bigint,
  p_quantity_out bigint
) returns table (
  quantity_after bigint,
  cost_basis_after_cents bigint,
  cost_effect_cents bigint,
  cogs_cents bigint
)
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $$
begin
  if p_quantity_before is null or p_quantity_before <= 0
     or p_quantity_out is null or p_quantity_out <= 0
     or (p_cost_basis_before_cents is not null
         and p_cost_basis_before_cents < 0) then
    raise exception 'Invalid inventory issue cost-basis state'
      using errcode = '22023';
  end if;
  if p_quantity_out > p_quantity_before then
    raise exception 'Insufficient stock for inventory issue'
      using errcode = '22023';
  end if;

  quantity_after := p_quantity_before - p_quantity_out;
  if p_cost_basis_before_cents is null then
    -- Historical COGS is unknown, but zero remaining stock has zero basis.
    cost_basis_after_cents := case when quantity_after = 0 then 0 else null end;
    cost_effect_cents := null;
    cogs_cents := null;
  else
    -- Full depletion takes all residual cents, never a proportional estimate.
    cogs_cents := case when quantity_after = 0
      then p_cost_basis_before_cents
      else private.calculate_basis_amount_cents(
        p_cost_basis_before_cents, p_quantity_out, p_quantity_before)
      end;
    cost_basis_after_cents := p_cost_basis_before_cents - cogs_cents;
    cost_effect_cents := -cogs_cents;
  end if;
  return next;
end;
$$;

revoke all on function private.apply_costed_inventory_receipt(bigint, bigint, bigint, bigint)
  from public, anon, authenticated, service_role;
revoke all on function private.apply_costed_inventory_issue(bigint, bigint, bigint)
  from public, anon, authenticated, service_role;
