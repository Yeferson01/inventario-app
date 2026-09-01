begin;

-- Keep the proven POS mapper intact and add a focused guard around sales.
do $$
begin
  if to_regprocedure(
    'private.apply_sync_pos_mutation_before_cash_session_guard(uuid)'
  ) is null then
    alter function private.apply_sync_pos_mutation(uuid)
      rename to apply_sync_pos_mutation_before_cash_session_guard;
  end if;
end;
$$;

create or replace function private.resolve_sync_sale_cash_session_context(
  p_sync_mutation_id uuid
)
returns table (
  is_valid boolean,
  rejection_reason text,
  resolved_cash_session_id uuid,
  resolved_cash_register_id uuid,
  resolved_branch_id uuid
)
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_payload jsonb;
  v_session record;
  v_requested_session_id uuid;
  v_requested_register_id uuid;
begin
  select
    sm.business_id,
    sm.branch_id,
    sm.payload
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id
    and sm.deleted_at is null;

  if v_mutation.business_id is null then
    is_valid := false;
    rejection_reason := 'missing';
    return next;
    return;
  end if;

  v_payload := coalesce(v_mutation.payload, '{}'::jsonb);

  begin
    v_requested_session_id :=
      nullif(v_payload ->> 'cash_session_id', '')::uuid;
  exception when invalid_text_representation then
    is_valid := false;
    rejection_reason := 'missing';
    return next;
    return;
  end;

  begin
    v_requested_register_id :=
      nullif(v_payload ->> 'cash_register_id', '')::uuid;
  exception when invalid_text_representation then
    is_valid := false;
    rejection_reason := 'missing';
    resolved_cash_session_id := v_requested_session_id;
    return next;
    return;
  end;

  begin
    resolved_branch_id := coalesce(
      nullif(v_payload ->> 'branch_id', '')::uuid,
      v_mutation.branch_id
    );
  exception when invalid_text_representation then
    is_valid := false;
    rejection_reason := 'wrong_branch';
    resolved_cash_session_id := v_requested_session_id;
    resolved_cash_register_id := v_requested_register_id;
    return next;
    return;
  end;

  resolved_cash_session_id := v_requested_session_id;
  resolved_cash_register_id := v_requested_register_id;

  if v_requested_session_id is null or v_requested_register_id is null then
    is_valid := false;
    rejection_reason := 'missing';
    return next;
    return;
  end if;

  -- Same lock order as close_cash_session_authoritatively:
  -- register advisory lock, then the cash_sessions row lock.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cash_session:' || v_requested_register_id::text,
      0
    )
  );

  select session.*
  into v_session
  from public.cash_sessions session
  where session.id = v_requested_session_id
  for update of session;

  if v_session.id is null then
    is_valid := false;
    rejection_reason := 'missing';
  elsif v_session.business_id is distinct from v_mutation.business_id then
    is_valid := false;
    rejection_reason := 'wrong_business';
  elsif v_session.deleted_at is not null then
    is_valid := false;
    rejection_reason := 'deleted';
  elsif v_session.branch_id is distinct from resolved_branch_id then
    is_valid := false;
    rejection_reason := 'wrong_branch';
  elsif v_session.cash_register_id is distinct from v_requested_register_id then
    is_valid := false;
    rejection_reason := 'wrong_register';
  elsif v_session.status is distinct from 'open' then
    is_valid := false;
    rejection_reason := 'closed';
  else
    is_valid := true;
    rejection_reason := null;
  end if;

  return next;
end;
$$;

create or replace function private.reject_sync_sale_cash_session_mutation(
  p_sync_mutation_id uuid,
  p_reason text,
  p_phase text
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_mutation record;
  v_conflict_id uuid;
begin
  select
    sm.entity_id,
    sm.branch_id,
    sm.payload
  into v_mutation
  from public.sync_mutations sm
  where sm.id = p_sync_mutation_id;

  v_conflict_id := private.create_sync_conflict_for_mutation(
    p_sync_mutation_id := p_sync_mutation_id,
    p_conflict_type := 'business_rule_violation',
    p_severity := 'high',
    p_server_payload := null,
    p_error_message :=
      'Sale cash session is unavailable for the requested operational context.',
    p_metadata := jsonb_strip_nulls(jsonb_build_object(
      'phase', p_phase,
      'rule', 'sale_cash_session_invalid',
      'reason', p_reason,
      'sale_id', v_mutation.entity_id,
      'cash_session_id', nullif(v_mutation.payload ->> 'cash_session_id', ''),
      'cash_register_id', nullif(v_mutation.payload ->> 'cash_register_id', ''),
      'branch_id', v_mutation.branch_id
    ))
  );

  return jsonb_build_object(
    'status', 'conflict',
    'conflict_id', v_conflict_id,
    'reason', 'sale_cash_session_invalid',
    'remote_reason', p_reason,
    'entity_table', 'sales',
    'entity_id', v_mutation.entity_id
  );
end;
$$;

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
  v_context record;
  v_result jsonb;
begin
  if p_sync_mutation_id is null then
    raise exception 'p_sync_mutation_id is required';
  end if;

  select
    sm.id,
    sm.entity_id,
    lower(trim(sm.entity_table)) as entity_table,
    lower(trim(sm.operation)) as operation,
    coalesce(sm.payload, '{}'::jsonb) as payload,
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

  if v_mutation.entity_table <> 'sales'
     or v_mutation.operation not in ('insert', 'update', 'upsert')
     or nullif(v_mutation.payload ->> 'cash_session_id', '') is null then
    return private.apply_sync_pos_mutation_before_cash_session_guard(
      p_sync_mutation_id
    );
  end if;

  select *
  into v_context
  from private.resolve_sync_sale_cash_session_context(p_sync_mutation_id);

  if not coalesce(v_context.is_valid, false) then
    return private.reject_sync_sale_cash_session_mutation(
      p_sync_mutation_id,
      coalesce(v_context.rejection_reason, 'missing'),
      'stale_cash_session_sale_guard'
    );
  end if;

  v_result := private.apply_sync_pos_mutation_before_cash_session_guard(
    p_sync_mutation_id
  );

  if v_result ->> 'status' = 'applied' then
    update public.sales sale
    set
      cash_session_id = v_context.resolved_cash_session_id,
      updated_at = now()
    where sale.id = v_mutation.entity_id;
  end if;

  return v_result || jsonb_build_object(
    'cash_session_id', v_context.resolved_cash_session_id,
    'cash_register_id', v_context.resolved_cash_register_id
  );
end;
$$;

comment on function private.apply_sync_pos_mutation(uuid)
is 'Applies POS mutations and rejects sales whose supplied cash session is not the same open business/branch/register session.';

create or replace function private.backfill_pos_sales_cash_session_from_sync_batch(
  p_sync_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_candidate record;
  v_context record;
  v_updated_count integer := 0;
  v_already_linked_count integer := 0;
  v_rejected_count integer := 0;
  v_sales_with_payload integer := 0;
begin
  select count(*)
  into v_sales_with_payload
  from public.sync_mutations sm
  where sm.sync_batch_id = p_sync_batch_id
    and sm.deleted_at is null
    and lower(sm.entity_table) = 'sales'
    and nullif(sm.payload ->> 'cash_session_id', '') is not null;

  for v_candidate in
    select
      sm.id as sync_mutation_id,
      sm.entity_id as sale_id,
      nullif(sm.payload ->> 'cash_session_id', '') as cash_session_id,
      sale.cash_session_id as current_cash_session_id
    from public.sync_mutations sm
    join public.sales sale
      on sale.id = sm.entity_id
     and sale.deleted_at is null
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and lower(sm.entity_table) = 'sales'
      and nullif(sm.payload ->> 'cash_session_id', '') is not null
  loop
    -- Historical rows already linked remain untouched even if their session
    -- has since been closed legitimately.
    if v_candidate.current_cash_session_id::text = v_candidate.cash_session_id then
      v_already_linked_count := v_already_linked_count + 1;
      continue;
    end if;

    select *
    into v_context
    from private.resolve_sync_sale_cash_session_context(
      v_candidate.sync_mutation_id
    );

    if not coalesce(v_context.is_valid, false) then
      perform private.reject_sync_sale_cash_session_mutation(
        v_candidate.sync_mutation_id,
        coalesce(v_context.rejection_reason, 'missing'),
        'legacy_cash_session_backfill_guard'
      );
      v_rejected_count := v_rejected_count + 1;
      continue;
    end if;

    update public.sales sale
    set
      cash_session_id = v_context.resolved_cash_session_id,
      updated_at = now()
    where sale.id = v_candidate.sale_id
      and sale.cash_session_id is distinct from
        v_context.resolved_cash_session_id;

    if found then
      v_updated_count := v_updated_count + 1;
    end if;
  end loop;

  if v_rejected_count > 0 then
    perform private.recalculate_sync_batch_counts(p_sync_batch_id);
    perform private.finalize_sync_batch_from_counts(p_sync_batch_id);
  end if;

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'sales_with_cash_session_payload', v_sales_with_payload,
    'sales_updated', v_updated_count,
    'sales_already_linked', v_already_linked_count,
    'sales_rejected', v_rejected_count
  );
end;
$$;

revoke all on function private.resolve_sync_sale_cash_session_context(uuid)
from public;
revoke all on function private.reject_sync_sale_cash_session_mutation(
  uuid,
  text,
  text
) from public;
revoke all on function private.apply_sync_pos_mutation(uuid) from public;

grant execute on function private.resolve_sync_sale_cash_session_context(uuid)
to authenticated, service_role;
grant execute on function private.reject_sync_sale_cash_session_mutation(
  uuid,
  text,
  text
) to authenticated, service_role;
grant execute on function private.apply_sync_pos_mutation(uuid)
to authenticated, service_role;

commit;
