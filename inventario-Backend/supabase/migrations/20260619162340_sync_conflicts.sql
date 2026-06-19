-- Fase 6.4 - Sync conflicts
-- Objetivo:
-- Registrar conflictos detectados durante la sincronización offline-first.
--
-- sync_batches    = lote de sincronización
-- sync_mutations  = cambios individuales subidos por la app
-- sync_conflicts  = conflictos generados por mutaciones que no se pueden aplicar limpiamente
--
-- Nota:
-- Esta tabla no resuelve conflictos automáticamente.
-- La resolución vendrá después con process_sync_batch() y/o funciones de resolución.

begin;

-- =========================================================
-- SYNC CONFLICTS
-- =========================================================

create table if not exists public.sync_conflicts (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  sync_batch_id uuid not null references public.sync_batches(id) on delete cascade,
  sync_mutation_id uuid not null references public.sync_mutations(id) on delete cascade,
  app_device_id uuid not null references public.app_devices(id) on delete restrict,
  profile_id uuid not null references public.profiles(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete set null,

  entity_table text not null,
  entity_id uuid not null,
  operation text not null,

  client_mutation_id text not null,
  client_sequence integer not null,

  conflict_type text not null,
  severity text not null default 'medium',
  status text not null default 'open',

  base_payload jsonb,
  client_payload jsonb not null default '{}'::jsonb,
  server_payload jsonb,
  resolved_payload jsonb,

  base_version integer,
  server_entity_version integer,

  error_code text,
  error_message text,

  resolution_strategy text,
  resolution_notes text,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamp without time zone,

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

  constraint sync_conflicts_entity_table_not_blank
    check (length(trim(entity_table)) > 0),

  constraint sync_conflicts_entity_table_allowed
    check (
      entity_table in (
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
        'stock_counts',
        'stock_count_items',
        'inventory_transfers',
        'inventory_transfer_items',

        'cash_sessions',
        'cash_registers'
      )
    ),

  constraint sync_conflicts_operation_check
    check (
      operation in (
        'insert',
        'update',
        'upsert',
        'soft_delete',
        'delete'
      )
    ),

  constraint sync_conflicts_client_mutation_id_not_blank
    check (length(trim(client_mutation_id)) > 0),

  constraint sync_conflicts_client_sequence_non_negative
    check (client_sequence >= 0),

  constraint sync_conflicts_conflict_type_check
    check (
      conflict_type in (
        'version_mismatch',
        'updated_at_mismatch',
        'missing_server_row',
        'missing_client_base',
        'deleted_on_server',
        'duplicate_key',
        'permission_denied',
        'validation_error',
        'business_rule_violation',
        'unknown'
      )
    ),

  constraint sync_conflicts_severity_check
    check (
      severity in (
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  constraint sync_conflicts_status_check
    check (
      status in (
        'open',
        'resolved_client_wins',
        'resolved_server_wins',
        'resolved_manual',
        'ignored'
      )
    ),

  constraint sync_conflicts_client_payload_object_check
    check (jsonb_typeof(client_payload) = 'object'),

  constraint sync_conflicts_base_payload_object_check
    check (
      base_payload is null
      or jsonb_typeof(base_payload) = 'object'
    ),

  constraint sync_conflicts_server_payload_object_check
    check (
      server_payload is null
      or jsonb_typeof(server_payload) = 'object'
    ),

  constraint sync_conflicts_resolved_payload_object_check
    check (
      resolved_payload is null
      or jsonb_typeof(resolved_payload) = 'object'
    ),

  constraint sync_conflicts_base_version_positive
    check (
      base_version is null
      or base_version >= 1
    ),

  constraint sync_conflicts_server_entity_version_positive
    check (
      server_entity_version is null
      or server_entity_version >= 1
    ),

  constraint sync_conflicts_resolved_requires_timestamp
    check (
      status = 'open'
      or resolved_at is not null
    ),

  constraint sync_conflicts_manual_requires_payload
    check (
      status <> 'resolved_manual'
      or resolved_payload is not null
    ),

  constraint sync_conflicts_version_positive
    check (version >= 1),

  constraint sync_conflicts_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

comment on table public.sync_conflicts
is 'Conflicts detected while processing offline-first sync mutations.';

comment on column public.sync_conflicts.sync_mutation_id
is 'Mutation that produced this conflict.';

comment on column public.sync_conflicts.conflict_type
is 'Reason why the mutation could not be applied cleanly.';

comment on column public.sync_conflicts.base_payload
is 'Optional client-known base snapshot when the offline mutation was created.';

comment on column public.sync_conflicts.client_payload
is 'Payload sent by the app/device.';

comment on column public.sync_conflicts.server_payload
is 'Current server-side payload at conflict detection time.';

comment on column public.sync_conflicts.resolved_payload
is 'Final payload selected when conflict is manually resolved.';

comment on column public.sync_conflicts.status
is 'Conflict lifecycle: open, resolved_client_wins, resolved_server_wins, resolved_manual or ignored.';

-- =========================================================
-- ÍNDICES
-- =========================================================

create unique index if not exists sync_conflicts_mutation_unique
on public.sync_conflicts (sync_mutation_id)
where deleted_at is null;

create index if not exists sync_conflicts_batch_status_idx
on public.sync_conflicts (sync_batch_id, status, created_at desc)
where deleted_at is null;

create index if not exists sync_conflicts_business_status_idx
on public.sync_conflicts (business_id, status, created_at desc)
where deleted_at is null;

create index if not exists sync_conflicts_device_status_idx
on public.sync_conflicts (app_device_id, status, created_at desc)
where deleted_at is null;

create index if not exists sync_conflicts_profile_status_idx
on public.sync_conflicts (business_id, profile_id, status, created_at desc)
where deleted_at is null;

create index if not exists sync_conflicts_entity_idx
on public.sync_conflicts (business_id, entity_table, entity_id)
where deleted_at is null;

create index if not exists sync_conflicts_open_idx
on public.sync_conflicts (business_id, severity, created_at desc)
where deleted_at is null
  and status = 'open';

-- =========================================================
-- VALIDAR MUTATION / BATCH / DEVICE / PROFILE
-- =========================================================

create or replace function private.validate_sync_conflict_mutation_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
begin
  select
    sm.id,
    sm.business_id,
    sm.sync_batch_id,
    sm.app_device_id,
    sm.profile_id,
    sm.branch_id,
    sm.client_mutation_id,
    sm.client_sequence,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.before_payload,
    sm.base_version,
    sm.server_entity_version,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = new.sync_mutation_id;

  if v_mutation.id is null then
    raise exception 'sync_conflicts.sync_mutation_id must reference an existing sync_mutation';
  end if;

  if v_mutation.deleted_at is not null then
    raise exception 'Cannot create conflict for deleted sync_mutation';
  end if;

  if new.business_id <> v_mutation.business_id then
    raise exception 'sync_conflicts.business_id must match sync_mutations.business_id';
  end if;

  if new.sync_batch_id <> v_mutation.sync_batch_id then
    raise exception 'sync_conflicts.sync_batch_id must match sync_mutations.sync_batch_id';
  end if;

  if new.app_device_id <> v_mutation.app_device_id then
    raise exception 'sync_conflicts.app_device_id must match sync_mutations.app_device_id';
  end if;

  if new.profile_id <> v_mutation.profile_id then
    raise exception 'sync_conflicts.profile_id must match sync_mutations.profile_id';
  end if;

  if coalesce(new.branch_id, '00000000-0000-0000-0000-000000000000'::uuid)
     <> coalesce(v_mutation.branch_id, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'sync_conflicts.branch_id must match sync_mutations.branch_id';
  end if;

  if new.entity_table <> v_mutation.entity_table then
    raise exception 'sync_conflicts.entity_table must match sync_mutations.entity_table';
  end if;

  if new.entity_id <> v_mutation.entity_id then
    raise exception 'sync_conflicts.entity_id must match sync_mutations.entity_id';
  end if;

  if new.operation <> v_mutation.operation then
    raise exception 'sync_conflicts.operation must match sync_mutations.operation';
  end if;

  if new.client_mutation_id <> v_mutation.client_mutation_id then
    raise exception 'sync_conflicts.client_mutation_id must match sync_mutations.client_mutation_id';
  end if;

  if new.client_sequence <> v_mutation.client_sequence then
    raise exception 'sync_conflicts.client_sequence must match sync_mutations.client_sequence';
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
      raise exception 'sync_conflicts.branch_id must belong to the same active business';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.validate_sync_conflict_mutation_consistency()
is 'Ensures sync_conflicts match their parent sync_mutation.';

drop trigger if exists trg_sync_conflicts_validate_mutation_consistency
on public.sync_conflicts;

create trigger trg_sync_conflicts_validate_mutation_consistency
before insert or update of business_id, sync_batch_id, sync_mutation_id, app_device_id, profile_id, branch_id, entity_table, entity_id, operation, client_mutation_id, client_sequence
on public.sync_conflicts
for each row
execute function private.validate_sync_conflict_mutation_consistency();

-- =========================================================
-- FILL DEFAULTS FROM MUTATION
-- =========================================================

create or replace function private.fill_sync_conflict_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
begin
  select
    sm.payload,
    sm.before_payload,
    sm.base_version,
    sm.server_entity_version
  into v_mutation
  from public.sync_mutations sm
  where sm.id = new.sync_mutation_id;

  new.client_payload := coalesce(new.client_payload, v_mutation.payload, '{}'::jsonb);
  new.base_payload := coalesce(new.base_payload, v_mutation.before_payload);
  new.base_version := coalesce(new.base_version, v_mutation.base_version);
  new.server_entity_version := coalesce(new.server_entity_version, v_mutation.server_entity_version);

  new.created_by := coalesce(new.created_by, auth.uid());
  new.updated_by := coalesce(new.updated_by, auth.uid());

  if new.status <> 'open' and new.resolved_at is null then
    new.resolved_at := now();
  end if;

  if new.status <> 'open' and new.resolved_by is null then
    new.resolved_by := auth.uid();
  end if;

  return new;
end;
$$;

comment on function private.fill_sync_conflict_defaults()
is 'Fills payload snapshots, audit fields and resolution timestamps for sync_conflicts.';

drop trigger if exists trg_sync_conflicts_fill_defaults
on public.sync_conflicts;

create trigger trg_sync_conflicts_fill_defaults
before insert or update of status
on public.sync_conflicts
for each row
execute function private.fill_sync_conflict_defaults();

-- =========================================================
-- MARK MUTATION AS CONFLICT
-- =========================================================

create or replace function private.mark_sync_mutation_as_conflict()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  update public.sync_mutations sm
  set
    status = 'conflict',
    error_code = coalesce(new.error_code, new.conflict_type),
    error_message = coalesce(new.error_message, 'Sync conflict detected'),
    server_processed_at = coalesce(sm.server_processed_at, now()),
    updated_at = now()
  where sm.id = new.sync_mutation_id
    and sm.status <> 'conflict';

  update public.sync_batches sb
  set
    conflict_count = conflict_count + 1,
    updated_at = now()
  where sb.id = new.sync_batch_id;

  return new;
end;
$$;

comment on function private.mark_sync_mutation_as_conflict()
is 'Marks parent sync_mutation as conflict and increments sync_batches.conflict_count.';

drop trigger if exists trg_sync_conflicts_mark_mutation
on public.sync_conflicts;

create trigger trg_sync_conflicts_mark_mutation
after insert
on public.sync_conflicts
for each row
execute function private.mark_sync_mutation_as_conflict();

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_sync_conflicts_updated_at
on public.sync_conflicts;

create trigger trg_sync_conflicts_updated_at
before update on public.sync_conflicts
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_sync_conflicts_increment_version
on public.sync_conflicts;

create trigger trg_sync_conflicts_increment_version
before update on public.sync_conflicts
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- RLS
-- =========================================================

alter table public.sync_conflicts enable row level security;

drop policy if exists sync_conflicts_select_allowed on public.sync_conflicts;
drop policy if exists sync_conflicts_insert_own_allowed on public.sync_conflicts;
drop policy if exists sync_conflicts_update_resolution_allowed on public.sync_conflicts;
drop policy if exists sync_conflicts_admin_update_allowed on public.sync_conflicts;
drop policy if exists sync_conflicts_delete_blocked on public.sync_conflicts;

-- Usuario ve sus propios conflictos.
-- Admin/settings/security puede auditar conflictos del negocio.
create policy sync_conflicts_select_allowed
on public.sync_conflicts
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

-- El usuario puede registrar conflictos asociados a sus propias mutaciones.
-- En la práctica, process_sync_batch() también podrá insertarlos con SECURITY DEFINER.
create policy sync_conflicts_insert_own_allowed
on public.sync_conflicts
for insert
to authenticated
with check (
  deleted_at is null
  and profile_id = auth.uid()
  and private.is_business_member(business_id)
  and exists (
    select 1
    from public.sync_mutations sm
    where sm.id = sync_conflicts.sync_mutation_id
      and sm.business_id = sync_conflicts.business_id
      and sm.sync_batch_id = sync_conflicts.sync_batch_id
      and sm.app_device_id = sync_conflicts.app_device_id
      and sm.profile_id = auth.uid()
      and sm.deleted_at is null
  )
);

-- Usuario puede resolver sus propios conflictos abiertos.
create policy sync_conflicts_update_resolution_allowed
on public.sync_conflicts
for update
to authenticated
using (
  deleted_at is null
  and profile_id = auth.uid()
  and private.is_business_member(business_id)
  and status = 'open'
)
with check (
  profile_id = auth.uid()
  and private.is_business_member(business_id)
);

-- Admin/settings/security puede resolver o actualizar conflictos del negocio.
create policy sync_conflicts_admin_update_allowed
on public.sync_conflicts
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
create policy sync_conflicts_delete_blocked
on public.sync_conflicts
for delete
to authenticated
using (false);

commit;