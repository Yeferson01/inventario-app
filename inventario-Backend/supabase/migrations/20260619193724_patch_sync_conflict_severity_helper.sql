-- Fase 6.15F.1 - Patch sync conflict severity helper
-- Objetivo:
-- Corregir private.create_sync_conflict_for_mutation(...)
-- para que inserte una severidad válida en sync_conflicts.severity.
--
-- Problema detectado:
-- new row for relation "sync_conflicts" violates check constraint "sync_conflicts_severity_check"

begin;

create or replace function private.pick_sync_conflict_severity(
  p_conflict_type text
)
returns text
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_conflict_type text := lower(trim(coalesce(p_conflict_type, 'unknown')));
  v_constraint_def text;
  v_preferred text;
  v_candidate text;
begin
  -- Mapeo semántico recomendado.
  v_preferred := case
    when v_conflict_type in (
      'permission_denied',
      'business_rule_violation',
      'deleted_on_server'
    ) then 'high'

    when v_conflict_type in (
      'version_mismatch',
      'duplicate_key',
      'missing_server_row',
      'missing_client_base',
      'validation_error',
      'updated_at_mismatch'
    ) then 'medium'

    else 'medium'
  end;

  select string_agg(pg_get_constraintdef(c.oid), ' ')
  into v_constraint_def
  from pg_constraint c
  where c.conrelid = 'public.sync_conflicts'::regclass
    and c.conname = 'sync_conflicts_severity_check';

  -- Si no existe constraint, usamos el valor semántico.
  if v_constraint_def is null then
    return v_preferred;
  end if;

  -- Si el valor preferido aparece en el constraint, lo usamos.
  if position(quote_literal(v_preferred) in v_constraint_def) > 0
     or position(v_preferred in lower(v_constraint_def)) > 0 then
    return v_preferred;
  end if;

  -- Fallbacks comunes según distintos esquemas.
  foreach v_candidate in array array[
    'medium',
    'warning',
    'error',
    'high',
    'low',
    'info',
    'critical'
  ]
  loop
    if position(quote_literal(v_candidate) in v_constraint_def) > 0
       or position(v_candidate in lower(v_constraint_def)) > 0 then
      return v_candidate;
    end if;
  end loop;

  -- Último fallback defensivo.
  return v_preferred;
end;
$$;

comment on function private.pick_sync_conflict_severity(text)
is 'Returns a valid severity value for sync_conflicts based on the active severity check constraint.';

revoke all on function private.pick_sync_conflict_severity(text) from public;
grant execute on function private.pick_sync_conflict_severity(text) to authenticated, service_role;

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
  p_message text,
  p_server_payload jsonb default null,
  p_severity text default 'manual_review',
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_conflict_id uuid;
  v_conflict_type text := lower(trim(coalesce(p_conflict_type, 'unknown')));
  v_resolution_strategy text := lower(trim(coalesce(p_severity, 'manual_review')));
  v_severity text;
  v_metadata jsonb;
begin
  select
    sm.id,
    sm.sync_batch_id,
    sm.business_id,
    sm.app_device_id,
    sm.profile_id,
    sm.branch_id,
    sm.entity_table,
    sm.entity_id,
    sm.operation,
    sm.payload,
    sm.base_version,
    sm.base_updated_at,
    sm.status,
    sm.deleted_at
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
    and sm.deleted_at is null;

  if v_mutation.id is null then
    raise exception 'sync mutation not found for conflict creation';
  end if;

  v_severity := private.pick_sync_conflict_severity(v_conflict_type);

  v_metadata :=
    coalesce(p_metadata, '{}'::jsonb)
    || jsonb_build_object(
      'message', p_message,
      'resolution_strategy', v_resolution_strategy,
      'created_by_helper', 'private.create_sync_conflict_for_mutation',
      'client_operation', v_mutation.operation,
      'client_base_version', v_mutation.base_version,
      'client_base_updated_at', v_mutation.base_updated_at
    );

  insert into public.sync_conflicts (
    sync_mutation_id,
    sync_batch_id,
    business_id,
    app_device_id,
    profile_id,
    branch_id,
    entity_table,
    entity_id,
    conflict_type,
    severity,
    client_payload,
    server_payload,
    resolution_strategy,
    metadata,
    created_by,
    updated_by
  )
  values (
    v_mutation.id,
    v_mutation.sync_batch_id,
    v_mutation.business_id,
    v_mutation.app_device_id,
    v_mutation.profile_id,
    v_mutation.branch_id,
    v_mutation.entity_table,
    v_mutation.entity_id,
    v_conflict_type,
    v_severity,
    coalesce(v_mutation.payload, '{}'::jsonb),
    p_server_payload,
    v_resolution_strategy,
    v_metadata,
    v_mutation.profile_id,
    v_mutation.profile_id
  )
  returning id into v_conflict_id;

  update public.sync_mutations sm
  set
    status = 'conflict',
    error_code = v_conflict_type,
    error_message = p_message,
    server_processed_at = now(),
    updated_at = now(),
    updated_by = v_mutation.profile_id
  where sm.id = v_mutation.id;

  return v_conflict_id;
end;
$$;

comment on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb)
is 'Creates a sync conflict for a mutation with a valid severity value and marks the mutation as conflict.';

revoke all on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb) from public;
grant execute on function private.create_sync_conflict_for_mutation(uuid, text, text, jsonb, text, jsonb) to authenticated, service_role;

commit;