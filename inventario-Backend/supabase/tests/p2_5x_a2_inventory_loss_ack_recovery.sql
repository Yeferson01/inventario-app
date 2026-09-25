-- Local-only fixtures; all changes roll back. No ledger/balance changes by ACK.
begin;
select plan(28);

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values (md5('a2-user')::uuid, 'authenticated', 'authenticated', 'a2@example.test', '{}', '{}');
insert into public.profiles (id, full_name, role, status)
values (md5('a2-user')::uuid, 'A2', 'owner', 'active') on conflict (id) do nothing;
insert into public.businesses (id, name, status)
select md5('a2-business-' || n)::uuid, 'A2 ' || n, 'active' from generate_series(1,2) n;
insert into public.branches (id, business_id, name, status)
select md5('a2-branch-' || n)::uuid, md5('a2-business-' || case when n=3 then 2 else 1 end)::uuid,
       'A2 branch ' || n, 'active' from generate_series(1,3) n;
insert into public.business_members (id, business_id, profile_id, role_id, status)
values (md5('a2-member')::uuid, md5('a2-business-1')::uuid, md5('a2-user')::uuid,
        (select id from public.roles where business_id is null and name='owner' and deleted_at is null limit 1), 'active');
insert into public.app_devices (id, business_id, profile_id, branch_id, installation_id, status)
values (md5('a2-device')::uuid, md5('a2-business-1')::uuid, md5('a2-user')::uuid,
        md5('a2-branch-1')::uuid, 'a2-installation', 'active');
insert into public.products (id, business_id, name, sale_price)
select md5('a2-product-' || n)::uuid, md5('a2-business-1')::uuid, 'A2 product ' || n, 10
from generate_series(1,2) n;
insert into public.product_stock_balances (business_id, branch_id, product_id, quantity_on_hand, average_cost)
values (md5('a2-business-1')::uuid, md5('a2-branch-1')::uuid, md5('a2-product-1')::uuid, 10, 2);
select set_config('request.jwt.claim.sub', md5('a2-user')::uuid::text, true);
insert into public.inventory_movements (id, business_id, branch_id, product_id, movement_type,
 quantity_change, created_by, source_type, idempotency_key, sync_status, occurred_at)
values (md5('a2-loss')::uuid, md5('a2-business-1')::uuid, md5('a2-branch-1')::uuid,
 md5('a2-product-1')::uuid, 'loss', -2, md5('a2-user')::uuid, 'loss', 'a2-loss-key', 'synced', now());

create function pg_temp.a2_operation(p_patch jsonb default '{}') returns jsonb language sql as $$
 select jsonb_build_object('movement_id', md5('a2-loss')::uuid, 'idempotency_key', 'a2-loss-key',
   'source_type', 'loss', 'product_id', md5('a2-product-1')::uuid, 'quantity_change', -2) || p_patch;
$$;
create function pg_temp.a2_ack(p_patch jsonb default '{}') returns jsonb language sql as $$
 select public.lookup_inventory_movement_acknowledgements(md5('a2-business-1')::uuid,
   md5('a2-branch-1')::uuid, md5('a2-device')::uuid, jsonb_build_array(pg_temp.a2_operation(p_patch)))
   -> 'acknowledgements' -> 0;
$$;

set local role authenticated;
select is(pg_temp.a2_ack()->>'status', 'applied', '1 loss applied by exact ID + key');
select is(pg_temp.a2_ack()->>'remote_movement_id', md5('a2-loss')::uuid::text, '2 canonical movement ID');
select is(pg_temp.a2_ack()->>'remote_idempotency_key', 'a2-loss-key', '3 canonical key');
select is(pg_temp.a2_ack(jsonb_build_object('product_id',md5('a2-product-2')::uuid))->>'status', 'ambiguous', '4 wrong product not acknowledged');
select is(pg_temp.a2_ack('{"quantity_change":-3}')->>'status', 'ambiguous', '5 wrong delta not acknowledged');
select is(pg_temp.a2_ack('{"idempotency_key":"wrong"}')->>'status', 'ambiguous', '6 ID alone insufficient');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('missing')::uuid))->>'status', 'ambiguous', '7 key alone insufficient');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('missing')::uuid,'idempotency_key','missing'))->>'status', 'not_found', '8 absent ledger is not applied');
select throws_ok($q$select pg_temp.a2_ack('{"source_type":"unknown"}')$q$, 'P0001', 'Unsupported acknowledgement source_type: unknown', '9 unknown source rejected');
select throws_ok($q$select pg_temp.a2_ack('{"quantity_change":2}')$q$, 'P0001', 'loss quantity_change must be negative', '10 loss must be negative');
-- Authorization failure must not expose tenant evidence; exact helper messages may evolve.
select throws_ok($q$select public.lookup_inventory_movement_acknowledgements(md5('a2-business-2')::uuid,md5('a2-branch-3')::uuid,md5('a2-device')::uuid,'[]')$q$, 'P0001', null, '11 unauthorized business denied');
select throws_ok($q$select public.lookup_inventory_movement_acknowledgements(md5('a2-business-1')::uuid,md5('a2-branch-2')::uuid,md5('a2-device')::uuid,'[]')$q$, 'P0001', null, '12 wrong device branch denied');
reset role;

insert into public.sync_batches (id,business_id,branch_id,app_device_id,profile_id,client_batch_id,direction,status,mutation_count)
values (md5('a2-batch')::uuid,md5('a2-business-1')::uuid,md5('a2-branch-1')::uuid,
 md5('a2-device')::uuid,md5('a2-user')::uuid,'a2-batch','upload','pending',2);
insert into public.sync_mutations (id,business_id,branch_id,app_device_id,profile_id,sync_batch_id,
 client_mutation_id,client_sequence,entity_table,entity_id,operation,payload,status,idempotency_key,error_message)
select md5('a2-mutation-'||n)::uuid,md5('a2-business-1')::uuid,md5('a2-branch-1')::uuid,
 md5('a2-device')::uuid,md5('a2-user')::uuid,md5('a2-batch')::uuid,'a2-mutation-'||n,n,
 'inventory_movements',md5('a2-rejected-'||n)::uuid,'insert',jsonb_build_object(
 'id',md5('a2-rejected-'||n)::uuid,'idempotency_key','a2-rejected-key-'||n,
 'business_id',md5('a2-business-1')::uuid,'branch_id',md5('a2-branch-1')::uuid,
 'product_id',md5('a2-product-1')::uuid,'source_type','loss','movement_type','loss','quantity_change',-2),
 case when n=1 then 'conflict' else 'pending' end,'a2-rejected-key-'||n,
 case when n=1 then 'Rejected loss fixture' else null end
from generate_series(1,2) n;
update public.sync_batches set status='partial',conflict_count=1 where id=md5('a2-batch')::uuid;
set local role authenticated;
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-rejected-1')::uuid,'idempotency_key','a2-rejected-key-1'))->>'status', 'rejected', '13 exact terminal evidence rejected');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-rejected-2')::uuid,'idempotency_key','a2-rejected-key-2'))->>'status', 'not_found', '14 pending transport is not applied');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-rejected-1')::uuid,'idempotency_key','wrong'))->>'status', 'not_found', '15 rejection not borrowed by ID alone');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-rejected-1')::uuid,'idempotency_key','a2-rejected-key-1','quantity_change',-3))->>'status', 'not_found', '16 rejection payload must match');
select is(pg_temp.a2_ack()->>'status', 'applied', '17 ledger remains authority independent of transport');
reset role;
select is((select quantity_on_hand from public.product_stock_balances where product_id=md5('a2-product-1')::uuid),8,'18 repeated read-only ACK never changes stock');
select ok(not has_function_privilege('anon','public.lookup_inventory_movement_acknowledgements(uuid,uuid,uuid,jsonb)','execute'), '19 anon denied');
select ok(has_function_privilege('authenticated','public.lookup_inventory_movement_acknowledgements(uuid,uuid,uuid,jsonb)','execute'), '20 authenticated execute preserved');
update public.app_devices set status='blocked' where id=md5('a2-device')::uuid;
set local role authenticated;
select throws_ok('select pg_temp.a2_ack()', 'P0001', null, '21 blocked device denied');
reset role;
update public.app_devices set status='active' where id=md5('a2-device')::uuid;
update public.business_members set status='suspended' where id=md5('a2-member')::uuid;
set local role authenticated;
select throws_ok('select pg_temp.a2_ack()', 'P0001', null, '22 revoked membership denied');
reset role;
update public.business_members set status='active' where id=md5('a2-member')::uuid;
-- Authorized alternate branch still must not expose the original ledger or keys.
update public.app_devices set branch_id=md5('a2-branch-2')::uuid where id=md5('a2-device')::uuid;
set local role authenticated;
select is(public.lookup_inventory_movement_acknowledgements(md5('a2-business-1')::uuid,
 md5('a2-branch-2')::uuid,md5('a2-device')::uuid,jsonb_build_array(pg_temp.a2_operation()))
 ->'acknowledgements'->0->>'status','not_found','23 cross-branch evidence not exposed');
reset role;
update public.app_devices set branch_id=md5('a2-branch-1')::uuid where id=md5('a2-device')::uuid;
set local role authenticated;
select throws_ok($q$select pg_temp.a2_ack('{"quantity_change":0}')$q$, 'P0001', 'movement_id, idempotency_key, source_type, product_id and non-zero quantity_change are required','24 zero rejected');
select is(pg_temp.a2_ack('{"source_type":"manual_adjustment"}')->>'status','ambiguous','25 source type mismatch never applied');
reset role;
insert into public.inventory_movements (id,business_id,branch_id,product_id,movement_type,
 quantity_change,created_by,source_type,idempotency_key,sync_status,occurred_at)
select md5('a2-extra-'||n)::uuid,md5('a2-business-1')::uuid,md5('a2-branch-1')::uuid,
 md5('a2-product-1')::uuid,'loss',-2,md5('a2-user')::uuid,'loss',
 case when n=1 then null else 'a2-second-key' end,'synced',now()
from generate_series(1,2) n;
set local role authenticated;
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-extra-1')::uuid,'idempotency_key','no-remote-key'))->>'status',
 'ambiguous','26 missing remote key cannot prove applied');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-extra-2')::uuid))->>'status',
 'ambiguous','27 repeated loss ID and another loss key cannot be combined');
select is(pg_temp.a2_ack(jsonb_build_object('movement_id',md5('a2-extra-2')::uuid,'idempotency_key','a2-second-key'))->>'status',
 'applied','28 second equivalent loss recognized only by its own identity');
reset role;
select * from finish();
rollback;
