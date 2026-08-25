-- CATALOG-2F - Close catalog table, RPC and private-helper ACLs before the
-- first shared deployment of the CATALOG migration set.

begin;

-- Authenticated clients may read only active, synchronized global reference
-- rows directly. The SECURITY DEFINER pull RPC retains access to tombstones.
drop policy if exists master_products_catalog_select
on public.master_products_catalog;

drop policy if exists master_products_catalog_select_authenticated
on public.master_products_catalog;

create policy master_products_catalog_select_authenticated
on public.master_products_catalog
for select
to authenticated
using (
  deleted_at is null
  and coalesce(sync_status, 'synced') = 'synced'
);

-- Start from no privileges for every non-owner role, then grant the exact
-- direct table contract. service_role keeps only the administrative DML that
-- CATALOG-2E established; review mutations continue through the review RPC.
revoke all privileges on table public.master_products_catalog
from public, anon, authenticated, service_role;
grant select on table public.master_products_catalog to authenticated;
grant select, insert, update on table public.master_products_catalog
to service_role;

revoke all privileges on table public.product_barcodes
from public, anon, authenticated, service_role;
grant select on table public.product_barcodes to authenticated;
grant select, insert, update on table public.product_barcodes to service_role;

revoke all privileges on table public.product_catalog_contributions
from public, anon, authenticated, service_role;
grant select on table public.product_catalog_contributions to authenticated;
grant select on table public.product_catalog_contributions to service_role;

-- Public catalog RPCs have explicit caller ACLs. EXECUTE is never sufficient
-- authorization: each RPC retains its server-side auth and scope checks.
revoke all on function public.pull_product_catalog_delta(
  uuid, timestamptz, integer, jsonb, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.pull_product_catalog_delta(
  uuid, timestamptz, integer, jsonb, boolean
) to authenticated, service_role;

revoke all on function public.submit_product_catalog_contribution(
  uuid, uuid, uuid, uuid, text, text, text, text, text, text, text, text,
  numeric, text, text, text, text, text, text, numeric, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.submit_product_catalog_contribution(
  uuid, uuid, uuid, uuid, text, text, text, text, text, text, text, text,
  numeric, text, text, text, text, text, text, numeric, jsonb
) to authenticated, service_role;

revoke all on function public.review_product_catalog_contribution(
  uuid, text, text, uuid, text, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.review_product_catalog_contribution(
  uuid, text, text, uuid, text, jsonb
) to service_role;

-- Private catalog helpers are implementation details, not client APIs. The
-- owner and service_role retain the calls needed by SECURITY DEFINER sync and
-- administrative paths; anon/authenticated cannot invoke them directly.
revoke all on function private.sync_entity_permission_candidates(text, text)
from public, anon, authenticated;
grant execute on function private.sync_entity_permission_candidates(text, text)
to service_role;

revoke all on function private.has_sync_entity_permission(
  uuid, uuid, text, text
) from public, anon, authenticated;
grant execute on function private.has_sync_entity_permission(
  uuid, uuid, text, text
) to service_role;

revoke all on function private.apply_sync_catalog_mutation(uuid)
from public, anon, authenticated;
grant execute on function private.apply_sync_catalog_mutation(uuid)
to service_role;

revoke all on function private.apply_sync_product_barcode_mutation(uuid)
from public, anon, authenticated;
grant execute on function private.apply_sync_product_barcode_mutation(uuid)
to service_role;

revoke all on function private.normalize_barcode(text)
from public, anon, authenticated;
grant execute on function private.normalize_barcode(text)
to service_role;

revoke all on function private.touch_master_products_catalog()
from public, anon, authenticated;

revoke all on function private.prepare_product_barcode_before_write()
from public, anon, authenticated;

revoke all on function private.prepare_product_catalog_contribution()
from public, anon, authenticated;

revoke all on function private.enforce_product_barcode_mutation_batch_scope()
from public, anon, authenticated;

revoke all on function private.enforce_product_barcode_scope_ownership()
from public, anon, authenticated;

revoke all on function private.can_submit_product_catalog_contribution(
  uuid, uuid
) from public, anon, authenticated;
grant execute on function private.can_submit_product_catalog_contribution(
  uuid, uuid
) to service_role;

revoke all on function private.authorize_product_catalog_contribution_write()
from public, anon, authenticated;

revoke all on function private.can_review_product_catalog_contribution(uuid)
from public, anon, authenticated, service_role;

revoke all on function private.ensure_global_product_barcode(
  uuid, text, text, text, numeric, jsonb
) from public, anon, authenticated;
grant execute on function private.ensure_global_product_barcode(
  uuid, text, text, text, numeric, jsonb
) to service_role;

-- CATALOG-2A deliberately introduced this invariant as NOT VALID so existing
-- data could be inspected first. The remote preflight found no incompatible
-- legacy rows, so the first deployment can validate the full table safely.
alter table public.product_barcodes
validate constraint product_barcodes_internal_code_business_scope;

commit;
