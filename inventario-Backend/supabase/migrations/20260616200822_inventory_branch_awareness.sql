-- Fase 5.1 - Inventory branch awareness
-- Objetivo:
-- Agregar branch_id a purchases e inventory_movements.
-- Esto prepara inventario por sucursal y futuros product_stock_balances.
--
-- Nota:
-- No creamos todavía product_stock_balances.
-- No automatizamos todavía entradas/salidas de stock.
-- products.stock_quantity sigue existiendo como campo legacy temporal.

begin;

-- =========================================================
-- 1. Agregar branch_id a purchases
-- =========================================================

alter table public.purchases
  add column if not exists branch_id uuid references public.branches(id) on delete restrict;

comment on column public.purchases.branch_id
is 'Branch where the purchase stock is received. Required for branch-level inventory.';

-- =========================================================
-- 2. Agregar branch_id a inventory_movements
-- =========================================================

alter table public.inventory_movements
  add column if not exists branch_id uuid references public.branches(id) on delete restrict;

comment on column public.inventory_movements.branch_id
is 'Branch where this inventory movement affects stock. Required for branch-level inventory.';

-- =========================================================
-- 3. Backfill purchases.branch_id con sucursal principal/default
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
update public.purchases p
set branch_id = db.branch_id
from default_branches db
where p.business_id = db.business_id
  and p.business_id is not null
  and p.branch_id is null;

-- =========================================================
-- 4. Backfill inventory_movements.branch_id
--
-- OJO:
-- inventory_movements ya tiene trigger anti-update por ser ledger.
-- Para un backfill estructural de migración, lo quitamos temporalmente
-- y lo recreamos al final.
-- =========================================================

drop trigger if exists trg_inventory_movements_prevent_update
on public.inventory_movements;

with movement_branches as (
  select
    im.id as movement_id,
    coalesce(
      -- Si el movimiento viene de una compra, usar branch de esa compra.
      p.branch_id,

      -- Si viene de una venta, usar branch de esa venta.
      s.branch_id,

      -- Si no hay fuente, usar sucursal default del negocio.
      db.branch_id
    ) as branch_id
  from public.inventory_movements im
  left join public.purchases p
    on im.reference_type = 'purchase'
   and p.id = im.reference_id
  left join public.sales s
    on im.reference_type = 'sale'
   and s.id = im.reference_id
  left join lateral (
    select br.id as branch_id
    from public.branches br
    where br.business_id = im.business_id
      and br.deleted_at is null
      and br.status = 'active'
    order by
      case when lower(br.name) = lower('Principal') then 0 else 1 end,
      br.created_at asc
    limit 1
  ) db on true
  where im.business_id is not null
)
update public.inventory_movements im
set branch_id = mb.branch_id
from movement_branches mb
where im.id = mb.movement_id
  and im.branch_id is null
  and mb.branch_id is not null;

-- Recrear trigger anti-update del ledger.
create trigger trg_inventory_movements_prevent_update
before update on public.inventory_movements
for each row
execute function public.prevent_inventory_movements_update();

-- =========================================================
-- 5. Constraints NOT VALID
-- No forzamos NOT NULL todavía para mantener migración segura.
-- Primero validamos datos y luego endurecemos en fase posterior.
-- =========================================================

alter table public.purchases
  add constraint purchases_branch_required
  check (branch_id is not null)
  not valid;

alter table public.inventory_movements
  add constraint inventory_movements_branch_required
  check (branch_id is not null)
  not valid;

-- =========================================================
-- 6. Índices
-- =========================================================

create index if not exists purchases_business_branch_created_idx
on public.purchases (business_id, branch_id, created_at desc)
where deleted_at is null;

create index if not exists inventory_movements_business_branch_product_created_idx
on public.inventory_movements (business_id, branch_id, product_id, created_at desc);

create index if not exists inventory_movements_branch_created_idx
on public.inventory_movements (branch_id, created_at desc)
where branch_id is not null;

-- =========================================================
-- 7. Integridad purchases.branch_id pertenece al mismo business_id
-- =========================================================

create or replace function private.validate_purchase_branch_consistency()
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
      raise exception 'purchases.branch_id must belong to the same business_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_purchase_branch_consistency()
is 'Ensures purchases.branch_id belongs to the same business_id.';

drop trigger if exists trg_purchases_validate_branch_consistency
on public.purchases;

create trigger trg_purchases_validate_branch_consistency
before insert or update of business_id, branch_id
on public.purchases
for each row
execute function private.validate_purchase_branch_consistency();

-- =========================================================
-- 8. Integridad inventory_movements.branch_id pertenece al mismo business_id
-- =========================================================

create or replace function private.validate_inventory_movement_branch_consistency()
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
      raise exception 'inventory_movements.branch_id must belong to the same business_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_inventory_movement_branch_consistency()
is 'Ensures inventory_movements.branch_id belongs to the same business_id.';

drop trigger if exists trg_inventory_movements_validate_branch_consistency
on public.inventory_movements;

create trigger trg_inventory_movements_validate_branch_consistency
before insert or update of business_id, branch_id
on public.inventory_movements
for each row
execute function private.validate_inventory_movement_branch_consistency();

-- =========================================================
-- 9. Actualizar RLS de purchases con branch_id
-- =========================================================

drop policy if exists purchases_select_allowed on public.purchases;
drop policy if exists purchases_insert_allowed on public.purchases;
drop policy if exists purchases_update_allowed on public.purchases;
drop policy if exists purchases_soft_delete_allowed on public.purchases;
drop policy if exists purchases_delete_blocked on public.purchases;

create policy purchases_select_allowed
on public.purchases
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
    private.has_business_permission(business_id, 'inventory.purchase')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

create policy purchases_insert_allowed
on public.purchases
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'inventory.purchase')
);

create policy purchases_update_allowed
on public.purchases
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'inventory.purchase')
)
with check (
  business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'inventory.purchase')
);

create policy purchases_soft_delete_allowed
on public.purchases
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'inventory.purchase')
)
with check (
  business_id is not null
  and deleted_at is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and private.has_business_permission(business_id, 'inventory.purchase')
);

create policy purchases_delete_blocked
on public.purchases
for delete
to authenticated
using (false);

-- =========================================================
-- 10. Actualizar RLS de inventory_movements con branch_id
-- =========================================================

drop policy if exists inventory_movements_select_allowed on public.inventory_movements;
drop policy if exists inventory_movements_insert_allowed on public.inventory_movements;
drop policy if exists inventory_movements_delete_blocked on public.inventory_movements;

create policy inventory_movements_select_allowed
on public.inventory_movements
for select
to authenticated
using (
  business_id is not null
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and (
    private.has_business_permission(business_id, 'inventory.read')
    or private.has_business_permission(business_id, 'reports.inventory')
  )
);

create policy inventory_movements_insert_allowed
on public.inventory_movements
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    (
      coalesce(source_type, movement_type::text) = 'sale'
      and private.has_branch_permission(business_id, branch_id, 'sales.create')
    )

    or

    (
      coalesce(source_type, movement_type::text) = 'purchase'
      and private.has_branch_permission(business_id, branch_id, 'inventory.purchase')
    )

    or

    (
      coalesce(source_type, movement_type::text) in ('manual_adjustment', 'loss', 'reversal')
      and private.has_branch_permission(business_id, branch_id, 'inventory.adjust')
    )

    or

    (
      coalesce(source_type, movement_type::text) = 'return'
      and (
        private.has_branch_permission(business_id, branch_id, 'sales.refund')
        or private.has_branch_permission(business_id, branch_id, 'inventory.adjust')
      )
    )

    or

    (
      coalesce(source_type, movement_type::text) = 'stock_count'
      and private.has_branch_permission(business_id, branch_id, 'inventory.count')
    )

    or

    (
      coalesce(source_type, movement_type::text) = 'transfer'
      and private.has_branch_permission(business_id, branch_id, 'inventory.transfer')
    )
  )
);

create policy inventory_movements_delete_blocked
on public.inventory_movements
for delete
to authenticated
using (false);

commit;