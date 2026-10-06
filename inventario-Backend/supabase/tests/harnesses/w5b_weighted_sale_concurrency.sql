-- Two independent authenticated connections apply WEIGHT sales to one balance.
-- Disposable Supabase LOCAL only, after db reset. The DSN is supplied by
-- psql, never stored. The immutable inventory ledger forbids cleanup; reset
-- the local database before another run.
\set ON_ERROR_STOP on
\if :{?w5b_dblink_dsn}
\else
  \echo 'ERROR: required psql variable w5b_dblink_dsn was not provided'
  do $$ begin raise exception 'w5b_dblink_dsn required'; end $$;
\endif

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;
set search_path = extensions, public, pg_catalog;

-- Refuse fixture reuse rather than silently mixing with non-harness records.
do $$ begin
  if exists (select 1 from public.businesses where id =
    'b5c00000-0000-0000-0000-000000000001')
    or exists (select 1 from auth.users where id =
    'b5c00000-0000-0000-0000-000000000101') then
    raise exception 'W5B concurrency fixture already exists; use local reset';
  end if;
end $$;

insert into auth.users (id,aud,role,email,encrypted_password,
  email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('b5c00000-0000-0000-0000-000000000101','authenticated',
  'authenticated','w5b-concurrency@example.test','',now(),'{}','{}',now(),now());
insert into public.profiles (id,full_name,role,status)
values ('b5c00000-0000-0000-0000-000000000101',
  'W5B Concurrent','owner','active');
insert into public.businesses (id,name,status)
values ('b5c00000-0000-0000-0000-000000000001',
  'W5B Concurrent','active');
insert into public.branches (id,business_id,name,status)
values ('b5c00000-0000-0000-0000-000000000011',
  'b5c00000-0000-0000-0000-000000000001','Primary','active');
insert into public.business_members (id,business_id,profile_id,branch_id,
  role_id,status)
select 'b5c00000-0000-0000-0000-000000000041',
  'b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000101',null,id,'active'
from public.roles where business_id is null and name='owner'
  and deleted_at is null limit 1;
insert into public.app_devices (id,business_id,profile_id,branch_id,
  installation_id,status)
values ('b5c00000-0000-0000-0000-000000000051',
  'b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000101',
  'b5c00000-0000-0000-0000-000000000011',
  'w5b-concurrent','active');
insert into public.cash_registers (id,business_id,branch_id,name,status)
values ('b5c00000-0000-0000-0000-000000000061',
  'b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000011','Register','active');
insert into public.cash_sessions (id,business_id,branch_id,cash_register_id,
  opened_by,opening_amount,status,opened_at)
values ('b5c00000-0000-0000-0000-000000000071',
  'b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000011',
  'b5c00000-0000-0000-0000-000000000061',
  'b5c00000-0000-0000-0000-000000000101',0,'open',now());
insert into public.products (id,business_id,name,sale_price,purchase_price,
  sale_mode)
values ('b5c00000-0000-0000-0000-000000000201',
  'b5c00000-0000-0000-0000-000000000001','Weight',12000,1000,'weight');
insert into public.product_stock_balances (business_id,branch_id,product_id,
  quantity_on_hand,quantity_reserved,cost_basis_cents)
values ('b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000011',
  'b5c00000-0000-0000-0000-000000000201',13000,0,2280000);

create temporary table w5b_concurrent_cases (
  n integer primary key, batch_id uuid, sale_id uuid, item_id uuid,
  payment_id uuid, quantity integer, total_cents bigint
);
insert into w5b_concurrent_cases values
  (1,'b5c00000-0000-0000-0000-000000000301',
   'b5c00000-0000-0000-0000-000000000401',
   'b5c00000-0000-0000-0000-000000000501',
   'b5c00000-0000-0000-0000-000000000601',735,1764000),
  (2,'b5c00000-0000-0000-0000-000000000302',
   'b5c00000-0000-0000-0000-000000000402',
   'b5c00000-0000-0000-0000-000000000502',
   'b5c00000-0000-0000-0000-000000000602',500,1200000),
  (3,'b5c00000-0000-0000-0000-000000000303',
   'b5c00000-0000-0000-0000-000000000403',
   'b5c00000-0000-0000-0000-000000000503',
   'b5c00000-0000-0000-0000-000000000603',250,600000);
insert into public.sync_batches (id,business_id,app_device_id,profile_id,
  branch_id,client_batch_id,direction,status,mutation_count,metadata)
select c.batch_id,'b5c00000-0000-0000-0000-000000000001',
  'b5c00000-0000-0000-0000-000000000051',
  'b5c00000-0000-0000-0000-000000000101',
  'b5c00000-0000-0000-0000-000000000011',
  'w5b-concurrent-'||c.n,'upload','pending',3,
  '{"domain":"pos","monetary_contract_version":"exact_weight_sale_v1","item_count":1,"payment_count":1}'::jsonb
from w5b_concurrent_cases c;
insert into public.sync_mutations (id,business_id,sync_batch_id,
  app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
  entity_table,entity_id,operation,payload,idempotency_key,status)
select ('b5c00000-0000-0000-0000-'||lpad((700+c.n)::text,12,'0'))::uuid,
  'b5c00000-0000-0000-0000-000000000001',c.batch_id,
  'b5c00000-0000-0000-0000-000000000051',
  'b5c00000-0000-0000-0000-000000000101',
  'b5c00000-0000-0000-0000-000000000011',
  'w5b-concurrent-'||c.n||'-sale',1,'sales',c.sale_id,'insert',
  jsonb_build_object('id',c.sale_id,
    'business_id','b5c00000-0000-0000-0000-000000000001',
    'branch_id','b5c00000-0000-0000-0000-000000000011',
    'cash_register_id','b5c00000-0000-0000-0000-000000000061',
    'cash_session_id','b5c00000-0000-0000-0000-000000000071',
    'subtotal',c.total_cents::numeric/100,'discount_total',0,'tax_total',0,
    'total',c.total_cents::numeric/100,'total_cents',c.total_cents,
    'status','completed','monetary_contract_version','exact_weight_sale_v1',
    'metadata',jsonb_build_object('monetary_contract_version',
      'exact_weight_sale_v1','total_cents',c.total_cents)),
  'w5b-concurrent-'||c.n||'-sale-key','pending'
from w5b_concurrent_cases c;
insert into public.sync_mutations (id,business_id,sync_batch_id,
  app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
  entity_table,entity_id,operation,payload,idempotency_key,status)
select ('b5c00000-0000-0000-0000-'||lpad((710+c.n)::text,12,'0'))::uuid,
  'b5c00000-0000-0000-0000-000000000001',c.batch_id,
  'b5c00000-0000-0000-0000-000000000051',
  'b5c00000-0000-0000-0000-000000000101',
  'b5c00000-0000-0000-0000-000000000011',
  'w5b-concurrent-'||c.n||'-item',2,'sale_items',c.item_id,'insert',
  jsonb_build_object('id',c.item_id,
    'business_id','b5c00000-0000-0000-0000-000000000001',
    'branch_id','b5c00000-0000-0000-0000-000000000011',
    'sale_id',c.sale_id,
    'product_id','b5c00000-0000-0000-0000-000000000201',
    'quantity',c.quantity,'unit_price',12000,'subtotal',
    c.total_cents::numeric/100,'discount_amount',0,'tax_amount',0,
    'total',c.total_cents::numeric/100,
    'monetary_contract_version','exact_weight_sale_v1',
    'sale_mode_snapshot','weight','price_basis_quantity_snapshot',500,
    'price_cents_snapshot',1200000,'line_total_cents',c.total_cents),
  'w5b-concurrent-'||c.n||'-item-key','pending'
from w5b_concurrent_cases c;
insert into public.sync_mutations (id,business_id,sync_batch_id,
  app_device_id,profile_id,branch_id,client_mutation_id,client_sequence,
  entity_table,entity_id,operation,payload,idempotency_key,status)
select ('b5c00000-0000-0000-0000-'||lpad((720+c.n)::text,12,'0'))::uuid,
  'b5c00000-0000-0000-0000-000000000001',c.batch_id,
  'b5c00000-0000-0000-0000-000000000051',
  'b5c00000-0000-0000-0000-000000000101',
  'b5c00000-0000-0000-0000-000000000011',
  'w5b-concurrent-'||c.n||'-payment',3,'sale_payments',c.payment_id,'insert',
  jsonb_build_object('id',c.payment_id,
    'business_id','b5c00000-0000-0000-0000-000000000001',
    'branch_id','b5c00000-0000-0000-0000-000000000011',
    'sale_id',c.sale_id,'amount',c.total_cents::numeric/100,
    'amount_cents',c.total_cents,'payment_method','cash',
    'status','completed','paid_at',now()),
  'w5b-concurrent-'||c.n||'-payment-key','pending'
from w5b_concurrent_cases c;

select extensions.dblink_connect('w5b_a', :'w5b_dblink_dsn');
select extensions.dblink_connect('w5b_b', :'w5b_dblink_dsn');
\unset w5b_dblink_dsn
select extensions.dblink_exec('w5b_a',
  'set role authenticated; set request.jwt.claim.sub = ''b5c00000-0000-0000-0000-000000000101''');
select extensions.dblink_exec('w5b_b',
  'set role authenticated; set request.jwt.claim.sub = ''b5c00000-0000-0000-0000-000000000101''');

-- Duplicate concurrent execution of the SAME batch.
select extensions.dblink_send_query('w5b_a', $query$
  select public.process_sync_batch(
    'b5c00000-0000-0000-0000-000000000301','apply_pos')::text
$query$);
select extensions.dblink_send_query('w5b_b', $query$
  select public.process_sync_batch(
    'b5c00000-0000-0000-0000-000000000301','apply_pos')::text
$query$);
create temporary table w5b_concurrent_results (phase text,caller text,result jsonb);
insert into w5b_concurrent_results select 'same','a',value::jsonb
from extensions.dblink_get_result('w5b_a') as response(value text);
insert into w5b_concurrent_results select 'same','b',value::jsonb
from extensions.dblink_get_result('w5b_b') as response(value text);
select * from extensions.dblink_get_result('w5b_a') as response(value text);
select * from extensions.dblink_get_result('w5b_b') as response(value text);

-- Two still-pending batches race on the SAME product and costed stock row.
select extensions.dblink_send_query('w5b_a', $query$
  select public.process_sync_batch(
    'b5c00000-0000-0000-0000-000000000302','apply_pos')::text
$query$);
select extensions.dblink_send_query('w5b_b', $query$
  select public.process_sync_batch(
    'b5c00000-0000-0000-0000-000000000303','apply_pos')::text
$query$);
insert into w5b_concurrent_results select 'distinct','a',value::jsonb
from extensions.dblink_get_result('w5b_a') as response(value text);
insert into w5b_concurrent_results select 'distinct','b',value::jsonb
from extensions.dblink_get_result('w5b_b') as response(value text);
select extensions.dblink_disconnect('w5b_a');
select extensions.dblink_disconnect('w5b_b');

select plan(4);
select ok((select count(*)=2 and bool_and(result->>'status'='completed')
  from w5b_concurrent_results where phase='same'),
  'concurrent same-batch calls both complete');
select is((select count(*) from public.inventory_movements where
  source_id='b5c00000-0000-0000-0000-000000000401'),1::bigint,
  'same-batch race creates one movement');
select ok((select count(*)=2 and bool_and(result->>'status'='completed')
  from w5b_concurrent_results where phase='distinct')
  and (select quantity_on_hand=11515
    from public.product_stock_balances where product_id=
      'b5c00000-0000-0000-0000-000000000201'),
  'two competing batches apply one 500g and one 250g debit');
select ok((select count(*)=3 and sum(cogs_cents)=2280000-b.cost_basis_cents
  from public.sale_items i cross join public.product_stock_balances b
  where i.business_id='b5c00000-0000-0000-0000-000000000001'
    and b.product_id='b5c00000-0000-0000-0000-000000000201'
  group by b.cost_basis_cents)
  and (select count(*)=3 from public.inventory_movements
    where business_id='b5c00000-0000-0000-0000-000000000001'
      and source_type='sale'),
  'three sales consume cost basis exactly once with three movements');
select * from finish();
