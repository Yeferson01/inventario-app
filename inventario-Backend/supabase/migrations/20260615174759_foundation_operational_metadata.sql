-- Fase 1.4 - Foundation operational metadata
-- Objetivo:
-- Agregar metadatos profesionales a tablas operativas.
-- Tablas afectadas: purchases, sales, devices, subscriptions.
--
-- Nota:
-- No se incluye inventory_movements todavía porque será tratado
-- como ledger inmutable con reglas especiales.

begin;

-- =========================================================
-- PURCHASES
-- =========================================================

alter table public.purchases
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.purchases
  add constraint purchases_version_positive
  check (version >= 1)
  not valid;

alter table public.purchases
  add constraint purchases_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.purchases.created_by is 'Profile that created this purchase.';
comment on column public.purchases.updated_by is 'Profile that last updated this purchase.';
comment on column public.purchases.deleted_by is 'Profile that soft-deleted this purchase.';
comment on column public.purchases.delete_reason is 'Reason for soft-deleting this purchase.';
comment on column public.purchases.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.purchases.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- SALES
-- =========================================================

alter table public.sales
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.sales
  add constraint sales_version_positive
  check (version >= 1)
  not valid;

alter table public.sales
  add constraint sales_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.sales.created_by is 'Profile that created this sale.';
comment on column public.sales.updated_by is 'Profile that last updated this sale.';
comment on column public.sales.deleted_by is 'Profile that soft-deleted this sale.';
comment on column public.sales.delete_reason is 'Reason for soft-deleting this sale.';
comment on column public.sales.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.sales.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- DEVICES
-- =========================================================

alter table public.devices
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.devices
  add constraint devices_version_positive
  check (version >= 1)
  not valid;

alter table public.devices
  add constraint devices_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.devices.created_by is 'Profile that created this device.';
comment on column public.devices.updated_by is 'Profile that last updated this device.';
comment on column public.devices.deleted_by is 'Profile that soft-deleted this device.';
comment on column public.devices.delete_reason is 'Reason for soft-deleting this device.';
comment on column public.devices.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.devices.sync_status is 'Synchronization status for offline-first workflows.';

-- =========================================================
-- SUBSCRIPTIONS
-- =========================================================

alter table public.subscriptions
  add column if not exists created_by uuid references public.profiles(id) on delete set null,
  add column if not exists updated_by uuid references public.profiles(id) on delete set null,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null,
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

alter table public.subscriptions
  add constraint subscriptions_version_positive
  check (version >= 1)
  not valid;

alter table public.subscriptions
  add constraint subscriptions_sync_status_check
  check (sync_status in ('synced', 'pending', 'conflict', 'error'))
  not valid;

comment on column public.subscriptions.created_by is 'Profile that created this subscription.';
comment on column public.subscriptions.updated_by is 'Profile that last updated this subscription.';
comment on column public.subscriptions.deleted_by is 'Profile that soft-deleted this subscription.';
comment on column public.subscriptions.delete_reason is 'Reason for soft-deleting this subscription.';
comment on column public.subscriptions.version is 'Optimistic concurrency version for sync and conflict detection.';
comment on column public.subscriptions.sync_status is 'Synchronization status for offline-first workflows.';

commit;