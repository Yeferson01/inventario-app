-- Fase 6.15A - Apply offline sync para purchases y purchase_items
-- Objetivo:
-- Permitir que process_sync_batch(..., 'apply_purchases') aplique compras offline.
--
-- Nota:
-- Esta fase NO aplica inventario automáticamente.
-- La aplicación de inventario por compras queda separada para 6.15C,
-- usando public.apply_purchase_inventory_movements(purchase_id).

begin;

-- =========================================================
-- 1. PATCH PROFESIONAL PARA purchases
-- =========================================================

alter table public.purchases
  add column if not exists branch_id uuid references public.branches(id),
  add column if not exists idempotency_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists updated_by uuid references public.profiles(id),
  add column if not exists deleted_by uuid references public.profiles(id),
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced';

update public.purchases p
set
  branch_id = coalesce(p.branch_id, br.id),
  metadata = coalesce(p.metadata, '{}'::jsonb),
  sync_status = coalesce(p.sync_status, 'synced'),
  version = greatest(coalesce(p.version, 1), 1)
from public.branches br
where br.business_id = p.business_id
  and br.deleted_at is null
  and br.status = 'active'
  and p.branch_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchases_version_positive'
      and conrelid = 'public.purchases'::regclass
  ) then
    alter table public.purchases
      add constraint purchases_version_positive
      check (version >= 1) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchases_sync_status_allowed'
      and conrelid = 'public.purchases'::regclass
  ) then
    alter table public.purchases
      add constraint purchases_sync_status_allowed
      check (sync_status in ('synced', 'pending', 'conflict', 'error')) not valid;
  end if;
end $$;

do $$
begin
  alter table public.purchases validate constraint purchases_version_positive;
exception when others then
  raise notice 'Could not validate purchases_version_positive: %', sqlerrm;
end $$;

do $$
begin
  alter table public.purchases validate constraint purchases_sync_status_allowed;
exception when others then
  raise notice 'Could not validate purchases_sync_status_allowed: %', sqlerrm;
end $$;

create unique index if not exists purchases_business_idempotency_active_uidx
on public.purchases (business_id, idempotency_key)
where idempotency_key is not null
  and deleted_at is null;

create index if not exists idx_purchases_business_branch_status
on public.purchases (business_id, branch_id, status)
where deleted_at is null;

create index if not exists idx_purchases_business_updated_at
on public.purchases (business_id, updated_at)
where deleted_at is null;

-- =========================================================
-- 2. PATCH PROFESIONAL PARA purchase_items
-- =========================================================

alter table public.purchase_items
  add column if not exists business_id uuid references public.businesses(id),
  add column if not exists branch_id uuid references public.branches(id),
  add column if not exists updated_at timestamp without time zone default now(),
  add column if not exists deleted_at timestamp without time zone,
  add column if not exists created_by uuid references public.profiles(id),
  add column if not exists updated_by uuid references public.profiles(id),
  add column if not exists deleted_by uuid references public.profiles(id),
  add column if not exists delete_reason text,
  add column if not exists version integer not null default 1,
  add column if not exists sync_status text not null default 'synced',
  add column if not exists idempotency_key text,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

update public.purchase_items pi
set
  business_id = coalesce(pi.business_id, p.business_id),
  branch_id = coalesce(pi.branch_id, p.branch_id),
  updated_at = coalesce(pi.updated_at, pi.created_at, now()),
  metadata = coalesce(pi.metadata, '{}'::jsonb),
  sync_status = coalesce(pi.sync_status, 'synced'),
  version = greatest(coalesce(pi.version, 1), 1)
from public.purchases p
where p.id = pi.purchase_id
  and (
    pi.business_id is null
    or pi.branch_id is null
    or pi.updated_at is null
    or pi.metadata is null
    or pi.sync_status is null
    or pi.version is null
  );

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_items_version_positive'
      and conrelid = 'public.purchase_items'::regclass
  ) then
    alter table public.purchase_items
      add constraint purchase_items_version_positive
      check (version >= 1) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_items_sync_status_allowed'
      and conrelid = 'public.purchase_items'::regclass
  ) then
    alter table public.purchase_items
      add constraint purchase_items_sync_status_allowed
      check (sync_status in ('synced', 'pending', 'conflict', 'error')) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_items_quantity_positive_sync'
      and conrelid = 'public.purchase_items'::regclass
  ) then
    alter table public.purchase_items
      add constraint purchase_items_quantity_positive_sync
      check (quantity > 0) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_items_unit_cost_nonnegative_sync'
      and conrelid = 'public.purchase_items'::regclass
  ) then
    alter table public.purchase_items
      add constraint purchase_items_unit_cost_nonnegative_sync
      check (unit_cost >= 0) not valid;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'purchase_items_subtotal_nonnegative_sync'
      and conrelid = 'public.purchase_items'::regclass
  ) then
    alter table public.purchase_items
      add constraint purchase_items_subtotal_nonnegative_sync
      check (subtotal >= 0) not valid;
  end if;
end $$;

do $$
begin
  alter table public.purchase_items validate constraint purchase_items_version_positive;
exception when others then
  raise notice 'Could not validate purchase_items_version_positive: %', sqlerrm;
end $$;

do $$
begin
  alter table public.purchase_items validate constraint purchase_items_sync_status_allowed;
exception when others then
  raise notice 'Could not validate purchase_items_sync_status_allowed: %', sqlerrm;
end $$;

do $$
begin
  alter table public.purchase_items validate constraint purchase_items_quantity_positive_sync;
exception when others then
  raise notice 'Could not validate purchase_items_quantity_positive_sync: %', sqlerrm;
end $$;

do $$
begin
  alter table public.purchase_items validate constraint purchase_items_unit_cost_nonnegative_sync;
exception when others then
  raise notice 'Could not validate purchase_items_unit_cost_nonnegative_sync: %', sqlerrm;
end $$;

do $$
begin
  alter table public.purchase_items validate constraint purchase_items_subtotal_nonnegative_sync;
exception when others then
  raise notice 'Could not validate purchase_items_subtotal_nonnegative_sync: %', sqlerrm;
end $$;

create unique index if not exists purchase_items_business_idempotency_active_uidx
on public.purchase_items (business_id, idempotency_key)
where idempotency_key is not null
  and deleted_at is null;

create index if not exists idx_purchase_items_business_purchase_active
on public.purchase_items (business_id, purchase_id)
where deleted_at is null;

create index if not exists idx_purchase_items_business_product_active
on public.purchase_items (business_id, product_id)
where deleted_at is null;

create index if not exists idx_purchase_items_business_updated_at
on public.purchase_items (business_id, updated_at)
where deleted_at is null;

-- =========================================================
-- 3. TRIGGERS DE CONSISTENCIA PARA purchase_items
-- =========================================================

create or replace function private.validate_purchase_item_purchase_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_purchase record;
begin
  if new.purchase_id is null then
    raise exception 'purchase_items.purchase_id is required';
  end if;

  select p.id, p.business_id, p.branch_id, p.deleted_at
  into v_purchase
  from public.purchases p
  where p.id = new.purchase_id;

  if v_purchase.id is null then
    raise exception 'purchase_items.purchase_id does not exist';
  end if;

  if v_purchase.deleted_at is not null then
    raise exception 'Cannot attach purchase_item to deleted purchase';
  end if;

  if new.business_id is not null and new.business_id <> v_purchase.business_id then
    raise exception 'purchase_items.business_id must match purchase.business_id';
  end if;

  if new.branch_id is not null
     and v_purchase.branch_id is not null
     and new.branch_id <> v_purchase.branch_id then
    raise exception 'purchase_items.branch_id must match purchase.branch_id';
  end if;

  new.business_id := v_purchase.business_id;
  new.branch_id := v_purchase.branch_id;

  return new;
end;
$$;

create or replace function private.validate_purchase_item_product_consistency()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_product_business_id uuid;
begin
  if new.product_id is null then
    raise exception 'purchase_items.product_id is required';
  end if;

  select p.business_id
  into v_product_business_id
  from public.products p
  where p.id = new.product_id
    and p.deleted_at is null;

  if v_product_business_id is null then
    raise exception 'purchase_items.product_id does not exist or is deleted';
  end if;

  if new.business_id is not null and new.business_id <> v_product_business_id then
    raise exception 'purchase_items.product_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

create or replace function private.fill_purchase_item_defaults()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  new.quantity := coalesce(new.quantity, 1);
  new.unit_cost := coalesce(new.unit_cost, 0);
  new.subtotal := coalesce(new.subtotal, new.quantity * new.unit_cost);

  if new.subtotal <> new.quantity * new.unit_cost then
    new.subtotal := new.quantity * new.unit_cost;
  end if;

  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.version := greatest(coalesce(new.version, 1), 1);

  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
  end if;

  new.updated_at := now();

  return new;
end;
$$;

drop trigger if exists trg_purchase_items_validate_purchase on public.purchase_items;
create trigger trg_purchase_items_validate_purchase
before insert or update of purchase_id, business_id, branch_id
on public.purchase_items
for each row
execute function private.validate_purchase_item_purchase_consistency();

drop trigger if exists trg_purchase_items_validate_product on public.purchase_items;
create trigger trg_purchase_items_validate_product
before insert or update of product_id, business_id
on public.purchase_items
for each row
execute function private.validate_purchase_item_product_consistency();

drop trigger if exists trg_purchase_items_fill_defaults on public.purchase_items;
create trigger trg_purchase_items_fill_defaults
before insert or update
on public.purchase_items
for each row
execute function private.fill_purchase_item_defaults();

drop trigger if exists trg_purchase_items_version on public.purchase_items;
create trigger trg_purchase_items_version
before update
on public.purchase_items
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- 4. RECÁLCULO DE TOTAL DE COMPRA
-- =========================================================

create or replace function public.recalculate_purchase_totals(
  p_purchase_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_total numeric := 0;
begin
  if p_purchase_id is null then
    raise exception 'p_purchase_id is required';
  end if;

  select coalesce(sum(pi.subtotal), 0)
  into v_total
  from public.purchase_items pi
  where pi.purchase_id = p_purchase_id
    and pi.deleted_at is null;

  update public.purchases p
  set
    total = v_total,
    updated_at = now()
  where p.id = p_purchase_id;

  return v_total;
end;
$$;

comment on function public.recalculate_purchase_totals(uuid)
is 'Recalculates purchases.total from non-deleted purchase_items.';

revoke all on function public.recalculate_purchase_totals(uuid) from public;
grant execute on function public.recalculate_purchase_totals(uuid) to authenticated, service_role;

create or replace function private.recalculate_purchase_totals_from_item()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
begin
  if tg_op = 'DELETE' then
    perform public.recalculate_purchase_totals(old.purchase_id);
    return old;
  end if;

  perform public.recalculate_purchase_totals(new.purchase_id);
  return new;
end;
$$;

drop trigger if exists trg_purchase_items_recalculate_purchase_totals on public.purchase_items;
create trigger trg_purchase_items_recalculate_purchase_totals
after insert or update of quantity, unit_cost, subtotal, deleted_at, purchase_id
on public.purchase_items
for each row
execute function private.recalculate_purchase_totals_from_item();

-- =========================================================
-- 5. PULL ALLOWLIST: incluir purchases y purchase_items
-- =========================================================

create or replace function private.sync_pull_allowed_entities()
returns text[]
language sql
stable
security definer
set search_path = public, private, extensions
as $$
  select array[
    'businesses',
    'branches',
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

    'product_stock_balances',
    'inventory_movements',

    'cash_registers',
    'cash_sessions'
  ]::text[];
$$;

comment on function private.sync_pull_allowed_entities()
is 'Returns the allowlisted entity tables that can be downloaded by pull sync RPCs.';

revoke all on function private.sync_pull_allowed_entities() from public;
grant execute on function private.sync_pull_allowed_entities() to authenticated, service_role;

-- =========================================================
-- 6. PERMISSION CANDIDATES: incluir compras
-- =========================================================

create or replace function private.sync_entity_permission_candidates(
  p_entity_table text,
  p_operation text
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text := lower(trim(coalesce(p_entity_table, '')));
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_action text;
begin
  v_action := case
    when v_operation in ('insert', 'upsert') then 'create'
    when v_operation in ('update') then 'update'
    when v_operation in ('soft_delete') then 'soft_delete'
    when v_operation in ('delete') then 'soft_delete'
    else 'read'
  end;

  if v_entity in ('categories', 'products', 'customers', 'suppliers') then
    return array[
      v_entity || '.' || v_action,
      v_entity || '.manage',
      'settings.business'
    ];
  end if;

  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array[
      'sales.' || v_action,
      'sales.manage',
      'settings.business'
    ];
  end if;

  if v_entity in ('purchases', 'purchase_items') then
    return array[
      'purchases.' || v_action,
      'purchases.manage',
      'inventory.purchase',
      'inventory.adjust',
      'settings.business'
    ];
  end if;

  if v_entity in ('inventory_movements') then
    if v_action in ('update', 'soft_delete') then
      return array[]::text[];
    end if;

    return array[
      'inventory.adjust',
      'inventory.manage',
      'settings.business'
    ];
  end if;

  if v_entity in ('stock_counts', 'stock_count_items') then
    return array[
      'inventory.count',
      'inventory.adjust',
      'inventory.manage',
      'settings.business'
    ];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array[
      'inventory.transfer',
      'inventory.adjust',
      'inventory.manage',
      'settings.business'
    ];
  end if;

  if v_entity in ('cash_registers', 'cash_sessions') then
    return array[
      'cash.' || v_action,
      'cash.manage',
      'settings.business'
    ];
  end if;

  return array[
    'settings.business'
  ];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text)
is 'Returns possible permissions that authorize a sync mutation for an entity/operation.';

revoke all on function private.sync_entity_permission_candidates(text, text) from public;
grant execute on function private.sync_entity_permission_candidates(text, text) to authenticated, service_role;

-- =========================================================
-- 7. APPLY PURCHASE MUTATION
-- =========================================================

create or replace function private.apply_sync_purchase_mutation(
  p_sync_mutation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_payload jsonb;
  v_metadata jsonb;

  v_entity text;
  v_operation text;

  v_current_purchase record;
  v_current_item record;
  v_parent_purchase record;

  v_entity_id uuid;
  v_purchase_id uuid;
  v_product_id uuid;
  v_supplier_id uuid;
  v_branch_id uuid;

  v_quantity integer;
  v_unit_cost numeric;
  v_subtotal numeric;

  v_new_version integer;
begin
  select
    sm.id,
    sm.sync_batch_id,
    sm.app_device_id,
    sm.profile_id,
    sm.business_id,
    sm.branch_id,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.base_version,
    sm.idempotency_key,
    sb.status as batch_status
  into v_mutation
  from public.sync_mutations sm
  join public.sync_batches sb on sb.id = sm.sync_batch_id
  where sm.id = p_sync_mutation_id
    and sm.deleted_at is null;

  if v_mutation.id is null then
    raise exception 'sync mutation not found';
  end if;

  v_entity := lower(trim(v_mutation.entity_table));
  v_operation := lower(trim(v_mutation.operation));
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);
  v_metadata := case
    when jsonb_typeof(v_payload -> 'metadata') = 'object' then v_payload -> 'metadata'
    else '{}'::jsonb
  end;

  v_entity_id := v_mutation.entity_id;

  if v_entity_id is null then
    perform private.mark_sync_mutation_error(
      v_mutation.id,
      'validation_error',
      'entity_id is required'
    );
    return;
  end if;

  if v_operation = 'delete' then
    perform private.create_sync_conflict_for_mutation(
      v_mutation.id,
      'business_rule_violation',
      'Hard delete is not allowed for purchases sync. Use soft_delete.',
      null,
      'client_retry',
      jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
    );
    return;
  end if;

  -- =======================================================
  -- purchases
  -- =======================================================

  if v_entity = 'purchases' then
    select *
    into v_current_purchase
    from public.purchases p
    where p.id = v_entity_id
    for update;

    if v_operation = 'insert' and v_current_purchase.id is not null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'duplicate_key',
        'Purchase already exists on server',
        to_jsonb(v_current_purchase),
        'server_wins',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_operation in ('update', 'soft_delete') and v_current_purchase.id is null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'missing_server_row',
        'Purchase does not exist on server',
        null,
        'client_retry',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_current_purchase.id is not null
       and v_current_purchase.deleted_at is not null
       and v_operation <> 'upsert' then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'deleted_on_server',
        'Purchase is already deleted on server',
        to_jsonb(v_current_purchase),
        'server_wins',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_current_purchase.id is not null
       and v_mutation.base_version is not null
       and coalesce(v_current_purchase.version, 1) > v_mutation.base_version then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'version_mismatch',
        'Purchase version on server is newer than client base_version',
        to_jsonb(v_current_purchase),
        'manual_review',
        jsonb_build_object(
          'entity_table', v_entity,
          'server_version', v_current_purchase.version,
          'client_base_version', v_mutation.base_version
        )
      );
      return;
    end if;

    if v_operation in ('insert', 'upsert') and v_current_purchase.id is null then
      v_branch_id := coalesce(
        nullif(v_payload ->> 'branch_id', '')::uuid,
        v_mutation.branch_id
      );

      v_supplier_id := nullif(v_payload ->> 'supplier_id', '')::uuid;

      insert into public.purchases (
        id,
        business_id,
        branch_id,
        supplier_id,
        user_id,
        total,
        status,
        invoice_photo_url,
        processing_status,
        supplier_name,
        idempotency_key,
        sync_status,
        created_by,
        updated_by,
        metadata
      )
      values (
        v_entity_id,
        v_mutation.business_id,
        v_branch_id,
        v_supplier_id,
        coalesce(nullif(v_payload ->> 'user_id', '')::uuid, v_mutation.profile_id),
        coalesce(nullif(v_payload ->> 'total', '')::numeric, 0),
        coalesce(nullif(v_payload ->> 'status', ''), 'completed'),
        nullif(v_payload ->> 'invoice_photo_url', ''),
        coalesce(nullif(v_payload ->> 'processing_status', ''), 'completed'),
        nullif(v_payload ->> 'supplier_name', ''),
        coalesce(nullif(v_mutation.idempotency_key, ''), nullif(v_payload ->> 'idempotency_key', '')),
        'synced',
        v_mutation.profile_id,
        v_mutation.profile_id,
        v_metadata
      )
      returning version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    if v_operation in ('update', 'upsert') then
      update public.purchases p
      set
        branch_id = coalesce(nullif(v_payload ->> 'branch_id', '')::uuid, p.branch_id),
        supplier_id = coalesce(nullif(v_payload ->> 'supplier_id', '')::uuid, p.supplier_id),
        user_id = coalesce(nullif(v_payload ->> 'user_id', '')::uuid, p.user_id),
        total = coalesce(nullif(v_payload ->> 'total', '')::numeric, p.total),
        status = coalesce(nullif(v_payload ->> 'status', ''), p.status),
        invoice_photo_url = coalesce(nullif(v_payload ->> 'invoice_photo_url', ''), p.invoice_photo_url),
        processing_status = coalesce(nullif(v_payload ->> 'processing_status', ''), p.processing_status),
        supplier_name = coalesce(nullif(v_payload ->> 'supplier_name', ''), p.supplier_name),
        idempotency_key = coalesce(nullif(v_mutation.idempotency_key, ''), nullif(v_payload ->> 'idempotency_key', ''), p.idempotency_key),
        sync_status = 'synced',
        updated_by = v_mutation.profile_id,
        metadata = coalesce(p.metadata, '{}'::jsonb) || v_metadata
      where p.id = v_entity_id
      returning p.version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    if v_operation = 'soft_delete' then
      update public.purchases p
      set
        deleted_at = coalesce(p.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(nullif(v_payload ->> 'delete_reason', ''), 'offline sync soft_delete'),
        sync_status = 'synced',
        updated_by = v_mutation.profile_id,
        metadata = coalesce(p.metadata, '{}'::jsonb) || v_metadata
      where p.id = v_entity_id
      returning p.version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    perform private.mark_sync_mutation_skipped(
      v_mutation.id,
      'Unsupported purchases operation: ' || v_operation
    );
    return;
  end if;

  -- =======================================================
  -- purchase_items
  -- =======================================================

  if v_entity = 'purchase_items' then
    select *
    into v_current_item
    from public.purchase_items pi
    where pi.id = v_entity_id
    for update;

    if v_operation = 'insert' and v_current_item.id is not null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'duplicate_key',
        'Purchase item already exists on server',
        to_jsonb(v_current_item),
        'server_wins',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_operation in ('update', 'soft_delete') and v_current_item.id is null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'missing_server_row',
        'Purchase item does not exist on server',
        null,
        'client_retry',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_current_item.id is not null
       and v_current_item.deleted_at is not null
       and v_operation <> 'upsert' then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'deleted_on_server',
        'Purchase item is already deleted on server',
        to_jsonb(v_current_item),
        'server_wins',
        jsonb_build_object('entity_table', v_entity)
      );
      return;
    end if;

    if v_current_item.id is not null
       and v_mutation.base_version is not null
       and coalesce(v_current_item.version, 1) > v_mutation.base_version then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'version_mismatch',
        'Purchase item version on server is newer than client base_version',
        to_jsonb(v_current_item),
        'manual_review',
        jsonb_build_object(
          'entity_table', v_entity,
          'server_version', v_current_item.version,
          'client_base_version', v_mutation.base_version
        )
      );
      return;
    end if;

    v_purchase_id := coalesce(
      nullif(v_payload ->> 'purchase_id', '')::uuid,
      case when v_current_item.id is not null then v_current_item.purchase_id else null end
    );

    if v_purchase_id is null then
      perform private.mark_sync_mutation_error(
        v_mutation.id,
        'validation_error',
        'purchase_id is required for purchase_items'
      );
      return;
    end if;

    select p.id, p.business_id, p.branch_id, p.deleted_at
    into v_parent_purchase
    from public.purchases p
    where p.id = v_purchase_id;

    if v_parent_purchase.id is null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'missing_server_row',
        'Parent purchase does not exist on server',
        null,
        'client_retry',
        jsonb_build_object('entity_table', v_entity, 'purchase_id', v_purchase_id)
      );
      return;
    end if;

    if v_parent_purchase.deleted_at is not null then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'deleted_on_server',
        'Parent purchase is deleted on server',
        to_jsonb(v_parent_purchase),
        'server_wins',
        jsonb_build_object('entity_table', v_entity, 'purchase_id', v_purchase_id)
      );
      return;
    end if;

    if v_parent_purchase.business_id <> v_mutation.business_id then
      perform private.mark_sync_mutation_error(
        v_mutation.id,
        'validation_error',
        'Parent purchase belongs to a different business'
      );
      return;
    end if;

    v_product_id := coalesce(
      nullif(v_payload ->> 'product_id', '')::uuid,
      case when v_current_item.id is not null then v_current_item.product_id else null end
    );

    if v_product_id is null then
      perform private.mark_sync_mutation_error(
        v_mutation.id,
        'validation_error',
        'product_id is required for purchase_items'
      );
      return;
    end if;

    if not exists (
      select 1
      from public.products p
      where p.id = v_product_id
        and p.business_id = v_mutation.business_id
        and p.deleted_at is null
    ) then
      perform private.create_sync_conflict_for_mutation(
        v_mutation.id,
        'validation_error',
        'Product does not exist or belongs to another business',
        null,
        'client_retry',
        jsonb_build_object('entity_table', v_entity, 'product_id', v_product_id)
      );
      return;
    end if;

    v_quantity := coalesce(
      nullif(v_payload ->> 'quantity', '')::integer,
      case when v_current_item.id is not null then v_current_item.quantity else 1 end
    );

    v_unit_cost := coalesce(
      nullif(v_payload ->> 'unit_cost', '')::numeric,
      case when v_current_item.id is not null then v_current_item.unit_cost else 0 end
    );

    v_subtotal := coalesce(
      nullif(v_payload ->> 'subtotal', '')::numeric,
      v_quantity * v_unit_cost
    );

    if v_operation in ('insert', 'upsert') and v_current_item.id is null then
      insert into public.purchase_items (
        id,
        business_id,
        branch_id,
        purchase_id,
        product_id,
        quantity,
        unit_cost,
        subtotal,
        idempotency_key,
        sync_status,
        created_by,
        updated_by,
        metadata
      )
      values (
        v_entity_id,
        v_mutation.business_id,
        v_parent_purchase.branch_id,
        v_purchase_id,
        v_product_id,
        v_quantity,
        v_unit_cost,
        v_subtotal,
        coalesce(nullif(v_mutation.idempotency_key, ''), nullif(v_payload ->> 'idempotency_key', '')),
        'synced',
        v_mutation.profile_id,
        v_mutation.profile_id,
        v_metadata
      )
      returning version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    if v_operation in ('update', 'upsert') then
      update public.purchase_items pi
      set
        business_id = v_mutation.business_id,
        branch_id = v_parent_purchase.branch_id,
        purchase_id = v_purchase_id,
        product_id = v_product_id,
        quantity = v_quantity,
        unit_cost = v_unit_cost,
        subtotal = v_subtotal,
        idempotency_key = coalesce(nullif(v_mutation.idempotency_key, ''), nullif(v_payload ->> 'idempotency_key', ''), pi.idempotency_key),
        sync_status = 'synced',
        updated_by = v_mutation.profile_id,
        metadata = coalesce(pi.metadata, '{}'::jsonb) || v_metadata
      where pi.id = v_entity_id
      returning pi.version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    if v_operation = 'soft_delete' then
      update public.purchase_items pi
      set
        deleted_at = coalesce(pi.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(nullif(v_payload ->> 'delete_reason', ''), 'offline sync soft_delete'),
        sync_status = 'synced',
        updated_by = v_mutation.profile_id,
        metadata = coalesce(pi.metadata, '{}'::jsonb) || v_metadata
      where pi.id = v_entity_id
      returning pi.version into v_new_version;

      perform private.mark_sync_mutation_applied(v_mutation.id, v_new_version);
      return;
    end if;

    perform private.mark_sync_mutation_skipped(
      v_mutation.id,
      'Unsupported purchase_items operation: ' || v_operation
    );
    return;
  end if;

  perform private.mark_sync_mutation_skipped(
    v_mutation.id,
    'Entity is not handled by apply_sync_purchase_mutation: ' || v_entity
  );
end;
$$;

comment on function private.apply_sync_purchase_mutation(uuid)
is 'Applies one purchases or purchase_items sync mutation. Does not apply inventory movements.';

revoke all on function private.apply_sync_purchase_mutation(uuid) from public;
grant execute on function private.apply_sync_purchase_mutation(uuid) to authenticated, service_role;

-- =========================================================
-- 8. PATCH process_sync_batch: nuevo modo apply_purchases
-- =========================================================

create or replace function public.process_sync_batch(
  p_sync_batch_id uuid,
  p_mode text default 'validate_only'
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_batch record;
  v_mutation record;

  v_mode text := lower(trim(coalesce(p_mode, 'validate_only')));
  v_processed_count integer := 0;

  v_started_at timestamp without time zone := now();
  v_completed_at timestamp without time zone;

  v_entity text;
  v_operation text;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  if v_mode not in ('validate_only', 'apply_catalog', 'apply_pos', 'apply_purchases') then
    raise exception 'Unsupported sync processing mode: %', v_mode;
  end if;

  select
    sb.id,
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.direction,
    sb.status,
    sb.deleted_at
  into v_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id
  for update;

  if v_batch.id is null then
    raise exception 'Sync batch not found';
  end if;

  if v_batch.deleted_at is not null then
    raise exception 'Cannot process deleted sync batch';
  end if;

  if v_batch.direction <> 'upload' then
    raise exception 'Only upload sync batches can be processed';
  end if;

  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'settings.business')
       or private.has_business_permission(v_batch.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to process this sync batch';
  end if;

  perform private.mark_sync_batch_processing(p_sync_batch_id);

  for v_mutation in
    select
      sm.id,
      sm.business_id,
      sm.branch_id,
      sm.entity_table,
      sm.entity_id,
      sm.operation,
      sm.status,
      sm.deleted_at
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and sm.status in ('pending', 'error', 'conflict', 'skipped')
    order by sm.client_sequence asc nulls last, sm.created_at asc
  loop
    v_processed_count := v_processed_count + 1;
    v_entity := lower(trim(v_mutation.entity_table));
    v_operation := lower(trim(v_mutation.operation));

    begin
      if v_operation = 'delete' then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'business_rule_violation',
          'Hard delete is not allowed through sync. Use soft_delete.',
          null,
          'client_retry',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if v_entity = 'inventory_movements'
         and v_operation in ('update', 'soft_delete', 'delete') then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'business_rule_violation',
          'inventory_movements is an append-only ledger and cannot be updated or deleted',
          null,
          'server_wins',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if not private.has_sync_entity_permission(
        v_batch.business_id,
        v_batch.branch_id,
        v_entity,
        v_operation
      ) then
        perform private.create_sync_conflict_for_mutation(
          v_mutation.id,
          'permission_denied',
          'Current user does not have permission to apply this mutation',
          null,
          'client_retry',
          jsonb_build_object('entity_table', v_entity, 'operation', v_operation)
        );
        continue;
      end if;

      if v_mode = 'validate_only' then
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'validate_only mode'
        );

      elsif v_mode = 'apply_catalog'
            and v_entity in ('categories', 'products', 'customers', 'suppliers') then
        perform private.apply_sync_catalog_mutation(v_mutation.id);

      elsif v_mode = 'apply_pos'
            and v_entity in ('sales', 'sale_items') then
        perform private.apply_sync_pos_mutation(v_mutation.id);

      elsif v_mode = 'apply_pos'
            and v_entity = 'sale_payments' then
        perform private.apply_sync_sale_payment_mutation(v_mutation.id);

      elsif v_mode = 'apply_purchases'
            and v_entity in ('purchases', 'purchase_items') then
        perform private.apply_sync_purchase_mutation(v_mutation.id);

      else
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'Entity is not supported by mode ' || v_mode
        );
      end if;

    exception when others then
      perform private.mark_sync_mutation_error(
        v_mutation.id,
        'unexpected_error',
        sqlerrm
      );
    end;
  end loop;

  perform private.recalculate_sync_batch_counts(p_sync_batch_id);
  perform private.finalize_sync_batch_from_counts(p_sync_batch_id);

  v_completed_at := now();

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'mode', v_mode,
    'status', (
      select sb.status
      from public.sync_batches sb
      where sb.id = p_sync_batch_id
    ),
    'mutation_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
    ),
    'processed_count', v_processed_count,
    'applied_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
    ),
    'skipped_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'skipped'
    ),
    'conflict_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'conflict'
    ),
    'error_count', (
      select count(*)
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'error'
    ),
    'server_started_at', v_started_at,
    'server_completed_at', v_completed_at,
    'note', case
      when v_mode = 'apply_purchases' then 'Purchases and purchase_items mutations were applied when supported. Inventory is applied separately.'
      when v_mode = 'apply_pos' then 'POS sales, sale_items and sale_payments mutations were applied when supported. Other entities were skipped.'
      when v_mode = 'apply_catalog' then 'Catalog mutations were applied when supported. Other entities were skipped.'
      else 'Mutations were validated and skipped without applying changes.'
    end
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Processes a sync batch. Modes: validate_only, apply_catalog, apply_pos, apply_purchases.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;

commit;