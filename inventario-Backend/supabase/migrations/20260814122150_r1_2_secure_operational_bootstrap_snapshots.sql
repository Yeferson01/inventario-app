-- R1.2 - Secure, cursor-independent operational bootstrap snapshots.
--
-- This migration adds a dedicated recovery contract. It does not read or
-- advance sync_cursors and it does not reuse pull_sync_changes_v2 as a full
-- bootstrap mechanism.

begin;

-- A database-local signing key keeps page tokens stateless while preventing a
-- client from changing snapshot, tenant, device, bundle, dataset, or keyset
-- state. No snapshot session/checkpoint rows are persisted.
create table if not exists private.operational_bootstrap_token_keys (
  key_id smallint primary key,
  secret bytea not null,
  created_at timestamp with time zone not null default now(),
  constraint operational_bootstrap_token_keys_singleton
    check (key_id = 1),
  constraint operational_bootstrap_token_keys_secret_length
    check (octet_length(secret) >= 32)
);

insert into private.operational_bootstrap_token_keys (key_id, secret)
values (1, extensions.gen_random_bytes(32))
on conflict (key_id) do nothing;

revoke all on table private.operational_bootstrap_token_keys from public;
revoke all on table private.operational_bootstrap_token_keys from anon;
revoke all on table private.operational_bootstrap_token_keys from authenticated;
revoke all on table private.operational_bootstrap_token_keys from service_role;

comment on table private.operational_bootstrap_token_keys
is 'Private singleton HMAC key for stateless R1.2 bootstrap page tokens.';

create or replace function private.encode_operational_bootstrap_page_token(
  p_payload jsonb
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secret bytea;
  v_payload_hex text;
  v_signature text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Operational bootstrap token payload must be an object';
  end if;

  select k.secret
  into v_secret
  from private.operational_bootstrap_token_keys k
  where k.key_id = 1;

  if v_secret is null then
    raise exception 'Operational bootstrap token key is not configured';
  end if;

  v_payload_hex := encode(
    convert_to(p_payload::text, 'UTF8'),
    'hex'
  );
  v_signature := encode(
    extensions.hmac(
      convert_to(v_payload_hex, 'UTF8'),
      v_secret,
      'sha256'
    ),
    'hex'
  );

  return v_payload_hex || '.' || v_signature;
end;
$$;

revoke all on function private.encode_operational_bootstrap_page_token(jsonb)
from public;
revoke all on function private.encode_operational_bootstrap_page_token(jsonb)
from anon;
revoke all on function private.encode_operational_bootstrap_page_token(jsonb)
from authenticated;
revoke all on function private.encode_operational_bootstrap_page_token(jsonb)
from service_role;

create or replace function private.decode_operational_bootstrap_page_token(
  p_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secret bytea;
  v_payload_hex text;
  v_provided_signature text;
  v_expected_signature text;
  v_payload jsonb;
begin
  if p_token is null
     or length(p_token) > 16384
     or p_token !~ '^[0-9a-f]+\.[0-9a-f]{64}$'
  then
    raise exception 'Invalid operational bootstrap page token';
  end if;

  v_payload_hex := split_part(p_token, '.', 1);
  v_provided_signature := split_part(p_token, '.', 2);

  select k.secret
  into v_secret
  from private.operational_bootstrap_token_keys k
  where k.key_id = 1;

  if v_secret is null then
    raise exception 'Operational bootstrap token key is not configured';
  end if;

  v_expected_signature := encode(
    extensions.hmac(
      convert_to(v_payload_hex, 'UTF8'),
      v_secret,
      'sha256'
    ),
    'hex'
  );

  if v_provided_signature <> v_expected_signature then
    raise exception 'Invalid operational bootstrap page token';
  end if;

  begin
    v_payload := convert_from(decode(v_payload_hex, 'hex'), 'UTF8')::jsonb;
  exception when others then
    raise exception 'Invalid operational bootstrap page token';
  end;

  if jsonb_typeof(v_payload) <> 'object' then
    raise exception 'Invalid operational bootstrap page token';
  end if;

  return v_payload;
end;
$$;

revoke all on function private.decode_operational_bootstrap_page_token(text)
from public;
revoke all on function private.decode_operational_bootstrap_page_token(text)
from anon;
revoke all on function private.decode_operational_bootstrap_page_token(text)
from authenticated;
revoke all on function private.decode_operational_bootstrap_page_token(text)
from service_role;

-- Shared authorization boundary. Bootstrap requires the caller's own device;
-- the hardened incremental pull may retain its established administrative
-- device-inspection exception by passing p_require_own_device = false.
create or replace function private.authorize_operational_device_context(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_require_own_device boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_business public.businesses%rowtype;
  v_branch public.branches%rowtype;
  v_device public.app_devices%rowtype;
  v_memberships jsonb;
  v_roles jsonb;
  v_permissions jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if not exists (
    select 1 from public.profiles p where p.id = v_profile_id
  ) then
    raise exception 'Authenticated profile does not exist';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if p_branch_id is null then
    raise exception 'branch_id is required';
  end if;

  if p_app_device_id is null then
    raise exception 'app_device_id is required';
  end if;

  select b.*
  into v_business
  from public.businesses b
  where b.id = p_business_id;

  if v_business.id is null
     or v_business.deleted_at is not null
     or coalesce(v_business.status, 'active') <> 'active'
  then
    raise exception 'Business does not exist or is not active';
  end if;

  select br.*
  into v_branch
  from public.branches br
  where br.id = p_branch_id;

  if v_branch.id is null then
    raise exception 'Branch does not exist';
  end if;

  if v_branch.business_id <> p_business_id then
    raise exception 'Branch does not belong to this business';
  end if;

  if v_branch.deleted_at is not null
     or coalesce(v_branch.status, 'active') <> 'active'
  then
    raise exception 'Branch is inactive or deleted';
  end if;

  if not exists (
    select 1
    from public.business_members bm
    where bm.profile_id = v_profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (bm.branch_id is null or bm.branch_id = p_branch_id)
  ) then
    raise exception 'No active membership grants access to this business and branch';
  end if;

  select ad.*
  into v_device
  from public.app_devices ad
  where ad.id = p_app_device_id;

  if v_device.id is null then
    raise exception 'app_device not found';
  end if;

  if v_device.business_id <> p_business_id then
    raise exception 'app_device does not belong to this business';
  end if;

  if v_device.deleted_at is not null or v_device.status <> 'active' then
    raise exception 'app_device is inactive, blocked, or deleted';
  end if;

  if v_device.branch_id is null or v_device.branch_id <> p_branch_id then
    raise exception 'app_device is not registered for the requested branch';
  end if;

  if not exists (
    select 1
    from public.business_members bm
    where bm.profile_id = v_device.profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (bm.branch_id is null or bm.branch_id = p_branch_id)
  ) then
    raise exception 'app_device profile no longer has active branch access';
  end if;

  if coalesce(p_require_own_device, true) then
    if v_device.profile_id <> v_profile_id then
      raise exception 'app_device does not belong to the authenticated profile';
    end if;
  elsif v_device.profile_id <> v_profile_id
        and not (
          private.has_business_permission(p_business_id, 'settings.business')
          or private.has_business_permission(
            p_business_id,
            'security_events.read'
          )
        )
  then
    raise exception 'Insufficient permission to use this app_device';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(m) order by m.created_at, m.id),
    '[]'::jsonb
  )
  into v_memberships
  from public.business_members m
  where m.profile_id = v_profile_id
    and m.business_id = p_business_id
    and m.status = 'active'
    and m.deleted_at is null
    and (m.branch_id is null or m.branch_id = p_branch_id);

  select coalesce(
    jsonb_agg(role_rows.payload order by role_rows.role_name, role_rows.role_id),
    '[]'::jsonb
  )
  into v_roles
  from (
    select
      r.id as role_id,
      r.name as role_name,
      jsonb_build_object(
        'role_id', r.id,
        'role_name', r.name,
        'business_id', r.business_id,
        'is_system_role', r.is_system_role
      ) as payload
    from public.business_members bm
    join public.roles r
      on r.id = bm.role_id
     and r.deleted_at is null
     and (r.business_id is null or r.business_id = p_business_id)
    where bm.profile_id = v_profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (bm.branch_id is null or bm.branch_id = p_branch_id)
    group by r.id, r.name, r.business_id, r.is_system_role
  ) role_rows;

  select coalesce(
    jsonb_agg(permission_rows.permission_key order by permission_rows.permission_key),
    '[]'::jsonb
  )
  into v_permissions
  from (
    select distinct p.key as permission_key
    from public.business_members bm
    join public.roles r
      on r.id = bm.role_id
     and r.deleted_at is null
     and (r.business_id is null or r.business_id = p_business_id)
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where bm.profile_id = v_profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (bm.branch_id is null or bm.branch_id = p_branch_id)
  ) permission_rows;

  return jsonb_build_object(
    'profile_id', v_profile_id,
    'business', to_jsonb(v_business),
    'branch', to_jsonb(v_branch),
    'app_device', to_jsonb(v_device),
    'memberships', v_memberships,
    'effective_roles', v_roles,
    'effective_permissions', v_permissions,
    'authorization_validated_at', statement_timestamp()
  );
end;
$$;

revoke all on function private.authorize_operational_device_context(
  uuid,
  uuid,
  uuid,
  boolean
) from public;
revoke all on function private.authorize_operational_device_context(
  uuid,
  uuid,
  uuid,
  boolean
) from anon;
revoke all on function private.authorize_operational_device_context(
  uuid,
  uuid,
  uuid,
  boolean
) from authenticated;
revoke all on function private.authorize_operational_device_context(
  uuid,
  uuid,
  uuid,
  boolean
) from service_role;

comment on function private.authorize_operational_device_context(
  uuid,
  uuid,
  uuid,
  boolean
) is
'Revalidates auth, profile, active membership, active business/branch, and app-device scope for every operational bootstrap or hardened pull page.';

-- Keyset page reader. Every selectable dataset is hardcoded below; no table or
-- predicate supplied by a client reaches dynamic SQL.
create or replace function private.pull_operational_bootstrap_dataset_page(
  p_dataset text,
  p_business_id uuid,
  p_branch_id uuid,
  p_snapshot_at timestamp with time zone,
  p_after_id uuid,
  p_limit integer,
  p_cash_session_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_dataset text;
  v_from_sql text;
  v_where_sql text;
  v_snapshot_sql text;
  v_row_expression text;
  v_sql text;
  v_limit integer;
  v_rows jsonb;
  v_count integer;
  v_has_more boolean;
  v_last_id uuid;
begin
  v_dataset := lower(btrim(coalesce(p_dataset, '')));
  v_limit := greatest(1, least(coalesce(p_limit, 500), 1000));
  v_row_expression :=
    'to_jsonb(q) || jsonb_build_object(''_bootstrap_record_state'', '
    || 'case when q.deleted_at is null then ''present'' else ''tombstone'' end)';

  if v_dataset = 'categories' then
    v_from_sql := 'public.categories q';
    v_where_sql := 'q.business_id = $1';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'products' then
    v_from_sql := 'public.products q';
    v_where_sql := 'q.business_id = $1';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'product_barcodes' then
    v_from_sql := 'public.product_barcodes q';
    v_where_sql := $predicate$
      (
        (q.scope = 'business' and q.business_id = $1)
        or (
          q.scope = 'global'
          and exists (
            select 1
            from public.products p
            where p.business_id = $1
              and p.master_product_id = q.master_product_id
              and (
                p.created_at is null
                or p.created_at <= ($3 at time zone 'UTC')
              )
          )
        )
      )
    $predicate$;
    v_snapshot_sql := 'q.created_at <= $3';
  elsif v_dataset = 'product_stock_balances' then
    v_from_sql := 'public.product_stock_balances q';
    v_where_sql := 'q.business_id = $1 and q.branch_id = $2';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'cash_registers' then
    v_from_sql := 'public.cash_registers q';
    v_where_sql := 'q.business_id = $1 and q.branch_id = $2';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'open_cash_sessions' then
    v_from_sql := 'public.cash_sessions q';
    v_where_sql :=
      'q.business_id = $1 and q.branch_id = $2 and q.id = any($6)';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
    v_row_expression :=
      'to_jsonb(q) || jsonb_build_object('
      || '''opened_by_profile_id'', q.opened_by, '
      || '''closed_by_profile_id'', q.closed_by, '
      || '''opening_cash_amount'', q.opening_amount, '
      || '''expected_cash_amount'', q.expected_closing_amount, '
      || '''closing_cash_amount'', q.actual_closing_amount, '
      || '''_bootstrap_record_state'', '
      || 'case when q.deleted_at is null then ''present'' else ''tombstone'' end)';
  elsif v_dataset = 'session_sales' then
    v_from_sql := 'public.sales q';
    v_where_sql :=
      'q.business_id = $1 and q.branch_id = $2 '
      || 'and q.cash_session_id = any($6)';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'session_sale_items' then
    v_from_sql :=
      'public.sale_items q join public.sales s on s.id = q.sale_id';
    v_where_sql :=
      's.business_id = $1 and s.branch_id = $2 '
      || 'and s.cash_session_id = any($6)';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  elsif v_dataset = 'session_sale_payments' then
    v_from_sql :=
      'public.sale_payments q join public.sales s on s.id = q.sale_id';
    v_where_sql :=
      's.business_id = $1 and s.branch_id = $2 '
      || 'and s.cash_session_id = any($6)';
    v_snapshot_sql :=
      '(q.created_at is null or q.created_at <= ($3 at time zone ''UTC''))';
  else
    raise exception 'Dataset % is not allowed for operational bootstrap', v_dataset;
  end if;

  v_sql := format(
    $sql$
      with raw as (
        select
          q.id as __bootstrap_id,
          (%1$s) as payload
        from %2$s
        where (%3$s)
          and (%4$s)
          and ($4 is null or q.id > $4)
        order by q.id
        limit ($5 + 1)
      ),
      paged as (
        select *
        from raw
        order by __bootstrap_id
        limit $5
      )
      select
        coalesce(
          jsonb_agg(payload order by __bootstrap_id),
          '[]'::jsonb
        ),
        count(*)::integer,
        (select count(*) from raw) > $5,
        (
          select __bootstrap_id
          from paged
          order by __bootstrap_id desc
          limit 1
        )
      from paged
    $sql$,
    v_row_expression,
    v_from_sql,
    v_where_sql,
    v_snapshot_sql
  );

  execute v_sql
  using
    p_business_id,
    p_branch_id,
    p_snapshot_at,
    p_after_id,
    v_limit,
    coalesce(p_cash_session_ids, array[]::uuid[])
  into v_rows, v_count, v_has_more, v_last_id;

  return jsonb_build_object(
    'dataset', v_dataset,
    'rows', coalesce(v_rows, '[]'::jsonb),
    'count', coalesce(v_count, 0),
    'has_more', coalesce(v_has_more, false),
    'last_id', v_last_id
  );
end;
$$;

revoke all on function private.pull_operational_bootstrap_dataset_page(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  uuid,
  integer,
  uuid[]
) from public;
revoke all on function private.pull_operational_bootstrap_dataset_page(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  uuid,
  integer,
  uuid[]
) from anon;
revoke all on function private.pull_operational_bootstrap_dataset_page(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  uuid,
  integer,
  uuid[]
) from authenticated;
revoke all on function private.pull_operational_bootstrap_dataset_page(
  text,
  uuid,
  uuid,
  timestamp with time zone,
  uuid,
  integer,
  uuid[]
) from service_role;

-- Full-scope/tombstone keyset indexes. Existing operational partial indexes
-- remain useful for live screens; these include deleted rows because recovery
-- must be able to reconcile tombstones.
create index if not exists idx_bootstrap_categories_business_id
on public.categories (business_id, id);

create index if not exists idx_bootstrap_products_business_id
on public.products (business_id, id);

create index if not exists idx_bootstrap_products_business_master_id
on public.products (business_id, master_product_id, id);

create index if not exists idx_bootstrap_product_barcodes_business_id
on public.product_barcodes (business_id, id);

create index if not exists idx_bootstrap_product_barcodes_master_id
on public.product_barcodes (master_product_id, id);

create index if not exists idx_bootstrap_balances_business_branch_id
on public.product_stock_balances (business_id, branch_id, id);

create index if not exists idx_bootstrap_cash_registers_business_branch_id
on public.cash_registers (business_id, branch_id, id);

create index if not exists idx_bootstrap_open_cash_sessions_branch_id
on public.cash_sessions (business_id, branch_id, status, id)
where deleted_at is null;

create index if not exists idx_bootstrap_sales_cash_session_id
on public.sales (cash_session_id, id);

create index if not exists idx_bootstrap_sale_items_sale_id
on public.sale_items (sale_id, id);

create index if not exists idx_bootstrap_sale_payments_sale_id
on public.sale_payments (sale_id, id);

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

  if not v_continuation then
    if v_dataset is not null then
      raise exception 'dataset must be omitted when starting a bootstrap snapshot';
    end if;

    v_snapshot_id := extensions.gen_random_uuid();
    v_snapshot_at := transaction_timestamp();
    v_after_id := null;
    v_requested_datasets := v_datasets;

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

    if not v_dataset = any(v_datasets) then
      raise exception 'Dataset does not belong to the requested bootstrap bundle';
    end if;

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

    -- A continuation token advances exactly one dataset.
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
    'dataset_requested', case when v_continuation then v_dataset else null end,
    'datasets', v_results,
    -- A continuation advances one dataset only, so it cannot assert that every
    -- dataset in the bundle has also been exhausted by the client.
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
'Returns authorized, cursor-independent core/product_operational/cash_pos recovery snapshots with signed dataset-bound UUID keyset tokens and a fixed identity window.';

commit;
