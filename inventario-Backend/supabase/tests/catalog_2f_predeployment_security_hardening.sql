-- Focused CATALOG-2F ACL and policy contract checks.
-- Run after migrations through 20260825170000 on a disposable database.

begin;

select plan(74);

-- 42 assertions: exact direct table privileges for both client roles.
with table_expectations(table_name) as (
  values
    ('master_products_catalog'),
    ('product_barcodes'),
    ('product_catalog_contributions')
), role_expectations(role_name) as (
  values ('anon'), ('authenticated')
), privilege_expectations(privilege_name) as (
  values
    ('SELECT'),
    ('INSERT'),
    ('UPDATE'),
    ('DELETE'),
    ('TRUNCATE'),
    ('REFERENCES'),
    ('TRIGGER')
)
select is(
  has_table_privilege(
    r.role_name,
    format('public.%I', t.table_name),
    p.privilege_name
  ),
  r.role_name = 'authenticated' and p.privilege_name = 'SELECT',
  format(
    '%s %s privilege on %s matches the minimum client ACL',
    r.role_name,
    p.privilege_name,
    t.table_name
  )
)
from table_expectations t
cross join role_expectations r
cross join privilege_expectations p
order by t.table_name, r.role_name, p.privilege_name;

-- Three assertions: service_role keeps only the direct administrative table
-- operations required by the catalog contract.
select ok(
  has_table_privilege('service_role', 'public.master_products_catalog', 'SELECT')
  and has_table_privilege('service_role', 'public.master_products_catalog', 'INSERT')
  and has_table_privilege('service_role', 'public.master_products_catalog', 'UPDATE')
  and not has_table_privilege('service_role', 'public.master_products_catalog', 'DELETE')
  and not has_table_privilege('service_role', 'public.master_products_catalog', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.master_products_catalog', 'REFERENCES')
  and not has_table_privilege('service_role', 'public.master_products_catalog', 'TRIGGER'),
  'service_role MasterProduct table ACL is administrative but non-destructive'
);

select ok(
  has_table_privilege('service_role', 'public.product_barcodes', 'SELECT')
  and has_table_privilege('service_role', 'public.product_barcodes', 'INSERT')
  and has_table_privilege('service_role', 'public.product_barcodes', 'UPDATE')
  and not has_table_privilege('service_role', 'public.product_barcodes', 'DELETE')
  and not has_table_privilege('service_role', 'public.product_barcodes', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.product_barcodes', 'REFERENCES')
  and not has_table_privilege('service_role', 'public.product_barcodes', 'TRIGGER'),
  'service_role ProductBarcode table ACL is administrative but non-destructive'
);

select ok(
  has_table_privilege('service_role', 'public.product_catalog_contributions', 'SELECT')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'INSERT')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'UPDATE')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'DELETE')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'TRUNCATE')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'REFERENCES')
  and not has_table_privilege('service_role', 'public.product_catalog_contributions', 'TRIGGER'),
  'service_role Contribution table ACL is read-only; review uses its RPC'
);

-- Nine assertions: exact public RPC callers.
with function_expectations(function_signature, role_name, expected) as (
  values
    ('public.pull_product_catalog_delta(uuid,timestamptz,integer,jsonb,boolean)', 'anon', false),
    ('public.pull_product_catalog_delta(uuid,timestamptz,integer,jsonb,boolean)', 'authenticated', true),
    ('public.pull_product_catalog_delta(uuid,timestamptz,integer,jsonb,boolean)', 'service_role', true),
    ('public.submit_product_catalog_contribution(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,text,text,text,text,text,text,numeric,jsonb)', 'anon', false),
    ('public.submit_product_catalog_contribution(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,text,text,text,text,text,text,numeric,jsonb)', 'authenticated', true),
    ('public.submit_product_catalog_contribution(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,text,text,text,text,text,text,numeric,jsonb)', 'service_role', true),
    ('public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)', 'anon', false),
    ('public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)', 'authenticated', false),
    ('public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)', 'service_role', true)
)
select is(
  has_function_privilege(f.role_name, f.function_signature, 'EXECUTE'),
  f.expected,
  format('%s EXECUTE on %s matches the public RPC contract', f.role_name, f.function_signature)
)
from function_expectations f;

-- Three assertions: the pseudo-role PUBLIC has no inherited EXECUTE grant.
with public_functions(function_name, function_signature) as (
  values
    ('pull catalog', 'public.pull_product_catalog_delta(uuid,timestamptz,integer,jsonb,boolean)'),
    ('submit contribution', 'public.submit_product_catalog_contribution(uuid,uuid,uuid,uuid,text,text,text,text,text,text,text,text,numeric,text,text,text,text,text,text,numeric,jsonb)'),
    ('review contribution', 'public.review_product_catalog_contribution(uuid,text,text,uuid,text,jsonb)')
)
select ok(
  not exists (
    select 1
    from pg_catalog.aclexplode(
      coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))
    ) acl
    where acl.grantee = 0
      and acl.privilege_type = 'EXECUTE'
  ),
  format('PUBLIC has no EXECUTE on %s RPC', f.function_name)
)
from public_functions f
join pg_catalog.pg_proc p
  on p.oid = pg_catalog.to_regprocedure(f.function_signature);

-- Fourteen assertions: private catalog implementation helpers are not client APIs.
with private_helpers(function_signature) as (
  values
    ('private.sync_entity_permission_candidates(text,text)'),
    ('private.has_sync_entity_permission(uuid,uuid,text,text)'),
    ('private.apply_sync_catalog_mutation(uuid)'),
    ('private.apply_sync_product_barcode_mutation(uuid)'),
    ('private.normalize_barcode(text)'),
    ('private.touch_master_products_catalog()'),
    ('private.prepare_product_barcode_before_write()'),
    ('private.prepare_product_catalog_contribution()'),
    ('private.enforce_product_barcode_mutation_batch_scope()'),
    ('private.enforce_product_barcode_scope_ownership()'),
    ('private.can_submit_product_catalog_contribution(uuid,uuid)'),
    ('private.authorize_product_catalog_contribution_write()'),
    ('private.can_review_product_catalog_contribution(uuid)'),
    ('private.ensure_global_product_barcode(uuid,text,text,text,numeric,jsonb)')
)
select ok(
  not has_function_privilege('anon', h.function_signature, 'EXECUTE')
  and not has_function_privilege('authenticated', h.function_signature, 'EXECUTE'),
  format('%s is not directly executable by client roles', h.function_signature)
)
from private_helpers h;

select is(
  (
    select count(*)::integer
    from pg_catalog.pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'master_products_catalog'
      and p.cmd = 'SELECT'
      and 'authenticated' = any(p.roles)
  ),
  1,
  'MasterProduct has one authenticated SELECT policy'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_policies p
    where p.schemaname = 'public'
      and p.tablename = 'master_products_catalog'
      and p.policyname = 'master_products_catalog_select_authenticated'
      and p.cmd = 'SELECT'
      and p.qual ilike '%deleted_at IS NULL%'
      and p.qual ilike '%sync_status%'
      and p.qual ilike '%synced%'
  ),
  'direct MasterProduct SELECT exposes only active synchronized reference rows'
);

select ok(
  exists (
    select 1
    from pg_catalog.pg_constraint c
    join pg_catalog.pg_class t on t.oid = c.conrelid
    join pg_catalog.pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'product_barcodes'
      and c.conname = 'product_barcodes_internal_code_business_scope'
      and c.convalidated
  ),
  'CATALOG-2A global internal/local SKU constraint is validated'
);

select * from finish();

rollback;
