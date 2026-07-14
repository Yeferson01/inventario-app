-- Fase 1.5 - Foundation operational version triggers
-- Objetivo:
-- Incrementar version automáticamente en tablas operativas
-- solo cuando cambien datos de negocio, evitando incrementos por
-- campos técnicos como updated_at, updated_by o sync_status.

begin;

-- =========================================================
-- Function: increment_row_version_on_business_change
-- =========================================================

create or replace function public.increment_row_version_on_business_change()
returns trigger
language plpgsql
as $$
declare
  old_business_data jsonb;
  new_business_data jsonb;
begin
  old_business_data :=
    to_jsonb(old)
    - 'version'
    - 'updated_at'
    - 'updated_by'
    - 'sync_status';

  new_business_data :=
    to_jsonb(new)
    - 'version'
    - 'updated_at'
    - 'updated_by'
    - 'sync_status';

  if old_business_data is distinct from new_business_data then
    new.version := coalesce(old.version, 0) + 1;
  else
    new.version := old.version;
  end if;

  return new;
end;
$$;

comment on function public.increment_row_version_on_business_change()
is 'Increments row version only when business-relevant fields change, excluding technical sync/update metadata.';

-- =========================================================
-- PURCHASES
-- =========================================================

drop trigger if exists trg_purchases_increment_version on public.purchases;

create trigger trg_purchases_increment_version
before update on public.purchases
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- SALES
-- =========================================================

drop trigger if exists trg_sales_increment_version on public.sales;

create trigger trg_sales_increment_version
before update on public.sales
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- DEVICES
-- =========================================================

drop trigger if exists trg_devices_increment_version on public.devices;

create trigger trg_devices_increment_version
before update on public.devices
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- SUBSCRIPTIONS
-- =========================================================

drop trigger if exists trg_subscriptions_increment_version on public.subscriptions;

create trigger trg_subscriptions_increment_version
before update on public.subscriptions
for each row
execute function public.increment_row_version_on_business_change();

commit;