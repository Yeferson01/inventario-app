begin;

alter table public.sync_conflicts
  drop constraint if exists sync_conflicts_resolution_strategy_check;
alter table public.sync_conflicts
  add constraint sync_conflicts_resolution_strategy_check
  check (
    resolution_strategy in (
      'server_wins',
      'client_retry',
      'manual_review',
      'manual_resolution',
      'ignored',
      'reconcile_to_open_cash_session',
      'sale_did_not_occur'
    )
  )
  not valid;
alter table public.sync_conflicts
  validate constraint sync_conflicts_resolution_strategy_check;

create or replace function public.resolve_unmaterialized_sale_did_not_occur(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_sale_id uuid,
  p_sync_conflict_id uuid,
  p_idempotency_key text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_conflict public.sync_conflicts%rowtype;
  v_sale_mutation public.sync_mutations%rowtype;
  v_idempotency_key text := btrim(coalesce(p_idempotency_key, ''));
  v_reason text := btrim(coalesce(p_reason, ''));
  v_terminalized integer := 0;
  v_idempotent boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null
     or p_branch_id is null
     or p_app_device_id is null
     or p_sale_id is null
     or p_sync_conflict_id is null
  then
    raise exception using
      errcode = '22023',
      message = 'business_id, branch_id, app_device_id, sale_id and sync_conflict_id are required';
  end if;

  if v_idempotency_key = '' or v_reason = '' then
    raise exception using
      errcode = '22023',
      message = 'idempotency_key and reason are required';
  end if;

  if not exists (
    select 1
    from public.businesses business
    join public.branches branch
      on branch.business_id = business.id
    where business.id = p_business_id
      and branch.id = p_branch_id
      and business.deleted_at is null
      and branch.deleted_at is null
      and coalesce(business.status, 'active') = 'active'
      and coalesce(branch.status, 'active') = 'active'
  ) or not private.has_branch_access(p_business_id, p_branch_id) then
    raise exception using
      errcode = '42501',
      message = 'Operational context is not available';
  end if;

  if not exists (
    select 1
    from public.app_devices device
    where device.id = p_app_device_id
      and device.business_id = p_business_id
      and device.branch_id = p_branch_id
      and device.profile_id = v_profile_id
      and device.status = 'active'
      and device.deleted_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'app_device is not active for this profile and branch';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'sale_did_not_occur:' || p_business_id::text || ':' || p_sale_id::text,
      0
    )
  );

  select conflict.*
  into v_conflict
  from public.sync_conflicts conflict
  where conflict.id = p_sync_conflict_id
  for update;

  if v_conflict.id is null
     or v_conflict.business_id is distinct from p_business_id
     or v_conflict.branch_id is distinct from p_branch_id
     or v_conflict.profile_id is distinct from v_profile_id
     or v_conflict.entity_table is distinct from 'sales'
     or v_conflict.entity_id is distinct from p_sale_id
     or v_conflict.deleted_at is not null
     or v_conflict.metadata ->> 'sale_id' is distinct from p_sale_id::text
     or v_conflict.metadata ->> 'rule' is distinct from 'sale_cash_session_invalid'
     or v_conflict.metadata ->> 'reason' is distinct from 'closed'
  then
    raise exception using
      errcode = '42501',
      message = 'Expected Sale conflict is not available';
  end if;

  if v_conflict.status <> 'open' then
    if v_conflict.status = 'resolved'
       and v_conflict.resolution_strategy = 'sale_did_not_occur'
       and v_conflict.metadata ->> 'discard_idempotency_key' = v_idempotency_key
       and v_conflict.metadata ->> 'discard_reason' = v_reason
       and v_conflict.metadata ->> 'sale_did_not_occur' = 'true'
    then
      v_idempotent := true;
      v_terminalized := coalesce(
        nullif(v_conflict.metadata ->> 'discard_mutations_terminalized', '')::integer,
        0
      );
    else
      raise exception using
        errcode = '23505',
        message = 'Sale conflict was already resolved by another decision';
    end if;
  end if;

  if exists (select 1 from public.sales sale where sale.id = p_sale_id)
     or exists (
       select 1 from public.sale_items item where item.sale_id = p_sale_id
     )
     or exists (
       select 1 from public.sale_payments payment where payment.sale_id = p_sale_id
     )
     or exists (
       select 1
       from public.inventory_movements movement
       where movement.source_type = 'sale'
         and movement.source_id = p_sale_id
     )
  then
    raise exception using
      errcode = '23514',
      message = 'Remote Sale evidence exists; did-not-occur finalization rejected';
  end if;

  select mutation.*
  into v_sale_mutation
  from public.sync_mutations mutation
  where mutation.id = v_conflict.sync_mutation_id
  for update;

  if v_sale_mutation.id is null
     or v_sale_mutation.business_id is distinct from p_business_id
     or v_sale_mutation.branch_id is distinct from p_branch_id
     or v_sale_mutation.profile_id is distinct from v_profile_id
     or v_sale_mutation.entity_table is distinct from 'sales'
     or v_sale_mutation.entity_id is distinct from p_sale_id
     or v_sale_mutation.operation not in ('insert', 'upsert')
     or v_sale_mutation.deleted_at is not null
  then
    raise exception 'Original Sale mutation is missing or inconsistent';
  end if;

  perform 1
  from public.sync_mutations mutation
  where mutation.business_id = p_business_id
    and mutation.branch_id is not distinct from p_branch_id
    and mutation.deleted_at is null
    and (
      (mutation.entity_table = 'sales' and mutation.entity_id = p_sale_id)
      or (
        mutation.entity_table in ('sale_items', 'sale_payments')
        and mutation.payload ->> 'sale_id' = p_sale_id::text
      )
    )
  for update;

  if exists (
    select 1
    from public.sync_mutations mutation
    where mutation.business_id = p_business_id
      and mutation.branch_id is not distinct from p_branch_id
      and mutation.deleted_at is null
      and (
        (mutation.entity_table = 'sales' and mutation.entity_id = p_sale_id)
        or (
          mutation.entity_table in ('sale_items', 'sale_payments')
          and mutation.payload ->> 'sale_id' = p_sale_id::text
        )
      )
      and (
        mutation.sync_batch_id <> v_sale_mutation.sync_batch_id
        or mutation.status in ('processing', 'applied')
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'A Sale mutation can still materialize or has already been applied';
  end if;

  if not v_idempotent then
    update public.sync_mutations mutation
    set
      status = 'skipped',
      server_processed_at = coalesce(mutation.server_processed_at, statement_timestamp()),
      error_code = 'superseded_by_sale_did_not_occur',
      error_message = 'The user authoritatively confirmed that the Sale did not occur.',
      metadata = coalesce(mutation.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'resolution_strategy', 'sale_did_not_occur',
          'sale_id', p_sale_id,
          'sync_conflict_id', p_sync_conflict_id,
          'discard_idempotency_key', v_idempotency_key,
          'discard_confirmed_at', statement_timestamp(),
          'discard_confirmed_by', v_profile_id,
          'discard_confirmed_app_device_id', p_app_device_id
        ),
      updated_at = statement_timestamp(),
      updated_by = v_profile_id
    where mutation.business_id = p_business_id
      and mutation.branch_id is not distinct from p_branch_id
      and mutation.sync_batch_id = v_sale_mutation.sync_batch_id
      and mutation.deleted_at is null
      and (
        (mutation.entity_table = 'sales' and mutation.entity_id = p_sale_id)
        or (
          mutation.entity_table in ('sale_items', 'sale_payments')
          and mutation.payload ->> 'sale_id' = p_sale_id::text
        )
      );
    get diagnostics v_terminalized = row_count;

    update public.sync_conflicts conflict
    set
      status = 'resolved',
      resolved_at = statement_timestamp(),
      resolved_by = v_profile_id,
      resolution_strategy = 'sale_did_not_occur',
      resolution_notes = v_reason,
      resolved_payload = jsonb_build_object(
        'sale_id', p_sale_id,
        'sale_did_not_occur', true,
        'remote_materialization_found', false
      ),
      metadata = coalesce(conflict.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'resolution_strategy', 'sale_did_not_occur',
          'sale_did_not_occur', true,
          'discard_confirmed_at', statement_timestamp(),
          'discard_confirmed_by', v_profile_id,
          'discard_confirmed_app_device_id', p_app_device_id,
          'discard_reason', v_reason,
          'discard_idempotency_key', v_idempotency_key,
          'discard_mutations_terminalized', v_terminalized
        ),
      updated_at = statement_timestamp(),
      updated_by = v_profile_id
    where conflict.id = p_sync_conflict_id;

    update public.sync_batches batch
    set
      metadata = coalesce(batch.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'sale_did_not_occur', true,
          'discarded_sale_id', p_sale_id,
          'discard_sync_conflict_id', p_sync_conflict_id,
          'discard_idempotency_key', v_idempotency_key
        ),
      updated_at = statement_timestamp(),
      updated_by = v_profile_id
    where batch.id = v_sale_mutation.sync_batch_id;

    perform private.recalculate_sync_batch_counts(v_sale_mutation.sync_batch_id);
    perform private.finalize_sync_batch_from_counts(v_sale_mutation.sync_batch_id);

    insert into public.activity_logs (
      id,
      business_id,
      user_id,
      action,
      affected_table,
      record_id,
      metadata,
      created_at
    ) values (
      extensions.gen_random_uuid(),
      p_business_id,
      v_profile_id,
      'SALE_DID_NOT_OCCUR_CONFIRMED',
      'sync_conflicts',
      p_sync_conflict_id,
      jsonb_build_object(
        'branch_id', p_branch_id,
        'sale_id', p_sale_id,
        'app_device_id', p_app_device_id,
        'idempotency_key', v_idempotency_key,
        'mutations_terminalized', v_terminalized
      ),
      statement_timestamp()
    );
  end if;

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'sale_id', p_sale_id,
    'sync_conflict_id', p_sync_conflict_id,
    'status', 'resolved',
    'resolution_strategy', 'sale_did_not_occur',
    'idempotency_key', v_idempotency_key,
    'mutations_terminalized', v_terminalized,
    'idempotent', v_idempotent
  );
end;
$$;

comment on function public.resolve_unmaterialized_sale_did_not_occur(
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text
)
is 'Atomically proves that a rejected Sale was never materialized, terminalizes its remote mutations and resolves its expected cash-session conflict as sale_did_not_occur.';

revoke all on function public.resolve_unmaterialized_sale_did_not_occur(
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text
)
from public, anon, authenticated;
grant execute on function public.resolve_unmaterialized_sale_did_not_occur(
  uuid,
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text
)
to authenticated, service_role;

commit;
