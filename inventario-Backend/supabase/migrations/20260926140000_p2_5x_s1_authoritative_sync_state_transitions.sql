begin;

-- The existing fill trigger supplies this value after the client guard. A
-- column default runs before BEFORE triggers and would make a legitimate
-- pending INSERT indistinguishable from a client-forged server timestamp.
alter table public.sync_batches alter column server_started_at drop default;

-- These invoker triggers see authenticated for direct table DML and postgres
-- for the existing SECURITY DEFINER processor. Client metadata is never an
-- authority signal. The normal upload upsert may repeat an unchanged pending
-- intent, including its generated transport row id and client timestamps.
create function private.guard_sync_batch_client_state()
returns trigger language plpgsql security invoker
set search_path = pg_catalog, public as $$
begin
  if current_user in ('postgres', 'service_role') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending' or new.applied_count <> 0 or
       new.skipped_count <> 0 or new.conflict_count <> 0 or
       new.error_count <> 0 or new.server_started_at is not null or
       new.server_completed_at is not null or new.error_message is not null or
       new.sync_status <> 'synced' or new.archived_at is not null or
       new.metadata ?| array['pos_inventory_apply',
         'pos_inventory_auto_apply', 'purchase_inventory_auto_apply',
         'apply_cash', 'sale_did_not_occur'] then
      raise exception using errcode = '42501',
        message = 'sync_batch_state_is_backend_owned';
    end if;
    return new;
  end if;

  if old.status <> 'pending' or new.status <> 'pending' or
     new.business_id is distinct from old.business_id or
     new.app_device_id is distinct from old.app_device_id or
     new.profile_id is distinct from old.profile_id or
     new.branch_id is distinct from old.branch_id or
     new.client_batch_id is distinct from old.client_batch_id or
     new.direction is distinct from old.direction or
     new.metadata is distinct from old.metadata or
     new.applied_count is distinct from old.applied_count or
     new.skipped_count is distinct from old.skipped_count or
     new.conflict_count is distinct from old.conflict_count or
     new.error_count is distinct from old.error_count or
     new.server_started_at is distinct from old.server_started_at or
     new.server_completed_at is distinct from old.server_completed_at or
     new.error_message is distinct from old.error_message or
     new.sync_status is distinct from old.sync_status or
     new.deleted_at is distinct from old.deleted_at or
     new.archived_at is distinct from old.archived_at or
     new.archived_by is distinct from old.archived_by or
     new.archive_reason is distinct from old.archive_reason or
     new.retention_until is distinct from old.retention_until then
    raise exception using errcode = '42501',
      message = 'sync_batch_state_is_backend_owned';
  end if;
  return new;
end;
$$;

create trigger trg_sync_batches_a_authoritative_client_state
before insert or update on public.sync_batches
for each row execute function private.guard_sync_batch_client_state();

create function private.guard_sync_mutation_client_state()
returns trigger language plpgsql security invoker
set search_path = pg_catalog, public as $$
begin
  if current_user in ('postgres', 'service_role') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'pending' or new.server_processed_at is not null or
       new.server_entity_version is not null or new.error_code is not null or
       new.error_message is not null or new.sync_status <> 'synced' or
       new.archived_at is not null or
       new.metadata ?| array['apply_cash_result', 'conflict_resolution',
         'resolved_payload_application', 'superseded_by_sale_reconciliation',
         'resolution_strategy', 'discard_confirmed_at'] then
      raise exception using errcode = '42501',
        message = 'sync_mutation_result_is_backend_owned';
    end if;
    return new;
  end if;

  if old.status <> 'pending' or new.status <> 'pending' or
     new.business_id is distinct from old.business_id or
     new.app_device_id is distinct from old.app_device_id or
     new.profile_id is distinct from old.profile_id or
     new.branch_id is distinct from old.branch_id or
     new.client_mutation_id is distinct from old.client_mutation_id or
     new.client_sequence is distinct from old.client_sequence or
     new.entity_table is distinct from old.entity_table or
     new.entity_id is distinct from old.entity_id or
     new.operation is distinct from old.operation or
     new.payload is distinct from old.payload or
     new.before_payload is distinct from old.before_payload or
     new.changed_fields is distinct from old.changed_fields or
     new.base_version is distinct from old.base_version or
     new.base_updated_at is distinct from old.base_updated_at or
     new.idempotency_key is distinct from old.idempotency_key or
     new.metadata is distinct from old.metadata or
     new.server_processed_at is distinct from old.server_processed_at or
     new.server_entity_version is distinct from old.server_entity_version or
     new.error_code is distinct from old.error_code or
     new.error_message is distinct from old.error_message or
     new.sync_status is distinct from old.sync_status or
     new.deleted_at is distinct from old.deleted_at or
     new.archived_at is distinct from old.archived_at or
     new.archived_by is distinct from old.archived_by or
     new.archive_reason is distinct from old.archive_reason or
     new.retention_until is distinct from old.retention_until then
    raise exception using errcode = '42501',
      message = 'sync_mutation_result_is_backend_owned';
  end if;
  return new;
end;
$$;

create trigger trg_sync_mutations_a_authoritative_client_state
before insert or update on public.sync_mutations
for each row execute function private.guard_sync_mutation_client_state();

-- Public RPCs continue to run as postgres. These helpers are not client RPCs.
revoke execute on function private.recalculate_sync_batch_counts(uuid)
  from authenticated;
revoke execute on function private.mark_sync_batch_processing(uuid)
  from authenticated;
revoke execute on function private.mark_sync_mutation_applied(uuid, integer)
  from authenticated;
revoke execute on function private.mark_sync_mutation_skipped(uuid, text)
  from authenticated;
revoke execute on function private.mark_sync_mutation_error(uuid, text, text)
  from authenticated;
revoke execute on function private.create_sync_conflict_for_mutation(
  uuid, text, text, jsonb, text, jsonb) from public, authenticated;
revoke execute on function private.finalize_sync_batch_from_counts(uuid)
  from authenticated;

-- private has USAGE for authenticated in this stack. The applicators are
-- processor internals, not callable client endpoints. The public processor
-- and conflict-resolution RPCs are SECURITY DEFINER and retain their access.
revoke execute on function private.apply_sync_cash_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_catalog_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_inventory_movement_mutation_base_before_source_auth(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_inventory_movement_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_pos_mutation_before_cash_session_guard(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_pos_mutation_before_sale_cost_snapshot(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_pos_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_purchase_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_sale_item_cost_snapshot_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_sale_payment_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_product_barcode_mutation(uuid)
  from public, authenticated;
revoke execute on function private.apply_sync_cash_movement_mutation(uuid)
  from public, authenticated;
revoke execute on function private.reject_sync_sale_cash_session_mutation(uuid, text, text)
  from public, authenticated;

revoke all on function private.guard_sync_batch_client_state() from public;
revoke all on function private.guard_sync_mutation_client_state() from public;

commit;
