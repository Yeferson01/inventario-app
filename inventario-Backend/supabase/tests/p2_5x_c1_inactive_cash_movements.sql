-- C1: no production write surface; fixture-only inserts are rolled back.
begin;
select plan(42);
insert into auth.users (id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data)
values ('cc100000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'c1@example.test', '', '{}', '{}');
insert into public.profiles(id, full_name, status) values ('cc100000-0000-0000-0000-000000000001', 'C1', 'active');
insert into public.businesses(id,name,status) values
('cc100000-0000-0000-0000-000000000010','C1','active'),
('cc100000-0000-0000-0000-000000000020','Other','active');
insert into public.branches(id,business_id,name,status) values
('cc100000-0000-0000-0000-000000000011','cc100000-0000-0000-0000-000000000010','Main','active'),
('cc100000-0000-0000-0000-000000000021','cc100000-0000-0000-0000-000000000020','Other','active');
insert into public.cash_registers(id,business_id,branch_id,name,status) values
('cc100000-0000-0000-0000-000000000012','cc100000-0000-0000-0000-000000000010','cc100000-0000-0000-0000-000000000011','Main','active'),
('cc100000-0000-0000-0000-000000000022','cc100000-0000-0000-0000-000000000020','cc100000-0000-0000-0000-000000000021','Other','active');
insert into public.cash_sessions(id,business_id,branch_id,cash_register_id,opened_by,status,closed_at) values
('cc100000-0000-0000-0000-000000000013','cc100000-0000-0000-0000-000000000010','cc100000-0000-0000-0000-000000000011','cc100000-0000-0000-0000-000000000012','cc100000-0000-0000-0000-000000000001','closed',now());
insert into public.business_members(business_id,branch_id,profile_id,role_id,status)
select 'cc100000-0000-0000-0000-000000000010','cc100000-0000-0000-0000-000000000011','cc100000-0000-0000-0000-000000000001',id,'active'
from public.roles where name='owner' and business_id is null and is_system_role and deleted_at is null;

create function pg_temp.cm_insert(p jsonb default '{}') returns void language sql as $$
insert into public.cash_movements select (jsonb_populate_record(null::public.cash_movements,
jsonb_build_object(
'id',extensions.gen_random_uuid(), 'business_id','cc100000-0000-0000-0000-000000000010',
'branch_id','cc100000-0000-0000-0000-000000000011','cash_register_id','cc100000-0000-0000-0000-000000000012',
'cash_session_id','cc100000-0000-0000-0000-000000000013','direction','outflow','category','utilities',
'amount',123.45,'currency','COP','source_type','manual','occurred_at',now(),
'created_by','cc100000-0000-0000-0000-000000000001','created_at',now(),'updated_at',now(),
'idempotency_key',extensions.gen_random_uuid(),'metadata','{}'::jsonb) || p)).*;
$$;

select has_table('public','cash_movements','table exists');
select ok((select relrowsecurity from pg_class where oid='public.cash_movements'::regclass),'RLS enabled');
select ok(not has_table_privilege('anon','public.cash_movements','SELECT'),'anon cannot read');
select ok(not has_table_privilege('authenticated','public.cash_movements','INSERT'),'authenticated cannot insert, even with capability');
select ok(not has_table_privilege('authenticated','public.cash_movements','UPDATE'),'authenticated cannot update');
select ok(not has_table_privilege('authenticated','public.cash_movements','DELETE'),'authenticated cannot delete');
select lives_ok($$select pg_temp.cm_insert('{"id":"cc100000-0000-0000-0000-000000000030","idempotency_key":"fixture"}')$$,'structural outflow, including historical closed session');
select lives_ok($$select pg_temp.cm_insert('{"direction":"inflow","category":"owner_contribution"}')$$,'structural inflow');
select throws_ok($$select pg_temp.cm_insert('{"amount":0}')$$,'23514',null,'reject zero');
select throws_ok($$select pg_temp.cm_insert('{"amount":-1}')$$,'23514',null,'reject negative');
select throws_ok($$select pg_temp.cm_insert('{"amount":1.001}')$$,'23514',null,'reject fractional cent');
select throws_ok($$select pg_temp.cm_insert('{"direction":"sideways"}')$$,'23514',null,'reject direction');
select throws_ok($$select pg_temp.cm_insert('{"category":"arbitrary"}')$$,'23514',null,'reject category');
select throws_ok($$select pg_temp.cm_insert('{"currency":" "}')$$,'23514',null,'reject currency');
select throws_ok($$select pg_temp.cm_insert('{"business_id":"cc100000-0000-0000-0000-000000000020"}')$$,'23514',null,'reject cross business');
select throws_ok($$select pg_temp.cm_insert('{"branch_id":"cc100000-0000-0000-0000-000000000021"}')$$,'23514',null,'reject cross branch');
select throws_ok($$select pg_temp.cm_insert('{"cash_register_id":"cc100000-0000-0000-0000-000000000022"}')$$,'23514',null,'reject cross register');
select throws_ok($$select pg_temp.cm_insert('{"cash_session_id":"cc100000-0000-0000-0000-000000000099"}')$$,'23514',null,'reject unknown session');
select throws_ok($$select pg_temp.cm_insert('{"created_by":"cc100000-0000-0000-0000-000000000099"}')$$,'23503',null,'reject actor FK');
select throws_ok($$select pg_temp.cm_insert('{"idempotency_key":"fixture"}')$$,'23505',null,'reject idempotency duplicate');
select throws_ok($$select pg_temp.cm_insert('{"source_type":"purchase"}')$$,'23514',null,'reject purchase requires source');
select throws_ok($$select pg_temp.cm_insert('{"reversed_movement_id":"cc100000-0000-0000-0000-000000000099"}')$$,'23514',null,'reject unknown reversal');
select throws_ok($$select pg_temp.cm_insert('{"metadata":[]}')$$,'23514',null,'reject metadata must be object');

select lives_ok($$select pg_temp.cm_insert('{"direction":"inflow","category":"other","reversed_movement_id":"cc100000-0000-0000-0000-000000000030"}')$$,'reversal reference');
select lives_ok($$select pg_temp.cm_insert('{"source_type":"purchase","source_id":"cc100000-0000-0000-0000-000000000050","category":"supplier_purchase"}')$$,'future purchase representation');
select ok(exists(select 1 from public.cash_movements where source_type='manual' and source_id is null),'manual source nullable');
select throws_ok($$update public.cash_movements set amount=2$$,'23514','cash_movements is append-only','functional update blocked even as postgres');
select throws_ok($$delete from public.cash_movements$$,'23514','cash_movements is append-only','delete blocked even as postgres');
select is((select count(*) from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.business_id is null and r.is_system_role and r.name='owner' and r.deleted_at is null and p.key in ('cash.receive','cash.disburse')),2::bigint,'owner defaults');
select is((select count(*) from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.business_id is null and r.is_system_role and r.name='admin' and r.deleted_at is null and p.key in ('cash.receive','cash.disburse')),2::bigint,'admin defaults');
select is((select count(*) from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.business_id is null and r.is_system_role and r.name='cashier' and r.deleted_at is null and p.key in ('cash.receive','cash.disburse')),0::bigint,'cashier defaults');
select is((select count(*) from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.business_id is null and r.is_system_role and r.name='warehouse' and r.deleted_at is null and p.key in ('cash.receive','cash.disburse')),0::bigint,'warehouse defaults');
select is((select count(*) from public.roles r join public.role_permissions rp on rp.role_id=r.id join public.permissions p on p.id=rp.permission_id where r.business_id is null and r.is_system_role and r.name='technician' and r.deleted_at is null and p.key in ('cash.receive','cash.disburse')),0::bigint,'technician defaults');

set local role authenticated;
select set_config('request.jwt.claim.sub','cc100000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.cash_movements),4::bigint,'cash.read authorized scope');
select throws_ok($$select pg_temp.cm_insert()$$,'42501',null,'client INSERT denied');
select set_config('request.jwt.claim.sub','cc100000-0000-0000-0000-000000000099',true);
select is((select count(*) from public.cash_movements),0::bigint,'no membership sees no data');
reset role;
update public.business_members set deleted_at=now() where profile_id='cc100000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub','cc100000-0000-0000-0000-000000000001',true);
select is((select count(*) from public.cash_movements),0::bigint,'revoked membership sees no data');
reset role;
select ok(not exists(select 1 from pg_policies where schemaname='public' and tablename='cash_movements' and cmd in ('INSERT','UPDATE','DELETE','ALL')),'no write policy');
select ok(not has_table_privilege('service_role','public.cash_movements','DELETE'),'service role no delete grant');
select ok(not has_table_privilege('service_role','public.cash_movements','UPDATE'),'service role no update grant');
select ok(position($guard$if v_entity not in ('cash_registers', 'cash_sessions') then$guard$ in pg_get_functiondef('private.apply_sync_cash_mutation(uuid)'::regprocedure)) > 0,'cash dispatcher allowlist remains registers/sessions only');
select ok(position('cash_movements' in pg_get_functiondef('public.close_cash_session_authoritatively(uuid,uuid,uuid,uuid,numeric,text)'::regprocedure))>0,'C2 expected cash includes ordinary cash movements');
select * from finish();
rollback;
