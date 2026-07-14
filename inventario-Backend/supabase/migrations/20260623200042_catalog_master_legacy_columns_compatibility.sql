-- =========================================================
-- Fase 6.19C.1 Patch - Compatibilidad con columnas legacy
-- Problema:
-- - master_products_catalog ya tenía product_name NOT NULL.
-- - La nueva estructura usa name / normalized_name.
-- Solución:
-- - Sincronizar product_name <-> name.
-- - Asegurar que product_name nunca quede null.
-- =========================================================

-- 1. Backfill defensivo.
update public.master_products_catalog
set
  name = coalesce(nullif(btrim(name), ''), nullif(btrim(product_name), ''), 'Producto sin nombre'),
  product_name = coalesce(nullif(btrim(product_name), ''), nullif(btrim(name), ''), 'Producto sin nombre'),
  normalized_name = coalesce(
    nullif(btrim(normalized_name), ''),
    lower(coalesce(nullif(btrim(name), ''), nullif(btrim(product_name), ''), 'Producto sin nombre'))
  ),
  updated_at = now()
where
  name is null
  or btrim(coalesce(name, '')) = ''
  or product_name is null
  or btrim(coalesce(product_name, '')) = ''
  or normalized_name is null
  or btrim(coalesce(normalized_name, '')) = '';

-- 2. Reemplazar trigger de catálogo maestro con compatibilidad legacy.
create or replace function private.touch_master_products_catalog()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Compatibilidad legacy:
  -- Si llega name pero no product_name, llenar product_name.
  -- Si llega product_name pero no name, llenar name.
  new.name := coalesce(
    nullif(btrim(new.name), ''),
    nullif(btrim(new.product_name), ''),
    'Producto sin nombre'
  );

  new.product_name := coalesce(
    nullif(btrim(new.product_name), ''),
    nullif(btrim(new.name), ''),
    'Producto sin nombre'
  );

  new.barcode_normalized := private.normalize_barcode(coalesce(new.gtin, new.barcode));

  new.normalized_name := lower(
    coalesce(
      nullif(btrim(new.name), ''),
      nullif(btrim(new.product_name), ''),
      'Producto sin nombre'
    )
  );

  new.has_image := coalesce(new.image_url is not null or new.image_thumb_url is not null, false);
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.catalog_version := greatest(coalesce(new.catalog_version, 1), 1);

  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.version := coalesce(old.version, 1) + 1;
  else
    new.version := greatest(coalesce(new.version, 1), 1);
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := coalesce(new.updated_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_master_products_catalog_touch on public.master_products_catalog;

create trigger trg_master_products_catalog_touch
before insert or update on public.master_products_catalog
for each row
execute function private.touch_master_products_catalog();

comment on function private.touch_master_products_catalog() is
'Touches and normalizes master product catalog rows, including legacy product_name/name compatibility.';