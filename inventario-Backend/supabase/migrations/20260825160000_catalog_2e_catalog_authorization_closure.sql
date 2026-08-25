-- CATALOG-2E - Catalog authorization closure.
--
-- Tenant product permissions authorize only tenant-owned Products and
-- business-scoped ProductBarcodes. Global master catalog changes are made
-- only by trusted service_role review of a tenant contribution.

begin;

-- -------------------------------------------------------------------------
-- Sync authorization: explicit mappings only. Unknown entity/action pairs
-- must never inherit a broad business setting permission.
-- -------------------------------------------------------------------------

create or replace function private.sync_entity_permission_candidates(
  p_entity_table text,
  p_operation text
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text := lower(trim(coalesce(p_entity_table, '')));
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_action text;
begin
  v_action := case
    when v_operation in ('insert', 'upsert') then 'create'
    when v_operation = 'update' then 'update'
    when v_operation in ('soft_delete', 'delete') then 'soft_delete'
    else null
  end;

  if v_entity = '' or v_action is null or v_operation = 'delete' then
    return array[]::text[];
  end if;

  if v_entity = 'products' then
    return case v_operation
      when 'insert' then array['products.create']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'product_barcodes' then
    return case v_operation
      when 'insert' then array['products.create', 'products.update']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'categories' then
    return array[
      'categories.' || v_action,
      'products.' || v_action,
      'inventory.' || case when v_action = 'create' then 'adjust' else 'read' end
    ];
  end if;

  if v_entity = 'customers' then
    return array[
      'customers.' || v_action,
      'sales.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity = 'suppliers' then
    return array[
      'suppliers.' || v_action,
      'purchases.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity in ('purchases', 'purchase_items') then
    return array['purchases.' || v_action];
  end if;

  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array['sales.' || v_action];
  end if;

  if v_entity in ('cash_sessions', 'cash_registers') then
    return array[
      'sales.' || case
        when v_action = 'create' then 'create'
        when v_action = 'update' then 'update'
        else 'soft_delete'
      end
    ];
  end if;

  if v_entity = 'inventory_movements' then
    if v_operation in ('insert', 'upsert') then
      return array[
        'inventory.adjust',
        'inventory.count',
        'inventory.transfer',
        'purchases.create',
        'sales.create'
      ];
    end if;
    return array[]::text[];
  end if;

  if v_entity in ('stock_counts', 'stock_count_items') then
    return array['inventory.count'];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array['inventory.transfer'];
  end if;

  return array[]::text[];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text) is
'Returns explicit candidate permissions for supported sync entity/operation pairs. Unknown pairs and hard deletes fail closed.';

-- A product barcode mutation must remain in the exact batch tenant/device/
-- profile/branch scope. This closes the gap where process_sync_batch checks
-- permission against the batch but the barcode applier writes mutation scope.
create or replace function private.enforce_product_barcode_mutation_batch_scope()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.sync_batches%rowtype;
begin
  if lower(trim(coalesce(new.entity_table, ''))) <> 'product_barcodes' then
    return new;
  end if;

  select sb.*
  into v_batch
  from public.sync_batches sb
  where sb.id = new.sync_batch_id;

  if v_batch.id is null then
    raise exception 'Product barcode mutation sync batch does not exist';
  end if;

  if new.business_id is distinct from v_batch.business_id
     or new.app_device_id is distinct from v_batch.app_device_id
     or new.profile_id is distinct from v_batch.profile_id
     or new.branch_id is distinct from v_batch.branch_id
  then
    raise exception 'Product barcode mutation scope must match its sync batch';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_sync_mutations_product_barcode_batch_scope
on public.sync_mutations;

create trigger trg_sync_mutations_product_barcode_batch_scope
before insert or update of
  business_id,
  sync_batch_id,
  app_device_id,
  profile_id,
  branch_id,
  entity_table
on public.sync_mutations
for each row
execute function private.enforce_product_barcode_mutation_batch_scope();

revoke all on function private.enforce_product_barcode_mutation_batch_scope()
from public, anon, authenticated;

-- -------------------------------------------------------------------------
-- Direct ProductBarcode table access. Authenticated users may write only a
-- business code whose Product belongs to that same business. settings.business
-- does not confer product mutation authority.
-- -------------------------------------------------------------------------

create or replace function private.enforce_product_barcode_scope_ownership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.scope is distinct from new.scope
     or old.business_id is distinct from new.business_id
  then
    raise exception 'Product barcode scope and business ownership are immutable';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_product_barcodes_scope_ownership
on public.product_barcodes;

create trigger trg_product_barcodes_scope_ownership
before update of scope, business_id on public.product_barcodes
for each row
execute function private.enforce_product_barcode_scope_ownership();

revoke all on function private.enforce_product_barcode_scope_ownership()
from public, anon, authenticated;

drop policy if exists product_barcodes_insert_business
on public.product_barcodes;

create policy product_barcodes_insert_business
on public.product_barcodes
for insert
to authenticated
with check (
  scope = 'business'
  and business_id is not null
  and product_id is not null
  and deleted_at is null
  and exists (
    select 1
    from public.products p
    where p.id = product_barcodes.product_id
      and p.business_id = product_barcodes.business_id
      and p.deleted_at is null
  )
  and (
    private.has_business_permission(business_id, 'products.create')
    or private.has_business_permission(business_id, 'products.update')
  )
);

drop policy if exists product_barcodes_update_business
on public.product_barcodes;
drop policy if exists product_barcodes_soft_delete_business
on public.product_barcodes;

create policy product_barcodes_update_business
on public.product_barcodes
for update
to authenticated
using (
  scope = 'business'
  and business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'products.update')
)
with check (
  scope = 'business'
  and business_id is not null
  and product_id is not null
  and deleted_at is null
  and exists (
    select 1
    from public.products p
    where p.id = product_barcodes.product_id
      and p.business_id = product_barcodes.business_id
      and p.deleted_at is null
  )
  and private.has_business_permission(business_id, 'products.update')
);

create policy product_barcodes_soft_delete_business
on public.product_barcodes
for update
to authenticated
using (
  scope = 'business'
  and business_id is not null
  and deleted_at is null
  and private.has_business_permission(business_id, 'products.soft_delete')
)
with check (
  scope = 'business'
  and business_id is not null
  and product_id is not null
  and deleted_at is not null
  and private.has_business_permission(business_id, 'products.soft_delete')
);

revoke insert, update, delete on public.product_barcodes from public, anon;
revoke delete on public.product_barcodes from authenticated, service_role;
grant select, insert, update on public.product_barcodes to authenticated;
grant select, insert, update on public.product_barcodes to service_role;

-- Master rows and global barcodes remain readable to authenticated callers,
-- but tenant roles receive no direct master/global write authority.
revoke insert, update, delete on public.master_products_catalog
from public, anon, authenticated;
revoke delete on public.master_products_catalog from service_role;
grant select on public.master_products_catalog to authenticated;
grant select, insert, update on public.master_products_catalog to service_role;

-- -------------------------------------------------------------------------
-- Contribution submission. Tenant proposal capability is separate from
-- global review authority. products.read is the minimum capability; create or
-- update also qualify for deliberately minimal custom roles.
-- -------------------------------------------------------------------------

create or replace function private.can_submit_product_catalog_contribution(
  p_business_id uuid,
  p_branch_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_permission text;
begin
  if p_business_id is null or auth.uid() is null then
    return false;
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.status = 'active'
      and b.deleted_at is null
  ) then
    return false;
  end if;

  if p_branch_id is not null
     and not exists (
       select 1
       from public.branches br
       where br.id = p_branch_id
         and br.business_id = p_business_id
         and br.status = 'active'
         and br.deleted_at is null
     )
  then
    return false;
  end if;

  foreach v_permission in array array[
    'products.read',
    'products.create',
    'products.update'
  ]::text[] loop
    if p_branch_id is null then
      if private.has_business_permission(p_business_id, v_permission) then
        return true;
      end if;
    elsif private.has_branch_permission(
      p_business_id,
      p_branch_id,
      v_permission
    ) then
      return true;
    end if;
  end loop;

  return false;
end;
$$;

create or replace function private.authorize_product_catalog_contribution_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
begin
  -- Trusted backend review has no end-user profile. Its authority is the
  -- service_role-only EXECUTE ACL on the review RPC below.
  if v_profile_id is null then
    return new;
  end if;

  if new.status <> 'pending_review' then
    raise exception 'Authenticated tenant users can only submit pending catalog contributions';
  end if;

  if new.profile_id is distinct from v_profile_id then
    raise exception 'Catalog contribution profile_id must match the authenticated user';
  end if;

  if not private.can_submit_product_catalog_contribution(
    new.business_id,
    new.branch_id
  ) then
    raise exception 'Insufficient product permission to submit catalog contribution';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_product_catalog_contributions_authorize_write
on public.product_catalog_contributions;

create trigger trg_product_catalog_contributions_authorize_write
before insert or update on public.product_catalog_contributions
for each row
execute function private.authorize_product_catalog_contribution_write();

drop policy if exists product_catalog_contributions_insert_business
on public.product_catalog_contributions;
drop policy if exists product_catalog_contributions_update_own_pending_or_admin
on public.product_catalog_contributions;

revoke insert, update, delete on public.product_catalog_contributions
from public, anon, authenticated, service_role;
grant select on public.product_catalog_contributions to authenticated, service_role;

revoke all on function private.can_submit_product_catalog_contribution(uuid, uuid)
from public, anon;
grant execute on function private.can_submit_product_catalog_contribution(uuid, uuid)
to authenticated, service_role;

revoke all on function private.authorize_product_catalog_contribution_write()
from public, anon, authenticated;

-- Keep submit available to authenticated tenant users. The existing RPC and
-- preparation trigger validate membership, branch, Product ownership and
-- MasterProduct existence; the new authorization trigger adds capability.
grant execute on function public.submit_product_catalog_contribution(
  uuid, uuid, uuid, uuid, text, text, text, text, text, text, text, text,
  numeric, text, text, text, text, text, text, numeric, jsonb
) to authenticated, service_role;

-- The legacy tenant review helper is retained only as a deny-by-default shim.
create or replace function private.can_review_product_catalog_contribution(
  p_business_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false;
$$;

comment on function private.can_review_product_catalog_contribution(uuid) is
'Deprecated deny-by-default shim. Business permissions never authorize global catalog review.';

revoke all on function private.can_review_product_catalog_contribution(uuid)
from public, anon, authenticated, service_role;

-- The helper mutates global catalog state, so it is not callable by tenant
-- authenticated users. The review RPC owner may call it internally.
revoke all on function private.ensure_global_product_barcode(
  uuid, text, text, text, numeric, jsonb
) from public, anon, authenticated;
grant execute on function private.ensure_global_product_barcode(
  uuid, text, text, text, numeric, jsonb
) to service_role;

-- -------------------------------------------------------------------------
-- Global contribution review. EXECUTE is service_role-only; no business role
-- name or tenant permission is consulted. reviewed_by remains nullable when
-- the trusted backend has no auth.uid(), while metadata records the authority.
-- -------------------------------------------------------------------------

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
  v_profile_id uuid := auth.uid();
  v_action text := lower(nullif(btrim(coalesce(p_action, '')), ''));
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_audit_metadata jsonb;
  v_contribution public.product_catalog_contributions%rowtype;
  v_target_master_id uuid;
  v_global_barcode_id uuid;
  v_result_status text;
  v_master_created boolean := false;
  v_master_updated boolean := false;
begin
  if p_contribution_id is null then
    raise exception 'contribution_id is required';
  end if;

  if v_action is null or v_action not in (
    'accept_new_product',
    'accept_improvement',
    'reject',
    'duplicate',
    'ignore'
  ) then
    raise exception 'Invalid review action: %', coalesce(v_action, '<null>');
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  v_audit_metadata := v_metadata || jsonb_build_object(
    'reviewed_via', 'public.review_product_catalog_contribution',
    'review_action', v_action,
    'reviewed_at', now(),
    'review_actor_authority', 'service_role',
    'review_actor_profile_id', v_profile_id
  );

  select pcc.*
  into v_contribution
  from public.product_catalog_contributions pcc
  where pcc.id = p_contribution_id
    and pcc.deleted_at is null
  for update;

  if v_contribution.id is null then
    raise exception 'Contribution not found';
  end if;

  if v_contribution.status <> 'pending_review' then
    raise exception 'Only pending_review contributions can be reviewed. Current status: %',
      v_contribution.status;
  end if;

  -- Revalidate the tenant-owned Product immediately before any global write.
  -- The API has no arbitrary Product target parameter: linking can only update
  -- the Product captured by the contribution and belonging to its business.
  if v_contribution.local_product_id is not null
     and not exists (
       select 1
       from public.products p
       where p.id = v_contribution.local_product_id
         and p.business_id = v_contribution.business_id
         and p.deleted_at is null
     )
  then
    raise exception 'Contribution local_product_id no longer belongs to its business';
  end if;

  if v_action = 'reject' then
    v_result_status := 'rejected';

  elsif v_action = 'ignore' then
    v_result_status := 'ignored';

  elsif v_action = 'duplicate' then
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

    v_result_status := 'duplicate';

  elsif v_action = 'accept_new_product' then
    if v_contribution.suggested_name is null then
      raise exception 'suggested_name is required to accept a new master product';
    end if;

    v_target_master_id := extensions.gen_random_uuid();

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
      v_target_master_id,
      case
        when v_contribution.barcode_type in ('internal', 'local_sku') then null
        else v_contribution.barcode
      end,
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
        || v_audit_metadata
        || jsonb_build_object(
          'created_via', 'public.review_product_catalog_contribution',
          'source_contribution_id', v_contribution.id,
          'phase', 'CATALOG-2E'
        ),
      'synced',
      v_profile_id,
      v_profile_id
    );

    v_master_created := true;
    v_result_status := 'accepted';

  elsif v_action = 'accept_improvement' then
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
        when m.verification_status in ('verified', 'gs1_verified')
          then m.verification_status
        else 'community'
      end,
      confidence_score = greatest(
        coalesce(m.confidence_score, 0),
        coalesce(v_contribution.confidence_score, 0)
      ),
      catalog_version = greatest(
        coalesce(m.catalog_version, 1),
        coalesce(v_contribution.evidence_count, 1)
      ),
      metadata = coalesce(m.metadata, '{}'::jsonb)
        || v_audit_metadata
        || jsonb_build_object('last_contribution_id', v_contribution.id),
      sync_status = 'synced',
      updated_by = v_profile_id
    where m.id = v_target_master_id;

    v_master_updated := true;
    v_result_status := 'merged';
  end if;

  -- A business-local/internal code remains a proposal attribute; it never
  -- becomes a global code. Global-compatible types are created only here,
  -- under service_role review authority.
  if v_action in ('accept_new_product', 'accept_improvement')
     and v_contribution.barcode is not null
     and v_contribution.barcode_type not in ('internal', 'local_sku')
  then
    v_global_barcode_id := private.ensure_global_product_barcode(
      v_target_master_id,
      v_contribution.barcode,
      v_contribution.barcode_type,
      'contribution',
      v_contribution.confidence_score,
      jsonb_build_object(
        'source_contribution_id', v_contribution.id,
        'phase', 'CATALOG-2E',
        'review_actor_authority', 'service_role'
      )
    );
  end if;

  update public.product_catalog_contributions pcc
  set
    status = v_result_status,
    reviewed_at = now(),
    reviewed_by = v_profile_id,
    review_notes = p_review_notes,
    rejected_reason = case
      when v_action = 'reject'
        then coalesce(p_rejected_reason, p_review_notes, 'Rejected by reviewer')
      else pcc.rejected_reason
    end,
    accepted_master_product_id = case
      when v_action in ('duplicate', 'accept_new_product', 'accept_improvement')
        then v_target_master_id
      else pcc.accepted_master_product_id
    end,
    metadata = coalesce(pcc.metadata, '{}'::jsonb) || v_audit_metadata,
    updated_by = v_profile_id,
    sync_status = 'synced'
  where pcc.id = v_contribution.id
  returning *
  into v_contribution;

  if v_action in ('accept_new_product', 'accept_improvement')
     and v_contribution.local_product_id is not null
  then
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

    if not found then
      raise exception 'Contribution Product could not be linked in its business scope';
    end if;
  end if;

  return jsonb_build_object(
    'contribution_id', v_contribution.id,
    'action', v_action,
    'status', v_contribution.status,
    'accepted_master_product_id', v_contribution.accepted_master_product_id,
    'global_barcode_id', v_global_barcode_id,
    'master_product_created', v_master_created,
    'master_product_updated', v_master_updated
  );
end;
$$;

revoke all on function public.review_product_catalog_contribution(
  uuid, text, text, uuid, text, jsonb
) from public, anon, authenticated;

grant execute on function public.review_product_catalog_contribution(
  uuid, text, text, uuid, text, jsonb
) to service_role;

comment on function public.review_product_catalog_contribution(
  uuid, text, text, uuid, text, jsonb
) is
'Reviews catalog contributions under service_role global authority. Tenant business permissions can submit proposals but cannot review or mutate the master catalog.';

commit;
