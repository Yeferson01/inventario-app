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
  v_has_business_id boolean;
  v_has_branch_id boolean;
  v_has_sync_batch_id boolean;
begin
  select
    sm.business_id,
    sm.branch_id,
    sm.sync_batch_id
  into
    v_business_id,
    v_branch_id,
    v_sync_batch_id
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id;

  update public.sync_mutations
  set
    status = case
      when p_severity in ('warning', 'info') then status
      else 'error'
    end,
    error_code = coalesce(p_conflict_type, error_code, 'sync_conflict'),
    error_message = coalesce(p_error_message, error_message),
    updated_at = now()
  where id = p_sync_mutation_id
    and status <> 'applied';

  if to_regclass('public.sync_conflicts') is null then
    return v_conflict_id;
  end if;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sync_conflicts'
      and column_name = 'business_id'
  )
  into v_has_business_id;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sync_conflicts'
      and column_name = 'branch_id'
  )
  into v_has_branch_id;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sync_conflicts'
      and column_name = 'sync_batch_id'
  )
  into v_has_sync_batch_id;

  begin
    if v_has_business_id and v_has_branch_id and v_has_sync_batch_id then
      insert into public.sync_conflicts (
        id,
        business_id,
        branch_id,
        sync_batch_id,
        sync_mutation_id,
        conflict_type,
        severity,
        server_payload,
        error_message,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_conflict_id,
        v_business_id,
        v_branch_id,
        v_sync_batch_id,
        p_sync_mutation_id,
        coalesce(p_conflict_type, 'sync_conflict'),
        coalesce(p_severity, 'error'),
        p_server_payload,
        p_error_message,
        coalesce(p_metadata, '{}'::jsonb),
        now(),
        now()
      )
      on conflict do nothing;

    elsif v_has_business_id and v_has_branch_id then
      insert into public.sync_conflicts (
        id,
        business_id,
        branch_id,
        sync_mutation_id,
        conflict_type,
        severity,
        server_payload,
        error_message,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_conflict_id,
        v_business_id,
        v_branch_id,
        p_sync_mutation_id,
        coalesce(p_conflict_type, 'sync_conflict'),
        coalesce(p_severity, 'error'),
        p_server_payload,
        p_error_message,
        coalesce(p_metadata, '{}'::jsonb),
        now(),
        now()
      )
      on conflict do nothing;

    else
      insert into public.sync_conflicts (
        id,
        sync_mutation_id,
        conflict_type,
        severity,
        server_payload,
        error_message,
        metadata,
        created_at,
        updated_at
      )
      values (
        v_conflict_id,
        p_sync_mutation_id,
        coalesce(p_conflict_type, 'sync_conflict'),
        coalesce(p_severity, 'error'),
        p_server_payload,
        p_error_message,
        coalesce(p_metadata, '{}'::jsonb),
        now(),
        now()
      )
      on conflict do nothing;
    end if;

  exception
    when undefined_table or undefined_column then
      null;
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
