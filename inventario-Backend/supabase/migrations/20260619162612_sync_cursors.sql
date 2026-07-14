-- Fase 6.5 - Sync cursors
-- Objetivo:
-- Guardar el último punto de descarga/sincronización por dispositivo y entidad.
--
-- app_devices    = instalación/dispositivo
-- sync_batches   = lote de sync
-- sync_mutations = cambios subidos por la app
-- sync_conflicts = conflictos
-- sync_cursors   = último punto conocido por dispositivo para descargar cambios

begin;

-- =========================================================
-- SYNC CURSORS
-- =========================================================

create table if not exists public.sync_cursors (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  app_device_id uuid not null references public.app_devices(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete set null,

  entity_table text not null,
  cursor_name text not null default 'default',
  scope text not null default 'business',

  last_pulled_at timestamp without time zone,
  last_successful_sync_at timestamp without time zone,

  last_server_updated_at timestamp without time zone,
  last_server_version integer,

  last_sync_batch_id uuid references public.sync_batches(id) on delete set null,

  cursor_token text,

  full_resync_required boolean not null default false,

  status text not null default 'active',

  error_code text,
  error_message text,

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',
  metadata jsonb not null default '{}'::jsonb,

  constraint sync_cursors_entity_table_not_blank
    check (length(trim(entity_table)) > 0),

  constraint sync_cursors_entity_table_allowed
    check (
      entity_table in (
        'all',

        'businesses',
        'branches',
        'profiles',
        'business_members',
        'roles',
        'permissions',
        'role_permissions',

        'categories',
        'products',
        'customers',
        'suppliers',

        'purchases',
        'purchase_items',

        'sales',
        'sale_items',
        'sale_payments',

        'inventory_movements',
        'product_stock_balances',
        'stock_counts',
        'stock_count_items',
        'inventory_transfers',
        'inventory_transfer_items',

        'cash_registers',
        'cash_sessions',
        'receipt_sequences',

        'app_devices',
        'sync_batches',
        'sync_mutations',
        'sync_conflicts',

        'devices',
        'subscriptions',
        'activity_logs'
      )
    ),

  constraint sync_cursors_cursor_name_not_blank
    check (length(trim(cursor_name)) > 0),

  constraint sync_cursors_scope_check
    check (
      scope in (
        'business',
        'branch',
        'profile',
        'device'
      )
    ),

  constraint sync_cursors_status_check
    check (
      status in (
        'active',
        'stale',
        'reset_required',
        'disabled'
      )
    ),

  constraint sync_cursors_branch_scope_requires_branch
    check (
      scope <> 'branch'
      or branch_id is not null
    ),

  constraint sync_cursors_last_server_version_positive
    check (
      last_server_version is null
      or last_server_version >= 1
    ),

  constraint sync_cursors_pull_times_order
    check (
      last_pulled_at is null
      or last_successful_sync_at is null
      or last_successful_sync_at >= last_pulled_at
    ),

  constraint sync_cursors_error_requires_message
    check (
      status not in ('stale', 'reset_required')
      or error_message is not null
      or full_resync_required = true
    ),

  constraint sync_cursors_version_positive
    check (version >= 1),

  constraint sync_cursors_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

comment on table public.sync_cursors
is 'Download/sync cursors per app device and entity, used to fetch only changes since the last successful sync.';

comment on column public.sync_cursors.entity_table
is 'Entity/table this cursor tracks. Use all for a global cursor.';

comment on column public.sync_cursors.cursor_name
is 'Named cursor, usually default. Allows future specialized cursors.';

comment on column public.sync_cursors.scope
is 'Cursor scope: business, branch, profile or device.';

comment on column public.sync_cursors.last_server_updated_at
is 'Highest server updated_at value successfully sent to the device.';

comment on column public.sync_cursors.last_server_version
is 'Highest row version successfully sent to the device when applicable.';

comment on column public.sync_cursors.cursor_token
is 'Optional opaque token for pagination or future cursor strategies.';

comment on column public.sync_cursors.full_resync_required
is 'When true, the device should ignore incremental sync and request a full resync for this cursor.';

-- =========================================================
-- ÍNDICES
-- =========================================================

create unique index if not exists sync_cursors_device_entity_scope_unique
on public.sync_cursors (
  business_id,
  app_device_id,
  entity_table,
  cursor_name,
  scope,
  coalesce(branch_id, '00000000-0000-0000-0000-000000000000'::uuid)
)
where deleted_at is null;

create index if not exists sync_cursors_business_device_idx
on public.sync_cursors (business_id, app_device_id)
where deleted_at is null;

create index if not exists sync_cursors_business_entity_idx
on public.sync_cursors (business_id, entity_table, status)
where deleted_at is null;

create index if not exists sync_cursors_branch_entity_idx
on public.sync_cursors (business_id, branch_id, entity_table)
where deleted_at is null
  and branch_id is not null;

create index if not exists sync_cursors_resync_required_idx
on public.sync_cursors (business_id, app_device_id, entity_table)
where deleted_at is null
  and full_resync_required = true;

create index if not exists sync_cursors_last_successful_sync_idx
on public.sync_cursors (business_id, app_device_id, last_successful_sync_at desc)
where deleted_at is null;

-- =========================================================
-- VALIDAR DEVICE / BUSINESS / PROFILE / BRANCH
-- =========================================================

create or replace function private.validate_sync_cursor_device_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_device record;
begin
  select
    ad.business_id,
    ad.profile_id,
    ad.branch_id,
    ad.status,
    ad.deleted_at
  into v_device
  from public.app_devices ad
  where ad.id = new.app_device_id;

  if v_device.business_id is null then
    raise exception 'sync_cursors.app_device_id must reference an existing app_device';
  end if;

  if v_device.deleted_at is not null then
    raise exception 'Cannot create sync cursor for deleted app_device';
  end if;

  if tg_op = 'INSERT' and v_device.status <> 'active' then
    raise exception 'Cannot create sync cursor for inactive or blocked app_device';
  end if;

  if new.business_id <> v_device.business_id then
    raise exception 'sync_cursors.business_id must match app_devices.business_id';
  end if;

  if new.profile_id <> v_device.profile_id then
    raise exception 'sync_cursors.profile_id must match app_devices.profile_id';
  end if;

  if new.branch_id is not null then
    if not exists (
      select 1
      from public.branches br
      where br.id = new.branch_id
        and br.business_id = new.business_id
        and br.deleted_at is null
        and br.status = 'active'
    ) then
      raise exception 'sync_cursors.branch_id must belong to the same active business';
    end if;
  end if;

  if v_device.branch_id is not null
     and new.branch_id is not null
     and new.branch_id <> v_device.branch_id then
    raise exception 'sync_cursors.branch_id must match app_devices.branch_id when device is branch-scoped';
  end if;

  return new;
end;
$$;

comment on function private.validate_sync_cursor_device_consistency()
is 'Ensures sync_cursors match app_devices business/profile and optional branch scope.';

drop trigger if exists trg_sync_cursors_validate_device_consistency
on public.sync_cursors;

create trigger trg_sync_cursors_validate_device_consistency
before insert or update of business_id, app_device_id, profile_id, branch_id
on public.sync_cursors
for each row
execute function private.validate_sync_cursor_device_consistency();

-- =========================================================
-- VALIDAR LAST SYNC BATCH
-- =========================================================

create or replace function private.validate_sync_cursor_batch_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch record;
begin
  if new.last_sync_batch_id is null then
    return new;
  end if;

  select
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.deleted_at
  into v_batch
  from public.sync_batches sb
  where sb.id = new.last_sync_batch_id;

  if v_batch.business_id is null then
    raise exception 'sync_cursors.last_sync_batch_id must reference an existing sync_batch';
  end if;

  if v_batch.deleted_at is not null then
    raise exception 'sync_cursors.last_sync_batch_id cannot reference a deleted sync_batch';
  end if;

  if new.business_id <> v_batch.business_id then
    raise exception 'sync_cursors.business_id must match sync_batches.business_id';
  end if;

  if new.app_device_id <> v_batch.app_device_id then
    raise exception 'sync_cursors.app_device_id must match sync_batches.app_device_id';
  end if;

  if new.profile_id <> v_batch.profile_id then
    raise exception 'sync_cursors.profile_id must match sync_batches.profile_id';
  end if;

  if new.branch_id is not null
     and v_batch.branch_id is not null
     and new.branch_id <> v_batch.branch_id then
    raise exception 'sync_cursors.branch_id must match sync_batches.branch_id when both are present';
  end if;

  return new;
end;
$$;

comment on function private.validate_sync_cursor_batch_consistency()
is 'Ensures sync_cursors.last_sync_batch_id belongs to the same device/business/profile.';

drop trigger if exists trg_sync_cursors_validate_batch_consistency
on public.sync_cursors;

create trigger trg_sync_cursors_validate_batch_consistency
before insert or update of last_sync_batch_id, business_id, app_device_id, profile_id, branch_id
on public.sync_cursors
for each row
execute function private.validate_sync_cursor_batch_consistency();

-- =========================================================
-- FILL DEFAULTS
-- =========================================================

create or replace function private.fill_sync_cursor_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  new.created_by := coalesce(new.created_by, auth.uid());
  new.updated_by := coalesce(new.updated_by, auth.uid());

  if new.cursor_name is null or length(trim(new.cursor_name)) = 0 then
    new.cursor_name := 'default';
  end if;

  if new.scope is null then
    new.scope := case
      when new.branch_id is not null then 'branch'
      else 'business'
    end;
  end if;

  if new.full_resync_required = true and new.status = 'active' then
    new.status := 'reset_required';
  end if;

  if new.last_successful_sync_at is null and new.last_pulled_at is not null then
    new.last_successful_sync_at := new.last_pulled_at;
  end if;

  return new;
end;
$$;

comment on function private.fill_sync_cursor_defaults()
is 'Fills audit fields and default scope/name/status for sync_cursors.';

drop trigger if exists trg_sync_cursors_fill_defaults
on public.sync_cursors;

create trigger trg_sync_cursors_fill_defaults
before insert or update of cursor_name, scope, full_resync_required, status, last_pulled_at
on public.sync_cursors
for each row
execute function private.fill_sync_cursor_defaults();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_sync_cursors_updated_at
on public.sync_cursors;

create trigger trg_sync_cursors_updated_at
before update on public.sync_cursors
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_sync_cursors_increment_version
on public.sync_cursors;

create trigger trg_sync_cursors_increment_version
before update on public.sync_cursors
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.sync_cursors enable row level security;

drop policy if exists sync_cursors_select_allowed on public.sync_cursors;
drop policy if exists sync_cursors_insert_own_allowed on public.sync_cursors;
drop policy if exists sync_cursors_update_own_allowed on public.sync_cursors;
drop policy if exists sync_cursors_admin_update_allowed on public.sync_cursors;
drop policy if exists sync_cursors_delete_blocked on public.sync_cursors;

-- Usuario ve sus propios cursores.
-- Admin/settings/security puede auditar cursores del negocio.
create policy sync_cursors_select_allowed
on public.sync_cursors
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and (
    profile_id = auth.uid()
    or private.has_business_permission(business_id, 'settings.business')
    or private.has_business_permission(business_id, 'security_events.read')
  )
);

-- Usuario puede crear cursores de su propio dispositivo.
create policy sync_cursors_insert_own_allowed
on public.sync_cursors
for insert
to authenticated
with check (
  deleted_at is null
  and profile_id = auth.uid()
  and private.is_business_member(business_id)
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
  and exists (
    select 1
    from public.app_devices ad
    where ad.id = sync_cursors.app_device_id
      and ad.business_id = sync_cursors.business_id
      and ad.profile_id = auth.uid()
      and ad.status = 'active'
      and ad.deleted_at is null
  )
);

-- Usuario puede actualizar sus propios cursores.
create policy sync_cursors_update_own_allowed
on public.sync_cursors
for update
to authenticated
using (
  deleted_at is null
  and profile_id = auth.uid()
  and private.is_business_member(business_id)
)
with check (
  profile_id = auth.uid()
  and private.is_business_member(business_id)
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
);

-- Admin/settings/security puede actualizar cursores del negocio.
create policy sync_cursors_admin_update_allowed
on public.sync_cursors
for update
to authenticated
using (
  deleted_at is null
  and (
    private.has_business_permission(business_id, 'settings.business')
    or private.has_business_permission(business_id, 'security_events.read')
  )
)
with check (
  private.has_business_permission(business_id, 'settings.business')
  or private.has_business_permission(business_id, 'security_events.read')
);

-- No hard delete.
create policy sync_cursors_delete_blocked
on public.sync_cursors
for delete
to authenticated
using (false);

commit;