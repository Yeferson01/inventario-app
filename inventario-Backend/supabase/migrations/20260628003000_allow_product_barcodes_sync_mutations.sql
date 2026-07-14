-- Allow catalog/product barcode mutations in offline sync.
-- Reason: Flutter offline-first creates a local product and a business barcode
-- from master catalog, producing sync_mutations for:
--   - products
--   - product_barcodes

alter table public.sync_mutations
drop constraint if exists sync_mutations_entity_table_allowed;

alter table public.sync_mutations
add constraint sync_mutations_entity_table_allowed
check (
  entity_table in (
    'businesses',
    'branches',
    'business_members',
    'profiles',

    'categories',
    'customers',
    'suppliers',

    'products',
    'product_barcodes',
    'catalog_contributions',

    'purchases',
    'purchase_items',

    'sales',
    'sale_items',
    'sale_payments',

    'cash_registers',
    'cash_sessions',

    'inventory_movements',
    'product_stock_balances'
  )
);
