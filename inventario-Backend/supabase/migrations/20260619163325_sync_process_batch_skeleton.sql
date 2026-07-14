-- Fase 6.7 - process_sync_batch skeleton
-- Objetivo:
-- Crear primera versión segura de public.process_sync_batch().
--
-- Esta versión NO aplica todavía cambios reales a las tablas del negocio.
-- Solo valida, clasifica mutaciones y finaliza el batch.
--
-- Próximas fases:
-- - Aplicar catálogo: products, categories, customers, suppliers.
-- - Aplicar POS: sales, sale_items, sale_payments.
-- - Aplicar inventario usando RPCs seguras existentes.

begin;

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
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  v_mode := lower(trim(coalesce(p_mode, 'validate_only')));

  if v_mode <> 'validate_only' then
    raise exception 'Unsupported process_sync_batch mode for this phase: %. Only validate_only is available.', p_mode;
  end if;

  -- Bloquear batch para evitar doble procesamiento concurrente.
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

  -- El usuario dueño del batch puede procesarlo.
  -- Admin/settings/security también puede procesarlo por soporte.
  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'settings.business')
       or private.has_business_permission(v_batch.business_id, 'security_events.read')
     ) then
    raise exception 'Insufficient permission to process this sync batch';
  end if;

  -- Validar dispositivo activo.
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

  -- Procesar mutaciones pendientes en orden estable.
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

      -- Validar que la mutación pertenece realmente al batch.
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

      -- Prohibir hard delete por arquitectura.
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
            'phase', '6.7',
            'mode', v_mode,
            'rule', 'no_hard_delete'
          )
        );

        continue;
      end if;

      -- inventory_movements debe ser append-only.
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
            'phase', '6.7',
            'mode', v_mode,
            'rule', 'inventory_movements_append_only'
          )
        );

        continue;
      end if;

      -- Validar permiso por entidad/operación.
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
            'phase', '6.7',
            'mode', v_mode,
            'entity_table', v_mutation.entity_table,
            'operation', v_mutation.operation
          )
        );

        continue;
      end if;

      -- En esta fase todavía no aplicamos cambios reales.
      -- Si pasó validaciones, queda como skipped técnico.
      perform private.mark_sync_mutation_skipped(
        v_mutation.id,
        'Validated by process_sync_batch skeleton. Real apply engine is not implemented yet.'
      );

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
    'note', 'Skeleton validation only. Real mutation application will be implemented in later phases.'
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Processes a sync batch in validate_only mode. Phase 6.7 skeleton validates/classifies mutations but does not apply business data changes yet.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;

commit;