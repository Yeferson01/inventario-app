-- Exercise the real apply_inventory batch path. Fixtures roll back.
begin;

select plan(39);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  ('a5a00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated', 'authenticated', 'movement-actor-' || n || '@example.test',
  '', now(), '{}', '{}', now(), now()
from generate_series(101, 108) as n;

insert into public.profiles (id, full_name, status)
select
  ('a5a00000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid,
  'Movement Actor ' || n, 'active'
from generate_series(101, 108) as n;

insert into public.businesses (id, name, status)
values
  ('a5a00000-0000-0000-0000-000000000001', 'Movement Business A', 'active'),
  ('a5a00000-0000-0000-0000-000000000002', 'Movement Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('a5a00000-0000-0000-0000-000000000011', 'a5a00000-0000-0000-0000-000000000001', 'A1', 'active'),
  ('a5a00000-0000-0000-0000-000000000012', 'a5a00000-0000-0000-0000-000000000001', 'A2', 'active'),
  ('a5a00000-0000-0000-0000-000000000021', 'a5a00000-0000-0000-0000-000000000002', 'B1', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
select
  ('a5a00000-0000-0000-0000-' || lpad((n + 100)::text, 12, '0'))::uuid,
  'a5a00000-0000-0000-0000-000000000001',
  'movement_capability_' || n, 'One capability for source authorization tests', false
from generate_series(1, 8) as n;

insert into public.role_permissions (role_id, permission_id)
select
  ('a5a00000-0000-0000-0000-' || lpad((n + 100)::text, 12, '0'))::uuid,
  permission.id
from (values
  (1, 'sales.create'),
  (2, 'inventory.purchase'),
  (3, 'inventory.adjust'),
  (4, 'inventory.count'),
  (5, 'inventory.transfer'),
  (6, 'sales.refund')
) as capability(n, key)
join public.permissions permission on permission.key = capability.key;

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, accepted_at
)
select
  ('a5a00000-0000-0000-0000-' || lpad((n + 200)::text, 12, '0'))::uuid,
  'a5a00000-0000-0000-0000-000000000001',
  ('a5a00000-0000-0000-0000-' || lpad((n + 100)::text, 12, '0'))::uuid,
  'a5a00000-0000-0000-0000-000000000011',
  ('a5a00000-0000-0000-0000-' || lpad((n + 100)::text, 12, '0'))::uuid,
  'active',
  now()
from generate_series(1, 8) as n;

-- Devices are registered while membership is valid, then revocation is
-- simulated before processing the affected batches.
insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, accepted_at
)
values (
  'a5a00000-0000-0000-0000-000000000291',
  'a5a00000-0000-0000-0000-000000000002',
  'a5a00000-0000-0000-0000-000000000101',
  'a5a00000-0000-0000-0000-000000000021',
  (select id from public.roles where business_id is null and name = 'cashier' limit 1),
  'active', now()
);

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
select
  ('a5a00000-0000-0000-0000-' || lpad((n + 300)::text, 12, '0'))::uuid,
  'a5a00000-0000-0000-0000-000000000001',
  ('a5a00000-0000-0000-0000-' || lpad((n + 100)::text, 12, '0'))::uuid,
  'a5a00000-0000-0000-0000-000000000011',
  'movement-device-' || n, 'active'
from generate_series(1, 8) as n;

insert into public.app_devices (
  id, business_id, profile_id, branch_id, installation_id, status
)
values
  ('a5a00000-0000-0000-0000-000000000391',
   'a5a00000-0000-0000-0000-000000000001',
   'a5a00000-0000-0000-0000-000000000101',
   'a5a00000-0000-0000-0000-000000000012', 'movement-device-a2', 'active'),
  ('a5a00000-0000-0000-0000-000000000392',
   'a5a00000-0000-0000-0000-000000000002',
   'a5a00000-0000-0000-0000-000000000101',
   'a5a00000-0000-0000-0000-000000000021', 'movement-device-b1', 'active');

update public.business_members
set status = 'suspended'
where id in (
  'a5a00000-0000-0000-0000-000000000208',
  'a5a00000-0000-0000-0000-000000000291'
);

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock, status
)
values (
  'a5a00000-0000-0000-0000-000000000401',
  'a5a00000-0000-0000-0000-000000000001',
  'Movement Product', 10, 0, 0, 'active'
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost
)
values (
  'a5a00000-0000-0000-0000-000000000411',
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000011',
  'a5a00000-0000-0000-0000-000000000401',
  100, 0, 5
);

create function pg_temp.run_movement_case(
  p_actor integer,
  p_source_type text,
  p_movement_type text,
  p_quantity_change integer,
  p_business_id uuid default 'a5a00000-0000-0000-0000-000000000001',
  p_branch_id uuid default 'a5a00000-0000-0000-0000-000000000011',
  p_payload_override jsonb default '{}'::jsonb,
  p_retry boolean default false
)
returns jsonb
language plpgsql
as $$
declare
  v_profile_id uuid := (
    'a5a00000-0000-0000-0000-' || lpad((p_actor + 100)::text, 12, '0')
  )::uuid;
  v_device_id uuid;
  v_batch_id uuid := gen_random_uuid();
  v_mutation_id uuid := gen_random_uuid();
  v_movement_id uuid := gen_random_uuid();
  v_payload jsonb;
  v_result jsonb;
begin
  v_device_id := case
    when p_branch_id = 'a5a00000-0000-0000-0000-000000000012'
      then 'a5a00000-0000-0000-0000-000000000391'::uuid
    when p_branch_id = 'a5a00000-0000-0000-0000-000000000021'
      then 'a5a00000-0000-0000-0000-000000000392'::uuid
    else (
      'a5a00000-0000-0000-0000-' || lpad((p_actor + 300)::text, 12, '0')
    )::uuid
  end;

  insert into public.sync_batches (
    id, business_id, app_device_id, profile_id, branch_id,
    client_batch_id, direction, status
  ) values (
    v_batch_id, p_business_id, v_device_id, v_profile_id, p_branch_id,
    v_batch_id::text, 'upload', 'pending'
  );

  v_payload := jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'product_id', 'a5a00000-0000-0000-0000-000000000401',
    'movement_type', p_movement_type,
    'source_type', p_source_type,
    'quantity_change', p_quantity_change,
    'unit_cost', 5,
    'idempotency_key', v_movement_id::text
  ) || p_payload_override;

  insert into public.sync_mutations (
    id, business_id, sync_batch_id, app_device_id, profile_id, branch_id,
    client_mutation_id, client_sequence, entity_table, entity_id, operation,
    payload, status, idempotency_key
  ) values (
    v_mutation_id, p_business_id, v_batch_id, v_device_id, v_profile_id,
    p_branch_id, v_mutation_id::text, 1, 'inventory_movements',
    v_movement_id, 'insert', v_payload, 'pending', v_movement_id::text
  );

  perform set_config('request.jwt.claim.sub', v_profile_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform public.process_sync_batch(v_batch_id, 'apply_inventory');
  if p_retry then
    perform public.process_sync_batch(v_batch_id, 'apply_inventory');
  end if;
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.role', '', true);

  select jsonb_build_object(
    'status', mutation.status,
    'batch_status', batch.status,
    'conflict_count', batch.conflict_count,
    'movement_count', (
      select count(*) from public.inventory_movements movement
      where movement.id = v_movement_id
    ),
    'movement_id', v_movement_id,
    'batch_id', v_batch_id,
    'mutation_id', v_mutation_id
  ) into v_result
  from public.sync_mutations mutation
  join public.sync_batches batch on batch.id = mutation.sync_batch_id
  where mutation.id = v_mutation_id;

  return v_result;
end;
$$;

select is((pg_temp.run_movement_case(1, 'sale', 'sale', -1)->>'status'), 'applied', 'SA-01 sales.create allows sale');
select is((pg_temp.run_movement_case(1, 'manual_adjustment', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-02 sales.create denies manual adjustment');
select is((pg_temp.run_movement_case(1, 'loss', 'loss', -1)->>'status'), 'conflict', 'SA-03 sales.create denies loss');
select is((pg_temp.run_movement_case(1, 'transfer', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-04 sales.create denies transfer');
select is((pg_temp.run_movement_case(1, 'stock_count', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-05 sales.create denies stock count');

select is((pg_temp.run_movement_case(2, 'purchase', 'purchase', 1)->>'status'), 'applied', 'SA-06 inventory.purchase allows purchase');
select is((pg_temp.run_movement_case(2, 'manual_adjustment', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-07 inventory.purchase denies adjustment');

select is((pg_temp.run_movement_case(3, 'manual_adjustment', 'manual_adjustment', 1)->>'status'), 'applied', 'SA-08 inventory.adjust allows adjustment');
select is((pg_temp.run_movement_case(3, 'loss', 'loss', -1)->>'status'), 'applied', 'SA-09 inventory.adjust allows loss');
select is((pg_temp.run_movement_case(3, 'transfer', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-10 inventory.adjust denies transfer');
select is((pg_temp.run_movement_case(3, 'stock_count', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-11 inventory.adjust denies stock count');

select is((pg_temp.run_movement_case(4, 'stock_count', 'manual_adjustment', 1)->>'status'), 'applied', 'SA-12 inventory.count allows stock count');
select is((pg_temp.run_movement_case(4, 'manual_adjustment', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-13 inventory.count denies adjustment');
select is((pg_temp.run_movement_case(5, 'transfer', 'manual_adjustment', 1)->>'status'), 'applied', 'SA-14 inventory.transfer allows transfer');
select is((pg_temp.run_movement_case(5, 'loss', 'loss', -1)->>'status'), 'conflict', 'SA-15 inventory.transfer denies loss');

select is((pg_temp.run_movement_case(6, 'return', 'return', 1)->>'status'), 'applied', 'SA-16 sales.refund allows return');
select is((pg_temp.run_movement_case(3, 'return', 'return', 1)->>'status'), 'applied', 'SA-17 inventory.adjust allows return');
select is((pg_temp.run_movement_case(7, 'return', 'return', 1)->>'status'), 'conflict', 'SA-18 no return capability denies return');

select is((pg_temp.run_movement_case(3, 'unknown', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-19 unknown source fails closed');
select is((pg_temp.run_movement_case(3, null, 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-20 null source fails closed');
select is((pg_temp.run_movement_case(3, '', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-21 empty source fails closed');
select is((pg_temp.run_movement_case(1, 'sale', 'purchase', -1)->>'status'), 'conflict', 'SA-22 inconsistent movement/source fails closed');

select is((pg_temp.run_movement_case(1, 'sale', 'sale', -1,
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000012')->>'status'), 'conflict',
  'SA-23 branch without membership denies movement');
select is((pg_temp.run_movement_case(1, 'sale', 'sale', -1,
  'a5a00000-0000-0000-0000-000000000002',
  'a5a00000-0000-0000-0000-000000000021')->>'status'), 'conflict',
  'SA-24 business without membership denies movement');
select is((pg_temp.run_movement_case(8, 'sale', 'sale', -1)->>'status'), 'conflict', 'SA-25 inactive membership denies movement');

select is((pg_temp.run_movement_case(3, 'reversal', 'manual_adjustment', 1)->>'status'), 'applied', 'SA-26 inventory.adjust allows reversal');
select is((pg_temp.run_movement_case(1, 'reversal', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-27 sales.create denies reversal');
select is((pg_temp.run_movement_case(3, 'offline_sync', 'manual_adjustment', 1)->>'status'), 'conflict', 'SA-28 legacy generic source fails closed');
select is((pg_temp.run_movement_case(3, 'manual_adjustment', 'manual_adjustment', 1,
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000011',
  '{"reference_type":"manual_initial_stock"}'::jsonb)->>'status'), 'applied',
  'SA-29 initial stock uses canonical manual_adjustment source');

create temporary table movement_retry_result on commit drop as
select pg_temp.run_movement_case(1, 'sale', 'sale', -1,
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000011', '{}'::jsonb, true) as result;

select is((select result->>'status' from movement_retry_result), 'applied',
  'SA-30 retry leaves the applied mutation terminal');
select is((select (result->>'movement_count')::integer from movement_retry_result), 1,
  'SA-31 retry does not duplicate the ledger movement');
select is((select result->>'batch_status' from movement_retry_result), 'completed',
  'SA-32 retry leaves the batch completed');

select is((pg_temp.run_movement_case(1, 'manual_adjustment', 'manual_adjustment', 1)->>'movement_count')::integer,
  0, 'SA-33 denied source never inserts a ledger movement');
select is((pg_temp.run_movement_case(3, 'manual_adjustment', 'manual_adjustment', 1,
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000011',
  '{"business_id":"a5a00000-0000-0000-0000-000000000002"}'::jsonb)->>'status'),
  'conflict', 'SA-34 payload cannot override the batch business');
select is((pg_temp.run_movement_case(3, 'manual_adjustment', 'manual_adjustment', 1,
  'a5a00000-0000-0000-0000-000000000001',
  'a5a00000-0000-0000-0000-000000000011',
  '{"branch_id":"a5a00000-0000-0000-0000-000000000012"}'::jsonb)->>'status'),
  'conflict', 'SA-35 payload cannot override the batch branch');
select is((pg_temp.run_movement_case(1, 'sale', 'sale', 1)->>'status'),
  'conflict', 'SA-36 sale source enforces negative quantity');
select is((pg_temp.run_movement_case(2, 'purchase', 'purchase', -1)->>'status'),
  'conflict', 'SA-37 purchase source enforces positive quantity');
select ok(not has_function_privilege(
  'authenticated',
  'private.apply_sync_inventory_movement_mutation_base_before_source_auth(uuid)',
  'EXECUTE'
), 'SA-38 authenticated cannot bypass the guard by calling the base applier');
select ok(not has_function_privilege(
  'anon', 'private.apply_sync_inventory_movement_mutation(uuid)', 'EXECUTE'
), 'SA-39 anon cannot call the guarded applier');

select * from finish();
rollback;
