-- P2.4R3 SB-10 - Real two-connection idempotency concurrency harness.
--
-- This harness is intentionally separate from the rollback-only pgTAP file:
-- independent database connections cannot observe uncommitted auth fixtures.
-- It commits an isolated fixture, races two calls, asserts one canonical
-- tenant, and then removes only that fixture from the disposable local DB.

\set ON_ERROR_STOP on

\if :{?p2_4_r3_dblink_dsn}
\else
  \echo 'ERROR: required psql variable p2_4_r3_dblink_dsn was not provided'
  do $$
  begin
    raise exception
      'required psql variable p2_4_r3_dblink_dsn was not provided';
  end;
  $$;
\endif

create extension if not exists pgtap with schema extensions;
create extension if not exists dblink with schema extensions;

set search_path = extensions, public, pg_catalog;

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values (
  'f2403000-0000-0000-0000-000000000010',
  'authenticated',
  'authenticated',
  'p24r3-concurrency@example.test',
  '',
  now(),
  '{}',
  '{"full_name":"P2.4R3 Concurrent Owner"}',
  now(),
  now()
);

select extensions.dblink_connect(
  'p2_4_r3_a',
  :'p2_4_r3_dblink_dsn'
);
select extensions.dblink_connect(
  'p2_4_r3_b',
  :'p2_4_r3_dblink_dsn'
);

\unset p2_4_r3_dblink_dsn

select extensions.dblink_send_query(
  'p2_4_r3_a',
  $query$
    with auth_context as materialized (
      select set_config(
        'request.jwt.claim.sub',
        'f2403000-0000-0000-0000-000000000010',
        false
      )
    ),
    created as materialized (
      select public.create_self_service_business(
        'P2.4R3 Concurrent Business',
        'p2-4-r3-concurrent',
        'Sucursal Principal'
      ) as result
      from auth_context
    ),
    held as materialized (
      select pg_sleep(2)
      from created
    )
    select created.result::text
    from created
    cross join held
  $query$
);

select extensions.dblink_send_query(
  'p2_4_r3_b',
  $query$
    with auth_context as materialized (
      select set_config(
        'request.jwt.claim.sub',
        'f2403000-0000-0000-0000-000000000010',
        false
      )
    )
    select public.create_self_service_business(
      'P2.4R3 Concurrent Business',
      'p2-4-r3-concurrent',
      'Sucursal Principal'
    )::text
    from auth_context
  $query$
);

create temporary table p2_4_r3_concurrency_results (
  caller text primary key,
  payload jsonb not null
);

insert into p2_4_r3_concurrency_results (caller, payload)
select 'a', result::jsonb
from extensions.dblink_get_result('p2_4_r3_a') as response(result text);

insert into p2_4_r3_concurrency_results (caller, payload)
select 'b', result::jsonb
from extensions.dblink_get_result('p2_4_r3_b') as response(result text);

select extensions.dblink_disconnect('p2_4_r3_a');
select extensions.dblink_disconnect('p2_4_r3_b');

select plan(1);

select ok(
  (select payload from p2_4_r3_concurrency_results where caller = 'a')
    =
  (select payload from p2_4_r3_concurrency_results where caller = 'b')
  and (
    select count(*) = 1
    from private.self_service_business_creation_requests request
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
      and request.status = 'completed'
  )
  and (
    select count(*) = 1
    from public.businesses business
    join private.self_service_business_creation_requests request
      on request.business_id = business.id
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
  )
  and (
    select count(*) = 1
    from public.business_members member
    join private.self_service_business_creation_requests request
      on request.business_id = member.business_id
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
      and member.profile_id = request.actor_user_id
      and member.branch_id is null
      and member.status = 'active'
      and member.deleted_at is null
  )
  and (
    select count(*) = 1
    from public.branches branch
    join private.self_service_business_creation_requests request
      on request.branch_id = branch.id
     and request.business_id = branch.business_id
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
  )
  and (
    select count(*) = 1
    from public.cash_registers register
    join private.self_service_business_creation_requests request
      on request.branch_id = register.branch_id
     and request.business_id = register.business_id
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
      and register.deleted_at is null
  )
  and (
    select count(*) = 1
    from public.receipt_sequences sequence
    join private.self_service_business_creation_requests request
      on request.branch_id = sequence.branch_id
     and request.business_id = sequence.business_id
    where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
      and request.idempotency_key = 'p2-4-r3-concurrent'
      and sequence.deleted_at is null
  ),
  'SB-10 concurrent equivalent calls create one canonical tenant and return identical IDs'
);

select * from finish();

-- Remove only the committed concurrency fixture. This is test cleanup, not a
-- production deletion path.
do $$
declare
  v_business_id uuid;
  v_branch_id uuid;
begin
  select request.business_id, request.branch_id
  into v_business_id, v_branch_id
  from private.self_service_business_creation_requests request
  where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
    and request.idempotency_key = 'p2-4-r3-concurrent';

  delete from private.self_service_business_creation_requests request
  where request.actor_user_id = 'f2403000-0000-0000-0000-000000000010'
    and request.idempotency_key = 'p2-4-r3-concurrent';

  delete from public.activity_logs log
  where log.business_id = v_business_id;

  delete from public.receipt_sequences sequence
  where sequence.business_id = v_business_id
    and sequence.branch_id = v_branch_id;

  delete from public.cash_registers register
  where register.business_id = v_business_id
    and register.branch_id = v_branch_id;

  delete from public.business_members member
  where member.business_id = v_business_id
    and member.profile_id = 'f2403000-0000-0000-0000-000000000010';

  delete from public.branches branch
  where branch.id = v_branch_id
    and branch.business_id = v_business_id;

  delete from public.businesses business
  where business.id = v_business_id;

  delete from public.profiles profile
  where profile.id = 'f2403000-0000-0000-0000-000000000010';

  delete from auth.users auth_user
  where auth_user.id = 'f2403000-0000-0000-0000-000000000010';
end;
$$;
