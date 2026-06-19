-- Fase 6.12C.1 - Patch sale_payments professional columns
-- Objetivo:
-- Alinear sale_payments con el flujo POS offline-first.
--
-- Agrega columnas profesionales requeridas por apply_sync_sale_payment_mutation:
-- - reference_number
-- - status
-- - paid_at
-- - idempotency_key
-- - sync_status
-- - version
-- - metadata
-- - auditoría / soft delete si hiciera falta

begin;

alter table public.sale_payments
add column if not exists reference_number text;

alter table public.sale_payments
add column if not exists status text not null default 'completed';

alter table public.sale_payments
add column if not exists paid_at timestamp without time zone not null default now();

alter table public.sale_payments
add column if not exists idempotency_key text;

alter table public.sale_payments
add column if not exists sync_status text not null default 'synced';

alter table public.sale_payments
add column if not exists version integer not null default 1;

alter table public.sale_payments
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.sale_payments
add column if not exists created_by uuid references public.profiles(id);

alter table public.sale_payments
add column if not exists updated_by uuid references public.profiles(id);

alter table public.sale_payments
add column if not exists deleted_by uuid references public.profiles(id);

alter table public.sale_payments
add column if not exists delete_reason text;

alter table public.sale_payments
add column if not exists deleted_at timestamp without time zone;

alter table public.sale_payments
add column if not exists updated_at timestamp without time zone default now();

-- =========================================================
-- CONSTRAINTS
-- =========================================================

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sale_payments_status_allowed'
      and conrelid = 'public.sale_payments'::regclass
  ) then
    alter table public.sale_payments
    add constraint sale_payments_status_allowed
    check (
      status in (
        'pending',
        'completed',
        'failed',
        'cancelled',
        'refunded',
        'voided'
      )
    ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sale_payments_sync_status_allowed'
      and conrelid = 'public.sale_payments'::regclass
  ) then
    alter table public.sale_payments
    add constraint sale_payments_sync_status_allowed
    check (
      sync_status in (
        'synced',
        'pending',
        'conflict',
        'error'
      )
    ) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'sale_payments_version_positive'
      and conrelid = 'public.sale_payments'::regclass
  ) then
    alter table public.sale_payments
    add constraint sale_payments_version_positive
    check (version >= 1) not valid;
  end if;
end $$;

-- Validar constraints nuevas.
alter table public.sale_payments
validate constraint sale_payments_status_allowed;

alter table public.sale_payments
validate constraint sale_payments_sync_status_allowed;

alter table public.sale_payments
validate constraint sale_payments_version_positive;

-- =========================================================
-- ÍNDICES
-- =========================================================

create unique index if not exists sale_payments_business_idempotency_unique
on public.sale_payments (business_id, idempotency_key)
where idempotency_key is not null
  and deleted_at is null;

create index if not exists idx_sale_payments_sale_active
on public.sale_payments (sale_id)
where deleted_at is null;

create index if not exists idx_sale_payments_business_status
on public.sale_payments (business_id, status)
where deleted_at is null;

create index if not exists idx_sale_payments_paid_at
on public.sale_payments (paid_at)
where deleted_at is null;

-- =========================================================
-- TRIGGER VERSION / UPDATED_AT
-- =========================================================

drop trigger if exists trg_sale_payments_version on public.sale_payments;

create trigger trg_sale_payments_version
before update on public.sale_payments
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- COMENTARIOS
-- =========================================================

comment on column public.sale_payments.reference_number
is 'Optional payment processor reference, voucher number, transaction id or external reference.';

comment on column public.sale_payments.status
is 'Payment status: pending, completed, failed, cancelled, refunded or voided.';

comment on column public.sale_payments.paid_at
is 'Timestamp when the payment was made according to the client/server.';

comment on column public.sale_payments.idempotency_key
is 'Client/server idempotency key to avoid duplicate offline payment application.';

comment on column public.sale_payments.sync_status
is 'Offline sync status for this payment row.';

comment on column public.sale_payments.version
is 'Optimistic concurrency version. Incremented on business updates.';

comment on column public.sale_payments.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

commit;