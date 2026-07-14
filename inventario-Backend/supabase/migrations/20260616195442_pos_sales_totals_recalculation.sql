-- Fase 4.7 - POS sales totals recalculation
-- Objetivo:
-- Recalcular automáticamente totales de sales desde sale_items y sale_payments.
--
-- Nota:
-- Esta migración no bloquea todavía ventas inconsistentes con constraints fuertes.
-- Primero dejamos cálculo automático y funciones reutilizables.

begin;

-- =========================================================
-- Helper: recalculate_sale_totals
-- =========================================================

create or replace function public.recalculate_sale_totals(
  p_sale_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_items_subtotal numeric(14,2);
  v_items_discount numeric(14,2);
  v_items_tax numeric(14,2);
  v_items_total numeric(14,2);
  v_paid_total numeric(14,2);
  v_change_amount numeric(14,2);
begin
  if p_sale_id is null then
    raise exception 'p_sale_id is required';
  end if;

  select
    coalesce(sum(si.subtotal), 0)::numeric(14,2),
    coalesce(sum(si.discount_amount), 0)::numeric(14,2),
    coalesce(sum(si.tax_amount), 0)::numeric(14,2),
    coalesce(sum(si.total), 0)::numeric(14,2)
  into
    v_items_subtotal,
    v_items_discount,
    v_items_tax,
    v_items_total
  from public.sale_items si
  where si.sale_id = p_sale_id
    and si.deleted_at is null;

  select
    coalesce(sum(sp.amount), 0)::numeric(14,2)
  into
    v_paid_total
  from public.sale_payments sp
  where sp.sale_id = p_sale_id
    and sp.deleted_at is null
    and sp.status = 'completed';

  v_change_amount := greatest(v_paid_total - v_items_total, 0)::numeric(14,2);

  update public.sales s
  set
    subtotal = v_items_subtotal,
    discount_total = v_items_discount,
    tax_total = v_items_tax,
    total = v_items_total,
    paid_total = v_paid_total,
    change_amount = v_change_amount,
    updated_at = now()
  where s.id = p_sale_id
    and s.deleted_at is null;
end;
$$;

comment on function public.recalculate_sale_totals(uuid)
is 'Recalculates sales totals from active sale_items and completed sale_payments.';

revoke all on function public.recalculate_sale_totals(uuid) from public;
grant execute on function public.recalculate_sale_totals(uuid) to authenticated;
grant execute on function public.recalculate_sale_totals(uuid) to service_role;

-- =========================================================
-- Trigger function: after sale_items change
-- =========================================================

create or replace function private.recalculate_sale_totals_from_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale_id uuid;
begin
  v_sale_id := coalesce(new.sale_id, old.sale_id);

  if v_sale_id is not null then
    perform public.recalculate_sale_totals(v_sale_id);
  end if;

  return coalesce(new, old);
end;
$$;

comment on function private.recalculate_sale_totals_from_item()
is 'Trigger helper that recalculates sale totals after sale_items changes.';

-- =========================================================
-- Trigger function: after sale_payments change
-- =========================================================

create or replace function private.recalculate_sale_totals_from_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale_id uuid;
begin
  v_sale_id := coalesce(new.sale_id, old.sale_id);

  if v_sale_id is not null then
    perform public.recalculate_sale_totals(v_sale_id);
  end if;

  return coalesce(new, old);
end;
$$;

comment on function private.recalculate_sale_totals_from_payment()
is 'Trigger helper that recalculates sale paid_total and change_amount after sale_payments changes.';

-- =========================================================
-- Triggers: sale_items
-- =========================================================

drop trigger if exists trg_sale_items_recalculate_sale_totals_insert
on public.sale_items;

create trigger trg_sale_items_recalculate_sale_totals_insert
after insert on public.sale_items
for each row
execute function private.recalculate_sale_totals_from_item();

drop trigger if exists trg_sale_items_recalculate_sale_totals_update
on public.sale_items;

create trigger trg_sale_items_recalculate_sale_totals_update
after update of quantity, unit_price, subtotal, discount_amount, tax_amount, total, deleted_at
on public.sale_items
for each row
execute function private.recalculate_sale_totals_from_item();

drop trigger if exists trg_sale_items_recalculate_sale_totals_delete
on public.sale_items;

create trigger trg_sale_items_recalculate_sale_totals_delete
after delete on public.sale_items
for each row
execute function private.recalculate_sale_totals_from_item();

-- =========================================================
-- Triggers: sale_payments
-- =========================================================

drop trigger if exists trg_sale_payments_recalculate_sale_totals_insert
on public.sale_payments;

create trigger trg_sale_payments_recalculate_sale_totals_insert
after insert on public.sale_payments
for each row
execute function private.recalculate_sale_totals_from_payment();

drop trigger if exists trg_sale_payments_recalculate_sale_totals_update
on public.sale_payments;

create trigger trg_sale_payments_recalculate_sale_totals_update
after update of amount, status, deleted_at
on public.sale_payments
for each row
execute function private.recalculate_sale_totals_from_payment();

drop trigger if exists trg_sale_payments_recalculate_sale_totals_delete
on public.sale_payments;

create trigger trg_sale_payments_recalculate_sale_totals_delete
after delete on public.sale_payments
for each row
execute function private.recalculate_sale_totals_from_payment();

-- =========================================================
-- Backfill: recalcular ventas existentes
-- =========================================================

do $$
declare
  v_sale_id uuid;
begin
  for v_sale_id in
    select id
    from public.sales
    where deleted_at is null
  loop
    perform public.recalculate_sale_totals(v_sale_id);
  end loop;
end;
$$;

commit;