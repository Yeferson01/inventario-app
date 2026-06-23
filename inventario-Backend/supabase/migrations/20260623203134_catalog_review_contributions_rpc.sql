-- =========================================================
-- Fase 6.19C.5 - Review / accept product catalog contributions
-- Objetivo:
-- - Revisar contribuciones del catálogo.
-- - Aceptar como nuevo master product.
-- - Aceptar mejora sobre master product existente.
-- - Crear barcode global si aplica.
-- - Rechazar / marcar duplicado / ignorar.
-- =========================================================

-- =========================================================
-- 1. Helper de permiso para revisión de contribuciones
-- =========================================================

create or replace function private.can_review_product_catalog_contribution(
  p_business_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_business_id is null then
    return false;
  end if;

  return
    private.has_business_permission(p_business_id, 'settings.business')
    or private.has_business_permission(p_business_id, 'products.update');
end;
$$;

comment on function private.can_review_product_catalog_contribution(uuid) is
'Returns whether the current user can review product catalog contributions for a business. Future versions should support platform catalog admin permissions.';

-- =========================================================
-- 2. Helper para asegurar barcode global
-- =========================================================

create or replace function private.ensure_global_product_barcode(
  p_master_product_id uuid,
  p_barcode text,
  p_barcode_type text default 'unknown',
  p_source text default 'contribution',
  p_confidence_score numeric default 0.75,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_barcode_normalized text;
  v_existing public.product_barcodes%rowtype;
  v_barcode_id uuid;
  v_metadata jsonb;
begin
  if p_master_product_id is null then
    raise exception 'master_product_id is required';
  end if;

  if not exists (
    select 1
    from public.master_products_catalog m
    where m.id = p_master_product_id
      and m.deleted_at is null
  ) then
    raise exception 'master_product_id does not exist';
  end if;

  v_barcode_normalized := private.normalize_barcode(p_barcode);

  if v_barcode_normalized is null then
    return null;
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  select pb.*
  into v_existing
  from public.product_barcodes pb
  where pb.scope = 'global'
    and pb.barcode_normalized = v_barcode_normalized
    and pb.deleted_at is null
    and pb.status = 'active'
  limit 1
  for update;

  if v_existing.id is not null then
    if v_existing.master_product_id <> p_master_product_id then
      raise exception 'Global barcode already belongs to another master product';
    end if;

    update public.product_barcodes pb
    set
      barcode_type = case
        when coalesce(pb.barcode_type, 'unknown') = 'unknown'
        then lower(coalesce(p_barcode_type, 'unknown'))
        else pb.barcode_type
      end,
      source = coalesce(pb.source, p_source),
      confidence_score = greatest(
        coalesce(pb.confidence_score, 0),
        greatest(least(coalesce(p_confidence_score, 0), 1), 0)
      ),
      metadata = coalesce(pb.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'updated_via', 'private.ensure_global_product_barcode',
          'last_review_at', now()
        ),
      updated_at = now()
    where pb.id = v_existing.id
    returning pb.id
    into v_barcode_id;

    return v_barcode_id;
  end if;

  insert into public.product_barcodes (
    master_product_id,
    barcode,
    barcode_type,
    scope,
    is_primary,
    status,
    source,
    confidence_score,
    metadata,
    sync_status
  )
  values (
    p_master_product_id,
    p_barcode,
    lower(coalesce(p_barcode_type, 'unknown')),
    'global',
    true,
    'active',
    coalesce(p_source, 'contribution'),
    greatest(least(coalesce(p_confidence_score, 0.75), 1), 0),
    v_metadata
      || jsonb_build_object(
        'created_via', 'private.ensure_global_product_barcode',
        'phase', '6.19C.5'
      ),
    'synced'
  )
  returning id
  into v_barcode_id;

  return v_barcode_id;
end;
$$;

comment on function private.ensure_global_product_barcode(uuid, text, text, text, numeric, jsonb) is
'Ensures a global active barcode exists for a master product, avoiding conflicts with other master products.';

-- =========================================================
-- 3. RPC principal de revisión
-- =========================================================

create or replace function public.review_product_catalog_contribution(
  p_contribution_id uuid,
  p_action text,
  p_review_notes text default null,
  p_target_master_product_id uuid default null,
  p_rejected_reason text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_action text;
  v_metadata jsonb;

  v_contribution public.product_catalog_contributions%rowtype;

  v_target_master_id uuid;
  v_new_master_id uuid;
  v_global_barcode_id uuid;

  v_status text;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_contribution_id is null then
    raise exception 'contribution_id is required';
  end if;

  v_action := lower(nullif(btrim(coalesce(p_action, '')), ''));

  if v_action is null then
    raise exception 'action is required';
  end if;

  if v_action not in (
    'accept_new_product',
    'accept_improvement',
    'reject',
    'duplicate',
    'ignore'
  ) then
    raise exception 'Invalid review action: %', v_action;
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  select pcc.*
  into v_contribution
  from public.product_catalog_contributions pcc
  where pcc.id = p_contribution_id
    and pcc.deleted_at is null
  limit 1
  for update;

  if v_contribution.id is null then
    raise exception 'Contribution not found';
  end if;

  if v_contribution.status <> 'pending_review' then
    raise exception 'Only pending_review contributions can be reviewed. Current status: %', v_contribution.status;
  end if;

  if not private.can_review_product_catalog_contribution(v_contribution.business_id) then
    raise exception 'Insufficient permission to review product catalog contribution';
  end if;

  -- =======================================================
  -- Reject / ignore / duplicate: no mutan el catálogo maestro.
  -- =======================================================

  if v_action = 'reject' then
    update public.product_catalog_contributions pcc
    set
      status = 'rejected',
      reviewed_at = now(),
      reviewed_by = v_profile_id,
      review_notes = p_review_notes,
      rejected_reason = coalesce(p_rejected_reason, p_review_notes, 'Rejected by reviewer'),
      metadata = coalesce(pcc.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'reviewed_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'reviewed_at', now()
        ),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where pcc.id = v_contribution.id
    returning *
    into v_contribution;

    return jsonb_build_object(
      'contribution_id', v_contribution.id,
      'action', v_action,
      'status', v_contribution.status,
      'accepted_master_product_id', v_contribution.accepted_master_product_id,
      'global_barcode_id', null,
      'master_product_created', false,
      'master_product_updated', false
    );
  end if;

  if v_action = 'ignore' then
    update public.product_catalog_contributions pcc
    set
      status = 'ignored',
      reviewed_at = now(),
      reviewed_by = v_profile_id,
      review_notes = p_review_notes,
      metadata = coalesce(pcc.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'reviewed_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'reviewed_at', now()
        ),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where pcc.id = v_contribution.id
    returning *
    into v_contribution;

    return jsonb_build_object(
      'contribution_id', v_contribution.id,
      'action', v_action,
      'status', v_contribution.status,
      'accepted_master_product_id', v_contribution.accepted_master_product_id,
      'global_barcode_id', null,
      'master_product_created', false,
      'master_product_updated', false
    );
  end if;

  if v_action = 'duplicate' then
    v_target_master_id := coalesce(
      p_target_master_product_id,
      v_contribution.master_product_id,
      v_contribution.accepted_master_product_id
    );

    if v_target_master_id is not null
       and not exists (
         select 1
         from public.master_products_catalog m
         where m.id = v_target_master_id
           and m.deleted_at is null
       )
    then
      raise exception 'target master product does not exist';
    end if;

    update public.product_catalog_contributions pcc
    set
      status = 'duplicate',
      reviewed_at = now(),
      reviewed_by = v_profile_id,
      review_notes = p_review_notes,
      accepted_master_product_id = v_target_master_id,
      metadata = coalesce(pcc.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'reviewed_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'reviewed_at', now()
        ),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where pcc.id = v_contribution.id
    returning *
    into v_contribution;

    return jsonb_build_object(
      'contribution_id', v_contribution.id,
      'action', v_action,
      'status', v_contribution.status,
      'accepted_master_product_id', v_contribution.accepted_master_product_id,
      'global_barcode_id', null,
      'master_product_created', false,
      'master_product_updated', false
    );
  end if;

  -- =======================================================
  -- accept_new_product
  -- =======================================================

  if v_action = 'accept_new_product' then
    if v_contribution.suggested_name is null then
      raise exception 'suggested_name is required to accept a new master product';
    end if;

    v_new_master_id := extensions.gen_random_uuid();

    insert into public.master_products_catalog (
      id,
      barcode,
      gtin,
      product_name,
      name,

      brand,
      manufacturer,
      category_name,
      subcategory_name,

      package_size,
      package_unit,
      unit_type,

      image_url,
      image_thumb_url,
      image_hash,

      source,
      verification_status,
      confidence_score,
      catalog_version,
      metadata,
      sync_status,
      created_by,
      updated_by
    )
    values (
      v_new_master_id,
      v_contribution.barcode,
      case
        when v_contribution.barcode_type in ('gtin', 'ean13', 'ean8', 'upc')
        then v_contribution.barcode
        else null
      end,
      v_contribution.suggested_name,
      v_contribution.suggested_name,

      v_contribution.suggested_brand,
      v_contribution.suggested_manufacturer,
      v_contribution.suggested_category_name,
      v_contribution.suggested_subcategory_name,

      v_contribution.suggested_package_size,
      v_contribution.suggested_package_unit,
      v_contribution.suggested_unit_type,

      v_contribution.suggested_image_url,
      v_contribution.suggested_image_thumb_url,
      v_contribution.suggested_image_hash,

      'contribution',
      'community',
      greatest(least(coalesce(v_contribution.confidence_score, 0.5), 1), 0),
      greatest(coalesce(v_contribution.evidence_count, 1), 1),
      coalesce(v_contribution.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'created_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'source_contribution_id', v_contribution.id,
          'phase', '6.19C.5'
        ),
      'synced',
      v_profile_id,
      v_profile_id
    );

    v_target_master_id := v_new_master_id;

    if v_contribution.barcode is not null then
      v_global_barcode_id := private.ensure_global_product_barcode(
        v_target_master_id,
        v_contribution.barcode,
        v_contribution.barcode_type,
        'contribution',
        v_contribution.confidence_score,
        jsonb_build_object(
          'source_contribution_id', v_contribution.id,
          'phase', '6.19C.5'
        )
      );
    end if;

    update public.product_catalog_contributions pcc
    set
      status = 'accepted',
      reviewed_at = now(),
      reviewed_by = v_profile_id,
      review_notes = p_review_notes,
      accepted_master_product_id = v_target_master_id,
      metadata = coalesce(pcc.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'reviewed_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'reviewed_at', now(),
          'created_master_product_id', v_target_master_id
        ),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where pcc.id = v_contribution.id
    returning *
    into v_contribution;

    -- Vincular producto local si existe.
    if v_contribution.local_product_id is not null then
      update public.products p
      set
        master_product_id = v_target_master_id,
        catalog_match_confidence = greatest(coalesce(p.catalog_match_confidence, 0), 0.90),
        catalog_linked_at = coalesce(p.catalog_linked_at, now()),
        updated_at = now(),
        updated_by = v_profile_id
      where p.id = v_contribution.local_product_id
        and p.business_id = v_contribution.business_id
        and p.deleted_at is null;
    end if;

    return jsonb_build_object(
      'contribution_id', v_contribution.id,
      'action', v_action,
      'status', v_contribution.status,
      'accepted_master_product_id', v_target_master_id,
      'global_barcode_id', v_global_barcode_id,
      'master_product_created', true,
      'master_product_updated', false
    );
  end if;

  -- =======================================================
  -- accept_improvement
  -- =======================================================

  if v_action = 'accept_improvement' then
    v_target_master_id := coalesce(
      p_target_master_product_id,
      v_contribution.master_product_id,
      v_contribution.accepted_master_product_id
    );

    if v_target_master_id is null then
      raise exception 'target master product is required to accept improvement';
    end if;

    if not exists (
      select 1
      from public.master_products_catalog m
      where m.id = v_target_master_id
        and m.deleted_at is null
    ) then
      raise exception 'target master product does not exist';
    end if;

    update public.master_products_catalog m
    set
      product_name = coalesce(v_contribution.suggested_name, m.product_name),
      name = coalesce(v_contribution.suggested_name, m.name),

      brand = coalesce(v_contribution.suggested_brand, m.brand),
      manufacturer = coalesce(v_contribution.suggested_manufacturer, m.manufacturer),
      category_name = coalesce(v_contribution.suggested_category_name, m.category_name),
      subcategory_name = coalesce(v_contribution.suggested_subcategory_name, m.subcategory_name),

      package_size = coalesce(v_contribution.suggested_package_size, m.package_size),
      package_unit = coalesce(v_contribution.suggested_package_unit, m.package_unit),
      unit_type = coalesce(v_contribution.suggested_unit_type, m.unit_type),

      image_url = coalesce(v_contribution.suggested_image_url, m.image_url),
      image_thumb_url = coalesce(v_contribution.suggested_image_thumb_url, m.image_thumb_url),
      image_hash = coalesce(v_contribution.suggested_image_hash, m.image_hash),

      verification_status = case
        when m.verification_status in ('verified', 'gs1_verified') then m.verification_status
        else 'community'
      end,
      confidence_score = greatest(
        coalesce(m.confidence_score, 0),
        coalesce(v_contribution.confidence_score, 0)
      ),
      catalog_version = greatest(coalesce(m.catalog_version, 1), coalesce(v_contribution.evidence_count, 1)),
      metadata = coalesce(m.metadata, '{}'::jsonb)
        || jsonb_build_object(
          'last_contribution_id', v_contribution.id,
          'last_review_action', v_action,
          'last_reviewed_at', now()
        )
        || v_metadata,
      sync_status = 'synced',
      updated_by = v_profile_id
    where m.id = v_target_master_id;

    if v_contribution.barcode is not null then
      v_global_barcode_id := private.ensure_global_product_barcode(
        v_target_master_id,
        v_contribution.barcode,
        v_contribution.barcode_type,
        'contribution',
        v_contribution.confidence_score,
        jsonb_build_object(
          'source_contribution_id', v_contribution.id,
          'phase', '6.19C.5'
        )
      );
    end if;

    update public.product_catalog_contributions pcc
    set
      status = 'merged',
      reviewed_at = now(),
      reviewed_by = v_profile_id,
      review_notes = p_review_notes,
      accepted_master_product_id = v_target_master_id,
      metadata = coalesce(pcc.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'reviewed_via', 'public.review_product_catalog_contribution',
          'review_action', v_action,
          'reviewed_at', now(),
          'updated_master_product_id', v_target_master_id
        ),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where pcc.id = v_contribution.id
    returning *
    into v_contribution;

    -- Vincular producto local si existe.
    if v_contribution.local_product_id is not null then
      update public.products p
      set
        master_product_id = v_target_master_id,
        catalog_match_confidence = greatest(coalesce(p.catalog_match_confidence, 0), 0.90),
        catalog_linked_at = coalesce(p.catalog_linked_at, now()),
        updated_at = now(),
        updated_by = v_profile_id
      where p.id = v_contribution.local_product_id
        and p.business_id = v_contribution.business_id
        and p.deleted_at is null;
    end if;

    return jsonb_build_object(
      'contribution_id', v_contribution.id,
      'action', v_action,
      'status', v_contribution.status,
      'accepted_master_product_id', v_target_master_id,
      'global_barcode_id', v_global_barcode_id,
      'master_product_created', false,
      'master_product_updated', true
    );
  end if;

  raise exception 'Unhandled review action';
end;
$$;

revoke all on function public.review_product_catalog_contribution(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) from public;

grant execute on function public.review_product_catalog_contribution(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) to authenticated;

comment on function public.review_product_catalog_contribution(
  uuid,
  text,
  text,
  uuid,
  text,
  jsonb
) is
'Reviews product catalog contributions. Can accept as new master product, merge as improvement, reject, mark duplicate, or ignore.';

-- Grants for helpers are not exposed publicly.