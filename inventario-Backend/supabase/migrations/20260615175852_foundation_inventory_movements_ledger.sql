-- Fase 1.6 - Foundation inventory movements ledger
-- Objetivo:
-- Fortalecer inventory_movements como ledger inmutable de inventario.
--
-- Reglas:
-- 1. Los movimientos de inventario se insertan.
-- 2. No se actualizan funcionalmente.
-- 3. No se borran.
-- 4. Las correcciones se hacen con movimientos reversos o ajustes.
--
-- Nota:
-- No agregamos branch_id todavía porque branches se creará en Fase 2.

begin;

-- =========================================================
-- Metadata y campos de trazabilidad
-- =========================================================

alter table public.inventory_movements
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists device_id uuid,
  add column if not exists source_type text,
  add column if not exists source_id uuid,
  add column if not exists unit_cost numeric(14,2),
  add column if not exists idempotency_key text,
  add column if not exists sync_status text not null default 'synced',
  add column if not exists version integer not null default 1,
  add column if not exists occurred_at timestamptz not null default now(),
  add column if not exists reversed_movement_id uuid references public.inventory_movements(id) on delete restrict,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- =========================================================
-- Constraints
-- =========================================================

alter table public.inventory_movements
  add constraint inventory_movements_version_positive
  check (version >= 1)
  not valid;

alter table public.inventory_movements
  add constraint inventory_movements_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

alter table public.inventory_movements
  add constraint inventory_movements_unit_cost_non_negative
  check (unit_cost is null or unit_cost >= 0)
  not valid;

alter table public.inventory_movements
  add constraint inventory_movements_no_self_reversal
  check (reversed_movement_id is null or reversed_movement_id <> id)
  not valid;

-- =========================================================
-- Idempotencia
-- =========================================================

create unique index if not exists inventory_movements_idempotency_key_unique
on public.inventory_movements (idempotency_key)
where idempotency_key is not null;

-- =========================================================
-- Bloquear updates/deletes funcionales
-- =========================================================

create or replace function public.prevent_inventory_movements_update()
returns trigger
language plpgsql
as $$
begin
  raise exception 'inventory_movements is an immutable ledger. Create a reversal or adjustment movement instead of updating existing rows.';
end;
$$;

create or replace function public.prevent_inventory_movements_delete()
returns trigger
language plpgsql
as $$
begin
  raise exception 'inventory_movements cannot be deleted. Create a reversal or adjustment movement instead.';
end;
$$;

drop trigger if exists trg_inventory_movements_prevent_update on public.inventory_movements;

create trigger trg_inventory_movements_prevent_update
before update on public.inventory_movements
for each row
execute function public.prevent_inventory_movements_update();

drop trigger if exists trg_inventory_movements_prevent_delete on public.inventory_movements;

create trigger trg_inventory_movements_prevent_delete
before delete on public.inventory_movements
for each row
execute function public.prevent_inventory_movements_delete();

-- =========================================================
-- Comments
-- =========================================================

comment on column public.inventory_movements.created_by is 'Profile that created the inventory movement.';
comment on column public.inventory_movements.device_id is 'Device that originated this movement. Will reference app_devices in a future phase.';
comment on column public.inventory_movements.source_type is 'Business source of the movement, e.g. sale, purchase, stock_count, manual_adjustment, reversal.';
comment on column public.inventory_movements.source_id is 'Identifier of the business entity that originated this movement.';
comment on column public.inventory_movements.unit_cost is 'Unit cost at the moment of the movement, useful for valuation.';
comment on column public.inventory_movements.idempotency_key is 'Unique key to avoid duplicated inventory movements during offline sync retries.';
comment on column public.inventory_movements.sync_status is 'Synchronization status for offline-first workflows.';
comment on column public.inventory_movements.version is 'Ledger row version. Kept for consistency, but rows should not be updated functionally.';
comment on column public.inventory_movements.occurred_at is 'Business timestamp of when the inventory movement occurred.';
comment on column public.inventory_movements.reversed_movement_id is 'Original movement reversed by this movement, when applicable.';
comment on column public.inventory_movements.metadata is 'Additional structured metadata for auditing, sync or import details.';

comment on function public.prevent_inventory_movements_update()
is 'Prevents updates to inventory_movements because it is an immutable inventory ledger.';

comment on function public.prevent_inventory_movements_delete()
is 'Prevents deletes from inventory_movements because it is an immutable inventory ledger.';

commit;