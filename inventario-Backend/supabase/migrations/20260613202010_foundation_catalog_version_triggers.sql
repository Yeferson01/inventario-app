-- Fase 1.3 - Foundation catalog version triggers
-- Objetivo:
-- Incrementar version automáticamente en tablas maestras
-- para control optimista de concurrencia y sync offline-first.

begin;

-- =========================================================
-- Function: increment_row_version
-- =========================================================

create or replace function public.increment_row_version()
returns trigger
language plpgsql
as $$
begin
  if new.version is null then
    new.version := 1;
  else
    new.version := coalesce(old.version, 0) + 1;
  end if;

  return new;
end;
$$;

comment on function public.increment_row_version()
is 'Automatically increments row version on update for optimistic concurrency and offline sync.';

-- =========================================================
-- PRODUCTS
-- =========================================================

drop trigger if exists trg_products_increment_version on public.products;

create trigger trg_products_increment_version
before update on public.products
for each row
execute function public.increment_row_version();

-- =========================================================
-- CATEGORIES
-- =========================================================

drop trigger if exists trg_categories_increment_version on public.categories;

create trigger trg_categories_increment_version
before update on public.categories
for each row
execute function public.increment_row_version();

-- =========================================================
-- CUSTOMERS
-- =========================================================

drop trigger if exists trg_customers_increment_version on public.customers;

create trigger trg_customers_increment_version
before update on public.customers
for each row
execute function public.increment_row_version();

-- =========================================================
-- SUPPLIERS
-- =========================================================

drop trigger if exists trg_suppliers_increment_version on public.suppliers;

create trigger trg_suppliers_increment_version
before update on public.suppliers
for each row
execute function public.increment_row_version();

commit;