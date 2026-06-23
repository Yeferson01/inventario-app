-- =========================================================
-- Fase 6.19C.4 - Product catalog contributions
-- Objetivo:
-- - Permitir que negocios/tenderos sugieran productos nuevos o mejoras.
-- - No contaminar automáticamente master_products_catalog.
-- - Dejar contribuciones en pending_review para revisión futura.
-- - Soportar offline-first: la app puede subir contribuciones desde sync.
-- =========================================================

create table if not exists public.product_catalog_contributions (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid references public.branches(id) on delete set null,
  profile_id uuid not null,

  local_product_id uuid references public.products(id) on delete set null,
  master_product_id uuid references public.master_products_catalog(id) on delete set null,

  contribution_type text not null default 'new_product',

  barcode text,
  barcode_normalized text,
  barcode_type text not null default 'unknown',

  suggested_name text,
  suggested_brand text,
  suggested_manufacturer text,
  suggested_category_name text,
  suggested_subcategory_name text,
  suggested_package_size numeric(14,4),
  suggested_package_unit text,
  suggested_unit_type text,

  suggested_image_url text,
  suggested_image_thumb_url text,
  suggested_image_hash text,

  source text not null default 'app',
  confidence_score numeric(5,4) not null default 0,
  evidence_count integer not null default 1,

  status text not null default 'pending_review',

  reviewed_at timestamptz,
  reviewed_by uuid,
  review_notes text,

  accepted_master_product_id uuid references public.master_products_catalog(id) on delete set null,
  rejected_reason text,

  metadata jsonb not null default '{}'::jsonb,

  sync_status text not null default 'synced',
  version integer not null default 1,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,

  created_by uuid,
  updated_by uuid,
  deleted_by uuid,
  delete_reason text,

  constraint product_catalog_contributions_type_check
    check (
      contribution_type in (
        'new_product',
        'improve_existing',
        'barcode_alias',
        'correction',
        'image_suggestion',
        'category_suggestion',
        'package_suggestion'
      )
    ),

  constraint product_catalog_contributions_barcode_type_check
    check (barcode_type in ('gtin', 'ean13', 'ean8', 'upc', 'local_sku', 'internal', 'unknown')),

  constraint product_catalog_contributions_status_check
    check (
      status in (
        'pending_review',
        'accepted',
        'rejected',
        'merged',
        'duplicate',
        'ignored'
      )
    ),

  constraint product_catalog_contributions_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint product_catalog_contributions_version_check
    check (version >= 1),

  constraint product_catalog_contributions_confidence_score_check
    check (confidence_score >= 0 and confidence_score <= 1),

  constraint product_catalog_contributions_evidence_count_check
    check (evidence_count >= 1),

  constraint product_catalog_contributions_package_size_check
    check (suggested_package_size is null or suggested_package_size > 0),

  constraint product_catalog_contributions_has_useful_data_check
    check (
      barcode is not null
      or local_product_id is not null
      or master_product_id is not null
      or suggested_name is not null
      or suggested_brand is not null
      or suggested_category_name is not null
      or suggested_package_size is not null
      or suggested_image_url is not null
      or suggested_image_thumb_url is not null
    )
);

create index if not exists idx_product_catalog_contributions_business_status_created
on public.product_catalog_contributions (business_id, status, created_at desc)
where deleted_at is null;

create index if not exists idx_product_catalog_contributions_barcode_normalized
on public.product_catalog_contributions (barcode_normalized)
where deleted_at is null and barcode_normalized is not null;

create index if not exists idx_product_catalog_contributions_master_product
on public.product_catalog_contributions (master_product_id, status, created_at desc)
where deleted_at is null and master_product_id is not null;

create index if not exists idx_product_catalog_contributions_local_product
on public.product_catalog_contributions (local_product_id, status, created_at desc)
where deleted_at is null and local_product_id is not null;

create index if not exists idx_product_catalog_contributions_review_queue
on public.product_catalog_contributions (status, contribution_type, created_at)
where deleted_at is null and status = 'pending_review';

-- Evita contribuciones duplicadas activas exactas por negocio/barcode/tipo.
create unique index if not exists idx_product_catalog_contributions_business_barcode_type_pending_unique
on public.product_catalog_contributions (business_id, barcode_normalized, contribution_type)
where deleted_at is null
  and status = 'pending_review'
  and barcode_normalized is not null;

-- =========================================================
-- Trigger de preparación/validación
-- =========================================================

create or replace function private.prepare_product_catalog_contribution()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product_business_id uuid;
  v_product_master_product_id uuid;
begin
  new.contribution_type := lower(coalesce(new.contribution_type, 'new_product'));
  new.barcode_type := lower(coalesce(new.barcode_type, 'unknown'));
  new.status := lower(coalesce(new.status, 'pending_review'));
  new.source := lower(coalesce(new.source, 'app'));
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.version := greatest(coalesce(new.version, 1), 1);
  new.evidence_count := greatest(coalesce(new.evidence_count, 1), 1);
  new.confidence_score := greatest(least(coalesce(new.confidence_score, 0), 1), 0);

  new.barcode := nullif(btrim(new.barcode), '');
  new.barcode_normalized := private.normalize_barcode(new.barcode);

  new.suggested_name := nullif(btrim(new.suggested_name), '');
  new.suggested_brand := nullif(btrim(new.suggested_brand), '');
  new.suggested_manufacturer := nullif(btrim(new.suggested_manufacturer), '');
  new.suggested_category_name := nullif(btrim(new.suggested_category_name), '');
  new.suggested_subcategory_name := nullif(btrim(new.suggested_subcategory_name), '');
  new.suggested_package_unit := nullif(btrim(new.suggested_package_unit), '');
  new.suggested_unit_type := nullif(btrim(new.suggested_unit_type), '');
  new.suggested_image_url := nullif(btrim(new.suggested_image_url), '');
  new.suggested_image_thumb_url := nullif(btrim(new.suggested_image_thumb_url), '');
  new.suggested_image_hash := nullif(btrim(new.suggested_image_hash), '');

  if jsonb_typeof(new.metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  -- business debe existir.
  if not exists (
    select 1
    from public.businesses b
    where b.id = new.business_id
      and b.deleted_at is null
  ) then
    raise exception 'business_id does not exist or is deleted';
  end if;

  -- branch debe pertenecer al negocio si viene.
  if new.branch_id is not null
     and not exists (
       select 1
       from public.branches br
       where br.id = new.branch_id
         and br.business_id = new.business_id
         and br.deleted_at is null
     )
  then
    raise exception 'branch_id does not belong to contribution business_id';
  end if;

  -- local_product debe pertenecer al negocio si viene.
  if new.local_product_id is not null then
    select
      p.business_id,
      p.master_product_id
    into
      v_product_business_id,
      v_product_master_product_id
    from public.products p
    where p.id = new.local_product_id
      and p.deleted_at is null;

    if v_product_business_id is null then
      raise exception 'local_product_id does not exist or is deleted';
    end if;

    if v_product_business_id <> new.business_id then
      raise exception 'local_product_id does not belong to contribution business_id';
    end if;

    if new.master_product_id is null then
      new.master_product_id := v_product_master_product_id;
    elsif v_product_master_product_id is not null
          and new.master_product_id <> v_product_master_product_id
    then
      raise exception 'master_product_id does not match local product master_product_id';
    end if;
  end if;

  -- master_product debe existir si viene.
  if new.master_product_id is not null
     and not exists (
       select 1
       from public.master_products_catalog m
       where m.id = new.master_product_id
         and m.deleted_at is null
     )
  then
    raise exception 'master_product_id does not exist or is deleted';
  end if;

  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.version := coalesce(old.version, 1) + 1;
  else
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := coalesce(new.updated_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_product_catalog_contributions_prepare
on public.product_catalog_contributions;

create trigger trg_product_catalog_contributions_prepare
before insert or update on public.product_catalog_contributions
for each row
execute function private.prepare_product_catalog_contribution();

-- =========================================================
-- RPC para enviar contribución desde Flutter/backend
-- =========================================================

create or replace function public.submit_product_catalog_contribution(
  p_business_id uuid,
  p_branch_id uuid default null,
  p_local_product_id uuid default null,
  p_master_product_id uuid default null,

  p_contribution_type text default 'new_product',

  p_barcode text default null,
  p_barcode_type text default 'unknown',

  p_suggested_name text default null,
  p_suggested_brand text default null,
  p_suggested_manufacturer text default null,
  p_suggested_category_name text default null,
  p_suggested_subcategory_name text default null,
  p_suggested_package_size numeric default null,
  p_suggested_package_unit text default null,
  p_suggested_unit_type text default null,

  p_suggested_image_url text default null,
  p_suggested_image_thumb_url text default null,
  p_suggested_image_hash text default null,

  p_source text default 'app',
  p_confidence_score numeric default 0,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_contribution public.product_catalog_contributions%rowtype;
  v_barcode_normalized text;
  v_metadata jsonb;
begin
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if not private.is_business_member(p_business_id) then
    raise exception 'Insufficient permission to submit catalog contribution for this business';
  end if;

  if p_branch_id is not null
     and not private.has_branch_access(p_business_id, p_branch_id)
  then
    raise exception 'Insufficient permission to submit catalog contribution for this branch';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  v_barcode_normalized := private.normalize_barcode(p_barcode);

  -- Idempotencia simple para contribuciones pendientes por business + barcode + tipo.
  if v_barcode_normalized is not null then
    select pcc.*
    into v_contribution
    from public.product_catalog_contributions pcc
    where pcc.business_id = p_business_id
      and pcc.barcode_normalized = v_barcode_normalized
      and pcc.contribution_type = lower(coalesce(p_contribution_type, 'new_product'))
      and pcc.status = 'pending_review'
      and pcc.deleted_at is null
    order by pcc.created_at desc
    limit 1
    for update;

    if v_contribution.id is not null then
      update public.product_catalog_contributions pcc
      set
        branch_id = coalesce(p_branch_id, pcc.branch_id),
        profile_id = v_profile_id,
        local_product_id = coalesce(p_local_product_id, pcc.local_product_id),
        master_product_id = coalesce(p_master_product_id, pcc.master_product_id),

        suggested_name = coalesce(nullif(btrim(p_suggested_name), ''), pcc.suggested_name),
        suggested_brand = coalesce(nullif(btrim(p_suggested_brand), ''), pcc.suggested_brand),
        suggested_manufacturer = coalesce(nullif(btrim(p_suggested_manufacturer), ''), pcc.suggested_manufacturer),
        suggested_category_name = coalesce(nullif(btrim(p_suggested_category_name), ''), pcc.suggested_category_name),
        suggested_subcategory_name = coalesce(nullif(btrim(p_suggested_subcategory_name), ''), pcc.suggested_subcategory_name),
        suggested_package_size = coalesce(p_suggested_package_size, pcc.suggested_package_size),
        suggested_package_unit = coalesce(nullif(btrim(p_suggested_package_unit), ''), pcc.suggested_package_unit),
        suggested_unit_type = coalesce(nullif(btrim(p_suggested_unit_type), ''), pcc.suggested_unit_type),

        suggested_image_url = coalesce(nullif(btrim(p_suggested_image_url), ''), pcc.suggested_image_url),
        suggested_image_thumb_url = coalesce(nullif(btrim(p_suggested_image_thumb_url), ''), pcc.suggested_image_thumb_url),
        suggested_image_hash = coalesce(nullif(btrim(p_suggested_image_hash), ''), pcc.suggested_image_hash),

        source = lower(coalesce(p_source, pcc.source)),
        confidence_score = greatest(pcc.confidence_score, greatest(least(coalesce(p_confidence_score, 0), 1), 0)),
        evidence_count = pcc.evidence_count + 1,

        metadata = coalesce(pcc.metadata, '{}'::jsonb)
          || v_metadata
          || jsonb_build_object(
            'updated_via', 'public.submit_product_catalog_contribution',
            'last_submission_at', now()
          ),

        updated_by = v_profile_id,
        sync_status = 'synced'
      where pcc.id = v_contribution.id
      returning *
      into v_contribution;

      return jsonb_build_object(
        'contribution_id', v_contribution.id,
        'business_id', v_contribution.business_id,
        'branch_id', v_contribution.branch_id,
        'profile_id', v_contribution.profile_id,
        'local_product_id', v_contribution.local_product_id,
        'master_product_id', v_contribution.master_product_id,
        'contribution_type', v_contribution.contribution_type,
        'barcode', v_contribution.barcode,
        'barcode_normalized', v_contribution.barcode_normalized,
        'status', v_contribution.status,
        'evidence_count', v_contribution.evidence_count,
        'created_or_updated', 'updated_existing_pending'
      );
    end if;
  end if;

  insert into public.product_catalog_contributions (
    business_id,
    branch_id,
    profile_id,

    local_product_id,
    master_product_id,

    contribution_type,

    barcode,
    barcode_type,

    suggested_name,
    suggested_brand,
    suggested_manufacturer,
    suggested_category_name,
    suggested_subcategory_name,
    suggested_package_size,
    suggested_package_unit,
    suggested_unit_type,

    suggested_image_url,
    suggested_image_thumb_url,
    suggested_image_hash,

    source,
    confidence_score,

    metadata,

    created_by,
    updated_by
  )
  values (
    p_business_id,
    p_branch_id,
    v_profile_id,

    p_local_product_id,
    p_master_product_id,

    p_contribution_type,

    p_barcode,
    p_barcode_type,

    p_suggested_name,
    p_suggested_brand,
    p_suggested_manufacturer,
    p_suggested_category_name,
    p_suggested_subcategory_name,
    p_suggested_package_size,
    p_suggested_package_unit,
    p_suggested_unit_type,

    p_suggested_image_url,
    p_suggested_image_thumb_url,
    p_suggested_image_hash,

    p_source,
    p_confidence_score,

    v_metadata
      || jsonb_build_object(
        'created_via', 'public.submit_product_catalog_contribution',
        'phase', '6.19C.4'
      ),

    v_profile_id,
    v_profile_id
  )
  returning *
  into v_contribution;

  return jsonb_build_object(
    'contribution_id', v_contribution.id,
    'business_id', v_contribution.business_id,
    'branch_id', v_contribution.branch_id,
    'profile_id', v_contribution.profile_id,
    'local_product_id', v_contribution.local_product_id,
    'master_product_id', v_contribution.master_product_id,
    'contribution_type', v_contribution.contribution_type,
    'barcode', v_contribution.barcode,
    'barcode_normalized', v_contribution.barcode_normalized,
    'status', v_contribution.status,
    'evidence_count', v_contribution.evidence_count,
    'created_or_updated', 'created'
  );
end;
$$;

-- =========================================================
-- RLS
-- =========================================================

alter table public.product_catalog_contributions enable row level security;

drop policy if exists product_catalog_contributions_select_business
on public.product_catalog_contributions;

create policy product_catalog_contributions_select_business
on public.product_catalog_contributions
for select
to authenticated
using (
  deleted_at is null
  and private.is_business_member(business_id)
);

drop policy if exists product_catalog_contributions_insert_business
on public.product_catalog_contributions;

create policy product_catalog_contributions_insert_business
on public.product_catalog_contributions
for insert
to authenticated
with check (
  deleted_at is null
  and private.is_business_member(business_id)
  and (
    branch_id is null
    or private.has_branch_access(business_id, branch_id)
  )
);

drop policy if exists product_catalog_contributions_update_own_pending_or_admin
on public.product_catalog_contributions;

create policy product_catalog_contributions_update_own_pending_or_admin
on public.product_catalog_contributions
for update
to authenticated
using (
  deleted_at is null
  and private.is_business_member(business_id)
  and (
    (
      status = 'pending_review'
      and profile_id = private.current_profile_id()
    )
    or private.has_business_permission(business_id, 'settings.business')
    or private.has_business_permission(business_id, 'products.update')
  )
)
with check (
  deleted_at is null
  and private.is_business_member(business_id)
);

-- No DELETE policy. Solo soft delete si se requiere en fase posterior.

grant select, insert, update on public.product_catalog_contributions to authenticated;

revoke all on function public.submit_product_catalog_contribution(
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  jsonb
) from public;

grant execute on function public.submit_product_catalog_contribution(
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  jsonb
) to authenticated;

comment on table public.product_catalog_contributions is
'Stores business/user contributions to improve the global product catalog without automatically mutating master_products_catalog.';

comment on function public.submit_product_catalog_contribution(
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  text,
  text,
  text,
  text,
  text,
  text,
  numeric,
  jsonb
) is
'Submits or updates a pending product catalog contribution for review. Idempotent by business + normalized barcode + contribution_type while pending.';