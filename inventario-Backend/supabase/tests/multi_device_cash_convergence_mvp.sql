begin;

select plan(5);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('ca500000-0000-0000-0000-000000000101', 'authenticated', 'authenticated', 'cash-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca500000-0000-0000-0000-000000000102', 'authenticated', 'authenticated', 'cash-b@example.test', '', now(), '{}', '{}', now(), now()),
  ('ca500000-0000-0000-0000-000000000103', 'authenticated', 'authenticated', 'sales-only@example.test', '', now(), '{}', '{}', now(), now());

insert into public.profiles (id, full_name, role, status)
values
  ('ca500000-0000-0000-0000-000000000101', 'Cash A', 'cashier', 'active'),
  ('ca500000-0000-0000-0000-000000000102', 'Cash B', 'cashier', 'active'),
  ('ca500000-0000-0000-0000-000000000103', 'Sales only', 'cashier', 'active');

insert into public.businesses (id, name, status)
values ('ca500000-0000-0000-0000-000000000001', 'Cash convergence', 'active');

insert into public.branches (id, business_id, name, status)
values
  ('ca500000-0000-0000-0000-000000000011', 'ca500000-0000-0000-0000-000000000001', 'Principal', 'active'),
  ('ca500000-0000-0000-0000-000000000012', 'ca500000-0000-0000-0000-000000000001', 'Secondary', 'active');

insert into public.roles (id, business_id, name, description, is_system_role)
values (
  'ca500000-0000-0000-0000-000000000031',
  'ca500000-0000-0000-0000-000000000001',
  'cash-mvp-sales-only',
  'Sales-only denial fixture',
  false
);

insert into public.role_permissions (role_id, permission_id)
select 'ca500000-0000-0000-0000-000000000031', permission.id
from public.permissions permission
where permission.key = 'sales.create';

insert into public.business_members (
  id, business_id, profile_id, branch_id, role_id, status, deleted_at
)
values
  (
    'ca500000-0000-0000-0000-000000000041',
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000101',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active', null
  ),
  (
    'ca500000-0000-0000-0000-000000000042',
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000102',
    null,
    (select id from public.roles where business_id is null and name = 'owner' and deleted_at is null limit 1),
    'active', null
  ),
  (
    'ca500000-0000-0000-0000-000000000043',
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000103',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000031',
    'active', null
  );

insert into public.cash_registers (id, business_id, branch_id, name, status)
values
  ('ca500000-0000-0000-0000-000000000051', 'ca500000-0000-0000-0000-000000000001', 'ca500000-0000-0000-0000-000000000011', 'Principal', 'active'),
  ('ca500000-0000-0000-0000-000000000052', 'ca500000-0000-0000-0000-000000000001', 'ca500000-0000-0000-0000-000000000012', 'Secondary', 'active');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca500000-0000-0000-0000-000000000101', true);

select is(
  public.open_or_reuse_cash_session(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000051',
    50000
  )->>'status',
  'open',
  '1. first device opens the authoritative session'
);

select isnt(
  public.open_or_reuse_cash_session(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000012',
    'ca500000-0000-0000-0000-000000000052',
    1000
  )->>'cash_session_id',
  public.open_or_reuse_cash_session(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000051',
    99999
  )->>'cash_session_id',
  '2. different branches/registers keep independent sessions'
);

select set_config('request.jwt.claim.sub', 'ca500000-0000-0000-0000-000000000102', true);

select ok(
  (public.open_or_reuse_cash_session(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000051',
    0
  )->>'reused_open_session')::boolean
  and (
    select count(*) = 1
    from public.cash_sessions session
    where session.cash_register_id = 'ca500000-0000-0000-0000-000000000051'
      and session.status = 'open'
      and session.deleted_at is null
  ),
  '3. second device reuses S1 and cannot create S2'
);

reset role;

insert into public.sales (
  id, business_id, branch_id, user_id, cash_session_id, total, status
)
select
  'ca500000-0000-0000-0000-000000000061',
  'ca500000-0000-0000-0000-000000000001',
  'ca500000-0000-0000-0000-000000000011',
  'ca500000-0000-0000-0000-000000000101',
  session.id,
  10000,
  'completed'
from public.cash_sessions session
where session.cash_register_id = 'ca500000-0000-0000-0000-000000000051'
  and session.status = 'open';

insert into public.sales (
  id, business_id, branch_id, user_id, cash_session_id, total, status
)
select
  'ca500000-0000-0000-0000-000000000062',
  'ca500000-0000-0000-0000-000000000001',
  'ca500000-0000-0000-0000-000000000011',
  'ca500000-0000-0000-0000-000000000102',
  session.id,
  5000,
  'completed'
from public.cash_sessions session
where session.cash_register_id = 'ca500000-0000-0000-0000-000000000051'
  and session.status = 'open';

insert into public.sale_payments (
  id, business_id, sale_id, payment_method, amount, status
)
values
  ('ca500000-0000-0000-0000-000000000071', 'ca500000-0000-0000-0000-000000000001', 'ca500000-0000-0000-0000-000000000061', 'cash', 10000, 'completed'),
  ('ca500000-0000-0000-0000-000000000072', 'ca500000-0000-0000-0000-000000000001', 'ca500000-0000-0000-0000-000000000062', 'cash', 5000, 'completed');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'ca500000-0000-0000-0000-000000000102', true);

do $$
declare
  v_session_id uuid;
  v_close jsonb;
  v_retry jsonb;
begin
  select id into v_session_id
  from public.cash_sessions
  where cash_register_id = 'ca500000-0000-0000-0000-000000000051'
    and status = 'open';

  v_close := public.close_cash_session_authoritatively(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000051',
    v_session_id,
    65000,
    'multi-device close'
  );
  v_retry := public.close_cash_session_authoritatively(
    'ca500000-0000-0000-0000-000000000001',
    'ca500000-0000-0000-0000-000000000011',
    'ca500000-0000-0000-0000-000000000051',
    v_session_id,
    65000,
    'retry'
  );

  if (v_close->>'expected_cash_amount')::numeric <> 65000
     or not (v_retry->>'idempotent')::boolean
  then
    raise exception 'Authoritative close mismatch: close=% retry=%', v_close, v_retry;
  end if;
end;
$$;
select pass('4. authoritative close includes both devices and retry is idempotent');

select set_config('request.jwt.claim.sub', 'ca500000-0000-0000-0000-000000000103', true);
do $$
begin
  begin
    perform public.open_or_reuse_cash_session(
      'ca500000-0000-0000-0000-000000000001',
      'ca500000-0000-0000-0000-000000000011',
      'ca500000-0000-0000-0000-000000000051',
      0
    );
    raise exception 'Expected capability denial';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'Effective permissions do not authorize cash opening' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', 'ca500000-0000-0000-0000-000000000102', true);
  begin
    perform public.open_or_reuse_cash_session(
      'ca500000-0000-0000-0000-000000000001',
      'ca500000-0000-0000-0000-000000000012',
      'ca500000-0000-0000-0000-000000000051',
      0
    );
    raise exception 'Expected cross-branch register denial';
  exception
    when sqlstate '42501' then
      if sqlerrm <> 'Cash register is not available' then
        raise;
      end if;
  end;
end;
$$;
select pass('5. capability and cross-branch denial are enforced server-side');

select * from finish();
rollback;
