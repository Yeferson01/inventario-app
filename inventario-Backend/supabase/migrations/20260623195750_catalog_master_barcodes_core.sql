-- =========================================================
-- Fase 6.19C.1 - Catálogo maestro offline-first + barcodes core
-- Objetivo:
-- - Normalizar master_products_catalog para catálogo liviano offline.
-- - Vincular products con master_product_id.
-- - Crear product_barcodes para códigos globales y locales por negocio.
-- - Permitir escaneo offline contra catálogo local sincronizado 1-2 veces al día.
-- =========================================================

-- =========================================================
-- 1. Helper de normalización de códigos
-- =========================================================

create or replace function private.normalize_barcode(
  p_barcode text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select nullif(
    upper(
      regexp_replace(
        btrim(coalesce(p_barcode, '')),
        '[^A-Za-z0-9]',
        '',
        'g'
      )
    ),
    ''
  );
$$;

comment on function private.normalize_barcode(text) is
'Normalizes global and local barcodes by trimming, uppercasing, and removing non-alphanumeric separators.';

-- =========================================================
-- 2. Asegurar/normalizar master_products_catalog
-- =========================================================

create table if not exists public.master_products_catalog (
  id uuid primary key default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.master_products_catalog
  add column if not exists id uuid;

update public.master_products_catalog
set id = extensions.gen_random_uuid()
where id is null;

alter table public.master_products_catalog
  alter column id set default extensions.gen_random_uuid(),
  alter column id set not null;

do $$
declare
  v_attnum smallint;
begin
  select a.attnum
  into v_attnum
  from pg_attribute a
  where a.attrelid = 'public.master_products_catalog'::regclass
    and a.attname = 'id'
    and not a.attisdropped;

  if not exists (
    select 1
    from pg_constraint c
    where c.conrelid = 'public.master_products_catalog'::regclass
      and c.contype in ('p', 'u')
      and c.conkey = array[v_attnum]
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_id_unique unique (id);
  end if;
end $$;

alter table public.master_products_catalog
  add column if not exists barcode text,
  add column if not exists gtin text,
  add column if not exists barcode_normalized text,

  add column if not exists name text,
  add column if not exists normalized_name text,
  add column if not exists brand text,
  add column if not exists manufacturer text,

  add column if not exists category_name text,
  add column if not exists subcategory_name text,

  add column if not exists package_size numeric(14,4),
  add column if not exists package_unit text,
  add column if not exists unit_type text,

  add column if not exists image_url text,
  add column if not exists image_thumb_url text,
  add column if not exists image_hash text,
  add column if not exists has_image boolean not null default false,

  add column if not exists source text not null default 'manual',
  add column if not exists verification_status text not null default 'unverified',
  add column if not exists confidence_score numeric(5,4) not null default 0,

  add column if not exists catalog_version bigint not null default 1,

  add column if not exists metadata jsonb not null default '{}'::jsonb,

  add column if not exists sync_status text not null default 'synced',
  add column if not exists version integer not null default 1,

  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists deleted_at timestamptz,
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid,
  add column if not exists deleted_by uuid,
  add column if not exists delete_reason text;

update public.master_products_catalog
set
  barcode_normalized = coalesce(
    barcode_normalized,
    private.normalize_barcode(coalesce(gtin, barcode))
  ),
  normalized_name = coalesce(
    normalized_name,
    nullif(lower(btrim(coalesce(name, ''))), '')
  ),
  has_image = coalesce(has_image, image_url is not null or image_thumb_url is not null),
  metadata = coalesce(metadata, '{}'::jsonb),
  sync_status = coalesce(sync_status, 'synced'),
  version = greatest(coalesce(version, 1), 1),
  catalog_version = greatest(coalesce(catalog_version, 1), 1)
where true;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'master_products_catalog_sync_status_check'
      and conrelid = 'public.master_products_catalog'::regclass
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_sync_status_check
      check (sync_status in ('synced', 'pending', 'conflict', 'error'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'master_products_catalog_version_check'
      and conrelid = 'public.master_products_catalog'::regclass
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_version_check
      check (version >= 1);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'master_products_catalog_catalog_version_check'
      and conrelid = 'public.master_products_catalog'::regclass
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_catalog_version_check
      check (catalog_version >= 1);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'master_products_catalog_confidence_score_check'
      and conrelid = 'public.master_products_catalog'::regclass
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_confidence_score_check
      check (confidence_score >= 0 and confidence_score <= 1);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'master_products_catalog_verification_status_check'
      and conrelid = 'public.master_products_catalog'::regclass
  ) then
    alter table public.master_products_catalog
      add constraint master_products_catalog_verification_status_check
      check (
        verification_status in (
          'unverified',
          'community',
          'verified',
          'gs1_verified',
          'rejected',
          'deprecated'
        )
      );
  end if;
end $$;

create index if not exists idx_master_products_catalog_barcode_normalized
on public.master_products_catalog (barcode_normalized)
where deleted_at is null and barcode_normalized is not null;

create index if not exists idx_master_products_catalog_catalog_version
on public.master_products_catalog (catalog_version, updated_at, id)
where deleted_at is null;

create index if not exists idx_master_products_catalog_name_brand
on public.master_products_catalog (normalized_name, brand)
where deleted_at is null;

create index if not exists idx_master_products_catalog_updated
on public.master_products_catalog (updated_at, id)
where deleted_at is null;

-- Trigger de normalización/versionado para catálogo maestro.
create or replace function private.touch_master_products_catalog()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.barcode_normalized := private.normalize_barcode(coalesce(new.gtin, new.barcode));
  new.normalized_name := nullif(lower(btrim(coalesce(new.name, ''))), '');
  new.has_image := coalesce(new.image_url is not null or new.image_thumb_url is not null, false);
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.catalog_version := greatest(coalesce(new.catalog_version, 1), 1);

  if tg_op = 'UPDATE' then
    new.updated_at := now();
    new.version := coalesce(old.version, 1) + 1;
  else
    new.version := greatest(coalesce(new.version, 1), 1);
    new.created_at := coalesce(new.created_at, now());
    new.updated_at := coalesce(new.updated_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_master_products_catalog_touch on public.master_products_catalog;

create trigger trg_master_products_catalog_touch
before insert or update on public.master_products_catalog
for each row
execute function private.touch_master_products_catalog();

-- =========================================================
-- 3. Vincular products con master_products_catalog
-- =========================================================

alter table public.products
  add column if not exists master_product_id uuid,
  add column if not exists catalog_match_confidence numeric(5,4),
  add column if not exists catalog_linked_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_master_product_id_fkey'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_master_product_id_fkey
      foreign key (master_product_id)
      references public.master_products_catalog(id)
      on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_catalog_match_confidence_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_catalog_match_confidence_check
      check (
        catalog_match_confidence is null
        or (catalog_match_confidence >= 0 and catalog_match_confidence <= 1)
      );
  end if;
end $$;

create index if not exists idx_products_master_product_id
on public.products (master_product_id)
where deleted_at is null;

create index if not exists idx_products_business_master_product
on public.products (business_id, master_product_id)
where deleted_at is null and master_product_id is not null;

-- =========================================================
-- 4. Crear product_barcodes
-- =========================================================

create table if not exists public.product_barcodes (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid references public.businesses(id) on delete cascade,
  master_product_id uuid references public.master_products_catalog(id) on delete cascade,
  product_id uuid references public.products(id) on delete cascade,

  barcode text not null,
  barcode_normalized text not null,

  barcode_type text not null default 'unknown',
  scope text not null default 'business',

  is_primary boolean not null default false,
  status text not null default 'active',

  source text not null default 'manual',
  confidence_score numeric(5,4) not null default 0,

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

  constraint product_barcodes_barcode_not_blank
    check (btrim(barcode) <> ''),

  constraint product_barcodes_barcode_normalized_not_blank
    check (btrim(barcode_normalized) <> ''),

  constraint product_barcodes_type_check
    check (barcode_type in ('gtin', 'ean13', 'ean8', 'upc', 'local_sku', 'internal', 'unknown')),

  constraint product_barcodes_scope_check
    check (scope in ('global', 'business')),

  constraint product_barcodes_status_check
    check (status in ('active', 'inactive', 'pending_review', 'deprecated')),

  constraint product_barcodes_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error')),

  constraint product_barcodes_version_check
    check (version >= 1),

  constraint product_barcodes_confidence_score_check
    check (confidence_score >= 0 and confidence_score <= 1),

  constraint product_barcodes_global_scope_shape
    check (
      scope <> 'global'
      or (
        business_id is null
        and product_id is null
        and master_product_id is not null
      )
    ),

  constraint product_barcodes_business_scope_shape
    check (
      scope <> 'business'
      or (
        business_id is not null
        and product_id is not null
      )
    )
);

create unique index if not exists idx_product_barcodes_global_unique
on public.product_barcodes (barcode_normalized)
where scope = 'global'
  and deleted_at is null
  and status = 'active';

create unique index if not exists idx_product_barcodes_business_unique
on public.product_barcodes (business_id, barcode_normalized)
where scope = 'business'
  and deleted_at is null
  and status = 'active';

create unique index if not exists idx_product_barcodes_product_primary_unique
on public.product_barcodes (product_id)
where is_primary = true
  and deleted_at is null
  and status = 'active';

create index if not exists idx_product_barcodes_master_product
on public.product_barcodes (master_product_id)
where deleted_at is null;

create index if not exists idx_product_barcodes_product
on public.product_barcodes (product_id)
where deleted_at is null;

create index if not exists idx_product_barcodes_business_product
on public.product_barcodes (business_id, product_id)
where deleted_at is null;

create index if not exists idx_product_barcodes_updated
on public.product_barcodes (updated_at, id)
where deleted_at is null;

-- =========================================================
-- 5. Triggers de product_barcodes
-- =========================================================

create or replace function private.prepare_product_barcode_before_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product_business_id uuid;
  v_product_master_product_id uuid;
begin
  new.barcode_normalized := private.normalize_barcode(new.barcode);

  if new.barcode_normalized is null then
    raise exception 'barcode cannot be empty';
  end if;

  new.scope := lower(coalesce(new.scope, 'business'));
  new.barcode_type := lower(coalesce(new.barcode_type, 'unknown'));
  new.status := lower(coalesce(new.status, 'active'));
  new.sync_status := coalesce(new.sync_status, 'synced');
  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.version := greatest(coalesce(new.version, 1), 1);

  if new.scope = 'global' then
    if new.business_id is not null or new.product_id is not null or new.master_product_id is null then
      raise exception 'Global barcode must have master_product_id and must not have business_id/product_id';
    end if;

    if not exists (
      select 1
      from public.master_products_catalog m
      where m.id = new.master_product_id
        and m.deleted_at is null
    ) then
      raise exception 'master_product_id does not exist for global barcode';
    end if;
  end if;

  if new.scope = 'business' then
    if new.business_id is null or new.product_id is null then
      raise exception 'Business barcode must have business_id and product_id';
    end if;

    select
      p.business_id,
      p.master_product_id
    into
      v_product_business_id,
      v_product_master_product_id
    from public.products p
    where p.id = new.product_id
      and p.deleted_at is null;

    if v_product_business_id is null then
      raise exception 'product_id does not exist for business barcode';
    end if;

    if v_product_business_id <> new.business_id then
      raise exception 'product_id does not belong to barcode business_id';
    end if;

    if new.master_product_id is not null
       and v_product_master_product_id is not null
       and new.master_product_id <> v_product_master_product_id
    then
      raise exception 'barcode master_product_id does not match product.master_product_id';
    end if;

    if new.master_product_id is not null
       and not exists (
         select 1
         from public.master_products_catalog m
         where m.id = new.master_product_id
           and m.deleted_at is null
       )
    then
      raise exception 'master_product_id does not exist for business barcode';
    end if;
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

drop trigger if exists trg_product_barcodes_prepare on public.product_barcodes;

create trigger trg_product_barcodes_prepare
before insert or update on public.product_barcodes
for each row
execute function private.prepare_product_barcode_before_write();

-- =========================================================
-- 6. Seed inicial desde master_products_catalog y products
-- =========================================================

insert into public.product_barcodes (
  master_product_id,
  barcode,
  barcode_type,
  scope,
  is_primary,
  status,
  source,
  confidence_score,
  sync_status,
  metadata
)
select
  m.id,
  coalesce(m.gtin, m.barcode),
  case
    when length(private.normalize_barcode(coalesce(m.gtin, m.barcode))) = 13 then 'ean13'
    when length(private.normalize_barcode(coalesce(m.gtin, m.barcode))) = 12 then 'upc'
    when length(private.normalize_barcode(coalesce(m.gtin, m.barcode))) = 8 then 'ean8'
    else 'gtin'
  end,
  'global',
  true,
  'active',
  coalesce(m.source, 'master_products_catalog'),
  greatest(coalesce(m.confidence_score, 0), 0),
  'synced',
  jsonb_build_object(
    'seeded_from', 'master_products_catalog',
    'phase', '6.19C.1'
  )
from public.master_products_catalog m
where m.deleted_at is null
  and private.normalize_barcode(coalesce(m.gtin, m.barcode)) is not null
on conflict do nothing;

insert into public.product_barcodes (
  business_id,
  master_product_id,
  product_id,
  barcode,
  barcode_type,
  scope,
  is_primary,
  status,
  source,
  confidence_score,
  sync_status,
  metadata
)
select
  p.business_id,
  p.master_product_id,
  p.id,
  p.barcode,
  case
    when length(private.normalize_barcode(p.barcode)) = 13 then 'ean13'
    when length(private.normalize_barcode(p.barcode)) = 12 then 'upc'
    when length(private.normalize_barcode(p.barcode)) = 8 then 'ean8'
    else 'local_sku'
  end,
  'business',
  true,
  'active',
  'products.barcode',
  case when p.master_product_id is not null then 0.90 else 0.50 end,
  'synced',
  jsonb_build_object(
    'seeded_from', 'products.barcode',
    'phase', '6.19C.1'
  )
from public.products p
where p.deleted_at is null
  and p.barcode is not null
  and private.normalize_barcode(p.barcode) is not null
on conflict do nothing;

-- =========================================================
-- 7. RLS y grants
-- =========================================================

alter table public.master_products_catalog enable row level security;
alter table public.product_barcodes enable row level security;

drop policy if exists master_products_catalog_select_authenticated on public.master_products_catalog;

create policy master_products_catalog_select_authenticated
on public.master_products_catalog
for select
to authenticated
using (
  deleted_at is null
  and coalesce(sync_status, 'synced') = 'synced'
);

drop policy if exists product_barcodes_select_authenticated on public.product_barcodes;

create policy product_barcodes_select_authenticated
on public.product_barcodes
for select
to authenticated
using (
  deleted_at is null
  and status = 'active'
  and (
    scope = 'global'
    or (
      scope = 'business'
      and business_id is not null
      and private.is_business_member(business_id)
    )
  )
);

drop policy if exists product_barcodes_insert_business on public.product_barcodes;

create policy product_barcodes_insert_business
on public.product_barcodes
for insert
to authenticated
with check (
  scope = 'business'
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'products.create')
    or private.has_business_permission(business_id, 'products.update')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

drop policy if exists product_barcodes_update_business on public.product_barcodes;

create policy product_barcodes_update_business
on public.product_barcodes
for update
to authenticated
using (
  scope = 'business'
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'products.update')
    or private.has_business_permission(business_id, 'settings.business')
  )
)
with check (
  scope = 'business'
  and business_id is not null
  and (
    private.has_business_permission(business_id, 'products.update')
    or private.has_business_permission(business_id, 'settings.business')
  )
);

-- No DELETE policy: se debe usar soft delete.

grant select on public.master_products_catalog to authenticated;
grant select, insert, update on public.product_barcodes to authenticated;

comment on table public.product_barcodes is
'Stores global standardized barcodes and business-local barcodes for offline-first product lookup.';