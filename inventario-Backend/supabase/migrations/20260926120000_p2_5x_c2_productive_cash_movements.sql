-- C2: ordinary cash movements may only be applied by the controlled cash
-- batch processor. The table remains append-only and has no client INSERT.
begin;

alter table public.sync_mutations
  drop constraint sync_mutations_entity_table_allowed;
alter table public.sync_mutations
  add constraint sync_mutations_entity_table_allowed check (entity_table in (
    -- Historical sync entities already allowed before C2.
    'businesses',
    'branches',
    'business_members',
    'profiles',
    'categories',
    'customers',
    'suppliers',
    'products',
    'product_barcodes',
    'catalog_contributions',
    'purchases',
    'purchase_items',
    'sales',
    'sale_items',
    'sale_payments',
    'cash_registers',
    'cash_sessions',
    'inventory_movements',
    'product_stock_balances',

    -- Additional entities supported by the current sync contract.
    'stock_counts',
    'stock_count_items',
    'inventory_transfers',
    'inventory_transfer_items',

    -- P2.5X-C2.
    'cash_movements'
  ));

alter table public.sync_conflicts
  drop constraint sync_conflicts_entity_table_allowed;
alter table public.sync_conflicts
  add constraint sync_conflicts_entity_table_allowed check (entity_table in (
    'categories', 'products', 'customers', 'suppliers', 'purchases',
    'purchase_items', 'sales', 'sale_items', 'sale_payments',
    'inventory_movements', 'stock_counts', 'stock_count_items',
    'inventory_transfers', 'inventory_transfer_items', 'cash_sessions',
    'cash_registers', 'cash_movements'
  ));

alter table public.cash_movements
  add constraint cash_movements_direction_category_check check (
    (direction <> 'inflow' or category not in (
      'supplier_purchase', 'payroll', 'utilities', 'rent', 'maintenance',
      'repairs', 'transport', 'infrastructure', 'cleaning',
      'office_supplies', 'owner_withdrawal'))
    and
    (direction <> 'outflow' or category not in (
      'owner_contribution', 'other_income'))
  );

create function private.apply_sync_cash_movement_mutation(
  p_sync_mutation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_mut public.sync_mutations%rowtype;
  v_batch public.sync_batches%rowtype;
  v_session public.cash_sessions%rowtype;
  v_existing public.cash_movements%rowtype;
  v_payload jsonb;
  v_actor uuid := auth.uid();
  v_id uuid;
  v_register_id uuid;
  v_session_id uuid;
  v_direction text;
  v_category text;
  v_amount numeric;
  v_currency text;
  v_source_type text;
  v_source_id uuid;
  v_note text;
  v_occurred_at timestamptz;
  v_key text;
  v_permission text;
begin
  select * into v_mut from public.sync_mutations
  where id = p_sync_mutation_id and deleted_at is null;
  if v_mut.id is null then
    raise exception using errcode = 'P0001', message = 'mutation_not_found';
  end if;
  select * into v_batch from public.sync_batches
  where id = v_mut.sync_batch_id and deleted_at is null;
  if v_batch.id is null or v_batch.direction <> 'upload'
     or v_batch.business_id <> v_mut.business_id
     or v_batch.branch_id is distinct from v_mut.branch_id
     or v_batch.profile_id is distinct from v_mut.profile_id
     or v_batch.app_device_id is distinct from v_mut.app_device_id
     or v_mut.branch_id is null or v_mut.app_device_id is null
     or v_mut.entity_table <> 'cash_movements'
     or v_mut.operation <> 'insert'
  then
    raise exception using errcode = 'P0001', message = 'invalid_scope';
  end if;
  if v_actor is null or v_actor <> v_mut.profile_id then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  perform private.authorize_operational_device_context(
    v_mut.business_id, v_mut.branch_id, v_mut.app_device_id, true);

  v_payload := v_mut.payload;
  begin
    v_id := (v_payload ->> 'id')::uuid;
    v_register_id := (v_payload ->> 'cash_register_id')::uuid;
    v_session_id := (v_payload ->> 'cash_session_id')::uuid;
    v_source_id := nullif(v_payload ->> 'source_id', '')::uuid;
    v_amount := (v_payload ->> 'amount')::numeric;
    v_occurred_at := (v_payload ->> 'occurred_at')::timestamptz;
  exception when others then
    raise exception using errcode = 'P0001', message = 'invalid_payload';
  end;
  v_direction := v_payload ->> 'direction';
  v_category := v_payload ->> 'category';
  v_currency := v_payload ->> 'currency';
  v_source_type := v_payload ->> 'source_type';
  v_note := v_payload ->> 'note';
  v_key := v_payload ->> 'idempotency_key';
  if v_id is null or v_id <> v_mut.entity_id
     or (v_payload ->> 'business_id') is distinct from v_mut.business_id::text
     or (v_payload ->> 'branch_id') is distinct from v_mut.branch_id::text
     or v_register_id is null or v_session_id is null
     or v_key is null or v_key <> v_mut.idempotency_key
     or v_amount is null or v_amount <= 0
     or v_amount > 999999999999.99 or v_amount <> trunc(v_amount, 2)
     or v_direction not in ('inflow', 'outflow')
     or v_category not in (
       'supplier_purchase', 'payroll', 'utilities', 'rent', 'maintenance',
       'repairs', 'transport', 'infrastructure', 'cleaning',
       'office_supplies', 'owner_withdrawal', 'owner_contribution',
       'other_income', 'other')
     or (v_direction = 'inflow' and v_category in (
       'supplier_purchase', 'payroll', 'utilities', 'rent', 'maintenance',
       'repairs', 'transport', 'infrastructure', 'cleaning',
       'office_supplies', 'owner_withdrawal'))
     or (v_direction = 'outflow' and v_category in (
       'owner_contribution', 'other_income'))
     or nullif(btrim(v_currency), '') is null
     or nullif(btrim(v_source_type), '') is null
     or nullif(btrim(v_key), '') is null
     or v_occurred_at is null
     or (v_source_type = 'purchase' and v_source_id is null)
     or (v_source_type = 'manual' and v_source_id is not null)
     or v_payload ? 'reversed_movement_id'
  then
    raise exception using errcode = 'P0001', message = 'invalid_payload';
  end if;
  v_permission := case v_direction when 'outflow' then 'cash.disburse'
    else 'cash.receive' end;
  if not private.has_branch_permission(
    v_mut.business_id, v_mut.branch_id, v_permission)
  then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;

  -- Same lock key/order as close_cash_session_authoritatively. A movement
  -- that wins this lock is included in close; one that loses sees closed.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cash_session:' || v_register_id::text, 0));
  select s.* into v_session from public.cash_sessions s
  join public.cash_registers r on r.id = s.cash_register_id
  where s.id = v_session_id and s.business_id = v_mut.business_id
    and s.branch_id = v_mut.branch_id
    and s.cash_register_id = v_register_id and s.deleted_at is null
    and r.business_id = v_mut.business_id
    and r.branch_id = v_mut.branch_id and r.deleted_at is null
  for update of s;
  if v_session.id is null then
    raise exception using errcode = 'P0001', message = 'invalid_scope';
  end if;

  select * into v_existing from public.cash_movements m
  where m.business_id = v_mut.business_id
    and (m.id = v_id or m.idempotency_key = v_key)
  order by case when m.id = v_id then 0 else 1 end
  limit 1;
  if v_existing.id is not null then
    if v_existing.id <> v_id
       or v_existing.branch_id <> v_mut.branch_id
       or v_existing.cash_register_id <> v_register_id
       or v_existing.cash_session_id <> v_session_id
       or v_existing.direction <> v_direction
       or v_existing.category <> v_category
       or v_existing.amount <> v_amount
       or v_existing.currency <> v_currency
       or v_existing.source_type <> v_source_type
       or v_existing.source_id is distinct from v_source_id
       or v_existing.note is distinct from v_note
       or v_existing.occurred_at <> v_occurred_at
       or v_existing.created_by <> v_actor
       or v_existing.idempotency_key <> v_key
       or v_existing.metadata <> coalesce(v_payload -> 'metadata', '{}'::jsonb)
    then
      raise exception using errcode = '23505', message = 'idempotency_conflict';
    end if;
    return jsonb_build_object('result', 'already_applied', 'movement_id', v_id);
  end if;
  if v_session.status <> 'open' then
    raise exception using errcode = 'P0001', message = 'cash_session_closed';
  end if;
  insert into public.cash_movements (
    id, business_id, branch_id, cash_register_id, cash_session_id,
    direction, category, amount, currency, source_type, source_id,
    note, occurred_at, created_by, idempotency_key, metadata
  ) values (
    v_id, v_mut.business_id, v_mut.branch_id, v_register_id, v_session_id,
    v_direction, v_category, v_amount, v_currency, v_source_type,
    v_source_id, v_note, v_occurred_at, v_actor, v_key,
    coalesce(v_payload -> 'metadata', '{}'::jsonb)
  );
  return jsonb_build_object('result', 'applied', 'movement_id', v_id);
end;
$$;

create function public.lookup_cash_movement_acknowledgements(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_candidates jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_item jsonb;
  v_id uuid;
  v_key text;
  v_mut public.sync_mutations%rowtype;
  v_movement public.cash_movements%rowtype;
  v_results jsonb := '[]'::jsonb;
  v_state text;
  v_reason text;
begin
  perform private.authorize_operational_device_context(
    p_business_id, p_branch_id, p_app_device_id, true);
  if p_candidates is null or jsonb_typeof(p_candidates) <> 'array'
     or jsonb_array_length(p_candidates) < 1
     or jsonb_array_length(p_candidates) > 100
  then
    raise exception using errcode = 'P0001', message = 'invalid_candidates';
  end if;
  for v_item in select value from jsonb_array_elements(p_candidates)
  loop
    begin
      v_id := (v_item ->> 'id')::uuid;
      v_key := nullif(v_item ->> 'idempotency_key', '');
      if v_id is null or v_key is null
         or jsonb_typeof(v_item) <> 'object'
         or (v_item ->> 'cash_register_id')::uuid is null
         or (v_item ->> 'cash_session_id')::uuid is null
         or (v_item ->> 'amount')::numeric is null
      then
        raise exception 'incomplete candidate';
      end if;
    exception when others then
      raise exception using errcode = 'P0001', message = 'invalid_candidates';
    end;
    -- A caller may only classify its own mutation. This prevents using an
    -- arbitrary ID/key to probe another device's financial ledger.
    select * into v_mut from public.sync_mutations m
    where m.business_id = p_business_id and m.branch_id = p_branch_id
      and m.app_device_id = p_app_device_id and m.profile_id = auth.uid()
      and m.entity_table = 'cash_movements' and m.entity_id = v_id
      and m.idempotency_key = v_key and m.deleted_at is null
    order by m.created_at desc limit 1;
    if v_mut.id is null then
      v_state := 'not_found';
      v_reason := null;
    else
      select * into v_movement from public.cash_movements m
      where m.business_id = p_business_id and m.branch_id = p_branch_id
        and (m.id = v_id or m.idempotency_key = v_key)
      order by case when m.id = v_id then 0 else 1 end limit 1;
      if v_movement.id is not null then
        if v_movement.id = v_id
           and v_movement.idempotency_key = v_key
           and v_movement.cash_register_id =
             (v_item ->> 'cash_register_id')::uuid
           and v_movement.cash_session_id =
             (v_item ->> 'cash_session_id')::uuid
           and v_movement.direction = v_item ->> 'direction'
           and v_movement.amount = (v_item ->> 'amount')::numeric
           and v_movement.category = v_item ->> 'category'
           and v_movement.currency = v_item ->> 'currency'
           and v_movement.source_type = v_mut.payload ->> 'source_type'
           and v_movement.source_id::text is not distinct from
             v_mut.payload ->> 'source_id'
           and v_movement.note is not distinct from v_mut.payload ->> 'note'
           and v_movement.occurred_at =
             (v_mut.payload ->> 'occurred_at')::timestamptz
           and v_movement.created_by = v_mut.profile_id
           and v_movement.metadata =
             coalesce(v_mut.payload -> 'metadata', '{}'::jsonb)
        then
          v_state := 'applied';
          v_reason := null;
        else
          v_state := 'ambiguous';
          v_reason := 'semantic_mismatch';
        end if;
      elsif v_mut.status in ('error', 'conflict')
        and v_mut.error_code in (
          'cash_session_closed', 'permission_denied', 'invalid_scope',
          'invalid_payload', 'idempotency_conflict',
          'offline_closed_session_requires_recovery')
      then
        v_state := 'rejected';
        v_reason := v_mut.error_code;
      elsif v_mut.status in ('pending', 'processing') then
        v_state := 'ambiguous';
        v_reason := 'remote_mutation_not_terminal';
      else
        v_state := 'ambiguous';
        v_reason := 'remote_evidence_incomplete';
      end if;
    end if;
    v_results := v_results || jsonb_build_array(jsonb_build_object(
      'id', v_id, 'state', v_state, 'reason', v_reason));
  end loop;
  return v_results;
end;
$$;

revoke all on function public.lookup_cash_movement_acknowledgements(
  uuid, uuid, uuid, jsonb) from public, anon;
grant execute on function public.lookup_cash_movement_acknowledgements(
  uuid, uuid, uuid, jsonb) to authenticated, service_role;

revoke all on function private.apply_sync_cash_movement_mutation(uuid)
  from public, anon, authenticated;

create or replace function public.process_cash_sync_batch(p_sync_batch_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_batch public.sync_batches%rowtype;
  v_mut public.sync_mutations%rowtype;
  v_result jsonb;
  v_count integer := 0;
  v_applied integer := 0;
  v_skipped integer := 0;
  v_errors integer := 0;
  v_messages jsonb := '[]'::jsonb;
  v_code text;
  v_message text;
begin
  select * into v_batch from public.sync_batches
  where id = p_sync_batch_id and deleted_at is null for update;
  if v_batch.id is null or v_batch.direction <> 'upload' then
    raise exception using errcode = 'P0001', message = 'invalid_cash_batch';
  end if;
  if auth.uid() is not null and v_batch.profile_id <> auth.uid() then
    raise exception using errcode = '42501', message = 'permission_denied';
  end if;
  update public.sync_batches set status = 'processing', updated_at = now()
  where id = p_sync_batch_id;

  for v_mut in
    select * from public.sync_mutations m
    where m.sync_batch_id = p_sync_batch_id and m.deleted_at is null
    order by case
      when m.entity_table = 'cash_registers' then 1
      when m.entity_table = 'cash_sessions'
        and not (m.operation = 'update' and m.payload ->> 'status' = 'closed')
        then 2
      when m.entity_table = 'cash_movements' then 3
      when m.entity_table = 'cash_sessions' then 4
      else 99 end,
      m.client_sequence, m.created_at, m.id
  loop
    v_count := v_count + 1;
    if v_mut.entity_table not in (
      'cash_registers', 'cash_sessions', 'cash_movements')
    then
      v_skipped := v_skipped + 1;
      update public.sync_mutations
      set status = 'skipped', error_code = null, error_message = null,
        server_processed_at = now(), updated_at = now()
      where id = v_mut.id;
      continue;
    end if;
    if v_mut.status = 'applied' then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    begin
      if v_mut.entity_table = 'cash_movements' then
        v_result := private.apply_sync_cash_movement_mutation(v_mut.id);
      elsif v_mut.entity_table = 'cash_sessions'
        and v_mut.payload ->> 'status' = 'closed'
      then
        if v_mut.operation <> 'update' then
          raise exception using errcode = 'P0001',
            message = 'offline_closed_session_requires_recovery';
        end if;
        v_result := public.close_cash_session_authoritatively(
          v_mut.business_id,
          v_mut.branch_id,
          (v_mut.payload ->> 'cash_register_id')::uuid,
          v_mut.entity_id,
          (v_mut.payload ->> 'actual_closing_amount')::numeric,
          v_mut.payload ->> 'notes');
      else
        v_result := private.apply_sync_cash_mutation(v_mut.id);
      end if;
      v_applied := v_applied + 1;
      update public.sync_mutations
      set status = 'applied', error_code = null, error_message = null,
        server_processed_at = now(),
        metadata = coalesce(metadata, '{}'::jsonb)
          || jsonb_build_object('apply_cash_result', v_result),
        updated_at = now()
      where id = v_mut.id;
    exception when others then
      get stacked diagnostics v_code = returned_sqlstate,
        v_message = message_text;
      v_errors := v_errors + 1;
      -- Stable public reason, not SQLSTATE P0001 for known cash failures.
      if v_message not in (
        'cash_session_closed', 'permission_denied', 'invalid_scope',
        'invalid_payload', 'idempotency_conflict',
        'offline_closed_session_requires_recovery')
      then
        v_message := 'cash_mutation_error';
      end if;
      update public.sync_mutations
      set status = 'error', error_code = v_message,
        error_message = v_message, server_processed_at = now(),
        updated_at = now()
      where id = v_mut.id;
      v_messages := v_messages || jsonb_build_array(jsonb_build_object(
        'sync_mutation_id', v_mut.id, 'entity_table', v_mut.entity_table,
        'entity_id', v_mut.entity_id, 'error_code', v_message));
    end;
  end loop;
  update public.sync_batches set
    status = case when v_errors > 0 then 'partial' else 'completed' end,
    applied_count = v_applied, skipped_count = v_skipped,
    error_count = v_errors, conflict_count = 0,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'apply_cash', jsonb_build_object(
        'processed_at', now(), 'mutation_count', v_count,
        'applied_count', v_applied, 'skipped_count', v_skipped,
        'error_count', v_errors, 'errors', v_messages)),
    updated_at = now()
  where id = p_sync_batch_id;
  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id, 'mode', 'apply_cash',
    'status', case when v_errors > 0 then 'partial' else 'completed' end,
    'mutation_count', v_count, 'applied_count', v_applied,
    'skipped_count', v_skipped, 'conflict_count', 0,
    'error_count', v_errors, 'errors', v_messages);
end;
$$;

revoke all on function public.process_cash_sync_batch(uuid) from public, anon;
grant execute on function public.process_cash_sync_batch(uuid)
  to authenticated, service_role;

create or replace function public.close_cash_session_authoritatively(
  p_business_id uuid,
  p_branch_id uuid,
  p_cash_register_id uuid,
  p_cash_session_id uuid,
  p_actual_closing_amount numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_session public.cash_sessions%rowtype;
  v_cash_payments numeric(14,2) := 0;
  v_cash_adjustments numeric(14,2) := 0;
  v_inflows numeric := 0;
  v_outflows numeric := 0;
  v_expected_amount numeric(14,2);
  v_idempotent boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_business_id is null or p_branch_id is null
     or p_cash_register_id is null or p_cash_session_id is null
  then
    raise exception 'business_id, branch_id, cash_register_id and cash_session_id are required';
  end if;
  if p_actual_closing_amount is null or p_actual_closing_amount < 0 then
    raise exception 'actual_closing_amount cannot be negative';
  end if;
  if not private.has_branch_permission(p_business_id, p_branch_id, 'cash.close') then
    raise exception using errcode = '42501',
      message = 'Effective permissions do not authorize cash closing';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cash_session:' || p_cash_register_id::text, 0));
  select session.* into v_session
  from public.cash_sessions session
  join public.cash_registers register
    on register.id = session.cash_register_id
   and register.business_id = session.business_id
   and register.branch_id = session.branch_id
   and register.deleted_at is null
  where session.id = p_cash_session_id
    and session.business_id = p_business_id
    and session.branch_id = p_branch_id
    and session.cash_register_id = p_cash_register_id
    and session.deleted_at is null
  for update of session;
  if v_session.id is null then
    raise exception using errcode = '42501', message = 'Cash session is not available';
  end if;
  if v_session.status = 'closed' then
    if v_session.actual_closing_amount is distinct from p_actual_closing_amount then
      raise exception using errcode = '23505',
        message = 'Cash session was already closed with another amount';
    end if;
    v_idempotent := true;
  elsif v_session.status <> 'open' then
    raise exception 'Cash session cannot be closed from status %', v_session.status;
  else
    select coalesce(sum(payment.amount), 0) into v_cash_payments
    from public.sale_payments payment
    join public.sales sale
      on sale.id = payment.sale_id
     and sale.business_id = payment.business_id
    where sale.business_id = p_business_id
      and sale.branch_id = p_branch_id
      and sale.cash_session_id = p_cash_session_id
      and sale.deleted_at is null
      and payment.deleted_at is null
      and lower(payment.payment_method) = 'cash'
      and lower(payment.status) in ('completed', 'paid', 'approved', 'synced');
    select coalesce(sum(adjustment.amount), 0) into v_cash_adjustments
    from public.cash_session_adjustments adjustment
    where adjustment.business_id = p_business_id
      and adjustment.branch_id = p_branch_id
      and adjustment.cash_register_id = p_cash_register_id
      and adjustment.cash_session_id = p_cash_session_id
      and adjustment.adjustment_type = 'reconciled_sale_already_in_opening'
      and adjustment.deleted_at is null;
    select
      coalesce(sum(amount) filter (where direction = 'inflow'), 0),
      coalesce(sum(amount) filter (where direction = 'outflow'), 0)
    into v_inflows, v_outflows
    from public.cash_movements movement
    where movement.business_id = p_business_id
      and movement.branch_id = p_branch_id
      and movement.cash_register_id = p_cash_register_id
      and movement.cash_session_id = p_cash_session_id;
    v_expected_amount := v_session.opening_amount + v_cash_payments
      + v_inflows - v_outflows + v_cash_adjustments;
    update public.cash_sessions session
    set closed_by = v_profile_id,
      closed_at = statement_timestamp(),
      expected_closing_amount = v_expected_amount,
      actual_closing_amount = p_actual_closing_amount,
      difference_amount = p_actual_closing_amount - v_expected_amount,
      status = 'closed',
      notes = coalesce(nullif(btrim(p_notes), ''), session.notes),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where session.id = p_cash_session_id returning * into v_session;
  end if;
  return jsonb_build_object(
    'cash_session_id', v_session.id,
    'business_id', v_session.business_id,
    'branch_id', v_session.branch_id,
    'cash_register_id', v_session.cash_register_id,
    'opened_by_profile_id', v_session.opened_by,
    'closed_by_profile_id', v_session.closed_by,
    'opened_at', v_session.opened_at,
    'closed_at', v_session.closed_at,
    'opening_cash_amount', v_session.opening_amount,
    'cash_payments_amount', v_cash_payments,
    'cash_adjustments_amount', v_cash_adjustments,
    'cash_inflows_amount', v_inflows,
    'cash_outflows_amount', v_outflows,
    'expected_cash_amount', v_session.expected_closing_amount,
    'closing_cash_amount', v_session.actual_closing_amount,
    'difference_amount', v_session.difference_amount,
    'status', v_session.status,
    'version', v_session.version,
    'notes', v_session.notes,
    'created_at', v_session.created_at,
    'updated_at', v_session.updated_at,
    'idempotent', v_idempotent);
end;
$$;

commit;
