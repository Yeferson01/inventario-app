-- Fase 4.1 - POS cash core
-- Objetivo:
-- Crear cash_registers y cash_sessions para controlar apertura/cierre de caja.
--
-- Nota:
-- No se modifica todavía sales.
-- No se crean todavía sale_payments ni receipt_sequences.

begin;

-- =========================================================
-- CASH REGISTERS
-- Caja física/lógica dentro de una sucursal.
-- =========================================================

create table if not exists public.cash_registers (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,

  name text not null,
  status text not null default 'active',

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',

  constraint cash_registers_status_check
    check (status in ('active', 'inactive')),

  constraint cash_registers_version_positive
    check (version >= 1),

  constraint cash_registers_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

create unique index if not exists cash_registers_business_branch_name_active_unique
on public.cash_registers (business_id, branch_id, lower(name))
where deleted_at is null;

create index if not exists cash_registers_business_branch_active_idx
on public.cash_registers (business_id, branch_id, status)
where deleted_at is null;

comment on table public.cash_registers
is 'Physical or logical cash registers for POS operations within a branch.';

comment on column public.cash_registers.branch_id
is 'Branch where this cash register operates.';

-- =========================================================
-- CASH SESSIONS
-- Apertura/cierre operativo de caja.
-- =========================================================

create table if not exists public.cash_sessions (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,

  opened_by uuid not null references public.profiles(id) on delete restrict,
  closed_by uuid references public.profiles(id) on delete set null,

  opening_amount numeric(14,2) not null default 0,
  expected_closing_amount numeric(14,2),
  actual_closing_amount numeric(14,2),
  difference_amount numeric(14,2),

  status text not null default 'open',

  opened_at timestamp without time zone default now(),
  closed_at timestamp without time zone,

  notes text,

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',

  constraint cash_sessions_opening_amount_non_negative
    check (opening_amount >= 0),

  constraint cash_sessions_expected_closing_amount_non_negative
    check (expected_closing_amount is null or expected_closing_amount >= 0),

  constraint cash_sessions_actual_closing_amount_non_negative
    check (actual_closing_amount is null or actual_closing_amount >= 0),

  constraint cash_sessions_status_check
    check (status in ('open', 'closed', 'cancelled')),

  constraint cash_sessions_version_positive
    check (version >= 1),

  constraint cash_sessions_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint cash_sessions_closed_requires_closed_at
    check (
      status <> 'closed'
      or closed_at is not null
    ),

  constraint cash_sessions_open_has_no_closed_at
    check (
      status <> 'open'
      or closed_at is null
    )
);

-- Solo una sesión abierta por caja.
create unique index if not exists cash_sessions_one_open_per_register
on public.cash_sessions (cash_register_id)
where status = 'open'
  and deleted_at is null;

create index if not exists cash_sessions_business_branch_status_idx
on public.cash_sessions (business_id, branch_id, status)
where deleted_at is null;

create index if not exists cash_sessions_register_opened_at_idx
on public.cash_sessions (cash_register_id, opened_at desc)
where deleted_at is null;

comment on table public.cash_sessions
is 'Cash register sessions for opening, operating and closing POS cash control.';

comment on column public.cash_sessions.opening_amount
is 'Initial cash amount declared when opening the cash session.';

comment on column public.cash_sessions.expected_closing_amount
is 'Expected closing amount calculated from opening amount and cash movements.';

comment on column public.cash_sessions.actual_closing_amount
is 'Actual counted cash amount entered during closing.';

comment on column public.cash_sessions.difference_amount
is 'Difference between actual and expected closing amount.';

-- =========================================================
-- UPDATED_AT TRIGGERS
-- =========================================================

drop trigger if exists trg_cash_registers_updated_at on public.cash_registers;

create trigger trg_cash_registers_updated_at
before update on public.cash_registers
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_cash_sessions_updated_at on public.cash_sessions;

create trigger trg_cash_sessions_updated_at
before update on public.cash_sessions
for each row
execute function public.update_updated_at_column();

-- =========================================================
-- VERSION TRIGGERS
-- =========================================================

drop trigger if exists trg_cash_registers_increment_version on public.cash_registers;

create trigger trg_cash_registers_increment_version
before update on public.cash_registers
for each row
execute function public.increment_row_version();

drop trigger if exists trg_cash_sessions_increment_version on public.cash_sessions;

create trigger trg_cash_sessions_increment_version
before update on public.cash_sessions
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.cash_registers enable row level security;
alter table public.cash_sessions enable row level security;

-- =========================================================
-- CASH REGISTERS POLICIES
-- =========================================================

drop policy if exists cash_registers_select_allowed on public.cash_registers;
drop policy if exists cash_registers_insert_allowed on public.cash_registers;
drop policy if exists cash_registers_update_allowed on public.cash_registers;
drop policy if exists cash_registers_soft_delete_allowed on public.cash_registers;
drop policy if exists cash_registers_delete_blocked on public.cash_registers;

create policy cash_registers_select_allowed
on public.cash_registers
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'cash.open')
    or private.has_business_permission(business_id, 'cash.close')
    or private.has_business_permission(business_id, 'settings.branches')
  )
);

create policy cash_registers_insert_allowed
on public.cash_registers
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'settings.branches')
);

create policy cash_registers_update_allowed
on public.cash_registers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_permission(business_id, branch_id, 'settings.branches')
)
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'settings.branches')
);

create policy cash_registers_soft_delete_allowed
on public.cash_registers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_permission(business_id, branch_id, 'settings.branches')
)
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is not null
  and private.has_branch_permission(business_id, branch_id, 'settings.branches')
);

create policy cash_registers_delete_blocked
on public.cash_registers
for delete
to authenticated
using (false);

-- =========================================================
-- CASH SESSIONS POLICIES
-- =========================================================

drop policy if exists cash_sessions_select_allowed on public.cash_sessions;
drop policy if exists cash_sessions_insert_allowed on public.cash_sessions;
drop policy if exists cash_sessions_update_allowed on public.cash_sessions;
drop policy if exists cash_sessions_delete_blocked on public.cash_sessions;

create policy cash_sessions_select_allowed
on public.cash_sessions
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'cash.open')
    or private.has_business_permission(business_id, 'cash.close')
    or private.has_business_permission(business_id, 'reports.cash')
  )
);

create policy cash_sessions_insert_allowed
on public.cash_sessions
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and cash_register_id is not null
  and deleted_at is null
  and status = 'open'
  and opened_by = auth.uid()
  and private.has_branch_permission(business_id, branch_id, 'cash.open')
);

create policy cash_sessions_update_allowed
on public.cash_sessions
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'cash.close')
    or private.has_business_permission(business_id, 'cash.adjust')
  )
)
with check (
  business_id is not null
  and branch_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'cash.close')
    or private.has_business_permission(business_id, 'cash.adjust')
  )
);

create policy cash_sessions_delete_blocked
on public.cash_sessions
for delete
to authenticated
using (false);

commit;