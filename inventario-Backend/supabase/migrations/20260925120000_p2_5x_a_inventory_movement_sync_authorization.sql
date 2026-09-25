-- P2.5X-A: authorize inventory sync by the movement's canonical source.
-- The entity-level permission check remains a preliminary filter only.
begin;

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
    when v_operation = 'update' then 'update'
    when v_operation in ('soft_delete', 'delete') then 'soft_delete'
    else null
  end;

  if v_entity = '' or v_action is null or v_operation = 'delete' then
    return array[]::text[];
  end if;

  if v_entity = 'products' then
    return case v_operation
      when 'insert' then array['products.create']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'product_barcodes' then
    return case v_operation
      when 'insert' then array['products.create', 'products.update']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'categories' then
    return array[
      'categories.' || v_action,
      'products.' || v_action,
      'inventory.' || case when v_action = 'create' then 'adjust' else 'read' end
    ];
  end if;

  if v_entity = 'customers' then
    return array[
      'customers.' || v_action,
      'sales.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity = 'suppliers' then
    return array[
      'suppliers.' || v_action,
      'purchases.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity in ('purchases', 'purchase_items') then
    return array['inventory.purchase'];
  end if;

  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array['sales.' || v_action];
  end if;

  if v_entity in ('cash_sessions', 'cash_registers') then
    return array[
      'sales.' || case
        when v_action = 'create' then 'create'
        when v_action = 'update' then 'update'
        else 'soft_delete'
      end
    ];
  end if;

  if v_entity = 'inventory_movements' then
    if v_operation = 'insert' then
      return array[
        'sales.create',
        'inventory.purchase',
        'inventory.adjust',
        'sales.refund',
        'inventory.count',
        'inventory.transfer'
      ];
    end if;
    return array[]::text[];
  end if;

  if v_entity in ('stock_counts', 'stock_count_items') then
    return array['inventory.count'];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array['inventory.transfer'];
  end if;

  return array[]::text[];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text) is
'Returns preliminary entity permissions. Inventory movement insertion also requires source-specific authorization in its sync applier.';

-- Keep this matrix aligned with public.create_inventory_movement. Only the
-- authenticated caller's effective branch permissions are authoritative.
create function private.has_inventory_movement_source_permission(
  p_business_id uuid,
  p_branch_id uuid,
  p_source_type text
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source_type text := lower(btrim(coalesce(p_source_type, '')));
begin
  if auth.uid() is null or p_business_id is null or p_branch_id is null then
    return false;
  end if;

  return case
    when v_source_type = 'sale' then
      private.has_branch_permission(p_business_id, p_branch_id, 'sales.create')
    when v_source_type = 'purchase' then
      private.has_branch_permission(p_business_id, p_branch_id, 'inventory.purchase')
    when v_source_type in ('manual_adjustment', 'loss', 'reversal') then
      private.has_branch_permission(p_business_id, p_branch_id, 'inventory.adjust')
    when v_source_type = 'return' then
      private.has_branch_permission(p_business_id, p_branch_id, 'sales.refund')
      or private.has_branch_permission(p_business_id, p_branch_id, 'inventory.adjust')
    when v_source_type = 'stock_count' then
      private.has_branch_permission(p_business_id, p_branch_id, 'inventory.count')
    when v_source_type = 'transfer' then
      private.has_branch_permission(p_business_id, p_branch_id, 'inventory.transfer')
    else false
  end;
end;
$$;

-- Preserve the existing apply/idempotency implementation, and put a narrow
-- fail-closed authorization and semantic guard in front of every call to it.
alter function private.apply_sync_inventory_movement_mutation(uuid)
rename to apply_sync_inventory_movement_mutation_base_before_source_auth;

create function private.apply_sync_inventory_movement_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_mutation public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_source_type text;
  v_movement_type text;
  v_expected_movement_type text;
  v_quantity_change integer;
begin
  select * into v_mutation
  from public.sync_mutations
  where id = p_sync_mutation_id;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  select * into v_batch
  from public.sync_batches
  where id = v_mutation.sync_batch_id;

  if auth.uid() is null
     or v_batch.id is null
     or v_mutation.business_id is distinct from v_batch.business_id
     or v_mutation.branch_id is distinct from v_batch.branch_id
     or v_mutation.profile_id is distinct from v_batch.profile_id
     or v_mutation.app_device_id is distinct from v_batch.app_device_id
     or v_mutation.branch_id is null
     or lower(btrim(coalesce(v_mutation.entity_table, ''))) <> 'inventory_movements'
     or lower(btrim(coalesce(v_mutation.operation, ''))) <> 'insert'
     or (v_mutation.payload ? 'business_id'
         and v_mutation.payload ->> 'business_id' is distinct from v_mutation.business_id::text)
     or (v_mutation.payload ? 'branch_id'
         and v_mutation.payload ->> 'branch_id' is distinct from v_mutation.branch_id::text)
     or (v_mutation.payload ? 'profile_id'
         and v_mutation.payload ->> 'profile_id' is distinct from v_mutation.profile_id::text)
  then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id, 'permission_denied',
      'Inventory movement mutation has invalid scope or operation',
      null, 'client_retry', '{}'::jsonb
    );
    return jsonb_build_object('status', 'conflict', 'reason', 'invalid_scope');
  end if;

  v_source_type := lower(btrim(coalesce(v_mutation.payload ->> 'source_type', '')));
  v_movement_type := lower(btrim(coalesce(v_mutation.payload ->> 'movement_type', '')));
  v_expected_movement_type := case
    when v_source_type in ('sale', 'purchase', 'manual_adjustment', 'loss', 'return')
      then v_source_type
    when v_source_type in ('stock_count', 'transfer', 'reversal')
      then 'manual_adjustment'
    else null
  end;

  if v_expected_movement_type is null
     or v_movement_type is distinct from v_expected_movement_type
  then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id, 'validation_error',
      'Inventory movement source_type and movement_type are invalid or inconsistent',
      null, 'client_retry', '{}'::jsonb
    );
    return jsonb_build_object('status', 'conflict', 'reason', 'invalid_movement_type');
  end if;

  if private.has_inventory_movement_source_permission(
    v_mutation.business_id, v_mutation.branch_id, v_source_type
  ) is not true then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id, 'permission_denied',
      'Current user lacks permission for this inventory movement source',
      null, 'client_retry', '{}'::jsonb
    );
    return jsonb_build_object('status', 'conflict', 'reason', 'permission_denied');
  end if;

  -- Mirror the direct RPC's sign/cost constraints before the existing applier.
  v_quantity_change := nullif(v_mutation.payload ->> 'quantity_change', '')::integer;
  if (v_source_type in ('sale', 'loss') and v_quantity_change > 0)
     or (v_source_type in ('purchase', 'return') and v_quantity_change < 0)
     or nullif(v_mutation.payload ->> 'unit_cost', '')::numeric < 0
  then
    perform private.create_sync_conflict_for_mutation(
      p_sync_mutation_id, 'validation_error',
      'Inventory movement quantity sign or unit cost is invalid for its source',
      null, 'client_retry', '{}'::jsonb
    );
    return jsonb_build_object('status', 'conflict', 'reason', 'invalid_movement_values');
  end if;

  return private.apply_sync_inventory_movement_mutation_base_before_source_auth(
    p_sync_mutation_id
  );
end;
$$;

revoke all on function private.has_inventory_movement_source_permission(uuid, uuid, text)
from public, anon, authenticated;
grant execute on function private.has_inventory_movement_source_permission(uuid, uuid, text)
to service_role;

revoke all on function private.apply_sync_inventory_movement_mutation(uuid)
from public, anon, authenticated;
grant execute on function private.apply_sync_inventory_movement_mutation(uuid)
to service_role;

revoke all on function private.apply_sync_inventory_movement_mutation_base_before_source_auth(uuid)
from public, anon, authenticated;
grant execute on function private.apply_sync_inventory_movement_mutation_base_before_source_auth(uuid)
to service_role;

commit;
