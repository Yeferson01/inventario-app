begin;
select plan(37);

insert into auth.users (id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values ('b4000000-0000-0000-0000-000000000101', 'authenticated',
  'authenticated', 'w4b-owner@example.test', '', now(), '{}', '{}', now(), now());
insert into public.profiles (id, full_name, role, status)
values ('b4000000-0000-0000-0000-000000000101', 'W4B Owner', 'owner', 'active');
insert into public.businesses (id, name, status)
values ('b4000000-0000-0000-0000-000000000001', 'W4B Business', 'active');
insert into public.branches (id, business_id, name, status) values
  ('b4000000-0000-0000-0000-000000000011',
   'b4000000-0000-0000-0000-000000000001', 'W4B Primary', 'active'),
  ('b4000000-0000-0000-0000-000000000012',
   'b4000000-0000-0000-0000-000000000001', 'W4B Other', 'active');
insert into public.business_members (id, business_id, profile_id, branch_id,
  role_id, status)
select 'b4000000-0000-0000-0000-000000000041',
  'b4000000-0000-0000-0000-000000000001',
  'b4000000-0000-0000-0000-000000000101', null, id, 'active'
from public.roles where business_id is null and name = 'owner'
  and deleted_at is null limit 1;
insert into public.app_devices (id, business_id, profile_id, branch_id,
  installation_id, status) values
  ('b4000000-0000-0000-0000-000000000051',
   'b4000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000101',
   'b4000000-0000-0000-0000-000000000011', 'w4b-device-a', 'active'),
  ('b4000000-0000-0000-0000-000000000052',
   'b4000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000101',
   'b4000000-0000-0000-0000-000000000011', 'w4b-device-b', 'active');
insert into public.products (id, business_id, name, sale_price, purchase_price,
  sale_mode) values
  ('b4000000-0000-0000-0000-000000000201',
   'b4000000-0000-0000-0000-000000000001', 'Papa', 1000, 800, 'weight'),
  ('b4000000-0000-0000-0000-000000000202',
   'b4000000-0000-0000-0000-000000000001', 'Empty', 1000, 800, 'weight'),
  ('b4000000-0000-0000-0000-000000000203',
   'b4000000-0000-0000-0000-000000000001', 'Unknown cost', 1000, 800, 'weight'),
  ('b4000000-0000-0000-0000-000000000204',
   'b4000000-0000-0000-0000-000000000001', 'Unit', 1000, 800, 'unit'),
  ('b4000000-0000-0000-0000-000000000205',
   'b4000000-0000-0000-0000-000000000001', 'Kilogram quote', 1000, 800, 'weight'),
  ('b4000000-0000-0000-0000-000000000206',
   'b4000000-0000-0000-0000-000000000001', 'Pound quote', 1000, 800, 'weight');
insert into public.product_stock_balances (business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost, cost_basis_cents) values
  ('b4000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000011',
   'b4000000-0000-0000-0000-000000000201', 3000, 0, 1.60, 480000),
  ('b4000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000011',
   'b4000000-0000-0000-0000-000000000203', 100, 0, null, null);

create temporary table w4b_cases (
  name text primary key, batch_id uuid not null, purchase_id uuid not null,
  item_id uuid not null, mutation_id uuid not null
);
create function pg_temp.seed_w4b_case(p_name text, p_product uuid,
  p_quantity integer, p_quote bigint, p_basis integer, p_subtotal bigint,
  p_mode text default 'weight', p_device uuid default
    'b4000000-0000-0000-0000-000000000051',
  p_purchase_branch uuid default
    'b4000000-0000-0000-0000-000000000011') returns uuid
language plpgsql as $$
declare
  v_batch uuid := extensions.gen_random_uuid();
  v_purchase uuid := extensions.gen_random_uuid();
  v_item uuid := extensions.gen_random_uuid();
  v_item_mutation uuid := extensions.gen_random_uuid();
  v_business uuid := 'b4000000-0000-0000-0000-000000000001';
  v_branch uuid := 'b4000000-0000-0000-0000-000000000011';
  v_profile uuid := 'b4000000-0000-0000-0000-000000000101';
  v_contract text;
  v_item_payload jsonb;
begin
  v_contract := case when p_mode = 'unit' then 'exact_v1'
    else 'exact_weight_basis_v1' end;
  insert into public.sync_batches (id, business_id, app_device_id,
    profile_id, branch_id, client_batch_id, direction, status,
    mutation_count, metadata)
  values (v_batch,v_business,p_device,v_profile,v_branch,
    'w4b-'||p_name,'upload','pending',2,'{"domain":"purchases"}');
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (extensions.gen_random_uuid(),v_business,v_batch,p_device,v_profile,
    v_branch,p_name||'-header',1,'purchases',v_purchase,'insert',
    jsonb_build_object('id',v_purchase,'business_id',v_business,
      'branch_id',p_purchase_branch,'total',p_subtotal::numeric/100,
      'status','completed','metadata',jsonb_build_object(
        'monetary_contract_version',v_contract,'item_count',1,
        'total_cents',p_subtotal::text)),
    p_name||'-header-key','pending');
  v_item_payload := jsonb_build_object('id',v_item,'purchase_id',v_purchase,
    'business_id',v_business,'branch_id',v_branch,'product_id',p_product,
    'quantity',p_quantity,'unit_cost',p_quote::numeric/100,
    'subtotal',p_subtotal::numeric/100,
    'idempotency_key',p_name||'-item-key',
    'metadata',jsonb_build_object('unit_cost_cents',p_quote::text,
      'subtotal_cents',p_subtotal::text,'sale_mode_snapshot',p_mode,
      'cost_basis_quantity_snapshot',p_basis));
  if p_mode = 'weight' then
    v_item_payload := v_item_payload || jsonb_build_object(
      'contract_version','weighted_purchase_v1','sale_mode','weight',
      'sale_mode_snapshot','weight','cost_basis_quantity',p_basis,
      'cost_basis_quantity_snapshot',p_basis,
      'unit_cost_cents',p_quote,'subtotal_cents',p_subtotal);
  end if;
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (v_item_mutation,v_business,v_batch,p_device,v_profile,v_branch,
    p_name||'-item',2,'purchase_items',v_item,'insert',v_item_payload,
    p_name||'-item-key','pending');
  insert into w4b_cases values(p_name,v_batch,v_purchase,v_item,v_item_mutation);
  return v_batch;
end;
$$;

select set_config('request.jwt.claim.sub',
  'b4000000-0000-0000-0000-000000000101',true);
select ok(not has_function_privilege('authenticated',
  'private.apply_sync_purchase_mutation(uuid)','EXECUTE'),
  'private purchase applier remains inaccessible to authenticated');
select ok(not has_function_privilege('anon',
  'private.apply_sync_purchase_mutation(uuid)','EXECUTE'),
  'private purchase applier remains inaccessible to anon');
select is(private.calculate_basis_amount_cents(90000,10000,500),
  1800000::bigint,'W2A computes plaza subtotal exactly');

select pg_temp.seed_w4b_case('plaza',
  'b4000000-0000-0000-0000-000000000201',10000,90000,500,1800000);
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='plaza'),'apply_purchases')->>'status'),'completed',
  'valid weighted purchase completes');
select is((select quantity_on_hand from public.product_stock_balances
  where product_id='b4000000-0000-0000-0000-000000000201'),13000,
  'plaza stock is 3000 + 10000 grams');
select is((select cost_basis_cents from public.product_stock_balances
  where product_id='b4000000-0000-0000-0000-000000000201'),2280000::bigint,
  'plaza cost basis is 480000 + 1800000 cents');
select ok((select sale_mode_snapshot='weight' and quantity=10000
  and cost_basis_quantity_snapshot=500 and unit_cost_cents=90000
  and subtotal_cents=1800000 and
  monetary_contract_version='exact_weight_basis_v1'
  from public.purchase_items where id=(select item_id from w4b_cases
    where name='plaza')),'immutable weighted snapshots persisted');
select ok((select quantity_change=10000 and cost_effect_cents=1800000
  and source_type='purchase' from public.inventory_movements
  where idempotency_key='purchase:'||(select purchase_id::text
    from w4b_cases where name='plaza')||':item:'||
    (select item_id::text from w4b_cases where name='plaza')),
  'movement is in grams with exact positive cost effect');
select ok((select jsonb_array_length(metadata->'weighted_purchase_ack')=1
  from public.sync_batches where id=(select batch_id from w4b_cases
    where name='plaza')),'batch stores one authoritative weighted ACK');
select ok((select response->>'status'='completed'
    and jsonb_array_length(response->'weighted_purchase_ack')=1
    and response->'weighted_purchase_ack'->0->>'cost_basis_cents'='2280000'
  from (select public.process_sync_batch((select batch_id from w4b_cases
    where name='plaza'),'apply_purchases') response) x),
  'exact batch retry returns authoritative stock/cost ACK');
select is(public.apply_purchase_inventory_movements(
  (select purchase_id from w4b_cases where name='plaza')),1,
  'explicit inventory retry reuses existing item effect');
select is((select count(*) from public.inventory_movements where
  source_id=(select purchase_id from w4b_cases where name='plaza')),1::bigint,
  'retries do not duplicate the movement');
select ok((select response->>'status'='completed'
    and jsonb_array_length(response->'weighted_purchase_ack')=1
  from (select public.process_sync_batch((select batch_id from w4b_cases
    where name='plaza'),'apply_purchases') response) x),
  'second exact batch retry remains completed with one ACK');

select pg_temp.seed_w4b_case('device-b',
  'b4000000-0000-0000-0000-000000000201',5000,80000,500,800000,
  'weight','b4000000-0000-0000-0000-000000000052');
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='device-b'),'apply_purchases')->>'status'),'completed',
  'second device purchase completes');
select is((select quantity_on_hand from public.product_stock_balances
  where product_id='b4000000-0000-0000-0000-000000000201'),18000,
  'two devices serialize to 18000 grams');
select is((select cost_basis_cents from public.product_stock_balances
  where product_id='b4000000-0000-0000-0000-000000000201'),3080000::bigint,
  'two devices serialize to 3080000 cents');
select ok(strpos(lower(pg_get_functiondef(
  'private.prepare_inventory_movement_before_insert()'::regprocedure)),
  'for update')>0, 'existing balance preparation holds FOR UPDATE row lock');

select pg_temp.seed_w4b_case('bad-subtotal',
  'b4000000-0000-0000-0000-000000000201',10000,90000,500,1799999);
select public.process_sync_batch((select batch_id from w4b_cases
  where name='bad-subtotal'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='bad-subtotal')),'error',
  'mismatched W2A subtotal is rejected');

select pg_temp.seed_w4b_case('bad-basis',
  'b4000000-0000-0000-0000-000000000201',1000,90000,250,360000);
select public.process_sync_batch((select batch_id from w4b_cases
  where name='bad-basis'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='bad-basis')),'error','invalid basis rejected');

select pg_temp.seed_w4b_case('bad-mode',
  'b4000000-0000-0000-0000-000000000201',1,90000,1,90000,'unit');
select public.process_sync_batch((select batch_id from w4b_cases
  where name='bad-mode'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='bad-mode')),'error',
  'old UNIT payload cannot apply to WEIGHT product');

select pg_temp.seed_w4b_case('zero-grams',
  'b4000000-0000-0000-0000-000000000201',0,90000,500,0);
select public.process_sync_batch((select batch_id from w4b_cases
  where name='zero-grams'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='zero-grams')),'error','zero grams rejected');

select pg_temp.seed_w4b_case('negative-cost',
  'b4000000-0000-0000-0000-000000000201',1000,-1,500,100);
select public.process_sync_batch((select batch_id from w4b_cases
  where name='negative-cost'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='negative-cost')),'error',
  'negative quoted cost rejected');

select pg_temp.seed_w4b_case('empty',
  'b4000000-0000-0000-0000-000000000202',500,90000,500,90000);
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='empty'),'apply_purchases')->>'status'),'completed',
  'empty balance receives known cost');
select is((select cost_basis_cents from public.product_stock_balances
  where product_id='b4000000-0000-0000-0000-000000000202'),90000::bigint,
  'empty NULL cost basis becomes exact receipt cost');

select pg_temp.seed_w4b_case('unknown',
  'b4000000-0000-0000-0000-000000000203',500,90000,500,90000);
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='unknown'),'apply_purchases')->>'status'),'completed',
  'known receipt can join unknown legacy stock');
select ok((select cost_basis_cents is null and quantity_on_hand=600
  from public.product_stock_balances where
    product_id='b4000000-0000-0000-0000-000000000203'),
  'unknown prior cost remains unknown after known receipt');

select pg_temp.seed_w4b_case('kilogram',
  'b4000000-0000-0000-0000-000000000205',10000,160000,1000,1600000);
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='kilogram'),'apply_purchases')->>'status'),'completed',
  '10 kg quoted per kilogram completes');
select ok((select quantity_on_hand=10000 and cost_basis_cents=1600000
    from public.product_stock_balances where
      product_id='b4000000-0000-0000-0000-000000000205'),
  '10 kg at 160000 cents/kg preserves exact stock and cost basis');

select pg_temp.seed_w4b_case('pound',
  'b4000000-0000-0000-0000-000000000206',10000,80000,500,1600000);
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='pound'),'apply_purchases')->>'status'),'completed',
  '10 kg quoted at 80000 cents/pound completes');
select ok((select quantity_on_hand=10000 and cost_basis_cents=1600000
    from public.product_stock_balances where
      product_id='b4000000-0000-0000-0000-000000000206'),
  '10 kg at 80000 cents/pound preserves exact stock and cost basis');

select pg_temp.seed_w4b_case('unit',
  'b4000000-0000-0000-0000-000000000204',2,90000,1,180000,'unit');
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='unit'),'apply_purchases')->>'status'),'completed',
  'legacy UNIT purchase path remains operational');

select pg_temp.seed_w4b_case('mixed',
  'b4000000-0000-0000-0000-000000000202',500,90000,500,90000);
do $$
declare
  v_batch uuid;
  v_purchase uuid;
  v_item uuid := extensions.gen_random_uuid();
  v_business uuid := 'b4000000-0000-0000-0000-000000000001';
  v_branch uuid := 'b4000000-0000-0000-0000-000000000011';
  v_profile uuid := 'b4000000-0000-0000-0000-000000000101';
  v_device uuid := 'b4000000-0000-0000-0000-000000000051';
begin
  select batch_id,purchase_id into v_batch,v_purchase
    from w4b_cases where name='mixed';
  update public.sync_batches set mutation_count=3 where id=v_batch;
  update public.sync_mutations set payload =
    jsonb_set(jsonb_set(payload,'{total}','1900'::jsonb),
      '{metadata}',jsonb_build_object('monetary_contract_version',
        'exact_weight_basis_v1','item_count',2,'total_cents','190000'))
    where sync_batch_id=v_batch and entity_table='purchases';
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (extensions.gen_random_uuid(),v_business,v_batch,v_device,v_profile,
    v_branch,'mixed-unit-item',3,'purchase_items',v_item,'insert',
    jsonb_build_object('id',v_item,'purchase_id',v_purchase,
      'business_id',v_business,'branch_id',v_branch,
      'product_id','b4000000-0000-0000-0000-000000000204',
      'quantity',1,'unit_cost',1000,'subtotal',1000,
      'idempotency_key','mixed-unit-item-key',
      'metadata',jsonb_build_object('unit_cost_cents','100000',
        'subtotal_cents','100000','sale_mode_snapshot','unit',
        'cost_basis_quantity_snapshot',1)),
    'mixed-unit-item-key','pending');
end;
$$;
select is((public.process_sync_batch((select batch_id from w4b_cases
  where name='mixed'),'apply_purchases')->>'status'),'completed',
  'mixed UNIT and WEIGHT purchase completes in one batch');
select is((select count(*) from public.purchase_items where purchase_id=
  (select purchase_id from w4b_cases where name='mixed')),2::bigint,
  'mixed purchase persists both item contracts');
select is((select count(*) from public.inventory_movements where source_id=
  (select purchase_id from w4b_cases where name='mixed')),2::bigint,
  'mixed purchase applies one movement per item');

select pg_temp.seed_w4b_case('wrong-branch',
  'b4000000-0000-0000-0000-000000000201',500,90000,500,90000,
  'weight','b4000000-0000-0000-0000-000000000051',
  'b4000000-0000-0000-0000-000000000012');
select public.process_sync_batch((select batch_id from w4b_cases
  where name='wrong-branch'),'apply_purchases');
select is((select status from public.sync_mutations where id=(select mutation_id
  from w4b_cases where name='wrong-branch')),'error',
  'purchase item with wrong branch is rejected');

select throws_ok($$select public.register_pending_sync_mutation(
  jsonb_build_object('business_id',sm.business_id,
    'app_device_id',sm.app_device_id,'branch_id',sm.branch_id,
    'sync_batch_id',sm.sync_batch_id,
    'client_mutation_id',sm.client_mutation_id,
    'client_sequence',sm.client_sequence,
    'entity_table',sm.entity_table,'entity_id',sm.entity_id,
    'operation',sm.operation,'idempotency_key',sm.idempotency_key,
    'payload',jsonb_set(sm.payload,'{quantity}','9000'::jsonb))
  ) from public.sync_mutations sm where sm.id =
    (select mutation_id from w4b_cases where name='plaza')$$,
  'P0001','sync_mutation_idempotency_conflict',
  'same mutation key with changed grams fails closed');

select set_config('request.jwt.claim.sub','',true);
select throws_ok($$select public.process_sync_batch(
  (select batch_id from w4b_cases where name='plaza'),'apply_purchases')$$,
  '42501','Authentication required','missing auth cannot process batch');

select * from finish();
rollback;
