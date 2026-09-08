-- P1.3 transactional master catalog importer contract.
-- Runs only against a disposable local Supabase database.

begin;

select plan(30);

create function pg_temp.p13_masters(
  p_master_id uuid,
  p_barcode text,
  p_name text,
  p_expected_version integer default null,
  p_record_hash text default repeat('a', 64),
  p_brand text default 'Marca P1.3'
)
returns jsonb
language sql
as $$
  select jsonb_build_array(jsonb_build_object(
    'master_product_id', p_master_id,
    'expected_version', p_expected_version,
    'record_hash', p_record_hash,
    'primary_barcode', p_barcode,
    'barcode_type', case length(p_barcode) when 8 then 'ean8' when 12 then 'upc' when 13 then 'ean13' else 'gtin' end,
    'name', p_name,
    'brand', p_brand,
    'manufacturer', 'Fabricante P1.3',
    'category_name', 'Alimentos',
    'subcategory_name', 'Pruebas',
    'package_size', '500',
    'package_unit', 'g',
    'unit_type', 'bolsa',
    'description', 'Fixture P1.3',
    'source', 'manual_curated',
    'verification_status', 'unverified',
    'confidence_score', '0.75',
    'source_reference', 'fixture:p1.3',
    'image_source_key', '',
    'image_license', '',
    'image_attribution', ''
  ));
$$;

create function pg_temp.p13_barcodes(
  p_master_id uuid,
  p_primary_id uuid,
  p_primary text,
  p_alternate_id uuid,
  p_alternate text,
  p_primary_expected integer default null,
  p_alternate_expected integer default null,
  p_record_hash text default repeat('c', 64)
)
returns jsonb
language sql
as $$
  select jsonb_build_array(
    jsonb_build_object(
      'barcode_id', p_primary_id,
      'master_product_id', p_master_id,
      'expected_version', p_primary_expected,
      'record_hash', p_record_hash,
      'barcode', p_primary,
      'barcode_type', case length(p_primary) when 8 then 'ean8' when 12 then 'upc' when 13 then 'ean13' else 'gtin' end,
      'is_primary', true,
      'source', 'manual_curated',
      'confidence_score', '0.75',
      'source_reference', 'fixture:p1.3:primary'
    ),
    jsonb_build_object(
      'barcode_id', p_alternate_id,
      'master_product_id', p_master_id,
      'expected_version', p_alternate_expected,
      'record_hash', repeat('d', 64),
      'barcode', p_alternate,
      'barcode_type', case length(p_alternate) when 8 then 'ean8' when 12 then 'upc' when 13 then 'ean13' else 'gtin' end,
      'is_primary', false,
      'source', 'manufacturer',
      'confidence_score', '0.90',
      'source_reference', 'fixture:p1.3:alternate'
    )
  );
$$;

insert into public.businesses (id, name, status)
values ('13000000-0000-4000-8000-000000000001', 'P1.3 Unrelated Business', 'active');

insert into public.master_products_catalog (
  id, barcode, gtin, name, product_name, source
) values (
  '13000000-0000-4000-8000-000000000101',
  '96385074', '96385074', 'Unrelated master', 'Unrelated master', 'manual_curated'
);

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock, master_product_id
) values (
  '13000000-0000-4000-8000-000000000201',
  '13000000-0000-4000-8000-000000000001',
  'Unrelated product', 10, 0, 0,
  '13000000-0000-4000-8000-000000000101'
);

select ok(
  has_function_privilege('service_role', 'public.import_master_catalog_batch(uuid,text,jsonb,jsonb)', 'EXECUTE'),
  '1. service_role can execute the transactional import RPC'
);

select ok(
  not has_function_privilege('anon', 'public.import_master_catalog_batch(uuid,text,jsonb,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.import_master_catalog_batch(uuid,text,jsonb,jsonb)', 'EXECUTE'),
  '2. client roles cannot execute the import RPC'
);

select ok(
  has_function_privilege('service_role', 'public.export_master_catalog_snapshot()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.export_master_catalog_snapshot()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.export_master_catalog_snapshot()', 'EXECUTE'),
  '3. snapshot RPC is service-role-only'
);

select ok(
  has_function_privilege('service_role', 'public.compensate_master_catalog_import_batch(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.compensate_master_catalog_import_batch(uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.compensate_master_catalog_import_batch(uuid,text)', 'EXECUTE'),
  '4. compensation RPC is service-role-only'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000301', 'fixture-1',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000401', '4006381333931', 'Denied'),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000401',
        '13000000-0000-4000-8000-000000000411', '4006381333931',
        '13000000-0000-4000-8000-000000000412', '5901234123457'
      )
    )$$,
  '42501', 'Service role authority required for master catalog import',
  '5. internal authority guard rejects a non-service caller even when owner can invoke'
);

select set_config('request.jwt.claim.role', 'service_role', true);

select is(
  (public.export_master_catalog_snapshot()->>'snapshot_version')::integer,
  1,
  '6. authorized snapshot returns the versioned contract'
);

select lives_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000301', 'fixture-1',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000401', '4006381333931', 'Producto importado'),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000401',
        '13000000-0000-4000-8000-000000000411', '4006381333931',
        '13000000-0000-4000-8000-000000000412', '5901234123457'
      )
    )$$,
  '7. service_role can atomically import one master and its barcodes'
);

select is(
  (select count(*)::integer from public.master_products_catalog where id = '13000000-0000-4000-8000-000000000401'),
  1,
  '8. one master was inserted with its preassigned UUID'
);

select is(
  (select count(*)::integer from public.product_barcodes where master_product_id = '13000000-0000-4000-8000-000000000401' and is_primary and deleted_at is null),
  1,
  '9. exactly one active primary global barcode was inserted'
);

select is(
  (select count(*)::integer from public.product_barcodes where master_product_id = '13000000-0000-4000-8000-000000000401' and not is_primary and deleted_at is null),
  1,
  '10. alternate global barcode was inserted'
);

select ok(
  exists (
    select 1 from public.master_products_catalog m
    where m.id = '13000000-0000-4000-8000-000000000401'
      and m.barcode = '4006381333931'
      and m.gtin = '4006381333931'
      and m.name = 'Producto importado'
      and m.product_name = 'Producto importado'
      and m.category_name = 'Alimentos'
      and m.category = 'Alimentos'
      and m.unit_type = 'bolsa'
      and m.unit = 'bolsa'
  ),
  '11. legacy barcode/name/category/unit mirrors are exact'
);

select ok(
  exists (
    select 1 from public.master_products_catalog m
    where m.id = '13000000-0000-4000-8000-000000000401'
      and m.metadata->'catalog_import'->>'import_batch_id' = '13000000-0000-4000-8000-000000000301'
      and m.metadata->'catalog_import'->>'dataset_version' = 'fixture-1'
      and m.metadata->'catalog_import'->>'record_hash' = repeat('a', 64)
      and m.metadata->'catalog_import'->>'source_reference' = 'fixture:p1.3'
  ) and exists (
    select 1 from public.product_barcodes pb
    where pb.id = '13000000-0000-4000-8000-000000000411'
      and pb.metadata->'catalog_import'->>'import_batch_id' = '13000000-0000-4000-8000-000000000301'
      and pb.metadata->'catalog_import'->>'source_reference' = 'fixture:p1.3:primary'
  ),
  '12. server-built import batch and provenance metadata are stored'
);

select is(
  (public.import_master_catalog_batch(
    '13000000-0000-4000-8000-000000000301', 'fixture-1',
    pg_temp.p13_masters('13000000-0000-4000-8000-000000000401', '4006381333931', 'Producto importado'),
    pg_temp.p13_barcodes(
      '13000000-0000-4000-8000-000000000401',
      '13000000-0000-4000-8000-000000000411', '4006381333931',
      '13000000-0000-4000-8000-000000000412', '5901234123457'
    )
  )->>'status'),
  'already_applied',
  '13. retrying the exact same batch is idempotent'
);

select is(
  (select count(*)::integer from public.product_barcodes where master_product_id = '13000000-0000-4000-8000-000000000401'),
  2,
  '14. same-batch retry creates no duplicate barcodes'
);

select ok(
  (public.import_master_catalog_batch(
    '13000000-0000-4000-8000-000000000302', 'fixture-1',
    pg_temp.p13_masters('13000000-0000-4000-8000-000000000401', '4006381333931', 'Producto importado', 1),
    pg_temp.p13_barcodes(
      '13000000-0000-4000-8000-000000000401',
      '13000000-0000-4000-8000-000000000411', '4006381333931',
      '13000000-0000-4000-8000-000000000412', '5901234123457', 1, 1
    )
  )->'masters'->>'no_op')::integer = 1
  and (select version from public.master_products_catalog where id = '13000000-0000-4000-8000-000000000401') = 1,
  '15. same dataset under a new batch is no-op without version churn'
);

select is(
  (public.import_master_catalog_batch(
    '13000000-0000-4000-8000-000000000303', 'fixture-2',
    pg_temp.p13_masters(
      '13000000-0000-4000-8000-000000000401', '4006381333931',
      'Producto importado', 1, repeat('b', 64), 'Marca actualizada'
    ),
    pg_temp.p13_barcodes(
      '13000000-0000-4000-8000-000000000401',
      '13000000-0000-4000-8000-000000000411', '4006381333931',
      '13000000-0000-4000-8000-000000000412', '5901234123457', 1, 1
    )
  )->'masters'->>'updated')::integer,
  1,
  '16. allowed canonical change updates the existing master'
);

select ok(
  exists (
    select 1 from public.master_products_catalog
    where id = '13000000-0000-4000-8000-000000000401'
      and brand = 'Marca actualizada'
      and version = 2
  ),
  '17. update increments the optimistic version exactly once'
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000304', 'fixture-stale',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000401', '4006381333931', 'Producto importado', 1),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000401',
        '13000000-0000-4000-8000-000000000411', '4006381333931',
        '13000000-0000-4000-8000-000000000412', '5901234123457', 1, 1
      )
    )$$,
  '40001', 'Master expected_version conflict',
  '18. stale expected version fails instead of overwriting a later update'
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000305', 'fixture-conflict',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000402', '4006381333931', 'Otro master'),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000402',
        '13000000-0000-4000-8000-000000000421', '4006381333931',
        '13000000-0000-4000-8000-000000000422', '10012345000017'
      )
    )$$,
  '23505', 'Global barcode belongs to another master',
  '19. active barcode cannot be reassigned across masters'
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000306', 'fixture-rollback',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000403', '036000291452', 'First valid')
        || jsonb_set(
          pg_temp.p13_masters('13000000-0000-4000-8000-000000000404', '96385074', 'Second invalid')->0,
          '{name}', '""'::jsonb
        ),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000403',
        '13000000-0000-4000-8000-000000000431', '036000291452',
        '13000000-0000-4000-8000-000000000432', '10012345000017'
      ) || pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000404',
        '13000000-0000-4000-8000-000000000441', '96385074',
        '13000000-0000-4000-8000-000000000442', '12345670'
      )
    )$$,
  '22023', 'Master payload is missing required validated fields',
  '20. one invalid row aborts the complete multi-master batch'
);

select is(
  (select count(*)::integer from public.master_products_catalog where id in (
    '13000000-0000-4000-8000-000000000403', '13000000-0000-4000-8000-000000000404'
  )),
  0,
  '21. failed batch left neither of its masters behind'
);

insert into public.master_products_catalog (
  id, barcode, gtin, name, product_name, source, deleted_at
) values (
  '13000000-0000-4000-8000-000000000405',
  '036000291452', '036000291452', 'Tombstoned', 'Tombstoned', 'manual_curated', now()
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000307', 'fixture-tombstone',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000405', '036000291452', 'Tombstoned', 1),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000405',
        '13000000-0000-4000-8000-000000000451', '036000291452',
        '13000000-0000-4000-8000-000000000452', '10012345000017'
      )
    )$$,
  '55000', 'Tombstoned master requires explicit review',
  '22. tombstoned master is not restored implicitly'
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000308', 'fixture-primary',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000406', '036000291452', 'Two primaries'),
      jsonb_set(
        pg_temp.p13_barcodes(
          '13000000-0000-4000-8000-000000000406',
          '13000000-0000-4000-8000-000000000461', '036000291452',
          '13000000-0000-4000-8000-000000000462', '10012345000017'
        ),
        '{1,is_primary}', 'true'::jsonb
      )
    )$$,
  '22023', 'Master must have exactly one matching primary barcode',
  '23. multiple primary barcodes are rejected before writes'
);

select throws_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000309', 'fixture-type',
      jsonb_set(
        pg_temp.p13_masters('13000000-0000-4000-8000-000000000407', '036000291452', 'Invalid type'),
        '{0,barcode_type}', '"internal"'::jsonb
      ),
      jsonb_set(
        pg_temp.p13_barcodes(
          '13000000-0000-4000-8000-000000000407',
          '13000000-0000-4000-8000-000000000471', '036000291452',
          '13000000-0000-4000-8000-000000000472', '10012345000017'
        ),
        '{0,barcode_type}', '"internal"'::jsonb
      )
    )$$,
  '22023', 'Master primary barcode is invalid',
  '24. internal/local SKU cannot enter the global catalog'
);

select is(
  (select count(*)::integer from private.master_catalog_import_audit where import_batch_id = '13000000-0000-4000-8000-000000000301'),
  3,
  '25. import audit records the master and both barcode operations'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '13000000-0000-4000-8000-000000000501', 'authenticated', 'authenticated',
  'p13-delta@example.test', '', now(), '{}', '{}', now(), now()
);
insert into public.profiles (id, full_name, role, status)
values ('13000000-0000-4000-8000-000000000501', 'P1.3 Delta', 'cashier', 'active');
insert into public.roles (id, business_id, name, is_system_role)
values ('13000000-0000-4000-8000-000000000502', '13000000-0000-4000-8000-000000000001', 'p13-delta', false);
insert into public.business_members (id, business_id, profile_id, role_id, status)
values (
  '13000000-0000-4000-8000-000000000503',
  '13000000-0000-4000-8000-000000000001',
  '13000000-0000-4000-8000-000000000501',
  '13000000-0000-4000-8000-000000000502', 'active'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '13000000-0000-4000-8000-000000000501', true);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.pull_product_catalog_delta(
        '13000000-0000-4000-8000-000000000001',
        '1970-01-01 00:00:00+00', 5000, '{}'::jsonb, false
      )->'records'
    ) r(value)
    where r.value->>'id' = '13000000-0000-4000-8000-000000000401'
      and r.value->>'entity_type' = 'master_product'
      and r.value->'payload'->>'image_thumb_url' is null
      and r.value->'payload' ? 'image_hash'
  ),
  '26. imported master is visible through the unchanged catalog delta contract'
);

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config('request.jwt.claim.sub', '', true);

select ok(
  exists (
    select 1 from public.products p
    where p.id = '13000000-0000-4000-8000-000000000201'
      and p.business_id = '13000000-0000-4000-8000-000000000001'
      and p.master_product_id = '13000000-0000-4000-8000-000000000101'
  ),
  '27. unrelated business Product remains untouched'
);

select lives_ok(
  $$select public.import_master_catalog_batch(
      '13000000-0000-4000-8000-000000000310', 'fixture-compensate',
      pg_temp.p13_masters('13000000-0000-4000-8000-000000000408', '55123457', 'Compensable'),
      pg_temp.p13_barcodes(
        '13000000-0000-4000-8000-000000000408',
        '13000000-0000-4000-8000-000000000481', '55123457',
        '13000000-0000-4000-8000-000000000482', '73513537'
      )
    )$$,
  '28. isolated insert-only batch is accepted before compensation'
);

select is(
  (public.compensate_master_catalog_import_batch(
    '13000000-0000-4000-8000-000000000310', 'P1.3 test compensation'
  )->>'status'),
  'compensated',
  '29. insert-only batch is compensated through soft deletion'
);

select ok(
  exists (
    select 1 from public.master_products_catalog
    where id = '13000000-0000-4000-8000-000000000408'
      and deleted_at is not null
  ) and (
    select count(*) from public.product_barcodes
    where master_product_id = '13000000-0000-4000-8000-000000000408'
      and deleted_at is not null
  ) = 2,
  '30. compensation preserves rows and auditability instead of hard deleting'
);

select * from finish();
rollback;
