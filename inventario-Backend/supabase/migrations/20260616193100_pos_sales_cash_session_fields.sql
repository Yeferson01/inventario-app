-- Fase 4.3 - POS sales cash session fields
-- Objetivo:
-- Conectar sales con branch_id y cash_session_id.
-- Agregar campos base para totales POS, recibos, idempotencia y anulación.
--
-- Nota:
-- No se crea todavía sale_payments.
-- No se obliga todavía cash_session_id NOT NULL para mantener compatibilidad con datos existentes/importaciones.

begin;

-- =========================================================
-- 1. Agregar columnas POS a sales
-- =========================================================

alter table public.sales
  add column if not exists branch_id uuid references public.branches(id) on delete restrict,
  add column if not exists cash_session_id uuid references public.cash_sessions(id) on delete restrict,
  add column if not exists device_id uuid,
  add column if not exists subtotal numeric(14,2) not null default 0,
  add column if not exists discount_total numeric(14,2) not null default 0,
  add column if not exists tax_total numeric(14,2) not null default 0,
  add column if not exists paid_total numeric(14,2) not null default 0,
  add column if not exists change_amount numeric(14,2) not null default 0,
  add column if not exists currency text not null default 'COP',
  add column if not exists receipt_number text,
  add column if not exists idempotency_key text,
  add column if not exists voided_at timestamp without time zone,
  add column if not exists voided_by uuid references public.profiles(id) on delete set null,
  add column if not exists void_reason text;

comment on column public.sales.branch_id
is 'Branch where the sale occurred.';

comment on column public.sales.cash_session_id
is 'Cash session associated with the sale, when the sale is handled through POS cash control.';

comment on column public.sales.device_id
is 'Device/app installation that originated the sale. Will reference app_devices in a future sync phase.';

comment on column public.sales.subtotal
is 'Sale subtotal before discounts and taxes.';

comment on column public.sales.discount_total
is 'Total discount amount applied to the sale.';

comment on column public.sales.tax_total
is 'Total tax amount applied to the sale.';

comment on column public.sales.paid_total
is 'Total amount paid by customer across all payment methods.';

comment on column public.sales.change_amount
is 'Cash change returned to customer.';

comment on column public.sales.receipt_number
is 'Receipt or invoice number generated for the sale.';

comment on column public.sales.idempotency_key
is 'Unique key to avoid duplicated sales during offline sync retries.';

comment on column public.sales.voided_at
is 'Timestamp when the sale was voided.';

comment on column public.sales.voided_by
is 'Profile that voided the sale.';

comment on column public.sales.void_reason
is 'Reason for voiding the sale.';

-- =========================================================
-- 2. Backfill branch_id para ventas existentes
-- =========================================================

with default_branches as (
  select distinct on (br.business_id)
    br.business_id,
    br.id as branch_id
  from public.branches br
  where br.deleted_at is null
    and br.status = 'active'
  order by
    br.business_id,
    case when lower(br.name) = lower('Principal') then 0 else 1 end,
    br.created_at asc
)
update public.sales s
set branch_id = db.branch_id
from default_branches db
where s.business_id = db.business_id
  and s.business_id is not null
  and s.branch_id is null;

-- =========================================================
-- 3. Constraints de totales y estado
-- =========================================================

alter table public.sales
  add constraint sales_subtotal_non_negative
  check (subtotal >= 0)
  not valid;

alter table public.sales
  add constraint sales_discount_total_non_negative
  check (discount_total >= 0)
  not valid;

alter table public.sales
  add constraint sales_tax_total_non_negative
  check (tax_total >= 0)
  not valid;

alter table public.sales
  add constraint sales_paid_total_non_negative
  check (paid_total >= 0)
  not valid;

alter table public.sales
  add constraint sales_change_amount_non_negative
  check (change_amount >= 0)
  not valid;

alter table public.sales
  add constraint sales_currency_not_blank
  check (length(trim(currency)) > 0)
  not valid;

alter table public.sales
  add constraint sales_void_fields_consistency
  check (
    (
      voided_at is null
      and voided_by is null
      and void_reason is null
    )
    or
    (
      voided_at is not null
      and voided_by is not null
    )
  )
  not valid;

-- =========================================================
-- 4. Índices
-- =========================================================

create index if not exists sales_business_branch_created_idx
on public.sales (business_id, branch_id, created_at desc)
where deleted_at is null;

create index if not exists sales_cash_session_created_idx
on public.sales (cash_session_id, created_at desc)
where deleted_at is null
  and cash_session_id is not null;

create unique index if not exists sales_idempotency_key_unique
on public.sales (idempotency_key)
where idempotency_key is not null;

create unique index if not exists sales_receipt_unique
on public.sales (business_id, branch_id, receipt_number)
where receipt_number is not null
  and deleted_at is null;

-- =========================================================
-- 5. Integridad: branch_id debe pertenecer al mismo negocio
-- =========================================================

create or replace function private.validate_sale_branch_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.branch_id is not null then
    if not exists (
      select 1
      from public.branches br
      where br.id = new.branch_id
        and br.business_id = new.business_id
        and br.deleted_at is null
    ) then
      raise exception 'sales.branch_id must belong to the same business_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_sale_branch_consistency()
is 'Ensures sales.branch_id belongs to the same business_id.';

drop trigger if exists trg_sales_validate_branch_consistency
on public.sales;

create trigger trg_sales_validate_branch_consistency
before insert or update of business_id, branch_id
on public.sales
for each row
execute function private.validate_sale_branch_consistency();

-- =========================================================
-- 6. Integridad: cash_session_id debe pertenecer al mismo negocio/sucursal
-- =========================================================

create or replace function private.validate_sale_cash_session_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.cash_session_id is not null then
    if not exists (
      select 1
      from public.cash_sessions cs
      where cs.id = new.cash_session_id
        and cs.business_id = new.business_id
        and cs.branch_id = new.branch_id
        and cs.deleted_at is null
    ) then
      raise exception 'sales.cash_session_id must belong to the same business_id and branch_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_sale_cash_session_consistency()
is 'Ensures sales.cash_session_id belongs to the same business_id and branch_id.';

drop trigger if exists trg_sales_validate_cash_session_consistency
on public.sales;

create trigger trg_sales_validate_cash_session_consistency
before insert or update of business_id, branch_id, cash_session_id
on public.sales
for each row
execute function private.validate_sale_cash_session_consistency();

-- =========================================================
-- 7. Actualizar RLS de sales para considerar branch_id
-- =========================================================

drop policy if exists sales_select_allowed on public.sales;
drop policy if exists sales_insert_allowed on public.sales;
drop policy if exists sales_update_allowed on public.sales;
drop policy if exists sales_soft_delete_allowed on public.sales;
drop policy if exists sales_delete_blocked on public.sales;

create policy sales_select_allowed
on public.sales
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and (
    private.has_business_permission(business_id, 'sales.read')
    or private.has_business_permission(business_id, 'reports.sales')
    or private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

create policy sales_insert_allowed
on public.sales
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'sales.create')
);

create policy sales_update_allowed
on public.sales
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and (
    private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'sales.create')
  )
)
with check (
  business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and (
    private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

create policy sales_soft_delete_allowed
on public.sales
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'sales.void')
)
with check (
  business_id is not null
  and deleted_at is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'sales.void')
);

create policy sales_delete_blocked
on public.sales
for delete
to authenticated
using (false);

commit;