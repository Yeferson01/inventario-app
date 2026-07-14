-- Fase 1.2 - Foundation catalog metadata
-- Objetivo:
-- Agregar metadatos profesionales a tablas maestras sin cambiar RLS todavía.
-- Tablas afectadas: products, categories, customers, suppliers.

begin;

-- =========================================================
-- PRODUCTS
-- =========================================================

alter table public.products
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.products
  add constraint products_version_positive
  check (version >= 1)
  not valid;

alter table public.products
  add constraint products_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.products.created_by is 'Profile that created this product.';
comment on column public.products.updated_by is 'Profile that last updated this product.';
comment on column public.products.deleted_by is 'Profile that soft-deleted this product.';
comment on column public.products.delete_reason is 'Reason for soft-deleting this product.';
comment on column public.products.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.products.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- CATEGORIES
-- =========================================================

alter table public.categories
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.categories
  add constraint categories_version_positive
  check (version >= 1)
  not valid;

alter table public.categories
  add constraint categories_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.categories.created_by is 'Profile that created this category.';
comment on column public.categories.updated_by is 'Profile that last updated this category.';
comment on column public.categories.deleted_by is 'Profile that soft-deleted this category.';
comment on column public.categories.delete_reason is 'Reason for soft-deleting this category.';
comment on column public.categories.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.categories.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- CUSTOMERS
-- =========================================================

alter table public.customers
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.customers
  add constraint customers_version_positive
  check (version >= 1)
  not valid;

alter table public.customers
  add constraint customers_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.customers.created_by is 'Profile that created this customer.';
comment on column public.customers.updated_by is 'Profile that last updated this customer.';
comment on column public.customers.deleted_by is 'Profile that soft-deleted this customer.';
comment on column public.customers.delete_reason is 'Reason for soft-deleting this customer.';
comment on column public.customers.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.customers.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- SUPPLIERS
-- =========================================================

alter table public.suppliers
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.suppliers
  add constraint suppliers_version_positive
  check (version >= 1)
  not valid;

alter table public.suppliers
  add constraint suppliers_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.suppliers.created_by is 'Profile that created this supplier.';
comment on column public.suppliers.updated_by is 'Profile that last updated this supplier.';
comment on column public.suppliers.deleted_by is 'Profile that soft-deleted this supplier.';
comment on column public.suppliers.delete_reason is 'Reason for soft-deleting this supplier.';
comment on column public.suppliers.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.suppliers.sync_status is 'Synchronization status for offline-first workflows.';

commit;