begin;
select plan(25);

select ok(to_regprocedure('private.calculate_basis_amount_cents(bigint,bigint,bigint)') is not null,
  'internal exact-basis helper exists');
select is(pg_get_function_result(to_regprocedure(
  'private.calculate_basis_amount_cents(bigint,bigint,bigint)')),
  'bigint', 'helper returns BIGINT');
select is((select p.provolatile from pg_proc p where p.oid =
  to_regprocedure('private.calculate_basis_amount_cents(bigint,bigint,bigint)')),
  'i'::"char", 'helper is immutable');
select is((select p.proparallel from pg_proc p where p.oid =
  to_regprocedure('private.calculate_basis_amount_cents(bigint,bigint,bigint)')),
  's'::"char", 'helper is parallel safe');

select ok(not exists (
  select 1 from pg_proc p,
    lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
  where p.oid = to_regprocedure(
    'private.calculate_basis_amount_cents(bigint,bigint,bigint)')
    and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
), 'PUBLIC has no EXECUTE');
select ok(not has_function_privilege('anon',
  'private.calculate_basis_amount_cents(bigint,bigint,bigint)', 'EXECUTE'),
  'anon has no EXECUTE');
select ok(not has_function_privilege('authenticated',
  'private.calculate_basis_amount_cents(bigint,bigint,bigint)', 'EXECUTE'),
  'authenticated has no EXECUTE');
select ok(not has_function_privilege('service_role',
  'private.calculate_basis_amount_cents(bigint,bigint,bigint)', 'EXECUTE'),
  'service_role has no direct EXECUTE');

-- Shared deterministic vectors, identical to exact_basis_money_test.dart.
select is(private.calculate_basis_amount_cents(350000, 2, 1), 700000::bigint,
  'unit');
select is(private.calculate_basis_amount_cents(1200000, 735, 500), 1764000::bigint,
  'weight');
select is(private.calculate_basis_amount_cents(1, 1, 3), 0::bigint,
  'below_half');
select is(private.calculate_basis_amount_cents(1, 1, 2), 1::bigint,
  'half');
select is(private.calculate_basis_amount_cents(2, 1, 3), 1::bigint,
  'above_half');
select is(private.calculate_basis_amount_cents(1200100, 3, 500), 7201::bigint,
  'commercial');
select is(private.calculate_basis_amount_cents(1200000, 0, 500), 0::bigint,
  'zero_quantity');
select is(private.calculate_basis_amount_cents(
  9223372036854775807, 9223372036854775807, 9223372036854775807),
  9223372036854775807::bigint, 'large_safe');
select is(private.calculate_basis_amount_cents(2280000, 735, 13000),
  128908::bigint, 'cost_ratio');

select throws_ok($$select private.calculate_basis_amount_cents(-1, 1, 1)$$,
  '22023', null, 'negative amount rejected');
select throws_ok($$select private.calculate_basis_amount_cents(1, -1, 1)$$,
  '22023', null, 'negative quantity rejected');
select throws_ok($$select private.calculate_basis_amount_cents(1, 1, 0)$$,
  '22023', null, 'zero basis rejected');
select throws_ok($$select private.calculate_basis_amount_cents(1, 1, -1)$$,
  '22023', null, 'negative basis rejected');
select throws_ok($$select private.calculate_basis_amount_cents(null, 1, 1)$$,
  '22023', null, 'null amount rejected');
select throws_ok($$select private.calculate_basis_amount_cents(1, null, 1)$$,
  '22023', null, 'null quantity rejected');
select throws_ok($$select private.calculate_basis_amount_cents(1, 1, null)$$,
  '22023', null, 'null basis rejected');
select throws_ok($$select private.calculate_basis_amount_cents(
  9223372036854775807, 2, 1)$$,
  '22003', null, 'rounded BIGINT overflow rejected');

select * from finish();
rollback;
