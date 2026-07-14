-- Fase 3.8 - RLS activity_logs, sync_logs and subscriptions
-- Objetivo:
-- Reemplazar policies antiguas basadas en profiles.business_id
-- por policies basadas en business_members, roles y permissions.
--
-- Nota:
-- activity_logs y sync_logs son tablas actuales básicas.
-- Más adelante serán complementadas/reemplazadas por:
-- audit_events, security_events, app_devices, sync_mutations,
-- sync_cursors y sync_conflicts.

begin;

-- =========================================================
-- Enable RLS
-- =========================================================

alter table public.activity_logs enable row level security;
alter table public.sync_logs enable row level security;
alter table public.subscriptions enable row level security;

-- =========================================================
-- Drop old policies: activity_logs
-- =========================================================

drop policy if exists activity_logs_insert_by_business on public.activity_logs;
drop policy if exists activity_logs_select_by_business on public.activity_logs;

drop policy if exists activity_logs_select_allowed on public.activity_logs;
drop policy if exists activity_logs_insert_allowed on public.activity_logs;
drop policy if exists activity_logs_update_blocked on public.activity_logs;
drop policy if exists activity_logs_delete_blocked on public.activity_logs;

-- =========================================================
-- Drop old policies: sync_logs
-- =========================================================

drop policy if exists sync_logs_insert_by_business on public.sync_logs;
drop policy if exists sync_logs_select_by_business on public.sync_logs;

drop policy if exists sync_logs_select_allowed on public.sync_logs;
drop policy if exists sync_logs_insert_allowed on public.sync_logs;
drop policy if exists sync_logs_update_blocked on public.sync_logs;
drop policy if exists sync_logs_delete_blocked on public.sync_logs;

-- =========================================================
-- Drop old policies: subscriptions
-- =========================================================

drop policy if exists subscriptions_insert_by_business on public.subscriptions;
drop policy if exists subscriptions_select_by_business on public.subscriptions;
drop policy if exists subscriptions_update_by_business on public.subscriptions;

drop policy if exists subscriptions_select_allowed on public.subscriptions;
drop policy if exists subscriptions_insert_allowed on public.subscriptions;
drop policy if exists subscriptions_update_allowed on public.subscriptions;
drop policy if exists subscriptions_delete_blocked on public.subscriptions;

-- =========================================================
-- ACTIVITY_LOGS: SELECT
-- Leer logs requiere audit.read.
-- =========================================================

create policy activity_logs_select_allowed
on public.activity_logs
for select
to authenticated
using (
  business_id is not null
  and private.has_business_permission(business_id, 'audit.read')
);

-- =========================================================
-- ACTIVITY_LOGS: INSERT
-- Permitimos insert temporal a miembros activos.
-- Más adelante, audit_events debería escribirse por triggers/RPC/servicio.
-- =========================================================

create policy activity_logs_insert_allowed
on public.activity_logs
for insert
to authenticated
with check (
  business_id is not null
  and private.is_business_member(business_id)
);

-- No UPDATE policy para activity_logs.
-- Los logs no deben editarse desde cliente.

create policy activity_logs_delete_blocked
on public.activity_logs
for delete
to authenticated
using (false);

-- =========================================================
-- SYNC_LOGS: SELECT
-- Leer logs de sync requiere ser miembro del negocio.
-- También se permite a quien tenga audit.read.
-- =========================================================

create policy sync_logs_select_allowed
on public.sync_logs
for select
to authenticated
using (
  business_id is not null
  and (
    private.is_business_member(business_id)
    or private.has_business_permission(business_id, 'audit.read')
  )
);

-- =========================================================
-- SYNC_LOGS: INSERT
-- Insert temporal permitido a miembros activos.
-- Más adelante será reemplazado por app_devices/sync_mutations/sync_cursors.
-- =========================================================

create policy sync_logs_insert_allowed
on public.sync_logs
for insert
to authenticated
with check (
  business_id is not null
  and private.is_business_member(business_id)
);

-- No UPDATE policy para sync_logs.

create policy sync_logs_delete_blocked
on public.sync_logs
for delete
to authenticated
using (false);

-- =========================================================
-- SUBSCRIPTIONS: SELECT
-- Ver suscripción requiere settings.billing o settings.business.
-- No lo abrimos a todos los miembros para evitar exposición innecesaria.
-- =========================================================

create policy subscriptions_select_allowed
on public.subscriptions
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'settings.billing')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

-- =========================================================
-- SUBSCRIPTIONS: INSERT
-- Crear suscripciones requiere settings.billing.
-- En producción real, idealmente lo hará billing/backend/service_role.
-- =========================================================

create policy subscriptions_insert_allowed
on public.subscriptions
for insert
to authenticated
with check (
  business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'settings.billing')
);

-- =========================================================
-- SUBSCRIPTIONS: UPDATE
-- Actualizar suscripciones requiere settings.billing.
-- =========================================================

create policy subscriptions_update_allowed
on public.subscriptions
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and private.has_business_permission(business_id, 'settings.billing')
)
with check (
  business_id is not null
  and private.has_business_permission(business_id, 'settings.billing')
);

-- No hard delete.

create policy subscriptions_delete_blocked
on public.subscriptions
for delete
to authenticated
using (false);

commit;