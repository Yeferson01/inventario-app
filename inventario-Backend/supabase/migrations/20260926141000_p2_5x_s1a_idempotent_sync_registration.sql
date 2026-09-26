begin;

-- PostgREST's on_conflict parameter cannot express the predicate of the
-- existing soft-delete-aware unique indexes. Keep those indexes and register
-- only pending intent under the caller's RLS and the S1 invoker guards.
create function public.register_pending_sync_batch(p_batch jsonb)
returns jsonb language plpgsql security invoker
set search_path = pg_catalog, public as $$
declare
  v_profile_id uuid := auth.uid();
  v_business_id uuid;
  v_device_id uuid;
  v_branch_id uuid;
  v_id uuid;
  v_client_batch_id text;
  v_direction text;
  v_mutation_count integer;
  v_metadata jsonb;
  v_row public.sync_batches%rowtype;
  v_inserted boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'sync_registration_auth_required';
  end if;
  if p_batch is null or jsonb_typeof(p_batch) <> 'object' then
    raise exception using errcode = '22023', message = 'sync_batch_invalid_input';
  end if;
  if (p_batch ? 'status' and p_batch ->> 'status' is distinct from 'pending')
     or p_batch ?| array['server_started_at', 'server_completed_at',
       'applied_count', 'skipped_count', 'conflict_count', 'error_count',
       'error_message', 'archived_at', 'archived_by', 'archive_reason'] then
    raise exception using errcode = '42501', message = 'sync_batch_state_is_backend_owned';
  end if;

  v_business_id := nullif(p_batch ->> 'business_id', '')::uuid;
  v_device_id := nullif(p_batch ->> 'app_device_id', '')::uuid;
  v_branch_id := nullif(p_batch ->> 'branch_id', '')::uuid;
  v_id := coalesce(nullif(p_batch ->> 'id', '')::uuid,
    extensions.gen_random_uuid());
  v_client_batch_id := nullif(btrim(p_batch ->> 'client_batch_id'), '');
  v_direction := coalesce(nullif(p_batch ->> 'direction', ''), 'upload');
  v_mutation_count := coalesce((p_batch ->> 'mutation_count')::integer, 0);
  v_metadata := coalesce(p_batch -> 'metadata', '{}'::jsonb);
  if v_business_id is null or v_device_id is null or v_client_batch_id is null
     or v_direction <> 'upload' or v_mutation_count < 0
     or jsonb_typeof(v_metadata) <> 'object' then
    raise exception using errcode = '22023', message = 'sync_batch_invalid_input';
  end if;
  if p_batch ? 'profile_id' and
     nullif(p_batch ->> 'profile_id', '')::uuid is distinct from v_profile_id then
    raise exception using errcode = '42501', message = 'sync_batch_scope_denied';
  end if;
  if not private.is_business_member(v_business_id)
     or (v_branch_id is not null and
       (not private.has_branch_access(v_business_id, v_branch_id) or
        not exists (select 1 from public.branches br
          where br.id = v_branch_id and br.business_id = v_business_id
            and br.status = 'active' and br.deleted_at is null))) then
    raise exception using errcode = '42501', message = 'sync_batch_scope_denied';
  end if;
  if not exists (select 1 from public.app_devices ad
    where ad.id = v_device_id and ad.business_id = v_business_id
      and ad.profile_id = v_profile_id and ad.status = 'active'
      and ad.deleted_at is null
      and (v_branch_id is null or ad.branch_id is null
        or ad.branch_id = v_branch_id)) then
    raise exception using errcode = '42501', message = 'sync_batch_device_invalid';
  end if;

  insert into public.sync_batches (id, business_id, app_device_id, profile_id,
    branch_id, client_batch_id, direction, status, mutation_count, metadata)
  values (v_id, v_business_id, v_device_id, v_profile_id, v_branch_id,
    v_client_batch_id, v_direction, 'pending', v_mutation_count, v_metadata)
  -- The proposed row UUID may also be reused on retry. Targetless DO NOTHING
  -- handles both the PK and the partial semantic index; the lookup below
  -- accepts only the exact active semantic identity.
  on conflict do nothing
  returning * into v_row;
  v_inserted := found;
  if not v_inserted then
    select * into v_row from public.sync_batches sb
    where sb.business_id = v_business_id and sb.app_device_id = v_device_id
      and sb.client_batch_id = v_client_batch_id and sb.deleted_at is null;
    if not found then
      if exists (select 1 from public.sync_batches sb
        where sb.id = v_id and sb.business_id = v_business_id
          and sb.app_device_id = v_device_id and sb.profile_id = v_profile_id
          and sb.deleted_at is null) then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_idempotency_conflict';
      end if;
      raise exception using errcode = '42501', message = 'sync_batch_scope_denied';
    end if;
    if v_row.profile_id is distinct from v_profile_id
       or v_row.branch_id is distinct from v_branch_id
       or v_row.direction is distinct from v_direction
       or v_row.mutation_count is distinct from v_mutation_count then
      raise exception using errcode = 'P0001', message = 'sync_batch_idempotency_conflict';
    end if;
  end if;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status,
    'inserted', v_inserted);
end;
$$;

create function public.register_pending_sync_mutation(p_mutation jsonb)
returns jsonb language plpgsql security invoker
set search_path = pg_catalog, public as $$
declare
  v_profile_id uuid := auth.uid();
  v_business_id uuid;
  v_device_id uuid;
  v_branch_id uuid;
  v_batch_id uuid;
  v_id uuid;
  v_client_mutation_id text;
  v_sequence integer;
  v_entity_table text;
  v_entity_id uuid;
  v_operation text;
  v_payload jsonb;
  v_before_payload jsonb;
  v_changed_fields text[];
  v_base_version integer;
  v_base_updated_at timestamp without time zone;
  v_idempotency_key text;
  v_metadata jsonb;
  v_batch public.sync_batches%rowtype;
  v_row public.sync_mutations%rowtype;
  v_inserted boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'sync_registration_auth_required';
  end if;
  if p_mutation is null or jsonb_typeof(p_mutation) <> 'object' then
    raise exception using errcode = '22023', message = 'sync_mutation_invalid_input';
  end if;
  if (p_mutation ? 'status' and
      p_mutation ->> 'status' is distinct from 'pending')
     or p_mutation ?| array['server_processed_at', 'server_entity_version',
       'error_code', 'error_message', 'archived_at', 'archived_by',
       'archive_reason'] then
    raise exception using errcode = '42501',
      message = 'sync_mutation_result_is_backend_owned';
  end if;

  v_business_id := nullif(p_mutation ->> 'business_id', '')::uuid;
  v_device_id := nullif(p_mutation ->> 'app_device_id', '')::uuid;
  v_branch_id := nullif(p_mutation ->> 'branch_id', '')::uuid;
  v_batch_id := nullif(p_mutation ->> 'sync_batch_id', '')::uuid;
  v_id := coalesce(nullif(p_mutation ->> 'id', '')::uuid,
    extensions.gen_random_uuid());
  v_client_mutation_id := nullif(btrim(p_mutation ->> 'client_mutation_id'), '');
  v_sequence := (p_mutation ->> 'client_sequence')::integer;
  v_entity_table := nullif(p_mutation ->> 'entity_table', '');
  v_entity_id := nullif(p_mutation ->> 'entity_id', '')::uuid;
  v_operation := nullif(p_mutation ->> 'operation', '');
  v_payload := coalesce(p_mutation -> 'payload', '{}'::jsonb);
  v_before_payload := p_mutation -> 'before_payload';
  if v_before_payload = 'null'::jsonb then v_before_payload := null; end if;
  if p_mutation ? 'changed_fields' and
     p_mutation -> 'changed_fields' <> 'null'::jsonb then
    if jsonb_typeof(p_mutation -> 'changed_fields') <> 'array' then
      raise exception using errcode = '22023', message = 'sync_mutation_invalid_input';
    end if;
    select array_agg(value) into v_changed_fields
    from jsonb_array_elements_text(p_mutation -> 'changed_fields') as x(value);
  end if;
  v_base_version := nullif(p_mutation ->> 'base_version', '')::integer;
  v_base_updated_at := nullif(p_mutation ->> 'base_updated_at', '')::timestamp;
  v_idempotency_key := nullif(btrim(p_mutation ->> 'idempotency_key'), '');
  v_metadata := coalesce(p_mutation -> 'metadata', '{}'::jsonb);
  if v_business_id is null or v_device_id is null or v_batch_id is null
     or v_client_mutation_id is null or v_sequence is null
     or v_entity_table is null or v_entity_id is null or v_operation is null
     or v_idempotency_key is null or jsonb_typeof(v_payload) <> 'object'
     or jsonb_typeof(v_metadata) <> 'object' then
    raise exception using errcode = '22023', message = 'sync_mutation_invalid_input';
  end if;
  if p_mutation ? 'profile_id' and
     nullif(p_mutation ->> 'profile_id', '')::uuid is distinct from v_profile_id then
    raise exception using errcode = '42501', message = 'sync_mutation_scope_denied';
  end if;
  if not private.is_business_member(v_business_id)
     or (v_branch_id is not null and
       not private.has_branch_access(v_business_id, v_branch_id)) then
    raise exception using errcode = '42501', message = 'sync_mutation_scope_denied';
  end if;
  if not exists (select 1 from public.app_devices ad
    where ad.id = v_device_id and ad.business_id = v_business_id
      and ad.profile_id = v_profile_id and ad.status = 'active'
      and ad.deleted_at is null
      and (v_branch_id is null or ad.branch_id is null
        or ad.branch_id = v_branch_id)) then
    raise exception using errcode = '42501', message = 'sync_mutation_device_invalid';
  end if;

  -- A key-share lock serializes registration with the processor's FOR UPDATE
  -- lock on the batch, so a new mutation cannot appear after completion.
  select * into v_batch from public.sync_batches sb
  where sb.id = v_batch_id and sb.deleted_at is null for key share;
  if not found or v_batch.business_id is distinct from v_business_id
     or v_batch.app_device_id is distinct from v_device_id
     or v_batch.profile_id is distinct from v_profile_id
     or v_batch.branch_id is distinct from v_branch_id then
    raise exception using errcode = '42501', message = 'sync_mutation_scope_denied';
  end if;

  if v_batch.status = 'pending' then
    begin
      insert into public.sync_mutations (id, business_id, sync_batch_id,
        app_device_id, profile_id, branch_id, client_mutation_id,
        client_sequence, entity_table, entity_id, operation, payload,
        before_payload, changed_fields, base_version, base_updated_at,
        status, idempotency_key, metadata)
      values (v_id, v_business_id, v_batch_id, v_device_id, v_profile_id,
        v_branch_id, v_client_mutation_id, v_sequence, v_entity_table,
        v_entity_id, v_operation, v_payload, v_before_payload,
        v_changed_fields, v_base_version, v_base_updated_at, 'pending',
        v_idempotency_key, v_metadata)
      -- As for batches, either the UUID or the partial semantic key can race.
      on conflict do nothing
      returning * into v_row;
      v_inserted := found;
    exception when unique_violation then
      raise exception using errcode = 'P0001',
        message = 'sync_mutation_idempotency_conflict';
    end;
  end if;
  if not v_inserted then
    select * into v_row from public.sync_mutations sm
    where sm.business_id = v_business_id
      and sm.idempotency_key = v_idempotency_key and sm.deleted_at is null;
    if not found then
      if exists (select 1 from public.sync_mutations sm
        where sm.id = v_id and sm.business_id = v_business_id
          and sm.app_device_id = v_device_id
          and sm.profile_id = v_profile_id and sm.deleted_at is null) then
        raise exception using errcode = 'P0001',
          message = 'sync_mutation_idempotency_conflict';
      end if;
      if v_batch.status <> 'pending' then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_not_pending_for_registration';
      end if;
      if exists (select 1 from public.sync_mutations sm
        where sm.business_id = v_business_id
          and sm.app_device_id = v_device_id
          and sm.profile_id = v_profile_id and sm.deleted_at is null
          and (sm.sync_batch_id = v_batch_id
            and sm.client_sequence = v_sequence
            or sm.client_mutation_id = v_client_mutation_id)) then
        raise exception using errcode = 'P0001',
          message = 'sync_mutation_idempotency_conflict';
      end if;
      raise exception using errcode = '42501', message = 'sync_mutation_scope_denied';
    end if;
    if v_row.sync_batch_id is distinct from v_batch_id
       or v_row.app_device_id is distinct from v_device_id
       or v_row.profile_id is distinct from v_profile_id
       or v_row.branch_id is distinct from v_branch_id
       or v_row.client_mutation_id is distinct from v_client_mutation_id
       or v_row.client_sequence is distinct from v_sequence
       or v_row.entity_table is distinct from v_entity_table
       or v_row.entity_id is distinct from v_entity_id
       or v_row.operation is distinct from v_operation
       or v_row.payload is distinct from v_payload
       or v_row.before_payload is distinct from v_before_payload
       or v_row.changed_fields is distinct from v_changed_fields
       or v_row.base_version is distinct from v_base_version
       or v_row.base_updated_at is distinct from v_base_updated_at then
      raise exception using errcode = 'P0001',
        message = 'sync_mutation_idempotency_conflict';
    end if;
  end if;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status,
    'sync_batch_id', v_row.sync_batch_id, 'inserted', v_inserted);
end;
$$;

create function public.register_pending_sync_mutations(p_mutations jsonb)
returns jsonb language plpgsql security invoker
set search_path = pg_catalog, public as $$
declare
  v_mutation jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'sync_registration_auth_required';
  end if;
  if p_mutations is null or jsonb_typeof(p_mutations) <> 'array'
     or jsonb_array_length(p_mutations) not between 1 and 1000 then
    raise exception using errcode = '22023', message = 'sync_mutations_invalid_input';
  end if;
  for v_mutation in select value from jsonb_array_elements(p_mutations) as x(value)
  loop
    v_results := v_results || jsonb_build_array(
      public.register_pending_sync_mutation(v_mutation));
  end loop;
  return v_results;
end;
$$;

revoke all on function public.register_pending_sync_batch(jsonb) from public, anon;
revoke all on function public.register_pending_sync_mutation(jsonb) from public, anon;
revoke all on function public.register_pending_sync_mutations(jsonb) from public, anon;
grant execute on function public.register_pending_sync_batch(jsonb) to authenticated;
grant execute on function public.register_pending_sync_mutation(jsonb) to authenticated;
grant execute on function public.register_pending_sync_mutations(jsonb) to authenticated;

commit;
