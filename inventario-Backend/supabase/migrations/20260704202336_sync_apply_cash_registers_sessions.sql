-- 6.18C.38F.1 - Apply offline sync for cash_registers and cash_sessions
--
-- Adds backend support for cash sync before POS upload.
--
-- Important:
-- - cash_registers/cash_sessions must exist remotely before sales reference them.
-- - Flutter/local may keep extra fields like code, metadata_json, idempotency_key.
-- - Backend public.cash_registers/public.cash_sessions currently do not have all
--   those columns, so this mapper only writes backend-supported columns.

create or replace function private.cash_sync_timestamp(
  p_value text,
  p_fallback timestamp without time zone default null
)
returns timestamp without time zone
language plpgsql
immutable
as $$
begin
  if p_value is null or btrim(p_value) = '' then
    return p_fallback;
  end if;

  return (p_value::timestamptz at time zone 'UTC');
exception
  when others then
    return p_fallback;
end;
$$;

comment on function private.cash_sync_timestamp(text, timestamp without time zone)
is 'Safely converts sync JSON timestamp strings into UTC timestamp without time zone.';


create or replace function private.apply_sync_cash_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mut public.sync_mutations%rowtype;
  v_payload jsonb;
  v_entity text;
  v_operation text;

  v_id uuid;
  v_business_id uuid;
  v_branch_id uuid;
  v_profile_id uuid;

  v_created_at timestamp without time zone;
  v_updated_at timestamp without time zone;
  v_deleted_at timestamp without time zone;

  v_status text;

  v_cash_register_id uuid;
  v_opened_by uuid;
  v_closed_by uuid;
  v_opened_at timestamp without time zone;
  v_closed_at timestamp without time zone;
  v_opening_amount numeric;
  v_expected_closing_amount numeric;
  v_actual_closing_amount numeric;
  v_difference_amount numeric;
begin
  select *
  into v_mut
  from public.sync_mutations
  where id = p_sync_mutation_id
    and deleted_at is null;

  if not found then
    raise exception 'sync_mutation not found: %', p_sync_mutation_id;
  end if;

  v_entity := lower(v_mut.entity_table);
  v_operation := lower(v_mut.operation);
  v_payload := coalesce(v_mut.payload, '{}'::jsonb);

  if v_entity not in ('cash_registers', 'cash_sessions') then
    raise exception 'Unsupported cash sync entity_table: %', v_mut.entity_table;
  end if;

  if v_operation not in ('insert', 'upsert', 'update', 'soft_delete') then
    raise exception 'Unsupported cash sync operation: %', v_mut.operation;
  end if;

  v_id := coalesce(
    nullif(v_payload ->> 'id', '')::uuid,
    v_mut.entity_id::uuid
  );

  v_business_id := coalesce(
    nullif(v_payload ->> 'business_id', '')::uuid,
    v_mut.business_id
  );

  v_branch_id := coalesce(
    nullif(v_payload ->> 'branch_id', '')::uuid,
    v_mut.branch_id
  );

  v_profile_id := coalesce(
    nullif(v_payload ->> 'profile_id', '')::uuid,
    nullif(v_payload ->> 'user_id', '')::uuid,
    nullif(v_payload ->> 'opened_by_profile_id', '')::uuid,
    nullif(v_payload ->> 'opened_by', '')::uuid,
    v_mut.profile_id
  );

  v_created_at := private.cash_sync_timestamp(
    v_payload ->> 'created_at',
    now()
  );

  v_updated_at := private.cash_sync_timestamp(
    v_payload ->> 'updated_at',
    now()
  );

  v_deleted_at := private.cash_sync_timestamp(
    v_payload ->> 'deleted_at',
    null
  );

  if v_business_id is null then
    raise exception 'business_id is required for cash sync mutation %', p_sync_mutation_id;
  end if;

  if v_branch_id is null then
    raise exception 'branch_id is required for cash sync mutation %', p_sync_mutation_id;
  end if;

  if v_entity = 'cash_registers' then
    if v_operation = 'soft_delete' then
      update public.cash_registers cr
      set
        deleted_at = coalesce(v_deleted_at, now()),
        deleted_by = v_profile_id,
        updated_by = v_profile_id,
        updated_at = now(),
        sync_status = 'synced'
      where cr.id = v_id
        and cr.business_id = v_business_id;

      return jsonb_build_object(
        'entity_table', v_entity,
        'entity_id', v_id,
        'operation', v_operation,
        'result', 'soft_deleted'
      );
    end if;

    v_status := coalesce(nullif(v_payload ->> 'status', ''), 'active');

    if v_status not in ('active', 'inactive') then
      raise exception 'Invalid cash_registers.status: %', v_status;
    end if;

    insert into public.cash_registers (
      id,
      business_id,
      branch_id,
      name,
      status,
      created_at,
      updated_at,
      deleted_at,
      created_by,
      updated_by,
      version,
      sync_status
    ) values (
      v_id,
      v_business_id,
      v_branch_id,
      coalesce(nullif(v_payload ->> 'name', ''), 'Caja principal'),
      v_status,
      v_created_at,
      v_updated_at,
      v_deleted_at,
      v_profile_id,
      v_profile_id,
      greatest(coalesce(nullif(v_payload ->> 'version', '')::integer, 1), 1),
      'synced'
    )
    on conflict (id) do update
    set
      branch_id = excluded.branch_id,
      name = excluded.name,
      status = excluded.status,
      updated_at = greatest(public.cash_registers.updated_at, excluded.updated_at),
      deleted_at = excluded.deleted_at,
      updated_by = excluded.updated_by,
      sync_status = 'synced';

    return jsonb_build_object(
      'entity_table', v_entity,
      'entity_id', v_id,
      'operation', v_operation,
      'result', 'applied'
    );
  end if;

  if v_entity = 'cash_sessions' then
    if v_operation = 'soft_delete' then
      update public.cash_sessions cs
      set
        deleted_at = coalesce(v_deleted_at, now()),
        deleted_by = v_profile_id,
        updated_by = v_profile_id,
        updated_at = now(),
        sync_status = 'synced'
      where cs.id = v_id
        and cs.business_id = v_business_id;

      return jsonb_build_object(
        'entity_table', v_entity,
        'entity_id', v_id,
        'operation', v_operation,
        'result', 'soft_deleted'
      );
    end if;

    v_cash_register_id := coalesce(
      nullif(v_payload ->> 'cash_register_id', '')::uuid,
      nullif(v_payload ->> 'cashRegisterId', '')::uuid
    );

    if v_cash_register_id is null then
      raise exception 'cash_register_id is required for cash_sessions mutation %', p_sync_mutation_id;
    end if;

    v_opened_by := coalesce(
      nullif(v_payload ->> 'opened_by', '')::uuid,
      nullif(v_payload ->> 'opened_by_profile_id', '')::uuid,
      nullif(v_payload ->> 'profile_id', '')::uuid,
      v_profile_id
    );

    if v_opened_by is null then
      raise exception 'opened_by is required for cash_sessions mutation %', p_sync_mutation_id;
    end if;

    v_closed_by := coalesce(
      nullif(v_payload ->> 'closed_by', '')::uuid,
      nullif(v_payload ->> 'closed_by_profile_id', '')::uuid
    );

    v_opened_at := private.cash_sync_timestamp(
      coalesce(v_payload ->> 'opened_at', v_payload ->> 'openedAt'),
      v_created_at
    );

    v_closed_at := private.cash_sync_timestamp(
      coalesce(v_payload ->> 'closed_at', v_payload ->> 'closedAt'),
      null
    );

    v_status := coalesce(nullif(v_payload ->> 'status', ''), 'open');

    if v_status not in ('open', 'closed', 'cancelled') then
      raise exception 'Invalid cash_sessions.status: %', v_status;
    end if;

    if v_status = 'open' then
      v_closed_at := null;
      v_closed_by := null;
    elsif v_status = 'closed' and v_closed_at is null then
      v_closed_at := v_updated_at;
    end if;

    v_opening_amount := coalesce(
      nullif(v_payload ->> 'opening_amount', '')::numeric,
      nullif(v_payload ->> 'opening_cash_amount', '')::numeric,
      0
    );

    v_expected_closing_amount := coalesce(
      nullif(v_payload ->> 'expected_closing_amount', '')::numeric,
      nullif(v_payload ->> 'expected_cash_amount', '')::numeric
    );

    v_actual_closing_amount := coalesce(
      nullif(v_payload ->> 'actual_closing_amount', '')::numeric,
      nullif(v_payload ->> 'closing_cash_amount', '')::numeric
    );

    v_difference_amount := coalesce(
      nullif(v_payload ->> 'difference_amount', '')::numeric,
      case
        when v_actual_closing_amount is not null
         and v_expected_closing_amount is not null
        then v_actual_closing_amount - v_expected_closing_amount
        else null
      end
    );

    insert into public.cash_sessions (
      id,
      business_id,
      branch_id,
      cash_register_id,
      opened_by,
      closed_by,
      opening_amount,
      expected_closing_amount,
      actual_closing_amount,
      difference_amount,
      status,
      opened_at,
      closed_at,
      notes,
      created_at,
      updated_at,
      deleted_at,
      created_by,
      updated_by,
      version,
      sync_status
    ) values (
      v_id,
      v_business_id,
      v_branch_id,
      v_cash_register_id,
      v_opened_by,
      v_closed_by,
      v_opening_amount,
      v_expected_closing_amount,
      v_actual_closing_amount,
      v_difference_amount,
      v_status,
      v_opened_at,
      v_closed_at,
      nullif(v_payload ->> 'notes', ''),
      v_created_at,
      v_updated_at,
      v_deleted_at,
      v_profile_id,
      v_profile_id,
      greatest(coalesce(nullif(v_payload ->> 'version', '')::integer, 1), 1),
      'synced'
    )
    on conflict (id) do update
    set
      branch_id = excluded.branch_id,
      cash_register_id = excluded.cash_register_id,
      opened_by = excluded.opened_by,
      closed_by = excluded.closed_by,
      opening_amount = excluded.opening_amount,
      expected_closing_amount = excluded.expected_closing_amount,
      actual_closing_amount = excluded.actual_closing_amount,
      difference_amount = excluded.difference_amount,
      status = excluded.status,
      opened_at = excluded.opened_at,
      closed_at = excluded.closed_at,
      notes = excluded.notes,
      updated_at = greatest(public.cash_sessions.updated_at, excluded.updated_at),
      deleted_at = excluded.deleted_at,
      updated_by = excluded.updated_by,
      sync_status = 'synced';

    return jsonb_build_object(
      'entity_table', v_entity,
      'entity_id', v_id,
      'operation', v_operation,
      'result', 'applied'
    );
  end if;

  raise exception 'Unhandled cash sync mutation: %', p_sync_mutation_id;
end;
$$;

comment on function private.apply_sync_cash_mutation(uuid)
is 'Applies one cash_registers or cash_sessions sync mutation. Used by apply_cash sync mode.';


create or replace function public.process_cash_sync_batch(
  p_sync_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_batch public.sync_batches%rowtype;
  v_mut record;
  v_result jsonb;

  v_mutation_count integer := 0;
  v_applied_count integer := 0;
  v_skipped_count integer := 0;
  v_error_count integer := 0;
  v_status text := 'completed';
  v_error_messages jsonb := '[]'::jsonb;
begin
  select *
  into v_batch
  from public.sync_batches
  where id = p_sync_batch_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'sync_batch not found: %', p_sync_batch_id;
  end if;

  if v_batch.direction is distinct from 'upload' then
    raise exception 'Only upload sync batches can be processed with apply_cash';
  end if;

  -- Basic ownership guard for authenticated clients.
  if auth.uid() is not null
     and v_batch.profile_id is not null
     and v_batch.profile_id <> auth.uid() then
    raise exception 'Cannot process a cash sync batch for another profile';
  end if;

  update public.sync_batches
  set
    status = 'processing',
    updated_at = now()
  where id = p_sync_batch_id;

  for v_mut in
    select *
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
    order by
      case lower(sm.entity_table)
        when 'cash_registers' then 1
        when 'cash_sessions' then 2
        else 99
      end,
      sm.client_sequence asc,
      sm.created_at asc
  loop
    v_mutation_count := v_mutation_count + 1;

    begin
      if lower(v_mut.entity_table) not in ('cash_registers', 'cash_sessions') then
        v_skipped_count := v_skipped_count + 1;

        update public.sync_mutations
        set
          status = 'skipped',
          error_code = null,
          error_message = null,
          updated_at = now()
        where id = v_mut.id;

        continue;
      end if;

      if lower(v_mut.status) = 'applied' then
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      v_result := private.apply_sync_cash_mutation(v_mut.id);

      v_applied_count := v_applied_count + 1;

      update public.sync_mutations
      set
        status = 'applied',
        error_code = null,
        error_message = null,
        metadata = coalesce(metadata, '{}'::jsonb)
          || jsonb_build_object('apply_cash_result', v_result),
        updated_at = now()
      where id = v_mut.id;

    exception
      when others then
        v_error_count := v_error_count + 1;
        v_status := 'partial';

        v_error_messages := v_error_messages || jsonb_build_array(
          jsonb_build_object(
            'sync_mutation_id', v_mut.id,
            'entity_table', v_mut.entity_table,
            'entity_id', v_mut.entity_id,
            'error', sqlerrm
          )
        );

        update public.sync_mutations
        set
          status = 'error',
          error_code = sqlstate,
          error_message = sqlerrm,
          updated_at = now()
        where id = v_mut.id;
    end;
  end loop;

  if v_error_count > 0 then
    v_status := 'partial';
  else
    v_status := 'completed';
  end if;

  update public.sync_batches
  set
    status = v_status,
    applied_count = v_applied_count,
    skipped_count = v_skipped_count,
    error_count = v_error_count,
    conflict_count = 0,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object(
        'apply_cash', jsonb_build_object(
          'processed_at', now(),
          'mutation_count', v_mutation_count,
          'applied_count', v_applied_count,
          'skipped_count', v_skipped_count,
          'error_count', v_error_count,
          'errors', v_error_messages
        )
      ),
    updated_at = now()
  where id = p_sync_batch_id;

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'mode', 'apply_cash',
    'status', v_status,
    'mutation_count', v_mutation_count,
    'applied_count', v_applied_count,
    'skipped_count', v_skipped_count,
    'conflict_count', 0,
    'error_count', v_error_count,
    'errors', v_error_messages
  );
end;
$$;

comment on function public.process_cash_sync_batch(uuid)
is 'Processes upload sync batches for cash_registers and cash_sessions. Used by process_sync_batch(..., apply_cash).';

revoke all on function public.process_cash_sync_batch(uuid) from public;
grant execute on function public.process_cash_sync_batch(uuid) to authenticated;
grant execute on function public.process_cash_sync_batch(uuid) to service_role;


do $$
begin
  -- Preserve the existing process_sync_batch implementation by renaming it once.
  -- The new public.process_sync_batch wrapper delegates all existing modes to the
  -- preserved function and handles only apply_cash directly.
  if to_regprocedure('public.process_sync_batch_base_before_cash(uuid,text)') is null then
    execute 'alter function public.process_sync_batch(uuid,text) rename to process_sync_batch_base_before_cash';
  end if;
end;
$$;


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
  v_mode text := lower(coalesce(p_mode, 'validate_only'));
begin
  if v_mode = 'apply_cash' then
    return public.process_cash_sync_batch(p_sync_batch_id);
  end if;

  return public.process_sync_batch_base_before_cash(
    p_sync_batch_id,
    p_mode
  );
end;
$$;

comment on function public.process_sync_batch(uuid, text)
is 'Wrapper for sync batch processing. Adds apply_cash and delegates previous modes to process_sync_batch_base_before_cash.';

revoke all on function public.process_sync_batch(uuid, text) from public;
grant execute on function public.process_sync_batch(uuid, text) to authenticated;
grant execute on function public.process_sync_batch(uuid, text) to service_role;
