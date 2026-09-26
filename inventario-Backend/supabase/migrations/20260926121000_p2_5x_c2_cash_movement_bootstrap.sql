begin;

create function private.pull_cash_movement_bootstrap_page(
  p_business_id uuid,
  p_branch_id uuid,
  p_snapshot_at timestamptz,
  p_after_id uuid,
  p_limit integer,
  p_cash_session_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_rows jsonb;
  v_count integer;
  v_more boolean;
  v_last_id uuid;
begin
  with raw as (
    select m.id, to_jsonb(m) || jsonb_build_object(
      '_bootstrap_record_state', 'present', 'amount', m.amount::text) as payload
    from public.cash_movements m
    where m.business_id = p_business_id and m.branch_id = p_branch_id
      and m.cash_session_id = any(p_cash_session_ids)
      and m.created_at <= p_snapshot_at
      and (p_after_id is null or m.id > p_after_id)
    order by m.id limit p_limit + 1
  ), paged as (
    select * from raw order by id limit p_limit
  )
  select coalesce(jsonb_agg(payload order by id), '[]'::jsonb),
    count(*)::integer,
    (select count(*) from raw) > p_limit,
    (select id from paged order by id desc limit 1)
  into v_rows, v_count, v_more, v_last_id from paged;
  return jsonb_build_object(
    'dataset', 'cash_movements', 'rows', v_rows, 'count', v_count,
    'has_more', v_more, 'last_id', v_last_id);
end;
$$;
revoke all on function private.pull_cash_movement_bootstrap_page(
  uuid, uuid, timestamptz, uuid, integer, uuid[]) from public, anon,
  authenticated;

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
  v_profile_id uuid := auth.uid();
  v_context jsonb;
  v_permissions jsonb;
  v_bundle text := lower(btrim(coalesce(p_bundle, '')));
  v_dataset text := lower(nullif(btrim(coalesce(p_dataset, '')), ''));
  v_datasets text[];
  v_requested_datasets text[];
  v_limit integer := greatest(1, least(coalesce(p_limit_per_dataset, 500), 1000));
  v_continuation boolean := p_page_token is not null;
  v_allowed boolean;
  v_token_payload jsonb;
  v_snapshot_id uuid;
  v_snapshot_at timestamptz;
  v_after_id uuid;
  v_cash_session_ids uuid[] := array[]::uuid[];
  v_page jsonb;
  v_dataset_result jsonb;
  v_results jsonb := '{}'::jsonb;
  v_next_page_token text;
  v_has_more boolean;
  v_any_has_more boolean := false;
begin
  v_context := private.authorize_operational_device_context(
    p_business_id, p_branch_id, p_app_device_id, true);
  v_permissions := v_context -> 'effective_permissions';
  if v_bundle = 'core' then
    v_datasets := array['context']::text[];
  elsif v_bundle = 'product_operational' then
    v_datasets := array[
      'categories', 'products', 'product_barcodes',
      'product_stock_balances']::text[];
    select exists (select 1 from jsonb_array_elements_text(v_permissions) p(value)
      where p.value = any(array[
        'sales.create', 'inventory.read', 'inventory.purchase']::text[]))
    into v_allowed;
    if not v_allowed then
      raise exception 'Effective permissions do not authorize product_operational bootstrap';
    end if;
  elsif v_bundle = 'cash_pos' then
    v_datasets := array[
      'cash_registers', 'open_cash_sessions', 'cash_movements',
      'session_sales', 'session_sale_items',
      'session_sale_payments']::text[];
    select exists (select 1 from jsonb_array_elements_text(v_permissions) p(value)
      where p.value = any(array[
        'cash.read', 'cash.open', 'cash.close', 'cash.disburse',
        'cash.receive', 'sales.create']::text[]))
    into v_allowed;
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
    v_requested_datasets := case when v_dataset is null then v_datasets
      else array[v_dataset]::text[] end;
    if v_bundle = 'cash_pos' then
      select coalesce(array_agg(s.id order by s.id), array[]::uuid[])
      into v_cash_session_ids from public.cash_sessions s
      where s.business_id = p_business_id and s.branch_id = p_branch_id
        and s.status = 'open' and s.deleted_at is null
        and (s.created_at is null
          or s.created_at <= (v_snapshot_at at time zone 'UTC'));
    end if;
  else
    if v_dataset is null then
      raise exception 'dataset is required when continuing a bootstrap snapshot';
    end if;
    v_token_payload := private.decode_operational_bootstrap_page_token(
      p_page_token);
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
      v_snapshot_at := (v_token_payload ->> 'snapshot_at')::timestamptz;
      v_after_id := (v_token_payload ->> 'last_id')::uuid;
      v_limit := (v_token_payload ->> 'page_size')::integer;
      if v_limit < 1 or v_limit > 1000
         or v_snapshot_at > clock_timestamp() then
        raise exception 'Invalid operational bootstrap page token state';
      end if;
      select coalesce(array_agg(session_id order by session_id), array[]::uuid[])
      into v_cash_session_ids from (
        select value::uuid as session_id
        from jsonb_array_elements_text(
          coalesce(v_token_payload -> 'cash_session_ids', '[]'::jsonb))
      ) session_rows;
    exception when raise_exception then raise;
      when others then raise exception 'Invalid operational bootstrap page token state';
    end;
    v_requested_datasets := array[v_dataset]::text[];
  end if;
  foreach v_dataset in array v_requested_datasets loop
    v_next_page_token := null;
    if v_dataset = 'context' then
      v_page := jsonb_build_object(
        'dataset', 'context', 'rows', jsonb_build_array(v_context),
        'count', 1, 'has_more', false, 'last_id', null);
    elsif v_dataset = 'cash_movements' then
      v_page := private.pull_cash_movement_bootstrap_page(
        p_business_id, p_branch_id, v_snapshot_at, v_after_id,
        v_limit, v_cash_session_ids);
    else
      v_page := private.pull_operational_bootstrap_dataset_page(
        v_dataset, p_business_id, p_branch_id, v_snapshot_at,
        v_after_id, v_limit, v_cash_session_ids);
    end if;
    v_has_more := coalesce((v_page ->> 'has_more')::boolean, false);
    v_any_has_more := v_any_has_more or v_has_more;
    if v_has_more then
      v_next_page_token := private.encode_operational_bootstrap_page_token(
        jsonb_build_object(
          'version', 1, 'snapshot_id', v_snapshot_id,
          'snapshot_at', v_snapshot_at, 'profile_id', v_profile_id,
          'business_id', p_business_id, 'branch_id', p_branch_id,
          'app_device_id', p_app_device_id, 'bundle', v_bundle,
          'dataset', v_dataset, 'last_id', v_page ->> 'last_id',
          'page_size', v_limit,
          'cash_session_ids', to_jsonb(v_cash_session_ids)));
    end if;
    v_dataset_result := (v_page - 'last_id') || jsonb_build_object(
      'page_size', v_limit, 'complete', not v_has_more,
      'authoritative_scope_complete', not v_has_more,
      'next_page_token', v_next_page_token);
    v_results := v_results || jsonb_build_object(v_dataset, v_dataset_result);
    if v_continuation then exit; end if;
  end loop;
  return jsonb_build_object(
    'snapshot_id', v_snapshot_id, 'snapshot_at', v_snapshot_at,
    'business_id', p_business_id, 'branch_id', p_branch_id,
    'app_device_id', p_app_device_id, 'profile_id', v_profile_id,
    'bundle', v_bundle,
    'dataset_requested', case when p_dataset is null then null
      else lower(nullif(btrim(p_dataset), '')) end,
    'datasets', v_results,
    'snapshot_complete', case when v_continuation then null
      else not v_any_has_more end,
    'requested_datasets_complete', not v_any_has_more,
    'authorization_validated_at',
      v_context -> 'authorization_validated_at',
    'generated_at', clock_timestamp(),
    'sync_cursor_read', false, 'sync_cursor_advanced', false,
    'consistency', jsonb_build_object(
      'model', 'fixed_identity_window_current_values',
      'identity_cutoff', v_snapshot_at, 'keyset', 'id',
      'new_rows_after_cutoff_excluded', true,
      'values', 'current_at_page_read',
      'soft_deleted_rows',
        'included_as_tombstones_for_scoped_entity_datasets',
      'hard_delete_recovery', false));
end;
$$;

revoke all on function public.pull_operational_bootstrap_snapshot(
  uuid, uuid, uuid, text, text, integer, text) from public, anon;
grant execute on function public.pull_operational_bootstrap_snapshot(
  uuid, uuid, uuid, text, text, integer, text) to authenticated, service_role;

commit;
