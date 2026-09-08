-- P1.3 - Transactional, service-role-only master catalog import.
--
-- The CSV tooling produces a deterministic plan. This migration keeps the
-- database authoritative: every identity, version, scope, barcode and
-- tombstone invariant is checked again inside one transaction.

begin;

create table if not exists private.master_catalog_import_batches (
  import_batch_id uuid primary key,
  dataset_version text not null check (btrim(dataset_version) <> ''),
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('applying', 'applied', 'compensated')),
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  applied_at timestamptz,
  compensated_at timestamptz,
  compensation_reason text
);

create table if not exists private.master_catalog_import_audit (
  import_batch_id uuid not null
    references private.master_catalog_import_batches(import_batch_id),
  entity_type text not null
    check (entity_type in ('master_product', 'global_barcode')),
  entity_id uuid not null,
  operation text not null check (operation in ('insert', 'update', 'no_op')),
  expected_version integer,
  previous_record jsonb,
  applied_record jsonb not null,
  record_hash text not null check (record_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  primary key (import_batch_id, entity_type, entity_id)
);

revoke all privileges on table private.master_catalog_import_batches
from public, anon, authenticated, service_role;
revoke all privileges on table private.master_catalog_import_audit
from public, anon, authenticated, service_role;

create or replace function private.catalog_gtin_is_valid(
  p_barcode text,
  p_barcode_type text
)
returns boolean
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_code text := private.normalize_barcode(p_barcode);
  v_expected_length integer;
  v_sum integer := 0;
  v_position_from_right integer := 1;
  v_expected_check integer;
begin
  v_expected_length := case lower(coalesce(p_barcode_type, ''))
    when 'ean8' then 8
    when 'upc' then 12
    when 'ean13' then 13
    when 'gtin' then 14
    else null
  end;

  if v_expected_length is null
     or v_code is null
     or v_code !~ '^[0-9]+$'
     or length(v_code) <> v_expected_length
  then
    return false;
  end if;

  for v_index in reverse length(v_code) - 1..1 loop
    v_sum := v_sum
      + substring(v_code from v_index for 1)::integer
        * case when v_position_from_right % 2 = 1 then 3 else 1 end;
    v_position_from_right := v_position_from_right + 1;
  end loop;

  v_expected_check := (10 - (v_sum % 10)) % 10;
  return v_expected_check = right(v_code, 1)::integer;
end;
$$;

revoke all on function private.catalog_gtin_is_valid(text, text)
from public, anon, authenticated;
grant execute on function private.catalog_gtin_is_valid(text, text)
to service_role;

create or replace function public.export_master_catalog_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_masters jsonb;
  v_barcodes jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service role authority required for master catalog snapshot';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', m.id,
        'barcode', m.barcode,
        'gtin', m.gtin,
        'barcode_normalized', m.barcode_normalized,
        'name', m.name,
        'product_name', m.product_name,
        'normalized_name', m.normalized_name,
        'brand', m.brand,
        'manufacturer', m.manufacturer,
        'category_name', m.category_name,
        'category', m.category,
        'subcategory_name', m.subcategory_name,
        'package_size', m.package_size,
        'package_unit', m.package_unit,
        'unit_type', m.unit_type,
        'unit', m.unit,
        'description', m.description,
        'image_url', m.image_url,
        'image_thumb_url', m.image_thumb_url,
        'image_hash', m.image_hash,
        'has_image', m.has_image,
        'source', m.source,
        'verification_status', m.verification_status,
        'confidence_score', m.confidence_score,
        'catalog_version', m.catalog_version,
        'version', m.version,
        'sync_status', m.sync_status,
        'metadata', m.metadata,
        'created_at', m.created_at,
        'updated_at', m.updated_at,
        'deleted_at', m.deleted_at
      )
      order by m.id::text
    ),
    '[]'::jsonb
  )
  into v_masters
  from public.master_products_catalog m;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', pb.id,
        'business_id', pb.business_id,
        'master_product_id', pb.master_product_id,
        'product_id', pb.product_id,
        'barcode', pb.barcode,
        'barcode_normalized', pb.barcode_normalized,
        'barcode_type', pb.barcode_type,
        'scope', pb.scope,
        'is_primary', pb.is_primary,
        'status', pb.status,
        'source', pb.source,
        'confidence_score', pb.confidence_score,
        'version', pb.version,
        'sync_status', pb.sync_status,
        'metadata', pb.metadata,
        'created_at', pb.created_at,
        'updated_at', pb.updated_at,
        'deleted_at', pb.deleted_at
      )
      order by pb.id::text
    ),
    '[]'::jsonb
  )
  into v_barcodes
  from public.product_barcodes pb
  where pb.scope = 'global';

  return jsonb_build_object(
    'snapshot_version', 1,
    'masters', v_masters,
    'global_barcodes', v_barcodes
  );
end;
$$;

revoke all on function public.export_master_catalog_snapshot()
from public, anon, authenticated, service_role;
grant execute on function public.export_master_catalog_snapshot()
to service_role;

comment on function public.export_master_catalog_snapshot() is
'Exports the minimal service-role-only master/global-barcode state used by the P1.3 offline import planner, including tombstones and versions.';

create or replace function public.import_master_catalog_batch(
  p_import_batch_id uuid,
  p_dataset_version text,
  p_masters jsonb,
  p_barcodes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_dataset_version text := nullif(btrim(coalesce(p_dataset_version, '')), '');
  v_masters jsonb;
  v_barcodes jsonb;
  v_request_hash text;
  v_existing_batch private.master_catalog_import_batches%rowtype;
  v_item jsonb;
  v_id uuid;
  v_master_id uuid;
  v_expected_version integer;
  v_record_hash text;
  v_code text;
  v_code_type text;
  v_primary boolean;
  v_existing_master public.master_products_catalog%rowtype;
  v_existing_barcode public.product_barcodes%rowtype;
  v_current_primary public.product_barcodes%rowtype;
  v_exists boolean;
  v_same boolean;
  v_operation text;
  v_previous jsonb;
  v_applied jsonb;
  v_master_inserts integer := 0;
  v_master_updates integer := 0;
  v_master_no_ops integer := 0;
  v_barcode_inserts integer := 0;
  v_barcode_updates integer := 0;
  v_barcode_no_ops integer := 0;
  v_master_operations jsonb := '[]'::jsonb;
  v_barcode_operations jsonb := '[]'::jsonb;
  v_result jsonb;
  v_catalog_metadata jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using
      errcode = '42501',
      message = 'Service role authority required for master catalog import';
  end if;

  if p_import_batch_id is null then
    raise exception using errcode = '22023', message = 'import_batch_id is required';
  end if;
  if v_dataset_version is null then
    raise exception using errcode = '22023', message = 'dataset_version is required';
  end if;
  if length(v_dataset_version) > 128 then
    raise exception using errcode = '22023', message = 'dataset_version is too long';
  end if;
  if jsonb_typeof(p_masters) <> 'array' or jsonb_typeof(p_barcodes) <> 'array' then
    raise exception using errcode = '22023', message = 'masters and barcodes must be JSON arrays';
  end if;
  if jsonb_array_length(p_masters) < 1
     or jsonb_array_length(p_masters) > 100
     or jsonb_array_length(p_barcodes) < 1
     or jsonb_array_length(p_barcodes) > 500
  then
    raise exception using
      errcode = '22023',
      message = 'Catalog batch must contain 1..100 masters and 1..500 barcodes';
  end if;

  select jsonb_agg(e.value order by e.value->>'master_product_id')
  into v_masters
  from jsonb_array_elements(p_masters) e(value);

  select jsonb_agg(e.value order by e.value->>'barcode_id')
  into v_barcodes
  from jsonb_array_elements(p_barcodes) e(value);

  v_request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'dataset_version', v_dataset_version,
          'masters', v_masters,
          'barcodes', v_barcodes
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_import_batch_id::text));

  select *
  into v_existing_batch
  from private.master_catalog_import_batches b
  where b.import_batch_id = p_import_batch_id
  for update;

  if found then
    if v_existing_batch.request_hash <> v_request_hash
       or v_existing_batch.dataset_version <> v_dataset_version
    then
      raise exception using
        errcode = '40001',
        message = 'import_batch_id was already used with a different request';
    end if;
    if v_existing_batch.status = 'applied' then
      return v_existing_batch.result
        || jsonb_build_object('status', 'already_applied');
    end if;
    raise exception using
      errcode = '55000',
      message = 'Import batch is not eligible for reapplication';
  end if;

  -- Lock all pre-existing rows that can participate in identity checks.
  perform 1
  from public.master_products_catalog m
  where m.id in (
    select (e.value->>'master_product_id')::uuid
    from jsonb_array_elements(v_masters) e(value)
  )
  order by m.id::text
  for update;

  perform 1
  from public.product_barcodes pb
  where pb.scope = 'global'
    and (
      pb.id in (
        select (e.value->>'barcode_id')::uuid
        from jsonb_array_elements(v_barcodes) e(value)
      )
      or pb.barcode_normalized in (
        select private.normalize_barcode(e.value->>'barcode')
        from jsonb_array_elements(v_barcodes) e(value)
      )
    )
  order by pb.id::text
  for update;

  -- Validate masters without writing.
  for v_item in
    select e.value
    from jsonb_array_elements(v_masters) e(value)
    order by e.value->>'master_product_id'
  loop
    begin
      v_id := (v_item->>'master_product_id')::uuid;
      v_expected_version := nullif(v_item->>'expected_version', '')::integer;
    exception when others then
      raise exception using errcode = '22023', message = 'Invalid master ID or expected_version';
    end;

    v_record_hash := lower(coalesce(v_item->>'record_hash', ''));
    v_code := private.normalize_barcode(v_item->>'primary_barcode');
    v_code_type := lower(coalesce(v_item->>'barcode_type', ''));

    if v_record_hash !~ '^[0-9a-f]{64}$'
       or nullif(btrim(coalesce(v_item->>'name', '')), '') is null
       or nullif(btrim(coalesce(v_item->>'category_name', '')), '') is null
       or nullif(btrim(coalesce(v_item->>'unit_type', '')), '') is null
       or nullif(btrim(coalesce(v_item->>'source', '')), '') is null
       or nullif(btrim(coalesce(v_item->>'source_reference', '')), '') is null
    then
      raise exception using errcode = '22023', message = 'Master payload is missing required validated fields';
    end if;
    if not private.catalog_gtin_is_valid(v_code, v_code_type) then
      raise exception using errcode = '22023', message = 'Master primary barcode is invalid';
    end if;
    if lower(coalesce(v_item->>'verification_status', '')) not in (
      'unverified', 'community', 'verified', 'gs1_verified', 'rejected', 'deprecated'
    ) then
      raise exception using errcode = '22023', message = 'Master verification_status is invalid';
    end if;
    if v_item->>'category_name' not in (
      'Alimentos', 'Bebidas', 'Snacks y confitería', 'Aseo del hogar', 'Cuidado personal'
    ) or v_item->>'unit_type' not in (
      'unidad', 'bolsa', 'botella', 'caja', 'paquete', 'lata', 'frasco', 'sobre', 'tubo', 'rollo'
    ) or lower(v_item->>'source') not in (
      'manual_curated', 'supplier', 'manufacturer', 'open_dataset', 'business_contribution'
    ) then
      raise exception using errcode = '22023', message = 'Master controlled vocabulary is invalid';
    end if;
    if (v_item->>'confidence_score')::numeric < 0
       or (v_item->>'confidence_score')::numeric > 1
    then
      raise exception using errcode = '22023', message = 'Master confidence_score is invalid';
    end if;
    if (nullif(v_item->>'package_size', '') is null)
       <> (nullif(v_item->>'package_unit', '') is null)
    then
      raise exception using errcode = '22023', message = 'Master package_size/package_unit must be paired';
    end if;
    if nullif(v_item->>'package_size', '') is not null
       and (v_item->>'package_size')::numeric <= 0
    then
      raise exception using errcode = '22023', message = 'Master package_size must be positive';
    end if;
    if nullif(v_item->>'package_unit', '') is not null
       and v_item->>'package_unit' not in ('g', 'kg', 'ml', 'l', 'unidad')
    then
      raise exception using errcode = '22023', message = 'Master package_unit is invalid';
    end if;
    if nullif(v_item->>'image_license', '') is not null
       and v_item->>'image_license' not in (
         'owned', 'authorized_manufacturer', 'authorized_supplier', 'cc0',
         'cc_by', 'other_documented', 'test_only'
       )
    then
      raise exception using errcode = '22023', message = 'Master image_license is invalid';
    end if;
    if nullif(v_item->>'image_source_key', '') is not null
       and nullif(v_item->>'image_license', '') is null
    then
      raise exception using errcode = '22023', message = 'Master image license is required';
    end if;
    if v_item->>'image_license' in (
      'authorized_manufacturer', 'authorized_supplier', 'cc_by', 'other_documented'
    ) and nullif(v_item->>'image_attribution', '') is null
    then
      raise exception using errcode = '22023', message = 'Master image attribution is required';
    end if;

    if (
      select count(*)
      from jsonb_array_elements(v_barcodes) b(value)
      where (b.value->>'master_product_id')::uuid = v_id
        and coalesce((b.value->>'is_primary')::boolean, false)
        and private.normalize_barcode(b.value->>'barcode') = v_code
    ) <> 1
       or (
         select count(*)
         from jsonb_array_elements(v_barcodes) b(value)
         where (b.value->>'master_product_id')::uuid = v_id
           and coalesce((b.value->>'is_primary')::boolean, false)
       ) <> 1
    then
      raise exception using errcode = '22023', message = 'Master must have exactly one matching primary barcode';
    end if;

    select * into v_existing_master
    from public.master_products_catalog m
    where m.id = v_id;
    v_exists := found;

    if v_exists then
      if v_existing_master.deleted_at is not null then
        raise exception using errcode = '55000', message = 'Tombstoned master requires explicit review';
      end if;
      if v_expected_version is null or v_existing_master.version <> v_expected_version then
        raise exception using errcode = '40001', message = 'Master expected_version conflict';
      end if;
    elsif coalesce(v_expected_version, 0) <> 0 then
      raise exception using errcode = '40001', message = 'Master expected_version conflict for insert';
    end if;
  end loop;

  -- Validate barcodes and all cross-row/cross-database identities without writing.
  for v_item in
    select e.value
    from jsonb_array_elements(v_barcodes) e(value)
    order by e.value->>'barcode_id'
  loop
    begin
      v_id := (v_item->>'barcode_id')::uuid;
      v_master_id := (v_item->>'master_product_id')::uuid;
      v_expected_version := nullif(v_item->>'expected_version', '')::integer;
      v_primary := (v_item->>'is_primary')::boolean;
    exception when others then
      raise exception using errcode = '22023', message = 'Invalid barcode identity, primary flag or expected_version';
    end;

    v_record_hash := lower(coalesce(v_item->>'record_hash', ''));
    v_code := private.normalize_barcode(v_item->>'barcode');
    v_code_type := lower(coalesce(v_item->>'barcode_type', ''));

    if v_record_hash !~ '^[0-9a-f]{64}$'
       or nullif(btrim(coalesce(v_item->>'source', '')), '') is null
       or nullif(btrim(coalesce(v_item->>'source_reference', '')), '') is null
       or not private.catalog_gtin_is_valid(v_code, v_code_type)
    then
      raise exception using errcode = '22023', message = 'Global barcode payload is invalid';
    end if;
    if (v_item->>'confidence_score')::numeric < 0
       or (v_item->>'confidence_score')::numeric > 1
    then
      raise exception using errcode = '22023', message = 'Barcode confidence_score is invalid';
    end if;
    if lower(v_item->>'source') not in (
      'manual_curated', 'supplier', 'manufacturer', 'open_dataset', 'business_contribution'
    ) then
      raise exception using errcode = '22023', message = 'Barcode source is invalid';
    end if;
    if not exists (
      select 1 from jsonb_array_elements(v_masters) m(value)
      where (m.value->>'master_product_id')::uuid = v_master_id
    ) then
      raise exception using errcode = '22023', message = 'Barcode master is absent from this batch';
    end if;
    if (
      select count(*) from jsonb_array_elements(v_barcodes) b(value)
      where (b.value->>'barcode_id')::uuid = v_id
    ) <> 1 then
      raise exception using errcode = '23505', message = 'Duplicate barcode_id in import batch';
    end if;
    if (
      select count(*) from jsonb_array_elements(v_barcodes) b(value)
      where private.normalize_barcode(b.value->>'barcode') = v_code
    ) <> 1 then
      raise exception using errcode = '23505', message = 'Duplicate normalized barcode in import batch';
    end if;

    select * into v_existing_barcode
    from public.product_barcodes pb
    where pb.id = v_id;
    v_exists := found;

    if v_exists then
      if v_existing_barcode.scope <> 'global'
         or v_existing_barcode.master_product_id <> v_master_id
         or v_existing_barcode.barcode_normalized <> v_code
      then
        raise exception using errcode = '23505', message = 'Barcode ID has contradictory identity';
      end if;
      if v_existing_barcode.deleted_at is not null then
        raise exception using errcode = '55000', message = 'Tombstoned barcode requires explicit review';
      end if;
      if v_expected_version is null or v_existing_barcode.version <> v_expected_version then
        raise exception using errcode = '40001', message = 'Barcode expected_version conflict';
      end if;
    elsif coalesce(v_expected_version, 0) <> 0 then
      raise exception using errcode = '40001', message = 'Barcode expected_version conflict for insert';
    end if;

    if exists (
      select 1
      from public.product_barcodes pb
      where pb.scope = 'global'
        and pb.barcode_normalized = v_code
        and pb.deleted_at is null
        and pb.status = 'active'
        and (pb.id <> v_id or pb.master_product_id <> v_master_id)
    ) then
      raise exception using errcode = '23505', message = 'Global barcode belongs to another master';
    end if;
    if exists (
      select 1
      from public.product_barcodes pb
      where pb.scope = 'global'
        and pb.barcode_normalized = v_code
        and pb.deleted_at is not null
        and pb.id <> v_id
    ) then
      raise exception using errcode = '55000', message = 'Tombstoned barcode value requires explicit review';
    end if;
  end loop;

  -- A primary switch is permitted only when the previous primary is explicitly
  -- present in the batch as a non-primary alias. Nothing is demoted implicitly.
  for v_item in
    select e.value
    from jsonb_array_elements(v_masters) e(value)
    order by e.value->>'master_product_id'
  loop
    v_master_id := (v_item->>'master_product_id')::uuid;
    select * into v_current_primary
    from public.product_barcodes pb
    where pb.scope = 'global'
      and pb.master_product_id = v_master_id
      and pb.is_primary
      and pb.status = 'active'
      and pb.deleted_at is null;
    if found
       and not exists (
         select 1
         from jsonb_array_elements(v_barcodes) b(value)
         where (b.value->>'barcode_id')::uuid = v_current_primary.id
           and (b.value->>'is_primary')::boolean = false
       )
       and v_current_primary.barcode_normalized
           <> private.normalize_barcode(v_item->>'primary_barcode')
    then
      raise exception using errcode = '55000', message = 'Primary barcode change requires explicit old-primary alias row';
    end if;
  end loop;

  insert into private.master_catalog_import_batches (
    import_batch_id, dataset_version, request_hash, status
  ) values (
    p_import_batch_id, v_dataset_version, v_request_hash, 'applying'
  );

  -- Masters are applied before their barcode relations.
  for v_item in
    select e.value
    from jsonb_array_elements(v_masters) e(value)
    order by e.value->>'master_product_id'
  loop
    v_id := (v_item->>'master_product_id')::uuid;
    v_expected_version := nullif(v_item->>'expected_version', '')::integer;
    v_record_hash := lower(v_item->>'record_hash');
    v_code := private.normalize_barcode(v_item->>'primary_barcode');
    v_previous := null;

    v_catalog_metadata := jsonb_strip_nulls(jsonb_build_object(
      'import_batch_id', p_import_batch_id,
      'dataset_version', v_dataset_version,
      'record_hash', v_record_hash,
      'source_reference', v_item->>'source_reference',
      'image_source_key', nullif(v_item->>'image_source_key', ''),
      'image_license', nullif(v_item->>'image_license', ''),
      'image_attribution', nullif(v_item->>'image_attribution', '')
    ));

    select * into v_existing_master
    from public.master_products_catalog m where m.id = v_id;
    v_exists := found;
    if v_exists then
      v_previous := to_jsonb(v_existing_master);
      v_same :=
        private.normalize_barcode(coalesce(v_existing_master.gtin, v_existing_master.barcode)) = v_code
        and v_existing_master.name is not distinct from nullif(btrim(v_item->>'name'), '')
        and v_existing_master.product_name is not distinct from nullif(btrim(v_item->>'name'), '')
        and v_existing_master.brand is not distinct from nullif(btrim(v_item->>'brand'), '')
        and v_existing_master.manufacturer is not distinct from nullif(btrim(v_item->>'manufacturer'), '')
        and v_existing_master.category_name is not distinct from nullif(btrim(v_item->>'category_name'), '')
        and v_existing_master.category is not distinct from nullif(btrim(v_item->>'category_name'), '')
        and v_existing_master.subcategory_name is not distinct from nullif(btrim(v_item->>'subcategory_name'), '')
        and v_existing_master.package_size is not distinct from nullif(v_item->>'package_size', '')::numeric
        and v_existing_master.package_unit is not distinct from nullif(btrim(v_item->>'package_unit'), '')
        and v_existing_master.unit_type is not distinct from nullif(btrim(v_item->>'unit_type'), '')
        and v_existing_master.unit is not distinct from nullif(btrim(v_item->>'unit_type'), '')
        and v_existing_master.description is not distinct from nullif(btrim(v_item->>'description'), '')
        and v_existing_master.source = lower(v_item->>'source')
        and v_existing_master.verification_status = lower(v_item->>'verification_status')
        and v_existing_master.confidence_score = (v_item->>'confidence_score')::numeric
        and coalesce(v_existing_master.metadata->'catalog_import'->>'source_reference', '')
            = coalesce(v_item->>'source_reference', '')
        and coalesce(v_existing_master.metadata->'catalog_import'->>'image_source_key', '')
            = coalesce(v_item->>'image_source_key', '')
        and coalesce(v_existing_master.metadata->'catalog_import'->>'image_license', '')
            = coalesce(v_item->>'image_license', '')
        and coalesce(v_existing_master.metadata->'catalog_import'->>'image_attribution', '')
            = coalesce(v_item->>'image_attribution', '');

      if v_same then
        v_operation := 'no_op';
        v_master_no_ops := v_master_no_ops + 1;
      else
        update public.master_products_catalog
        set
          barcode = v_code,
          gtin = v_code,
          name = nullif(btrim(v_item->>'name'), ''),
          product_name = nullif(btrim(v_item->>'name'), ''),
          brand = nullif(btrim(v_item->>'brand'), ''),
          manufacturer = nullif(btrim(v_item->>'manufacturer'), ''),
          category_name = nullif(btrim(v_item->>'category_name'), ''),
          category = nullif(btrim(v_item->>'category_name'), ''),
          subcategory_name = nullif(btrim(v_item->>'subcategory_name'), ''),
          package_size = nullif(v_item->>'package_size', '')::numeric,
          package_unit = nullif(btrim(v_item->>'package_unit'), ''),
          unit_type = nullif(btrim(v_item->>'unit_type'), ''),
          unit = nullif(btrim(v_item->>'unit_type'), ''),
          description = nullif(btrim(v_item->>'description'), ''),
          source = lower(v_item->>'source'),
          verification_status = lower(v_item->>'verification_status'),
          confidence_score = (v_item->>'confidence_score')::numeric,
          catalog_version = greatest(coalesce(catalog_version, 1) + 1, 2),
          metadata = coalesce(metadata, '{}'::jsonb)
            || jsonb_build_object('catalog_import', v_catalog_metadata),
          sync_status = 'synced'
        where id = v_id;
        v_operation := 'update';
        v_master_updates := v_master_updates + 1;
      end if;
    else
      insert into public.master_products_catalog (
        id, barcode, gtin, name, product_name, brand, manufacturer,
        category_name, category, subcategory_name, package_size, package_unit,
        unit_type, unit, description, source, verification_status,
        confidence_score, catalog_version, metadata, sync_status
      ) values (
        v_id, v_code, v_code, nullif(btrim(v_item->>'name'), ''),
        nullif(btrim(v_item->>'name'), ''), nullif(btrim(v_item->>'brand'), ''),
        nullif(btrim(v_item->>'manufacturer'), ''),
        nullif(btrim(v_item->>'category_name'), ''),
        nullif(btrim(v_item->>'category_name'), ''),
        nullif(btrim(v_item->>'subcategory_name'), ''),
        nullif(v_item->>'package_size', '')::numeric,
        nullif(btrim(v_item->>'package_unit'), ''),
        nullif(btrim(v_item->>'unit_type'), ''),
        nullif(btrim(v_item->>'unit_type'), ''),
        nullif(btrim(v_item->>'description'), ''), lower(v_item->>'source'),
        lower(v_item->>'verification_status'),
        (v_item->>'confidence_score')::numeric, 1,
        jsonb_build_object('catalog_import', v_catalog_metadata), 'synced'
      );
      v_operation := 'insert';
      v_master_inserts := v_master_inserts + 1;
    end if;

    select to_jsonb(m) into v_applied
    from public.master_products_catalog m where m.id = v_id;
    insert into private.master_catalog_import_audit (
      import_batch_id, entity_type, entity_id, operation, expected_version,
      previous_record, applied_record, record_hash
    ) values (
      p_import_batch_id, 'master_product', v_id, v_operation,
      v_expected_version, v_previous, v_applied, v_record_hash
    );
    v_master_operations := v_master_operations || jsonb_build_array(
      jsonb_build_object('id', v_id, 'operation', v_operation)
    );
  end loop;

  -- Demotions are applied before primaries so a reviewed primary swap respects
  -- the existing unique index throughout the transaction.
  for v_item in
    select e.value
    from jsonb_array_elements(v_barcodes) e(value)
    order by (e.value->>'is_primary')::boolean, e.value->>'barcode_id'
  loop
    v_id := (v_item->>'barcode_id')::uuid;
    v_master_id := (v_item->>'master_product_id')::uuid;
    v_expected_version := nullif(v_item->>'expected_version', '')::integer;
    v_record_hash := lower(v_item->>'record_hash');
    v_code := private.normalize_barcode(v_item->>'barcode');
    v_code_type := lower(v_item->>'barcode_type');
    v_primary := (v_item->>'is_primary')::boolean;
    v_previous := null;
    v_catalog_metadata := jsonb_build_object(
      'import_batch_id', p_import_batch_id,
      'dataset_version', v_dataset_version,
      'record_hash', v_record_hash,
      'source_reference', v_item->>'source_reference'
    );

    select * into v_existing_barcode
    from public.product_barcodes pb where pb.id = v_id;
    v_exists := found;
    if v_exists then
      v_previous := to_jsonb(v_existing_barcode);
      v_same :=
        v_existing_barcode.scope = 'global'
        and v_existing_barcode.business_id is null
        and v_existing_barcode.product_id is null
        and v_existing_barcode.master_product_id = v_master_id
        and v_existing_barcode.barcode_normalized = v_code
        and v_existing_barcode.barcode_type = v_code_type
        and v_existing_barcode.is_primary = v_primary
        and v_existing_barcode.status = 'active'
        and v_existing_barcode.source = lower(v_item->>'source')
        and v_existing_barcode.confidence_score = (v_item->>'confidence_score')::numeric
        and coalesce(v_existing_barcode.metadata->'catalog_import'->>'source_reference', '')
            = coalesce(v_item->>'source_reference', '');
      if v_same then
        v_operation := 'no_op';
        v_barcode_no_ops := v_barcode_no_ops + 1;
      else
        update public.product_barcodes
        set
          business_id = null,
          product_id = null,
          master_product_id = v_master_id,
          barcode = v_code,
          barcode_type = v_code_type,
          scope = 'global',
          is_primary = v_primary,
          status = 'active',
          source = lower(v_item->>'source'),
          confidence_score = (v_item->>'confidence_score')::numeric,
          metadata = coalesce(metadata, '{}'::jsonb)
            || jsonb_build_object('catalog_import', v_catalog_metadata),
          sync_status = 'synced'
        where id = v_id;
        v_operation := 'update';
        v_barcode_updates := v_barcode_updates + 1;
      end if;
    else
      insert into public.product_barcodes (
        id, business_id, master_product_id, product_id, barcode, barcode_type,
        scope, is_primary, status, source, confidence_score, metadata, sync_status
      ) values (
        v_id, null, v_master_id, null, v_code, v_code_type,
        'global', v_primary, 'active', lower(v_item->>'source'),
        (v_item->>'confidence_score')::numeric,
        jsonb_build_object('catalog_import', v_catalog_metadata), 'synced'
      );
      v_operation := 'insert';
      v_barcode_inserts := v_barcode_inserts + 1;
    end if;

    select to_jsonb(pb) into v_applied
    from public.product_barcodes pb where pb.id = v_id;
    insert into private.master_catalog_import_audit (
      import_batch_id, entity_type, entity_id, operation, expected_version,
      previous_record, applied_record, record_hash
    ) values (
      p_import_batch_id, 'global_barcode', v_id, v_operation,
      v_expected_version, v_previous, v_applied, v_record_hash
    );
    v_barcode_operations := v_barcode_operations || jsonb_build_array(
      jsonb_build_object('id', v_id, 'operation', v_operation)
    );
  end loop;

  v_result := jsonb_build_object(
    'status', 'applied',
    'import_batch_id', p_import_batch_id,
    'dataset_version', v_dataset_version,
    'request_hash', v_request_hash,
    'masters', jsonb_build_object(
      'inserted', v_master_inserts,
      'updated', v_master_updates,
      'no_op', v_master_no_ops,
      'operations', v_master_operations
    ),
    'barcodes', jsonb_build_object(
      'inserted', v_barcode_inserts,
      'updated', v_barcode_updates,
      'no_op', v_barcode_no_ops,
      'operations', v_barcode_operations
    )
  );

  update private.master_catalog_import_batches
  set status = 'applied', result = v_result, applied_at = now()
  where import_batch_id = p_import_batch_id;

  return v_result;
end;
$$;

revoke all on function public.import_master_catalog_batch(uuid, text, jsonb, jsonb)
from public, anon, authenticated, service_role;
grant execute on function public.import_master_catalog_batch(uuid, text, jsonb, jsonb)
to service_role;

comment on function public.import_master_catalog_batch(uuid, text, jsonb, jsonb) is
'Atomically imports a preflighted master catalog batch under service_role authority, with optimistic versions, server-side validation and audit metadata.';

create or replace function public.compensate_master_catalog_import_batch(
  p_import_batch_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch private.master_catalog_import_batches%rowtype;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_master_ids uuid[];
  v_barcode_ids uuid[];
  v_master_count integer;
  v_barcode_count integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception using errcode = '42501', message = 'Service role authority required for catalog compensation';
  end if;
  if p_import_batch_id is null or v_reason is null then
    raise exception using errcode = '22023', message = 'import_batch_id and compensation reason are required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_import_batch_id::text));
  select * into v_batch
  from private.master_catalog_import_batches b
  where b.import_batch_id = p_import_batch_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'Catalog import batch does not exist';
  end if;
  if v_batch.status = 'compensated' then
    return jsonb_build_object('status', 'already_compensated', 'import_batch_id', p_import_batch_id);
  end if;
  if v_batch.status <> 'applied' then
    raise exception using errcode = '55000', message = 'Catalog import batch is not applied';
  end if;
  if exists (
    select 1 from private.master_catalog_import_audit a
    where a.import_batch_id = p_import_batch_id and a.operation = 'update'
  ) then
    raise exception using errcode = '55000', message = 'Batches containing updates require manual historical restoration';
  end if;

  select coalesce(array_agg(a.entity_id), array[]::uuid[])
  into v_master_ids
  from private.master_catalog_import_audit a
  where a.import_batch_id = p_import_batch_id
    and a.entity_type = 'master_product'
    and a.operation = 'insert';

  select coalesce(array_agg(a.entity_id), array[]::uuid[])
  into v_barcode_ids
  from private.master_catalog_import_audit a
  where a.import_batch_id = p_import_batch_id
    and a.entity_type = 'global_barcode'
    and a.operation = 'insert';

  if exists (
    select 1
    from private.master_catalog_import_audit a
    join public.master_products_catalog m on m.id = a.entity_id
    where a.import_batch_id = p_import_batch_id
      and a.entity_type = 'master_product'
      and a.operation = 'insert'
      and m.version <> (a.applied_record->>'version')::integer
  ) or exists (
    select 1
    from private.master_catalog_import_audit a
    join public.product_barcodes pb on pb.id = a.entity_id
    where a.import_batch_id = p_import_batch_id
      and a.entity_type = 'global_barcode'
      and a.operation = 'insert'
      and pb.version <> (a.applied_record->>'version')::integer
  ) then
    raise exception using errcode = '55000', message = 'Imported entities changed after the batch and require manual compensation';
  end if;

  if exists (
    select 1 from public.products p
    where p.master_product_id = any(v_master_ids)
  ) or exists (
    select 1 from public.product_catalog_contributions c
    where c.master_product_id = any(v_master_ids)
       or c.accepted_master_product_id = any(v_master_ids)
  ) or exists (
    select 1 from public.product_barcodes pb
    where pb.master_product_id = any(v_master_ids)
      and pb.id <> all(v_barcode_ids)
      and pb.deleted_at is null
  ) then
    raise exception using errcode = '55000', message = 'Imported masters have later dependencies and cannot be compensated automatically';
  end if;

  update public.product_barcodes
  set
    status = 'deprecated',
    deleted_at = now(),
    delete_reason = v_reason,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('catalog_import_compensation', jsonb_build_object(
        'import_batch_id', p_import_batch_id,
        'reason', v_reason
      )),
    sync_status = 'synced'
  where id = any(v_barcode_ids)
    and deleted_at is null;
  get diagnostics v_barcode_count = row_count;

  update public.master_products_catalog
  set
    deleted_at = now(),
    delete_reason = v_reason,
    metadata = coalesce(metadata, '{}'::jsonb)
      || jsonb_build_object('catalog_import_compensation', jsonb_build_object(
        'import_batch_id', p_import_batch_id,
        'reason', v_reason
      )),
    sync_status = 'synced'
  where id = any(v_master_ids)
    and deleted_at is null;
  get diagnostics v_master_count = row_count;

  update private.master_catalog_import_batches
  set
    status = 'compensated',
    compensated_at = now(),
    compensation_reason = v_reason
  where import_batch_id = p_import_batch_id;

  return jsonb_build_object(
    'status', 'compensated',
    'import_batch_id', p_import_batch_id,
    'soft_deleted_masters', v_master_count,
    'soft_deleted_barcodes', v_barcode_count
  );
end;
$$;

revoke all on function public.compensate_master_catalog_import_batch(uuid, text)
from public, anon, authenticated, service_role;
grant execute on function public.compensate_master_catalog_import_batch(uuid, text)
to service_role;

comment on function public.compensate_master_catalog_import_batch(uuid, text) is
'Conservatively soft-deletes entities inserted by an insert-only import batch when no later dependencies exist. Updates are never rolled back without history.';

commit;
