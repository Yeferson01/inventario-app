-- CATALOG-2B - Stable, resumable master catalog delta windows.
-- Keeps the public RPC signature intact while replacing the unsigned keyset
-- token with a server-signed token bound to tenant, cursor, tombstone mode and
-- window upper bound.

create or replace function public.pull_product_catalog_delta(
  p_business_id uuid,
  p_since_updated_at timestamptz default null,
  p_limit integer default 1000,
  p_page_token jsonb default '{}'::jsonb,
  p_include_deleted boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_limit integer;
  v_since timestamptz;
  v_window_upper_bound timestamptz;

  v_page_token jsonb;
  v_token_payload jsonb;
  v_token_updated_at timestamptz;
  v_token_entity_type text;
  v_token_id text;

  v_records jsonb;
  v_returned_count integer;
  v_has_more boolean;
  v_next_page_token jsonb;
  v_next_token_payload jsonb;

  v_current_catalog_version bigint;
  v_counts_by_entity jsonb;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if not private.is_business_member(p_business_id) then
    raise exception 'Insufficient permission to pull product catalog for this business';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 1000), 1), 5000);
  v_since := coalesce(
    p_since_updated_at,
    '1970-01-01 00:00:00+00'::timestamptz
  );
  v_page_token := coalesce(p_page_token, '{}'::jsonb);

  if jsonb_typeof(v_page_token) <> 'object' then
    raise exception using
      errcode = '22023',
      message = 'Invalid catalog page token';
  end if;

  if jsonb_object_length(v_page_token) = 0 then
    v_window_upper_bound := clock_timestamp();
  else
    if coalesce(v_page_token->>'token_version', '') <> '1'
       or nullif(v_page_token->>'token', '') is null
    then
      raise exception using
        errcode = '22023',
        message = 'Invalid catalog page token';
    end if;

    begin
      v_token_payload := private.decode_operational_bootstrap_page_token(
        v_page_token->>'token'
      );

      if coalesce(v_token_payload->>'token_version', '') <> '1'
         or v_token_payload->>'business_id' <> p_business_id::text
         or (v_token_payload->>'since_updated_at')::timestamptz <> v_since
         or (v_token_payload->>'include_deleted')::boolean
              <> coalesce(p_include_deleted, false)
      then
        raise exception 'token binding mismatch';
      end if;

      v_window_upper_bound :=
        (v_token_payload->>'window_upper_bound')::timestamptz;
      v_token_updated_at :=
        (v_token_payload->>'updated_at')::timestamptz;
      v_token_entity_type := nullif(v_token_payload->>'entity_type', '');
      v_token_id := nullif(v_token_payload->>'id', '');

      if v_window_upper_bound is null
         or v_token_updated_at is null
         or v_token_entity_type is null
         or v_token_id is null
      then
        raise exception 'token keyset is incomplete';
      end if;
    exception when others then
      raise exception using
        errcode = '22023',
        message = 'Invalid catalog page token';
    end;
  end if;

  select coalesce(max(m.catalog_version), 0)
  into v_current_catalog_version
  from public.master_products_catalog m
  where p_include_deleted = true or m.deleted_at is null;

  with records as (
    select
      'master_product'::text as entity_type,
      m.id as record_id,
      m.updated_at,
      jsonb_build_object(
        'id', m.id,
        'barcode', m.barcode,
        'gtin', m.gtin,
        'barcode_normalized', m.barcode_normalized,
        'name', coalesce(m.name, m.product_name),
        'product_name', m.product_name,
        'normalized_name', m.normalized_name,
        'brand', m.brand,
        'manufacturer', m.manufacturer,
        'category_name', coalesce(m.category_name, m.category),
        'subcategory_name', m.subcategory_name,
        'package_size', m.package_size,
        'package_unit', m.package_unit,
        'unit_type', coalesce(m.unit_type, m.unit),
        'has_image', coalesce(m.has_image, false),
        'image_thumb_url', m.image_thumb_url,
        'image_hash', m.image_hash,
        'source', m.source,
        'verification_status', m.verification_status,
        'confidence_score', m.confidence_score,
        'catalog_version', m.catalog_version,
        'sync_status', m.sync_status,
        'version', m.version,
        'updated_at', m.updated_at,
        'deleted_at', m.deleted_at
      ) as payload
    from public.master_products_catalog m
    where m.updated_at > v_since
      and m.updated_at <= v_window_upper_bound
      and (p_include_deleted = true or m.deleted_at is null)
      and coalesce(m.sync_status, 'synced') = 'synced'

    union all

    select
      'global_barcode'::text as entity_type,
      pb.id as record_id,
      pb.updated_at,
      jsonb_build_object(
        'id', pb.id,
        'scope', pb.scope,
        'business_id', null,
        'product_id', null,
        'master_product_id', pb.master_product_id,
        'barcode', pb.barcode,
        'barcode_normalized', pb.barcode_normalized,
        'barcode_type', pb.barcode_type,
        'is_primary', pb.is_primary,
        'status', pb.status,
        'source', pb.source,
        'confidence_score', pb.confidence_score,
        'sync_status', pb.sync_status,
        'version', pb.version,
        'updated_at', pb.updated_at,
        'deleted_at', pb.deleted_at
      ) as payload
    from public.product_barcodes pb
    where pb.scope = 'global'
      and pb.updated_at > v_since
      and pb.updated_at <= v_window_upper_bound
      and (p_include_deleted = true or pb.deleted_at is null)

    union all

    select
      'business_barcode'::text as entity_type,
      pb.id as record_id,
      pb.updated_at,
      jsonb_build_object(
        'id', pb.id,
        'scope', pb.scope,
        'business_id', pb.business_id,
        'product_id', pb.product_id,
        'master_product_id', pb.master_product_id,
        'barcode', pb.barcode,
        'barcode_normalized', pb.barcode_normalized,
        'barcode_type', pb.barcode_type,
        'is_primary', pb.is_primary,
        'status', pb.status,
        'source', pb.source,
        'confidence_score', pb.confidence_score,
        'sync_status', pb.sync_status,
        'version', pb.version,
        'updated_at', pb.updated_at,
        'deleted_at', pb.deleted_at
      ) as payload
    from public.product_barcodes pb
    where pb.scope = 'business'
      and pb.business_id = p_business_id
      and pb.updated_at > v_since
      and pb.updated_at <= v_window_upper_bound
      and (p_include_deleted = true or pb.deleted_at is null)
  ), filtered as (
    select r.*
    from records r
    where v_token_updated_at is null
       or r.updated_at > v_token_updated_at
       or (
         r.updated_at = v_token_updated_at
         and r.entity_type > v_token_entity_type
       )
       or (
         r.updated_at = v_token_updated_at
         and r.entity_type = v_token_entity_type
         and r.record_id::text > v_token_id
       )
  ), ordered as (
    select r.*
    from filtered r
    order by r.updated_at, r.entity_type, r.record_id::text
    limit v_limit + 1
  ), numbered as (
    select
      o.*,
      row_number() over (
        order by o.updated_at, o.entity_type, o.record_id::text
      ) as rn
    from ordered o
  ), visible as (
    select *
    from numbered
    where rn <= v_limit
  )
  select
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'entity_type', v.entity_type,
            'id', v.record_id,
            'updated_at', v.updated_at,
            'payload', v.payload
          )
          order by v.updated_at, v.entity_type, v.record_id::text
        )
        from visible v
      ),
      '[]'::jsonb
    ),
    coalesce((select count(*)::integer from visible), 0),
    exists(select 1 from numbered n where n.rn > v_limit),
    case
      when exists(select 1 from visible) then (
        select jsonb_build_object(
          'token_version', 1,
          'business_id', p_business_id,
          'since_updated_at', v_since,
          'window_upper_bound', v_window_upper_bound,
          'include_deleted', coalesce(p_include_deleted, false),
          'updated_at', v.updated_at,
          'entity_type', v.entity_type,
          'id', v.record_id
        )
        from visible v
        order by v.updated_at desc, v.entity_type desc, v.record_id::text desc
        limit 1
      )
      else null
    end
  into
    v_records,
    v_returned_count,
    v_has_more,
    v_next_token_payload;

  if v_has_more then
    v_next_page_token := jsonb_build_object(
      'token_version', 1,
      'token', private.encode_operational_bootstrap_page_token(
        v_next_token_payload
      )
    );
  else
    v_next_page_token := null;
  end if;

  select coalesce(jsonb_object_agg(entity_type, entity_count), '{}'::jsonb)
  into v_counts_by_entity
  from (
    select
      e.value->>'entity_type' as entity_type,
      count(*)::integer as entity_count
    from jsonb_array_elements(v_records) e(value)
    group by e.value->>'entity_type'
  ) counts;

  return jsonb_build_object(
    'business_id', p_business_id,
    'server_time', v_window_upper_bound,
    'window_upper_bound', v_window_upper_bound,
    'since_updated_at', v_since,
    'current_catalog_version', coalesce(v_current_catalog_version, 0),
    'limit', v_limit,
    'returned_count', v_returned_count,
    'counts_by_entity', coalesce(v_counts_by_entity, '{}'::jsonb),
    'has_more', coalesce(v_has_more, false),
    'complete', not coalesce(v_has_more, false),
    'next_page_token', v_next_page_token,
    'include_deleted', coalesce(p_include_deleted, false),
    'records', coalesce(v_records, '[]'::jsonb)
  );
end;
$$;

revoke all on function public.pull_product_catalog_delta(
  uuid,
  timestamptz,
  integer,
  jsonb,
  boolean
) from public;

grant execute on function public.pull_product_catalog_delta(
  uuid,
  timestamptz,
  integer,
  jsonb,
  boolean
) to authenticated;

comment on function public.pull_product_catalog_delta(
  uuid,
  timestamptz,
  integer,
  jsonb,
  boolean
) is
'Pulls a stable lightweight catalog delta window with signed, tenant-bound continuation tokens and tombstones.';
