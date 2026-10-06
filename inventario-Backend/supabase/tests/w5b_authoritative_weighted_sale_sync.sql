begin;
select plan(76);

insert into auth.users (id,aud,role,email,encrypted_password,
  email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('b5000000-0000-0000-0000-000000000101','authenticated',
  'authenticated','w5b-owner@example.test','',now(),'{}','{}',now(),now());
insert into public.profiles (id,full_name,role,status)
values ('b5000000-0000-0000-0000-000000000101','W5B Owner','owner','active');
insert into public.businesses (id,name,status)
values ('b5000000-0000-0000-0000-000000000001','W5B Business','active');
insert into public.branches (id,business_id,name,status) values
  ('b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000001','Primary','active'),
  ('b5000000-0000-0000-0000-000000000012',
   'b5000000-0000-0000-0000-000000000001','Other','active');
insert into public.business_members (id,business_id,profile_id,branch_id,
  role_id,status)
select 'b5000000-0000-0000-0000-000000000041',
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000101',null,id,'active'
from public.roles where business_id is null and name='owner'
  and deleted_at is null limit 1;
insert into public.app_devices (id,business_id,profile_id,branch_id,
  installation_id,status) values
  ('b5000000-0000-0000-0000-000000000051',
   'b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000101',
   'b5000000-0000-0000-0000-000000000011','w5b-a','active'),
  ('b5000000-0000-0000-0000-000000000052',
   'b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000101',
   'b5000000-0000-0000-0000-000000000011','w5b-b','active');
insert into public.cash_registers (id,business_id,branch_id,name,status)
values ('b5000000-0000-0000-0000-000000000061',
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000011','W5B Register','active');
insert into public.cash_sessions (id,business_id,branch_id,cash_register_id,
  opened_by,opening_amount,status,opened_at,closed_at) values
  ('b5000000-0000-0000-0000-000000000071',
   'b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000061',
   'b5000000-0000-0000-0000-000000000101',0,'open',now(),null),
  ('b5000000-0000-0000-0000-000000000072',
   'b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000061',
   'b5000000-0000-0000-0000-000000000101',0,'closed',
   now()-interval '1 hour',now());
insert into public.products (id,business_id,name,sale_price,purchase_price,
  sale_mode) values
  ('b5000000-0000-0000-0000-000000000201',
   'b5000000-0000-0000-0000-000000000001','Weight',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000202',
   'b5000000-0000-0000-0000-000000000001','Zero',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000203',
   'b5000000-0000-0000-0000-000000000001','Unknown',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000204',
   'b5000000-0000-0000-0000-000000000001','Unit',1000,500,'unit'),
  ('b5000000-0000-0000-0000-000000000205',
   'b5000000-0000-0000-0000-000000000001',
   'Stale Weight',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000206',
   'b5000000-0000-0000-0000-000000000001',
   'Stale Unknown Cost',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000207',
   'b5000000-0000-0000-0000-000000000001',
   'Stale Mixed Weight',12000,1000,'weight'),
  ('b5000000-0000-0000-0000-000000000208',
   'b5000000-0000-0000-0000-000000000001',
   'Stale Mixed Unit',1000,500,'unit');
insert into public.product_stock_balances (business_id,branch_id,product_id,
  quantity_on_hand,quantity_reserved,cost_basis_cents) values
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000201',13000,0,2280000),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000202',100,0,0),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000203',100,0,null),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000204',10,0,null),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000205',13000,0,2280000),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000206',
   100,0,null),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000207',
   1000,0,100000),
  ('b5000000-0000-0000-0000-000000000001',
   'b5000000-0000-0000-0000-000000000011',
   'b5000000-0000-0000-0000-000000000208',
   10,0,null);

create temporary table w5b_cases (name text primary key,batch_id uuid,
  sale_id uuid,item_id uuid,payment_id uuid,item_mutation_id uuid);
create function pg_temp.seed_w5b(p_name text,p_product uuid,p_quantity integer,
  p_price bigint,p_total bigint,p_basis integer default 500,
  p_mode text default 'weight',p_discount numeric default 0,
  p_tax numeric default 0,p_session uuid default
    'b5000000-0000-0000-0000-000000000071',
  p_device uuid default 'b5000000-0000-0000-0000-000000000051')
returns uuid language plpgsql as $$
declare
  v_batch uuid := extensions.gen_random_uuid();
  v_sale uuid := extensions.gen_random_uuid();
  v_item uuid := extensions.gen_random_uuid();
  v_payment uuid := extensions.gen_random_uuid();
  v_item_mutation uuid := extensions.gen_random_uuid();
  v_business uuid := 'b5000000-0000-0000-0000-000000000001';
  v_branch uuid := 'b5000000-0000-0000-0000-000000000011';
  v_profile uuid := 'b5000000-0000-0000-0000-000000000101';
  v_subtotal numeric := (p_total::numeric / 100) + p_discount - p_tax;
begin
  insert into public.sync_batches (id,business_id,app_device_id,profile_id,
    branch_id,client_batch_id,direction,status,mutation_count,metadata)
  values (v_batch,v_business,p_device,v_profile,v_branch,
    'w5b-'||p_name,'upload','pending',3,jsonb_build_object('domain','pos',
      'monetary_contract_version','exact_weight_sale_v1','item_count',1,
      'payment_count',1));
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (extensions.gen_random_uuid(),v_business,v_batch,p_device,v_profile,
    v_branch,p_name||'-sale',1,'sales',v_sale,'insert',
    jsonb_build_object('id',v_sale,'business_id',v_business,
      'branch_id',v_branch,
      'cash_register_id','b5000000-0000-0000-0000-000000000061',
      'cash_session_id',p_session,'subtotal',v_subtotal,
      'discount_total',p_discount,'tax_total',p_tax,
      'total',p_total::numeric/100,'total_cents',p_total,
      'status','completed','monetary_contract_version','exact_weight_sale_v1',
      'metadata',jsonb_build_object('monetary_contract_version',
        'exact_weight_sale_v1','total_cents',p_total)),
    p_name||'-sale-key','pending');
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (v_item_mutation,v_business,v_batch,p_device,v_profile,v_branch,
    p_name||'-item',2,'sale_items',v_item,'insert',
    jsonb_build_object('id',v_item,'business_id',v_business,
      'branch_id',v_branch,'sale_id',v_sale,'product_id',p_product,
      'quantity',p_quantity,'unit_price',p_price::numeric/100,
      'subtotal',v_subtotal,'discount_amount',p_discount,'tax_amount',p_tax,
      'total',p_total::numeric/100,
      'monetary_contract_version','exact_weight_sale_v1',
      'sale_mode_snapshot',p_mode,
      'price_basis_quantity_snapshot',p_basis,
      'price_cents_snapshot',p_price,'line_total_cents',p_total),
    p_name||'-item-key','pending');
  insert into public.sync_mutations (id,business_id,sync_batch_id,
    app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
    entity_table,entity_id,operation,payload,idempotency_key,status)
  values (extensions.gen_random_uuid(),v_business,v_batch,p_device,v_profile,
    v_branch,p_name||'-payment',3,'sale_payments',v_payment,'insert',
    jsonb_build_object('id',v_payment,'business_id',v_business,
      'branch_id',v_branch,'sale_id',v_sale,'amount',p_total::numeric/100,
      'amount_cents',p_total,'payment_method','cash','status','completed',
      'paid_at',now()),p_name||'-payment-key','pending');
  insert into w5b_cases values(p_name,v_batch,v_sale,v_item,v_payment,
    v_item_mutation);
  return v_batch;
end;
$$;

select set_config('request.jwt.claim.sub',
  'b5000000-0000-0000-0000-000000000101',true);
select ok(not has_function_privilege('anon',
  'public.process_sync_batch(uuid,text)','EXECUTE'),
  'anon cannot execute POS batch');
select ok(not has_function_privilege('authenticated',
  'private.apply_sync_exact_weight_sale_item_mutation(uuid)','EXECUTE'),
  'private W5B applier is not a direct client RPC');
select is(public.weighted_sale_sync_capability(),
  'exact_weight_sale_v1','W5B capability is versioned');

select pg_temp.seed_w5b('main',
  'b5000000-0000-0000-0000-000000000201',735,1200000,1764000);
select is((select mutation_count from public.sync_batches
  where id=(select batch_id from w5b_cases where name='main')),3,
  'W5B complete registration retains declared three mutations');
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='main'),'apply_pos')->>'status'),'completed',
  '735g weighted sale completes');
select is((select quantity_on_hand from public.product_stock_balances
  where product_id='b5000000-0000-0000-0000-000000000201'),12265,
  'stock is 12265 grams');
select is((select cost_basis_cents from public.product_stock_balances
  where product_id='b5000000-0000-0000-0000-000000000201'),2151092::bigint,
  'cost basis is 2151092 cents');
select is((select cogs_cents from public.sale_items where id =
  (select item_id from w5b_cases where name='main')),128908::bigint,
  'authoritative W2B COGS is 128908 cents');
select is((select line_total_cents from public.sale_items where id =
  (select item_id from w5b_cases where name='main')),1764000::bigint,
  'historical W2A line total is 1764000 cents');
select ok((select sale_mode_snapshot='weight' and quantity=735
  and price_basis_quantity_snapshot=500 and price_cents_snapshot=1200000
  from public.sale_items where id=(select item_id from w5b_cases
    where name='main')),'mode/gram/basis/price snapshots persist');
select ok((select quantity_change=-735 and cost_effect_cents=-128908
  from public.inventory_movements where idempotency_key='sale:'||
    (select sale_id::text from w5b_cases where name='main')||':item:'||
    (select item_id::text from w5b_cases where name='main')),
  'existing ledger records gram and negative exact cost effect');
select ok((select jsonb_array_length(metadata->'weighted_sale_ack')=1
  from public.sync_batches where id=(select batch_id from w5b_cases
    where name='main')),'batch stores authoritative ACK');
select ok((select response->>'status'='completed' and
  response->'weighted_sale_ack'->0->>'cogs_cents'='128908'
  from (select public.process_sync_batch((select batch_id from w5b_cases
    where name='main'),'apply_pos') response) x),'retry returns same ACK');
select ok((select response->>'status'='completed' and
  response->'weighted_sale_ack'->0->>'stock_quantity_grams'='12265'
  from (select public.process_sync_batch((select batch_id from w5b_cases
    where name='main'),'apply_pos') response) x),'third apply is idempotent');
select is((select count(*) from public.inventory_movements where source_id=
  (select sale_id from w5b_cases where name='main')),1::bigint,
  'three applies create one inventory movement');
select is((select count(*) from public.sale_payments where sale_id=
  (select sale_id from w5b_cases where name='main')),1::bigint,
  'three applies create one payment');

select is((select known_net_sales from
  public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day')),
  17640::numeric,'W5D report includes exact WEIGHT revenue');
select is((select known_cogs from
  public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day')),
  1289.08::numeric,'W5D report uses authoritative WEIGHT COGS cents');

select pg_temp.seed_w5b('rounding',
  'b5000000-0000-0000-0000-000000000202',3,1200100,7201);
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='rounding'),'apply_pos')->>'status'),'completed',
  '3g at 12001 COP/500g completes');
select is((select line_total_cents from public.sale_items where id=
  (select item_id from w5b_cases where name='rounding')),7201::bigint,
  'W2A rounding is exact');
select is((select cogs_cents from public.sale_items where id=
  (select item_id from w5b_cases where name='rounding')),0::bigint,
  'known zero cost is not NULL');

select pg_temp.seed_w5b('unknown',
  'b5000000-0000-0000-0000-000000000203',25,1200000,60000);
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='unknown'),'apply_pos')->>'status'),'completed',
  'unknown cost partial issue completes');
select ok((select cogs_cents is null from public.sale_items where id=
  (select item_id from w5b_cases where name='unknown')),
  'unknown cost COGS remains NULL');
select ok((select cost_effect_cents is null from public.inventory_movements
  where source_id=(select sale_id from w5b_cases where name='unknown')),
  'unknown cost movement effect remains NULL');
select ok((select unknown_cost_item_count=1
  and unknown_cost_net_sales=600
  and not cost_coverage_complete
  from public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day')),
  'W5D excludes only unknown WEIGHT cost, not known zero');
select is((select known_cogs from
  public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day')),
  1289.08::numeric,'known zero WEIGHT cost contributes zero COGS');
select pg_temp.seed_w5b('deplete',
  'b5000000-0000-0000-0000-000000000202',97,1200000,232800);
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='deplete'),'apply_pos')->>'status'),'completed',
  'full depletion completes');
select is((select cost_basis_cents from public.product_stock_balances
  where product_id='b5000000-0000-0000-0000-000000000202'),0::bigint,
  'full depletion leaves zero cost basis');

select pg_temp.seed_w5b('bad-total',
  'b5000000-0000-0000-0000-000000000201',5,1200000,11999);
select public.process_sync_batch((select batch_id from w5b_cases
  where name='bad-total'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='bad-total')),
  'error','line total mismatch rejected');
select pg_temp.seed_w5b('bad-basis',
  'b5000000-0000-0000-0000-000000000201',5,1200000,12000,1000);
select public.process_sync_batch((select batch_id from w5b_cases
  where name='bad-basis'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='bad-basis')),
  'error','basis other than 500 rejected');
select pg_temp.seed_w5b('bad-mode',
  'b5000000-0000-0000-0000-000000000201',5,1200000,12000,1,'unit');
select public.process_sync_batch((select batch_id from w5b_cases
  where name='bad-mode'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='bad-mode')),
  'error','product/item mode mismatch rejected');
select pg_temp.seed_w5b('zero',
  'b5000000-0000-0000-0000-000000000201',0,1200000,0);
select public.process_sync_batch((select batch_id from w5b_cases
  where name='zero'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='zero')),
  'error','zero grams rejected');
select pg_temp.seed_w5b('discount',
  'b5000000-0000-0000-0000-000000000201',5,1200000,11900,500, 'weight',1);
select public.process_sync_batch((select batch_id from w5b_cases
  where name='discount'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='discount')),
  'error','weighted discount is rejected');
select ok(strpos(lower(pg_get_functiondef(
  'private.prepare_inventory_movement_before_insert()'::regprocedure)),
  'for update')>0,'existing stock trigger locks balance FOR UPDATE');
select ok(not has_function_privilege('authenticated',
  'private.apply_costed_inventory_issue(bigint,bigint,bigint)','EXECUTE'),
  'W2B helper remains private');

select pg_temp.seed_w5b('device-b',
  'b5000000-0000-0000-0000-000000000201',500,1200000,1200000,
  500,'weight',0,0,
  'b5000000-0000-0000-0000-000000000071',
  'b5000000-0000-0000-0000-000000000052');
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='device-b'),'apply_pos')->>'status'),'completed',
  'second device sale completes');
select is((select quantity_on_hand from public.product_stock_balances
  where product_id='b5000000-0000-0000-0000-000000000201'),11765,
  'two devices serialize grams against current remote balance');
select is((select cogs_cents from public.sale_items where id=
  (select item_id from w5b_cases where name='device-b')),
  private.calculate_basis_amount_cents(2151092,500,12265),
  'second device COGS uses first device resulting cost pool');

select pg_temp.seed_w5b('price-change',
  'b5000000-0000-0000-0000-000000000201',500,1200000,1200000);
insert into public.sync_batches (id,business_id,app_device_id,profile_id,
  branch_id,client_batch_id,direction,status,mutation_count,metadata)
values ('b5000000-0000-0000-0000-000000000301',
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000051',
  'b5000000-0000-0000-0000-000000000101',
  'b5000000-0000-0000-0000-000000000011',
  'w5b-price-update','upload','pending',1,'{"domain":"catalog"}');
insert into public.sync_mutations (id,business_id,sync_batch_id,
  app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
  entity_table,entity_id,operation,payload,idempotency_key,status)
values ('b5000000-0000-0000-0000-000000000302',
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000301',
  'b5000000-0000-0000-0000-000000000051',
  'b5000000-0000-0000-0000-000000000101',
  'b5000000-0000-0000-0000-000000000011',
  'w5b-price-update',1,'products',
  'b5000000-0000-0000-0000-000000000201','update',
  '{"sale_mode":"weight","sale_price":"13000.00","sale_price_cents":1300000}',
  'w5b-price-update-key','pending');
select is(private.apply_sync_catalog_mutation(
  'b5000000-0000-0000-0000-000000000302')->>'status','applied',
  'W3 versioned catalog path updates current price');
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='price-change'),'apply_pos')->>'status'),'completed',
  'sale applies after product price changes');
select is((select line_total_cents from public.sale_items where id=
  (select item_id from w5b_cases where name='price-change')),1200000::bigint,
  'historical price snapshot survives product price change');

select pg_temp.seed_w5b('insufficient',
  'b5000000-0000-0000-0000-000000000201',20000,1200000,48000000);
create temporary table w5b_failures(name text primary key,reason text);
do $$ begin
  perform public.process_sync_batch((select batch_id from w5b_cases
    where name='insufficient'),'apply_pos');
  insert into w5b_failures values('insufficient','unexpected_success');
exception when others then
  insert into w5b_failures values('insufficient',sqlerrm);
end $$;
select is((select reason from w5b_failures where name='insufficient'),
  'weighted_sale_inventory_not_complete',
  'insufficient stock aborts the entire weighted batch');
select ok(not exists (select 1 from public.sale_items where id=
  (select item_id from w5b_cases where name='insufficient'))
  and not exists (select 1 from public.sales where id=
  (select sale_id from w5b_cases where name='insufficient')),
  'insufficient stock leaves no sale/item without inventory');

select pg_temp.seed_w5b('closed',
  'b5000000-0000-0000-0000-000000000201',5,1200000,12000,
  500,'weight',0,0,'b5000000-0000-0000-0000-000000000072');
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='closed'),'apply_pos')->>'status'),'partial',
  'closed cash session retains stale rejection semantics');
select ok(not exists (select 1 from public.sales where id=
  (select sale_id from w5b_cases where name='closed')),
  'stale weighted sale is not materialized');

create temporary table w5d_before_mixed as
  select known_net_sales,known_cogs,unknown_cost_item_count
  from public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day');
select pg_temp.seed_w5b('mixed',
  'b5000000-0000-0000-0000-000000000201',5,1200000,12000);
update public.sync_batches set mutation_count=4,
  metadata=jsonb_set(metadata,'{item_count}','2'::jsonb)
  where id=(select batch_id from w5b_cases where name='mixed');
update public.sync_mutations set payload=payload || jsonb_build_object(
  'total',2120,'subtotal',2120,'total_cents',212000,
  'metadata',jsonb_build_object('monetary_contract_version',
    'exact_weight_sale_v1','total_cents',212000))
  where sync_batch_id=(select batch_id from w5b_cases where name='mixed')
    and entity_table='sales';
update public.sync_mutations set payload=payload || jsonb_build_object(
  'amount',2120,'amount_cents',212000)
  where sync_batch_id=(select batch_id from w5b_cases where name='mixed')
    and entity_table='sale_payments';
insert into public.sync_mutations (id,business_id,sync_batch_id,
  app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
  entity_table,entity_id,operation,payload,idempotency_key,status)
select extensions.gen_random_uuid(),
  'b5000000-0000-0000-0000-000000000001',c.batch_id,
  'b5000000-0000-0000-0000-000000000051',
  'b5000000-0000-0000-0000-000000000101',
  'b5000000-0000-0000-0000-000000000011','mixed-unit',4,
  'sale_items',extensions.gen_random_uuid(),'insert',
  jsonb_build_object('sale_id',c.sale_id,
    'product_id','b5000000-0000-0000-0000-000000000204',
    'quantity',2,'unit_price',1000,'subtotal',2000,'total',2000,
    'discount_amount',0,'tax_amount',0,
    'monetary_contract_version','exact_weight_sale_v1',
    'sale_mode_snapshot','unit','price_basis_quantity_snapshot',1,
    'price_cents_snapshot',100000,'line_total_cents',200000),
  'mixed-unit-key','pending' from w5b_cases c where c.name='mixed';
select is((public.process_sync_batch((select batch_id from w5b_cases
  where name='mixed'),'apply_pos')->>'status'),'completed',
  'mixed UNIT and WEIGHT sale completes in one batch');
select is((select count(*) from public.sale_items where sale_id=
  (select sale_id from w5b_cases where name='mixed')),2::bigint,
  'mixed sale persists both line modes');
select is((select count(*) from public.inventory_movements where source_id=
  (select sale_id from w5b_cases where name='mixed')),2::bigint,
  'mixed sale uses same inventory ledger');
select ok((select report.known_net_sales - previous.known_net_sales =
    coalesce(sum(item.subtotal-item.discount_amount)
      filter (where item.sale_mode_snapshot='weight'
        or item.unit_cost_snapshot is not null),0)
  from public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day') report
  cross join w5d_before_mixed previous
  join public.sale_items item on item.sale_id=
    (select sale_id from w5b_cases where name='mixed')
  group by report.known_net_sales,previous.known_net_sales),
  'W5D mixed sale revenue uses known UNIT and WEIGHT lines');
select ok((select report.known_cogs - previous.known_cogs =
    coalesce(sum(case when item.sale_mode_snapshot='weight'
      then item.cogs_cents::numeric/100
      else item.quantity*item.unit_cost_snapshot end),0)
  from public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day') report
  cross join w5d_before_mixed previous
  join public.sale_items item on item.sale_id=
    (select sale_id from w5b_cases where name='mixed')
  group by report.known_cogs,previous.known_cogs),
  'W5D mixed sale cost combines UNIT snapshot and WEIGHT COGS cents');
select ok((select report.unknown_cost_item_count -
    previous.unknown_cost_item_count = count(*) filter (
      where item.sale_mode_snapshot='unit'
        and item.unit_cost_snapshot is null)
  from public.get_branch_profitability_report_summary(
    'b5000000-0000-0000-0000-000000000001',
    'b5000000-0000-0000-0000-000000000011',
    now()-interval '1 day',now()+interval '1 day') report
  cross join w5d_before_mixed previous
  join public.sale_items item on item.sale_id=
    (select sale_id from w5b_cases where name='mixed')
  group by report.unknown_cost_item_count,
    previous.unknown_cost_item_count),
  'W5D mixed sale unknown-cost count preserves UNIT NULL semantics');

select pg_temp.seed_w5b('legacy-marker',
  'b5000000-0000-0000-0000-000000000201',5,1200000,12000);
update public.sync_mutations set payload=payload - 'monetary_contract_version'
  where id=(select item_mutation_id from w5b_cases where name='legacy-marker');
select public.process_sync_batch((select batch_id from w5b_cases
  where name='legacy-marker'),'apply_pos');
select is((select status from public.sync_mutations where id=
  (select item_mutation_id from w5b_cases where name='legacy-marker')),
  'error','old client without version cannot create weighted item');

-- S1A registration enforces byte-equivalent payload for a repeated key.
do $$
declare v public.sync_mutations%rowtype;
begin
  select * into v from public.sync_mutations where id=
    (select item_mutation_id from w5b_cases where name='main');
  perform public.register_pending_sync_mutation(jsonb_build_object(
    'id',v.id,'business_id',v.business_id,'app_device_id',v.app_device_id,
    'profile_id',v.profile_id,'branch_id',v.branch_id,
    'sync_batch_id',v.sync_batch_id,'client_mutation_id',v.client_mutation_id,
    'client_sequence',v.client_sequence,'entity_table',v.entity_table,
    'entity_id',v.entity_id,'operation',v.operation,
    'payload',v.payload || jsonb_build_object('quantity',736),
    'idempotency_key',v.idempotency_key));
  insert into w5b_failures values('payload-conflict','unexpected_success');
exception when others then
  insert into w5b_failures values('payload-conflict',sqlerrm);
end $$;
select is((select reason from w5b_failures where name='payload-conflict'),
  'sync_mutation_idempotency_conflict',
  'same key with different grams is explicitly rejected');

-- W5B intentional stale WEIGHT reconciliation.
select pg_temp.seed_w5b(
  'stale-main',
  'b5000000-0000-0000-0000-000000000205',
  735,
  1200000,
  1764000,
  500,
  'weight',
  0,
  0,
  'b5000000-0000-0000-0000-000000000072'
);

select is(
  (
    public.process_sync_batch(
      (select batch_id from w5b_cases where name='stale-main'),
      'apply_pos'
    ) ->> 'status'
  ),
  'partial',
  'stale WEIGHT sale is first rejected by the closed cash session'
);

create temporary table w5b_stale_result(response jsonb);

insert into w5b_stale_result(response)
select public.reconcile_rejected_sale_to_open_cash_session(
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000011',
  'b5000000-0000-0000-0000-000000000051',
  (select sale_id from w5b_cases where name='stale-main'),
  (
    select conflict.id
    from public.sync_conflicts conflict
    where conflict.entity_table = 'sales'
      and conflict.entity_id =
        (select sale_id from w5b_cases where name='stale-main')
      and conflict.status = 'open'
      and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
      and conflict.metadata ->> 'reason' = 'closed'
    limit 1
  ),
  'b5000000-0000-0000-0000-000000000071',
  'b5000000-0000-0000-0000-000000000301',
  'w5b-stale-main-reconciliation',
  'W5B weighted stale reconciliation test',
  'not_included_in_destination_opening'
);

select ok(
  (
    select
      response ->> 'status' = 'completed'
      and jsonb_array_length(
        response -> 'weighted_sale_reconciliation_results'
      ) = 1
      and response
            -> 'weighted_sale_reconciliation_results'
            -> 0
            ->> 'cogs_cents' = '128908'
      and response
            -> 'weighted_sale_reconciliation_results'
            -> 0
            ->> 'stock_quantity_grams' = '12265'
      and response
            -> 'weighted_sale_reconciliation_results'
            -> 0
            ->> 'cost_basis_cents' = '2151092'
    from w5b_stale_result
  ),
  'stale WEIGHT reconciliation returns authoritative W2B result'
);

select is(
  (
    select quantity_on_hand
    from public.product_stock_balances
    where product_id =
      'b5000000-0000-0000-0000-000000000205'
  ),
  12265,
  'stale WEIGHT reconciliation deducts grams exactly once'
);

select is(
  (
    select cost_basis_cents
    from public.product_stock_balances
    where product_id =
      'b5000000-0000-0000-0000-000000000205'
  ),
  2151092::bigint,
  'stale WEIGHT reconciliation updates authoritative cost basis'
);

select is(
  (
    select cogs_cents
    from public.sale_items
    where id =
      (select item_id from w5b_cases where name='stale-main')
  ),
  128908::bigint,
  'stale WEIGHT reconciliation stores authoritative COGS'
);
-- W5B intentional stale WEIGHT reconciliation with unknown cost.  Aquí
select pg_temp.seed_w5b(
  'stale-unknown',
  'b5000000-0000-0000-0000-000000000206',
  25,
  1200000,
  60000,
  500,
  'weight',
  0,
  0,
  'b5000000-0000-0000-0000-000000000072'
);

select is(
  (
    public.process_sync_batch(
      (select batch_id from w5b_cases where name='stale-unknown'),
      'apply_pos'
    ) ->> 'status'
  ),
  'partial',
  'stale WEIGHT unknown-cost sale is rejected by closed cash session first'
);

create temporary table w5b_stale_unknown_result(response jsonb);

insert into w5b_stale_unknown_result(response)
select public.reconcile_rejected_sale_to_open_cash_session(
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000011',
  'b5000000-0000-0000-0000-000000000051',
  (select sale_id from w5b_cases where name='stale-unknown'),
  (
    select conflict.id
    from public.sync_conflicts conflict
    where conflict.entity_table = 'sales'
      and conflict.entity_id =
        (select sale_id from w5b_cases where name='stale-unknown')
      and conflict.status = 'open'
      and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
      and conflict.metadata ->> 'reason' = 'closed'
    limit 1
  ),
  'b5000000-0000-0000-0000-000000000071',
  'b5000000-0000-0000-0000-000000000302',
  'w5b-stale-unknown-reconciliation',
  'W5B weighted stale unknown cost test',
  'not_included_in_destination_opening'
);

select ok(
  (
    select
      response ->> 'status' = 'completed'
      and jsonb_array_length(
        response -> 'weighted_sale_reconciliation_results'
      ) = 1
      and jsonb_typeof(
        response
          -> 'weighted_sale_reconciliation_results'
          -> 0
          -> 'cogs_cents'
      ) = 'null'
      and jsonb_typeof(
        response
          -> 'weighted_sale_reconciliation_results'
          -> 0
          -> 'cost_effect_cents'
      ) = 'null'
    from w5b_stale_unknown_result
  ),
  'stale WEIGHT unknown cost remains NULL in authoritative result'
);

select ok(
  (
    select
      quantity_on_hand = 75
      and cost_basis_cents is null
    from public.product_stock_balances
    where product_id =
      'b5000000-0000-0000-0000-000000000206'
  ),
  'stale WEIGHT unknown cost deducts grams while preserving NULL cost basis'
);

select ok(
  (
    select
      item.cogs_cents is null
      and movement.quantity_change = -25
      and movement.unit_cost is null
      and movement.cost_effect_cents is null
    from public.sale_items item
    join public.inventory_movements movement
      on movement.business_id = item.business_id
     and movement.idempotency_key =
       'sale:' || item.sale_id::text || ':item:' || item.id::text
    where item.id =
      (select item_id from w5b_cases where name='stale-unknown')
  ),
  'stale WEIGHT unknown cost never invents COGS or movement cost'
);

-- W5B intentional stale mixed UNIT + WEIGHT reconciliation.
select pg_temp.seed_w5b(
  'stale-mixed',
  'b5000000-0000-0000-0000-000000000207',
  5,
  1200000,
  12000,
  500,
  'weight',
  0,
  0,
  'b5000000-0000-0000-0000-000000000072'
);

update public.sync_batches
set mutation_count = 4,
    metadata = jsonb_set(metadata, '{item_count}', '2'::jsonb)
where id = (
  select batch_id from w5b_cases where name='stale-mixed'
);

update public.sync_mutations
set payload = payload || jsonb_build_object(
  'total', 2120,
  'subtotal', 2120,
  'total_cents', 212000,
  'metadata', jsonb_build_object(
    'monetary_contract_version', 'exact_weight_sale_v1',
    'total_cents', 212000
  )
)
where sync_batch_id = (
  select batch_id from w5b_cases where name='stale-mixed'
)
and entity_table = 'sales';

update public.sync_mutations
set payload = payload || jsonb_build_object(
  'amount', 2120,
  'amount_cents', 212000
)
where sync_batch_id = (
  select batch_id from w5b_cases where name='stale-mixed'
)
and entity_table = 'sale_payments';

insert into public.sync_mutations (
  id,
  business_id,
  sync_batch_id,
  app_device_id,
  profile_id,
  branch_id,
  client_mutation_id,
  client_sequence,
  entity_table,
  entity_id,
  operation,
  payload,
  idempotency_key,
  status
)
select
  extensions.gen_random_uuid(),
  'b5000000-0000-0000-0000-000000000001',
  c.batch_id,
  'b5000000-0000-0000-0000-000000000051',
  'b5000000-0000-0000-0000-000000000101',
  'b5000000-0000-0000-0000-000000000011',
  'stale-mixed-unit',
  4,
  'sale_items',
  extensions.gen_random_uuid(),
  'insert',
  jsonb_build_object(
    'sale_id', c.sale_id,
    'product_id', 'b5000000-0000-0000-0000-000000000208',
    'quantity', 2,
    'unit_price', 1000,
    'unit_cost_snapshot', 500,
    'subtotal', 2000,
    'total', 2000,
    'discount_amount', 0,
    'tax_amount', 0,
    'monetary_contract_version', 'exact_weight_sale_v1',
    'sale_mode_snapshot', 'unit',
    'price_basis_quantity_snapshot', 1,
    'price_cents_snapshot', 100000,
    'line_total_cents', 200000
  ),
  'stale-mixed-unit-key',
  'pending'
from w5b_cases c
where c.name='stale-mixed';

select is(
  (
    public.process_sync_batch(
      (select batch_id from w5b_cases where name='stale-mixed'),
      'apply_pos'
    ) ->> 'status'
  ),
  'partial',
  'stale mixed UNIT/WEIGHT sale is rejected by closed cash session first'
);

create temporary table w5b_stale_mixed_result(response jsonb);

insert into w5b_stale_mixed_result(response)
select public.reconcile_rejected_sale_to_open_cash_session(
  'b5000000-0000-0000-0000-000000000001',
  'b5000000-0000-0000-0000-000000000011',
  'b5000000-0000-0000-0000-000000000051',
  (select sale_id from w5b_cases where name='stale-mixed'),
  (
    select conflict.id
    from public.sync_conflicts conflict
    where conflict.entity_table = 'sales'
      and conflict.entity_id =
        (select sale_id from w5b_cases where name='stale-mixed')
      and conflict.status = 'open'
      and conflict.metadata ->> 'rule' = 'sale_cash_session_invalid'
      and conflict.metadata ->> 'reason' = 'closed'
    limit 1
  ),
  'b5000000-0000-0000-0000-000000000071',
  'b5000000-0000-0000-0000-000000000303',
  'w5b-stale-mixed-reconciliation',
  'W5B mixed stale reconciliation test',
  'not_included_in_destination_opening'
);

select ok(
  (
    select
      response ->> 'status' = 'completed'
      and jsonb_array_length(
        response -> 'weighted_sale_reconciliation_results'
      ) = 1
      and response
            -> 'weighted_sale_reconciliation_results'
            -> 0
            ->> 'cogs_cents' = '500'
    from w5b_stale_mixed_result
  ),
  'stale mixed reconciliation returns authoritative WEIGHT result'
);

select is(
  (
    select count(*)
    from public.sale_items
    where sale_id =
      (select sale_id from w5b_cases where name='stale-mixed')
  ),
  2::bigint,
  'stale mixed reconciliation persists UNIT and WEIGHT items'
);

select is(
  (
    select count(*)
    from public.inventory_movements
    where source_type = 'sale'
      and source_id =
        (select sale_id from w5b_cases where name='stale-mixed')
  ),
  2::bigint,
  'stale mixed reconciliation creates exactly two inventory movements'
);

select ok(
  (
    select
      quantity_on_hand = 995
      and cost_basis_cents = 99500
    from public.product_stock_balances
    where product_id =
      'b5000000-0000-0000-0000-000000000207'
  )
  and (
    select cogs_cents = 500
    from public.sale_items
    where sale_id =
      (select sale_id from w5b_cases where name='stale-mixed')
      and product_id =
        'b5000000-0000-0000-0000-000000000207'
  ),
  'stale mixed WEIGHT line applies authoritative W2B exactly'
);

select ok(
  (
    select quantity_on_hand = 8
    from public.product_stock_balances
    where product_id =
      'b5000000-0000-0000-0000-000000000208'
  )
  and (
    select unit_cost = 500
    from public.inventory_movements
    where source_type = 'sale'
      and source_id =
        (select sale_id from w5b_cases where name='stale-mixed')
      and product_id =
        'b5000000-0000-0000-0000-000000000208'
  ),
  'stale mixed UNIT line retains existing UNIT inventory semantics'
);

select ok(
  (
    public.reconcile_rejected_sale_to_open_cash_session(
      'b5000000-0000-0000-0000-000000000001',
      'b5000000-0000-0000-0000-000000000011',
      'b5000000-0000-0000-0000-000000000051',
      (select sale_id from w5b_cases where name='stale-mixed'),
      (
        select sync_conflict_id
        from public.sale_reconciliations
        where id =
          'b5000000-0000-0000-0000-000000000303'
      ),
      'b5000000-0000-0000-0000-000000000071',
      'b5000000-0000-0000-0000-000000000303',
      'w5b-stale-mixed-reconciliation',
      'W5B mixed stale reconciliation test',
      'not_included_in_destination_opening'
    ) ->> 'idempotent'
  )::boolean
  and (
    select count(*) = 2
    from public.inventory_movements
    where source_type = 'sale'
      and source_id =
        (select sale_id from w5b_cases where name='stale-mixed')
  ),
  'stale mixed retry is idempotent and creates no duplicate movements'
);

select ok(
  (
    select
      movement.quantity_change = -735
      and movement.unit_cost is null
      and movement.cost_effect_cents = -128908
    from public.inventory_movements movement
    where movement.idempotency_key =
      'sale:'
      || (
        select sale_id::text
        from w5b_cases
        where name='stale-main'
      )
      || ':item:'
      || (
        select item_id::text
        from w5b_cases
        where name='stale-main'
      )
  ),
  'stale WEIGHT ledger uses grams, NULL unit cost and exact cost effect'
);

select ok(
  (
    public.reconcile_rejected_sale_to_open_cash_session(
      'b5000000-0000-0000-0000-000000000001',
      'b5000000-0000-0000-0000-000000000011',
      'b5000000-0000-0000-0000-000000000051',
      (select sale_id from w5b_cases where name='stale-main'),
      (
        select sync_conflict_id
        from public.sale_reconciliations
        where id =
          'b5000000-0000-0000-0000-000000000301'
      ),
      'b5000000-0000-0000-0000-000000000071',
      'b5000000-0000-0000-0000-000000000301',
      'w5b-stale-main-reconciliation',
      'W5B weighted stale reconciliation test',
      'not_included_in_destination_opening'
    ) ->> 'idempotent'
  )::boolean,
  'identical stale WEIGHT reconciliation retry is idempotent'
);

select is(
  (
    select count(*)
    from public.inventory_movements
    where source_type = 'sale'
      and source_id =
        (select sale_id from w5b_cases where name='stale-main')
  ),
  1::bigint,
  'stale WEIGHT retry does not duplicate inventory movement'
);

-- W5B stale proof/security hardening.

select ok(
  not has_function_privilege(
    'authenticated',
    'public.reconcile_rejected_sale_to_open_cash_session_pre_w5b(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,text)',
    'EXECUTE'
  ),
  'authenticated cannot bypass W5B through the historical stale RPC'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'private.validate_stale_weight_sale_reconciliation(uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'private.hydrate_stale_weight_sale_item()',
    'EXECUTE'
  ),
  'W5B stale proof helpers are not directly executable by clients'
);

select throws_ok(
  $$
    insert into public.sale_items (
      id,
      business_id,
      sale_id,
      product_id,
      product_name_snapshot,
      quantity,
      unit_price,
      unit_cost_snapshot,
      subtotal,
      discount_amount,
      tax_amount,
      total,
      sale_mode_snapshot,
      price_basis_quantity_snapshot,
      price_cents_snapshot,
      line_total_cents,
      created_by,
      updated_by,
      sync_status,
      idempotency_key,
      metadata
    )
    values (
      'b5000000-0000-0000-0000-000000000901',
      'b5000000-0000-0000-0000-000000000001',
      (select sale_id from w5b_cases where name='main'),
      'b5000000-0000-0000-0000-000000000201',
      'Forged stale item',
      5,
      12000,
      null,
      120,
      0,
      0,
      120,
      'weight',
      500,
      1200000,
      12000,
      'b5000000-0000-0000-0000-000000000101',
      'b5000000-0000-0000-0000-000000000101',
      'synced',
      'forged-stale-item-key',
      jsonb_build_object(
        'monetary_contract_version',
        'exact_weight_sale_v1',
        'w5b_stale_reconciliation_id',
        'b5000000-0000-0000-0000-000000000999',
        'original_sync_mutation_id',
        'b5000000-0000-0000-0000-000000000998'
      )
    )
  $$,
  'P0001',
  'invalid_weighted_stale_reconciliation_contract',
  'forged stale WEIGHT markers cannot authorize a sale item'
);

select set_config('request.jwt.claim.sub','',true);
do $$ begin
  perform public.process_sync_batch((select batch_id from w5b_cases
    where name='main'),'apply_pos');
  insert into w5b_failures values('anonymous','unexpected_success');
exception when others then
  insert into w5b_failures values('anonymous',sqlerrm);
end $$;
select is((select reason from w5b_failures where name='anonymous'),
  'Authentication required','missing auth rejected before batch dispatch');
select * from finish();
rollback;
