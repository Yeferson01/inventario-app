-- Focused validation for the atomic cross-branch inventory transfer MVP.
-- All fixtures and transfer effects are rolled back.

begin;

select plan(6);

create temporary table inventory_transfer_results (
  result_key text primary key,
  payload jsonb not null
) on commit drop;

grant select, insert on inventory_transfer_results to authenticated;

create function pg_temp.transfer_rejected_without_effects(
  p_sql text,
  p_expected_message text,
  p_transfer_id uuid,
  p_source_balance integer,
  p_destination_balance integer
)
returns boolean
language plpgsql
as $$
begin
  begin
    execute p_sql;
    return false;
  exception when others then
    if sqlstate <> 'P0001' or sqlerrm <> p_expected_message then
      return false;
    end if;
  end;

  return not exists (
    select 1
    from public.inventory_transfers transfer
    where transfer.id = p_transfer_id
  )
  and not exists (
    select 1
    from public.inventory_movements movement
    where movement.source_type = 'transfer'
      and movement.source_id = p_transfer_id
  )
  and (
    select balance.quantity_on_hand
    from public.product_stock_balances balance
    where balance.business_id = 'fa300000-0000-0000-0000-000000000001'
      and balance.branch_id = 'fa300000-0000-0000-0000-000000000011'
      and balance.product_id = 'fa300000-0000-0000-0000-000000000021'
  ) = p_source_balance
  and (
    select balance.quantity_on_hand
    from public.product_stock_balances balance
    where balance.business_id = 'fa300000-0000-0000-0000-000000000001'
      and balance.branch_id = 'fa300000-0000-0000-0000-000000000012'
      and balance.product_id = 'fa300000-0000-0000-0000-000000000021'
  ) = p_destination_balance;
end;
$$;

create function pg_temp.transfer_rejected_exactly(
  p_sql text,
  p_expected_message text
)
returns boolean
language plpgsql
as $$
begin
  execute p_sql;
  return false;
exception when others then
  return sqlstate = 'P0001' and sqlerrm = p_expected_message;
end;
$$;

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  (
    'fa300000-0000-0000-0000-000000000101',
    'authenticated', 'authenticated', 'transfer-owner@example.test', '', now(),
    '{}', '{}', now(), now()
  ),
  (
    'fa300000-0000-0000-0000-000000000102',
    'authenticated', 'authenticated', 'transfer-limited@example.test', '', now(),
    '{}', '{}', now(), now()
  );

insert into public.profiles (id, full_name, status)
values
  ('fa300000-0000-0000-0000-000000000101', 'Transfer Owner', 'active'),
  ('fa300000-0000-0000-0000-000000000102', 'Transfer Limited', 'active');

insert into public.businesses (id, name, status)
values
  ('fa300000-0000-0000-0000-000000000001', 'Transfer Business A', 'active'),
  ('fa300000-0000-0000-0000-000000000002', 'Transfer Business B', 'active');

insert into public.branches (id, business_id, name, status)
values
  (
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000001',
    'Transfer Origin',
    'active'
  ),
  (
    'fa300000-0000-0000-0000-000000000012',
    'fa300000-0000-0000-0000-000000000001',
    'Transfer Destination',
    'active'
  ),
  (
    'fa300000-0000-0000-0000-000000000013',
    'fa300000-0000-0000-0000-000000000002',
    'Foreign Branch',
    'active'
  );

insert into public.roles (
  id, business_id, name, description, is_system_role
)
values (
  'fa300000-0000-0000-0000-000000000031',
  'fa300000-0000-0000-0000-000000000001',
  'transfer_without_capability',
  'Fixture without inventory.transfer.',
  false
);

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, accepted_at
)
values
  (
    'fa300000-0000-0000-0000-000000000041',
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000101',
    null,
    (
      select role.id
      from public.roles role
      where role.business_id is null
        and role.name = 'owner'
        and role.deleted_at is null
      limit 1
    ),
    'active',
    now()
  ),
  (
    'fa300000-0000-0000-0000-000000000042',
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000102',
    null,
    'fa300000-0000-0000-0000-000000000031',
    'active',
    now()
  );

insert into public.products (
  id, business_id, name, sale_price, stock_quantity, minimum_stock, status
)
values (
  'fa300000-0000-0000-0000-000000000021',
  'fa300000-0000-0000-0000-000000000001',
  'Transfer Product',
  25,
  0,
  0,
  'active'
);

insert into public.product_stock_balances (
  id, business_id, branch_id, product_id,
  quantity_on_hand, quantity_reserved, average_cost
)
values
  (
    'fa300000-0000-0000-0000-000000000051',
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000021',
    10,
    1,
    12.50
  ),
  (
    'fa300000-0000-0000-0000-000000000052',
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000012',
    'fa300000-0000-0000-0000-000000000021',
    0,
    0,
    null
  );

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa300000-0000-0000-0000-000000000101',
  true
);
insert into inventory_transfer_results (result_key, payload)
values (
  'first',
  public.create_and_complete_inventory_transfer(
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000012',
    'fa300000-0000-0000-0000-000000000021',
    3,
    'fa300000-0000-0000-0000-000000000061',
    'fa300000-0000-0000-0000-000000000062',
    'inventory-transfer-test:valid',
    'Focused transfer fixture'
  )
);
reset role;

select ok(
  (
    select result.payload ->> 'status' = 'completed'
      and (result.payload ->> 'quantity')::integer = 3
      and not (result.payload ->> 'idempotent_replay')::boolean
    from inventory_transfer_results result
    where result.result_key = 'first'
  )
  and (
    select balance.quantity_on_hand = 7
      and balance.quantity_reserved = 1
      and balance.quantity_available = 6
    from public.product_stock_balances balance
    where balance.id = 'fa300000-0000-0000-0000-000000000051'
  )
  and (
    select balance.quantity_on_hand = 3
      and balance.quantity_available = 3
    from public.product_stock_balances balance
    where balance.id = 'fa300000-0000-0000-0000-000000000052'
  ),
  '1. valid transfer atomically decrements origin and increments destination'
);

select ok(
  (
    select count(*) = 2
      and count(*) filter (where quantity_change = -3) = 1
      and count(*) filter (where quantity_change = 3) = 1
      and count(*) filter (where unit_cost = 12.50) = 2
      and count(distinct source_id) = 1
    from public.inventory_movements movement
    where movement.source_type = 'transfer'
      and movement.source_id = 'fa300000-0000-0000-0000-000000000061'
  )
  and (
    select item.unit_cost_snapshot = 12.50
    from public.inventory_transfer_items item
    where item.id = 'fa300000-0000-0000-0000-000000000062'
  )
  and (
    select balance.average_cost = 12.50
    from public.product_stock_balances balance
    where balance.id = 'fa300000-0000-0000-0000-000000000052'
  ),
  '2. correlated ledger legs preserve the origin cost basis and inventory value'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa300000-0000-0000-0000-000000000101',
  true
);
insert into inventory_transfer_results (result_key, payload)
values (
  'retry',
  public.create_and_complete_inventory_transfer(
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000012',
    'fa300000-0000-0000-0000-000000000021',
    3,
    'fa300000-0000-0000-0000-000000000061',
    'fa300000-0000-0000-0000-000000000062',
    'inventory-transfer-test:valid',
    'Focused transfer fixture'
  )
);
reset role;

select ok(
  (
    select (result.payload ->> 'idempotent_replay')::boolean
    from inventory_transfer_results result
    where result.result_key = 'retry'
  )
  and (
    select count(*) = 1
    from public.inventory_transfers transfer
    where transfer.id = 'fa300000-0000-0000-0000-000000000061'
  )
  and (
    select count(*) = 2
    from public.inventory_movements movement
    where movement.source_type = 'transfer'
      and movement.source_id = 'fa300000-0000-0000-0000-000000000061'
  ),
  '3. retry with the stable identity reuses one transfer and two movements'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  'fa300000-0000-0000-0000-000000000101',
  true
);
select ok(
  pg_temp.transfer_rejected_without_effects(
    $$select public.create_and_complete_inventory_transfer(
      'fa300000-0000-0000-0000-000000000001',
      'fa300000-0000-0000-0000-000000000011',
      'fa300000-0000-0000-0000-000000000012',
      'fa300000-0000-0000-0000-000000000021',
      99,
      'fa300000-0000-0000-0000-000000000071',
      'fa300000-0000-0000-0000-000000000072',
      'inventory-transfer-test:insufficient',
      null
    )$$,
    'Insufficient available stock for transfer. Available: 6, requested: 99',
    'fa300000-0000-0000-0000-000000000071',
    7,
    3
  ),
  '4. insufficient available stock leaves no partial transfer, movement, or balance change'
);

select throws_ok(
  $$select public.create_and_complete_inventory_transfer(
    'fa300000-0000-0000-0000-000000000001',
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000011',
    'fa300000-0000-0000-0000-000000000021',
    1,
    'fa300000-0000-0000-0000-000000000081',
    'fa300000-0000-0000-0000-000000000082',
    'inventory-transfer-test:same-branch',
    null
  )$$,
  'P0001',
  'Origin and destination branches must be different',
  '5. the same branch cannot be both origin and destination'
);
reset role;

select ok(
  pg_temp.transfer_rejected_exactly(
    $$select public.create_and_complete_inventory_transfer(
      'fa300000-0000-0000-0000-000000000001',
      'fa300000-0000-0000-0000-000000000011',
      'fa300000-0000-0000-0000-000000000013',
      'fa300000-0000-0000-0000-000000000021',
      1,
      'fa300000-0000-0000-0000-000000000091',
      'fa300000-0000-0000-0000-000000000092',
      'inventory-transfer-test:foreign',
      null
    )$$,
    'Destination branch is not active in the requested business'
  )
  and (
    set_config(
      'request.jwt.claim.sub',
      'fa300000-0000-0000-0000-000000000102',
      true
    ) is not null
  )
  and pg_temp.transfer_rejected_exactly(
    $$select public.create_and_complete_inventory_transfer(
      'fa300000-0000-0000-0000-000000000001',
      'fa300000-0000-0000-0000-000000000011',
      'fa300000-0000-0000-0000-000000000012',
      'fa300000-0000-0000-0000-000000000021',
      1,
      'fa300000-0000-0000-0000-000000000093',
      'fa300000-0000-0000-0000-000000000094',
      'inventory-transfer-test:no-permission',
      null
    )$$,
    'Insufficient inventory.transfer permission for origin branch'
  )
  and not has_table_privilege(
    'authenticated',
    'public.inventory_transfers',
    'INSERT'
  )
  and not has_function_privilege(
    'authenticated',
    'public.complete_inventory_transfer(uuid)',
    'EXECUTE'
  ),
  '6. tenant, capability, and direct-write guards close authorization bypasses'
);

select * from finish();

rollback;
