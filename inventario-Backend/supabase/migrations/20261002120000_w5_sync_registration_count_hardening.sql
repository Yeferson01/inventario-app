begin;

-- S1A owns the expected cardinality. The older INSERT trigger counted the
-- same mutations a second time and made an otherwise identical retry fail.
drop trigger if exists trg_sync_mutations_increment_batch_count
  on public.sync_mutations;

create or replace function public.register_pending_sync_batch(p_batch jsonb)
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
  v_actual_count integer;
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
       or v_row.direction is distinct from v_direction then
      raise exception using errcode = 'P0001', message = 'sync_batch_idempotency_conflict';
    end if;

    if v_row.mutation_count is distinct from v_mutation_count then
      -- Only pending rows can be locked/rewritten by the invoker's UPDATE
      -- policy. The lock also serializes this repair with mutation registration.
      if v_row.status <> 'pending' then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_idempotency_conflict';
      end if;
      select * into v_row from public.sync_batches sb
      where sb.id = v_row.id and sb.deleted_at is null for update;
      if not found or v_row.business_id is distinct from v_business_id
         or v_row.app_device_id is distinct from v_device_id
         or v_row.client_batch_id is distinct from v_client_batch_id
         or v_row.profile_id is distinct from v_profile_id
         or v_row.branch_id is distinct from v_branch_id
         or v_row.direction is distinct from v_direction
         or v_row.status <> 'pending' then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_idempotency_conflict';
      end if;
      if v_row.mutation_count is distinct from v_mutation_count then
        select count(*)::integer into v_actual_count
        from public.sync_mutations sm
        where sm.sync_batch_id = v_row.id and sm.deleted_at is null;
        if v_row.mutation_count <> v_mutation_count + v_actual_count then
          raise exception using errcode = 'P0001',
            message = 'sync_batch_idempotency_conflict';
        end if;
        update public.sync_batches sb set mutation_count = v_mutation_count
        where sb.id = v_row.id returning * into v_row;
      end if;
    end if;
  end if;
  return jsonb_build_object('id', v_row.id, 'status', v_row.status,
    'inserted', v_inserted);
end;
$$;
revoke all on function public.register_pending_sync_batch(jsonb)
  from public, anon;
grant execute on function public.register_pending_sync_batch(jsonb)
  to authenticated;

-- Keep the current W5B processor intact as an internal delegate. A row lock
-- conflicts with S1A's FOR KEY SHARE on registration and covers the count and
-- the delegated processing within this transaction.
alter function public.process_sync_batch(uuid,text)
  rename to process_sync_batch_base_before_w5_count_guard;
revoke all on function public.process_sync_batch_base_before_w5_count_guard(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch_base_before_w5_count_guard(uuid,text)
  to service_role;

create function public.process_sync_batch(
  p_sync_batch_id uuid, p_mode text default 'validate_only'
) returns jsonb language plpgsql security definer
set search_path = '' as $$
declare
  v_profile_id uuid := auth.uid();
  v_batch public.sync_batches%rowtype;
  v_actual_count integer;
  v_mode text := lower(trim(coalesce(p_mode, 'validate_only')));
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  -- Delegate invalid IDs/modes, deleted rows, non-upload and terminal rows so
  -- their existing authorization, idempotent return and errors stay intact.
  if p_sync_batch_id is not null and v_mode in
      ('validate_only', 'apply_catalog', 'apply_pos', 'apply_purchases',
       'apply_inventory', 'apply_cash') then
    select * into v_batch from public.sync_batches sb
    where sb.id = p_sync_batch_id for update;
    if found and v_batch.deleted_at is null and v_batch.direction = 'upload'
       and v_batch.status = 'pending' then
      if v_batch.profile_id <> v_profile_id
         and not (
           private.has_business_permission(v_batch.business_id, 'settings.business')
           or private.has_business_permission(v_batch.business_id,
             'security_events.read')
         ) then
        raise exception using errcode = '42501',
          message = case when v_mode = 'apply_cash' then 'permission_denied'
            else 'Insufficient permission to process this sync batch' end;
      end if;
      select count(*)::integer into v_actual_count
      from public.sync_mutations sm
      where sm.sync_batch_id = v_batch.id and sm.deleted_at is null;
      if v_actual_count < v_batch.mutation_count then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_registration_incomplete';
      end if;
      if v_actual_count > v_batch.mutation_count then
        raise exception using errcode = 'P0001',
          message = 'sync_batch_registration_overflow';
      end if;
    end if;
  end if;

  return public.process_sync_batch_base_before_w5_count_guard(
    p_sync_batch_id, p_mode);
end;
$$;
revoke all on function public.process_sync_batch(uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch(uuid,text)
  to authenticated, service_role;

commit;
