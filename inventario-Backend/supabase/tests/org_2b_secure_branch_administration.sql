-- ORG-2B - Focused pgTAP validation for secure branch administration.
-- All fixtures and branch creation effects are rolled back.

begin;

select plan(23);

create temporary table org_2b_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert, update on org_2b_results to authenticated;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'fa200000-0000-0000-0000-000000000001',
    'authenticated', 'authenticated', 'org2b-wide@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'fa200000-0000-0000-0000-000000000002',
    'authenticated', 'authenticated', 'org2b-scoped@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'fa200000-0000-0000-0000-000000000003',
    'authenticated', 'authenticated', 'org2b-other@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'fa200000-0000-0000-0000-000000000004',
    'authenticated', 'authenticated', 'org2b-limited@example.test', '', now(),
    '{}', '{}', now(), now()
  );

insert into public.profiles (id, full_name, status)
values
  ('fa200000-0000-0000-0000-000000000001', 'ORG-2B Wide Admin', 'active'),
  ('fa200000-0000-0000-0000-000000000002', 'ORG-2B Scoped Admin', 'active'),
  ('fa200000-0000-0000-0000-000000000003', 'ORG-2B Other Admin', 'active'),
  ('fa200000-0000-0000-0000-000000000004', 'ORG-2B Limited', 'active');

insert into public.businesses (id, name, status)
values
  ('fa200000-0000-0000-0000-000000000101', 'ORG-2B Business A', 'active'),
  ('fa200000-0000-0000-0000-000000000102', 'ORG-2B Business B', 'active'),
  ('fa200000-0000-0000-0000-000000000103', 'ORG-2B No Primary', 'active');

insert into public.branches (id, business_id, name, status)
values
  (
    'fa200000-0000-0000-0000-000000000111',
    'fa200000-0000-0000-0000-000000000101',
    'Principal A',
    'active'
  ),
  (
    'fa200000-0000-0000-0000-000000000112',
    'fa200000-0000-0000-0000-000000000101',
    'Scoped A',
    'active'
  ),
  (
    'fa200000-0000-0000-0000-000000000121',
    'fa200000-0000-0000-0000-000000000102',
    'Principal B',
    'active'
  );

insert into public.roles (
  id, business_id, name, description, is_system_role
)
values
  (
    'fa200000-0000-0000-0000-000000000201',
    'fa200000-0000-0000-0000-000000000101',
    'org2b_branch_creator_a',
    'Custom capability fixture for ORG-2B Business A.',
    false
  ),
  (
    'fa200000-0000-0000-0000-000000000202',
    'fa200000-0000-0000-0000-000000000102',
    'org2b_branch_creator_b',
    'Custom capability fixture for ORG-2B Business B.',
    false
  );

insert into public.role_permissions (role_id, permission_id)
select role_id, p.id
from (
  values
    ('fa200000-0000-0000-0000-000000000201'::uuid),
    ('fa200000-0000-0000-0000-000000000202'::uuid)
) fixture(role_id)
cross join public.permissions p
where p.key = 'settings.branches';

insert into public.business_members (
  business_id, profile_id, branch_id, role_id, status, accepted_at
)
values
  (
    'fa200000-0000-0000-0000-000000000101',
    'fa200000-0000-0000-0000-000000000001',
    null,
    'fa200000-0000-0000-0000-000000000201',
    'active',
    now()
  ),
  (
    'fa200000-0000-0000-0000-000000000101',
    'fa200000-0000-0000-0000-000000000002',
    'fa200000-0000-0000-0000-000000000112',
    'fa200000-0000-0000-0000-000000000201',
    'active',
    now()
  ),
  (
    'fa200000-0000-0000-0000-000000000102',
    'fa200000-0000-0000-0000-000000000003',
    null,
    'fa200000-0000-0000-0000-000000000202',
    'active',
    now()
  ),
  (
    'fa200000-0000-0000-0000-000000000101',
    'fa200000-0000-0000-0000-000000000004',
    null,
    (
      select r.id
      from public.roles r
      where r.business_id is null
        and r.name = 'cashier'
        and r.deleted_at is null
      limit 1
    ),
    'active',
    now()
  ),
  (
    'fa200000-0000-0000-0000-000000000103',
    'fa200000-0000-0000-0000-000000000001',
    null,
    (
      select r.id
      from public.roles r
      where r.business_id is null
        and r.name = 'owner'
        and r.deleted_at is null
      limit 1
    ),
    'active',
    now()
  );

select ok(
  has_table_privilege('authenticated', 'public.branches', 'SELECT')
  and not has_table_privilege('authenticated', 'public.branches', 'INSERT')
  and not has_table_privilege('authenticated', 'public.branches', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.branches', 'DELETE')
  and not has_table_privilege('authenticated', 'public.branches', 'TRUNCATE')
  and not has_table_privilege('authenticated', 'public.branches', 'REFERENCES')
  and not has_table_privilege('authenticated', 'public.branches', 'TRIGGER')
  and not has_table_privilege('anon', 'public.branches', 'SELECT')
  and not has_table_privilege('anon', 'public.branches', 'INSERT'),
  '1. authenticated keeps SELECT only and anon has no direct branches privilege'
);

select is(
  (
    select count(*)::bigint
    from pg_policy p
    where p.polrelid = 'public.branches'::regclass
      and p.polcmd in ('a', 'w', 'd')
  ),
  0::bigint,
  '2. no direct INSERT, UPDATE, or DELETE branch policy remains'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.create_business_branch(uuid,text,text,text,text)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.list_business_branches(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.ensure_business_runtime_setup(uuid,uuid,uuid,jsonb,text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_business(uuid,uuid,text,text,text,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.create_business_branch(uuid,text,text,text,text)',
    'EXECUTE'
  ),
  '3. only the new branch RPCs are client branch-administration capabilities'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'private.business_branch_creation_requests',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'private.business_branch_creation_requests',
    'INSERT'
  )
  and not has_table_privilege(
    'anon',
    'private.business_branch_creation_requests',
    'SELECT'
  ),
  '4. durable branch idempotency storage is not client-readable or writable'
);

select ok(
  position(
    'insert into public.branches'
    in lower(pg_get_functiondef(
      'public.ensure_business_runtime_setup(uuid,uuid,uuid,jsonb,text,text,text)'::regprocedure
    ))
  ) = 0
  and (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and position('insert into public.branches' in lower(pg_get_functiondef(p.oid))) > 0
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ) = 1,
  '5. create_business_branch is the sole authenticated branch INSERT function'
);

select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000001',
  true
);
insert into org_2b_results (result_key, payload)
values (
  'created',
  public.create_business_branch(
    'fa200000-0000-0000-0000-000000000101',
    '  Sucursal Norte  ',
    '  Calle 10  ',
    '  555-0100  ',
    'org-2b-create-north'
  )
);
reset role;

select ok(
  (
    select payload ->> 'name' = 'Sucursal Norte'
      and payload ->> 'address' = 'Calle 10'
      and payload ->> 'phone' = '555-0100'
      and (payload ->> 'runtime_ready')::boolean
    from org_2b_results
    where result_key = 'created'
  ),
  '6. a custom role capability fixture creates a normalized branch'
);

select ok(
  (
    select br.status = 'active'
      and br.deleted_at is null
      and br.is_primary = false
      and br.created_by = 'fa200000-0000-0000-0000-000000000001'
    from public.branches br
    join org_2b_results result on result.result_key = 'created'
    where br.id = (result.payload ->> 'branch_id')::uuid
  ),
  '7. the created branch is active, secondary, and attributed to auth.uid()'
);

select ok(
  (
    select count(*) = 1
    from public.cash_registers cr
    join org_2b_results result on result.result_key = 'created'
    where cr.branch_id = (result.payload ->> 'branch_id')::uuid
      and cr.id = (result.payload ->> 'cash_register_id')::uuid
      and cr.name = 'Caja Principal'
      and cr.status = 'active'
      and cr.deleted_at is null
  ),
  '8. creation materializes exactly the canonical active cash register'
);

select ok(
  (
    select count(*) = 1
    from public.receipt_sequences rs
    join org_2b_results result on result.result_key = 'created'
    where rs.branch_id = (result.payload ->> 'branch_id')::uuid
      and rs.id = (result.payload ->> 'receipt_sequence_id')::uuid
      and rs.prefix = 'POS'
      and rs.status = 'active'
      and rs.deleted_at is null
  ),
  '9. creation materializes exactly the canonical active receipt sequence'
);

select ok(
  not exists (
    select 1
    from public.cash_sessions cs
    join org_2b_results result on result.result_key = 'created'
    where cs.branch_id = (result.payload ->> 'branch_id')::uuid
  )
  and not exists (
    select 1
    from public.product_stock_balances balance
    join org_2b_results result on result.result_key = 'created'
    where balance.branch_id = (result.payload ->> 'branch_id')::uuid
  )
  and not exists (
    select 1
    from public.inventory_movements movement
    join org_2b_results result on result.result_key = 'created'
    where movement.branch_id = (result.payload ->> 'branch_id')::uuid
  )
  and not exists (
    select 1
    from public.app_devices device
    join org_2b_results result on result.result_key = 'created'
    where device.branch_id = (result.payload ->> 'branch_id')::uuid
  ),
  '10. branch administration creates no session, stock, movement, or app_device'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      public.list_authorized_operational_contexts() -> 'contexts'
    ) context_row(value)
    join org_2b_results result on result.result_key = 'created'
      and context_row.value ->> 'branch_id' = result.payload ->> 'branch_id'
    where context_row.value ->> 'business_id'
      = 'fa200000-0000-0000-0000-000000000101'
  ),
  '11. discovery exposes the new branch to the business-wide actor'
);

select ok(
  (
    select jsonb_array_length(listing.payload -> 'branches') = 3
      and exists (
        select 1
        from jsonb_array_elements(listing.payload -> 'branches') row(value)
        join org_2b_results created on created.result_key = 'created'
          and row.value ->> 'id' = created.payload ->> 'branch_id'
        where (row.value ->> 'runtime_ready')::boolean
      )
    from (
      select public.list_business_branches(
        'fa200000-0000-0000-0000-000000000101'
      ) as payload
    ) listing
  ),
  '12. administrative listing returns the full business topology and readiness'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000002',
  true
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000101',
      'Scoped Forbidden', null, null, 'org-2b-scoped-forbidden'
    )$$,
  '42501',
  'Business-wide settings.branches permission is required',
  '13. branch-specific settings.branches cannot create another branch'
);
select throws_ok(
  $$select public.list_business_branches(
      'fa200000-0000-0000-0000-000000000101'
    )$$,
  '42501',
  'Business-wide settings.branches permission is required',
  '14. branch-specific settings.branches cannot enumerate administrative topology'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000001',
  true
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000102',
      'Cross Business', null, null, 'org-2b-cross-business'
    )$$,
  '42501',
  'Business-wide settings.branches permission is required',
  '15. a business-wide admin of A cannot create a branch in B'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000004',
  true
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000101',
      'No Permission', null, null, 'org-2b-no-permission'
    )$$,
  '42501',
  'Business-wide settings.branches permission is required',
  '16. a business-wide member without settings.branches is denied'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000001',
  true
);
insert into org_2b_results (result_key, payload)
values (
  'retry',
  public.create_business_branch(
    'fa200000-0000-0000-0000-000000000101',
    'Sucursal Norte',
    'Calle 10',
    '555-0100',
    'org-2b-create-north'
  )
);
reset role;

select ok(
  (
    select first.payload ->> 'branch_id' = retry.payload ->> 'branch_id'
      and first.payload ->> 'cash_register_id'
        = retry.payload ->> 'cash_register_id'
      and first.payload ->> 'receipt_sequence_id'
        = retry.payload ->> 'receipt_sequence_id'
    from org_2b_results first
    join org_2b_results retry on retry.result_key = 'retry'
    where first.result_key = 'created'
  ),
  '17. response-loss retry returns the same branch and runtime ids'
);

select ok(
  (
    select count(*) = 1
    from private.business_branch_creation_requests request
    where request.business_id = 'fa200000-0000-0000-0000-000000000101'
      and request.idempotency_key = 'org-2b-create-north'
      and request.completed_at is not null
  )
  and (
    select count(*) = 1
    from public.branches br
    where br.business_id = 'fa200000-0000-0000-0000-000000000101'
      and lower(br.name) = lower('Sucursal Norte')
      and br.deleted_at is null
  ),
  '18. retry leaves one durable request and one canonical branch'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000001',
  true
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000101',
      'Sucursal Norte', 'Otra dirección', '555-0100',
      'org-2b-create-north'
    )$$,
  '23505',
  'idempotency_key was already used with an incompatible branch payload',
  '19. one idempotency key cannot be reused with an incompatible payload'
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000101',
      'sucursal norte', 'Calle 10', '555-0100',
      'org-2b-duplicate-name'
    )$$,
  '23505',
  null,
  '20. a distinct idempotency key cannot duplicate a branch name'
);
reset role;

select is(
  (
    select count(*)::bigint
    from public.branches br
    where br.business_id = 'fa200000-0000-0000-0000-000000000101'
      and br.is_primary = true
      and br.status = 'active'
      and br.deleted_at is null
  ),
  1::bigint,
  '21. additional branch creation preserves exactly one active primary'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa200000-0000-0000-0000-000000000001',
  true
);
select throws_ok(
  $$select public.create_business_branch(
      'fa200000-0000-0000-0000-000000000103',
      'Cannot Become First', null, null, 'org-2b-no-primary'
    )$$,
  '23514',
  'Business must have exactly one active primary branch before creating an additional branch',
  '22. ORG-2B cannot create the first branch of a business'
);
select throws_ok(
  $$select public.ensure_business_runtime_setup(
      'fa200000-0000-0000-0000-000000000101',
      'fa200000-0000-0000-0000-000000000199',
      null, '{}'::jsonb, 'Historical Bypass', 'Caja Principal', 'POS'
    )$$,
  '42501',
  'Runtime setup cannot create branches; use create_business_branch or private platform onboarding',
  '23. historical runtime setup cannot create an absent branch'
);
reset role;

select * from finish();

rollback;
