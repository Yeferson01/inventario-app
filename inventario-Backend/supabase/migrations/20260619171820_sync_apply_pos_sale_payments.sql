-- Fase 6.12C - Apply POS sale_payments
-- Objetivo:
-- Permitir que process_sync_batch(..., 'apply_pos') aplique mutaciones reales para:
-- - sale_payments
--
-- Después de esta fase apply_pos soporta:
-- - sales
-- - sale_items
-- - sale_payments

begin;

-- =========================================================
-- ASEGURAR METADATA EN SALE_PAYMENTS
-- =========================================================

alter table public.sale_payments
add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.sale_payments.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

-- =========================================================
-- HELPER: APPLY SALE_PAYMENT MUTATION
-- =========================================================

create or replace function private.apply_sync_sale_payment_mutation(
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

  v_operation text;

  v_exists boolean := false;
  v_deleted boolean := false;

  v_server_version integer;
  v_new_version integer;

  v_conflict_id uuid;

  v_sale_id uuid;
  v_amount numeric;
  v_payment_method text;
  v_currency text;
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
    sm.idempotency_key,
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

  if lower(trim(v_mutation.entity_table)) <> 'sale_payments' then
    perform private.mark_sync_mutation_skipped(
      v_mutation.id,
      'Entity is not sale_payments.'
    );

    return jsonb_build_object(
      'status', 'skipped',
      'reason', 'unsupported_entity_for_sale_payment_phase',
      'entity_table', v_mutation.entity_table
    );
  end if;

  v_operation := lower(trim(v_mutation.operation));
  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  if v_operation = 'delete' then
    v_server_payload := private.get_current_server_payload(
      'sale_payments',
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'business_rule_violation',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Hard delete is not allowed. Use soft_delete instead.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
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
      'Unsupported sale_payments sync operation: ' || v_operation
    );

    return jsonb_build_object(
      'status', 'error',
      'reason', 'unsupported_operation'
    );
  end if;

  if not private.has_sync_entity_permission(
    v_mutation.business_id,
    v_mutation.branch_id,
    'sale_payments',
    v_operation
  ) then
    v_server_payload := private.get_current_server_payload(
      'sale_payments',
      v_mutation.entity_id
    );

    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'permission_denied',
      p_severity := 'high',
      p_server_payload := v_server_payload,
      p_error_message := 'Current user does not have permission to apply this sale_payments mutation.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
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
    'sale_payments',
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

  if v_operation = 'insert' and v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'duplicate_key',
      p_severity := 'medium',
      p_server_payload := v_server_payload,
      p_error_message := 'Cannot insert sale_payment because entity_id already exists on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
        'entity_table', 'sale_payments'
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'duplicate_key'
    );
  end if;

  if v_operation in ('update', 'soft_delete') and not v_exists then
    v_conflict_id := private.create_sync_conflict_for_mutation(
      p_sync_mutation_id := v_mutation.id,
      p_conflict_type := 'missing_server_row',
      p_severity := 'medium',
      p_server_payload := null,
      p_error_message := 'Cannot update or soft_delete sale_payment because it does not exist on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
        'entity_table', 'sale_payments'
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
      p_error_message := 'Cannot update sale_payment because it is already deleted on server.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
        'entity_table', 'sale_payments'
      )
    );

    return jsonb_build_object(
      'status', 'conflict',
      'conflict_id', v_conflict_id,
      'reason', 'deleted_on_server'
    );
  end if;

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
      p_error_message := 'Server sale_payment version is newer than client base_version.',
      p_metadata := jsonb_build_object(
        'phase', '6.12C',
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

  if v_payload ? 'sale_id'
     and nullif(v_payload ->> 'sale_id', '') is not null then
    v_sale_id := (v_payload ->> 'sale_id')::uuid;
  else
    raise exception 'sale_payments.sale_id is required';
  end if;

  if not exists (
    select 1
    from public.sales s
    where s.id = v_sale_id
      and s.business_id = v_mutation.business_id
      and s.deleted_at is null
  ) then
    raise exception 'sale_payments.sale_id must belong to the same business';
  end if;

  v_amount := coalesce((nullif(v_payload ->> 'amount', ''))::numeric, 0);
  v_payment_method := coalesce(nullif(v_payload ->> 'payment_method', ''), 'cash');
  v_currency := coalesce(nullif(v_payload ->> 'currency', ''), 'COP');

  if v_amount <= 0 and v_operation in ('insert', 'upsert') then
    raise exception 'sale_payments.amount must be positive';
  end if;

  if v_operation in ('insert', 'upsert') and not v_exists then
    insert into public.sale_payments (
      id,
      business_id,
      sale_id,
      payment_method,
      amount,
      currency,
      reference_number,
      status,
      paid_at,
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
      v_payment_method,
      v_amount,
      v_currency,
      nullif(v_payload ->> 'reference_number', ''),
      coalesce(nullif(v_payload ->> 'status', ''), 'completed'),
      coalesce((nullif(v_payload ->> 'paid_at', ''))::timestamp without time zone, now()),
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
        'phase', '6.12C'
      )
    );
  elsif v_operation in ('update', 'upsert') and v_exists then
    update public.sale_payments sp
    set
      payment_method = case
        when v_payload ? 'payment_method' then v_payment_method
        else sp.payment_method
      end,
      amount = case
        when v_payload ? 'amount' then v_amount
        else sp.amount
      end,
      currency = case
        when v_payload ? 'currency' then v_currency
        else sp.currency
      end,
      reference_number = case
        when v_payload ? 'reference_number' then nullif(v_payload ->> 'reference_number', '')
        else sp.reference_number
      end,
      status = case
        when v_payload ? 'status' then coalesce(nullif(v_payload ->> 'status', ''), sp.status)
        else sp.status
      end,
      paid_at = case
        when v_payload ? 'paid_at' then coalesce((nullif(v_payload ->> 'paid_at', ''))::timestamp without time zone, sp.paid_at)
        else sp.paid_at
      end,
      updated_by = v_mutation.profile_id,
      sync_status = 'synced'
    where sp.id = v_mutation.entity_id;
  elsif v_operation = 'soft_delete' then
    update public.sale_payments sp
    set
      deleted_at = coalesce(sp.deleted_at, now()),
      deleted_by = v_mutation.profile_id,
      delete_reason = coalesce(
        nullif(v_payload ->> 'delete_reason', ''),
        'Deleted from offline sync'
      ),
      updated_by = v_mutation.profile_id,
      sync_status = 'synced'
    where sp.id = v_mutation.entity_id;
  end if;

  v_result_payload := private.get_current_server_payload(
    'sale_payments',
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
    'entity_table', 'sale_payments',
    'entity_id', v_mutation.entity_id,
    'operation', v_operation,
    'server_entity_version', v_new_version
  );
end;
$$;

comment on function private.apply_sync_sale_payment_mutation(uuid)
is 'Applies insert/update/upsert/soft_delete sync mutations for sale_payments.';

revoke all on function private.apply_sync_sale_payment_mutation(uuid) from public;
grant execute on function private.apply_sync_sale_payment_mutation(uuid) to authenticated, service_role;

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
            'phase', '6.12C',
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
            'phase', '6.12C',
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
            'phase', '6.12C',
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
        elsif lower(v_mutation.entity_table) = 'sale_payments' then
          v_apply_result := private.apply_sync_sale_payment_mutation(v_mutation.id);
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
        then 'POS sales, sale_items and sale_payments mutations were applied when supported. Other entities were skipped.'
      else 'Validation only. No business data was changed.'
    end
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Processes a sync batch. Supports validate_only, apply_catalog and apply_pos modes. apply_pos supports sales, sale_items and sale_payments.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;

commit;