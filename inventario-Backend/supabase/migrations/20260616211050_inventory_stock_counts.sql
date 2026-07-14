-- Fase 5.8 - Inventory stock counts
-- Objetivo:
-- Crear stock_counts y stock_count_items para conteos físicos de inventario.
--
-- Nota:
-- Esta migración solo crea estructura.
-- La función para finalizar conteos y generar inventory_movements vendrá después.

begin;

-- =========================================================
-- STOCK COUNTS
-- =========================================================

create table if not exists public.stock_counts (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,

  name text not null,
  status text not null default 'draft',

  started_by uuid references public.profiles(id) on delete set null,
  started_at timestamp without time zone default now(),

  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamp without time zone,

  cancelled_by uuid references public.profiles(id) on delete set null,
  cancelled_at timestamp without time zone,
  cancel_reason text,

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

  constraint stock_counts_name_not_blank
    check (length(trim(name)) > 0),

  constraint stock_counts_status_check
    check (status in ('draft', 'in_progress', 'completed', 'cancelled')),

  constraint stock_counts_version_positive
    check (version >= 1),

  constraint stock_counts_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint stock_counts_completed_requires_completed_at
    check (
      status <> 'completed'
      or completed_at is not null
    ),

  constraint stock_counts_cancelled_requires_cancelled_at
    check (
      status <> 'cancelled'
      or cancelled_at is not null
    )
);

comment on table public.stock_counts
is 'Physical inventory count sessions by business and branch.';

comment on column public.stock_counts.status
is 'Stock count lifecycle: draft, in_progress, completed, cancelled.';

-- =========================================================
-- STOCK COUNT ITEMS
-- =========================================================

create table if not exists public.stock_count_items (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  stock_count_id uuid not null references public.stock_counts(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,

  expected_quantity integer not null default 0,
  counted_quantity integer,
  difference_quantity integer generated always as (
    coalesce(counted_quantity, 0) - expected_quantity
  ) stored,

  unit_cost_snapshot numeric(14,2),

  counted_by uuid references public.profiles(id) on delete set null,
  counted_at timestamp without time zone,

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

  constraint stock_count_items_expected_quantity_non_negative
    check (expected_quantity >= 0),

  constraint stock_count_items_counted_quantity_non_negative
    check (counted_quantity is null or counted_quantity >= 0),

  constraint stock_count_items_unit_cost_snapshot_non_negative
    check (unit_cost_snapshot is null or unit_cost_snapshot >= 0),

  constraint stock_count_items_version_positive
    check (version >= 1),

  constraint stock_count_items_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint stock_count_items_unique_product_per_count
    unique (stock_count_id, product_id)
);

comment on table public.stock_count_items
is 'Products counted within a physical stock count session.';

comment on column public.stock_count_items.expected_quantity
is 'System quantity at the moment the product was added to the stock count.';

comment on column public.stock_count_items.counted_quantity
is 'Physical quantity counted by the user.';

comment on column public.stock_count_items.difference_quantity
is 'Generated difference: counted_quantity - expected_quantity.';

-- =========================================================
-- ÍNDICES
-- =========================================================

create index if not exists stock_counts_business_branch_status_idx
on public.stock_counts (business_id, branch_id, status)
where deleted_at is null;

create index if not exists stock_counts_started_at_idx
on public.stock_counts (business_id, branch_id, started_at desc)
where deleted_at is null;

create index if not exists stock_count_items_count_idx
on public.stock_count_items (stock_count_id)
where deleted_at is null;

create index if not exists stock_count_items_product_idx
on public.stock_count_items (product_id)
where deleted_at is null;

create index if not exists stock_count_items_business_branch_product_idx
on public.stock_count_items (business_id, branch_id, product_id)
where deleted_at is null;

-- =========================================================
-- VALIDAR BRANCH/BUSINESS
-- =========================================================

create or replace function private.validate_stock_count_branch_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if not exists (
    select 1
    from public.branches br
    where br.id = new.branch_id
      and br.business_id = new.business_id
      and br.deleted_at is null
  ) then
    raise exception 'stock_counts.branch_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_counts_validate_branch_consistency
on public.stock_counts;

create trigger trg_stock_counts_validate_branch_consistency
before insert or update of business_id, branch_id
on public.stock_counts
for each row
execute function private.validate_stock_count_branch_consistency();

-- =========================================================
-- VALIDAR ITEM CONTRA STOCK COUNT / PRODUCT
-- =========================================================

create or replace function private.validate_stock_count_item_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_count record;
begin
  select
    sc.business_id,
    sc.branch_id,
    sc.status
  into v_count
  from public.stock_counts sc
  where sc.id = new.stock_count_id
    and sc.deleted_at is null;

  if v_count.business_id is null then
    raise exception 'stock_count_items.stock_count_id must reference an active stock_count';
  end if;

  if new.business_id <> v_count.business_id then
    raise exception 'stock_count_items.business_id must match stock_counts.business_id';
  end if;

  if new.branch_id <> v_count.branch_id then
    raise exception 'stock_count_items.branch_id must match stock_counts.branch_id';
  end if;

  if v_count.status in ('completed', 'cancelled') then
    raise exception 'Cannot modify items for completed or cancelled stock count';
  end if;

  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.business_id = new.business_id
      and p.deleted_at is null
  ) then
    raise exception 'stock_count_items.product_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_count_items_validate_consistency
on public.stock_count_items;

create trigger trg_stock_count_items_validate_consistency
before insert or update of business_id, branch_id, stock_count_id, product_id
on public.stock_count_items
for each row
execute function private.validate_stock_count_item_consistency();

-- =========================================================
-- FILL DEFAULT ITEM SNAPSHOT
-- =========================================================

create or replace function private.fill_stock_count_item_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_balance_quantity integer;
  v_average_cost numeric(14,2);
begin
  select
    psb.quantity_on_hand,
    psb.average_cost
  into
    v_balance_quantity,
    v_average_cost
  from public.product_stock_balances psb
  where psb.business_id = new.business_id
    and psb.branch_id = new.branch_id
    and psb.product_id = new.product_id
    and psb.deleted_at is null
  limit 1;

  new.expected_quantity := coalesce(new.expected_quantity, coalesce(v_balance_quantity, 0));
  new.unit_cost_snapshot := coalesce(new.unit_cost_snapshot, v_average_cost);

  if new.counted_quantity is not null and new.counted_by is null then
    new.counted_by := auth.uid();
  end if;

  if new.counted_quantity is not null and new.counted_at is null then
    new.counted_at := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_stock_count_items_fill_defaults
on public.stock_count_items;

create trigger trg_stock_count_items_fill_defaults
before insert or update of product_id, counted_quantity
on public.stock_count_items
for each row
execute function private.fill_stock_count_item_defaults();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_stock_counts_updated_at
on public.stock_counts;

create trigger trg_stock_counts_updated_at
before update on public.stock_counts
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_stock_counts_increment_version
on public.stock_counts;

create trigger trg_stock_counts_increment_version
before update on public.stock_counts
for each row
execute function public.increment_row_version_on_business_change();

drop trigger if exists trg_stock_count_items_updated_at
on public.stock_count_items;

create trigger trg_stock_count_items_updated_at
before update on public.stock_count_items
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_stock_count_items_increment_version
on public.stock_count_items;

create trigger trg_stock_count_items_increment_version
before update on public.stock_count_items
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.stock_counts enable row level security;
alter table public.stock_count_items enable row level security;

drop policy if exists stock_counts_select_allowed on public.stock_counts;
drop policy if exists stock_counts_insert_allowed on public.stock_counts;
drop policy if exists stock_counts_update_allowed on public.stock_counts;
drop policy if exists stock_counts_delete_blocked on public.stock_counts;

drop policy if exists stock_count_items_select_allowed on public.stock_count_items;
drop policy if exists stock_count_items_insert_allowed on public.stock_count_items;
drop policy if exists stock_count_items_update_allowed on public.stock_count_items;
drop policy if exists stock_count_items_delete_blocked on public.stock_count_items;

create policy stock_counts_select_allowed
on public.stock_counts
for select
to authenticated
using (
  deleted_at is null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'inventory.count')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

create policy stock_counts_insert_allowed
on public.stock_counts
for insert
to authenticated
with check (
  deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'inventory.count')
);

create policy stock_counts_update_allowed
on public.stock_counts
for update
to authenticated
using (
  deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'inventory.count')
)
with check (
  private.has_branch_permission(business_id, branch_id, 'inventory.count')
);

create policy stock_counts_delete_blocked
on public.stock_counts
for delete
to authenticated
using (false);

create policy stock_count_items_select_allowed
on public.stock_count_items
for select
to authenticated
using (
  deleted_at is null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'inventory.count')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

create policy stock_count_items_insert_allowed
on public.stock_count_items
for insert
to authenticated
with check (
  deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'inventory.count')
);

create policy stock_count_items_update_allowed
on public.stock_count_items
for update
to authenticated
using (
  deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'inventory.count')
)
with check (
  private.has_branch_permission(business_id, branch_id, 'inventory.count')
);

create policy stock_count_items_delete_blocked
on public.stock_count_items
for delete
to authenticated
using (false);

commit;