-- Fase 6.12A - Apply POS sales and sale_items
-- Objetivo:
-- Permitir que process_sync_batch() aplique mutaciones reales para:
-- - sales
-- - sale_items
--
-- No aplica todavía:
-- - sale_payments
-- - inventory_movements
-- - cierre automático de venta
--
-- El inventario se seguirá moviendo solo por funciones explícitas:
-- public.apply_sale_inventory_movements()
-- public.create_inventory_movement()

begin;

-- =========================================================
-- ASEGURAR METADATA EN POS
-- =========================================================

alter table public.sales
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.sale_items
add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.sales.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

comment on column public.sale_items.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

-- =========================================================
-- HELPER: APPLY POS SALE / SALE_ITEM MUTATION
-- =========================================================

create or replace function private.apply_sync_pos_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_payload jsonb;
  v_server_payload jsonb;
  v_result_payload jsonb;

  v_entity text;
  v_operation text;

  v_exists boolean := false;
  v_deleted boolean := false;

  v_server_version integer;
  v_new_version integer;

  v_conflict_id uuid;

  v_branch_id uuid;
  v_customer_id uuid;

  v_sale_id uuid;
  v_product_id uuid;

  v_quantity integer;
  v_unit_price numeric;
  v_discount_amount numeric;
  v_tax_amount numeric;
  v_subtotal numeric;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

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
    sm.base_updated_at,
    sm.status,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
  for update;

  if v_mutation.id is null then
    raise exception 'Sync mutation not found';
  end if;

  if v_mutation.deleted_at is not null then
    raise exception 'Cannot apply deleted sync mutation';
  end if;

  v_entity := lower(trim(v_mutation.entity_table));
  v_operation := lower(trim(v_mutation.operation));
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  if v_entity not in ('sales', 'sale_items') then
    perform private.mark_sync_mutation_skipped(
      v_mutation.id,
      'Entity is not part of POS sales/items apply phase.'
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'unsupported_entity_for_pos_phase',
      'entity_table', v_entity
    );
  end if;

  if v_operation = 'delete' then
    v_server_payload := private.get_current_server_payload(
      v_entity,
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'business_rule_violation',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Hard delete is not allowed. Use soft_delete instead.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'rule', 'no_hard_delete'
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'hard_delete_not_allowed'
    );
  end if;

  if v_operation not in ('insert', 'update', 'upsert', 'soft_delete') then
    perform private.mark_sync_mutation_error(
      v_mutation.id,
      'unsupported_operation',
      'Unsupported POS sync operation: ' || v_operation
    );

    return jsonb_build_object(
      'status', 'error',
      'reason', 'unsupported_operation'
    );
  end if;

  -- Defensa en profundidad: validar permiso otra vez dentro del helper.
  if not private.has_sync_entity_permission(
    v_mutation.business_id,
    v_mutation.branch_id,
    v_entity,
    v_operation
  ) then
    v_server_payload := private.get_current_server_payload(
      v_entity,
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'permission_denied',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Current user does not have permission to apply this POS mutation.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'entity_table', v_entity,
        'operation', v_operation
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'permission_denied'
    );
  end if;

  v_server_payload := private.get_current_server_payload(
    v_entity,
    v_mutation.entity_id
  );

  v_exists := v_server_payload is not null;
  v_deleted := v_exists
    and v_server_payload ? 'deleted_at'
    and nullif(v_server_payload ->> 'deleted_at', '') is not null;

  if v_exists
     and v_server_payload ? 'version'
     and (v_server_payload ->> 'version') ~ '^[0-9]+$' then
    v_server_version := (v_server_payload ->> 'version')::integer;
  else
    v_server_version := null;
  end if;

  -- INSERT con ID ya existente debe ser conflicto.
  if v_operation = 'insert' and v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'duplicate_key',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Cannot insert POS row because entity_id already exists on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'duplicate_key'
    );
  end if;

  -- UPDATE / SOFT_DELETE requieren fila existente.
  if v_operation in ('update', 'soft_delete') and not v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'missing_server_row',
      p_severity := 'medium',
      p_server_payload := null,
      p_error_message := 'Cannot update or soft_delete POS row because it does not exist on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'missing_server_row'
    );
  end if;

  if v_operation in ('update', 'soft_delete') and v_deleted then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'deleted_on_server',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Cannot update POS row because it is already deleted on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'entity_table', v_entity
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'deleted_on_server'
    );
  end if;

  -- Control optimista por version.
  if v_operation in ('update', 'upsert', 'soft_delete')
     and v_exists
     and not v_deleted
     and v_mutation.base_version is not null
     and v_server_version is not null
     and v_server_version > v_mutation.base_version then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'version_mismatch',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Server POS row version is newer than client base_version.',
      p_metadata := jsonb_build_object(
        'phase', '6.12A',
        'entity_table', v_entity,
        'server_version', v_server_version,
        'client_base_version', v_mutation.base_version
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'version_mismatch'
    );
  end if;

  -- =========================================================
  -- SALES
  -- =========================================================

  if v_entity = 'sales' then
    if v_payload ? 'branch_id'
       and nullif(v_payload ->> 'branch_id', '') is not null then
      v_branch_id := (v_payload ->> 'branch_id')::uuid;
    else
      v_branch_id := v_mutation.branch_id;
    end if;

    if v_branch_id is null then
      raise exception 'sales.branch_id is required';
    end if;

    if not exists (
      select 1
      from public.branches br
      where br.id = v_branch_id
        and br.business_id = v_mutation.business_id
        and br.deleted_at is null
        and br.status = 'active'
    ) then
      raise exception 'sales.branch_id must belong to the same active business';
    end if;

    if v_payload ? 'customer_id'
       and nullif(v_payload ->> 'customer_id', '') is not null then
      v_customer_id := (v_payload ->> 'customer_id')::uuid;

      if not exists (
        select 1
        from public.customers c
        where c.id = v_customer_id
          and c.business_id = v_mutation.business_id
          and c.deleted_at is null
      ) then
        raise exception 'sales.customer_id must belong to the same business';
      end if;
    else
      v_customer_id := null;
    end if;

    if v_operation in ('insert', 'upsert') and not v_exists then
      insert into public.sales (
        id,
        business_id,
        branch_id,
        user_id,
        customer_id,
        total,
        payment_method,
        status,

        subtotal,
        discount_total,
        tax_total,
        paid_total,
        change_amount,
        currency,

        receipt_number,
        idempotency_key,

        created_by,
        updated_by,
        sync_status,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_branch_id,
        v_mutation.profile_id,
        v_customer_id,

        coalesce((nullif(v_payload ->> 'total', ''))::numeric, 0),
        nullif(v_payload ->> 'payment_method', ''),
        coalesce(nullif(v_payload ->> 'status', ''), 'completed'),

        coalesce((nullif(v_payload ->> 'subtotal', ''))::numeric, 0),
        coalesce((nullif(v_payload ->> 'discount_total', ''))::numeric, 0),
        coalesce((nullif(v_payload ->> 'tax_total', ''))::numeric, 0),
        coalesce((nullif(v_payload ->> 'paid_total', ''))::numeric, 0),
        coalesce((nullif(v_payload ->> 'change_amount', ''))::numeric, 0),
        coalesce(nullif(v_payload ->> 'currency', ''), 'COP'),

        nullif(v_payload ->> 'receipt_number', ''),
        coalesce(
          nullif(v_payload ->> 'idempotency_key', ''),
          v_mutation.idempotency_key
        ),

        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id,
          'phase', '6.12A'
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.sales s
      set
        customer_id = case
          when v_payload ? 'customer_id' then v_customer_id
          else s.customer_id
        end,
        payment_method = case
          when v_payload ? 'payment_method' then nullif(v_payload ->> 'payment_method', '')
          else s.payment_method
        end,
        status = case
          when v_payload ? 'status' then coalesce(nullif(v_payload ->> 'status', ''), s.status)
          else s.status
        end,
        subtotal = case
          when v_payload ? 'subtotal' then coalesce((nullif(v_payload ->> 'subtotal', ''))::numeric, 0)
          else s.subtotal
        end,
        discount_total = case
          when v_payload ? 'discount_total' then coalesce((nullif(v_payload ->> 'discount_total', ''))::numeric, 0)
          else s.discount_total
        end,
        tax_total = case
          when v_payload ? 'tax_total' then coalesce((nullif(v_payload ->> 'tax_total', ''))::numeric, 0)
          else s.tax_total
        end,
        paid_total = case
          when v_payload ? 'paid_total' then coalesce((nullif(v_payload ->> 'paid_total', ''))::numeric, 0)
          else s.paid_total
        end,
        change_amount = case
          when v_payload ? 'change_amount' then coalesce((nullif(v_payload ->> 'change_amount', ''))::numeric, 0)
          else s.change_amount
        end,
        currency = case
          when v_payload ? 'currency' then coalesce(nullif(v_payload ->> 'currency', ''), s.currency)
          else s.currency
        end,
        receipt_number = case
          when v_payload ? 'receipt_number' then nullif(v_payload ->> 'receipt_number', '')
          else s.receipt_number
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where s.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.sales s
      set
        deleted_at = coalesce(s.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where s.id = v_mutation.entity_id;
    end if;
  end if;

  -- =========================================================
  -- SALE ITEMS
  -- =========================================================

  if v_entity = 'sale_items' then
    if v_payload ? 'sale_id'
       and nullif(v_payload ->> 'sale_id', '') is not null then
      v_sale_id := (v_payload ->> 'sale_id')::uuid;
    else
      raise exception 'sale_items.sale_id is required';
    end if;

    if not exists (
      select 1
      from public.sales s
      where s.id = v_sale_id
        and s.business_id = v_mutation.business_id
        and s.deleted_at is null
    ) then
      raise exception 'sale_items.sale_id must belong to the same business';
    end if;

    if v_payload ? 'product_id'
       and nullif(v_payload ->> 'product_id', '') is not null then
      v_product_id := (v_payload ->> 'product_id')::uuid;
    else
      raise exception 'sale_items.product_id is required';
    end if;

    if not exists (
      select 1
      from public.products p
      where p.id = v_product_id
        and p.business_id = v_mutation.business_id
        and p.deleted_at is null
    ) then
      raise exception 'sale_items.product_id must belong to the same business';
    end if;

    v_quantity := coalesce((nullif(v_payload ->> 'quantity', ''))::integer, 1);
    v_unit_price := coalesce((nullif(v_payload ->> 'unit_price', ''))::numeric, 0);
    v_discount_amount := coalesce((nullif(v_payload ->> 'discount_amount', ''))::numeric, 0);
    v_tax_amount := coalesce((nullif(v_payload ->> 'tax_amount', ''))::numeric, 0);
    v_subtotal := coalesce(
      (nullif(v_payload ->> 'subtotal', ''))::numeric,
      v_quantity * v_unit_price
    );

    if v_quantity <= 0 then
      raise exception 'sale_items.quantity must be positive';
    end if;

    if v_unit_price < 0 then
      raise exception 'sale_items.unit_price must be non-negative';
    end if;

    if v_operation in ('insert', 'upsert') and not v_exists then
      insert into public.sale_items (
        id,
        business_id,
        sale_id,
        product_id,
        quantity,
        unit_price,
        subtotal,

        discount_amount,
        tax_amount,

        created_by,
        updated_by,
        sync_status,
        idempotency_key,
        metadata
      )
      values (
        v_mutation.entity_id,
        v_mutation.business_id,
        v_sale_id,
        v_product_id,
        v_quantity,
        v_unit_price,
        v_subtotal,

        v_discount_amount,
        v_tax_amount,

        v_mutation.profile_id,
        v_mutation.profile_id,
        'synced',
        coalesce(
          nullif(v_payload ->> 'idempotency_key', ''),
          v_mutation.idempotency_key
        ),
        jsonb_build_object(
          'created_by_sync', true,
          'sync_mutation_id', v_mutation.id,
          'phase', '6.12A'
        )
      );
    elsif v_operation in ('update', 'upsert') and v_exists then
      update public.sale_items si
      set
        quantity = case
          when v_payload ? 'quantity' then v_quantity
          else si.quantity
        end,
        unit_price = case
          when v_payload ? 'unit_price' then v_unit_price
          else si.unit_price
        end,
        subtotal = case
          when v_payload ? 'subtotal'
            or v_payload ? 'quantity'
            or v_payload ? 'unit_price'
          then v_subtotal
          else si.subtotal
        end,
        discount_amount = case
          when v_payload ? 'discount_amount' then v_discount_amount
          else si.discount_amount
        end,
        tax_amount = case
          when v_payload ? 'tax_amount' then v_tax_amount
          else si.tax_amount
        end,
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where si.id = v_mutation.entity_id;
    elsif v_operation = 'soft_delete' then
      update public.sale_items si
      set
        deleted_at = coalesce(si.deleted_at, now()),
        deleted_by = v_mutation.profile_id,
        delete_reason = coalesce(
          nullif(v_payload ->> 'delete_reason', ''),
          'Deleted from offline sync'
        ),
        updated_by = v_mutation.profile_id,
        sync_status = 'synced'
      where si.id = v_mutation.entity_id;
    end if;
  end if;

  v_result_payload := private.get_current_server_payload(
    v_entity,
    v_mutation.entity_id
  );

  if v_result_payload is not null
     and v_result_payload ? 'version'
     and (v_result_payload ->> 'version') ~ '^[0-9]+$' then
    v_new_version := (v_result_payload ->> 'version')::integer;
  else
    v_new_version := null;
  end if;

  perform private.mark_sync_mutation_applied(
    v_mutation.id,
    v_new_version
  );

  return jsonb_build_object(
    'status', 'applied',
    'entity_table', v_entity,
    'entity_id', v_mutation.entity_id,
    'operation', v_operation,
    'server_entity_version', v_new_version
  );
end;
$$;

comment on function private.apply_sync_pos_mutation(uuid)
is 'Applies insert/update/upsert/soft_delete sync mutations for POS entities: sales and sale_items.';

revoke all on function private.apply_sync_pos_mutation(uuid) from public;
grant execute on function private.apply_sync_pos_mutation(uuid) to authenticated, service_role;

-- =========================================================
-- UPDATE PUBLIC PROCESS SYNC BATCH
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
  v_final_batch record;
  v_mutation record;

  v_mode text;

  v_processed_count integer := 0;
  v_permission_ok boolean;
  v_server_payload jsonb;
  v_conflict_id uuid;
  v_apply_result jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  v_mode := lower(trim(coalesce(p_mode, 'validate_only')));

  if v_mode not in ('validate_only', 'apply_catalog', 'apply_pos') then
    raise exception 'Unsupported process_sync_batch mode: %. Supported modes: validate_only, apply_catalog, apply_pos.', p_mode;
  end if;

  select
    sb.id,
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.client_batch_id,
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

  if v_batch.status in ('completed', 'partial', 'failed', 'cancelled') then
    return jsonb_build_object(
      'sync_batch_id', v_batch.id,
      'status', v_batch.status,
      'message', 'Batch already finalized',
      'processed_count', 0
    );
  end if;

  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'settings.business')
       or private.has_business_permission(v_batch.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to process this sync batch';
  end if;

  if not exists (
    select 1
    from public.app_devices ad
    where ad.id = v_batch.app_device_id
      and ad.business_id = v_batch.business_id
      and ad.profile_id = v_batch.profile_id
      and ad.status = 'active'
      and ad.deleted_at is null
  ) then
    raise exception 'Cannot process sync batch for inactive, blocked or deleted app_device';
  end if;

  perform private.mark_sync_batch_processing(p_sync_batch_id);

  for v_mutation in
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
      sm.base_updated_at,
      sm.status,
      sm.idempotency_key
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and sm.status in ('pending', 'processing')
    order by sm.client_sequence asc, sm.created_at asc
    for update
  loop
    begin
      v_processed_count := v_processed_count + 1;

      update public.sync_mutations sm
      set
        status = 'processing',
        updated_at = now(),
        updated_by = coalesce(v_profile_id, sm.updated_by)
      where sm.id = v_mutation.id;

      if v_mutation.business_id <> v_batch.business_id
         or v_mutation.app_device_id <> v_batch.app_device_id
         or v_mutation.profile_id <> v_batch.profile_id then
        perform private.mark_sync_mutation_error(
          v_mutation.id,
          'batch_mismatch',
          'Mutation does not match parent batch business/device/profile'
        );

        continue;
      end if;

      if v_mutation.operation = 'delete' then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'business_rule_violation',
          p_severity := 'high',
          p_server_payload := v_server_payload,
          p_error_message := 'Hard delete is not allowed. Use soft_delete instead.',
          p_metadata := jsonb_build_object(
            'phase', '6.12A',
            'mode', v_mode,
            'rule', 'no_hard_delete'
          )
        );

        continue;
      end if;

      if lower(v_mutation.entity_table) = 'inventory_movements'
         and v_mutation.operation in ('update', 'soft_delete', 'delete') then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'business_rule_violation',
          p_severity := 'critical',
          p_server_payload := v_server_payload,
          p_error_message := 'inventory_movements is immutable. Updates or deletes are not allowed.',
          p_metadata := jsonb_build_object(
            'phase', '6.12A',
            'mode', v_mode,
            'rule', 'inventory_movements_append_only'
          )
        );

        continue;
      end if;

      v_permission_ok := private.has_sync_entity_permission(
        v_mutation.business_id,
        v_mutation.branch_id,
        v_mutation.entity_table,
        v_mutation.operation
      );

      if not v_permission_ok then
        v_server_payload := private.get_current_server_payload(
          v_mutation.entity_table,
          v_mutation.entity_id
        );

        v_conflict_id := private.create_sync_conflict_for_mutation(
          p_sync_mutation_id := v_mutation.id,
          p_conflict_type := 'permission_denied',
          p_severity := 'high',
          p_server_payload := v_server_payload,
          p_error_message := 'Current user does not have permission to sync this entity/operation.',
          p_metadata := jsonb_build_object(
            'phase', '6.12A',
            'mode', v_mode,
            'entity_table', v_mutation.entity_table,
            'operation', v_mutation.operation
          )
        );

        continue;
      end if;

      if v_mode = 'validate_only' then
        perform private.mark_sync_mutation_skipped(
          v_mutation.id,
          'Validated by process_sync_batch validate_only mode. No business data was changed.'
        );

        continue;
      end if;

      if v_mode = 'apply_catalog' then
        if lower(v_mutation.entity_table) in (
          'categories',
          'products',
          'customers',
          'suppliers'
        ) then
          v_apply_result := private.apply_sync_catalog_mutation(v_mutation.id);
          continue;
        else
          perform private.mark_sync_mutation_skipped(
            v_mutation.id,
            'Entity is not supported by apply_catalog mode yet.'
          );
          continue;
        end if;
      end if;

      if v_mode = 'apply_pos' then
        if lower(v_mutation.entity_table) in (
          'sales',
          'sale_items'
        ) then
          v_apply_result := private.apply_sync_pos_mutation(v_mutation.id);
          continue;
        else
          perform private.mark_sync_mutation_skipped(
            v_mutation.id,
            'Entity is not supported by apply_pos mode yet.'
          );
          continue;
        end if;
      end if;

    exception
      when others then
        perform private.mark_sync_mutation_error(
          v_mutation.id,
          'exception',
          sqlerrm
        );
    end;
  end loop;

  perform private.finalize_sync_batch_from_counts(p_sync_batch_id);

  select
    sb.id,
    sb.status,
    sb.mutation_count,
    sb.applied_count,
    sb.skipped_count,
    sb.conflict_count,
    sb.error_count,
    sb.server_started_at,
    sb.server_completed_at
  into v_final_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id;

  return jsonb_build_object(
    'sync_batch_id', v_final_batch.id,
    'mode', v_mode,
    'status', v_final_batch.status,
    'processed_count', v_processed_count,
    'mutation_count', v_final_batch.mutation_count,
    'applied_count', v_final_batch.applied_count,
    'skipped_count', v_final_batch.skipped_count,
    'conflict_count', v_final_batch.conflict_count,
    'error_count', v_final_batch.error_count,
    'server_started_at', v_final_batch.server_started_at,
    'server_completed_at', v_final_batch.server_completed_at,
    'note', case
      when v_mode = 'apply_catalog'
        then 'Catalog mutations were applied when supported. Other entities were skipped.'
      when v_mode = 'apply_pos'
        then 'POS sales and sale_items mutations were applied when supported. Other entities were skipped.'
      else 'Validation only. No business data was changed.'
    end
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Processes a sync batch. Supports validate_only, apply_catalog and apply_pos modes. apply_pos currently supports sales and sale_items.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;

commit;