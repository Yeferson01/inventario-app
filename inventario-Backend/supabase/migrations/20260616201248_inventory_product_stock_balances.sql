-- Fase 5.2 - Product stock balances
-- Objetivo:
-- Crear product_stock_balances para mantener stock actual por producto/sucursal.
--
-- Modelo:
-- inventory_movements = ledger histórico
-- product_stock_balances = saldo actual rápido
--
-- Nota:
-- En esta fase creamos la tabla y hacemos backfill inicial.
-- La actualización automática desde inventory_movements viene después.

begin;

-- =========================================================
-- PRODUCT STOCK BALANCES
-- =========================================================

create table if not exists public.product_stock_balances (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,

  quantity_on_hand integer not null default 0,
  quantity_reserved integer not null default 0,
  quantity_available integer generated always as (quantity_on_hand - quantity_reserved) stored,

  average_cost numeric(14,2),
  last_movement_at timestamp without time zone,

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

  constraint product_stock_balances_quantity_on_hand_non_negative
    check (quantity_on_hand >= 0),

  constraint product_stock_balances_quantity_reserved_non_negative
    check (quantity_reserved >= 0),

  constraint product_stock_balances_quantity_reserved_lte_on_hand
    check (quantity_reserved <= quantity_on_hand),

  constraint product_stock_balances_average_cost_non_negative
    check (average_cost is null or average_cost >= 0),

  constraint product_stock_balances_version_positive
    check (version >= 1),

  constraint product_stock_balances_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint product_stock_balances_unique_product_branch
    unique (business_id, branch_id, product_id)
);

comment on table public.product_stock_balances
is 'Current stock balance by business, branch and product. Derived from inventory_movements.';

comment on column public.product_stock_balances.quantity_on_hand
is 'Physical quantity currently on hand.';

comment on column public.product_stock_balances.quantity_reserved
is 'Quantity reserved for pending orders, holds or future workflows.';

comment on column public.product_stock_balances.quantity_available
is 'Generated quantity available for sale: quantity_on_hand - quantity_reserved.';

comment on column public.product_stock_balances.average_cost
is 'Average cost used for inventory valuation.';

comment on column public.product_stock_balances.last_movement_at
is 'Timestamp of the latest inventory movement applied to this balance.';

-- =========================================================
-- Índices
-- =========================================================

create index if not exists product_stock_balances_business_branch_idx
on public.product_stock_balances (business_id, branch_id)
where deleted_at is null;

create index if not exists product_stock_balances_product_idx
on public.product_stock_balances (product_id)
where deleted_at is null;

create index if not exists product_stock_balances_low_stock_idx
on public.product_stock_balances (business_id, branch_id, quantity_available)
where deleted_at is null;

-- =========================================================
-- Integridad: branch pertenece al business
-- =========================================================

create or replace function private.validate_stock_balance_branch_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.branches br
    where br.id = new.branch_id
      and br.business_id = new.business_id
      and br.deleted_at is null
  ) then
    raise exception 'product_stock_balances.branch_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_stock_balance_branch_consistency()
is 'Ensures product_stock_balances.branch_id belongs to the same business_id.';

drop trigger if exists trg_product_stock_balances_validate_branch_consistency
on public.product_stock_balances;

create trigger trg_product_stock_balances_validate_branch_consistency
before insert or update of business_id, branch_id
on public.product_stock_balances
for each row
execute function private.validate_stock_balance_branch_consistency();

-- =========================================================
-- Integridad: product pertenece al business
-- =========================================================

create or replace function private.validate_stock_balance_product_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.products p
    where p.id = new.product_id
      and p.business_id = new.business_id
      and p.deleted_at is null
  ) then
    raise exception 'product_stock_balances.product_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_stock_balance_product_consistency()
is 'Ensures product_stock_balances.product_id belongs to the same business_id.';

drop trigger if exists trg_product_stock_balances_validate_product_consistency
on public.product_stock_balances;

create trigger trg_product_stock_balances_validate_product_consistency
before insert or update of business_id, product_id
on public.product_stock_balances
for each row
execute function private.validate_stock_balance_product_consistency();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_product_stock_balances_updated_at
on public.product_stock_balances;

create trigger trg_product_stock_balances_updated_at
before update on public.product_stock_balances
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_product_stock_balances_increment_version
on public.product_stock_balances;

create trigger trg_product_stock_balances_increment_version
before update on public.product_stock_balances
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- Backfill 1:
-- Crear balances desde inventory_movements existentes.
-- Si no tienes movimientos, esto no insertará nada.
-- =========================================================

insert into public.product_stock_balances (
  business_id,
  branch_id,
  product_id,
  quantity_on_hand,
  quantity_reserved,
  average_cost,
  last_movement_at
)
select
  im.business_id,
  im.branch_id,
  im.product_id,
  greatest(coalesce(sum(im.quantity_change), 0), 0)::integer as quantity_on_hand,
  0 as quantity_reserved,
  null as average_cost,
  max(im.created_at) as last_movement_at
from public.inventory_movements im
where im.business_id is not null
  and im.branch_id is not null
  and im.product_id is not null
group by im.business_id, im.branch_id, im.product_id
on conflict (business_id, branch_id, product_id) do update
set
  quantity_on_hand = excluded.quantity_on_hand,
  last_movement_at = excluded.last_movement_at,
  updated_at = now();

-- =========================================================
-- Backfill 2:
-- Para productos sin movimientos, crear balance inicial en sucursal default
-- usando products.stock_quantity como compatibilidad legacy.
--
-- Nota:
-- Esto solo aplica si no existe ya balance para ese producto.
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
insert into public.product_stock_balances (
  business_id,
  branch_id,
  product_id,
  quantity_on_hand,
  quantity_reserved,
  average_cost,
  last_movement_at
)
select
  p.business_id,
  db.branch_id,
  p.id as product_id,
  greatest(coalesce(p.stock_quantity, 0), 0)::integer as quantity_on_hand,
  0 as quantity_reserved,
  p.purchase_price as average_cost,
  null as last_movement_at
from public.products p
join default_branches db
  on db.business_id = p.business_id
where p.business_id is not null
  and p.deleted_at is null
  and not exists (
    select 1
    from public.product_stock_balances psb
    where psb.business_id = p.business_id
      and psb.product_id = p.id
  )
on conflict (business_id, branch_id, product_id) do nothing;

-- =========================================================
-- RLS
-- =========================================================

alter table public.product_stock_balances enable row level security;

drop policy if exists product_stock_balances_select_allowed on public.product_stock_balances;
drop policy if exists product_stock_balances_insert_blocked on public.product_stock_balances;
drop policy if exists product_stock_balances_update_blocked on public.product_stock_balances;
drop policy if exists product_stock_balances_delete_blocked on public.product_stock_balances;

-- SELECT:
-- Usuarios con inventory.read, reports.inventory o sales.create pueden ver saldos,
-- siempre respetando acceso a sucursal.
create policy product_stock_balances_select_allowed
on public.product_stock_balances
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'reports.inventory')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

-- No permitimos INSERT directo desde cliente.
-- Los balances se crearán/actualizarán desde funciones controladas.
create policy product_stock_balances_insert_blocked
on public.product_stock_balances
for insert
to authenticated
with check (false);

-- No permitimos UPDATE directo desde cliente.
-- Las modificaciones deben venir desde inventory_movements/apply_inventory_movement.
create policy product_stock_balances_update_blocked
on public.product_stock_balances
for update
to authenticated
using (false)
with check (false);

-- No hard delete.
create policy product_stock_balances_delete_blocked
on public.product_stock_balances
for delete
to authenticated
using (false);

commit;