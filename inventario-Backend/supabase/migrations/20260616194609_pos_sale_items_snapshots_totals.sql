-- Fase 4.5 - POS sale_items snapshots and totals
-- Objetivo:
-- Fortalecer sale_items para historial confiable:
-- snapshots de producto, costo, descuentos, impuestos, total,
-- metadata de auditoría y sync.
--
-- Nota:
-- No se elimina ni modifica todavía sales.payment_method.
-- No se automatiza todavía el descuento de inventario.

begin;

-- =========================================================
-- 1. Agregar columnas a sale_items
-- =========================================================

alter table public.sale_items
  add column if not exists business_id uuid references public.businesses(id) on delete restrict,
  add column if not exists product_name_snapshot text,
  add column if not exists barcode_snapshot text,
  add column if not exists unit_cost_snapshot numeric(14,2),
  add column if not exists discount_amount numeric(14,2) not null default 0,
  add column if not exists tax_amount numeric(14,2) not null default 0,
  add column if not exists total numeric(14,2) not null default 0,
  add column if not exists updated_at timestamp without time zone default now(),
  add column if not exists deleted_at timestamp without time zone,
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced',
  add column if not exists idempotency_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.sale_items.business_id
is 'Business tenant copied from the parent sale for faster RLS, reporting and sync.';

comment on column public.sale_items.product_name_snapshot
is 'Product name at the moment of sale. Preserves sale history if product changes later.';

comment on column public.sale_items.barcode_snapshot
is 'Product barcode at the moment of sale.';

comment on column public.sale_items.unit_cost_snapshot
is 'Product unit cost at the moment of sale, useful for margin reports.';

comment on column public.sale_items.discount_amount
is 'Discount amount applied to this sale item.';

comment on column public.sale_items.tax_amount
is 'Tax amount applied to this sale item.';

comment on column public.sale_items.total
is 'Final item total after discount and tax.';

comment on column public.sale_items.idempotency_key
is 'Unique key to avoid duplicated sale items during offline sync retries.';

comment on column public.sale_items.metadata
is 'Additional structured metadata for POS, sync or import details.';

-- =========================================================
-- 2. Backfill business_id y snapshots desde sales/products
-- =========================================================

with sale_item_backfill as (
  select
    si.id as sale_item_id,
    s.business_id as sale_business_id,
    p.name as product_name,
    p.barcode as product_barcode,
    p.purchase_price as product_purchase_price
  from public.sale_items si
  join public.sales s
    on s.id = si.sale_id
  left join public.products p
    on p.id = si.product_id
)
update public.sale_items si
set
  business_id = coalesce(si.business_id, bf.sale_business_id),
  product_name_snapshot = coalesce(si.product_name_snapshot, bf.product_name),
  barcode_snapshot = coalesce(si.barcode_snapshot, bf.product_barcode),
  unit_cost_snapshot = coalesce(si.unit_cost_snapshot, bf.product_purchase_price),
  total = case
    when si.total = 0 then greatest(
      coalesce(si.subtotal, si.quantity * si.unit_price)
      - coalesce(si.discount_amount, 0)
      + coalesce(si.tax_amount, 0),
      0
    )
    else si.total
  end
from sale_item_backfill bf
where bf.sale_item_id = si.id;

-- =========================================================
-- 3. Constraints
-- =========================================================

alter table public.sale_items
  add constraint sale_items_business_required
  check (business_id is not null)
  not valid;

alter table public.sale_items
  add constraint sale_items_unit_cost_snapshot_non_negative
  check (unit_cost_snapshot is null or unit_cost_snapshot >= 0)
  not valid;

alter table public.sale_items
  add constraint sale_items_discount_amount_non_negative
  check (discount_amount >= 0)
  not valid;

alter table public.sale_items
  add constraint sale_items_tax_amount_non_negative
  check (tax_amount >= 0)
  not valid;

alter table public.sale_items
  add constraint sale_items_total_non_negative
  check (total >= 0)
  not valid;

alter table public.sale_items
  add constraint sale_items_version_positive
  check (version >= 1)
  not valid;

alter table public.sale_items
  add constraint sale_items_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

-- =========================================================
-- 4. Índices
-- =========================================================

create index if not exists sale_items_business_created_idx
on public.sale_items (business_id, created_at desc)
where deleted_at is null;

create index if not exists sale_items_sale_idx
on public.sale_items (sale_id)
where deleted_at is null;

create index if not exists sale_items_product_idx
on public.sale_items (product_id)
where deleted_at is null
  and product_id is not null;

create unique index if not exists sale_items_idempotency_key_unique
on public.sale_items (idempotency_key)
where idempotency_key is not null;

-- =========================================================
-- 5. Helpers de integridad
-- =========================================================

create or replace function private.validate_sale_item_sale_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale_business_id uuid;
begin
  select s.business_id
  into v_sale_business_id
  from public.sales s
  where s.id = new.sale_id
    and s.deleted_at is null;

  if v_sale_business_id is null then
    raise exception 'sale_items.sale_id must reference an active sale';
  end if;

  if new.business_id is null then
    new.business_id := v_sale_business_id;
  end if;

  if new.business_id <> v_sale_business_id then
    raise exception 'sale_items.business_id must match parent sales.business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_sale_item_sale_consistency()
is 'Ensures sale_items.business_id matches the parent sale business_id.';

create or replace function private.validate_sale_item_product_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.product_id is not null then
    if not exists (
      select 1
      from public.products p
      where p.id = new.product_id
        and p.business_id = new.business_id
        and p.deleted_at is null
    ) then
      raise exception 'sale_items.product_id must belong to the same business_id';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_sale_item_product_consistency()
is 'Ensures sale_items.product_id belongs to the same business_id when product_id is present.';

create or replace function private.fill_sale_item_snapshots()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product_name text;
  v_barcode text;
  v_purchase_price numeric;
begin
  if new.product_id is not null then
    select p.name, p.barcode, p.purchase_price
    into v_product_name, v_barcode, v_purchase_price
    from public.products p
    where p.id = new.product_id
      and p.business_id = new.business_id
    limit 1;

    new.product_name_snapshot := coalesce(new.product_name_snapshot, v_product_name);
    new.barcode_snapshot := coalesce(new.barcode_snapshot, v_barcode);
    new.unit_cost_snapshot := coalesce(new.unit_cost_snapshot, v_purchase_price);
  end if;

  new.discount_amount := coalesce(new.discount_amount, 0);
  new.tax_amount := coalesce(new.tax_amount, 0);

  if new.subtotal is null then
    new.subtotal := new.quantity * new.unit_price;
  end if;

  if new.total is null or new.total = 0 then
    new.total := greatest(
      coalesce(new.subtotal, new.quantity * new.unit_price)
      - new.discount_amount
      + new.tax_amount,
      0
    );
  end if;

  return new;
end;
$$;

comment on function private.fill_sale_item_snapshots()
is 'Fills product snapshots and calculates item total when not provided.';

-- =========================================================
-- 6. Triggers
-- =========================================================

drop trigger if exists trg_sale_items_validate_sale_consistency
on public.sale_items;

create trigger trg_sale_items_validate_sale_consistency
before insert or update of business_id, sale_id
on public.sale_items
for each row
execute function private.validate_sale_item_sale_consistency();

drop trigger if exists trg_sale_items_validate_product_consistency
on public.sale_items;

create trigger trg_sale_items_validate_product_consistency
before insert or update of business_id, product_id
on public.sale_items
for each row
execute function private.validate_sale_item_product_consistency();

drop trigger if exists trg_sale_items_fill_snapshots
on public.sale_items;

create trigger trg_sale_items_fill_snapshots
before insert or update of product_id, quantity, unit_price, subtotal, discount_amount, tax_amount, total
on public.sale_items
for each row
execute function private.fill_sale_item_snapshots();

drop trigger if exists trg_sale_items_updated_at on public.sale_items;

create trigger trg_sale_items_updated_at
before update on public.sale_items
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_sale_items_increment_version on public.sale_items;

create trigger trg_sale_items_increment_version
before update on public.sale_items
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- 7. Actualizar RLS de sale_items usando business_id + branch del sale
-- =========================================================

drop policy if exists sale_items_select_allowed on public.sale_items;
drop policy if exists sale_items_insert_allowed on public.sale_items;
drop policy if exists sale_items_update_allowed on public.sale_items;
drop policy if exists sale_items_delete_blocked on public.sale_items;

create policy sale_items_select_allowed
on public.sale_items
for select
to authenticated
using (
  business_id is not null
  and sale_id is not null
  and deleted_at is null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.read')
    or private.has_business_permission(business_id, 'reports.sales')
    or private.has_business_permission(business_id, 'cash.read')
    or private.has_business_permission(business_id, 'sales.create')
  )
);

create policy sale_items_insert_allowed
on public.sale_items
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

create policy sale_items_update_allowed
on public.sale_items
for update
to authenticated
using (
  business_id is not null
  and sale_id is not null
  and deleted_at is null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.create')
    or private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
  )
)
with check (
  business_id is not null
  and sale_id is not null
  and (
    private.sale_branch_id(sale_id) is null
    or private.has_branch_access(business_id, private.sale_branch_id(sale_id))
  )
  and (
    private.has_business_permission(business_id, 'sales.create')
    or private.has_business_permission(business_id, 'sales.void')
    or private.has_business_permission(business_id, 'sales.refund')
  )
);

create policy sale_items_delete_blocked
on public.sale_items
for delete
to authenticated
using (false);

commit;