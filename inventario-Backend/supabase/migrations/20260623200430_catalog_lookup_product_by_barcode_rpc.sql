-- =========================================================
-- Fase 6.19C.2 - RPC lookup_product_by_barcode
-- Objetivo:
-- - Buscar códigos locales del negocio primero.
-- - Si no hay match local, buscar código global del catálogo maestro.
-- - Devolver respuesta liviana para Flutter.
-- - Mantener enfoque offline-first: esta RPC no es para cada escaneo.
-- =========================================================

create or replace function public.lookup_product_by_barcode(
  p_business_id uuid,
  p_barcode text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_barcode_normalized text;

  v_business_barcode jsonb;
  v_global_barcode jsonb;

  v_product jsonb;
  v_master_product jsonb;

  v_product_id uuid;
  v_master_product_id uuid;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if not private.is_business_member(p_business_id) then
    raise exception 'Insufficient permission to lookup product barcode for this business';
  end if;

  v_barcode_normalized := private.normalize_barcode(p_barcode);

  if v_barcode_normalized is null then
    raise exception 'barcode is required';
  end if;

  -- =======================================================
  -- 1. Buscar barcode local del negocio
  -- =======================================================

  select
    to_jsonb(pb),
    pb.product_id,
    pb.master_product_id
  into
    v_business_barcode,
    v_product_id,
    v_master_product_id
  from public.product_barcodes pb
  where pb.scope = 'business'
    and pb.business_id = p_business_id
    and pb.barcode_normalized = v_barcode_normalized
    and pb.deleted_at is null
    and pb.status = 'active'
  order by
    pb.is_primary desc,
    pb.updated_at desc,
    pb.created_at desc
  limit 1;

  if v_product_id is not null then
    select to_jsonb(p)
    into v_product
    from public.products p
    where p.id = v_product_id
      and p.business_id = p_business_id
      and p.deleted_at is null
    limit 1;

    -- Si el barcode apunta a un producto eliminado o inválido, no lo usamos.
    if v_product is not null then
      if v_master_product_id is null then
        v_master_product_id := nullif(v_product->>'master_product_id', '')::uuid;
      end if;

      if v_master_product_id is not null then
        select to_jsonb(m)
        into v_master_product
        from public.master_products_catalog m
        where m.id = v_master_product_id
          and m.deleted_at is null
        limit 1;
      end if;

      return jsonb_build_object(
        'found', true,
        'match_type', 'business',
        'suggested_action', 'use_local_product',

        'business_id', p_business_id,
        'barcode_input', p_barcode,
        'barcode_normalized', v_barcode_normalized,

        'barcode_record', jsonb_build_object(
          'id', v_business_barcode->>'id',
          'scope', v_business_barcode->>'scope',
          'barcode', v_business_barcode->>'barcode',
          'barcode_normalized', v_business_barcode->>'barcode_normalized',
          'barcode_type', v_business_barcode->>'barcode_type',
          'is_primary', coalesce((v_business_barcode->>'is_primary')::boolean, false),
          'source', v_business_barcode->>'source',
          'confidence_score', v_business_barcode->>'confidence_score'
        ),

        'local_product', jsonb_build_object(
          'id', v_product->>'id',
          'business_id', v_product->>'business_id',
          'master_product_id', v_product->>'master_product_id',
          'barcode', v_product->>'barcode',
          'name', coalesce(v_product->>'name', v_product->>'product_name'),
          'description', v_product->>'description',
          'category_id', v_product->>'category_id',
          'sale_price', coalesce(v_product->'sale_price', v_product->'price'),
          'purchase_price', coalesce(v_product->'purchase_price', v_product->'cost_price'),
          'stock_quantity', v_product->'stock_quantity',
          'min_stock', coalesce(v_product->'min_stock', v_product->'minimum_stock'),
          'sync_status', v_product->>'sync_status',
          'version', v_product->>'version',
          'updated_at', v_product->>'updated_at'
        ),

        'master_product',
          case
            when v_master_product is null then null
            else jsonb_build_object(
              'id', v_master_product->>'id',
              'barcode', v_master_product->>'barcode',
              'gtin', v_master_product->>'gtin',
              'barcode_normalized', v_master_product->>'barcode_normalized',
              'name', coalesce(v_master_product->>'name', v_master_product->>'product_name'),
              'product_name', v_master_product->>'product_name',
              'brand', v_master_product->>'brand',
              'manufacturer', v_master_product->>'manufacturer',
              'category_name', coalesce(v_master_product->>'category_name', v_master_product->>'category'),
              'subcategory_name', v_master_product->>'subcategory_name',
              'package_size', v_master_product->'package_size',
              'package_unit', v_master_product->>'package_unit',
              'unit_type', coalesce(v_master_product->>'unit_type', v_master_product->>'unit'),
              'has_image', coalesce((v_master_product->>'has_image')::boolean, false),
              'image_thumb_url', v_master_product->>'image_thumb_url',
              'image_hash', v_master_product->>'image_hash',
              'verification_status', v_master_product->>'verification_status',
              'confidence_score', v_master_product->>'confidence_score',
              'catalog_version', v_master_product->>'catalog_version',
              'updated_at', v_master_product->>'updated_at'
            )
          end
      );
    end if;
  end if;

  -- =======================================================
  -- 2. Buscar barcode global del catálogo maestro
  -- =======================================================

  v_business_barcode := null;
  v_product := null;
  v_master_product := null;
  v_master_product_id := null;

  select
    to_jsonb(pb),
    pb.master_product_id
  into
    v_global_barcode,
    v_master_product_id
  from public.product_barcodes pb
  where pb.scope = 'global'
    and pb.barcode_normalized = v_barcode_normalized
    and pb.deleted_at is null
    and pb.status = 'active'
  order by
    pb.is_primary desc,
    pb.confidence_score desc,
    pb.updated_at desc,
    pb.created_at desc
  limit 1;

  if v_master_product_id is not null then
    select to_jsonb(m)
    into v_master_product
    from public.master_products_catalog m
    where m.id = v_master_product_id
      and m.deleted_at is null
      and coalesce(m.sync_status, 'synced') = 'synced'
    limit 1;

    if v_master_product is not null then
      return jsonb_build_object(
        'found', true,
        'match_type', 'global',
        'suggested_action', 'create_local_product_from_master',

        'business_id', p_business_id,
        'barcode_input', p_barcode,
        'barcode_normalized', v_barcode_normalized,

        'barcode_record', jsonb_build_object(
          'id', v_global_barcode->>'id',
          'scope', v_global_barcode->>'scope',
          'barcode', v_global_barcode->>'barcode',
          'barcode_normalized', v_global_barcode->>'barcode_normalized',
          'barcode_type', v_global_barcode->>'barcode_type',
          'is_primary', coalesce((v_global_barcode->>'is_primary')::boolean, false),
          'source', v_global_barcode->>'source',
          'confidence_score', v_global_barcode->>'confidence_score'
        ),

        'local_product', null,

        'master_product', jsonb_build_object(
          'id', v_master_product->>'id',
          'barcode', v_master_product->>'barcode',
          'gtin', v_master_product->>'gtin',
          'barcode_normalized', v_master_product->>'barcode_normalized',
          'name', coalesce(v_master_product->>'name', v_master_product->>'product_name'),
          'product_name', v_master_product->>'product_name',
          'brand', v_master_product->>'brand',
          'manufacturer', v_master_product->>'manufacturer',
          'category_name', coalesce(v_master_product->>'category_name', v_master_product->>'category'),
          'subcategory_name', v_master_product->>'subcategory_name',
          'package_size', v_master_product->'package_size',
          'package_unit', v_master_product->>'package_unit',
          'unit_type', coalesce(v_master_product->>'unit_type', v_master_product->>'unit'),
          'has_image', coalesce((v_master_product->>'has_image')::boolean, false),
          'image_thumb_url', v_master_product->>'image_thumb_url',
          'image_hash', v_master_product->>'image_hash',
          'verification_status', v_master_product->>'verification_status',
          'confidence_score', v_master_product->>'confidence_score',
          'catalog_version', v_master_product->>'catalog_version',
          'updated_at', v_master_product->>'updated_at'
        )
      );
    end if;
  end if;

  -- =======================================================
  -- 3. Sin resultado
  -- =======================================================

  return jsonb_build_object(
    'found', false,
    'match_type', 'none',
    'suggested_action', 'create_manual_product',

    'business_id', p_business_id,
    'barcode_input', p_barcode,
    'barcode_normalized', v_barcode_normalized,

    'barcode_record', null,
    'local_product', null,
    'master_product', null
  );
end;
$$;

revoke all on function public.lookup_product_by_barcode(uuid, text) from public;

grant execute on function public.lookup_product_by_barcode(uuid, text) to authenticated;

comment on function public.lookup_product_by_barcode(uuid, text) is
'Looks up a barcode for a business. Business-local barcodes are preferred over global master catalog barcodes. Intended for refresh/support, not per-scan online usage.';