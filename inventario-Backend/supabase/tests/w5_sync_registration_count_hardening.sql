begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('55000000-0000-0000-0000-000000000001', 'authenticated',
  'authenticated', 'w5-count@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, status)
values ('55000000-0000-0000-0000-000000000001', 'W5 Count', 'active');
insert into public.businesses (id, name, status)
values ('55000000-0000-0000-0000-000000000002', 'W5 Count', 'active');
insert into public.branches (id, business_id, name, status)
values ('55000000-0000-0000-0000-000000000003',
  '55000000-0000-0000-0000-000000000002', 'Primary', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select '55000000-0000-0000-0000-000000000004',
  '55000000-0000-0000-0000-000000000002',
  '55000000-0000-0000-0000-000000000001', null, id, 'active'
from public.roles where name = 'owner' and business_id is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status)
values ('55000000-0000-0000-0000-000000000005',
  '55000000-0000-0000-0000-000000000002',
  '55000000-0000-0000-0000-000000000001', null, 'w5-count-device', 'active');
insert into public.products (id, business_id, name, sale_price,
  purchase_price, stock_quantity, minimum_stock)
values ('55000000-0000-0000-0000-000000000006',
  '55000000-0000-0000-0000-000000000002', 'Count Product', 20, 10, 0, 0);

create function pg_temp.batch_json(p_id uuid, p_client text, p_count integer)
returns jsonb language sql immutable as $$
  select jsonb_build_object('id',p_id,
    'business_id','55000000-0000-0000-0000-000000000002',
    'app_device_id','55000000-0000-0000-0000-000000000005',
    'profile_id','55000000-0000-0000-0000-000000000001',
    'branch_id','55000000-0000-0000-0000-000000000003',
    'client_batch_id',p_client,'direction','upload',
    'mutation_count',p_count,'metadata',jsonb_build_object('source','w5-count'));
$$;
create function pg_temp.mutation_json(p_batch uuid, p_sequence integer,
  p_client text)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'business_id','55000000-0000-0000-0000-000000000002',
    'sync_batch_id',p_batch,
    'app_device_id','55000000-0000-0000-0000-000000000005',
    'profile_id','55000000-0000-0000-0000-000000000001',
    'branch_id','55000000-0000-0000-0000-000000000003',
    'client_mutation_id',p_client,'client_sequence',p_sequence,
    'entity_table','products',
    'entity_id','55000000-0000-0000-0000-000000000006',
    'operation','update','payload',jsonb_build_object('sale_price',30),
    'idempotency_key',p_client);
$$;
create function pg_temp.seed_legacy(p_id uuid, p_client text,
  p_stored integer, p_actual integer)
returns void language plpgsql as $$
declare
  v_sequence integer;
begin
  insert into public.sync_batches (id,business_id,app_device_id,profile_id,
    branch_id,client_batch_id,direction,status,mutation_count,metadata)
  values (p_id,'55000000-0000-0000-0000-000000000002',
    '55000000-0000-0000-0000-000000000005',
    '55000000-0000-0000-0000-000000000001',
    '55000000-0000-0000-0000-000000000003',p_client,'upload','pending',
    p_stored,'{"source":"w5-count"}'::jsonb);
  for v_sequence in 1..p_actual loop
    insert into public.sync_mutations (business_id,sync_batch_id,
      app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
      entity_table,entity_id,operation,payload,idempotency_key,status)
    values ('55000000-0000-0000-0000-000000000002',p_id,
      '55000000-0000-0000-0000-000000000005',
      '55000000-0000-0000-0000-000000000001',
      '55000000-0000-0000-0000-000000000003',
      p_client||'-'||v_sequence,v_sequence,'products',
      '55000000-0000-0000-0000-000000000006','update',
      '{"sale_price":30}'::jsonb,p_client||'-'||v_sequence,'pending');
  end loop;
end;
$$;

select pg_temp.seed_legacy('55000000-0000-0000-0000-000000000020',
  'legacy-full',6,3);
select pg_temp.seed_legacy('55000000-0000-0000-0000-000000000030',
  'legacy-partial',4,1);
select pg_temp.seed_legacy('55000000-0000-0000-0000-000000000040',
  'non-legacy',5,1);
select pg_temp.seed_legacy('55000000-0000-0000-0000-000000000050',
  'incomplete',3,1);
select pg_temp.seed_legacy('55000000-0000-0000-0000-000000000060',
  'overflow',2,3);

select ok(not exists (select 1 from pg_trigger
  where tgrelid = 'public.sync_mutations'::regclass
    and tgname = 'trg_sync_mutations_increment_batch_count'
    and not tgisinternal), 'legacy counter trigger is absent');

set local role authenticated;
select set_config('request.jwt.claim.sub',
  '55000000-0000-0000-0000-000000000001',true);

select is(public.register_pending_sync_batch(pg_temp.batch_json(
  '55000000-0000-0000-0000-000000000010','new-batch',3))->>'id',
  '55000000-0000-0000-0000-000000000010', 'new batch registers');
select is(jsonb_array_length(public.register_pending_sync_mutations(
  jsonb_build_array(
    pg_temp.mutation_json('55000000-0000-0000-0000-000000000010',1,'new-1'),
    pg_temp.mutation_json('55000000-0000-0000-0000-000000000010',2,'new-2'),
    pg_temp.mutation_json('55000000-0000-0000-0000-000000000010',3,'new-3')
  ))),3,'three mutations register');
select is((select mutation_count from public.sync_batches
  where id='55000000-0000-0000-0000-000000000010'),3,
  'declared count stays three after inserts');
select is((select count(*) from public.sync_mutations
  where sync_batch_id='55000000-0000-0000-0000-000000000010'),3::bigint,
  'three active mutations exist');
select is(public.register_pending_sync_batch(pg_temp.batch_json(
  '55000000-0000-0000-0000-000000000010','new-batch',3))->>'id',
  '55000000-0000-0000-0000-000000000010','normal retry reuses batch');
select is((select count(*) from public.sync_batches
  where client_batch_id='new-batch'),1::bigint,'normal retry adds no batch');

select is(public.register_pending_sync_batch(pg_temp.batch_json(
  '55000000-0000-0000-0000-000000000020','legacy-full',3))->>'id',
  '55000000-0000-0000-0000-000000000020',
  'complete legacy signature returns same identity');
select is((select mutation_count from public.sync_batches
  where id='55000000-0000-0000-0000-000000000020'),3,
  'complete legacy count normalizes to declared three');
select is((select count(*) from public.sync_batches
  where client_batch_id='legacy-full'),1::bigint,
  'complete legacy retry adds no batch');

select is(public.register_pending_sync_batch(pg_temp.batch_json(
  '55000000-0000-0000-0000-000000000030','legacy-partial',3))->>'id',
  '55000000-0000-0000-0000-000000000030',
  'partial legacy signature returns same identity');
select is((select mutation_count from public.sync_batches
  where id='55000000-0000-0000-0000-000000000030'),3,
  'partial legacy count normalizes to declared three');
select is(jsonb_array_length(public.register_pending_sync_mutations(
  jsonb_build_array(
    pg_temp.mutation_json('55000000-0000-0000-0000-000000000030',2,
      'legacy-partial-2'),
    pg_temp.mutation_json('55000000-0000-0000-0000-000000000030',3,
      'legacy-partial-3')
  ))),2,'partial legacy batch accepts remaining mutations');
select is((select count(*) from public.sync_mutations
  where sync_batch_id='55000000-0000-0000-0000-000000000030'),3::bigint,
  'partial legacy batch converges to declared count');

select throws_ok($stmt$select public.register_pending_sync_batch(
  pg_temp.batch_json('55000000-0000-0000-0000-000000000040',
    'non-legacy',3))$stmt$,'P0001','sync_batch_idempotency_conflict',
  'non-legacy mismatch is rejected');
select is((select mutation_count from public.sync_batches
  where id='55000000-0000-0000-0000-000000000040'),5,
  'non-legacy count is unchanged');

select throws_ok($stmt$select public.process_sync_batch(
  '55000000-0000-0000-0000-000000000050','apply_catalog')$stmt$,
  'P0001','sync_batch_registration_incomplete',
  'incomplete registration is rejected before processing');
select is((select status from public.sync_batches
  where id='55000000-0000-0000-0000-000000000050'),'pending',
  'incomplete batch remains pending');
select is((select status from public.sync_mutations
  where sync_batch_id='55000000-0000-0000-0000-000000000050'),
  'pending','incomplete mutation remains pending');
select is((select sale_price from public.products
  where id='55000000-0000-0000-0000-000000000006'),20::numeric,
  'incomplete process applies no product update');

select throws_ok($stmt$select public.process_sync_batch(
  '55000000-0000-0000-0000-000000000060','apply_catalog')$stmt$,
  'P0001','sync_batch_registration_overflow',
  'overflow registration is rejected before processing');
select is((select status from public.sync_batches
  where id='55000000-0000-0000-0000-000000000060'),'pending',
  'overflow batch remains pending');

select is(public.process_sync_batch(
  '55000000-0000-0000-0000-000000000010','apply_catalog')->>'status',
  'completed','complete batch delegates to existing processor');
select is((select sale_price from public.products
  where id='55000000-0000-0000-0000-000000000006'),30::numeric,
  'complete batch applies product update');
select is(public.process_sync_batch(
  '55000000-0000-0000-0000-000000000010','apply_catalog')->>'status',
  'completed','terminal retry retains idempotent result');

select * from finish();
rollback;
