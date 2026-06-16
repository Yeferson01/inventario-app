-- Fase 4.4 - POS sale payments
-- Objetivo:
-- Crear sale_payments para soportar pagos separados y pagos mixtos.
--
-- Nota:
-- No eliminamos sales.payment_method todavía.
-- sales.payment_method queda como campo legacy/compatibilidad temporal.

begin;

-- =========================================================
-- SALE PAYMENTS
-- =========================================================

create table if not exists public.sale_payments (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  sale_id uuid not null references public.sales(id) on delete restrict,

  payment_method text not null,
  amount numeric(14,2) not null,
  currency text not null default 'COP',

  reference text,
  provider text,
  status text not null default 'completed',

  paid_at timestamp without time zone default now(),

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',
  idempotency_key text,
  metadata jsonb not null default '{}'::jsonb,

  constraint sale_payments_method_check
    check (
      payment_method in (
        'cash',
        'card',
        'bank_transfer',
        'nequi',
        'daviplata',
        'credit',
        'other'
      )
    ),

  constraint sale_payments_amount_positive
    check (amount > 0),

  constraint sale_payments_currency_not_blank
    check (length(trim(currency)) > 0),

  constraint sale_payments_status_check
    check (
      status in (
        'pending',
        'completed',
        'failed',
        'refunded',
        'cancelled'
      )
    ),

  constraint sale_payments_version_positive
    check (version >= 1),

  constraint sale_payments_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

comment on table public.sale_payments
is 'Payments associated with sales. Supports mixed payments and payment method reporting.';

comment on column public.sale_payments.payment_method
is 'Payment method used for this payment row. Mixed payments are represented by multiple sale_payments rows.';

comment on column public.sale_payments.amount
is 'Amount applied to the sale for this payment method.';

comment on column public.sale_payments.reference
is 'External payment reference, voucher number or transaction reference.';

comment on column public.sale_payments.provider
is 'Payment provider or processor, e.g. bank, card processor, Nequi, Daviplata.';

comment on column public.sale_payments.idempotency_key
is 'Unique key to avoid duplicated payment rows during offline sync retries.';

comment on column public.sale_payments.metadata
is 'Additional structured payment metadata.';

-- =========================================================
-- Índices
-- =========================================================

create index if not exists sale_payments_business_created_idx
on public.sale_payments (business_id, created_at desc)
where deleted_at is null;

create index if not exists sale_payments_sale_idx
on public.sale_payments (sale_id)
where deleted_at is null;

create index if not exists sale_payments_business_method_created_idx
on public.sale_payments (business_id, payment_method, created_at desc)
where deleted_at is null;

create index if not exists sale_payments_business_status_created_idx
on public.sale_payments (business_id, status, created_at desc)
where deleted_at is null;

create unique index if not exists sale_payments_idempotency_key_unique
on public.sale_payments (idempotency_key)
where idempotency_key is not null;

-- =========================================================
-- Helpers para RLS e integridad
-- =========================================================

create or replace function private.sale_branch_id(
  p_sale_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select s.branch_id
  from public.sales s
  where s.id = p_sale_id
  limit 1;
$$;

comment on function private.sale_branch_id(uuid)
is 'Returns the branch_id for a sale. Used by RLS policies on sale_payments.';

revoke all on function private.sale_branch_id(uuid) from public;
grant execute on function private.sale_branch_id(uuid) to authenticated;
grant execute on function private.sale_branch_id(uuid) to service_role;

create or replace function private.validate_sale_payment_sale_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.sales s
    where s.id = new.sale_id
      and s.business_id = new.business_id
      and s.deleted_at is null
  ) then
    raise exception 'sale_payments.sale_id must belong to the same business_id and reference an active sale';
  end if;

  return new;
end;
$$;

comment on function private.validate_sale_payment_sale_consistency()
is 'Ensures sale_payments.sale_id belongs to the same business_id.';

drop trigger if exists trg_sale_payments_validate_sale_consistency
on public.sale_payments;

create trigger trg_sale_payments_validate_sale_consistency
before insert or update of business_id, sale_id
on public.sale_payments
for each row
execute function private.validate_sale_payment_sale_consistency();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_sale_payments_updated_at on public.sale_payments;

create trigger trg_sale_payments_updated_at
before update on public.sale_payments
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_sale_payments_increment_version on public.sale_payments;

create trigger trg_sale_payments_increment_version
before update on public.sale_payments
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.sale_payments enable row level security;

drop policy if exists sale_payments_select_allowed on public.sale_payments;
drop policy if exists sale_payments_insert_allowed on public.sale_payments;
drop policy if exists sale_payments_update_allowed on public.sale_payments;
drop policy if exists sale_payments_soft_delete_allowed on public.sale_payments;
drop policy if exists sale_payments_delete_blocked on public.sale_payments;

-- SELECT:
-- Ver pagos requiere permisos relacionados con ventas/caja/reportes
-- y acceso a la sucursal de la venta.
create policy sale_payments_select_allowed
on public.sale_payments
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.read')
    or private.has_business_permission(business_id, 'sales.create')
    or private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'reports.sales')
    or private.has_business_permission(business_id, 'reports.cash')
  )
);

-- INSERT:
-- Crear pagos requiere sales.create.
create policy sale_payments_insert_allowed
on public.sale_payments
for insert
to authenticated
with check (
  business_id is not null
  and sale_id is not null
  and deleted_at is null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_permission(business_id, private.sale_branch_id(sale_id), 'sales.create')
  )
  and private.has_business_permission(business_id, 'sales.create')
);

-- UPDATE:
-- Cambios de estado/referencia requieren sales.refund, cash.adjust o sales.create.
-- Esto es temporal durante desarrollo. Luego restringiremos pagos de ventas finalizadas.
create policy sale_payments_update_allowed
on public.sale_payments
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'cash.adjust')
    or private.has_business_permission(business_id, 'sales.create')
  )
)
with check (
  business_id is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'cash.adjust')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- SOFT DELETE:
-- No es el flujo final para pagos. Más adelante usaremos status cancelled/refunded.
-- Mientras tanto, solo cash.adjust o sales.refund.
create policy sale_payments_soft_delete_allowed
on public.sale_payments
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'cash.adjust')
  )
)
with check (
  business_id is not null
  and deleted_at is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.refund')
    or private.has_business_permission(business_id, 'cash.adjust')
  )
);

-- DELETE bloqueado.
create policy sale_payments_delete_blocked
on public.sale_payments
for delete
to authenticated
using (false);

commit;