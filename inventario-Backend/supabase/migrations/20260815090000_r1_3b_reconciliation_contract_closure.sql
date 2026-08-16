-- R1.3b - Close the backend contracts required by local bootstrap
-- reconciliation.
--
-- This migration adds:
--   1. a tenant-scoped inventory movement acknowledgement lookup; and
--   2. fresh, authorized bootstrap snapshots focused on one dataset.
--
-- It does not modify sync cursors and does not add client/Drift state.

begin;

create or replace function public.lookup_inventory_movement_acknowledgements(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_operations jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_context jsonb;
  v_permissions jsonb;
  v_allowed boolean;
  v_operation jsonb;
  v_results jsonb := '[]'::jsonb;

  v_client_movement_id uuid;
  v_local_idempotency_key text;
  v_source_type text;
  v_source_id uuid;
  v_source_item_id uuid;
  v_product_id uuid;
  v_quantity_change integer;
  v_remote_idempotency_key text;
  v_item_metadata_key text;
  v_parent_entity_table text;

  v_candidate_ids uuid[];
  v_candidate record;
  v_terminal_status text;
  v_status text;
  v_result jsonb;
  v_checked_at timestamp with time zone := statement_timestamp();
begin
  v_context := private.authorize_operational_device_context(
    p_business_id,
    p_branch_id,
    p_app_device_id,
    true
  );
  v_permissions := v_context -> 'effective_permissions';

  select exists (
    select 1
    from jsonb_array_elements_text(v_permissions) permission_row(value)
    where permission_row.value = any(array[
      'sales.create',
      'inventory.read',
      'inventory.purchase',
      'inventory.adjust'
    ]::text[])
  ) into v_allowed;

  if not v_allowed then
    raise exception 'Effective permissions do not authorize inventory acknowledgement lookup';
  end if;

  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'operations must be a JSON array';
  end if;

  if jsonb_array_length(p_operations) > 200 then
    raise exception 'operations exceeds the maximum of 200 entries';
  end if;

  for v_operation in
    select operation_row.value
    from jsonb_array_elements(p_operations) operation_row(value)
  loop
    if jsonb_typeof(v_operation) <> 'object' then
      raise exception 'Each acknowledgement operation must be an object';
    end if;

    begin
      v_client_movement_id := nullif(
        btrim(coalesce(v_operation ->> 'movement_id', '')),
        ''
      )::uuid;
      v_source_id := nullif(
        btrim(coalesce(v_operation ->> 'source_id', '')),
        ''
      )::uuid;
      v_source_item_id := nullif(
        btrim(coalesce(v_operation ->> 'source_item_id', '')),
        ''
      )::uuid;
      v_product_id := nullif(
        btrim(coalesce(v_operation ->> 'product_id', '')),
        ''
      )::uuid;
      v_quantity_change := nullif(
        btrim(coalesce(v_operation ->> 'quantity_change', '')),
        ''
      )::integer;
    exception when others then
      raise exception 'Invalid UUID or quantity in acknowledgement operation';
    end;

    v_local_idempotency_key := nullif(
      btrim(coalesce(v_operation ->> 'idempotency_key', '')),
      ''
    );
    v_source_type := lower(nullif(
      btrim(coalesce(v_operation ->> 'source_type', '')),
      ''
    ));

    if v_client_movement_id is null
       or v_local_idempotency_key is null
       or v_product_id is null
       or v_quantity_change is null
       or v_quantity_change = 0
       or v_source_type is null
    then
      raise exception 'movement_id, idempotency_key, source_type, product_id and non-zero quantity_change are required';
    end if;

    if length(v_local_idempotency_key) > 512 then
      raise exception 'idempotency_key exceeds 512 characters';
    end if;

    if v_source_type not in ('sale', 'purchase', 'manual_adjustment') then
      raise exception 'Unsupported acknowledgement source_type: %', v_source_type;
    end if;

    v_candidate_ids := null;
    v_terminal_status := null;
    v_remote_idempotency_key := v_local_idempotency_key;
    v_item_metadata_key := null;
    v_parent_entity_table := 'inventory_movements';

    if v_source_type in ('sale', 'purchase') then
      if v_source_id is null or v_source_item_id is null then
        raise exception 'source_id and source_item_id are required for sale or purchase acknowledgements';
      end if;

      v_remote_idempotency_key :=
        v_source_type || ':' || v_source_id::text || ':item:'
        || v_source_item_id::text;
      v_item_metadata_key := case
        when v_source_type = 'sale' then 'sale_item_id'
        else 'purchase_item_id'
      end;
      v_parent_entity_table := case
        when v_source_type = 'sale' then 'sale_items'
        else 'purchase_items'
      end;

      select array_agg(im.id order by im.id)
      into v_candidate_ids
      from public.inventory_movements im
      where im.business_id = p_business_id
        and im.branch_id = p_branch_id
        and (
          im.idempotency_key = v_remote_idempotency_key
          or (
            im.source_type = v_source_type
            and im.source_id = v_source_id
            and im.metadata ->> v_item_metadata_key = v_source_item_id::text
          )
        );
    else
      select array_agg(im.id order by im.id)
      into v_candidate_ids
      from public.inventory_movements im
      where im.business_id = p_business_id
        and im.branch_id = p_branch_id
        and (
          im.id = v_client_movement_id
          or im.idempotency_key = v_local_idempotency_key
        );
    end if;

    if coalesce(cardinality(v_candidate_ids), 0) > 1 then
      v_status := 'ambiguous';
      v_result := jsonb_build_object(
        'movement_id', v_client_movement_id,
        'status', v_status,
        'checked_at', v_checked_at
      );
    elsif coalesce(cardinality(v_candidate_ids), 0) = 1 then
      select
        im.id,
        im.product_id,
        im.quantity_change,
        im.source_type,
        im.source_id,
        im.idempotency_key
      into v_candidate
      from public.inventory_movements im
      where im.id = v_candidate_ids[1];

      if v_candidate.product_id <> v_product_id
         or v_candidate.quantity_change <> v_quantity_change
         or v_candidate.source_type <> v_source_type
         or (
           v_source_type in ('sale', 'purchase')
           and v_candidate.source_id is distinct from v_source_id
         )
         or (
           v_source_type = 'manual_adjustment'
           and (
             v_candidate.id <> v_client_movement_id
             or v_candidate.idempotency_key <> v_local_idempotency_key
           )
         )
      then
        v_status := 'ambiguous';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'checked_at', v_checked_at
        );
      else
        v_status := 'applied';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'remote_movement_id', v_candidate.id,
          'remote_idempotency_key', v_candidate.idempotency_key,
          'checked_at', v_checked_at
        );
      end if;
    else
      if v_source_type in ('sale', 'purchase') then
        select sm.status
        into v_terminal_status
        from public.sync_mutations sm
        where sm.business_id = p_business_id
          and sm.branch_id = p_branch_id
          and sm.entity_table = v_parent_entity_table
          and sm.entity_id = v_source_item_id
          and sm.status in ('conflict', 'skipped')
          and sm.deleted_at is null
        order by sm.server_processed_at desc nulls last, sm.created_at desc
        limit 1;
      else
        select sm.status
        into v_terminal_status
        from public.sync_mutations sm
        where sm.business_id = p_business_id
          and sm.branch_id = p_branch_id
          and sm.entity_table = 'inventory_movements'
          and (
            sm.entity_id = v_client_movement_id
            or sm.idempotency_key = v_local_idempotency_key
          )
          and sm.status in ('conflict', 'skipped')
          and sm.deleted_at is null
        order by sm.server_processed_at desc nulls last, sm.created_at desc
        limit 1;
      end if;

      if v_terminal_status is not null then
        v_status := 'rejected';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'remote_evidence_status', v_terminal_status,
          'checked_at', v_checked_at
        );
      else
        v_status := 'not_found';
        v_result := jsonb_build_object(
          'movement_id', v_client_movement_id,
          'status', v_status,
          'checked_at', v_checked_at
        );
      end if;
    end if;

    v_results := v_results || jsonb_build_array(v_result);
  end loop;

  return jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'app_device_id', p_app_device_id,
    'authorization_validated_at',
      v_context -> 'authorization_validated_at',
    'checked_at', v_checked_at,
    'acknowledgements', v_results
  );
end;
$$;

revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from public;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from anon;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from authenticated;
revoke all on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) from service_role;

grant execute on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) to authenticated, service_role;

comment on function public.lookup_inventory_movement_acknowledgements(
  uuid,
  uuid,
  uuid,
  jsonb
) is
'Returns minimal, tenant- and branch-scoped evidence that local inventory deltas are already represented by the immutable remote inventory ledger. Direct adjustments correlate by preserved movement ID and idempotency key; sale and purchase deltas correlate by their preserved parent/item IDs and canonical server idempotency key.';

-- Keep the single R1.2 signature. R1.3b changes only fresh-call semantics:
-- p_dataset may now select one authorized dataset in its bundle.
create or replace function public.pull_operational_bootstrap_snapshot(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_bundle text,
  p_dataset text default null,
  p_limit_per_dataset integer default 500,
  p_page_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid;
  v_context jsonb;
  v_permissions jsonb;
  v_bundle text;
  v_dataset text;
  v_datasets text[];
  v_requested_datasets text[];
  v_limit integer;
  v_continuation boolean;
  v_allowed boolean;

  v_token_payload jsonb;
  v_snapshot_id uuid;
  v_snapshot_at timestamp with time zone;
  v_after_id uuid;
  v_cash_session_ids uuid[] := array[]::uuid[];

  v_page jsonb;
  v_dataset_result jsonb;
  v_results jsonb := '{}'::jsonb;
  v_next_page_token text;
  v_has_more boolean;
  v_any_has_more boolean := false;
begin
  v_profile_id := auth.uid();
  v_bundle := lower(btrim(coalesce(p_bundle, '')));
  v_dataset := lower(nullif(btrim(coalesce(p_dataset, '')), ''));
  v_limit := greatest(1, least(coalesce(p_limit_per_dataset, 500), 1000));
  v_continuation := p_page_token is not null;

  v_context := private.authorize_operational_device_context(
    p_business_id,
    p_branch_id,
    p_app_device_id,
    true
  );
  v_permissions := v_context -> 'effective_permissions';

  if v_bundle = 'core' then
    v_datasets := array['context']::text[];
  elsif v_bundle = 'product_operational' then
    v_datasets := array[
      'categories',
      'products',
      'product_barcodes',
      'product_stock_balances'
    ]::text[];

    select exists (
      select 1
      from jsonb_array_elements_text(v_permissions) permission_row(value)
      where permission_row.value = any(array[
        'sales.create',
        'inventory.read',
        'inventory.purchase'
      ]::text[])
    ) into v_allowed;

    if not v_allowed then
      raise exception 'Effective permissions do not authorize product_operational bootstrap';
    end if;
  elsif v_bundle = 'cash_pos' then
    v_datasets := array[
      'cash_registers',
      'open_cash_sessions',
      'session_sales',
      'session_sale_items',
      'session_sale_payments'
    ]::text[];

    select exists (
      select 1
      from jsonb_array_elements_text(v_permissions) permission_row(value)
      where permission_row.value = any(array[
        'cash.read',
        'cash.open',
        'cash.close',
        'sales.create'
      ]::text[])
    ) into v_allowed;

    if not v_allowed then
      raise exception 'Effective permissions do not authorize cash_pos bootstrap';
    end if;
  else
    raise exception 'Unsupported operational bootstrap bundle: %', v_bundle;
  end if;

  if v_dataset is not null and not v_dataset = any(v_datasets) then
    raise exception 'Dataset does not belong to the requested bootstrap bundle';
  end if;

  if not v_continuation then
    v_snapshot_id := extensions.gen_random_uuid();
    v_snapshot_at := transaction_timestamp();
    v_after_id := null;
    v_requested_datasets := case
      when v_dataset is null then v_datasets
      else array[v_dataset]::text[]
    end;

    if v_bundle = 'cash_pos' then
      select coalesce(array_agg(cs.id order by cs.id), array[]::uuid[])
      into v_cash_session_ids
      from public.cash_sessions cs
      where cs.business_id = p_business_id
        and cs.branch_id = p_branch_id
        and cs.status = 'open'
        and cs.deleted_at is null
        and (
          cs.created_at is null
          or cs.created_at <= (v_snapshot_at at time zone 'UTC')
        );
    end if;
  else
    if v_dataset is null then
      raise exception 'dataset is required when continuing a bootstrap snapshot';
    end if;

    v_token_payload := private.decode_operational_bootstrap_page_token(
      p_page_token
    );

    begin
      if coalesce((v_token_payload ->> 'version')::integer, 0) <> 1
         or v_token_payload ->> 'profile_id' <> v_profile_id::text
         or v_token_payload ->> 'business_id' <> p_business_id::text
         or v_token_payload ->> 'branch_id' <> p_branch_id::text
         or v_token_payload ->> 'app_device_id' <> p_app_device_id::text
         or v_token_payload ->> 'bundle' <> v_bundle
         or v_token_payload ->> 'dataset' <> v_dataset
      then
        raise exception 'Operational bootstrap page token scope mismatch';
      end if;

      v_snapshot_id := (v_token_payload ->> 'snapshot_id')::uuid;
      v_snapshot_at := (v_token_payload ->> 'snapshot_at')::timestamp with time zone;
      v_after_id := (v_token_payload ->> 'last_id')::uuid;
      v_limit := (v_token_payload ->> 'page_size')::integer;

      if v_limit < 1 or v_limit > 1000 or v_snapshot_at > clock_timestamp() then
        raise exception 'Invalid operational bootstrap page token state';
      end if;

      select coalesce(array_agg(session_id order by session_id), array[]::uuid[])
      into v_cash_session_ids
      from (
        select value::uuid as session_id
        from jsonb_array_elements_text(
          coalesce(v_token_payload -> 'cash_session_ids', '[]'::jsonb)
        )
      ) session_rows;
    exception
      when raise_exception then raise;
      when others then
        raise exception 'Invalid operational bootstrap page token state';
    end;

    v_requested_datasets := array[v_dataset]::text[];
  end if;

  foreach v_dataset in array v_requested_datasets
  loop
    v_next_page_token := null;

    if v_dataset = 'context' then
      v_page := jsonb_build_object(
        'dataset', 'context',
        'rows', jsonb_build_array(v_context),
        'count', 1,
        'has_more', false,
        'last_id', null
      );
    else
      v_page := private.pull_operational_bootstrap_dataset_page(
        v_dataset,
        p_business_id,
        p_branch_id,
        v_snapshot_at,
        v_after_id,
        v_limit,
        v_cash_session_ids
      );
    end if;

    v_has_more := coalesce((v_page ->> 'has_more')::boolean, false);
    v_any_has_more := v_any_has_more or v_has_more;

    if v_has_more then
      v_next_page_token := private.encode_operational_bootstrap_page_token(
        jsonb_build_object(
          'version', 1,
          'snapshot_id', v_snapshot_id,
          'snapshot_at', v_snapshot_at,
          'profile_id', v_profile_id,
          'business_id', p_business_id,
          'branch_id', p_branch_id,
          'app_device_id', p_app_device_id,
          'bundle', v_bundle,
          'dataset', v_dataset,
          'last_id', v_page ->> 'last_id',
          'page_size', v_limit,
          'cash_session_ids', to_jsonb(v_cash_session_ids)
        )
      );
    end if;

    v_dataset_result := (v_page - 'last_id') || jsonb_build_object(
      'page_size', v_limit,
      'complete', not v_has_more,
      'authoritative_scope_complete', not v_has_more,
      'next_page_token', v_next_page_token
    );

    v_results := v_results || jsonb_build_object(
      v_dataset,
      v_dataset_result
    );

    if v_continuation then
      exit;
    end if;
  end loop;

  return jsonb_build_object(
    'snapshot_id', v_snapshot_id,
    'snapshot_at', v_snapshot_at,
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'app_device_id', p_app_device_id,
    'profile_id', v_profile_id,
    'bundle', v_bundle,
    'dataset_requested', case
      when p_dataset is null then null
      else lower(nullif(btrim(p_dataset), ''))
    end,
    'datasets', v_results,
    'snapshot_complete', case
      when v_continuation then null
      else not v_any_has_more
    end,
    'requested_datasets_complete', not v_any_has_more,
    'authorization_validated_at',
      v_context -> 'authorization_validated_at',
    'generated_at', clock_timestamp(),
    'sync_cursor_read', false,
    'sync_cursor_advanced', false,
    'consistency', jsonb_build_object(
      'model', 'fixed_identity_window_current_values',
      'identity_cutoff', v_snapshot_at,
      'keyset', 'id',
      'new_rows_after_cutoff_excluded', true,
      'values', 'current_at_page_read',
      'soft_deleted_rows', 'included_as_tombstones_for_scoped_entity_datasets',
      'hard_delete_recovery', false
    )
  );
end;
$$;

revoke all on function public.pull_operational_bootstrap_snapshot(
  uuid,
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) from public;
revoke all on function public.pull_operational_bootstrap_snapshot(
  uuid,
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) from anon;

grant execute on function public.pull_operational_bootstrap_snapshot(
  uuid,
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) to authenticated, service_role;

comment on function public.pull_operational_bootstrap_snapshot(
  uuid,
  uuid,
  uuid,
  text,
  text,
  integer,
  text
) is
'Returns authorized, cursor-independent full-bundle or single-dataset operational recovery snapshots with signed dataset-bound UUID keyset tokens and a fixed identity window.';

-- R1.3c+ client contracts (documentation only; no Drift changes here):
--
-- * Operational outbox domains cash, pos, purchases and inventory must support
--   business_id + branch_id + domain filtering. Business-scoped domains such
--   as catalog must remain business-scoped.
-- * The offline authorization authority is a projection keyed by
--   profile_id + business_id + branch_id and stores effective_permissions,
--   effective_roles, applicable_membership_ids, authorization_validated_at,
--   snapshot_id and status.
-- * Local stock balance reconciliation uses the unique semantic scope
--   business_id + branch_id + product_id. It stores the remote balance ID and
--   remote/base quantities/cost/provenance separately from operative fields,
--   plus deleted_at/tombstone state. A snapshot applier looks up by scope, not
--   by its local primary key.
-- * Cash recovery conflict rules are:
--     remote open A + local dirty open B for the same register => blocker;
--     remote open A + local dirty A => reconcile through identity/outbox;
--     remote none + local dirty open B => preserve B.

commit;
