-- Fase 5.11 - Inventory transfers
-- Objetivo:
-- Crear inventory_transfers e inventory_transfer_items para traslados entre sucursales.
--
-- Nota:
-- Esta migración solo crea estructura.
-- La RPC para completar transferencias y generar inventory_movements vendrá después.

begin;

-- =========================================================
-- INVENTORY TRANSFERS
-- =========================================================

create table if not exists public.inventory_transfers (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,

  from_branch_id uuid not null references public.branches(id) on delete restrict,
  to_branch_id uuid not null references public.branches(id) on delete restrict,

  status text not null default 'draft',

  requested_by uuid references public.profiles(id) on delete set null,
  requested_at timestamp without time zone default now(),

  sent_by uuid references public.profiles(id) on delete set null,
  sent_at timestamp without time zone,

  received_by uuid references public.profiles(id) on delete set null,
  received_at timestamp without time zone,

  cancelled_by uuid references public.profiles(id) on delete set null,
  cancelled_at timestamp without time zone,
  cancel_reason text,

  notes text,

  idempotency_key text,

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',
  metadata jsonb not null default '{}'::jsonb,

  constraint inventory_transfers_status_check
    check (status in ('draft', 'in_transit', 'completed', 'cancelled')),

  constraint inventory_transfers_different_branches
    check (from_branch_id <> to_branch_id),

  constraint inventory_transfers_version_positive
    check (version >= 1),

  constraint inventory_transfers_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint inventory_transfers_sent_requires_sent_at
    check (
      status <> 'in_transit'
      or sent_at is not null
    ),

  constraint inventory_transfers_completed_requires_received_at
    check (
      status <> 'completed'
      or received_at is not null
    ),

  constraint inventory_transfers_cancelled_requires_cancelled_at
    check (
      status <> 'cancelled'
      or cancelled_at is not null
    )
);

comment on table public.inventory_transfers
is 'Inventory transfers between branches. Completion generates inventory movements for origin and destination branches.';

comment on column public.inventory_transfers.from_branch_id
is 'Origin branch where stock is deducted.';

comment on column public.inventory_transfers.to_branch_id
is 'Destination branch where stock is added.';

comment on column public.inventory_transfers.idempotency_key
is 'Unique key to avoid duplicate transfer creation during offline sync retries.';

-- =========================================================
-- INVENTORY TRANSFER ITEMS
-- =========================================================

create table if not exists public.inventory_transfer_items (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  inventory_transfer_id uuid not null references public.inventory_transfers(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,

  quantity integer not null,
  unit_cost_snapshot numeric(14,2),

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
  metadata jsonb not null default '{}'::jsonb,

  constraint inventory_transfer_items_quantity_positive
    check (quantity > 0),

  constraint inventory_transfer_items_unit_cost_non_negative
    check (unit_cost_snapshot is null or unit_cost_snapshot >= 0),

  constraint inventory_transfer_items_version_positive
    check (version >= 1),

  constraint inventory_transfer_items_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint inventory_transfer_items_unique_product_per_transfer
    unique (inventory_transfer_id, product_id)
);

comment on table public.inventory_transfer_items
is 'Products and quantities included in an inventory transfer.';

comment on column public.inventory_transfer_items.quantity
is 'Quantity to transfer from origin branch to destination branch.';

comment on column public.inventory_transfer_items.unit_cost_snapshot
is 'Average/unit cost snapshot at the moment of transfer creation.';

-- =========================================================
-- ÍNDICES
-- =========================================================

create index if not exists inventory_transfers_business_status_idx
on public.inventory_transfers (business_id, status)
where deleted_at is null;

create index if not exists inventory_transfers_from_branch_status_idx
on public.inventory_transfers (business_id, from_branch_id, status)
where deleted_at is null;

create index if not exists inventory_transfers_to_branch_status_idx
on public.inventory_transfers (business_id, to_branch_id, status)
where deleted_at is null;

create unique index if not exists inventory_transfers_idempotency_key_unique
on public.inventory_transfers (idempotency_key)
where idempotency_key is not null;

create index if not exists inventory_transfer_items_transfer_idx
on public.inventory_transfer_items (inventory_transfer_id)
where deleted_at is null;

create index if not exists inventory_transfer_items_product_idx
on public.inventory_transfer_items (business_id, product_id)
where deleted_at is null;

-- =========================================================
-- VALIDAR BRANCHES DE TRANSFERENCIA
-- =========================================================

create or replace function private.validate_inventory_transfer_branches()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if not exists (
    select 1
    from public.branches br
    where br.id = new.from_branch_id
      and br.business_id = new.business_id
      and br.deleted_at is null
      and br.status = 'active'
  ) then
    raise exception 'inventory_transfers.from_branch_id must belong to the same active business';
  end if;

  if not exists (
    select 1
    from public.branches br
    where br.id = new.to_branch_id
      and br.business_id = new.business_id
      and br.deleted_at is null
      and br.status = 'active'
  ) then
    raise exception 'inventory_transfers.to_branch_id must belong to the same active business';
  end if;

  if new.from_branch_id = new.to_branch_id then
    raise exception 'inventory_transfers from_branch_id and to_branch_id must be different';
  end if;

  return new;
end;
$$;

comment on function private.validate_inventory_transfer_branches()
is 'Ensures origin and destination branches belong to the same active business and are different.';

drop trigger if exists trg_inventory_transfers_validate_branches
on public.inventory_transfers;

create trigger trg_inventory_transfers_validate_branches
before insert or update of business_id, from_branch_id, to_branch_id
on public.inventory_transfers
for each row
execute function private.validate_inventory_transfer_branches();

-- =========================================================
-- VALIDAR ITEM CONTRA TRANSFERENCIA Y PRODUCTO
-- =========================================================

create or replace function private.validate_inventory_transfer_item_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_transfer record;
begin
  select
    it.business_id,
    it.status,
    it.deleted_at
  into v_transfer
  from public.inventory_transfers it
  where it.id = new.inventory_transfer_id;

  if v_transfer.business_id is null then
    raise exception 'inventory_transfer_items.inventory_transfer_id must reference an existing transfer';
  end if;

  if v_transfer.deleted_at is not null then
    raise exception 'Cannot add items to a deleted transfer';
  end if;

  if v_transfer.status in ('completed', 'cancelled') then
    raise exception 'Cannot modify items for completed or cancelled transfer';
  end if;

  if new.business_id <> v_transfer.business_id then
    raise exception 'inventory_transfer_items.business_id must match inventory_transfers.business_id';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.business_id = new.business_id
      and p.deleted_at is null
  ) then
    raise exception 'inventory_transfer_items.product_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_inventory_transfer_item_consistency()
is 'Ensures transfer items match their parent transfer and product business.';

drop trigger if exists trg_inventory_transfer_items_validate_consistency
on public.inventory_transfer_items;

create trigger trg_inventory_transfer_items_validate_consistency
before insert or update of business_id, inventory_transfer_id, product_id
on public.inventory_transfer_items
for each row
execute function private.validate_inventory_transfer_item_consistency();

-- =========================================================
-- FILL ITEM COST SNAPSHOT
-- =========================================================

create or replace function private.fill_inventory_transfer_item_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_transfer record;
  v_average_cost numeric(14,2);
begin
  select
    it.business_id,
    it.from_branch_id
  into v_transfer
  from public.inventory_transfers it
  where it.id = new.inventory_transfer_id;

  select
    psb.average_cost
  into v_average_cost
  from public.product_stock_balances psb
  where psb.business_id = v_transfer.business_id
    and psb.branch_id = v_transfer.from_branch_id
    and psb.product_id = new.product_id
    and psb.deleted_at is null
  limit 1;

  new.unit_cost_snapshot := coalesce(new.unit_cost_snapshot, v_average_cost);

  return new;
end;
$$;

comment on function private.fill_inventory_transfer_item_defaults()
is 'Fills unit_cost_snapshot from origin branch stock balance when available.';

drop trigger if exists trg_inventory_transfer_items_fill_defaults
on public.inventory_transfer_items;

create trigger trg_inventory_transfer_items_fill_defaults
before insert or update of product_id
on public.inventory_transfer_items
for each row
execute function private.fill_inventory_transfer_item_defaults();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_inventory_transfers_updated_at
on public.inventory_transfers;

create trigger trg_inventory_transfers_updated_at
before update on public.inventory_transfers
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_inventory_transfers_increment_version
on public.inventory_transfers;

create trigger trg_inventory_transfers_increment_version
before update on public.inventory_transfers
for each row
execute function public.increment_row_version_on_business_change();

drop trigger if exists trg_inventory_transfer_items_updated_at
on public.inventory_transfer_items;

create trigger trg_inventory_transfer_items_updated_at
before update on public.inventory_transfer_items
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_inventory_transfer_items_increment_version
on public.inventory_transfer_items;

create trigger trg_inventory_transfer_items_increment_version
before update on public.inventory_transfer_items
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.inventory_transfers enable row level security;
alter table public.inventory_transfer_items enable row level security;

drop policy if exists inventory_transfers_select_allowed on public.inventory_transfers;
drop policy if exists inventory_transfers_insert_allowed on public.inventory_transfers;
drop policy if exists inventory_transfers_update_allowed on public.inventory_transfers;
drop policy if exists inventory_transfers_delete_blocked on public.inventory_transfers;

drop policy if exists inventory_transfer_items_select_allowed on public.inventory_transfer_items;
drop policy if exists inventory_transfer_items_insert_allowed on public.inventory_transfer_items;
drop policy if exists inventory_transfer_items_update_allowed on public.inventory_transfer_items;
drop policy if exists inventory_transfer_items_delete_blocked on public.inventory_transfer_items;

create policy inventory_transfers_select_allowed
on public.inventory_transfers
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_branch_access(business_id, from_branch_id)
    or private.has_branch_access(business_id, to_branch_id)
  )
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'inventory.transfer')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

create policy inventory_transfers_insert_allowed
on public.inventory_transfers
for insert
to authenticated
with check (
  deleted_at is null
  and business_id is not null
  and private.has_branch_permission(business_id, from_branch_id, 'inventory.transfer')
  and private.has_branch_permission(business_id, to_branch_id, 'inventory.transfer')
);

create policy inventory_transfers_update_allowed
on public.inventory_transfers
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_branch_permission(business_id, from_branch_id, 'inventory.transfer')
  and private.has_branch_permission(business_id, to_branch_id, 'inventory.transfer')
)
with check (
  business_id is not null
  and private.has_branch_permission(business_id, from_branch_id, 'inventory.transfer')
  and private.has_branch_permission(business_id, to_branch_id, 'inventory.transfer')
);

create policy inventory_transfers_delete_blocked
on public.inventory_transfers
for delete
to authenticated
using (false);

create policy inventory_transfer_items_select_allowed
on public.inventory_transfer_items
for select
to authenticated
using (
  deleted_at is null
  and exists (
    select 1
    from public.inventory_transfers it
    where it.id = inventory_transfer_items.inventory_transfer_id
      and it.deleted_at is null
      and (
        private.has_branch_access(it.business_id, it.from_branch_id)
        or private.has_branch_access(it.business_id, it.to_branch_id)
      )
      and (
        private.has_business_permission(it.business_id, 'inventory.read')
        or private.has_business_permission(it.business_id, 'inventory.transfer')
        or private.has_business_permission(it.business_id, 'reports.inventory')
      )
  )
);

create policy inventory_transfer_items_insert_allowed
on public.inventory_transfer_items
for insert
to authenticated
with check (
  deleted_at is null
  and exists (
    select 1
    from public.inventory_transfers it
    where it.id = inventory_transfer_items.inventory_transfer_id
      and it.deleted_at is null
      and it.status in ('draft', 'in_transit')
      and private.has_branch_permission(it.business_id, it.from_branch_id, 'inventory.transfer')
      and private.has_branch_permission(it.business_id, it.to_branch_id, 'inventory.transfer')
  )
);

create policy inventory_transfer_items_update_allowed
on public.inventory_transfer_items
for update
to authenticated
using (
  deleted_at is null
  and exists (
    select 1
    from public.inventory_transfers it
    where it.id = inventory_transfer_items.inventory_transfer_id
      and it.deleted_at is null
      and it.status in ('draft', 'in_transit')
      and private.has_branch_permission(it.business_id, it.from_branch_id, 'inventory.transfer')
      and private.has_branch_permission(it.business_id, it.to_branch_id, 'inventory.transfer')
  )
)
with check (
  exists (
    select 1
    from public.inventory_transfers it
    where it.id = inventory_transfer_items.inventory_transfer_id
      and it.deleted_at is null
      and it.status in ('draft', 'in_transit')
      and private.has_branch_permission(it.business_id, it.from_branch_id, 'inventory.transfer')
      and private.has_branch_permission(it.business_id, it.to_branch_id, 'inventory.transfer')
  )
);

create policy inventory_transfer_items_delete_blocked
on public.inventory_transfer_items
for delete
to authenticated
using (false);

commit;