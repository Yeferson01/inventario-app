-- =========================================================
-- Fase 6.19C.6 Patch - Catálogo offline-first final hardening
-- Objetivo:
-- - Agregar índices faltantes.
-- - Agregar constraints faltantes.
-- - No modificar lógica funcional.
-- =========================================================

-- =========================================================
-- 1. Índice para búsquedas de códigos locales por negocio/scope
-- =========================================================

create index if not exists idx_product_barcodes_business_scope
on public.product_barcodes (
  business_id,
  scope,
  barcode_normalized
)
where deleted_at is null;

-- =========================================================
-- 2. Índice único para evitar contribuciones pendientes duplicadas
--    por negocio + barcode + tipo
-- =========================================================

create unique index if not exists idx_product_catalog_contributions_business_barcode_type_pending_unique
on public.product_catalog_contributions (
  business_id,
  barcode_normalized,
  contribution_type
)
where deleted_at is null
  and status = 'pending_review'
  and barcode_normalized is not null;

-- =========================================================
-- 3. Constraint barcode_type en product_barcodes
-- =========================================================

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'product_barcodes_barcode_type_check'
      and conrelid = 'public.product_barcodes'::regclass
  ) then
    alter table public.product_barcodes
    add constraint product_barcodes_barcode_type_check
    check (
      barcode_type in (
        'gtin',
        'ean13',
        'ean8',
        'upc',
        'local_sku',
        'internal',
        'unknown'
      )
    )
    not valid;
  end if;
end $$;

alter table public.product_barcodes
validate constraint product_barcodes_barcode_type_check;

-- =========================================================
-- 4. Constraint de forma según scope
--    global:
--      - business_id null
--      - product_id null
--      - master_product_id requerido
--
--    business:
--      - business_id requerido
--      - product_id requerido
--      - master_product_id opcional
-- =========================================================

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'product_barcodes_scope_shape_check'
      and conrelid = 'public.product_barcodes'::regclass
  ) then
    alter table public.product_barcodes
    add constraint product_barcodes_scope_shape_check
    check (
      (
        scope = 'global'
        and business_id is null
        and product_id is null
        and master_product_id is not null
      )
      or
      (
        scope = 'business'
        and business_id is not null
        and product_id is not null
      )
    )
    not valid;
  end if;
end $$;

alter table public.product_barcodes
validate constraint product_barcodes_scope_shape_check;

comment on index public.idx_product_barcodes_business_scope is
'Supports fast offline catalog lookup sync for business-local barcodes by business, scope and normalized barcode.';

comment on index public.idx_product_catalog_contributions_business_barcode_type_pending_unique is
'Prevents duplicate pending product catalog contributions for the same business, normalized barcode and contribution type.';

comment on constraint product_barcodes_barcode_type_check
on public.product_barcodes is
'Restricts product barcode type to supported global/local barcode categories.';

comment on constraint product_barcodes_scope_shape_check
on public.product_barcodes is
'Ensures global barcodes are linked to master products and business barcodes are linked to local business products.';