-- W2A: internal exact-money primitive. Amount and result are minor units.
-- Quantity uses the quoted basis directly; no rounded per-gram price exists.
create or replace function private.calculate_basis_amount_cents(
  p_base_amount_cents bigint,
  p_quantity bigint,
  p_basis_quantity bigint
) returns bigint
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $$
declare
  v_numerator numeric;
  v_quotient numeric;
  v_remainder numeric;
begin
  if p_base_amount_cents is null or p_quantity is null
     or p_basis_quantity is null or p_base_amount_cents < 0
     or p_quantity < 0 or p_basis_quantity <= 0 then
    raise exception 'Exact basis amount requires nonnegative amount/quantity and positive basis'
      using errcode = '22023';
  end if;

  -- NUMERIC multiplication avoids BIGINT overflow before division.
  v_numerator := p_base_amount_cents::numeric * p_quantity::numeric;
  v_quotient := div(v_numerator, p_basis_quantity::numeric);
  v_remainder := mod(v_numerator, p_basis_quantity::numeric);
  if 2 * v_remainder >= p_basis_quantity::numeric then
    v_quotient := v_quotient + 1;
  end if;

  if v_quotient > 9223372036854775807::numeric then
    raise exception 'Exact basis amount exceeds BIGINT range'
      using errcode = '22003';
  end if;
  return v_quotient::bigint;
end;
$$;

-- This is not a client RPC. Future server-side callers can invoke it through
-- their own authorized SECURITY DEFINER contract.
revoke all on function private.calculate_basis_amount_cents(bigint, bigint, bigint)
  from public, anon, authenticated, service_role;
