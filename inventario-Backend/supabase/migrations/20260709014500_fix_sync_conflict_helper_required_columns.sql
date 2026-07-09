begin;

drop function if exists private.create_sync_conflict_for_mutation(
  uuid,
  text,
  text,
  jsonb,
  text,
  jsonb
);

create function private.create_sync_conflict_for_mutation(
  p_sync_mutation_id uuid,
  p_conflict_type text,
  p_severity text,
  p_server_payload jsonb default null,
  p_error_message text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_conflict_id uuid := gen_random_uuid();

  v_business_id uuid;
  v_branch_id uuid;
  v_sync_batch_id uuid;
  v_app_device_id uuid;
  v_profile_id uuid;
  v_client_mutation_id text;
  v_client_sequence integer;
  v_entity_table text;
  v_entity_id uuid;
  v_operation text;
  v_client_payload jsonb;
  v_before_payload jsonb;
  v_base_version integer;

  v_conflict_type text;
  v_severity text;
begin
  select
    sm.business_id,
    sm.branch_id,
    sm.sync_batch_id,
    sm.app_device_id,
    sm.profile_id,
    sm.client_mutation_id,
    sm.client_sequence,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.before_payload,
    sm.base_version
  into
    v_business_id,
    v_branch_id,
    v_sync_batch_id,
    v_app_device_id,
    v_profile_id,
    v_client_mutation_id,
    v_client_sequence,
    v_entity_table,
    v_entity_id,
    v_operation,
    v_client_payload,
    v_before_payload,
    v_base_version
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id;

  v_conflict_type := case
    when p_conflict_type in (
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
    then p_conflict_type
    else 'unknown'
  end;

  v_severity := case
    when p_severity in ('low', 'medium', 'high', 'critical')
    then p_severity
    when p_severity in ('warning', 'info')
    then 'low'
    else 'high'
  end;

  update public.sync_mutations
  set
    status = case
      when p_severity in ('warning', 'info') then status
      else 'error'
    end,
    error_code = coalesce(v_conflict_type, error_code, 'unknown'),
    error_message = coalesce(p_error_message, error_message),
    updated_at = now()
  where id = p_sync_mutation_id
    and status <> 'applied';

  if to_regclass('public.sync_conflicts') is null then
    return v_conflict_id;
  end if;

  begin
    insert into public.sync_conflicts (
      id,
      business_id,
      branch_id,
      sync_batch_id,
      sync_mutation_id,
      app_device_id,
      profile_id,
      client_mutation_id,
      client_sequence,
      entity_table,
      entity_id,
      operation,
      conflict_type,
      severity,
      status,
      resolution_strategy,
      client_payload,
      server_payload,
      base_payload,
      base_version,
      error_message,
      metadata,
      version,
      sync_status,
      created_by,
      updated_by,
      created_at,
      updated_at
    )
    values (
      v_conflict_id,
      v_business_id,
      v_branch_id,
      v_sync_batch_id,
      p_sync_mutation_id,
      v_app_device_id,
      v_profile_id,
      v_client_mutation_id,
      coalesce(v_client_sequence, 0),
      v_entity_table,
      v_entity_id,
      v_operation,
      v_conflict_type,
      v_severity,
      'open',
      'manual_review',
      coalesce(v_client_payload, '{}'::jsonb),
      p_server_payload,
      v_before_payload,
      v_base_version,
      p_error_message,
      coalesce(p_metadata, '{}'::jsonb),
      1,
      'synced',
      v_profile_id,
      v_profile_id,
      now(),
      now()
    )
    on conflict do nothing;

  exception
    when others then
      -- Importante:
      -- Esta función se usa para registrar el conflicto, pero nunca debe romper
      -- process_sync_batch. Si sync_conflicts cambia de estructura o tiene una
      -- validación adicional, dejamos el error en sync_mutations y continuamos.
      update public.sync_mutations
      set
        error_code = coalesce(error_code, 'unknown'),
        error_message = coalesce(
          error_message,
          p_error_message,
          'No se pudo registrar sync_conflict.'
        ),
        updated_at = now()
      where id = p_sync_mutation_id
        and status <> 'applied';
  end;

  return v_conflict_id;
end;
$$;

grant execute on function private.create_sync_conflict_for_mutation(
  uuid,
  text,
  text,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

commit;
