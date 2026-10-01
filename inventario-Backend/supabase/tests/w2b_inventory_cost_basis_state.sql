begin;
select plan(40);

select ok(to_regprocedure(
  'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)')
  is not null, 'pure receipt helper exists');
select ok(to_regprocedure(
  'private.apply_costed_inventory_issue(bigint,bigint,bigint)')
  is not null, 'pure issue helper exists');
select ok(not exists (
  select 1 from pg_proc p,
    lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
  where p.oid = to_regprocedure(
    'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)')
    and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
), 'receipt PUBLIC execute denied');
select ok(not has_function_privilege('anon',
  'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)',
  'EXECUTE'), 'receipt anon execute denied');
select ok(not has_function_privilege('authenticated',
  'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)',
  'EXECUTE'), 'receipt authenticated execute denied');
select ok(not has_function_privilege('service_role',
  'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)',
  'EXECUTE'), 'receipt service_role direct execute denied');
select ok(not exists (
  select 1 from pg_proc p,
    lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) acl
  where p.oid = to_regprocedure(
    'private.apply_costed_inventory_issue(bigint,bigint,bigint)')
    and acl.grantee = 0 and acl.privilege_type = 'EXECUTE'
), 'issue PUBLIC execute denied');
select ok(not has_function_privilege('anon',
  'private.apply_costed_inventory_issue(bigint,bigint,bigint)',
  'EXECUTE'), 'issue anon execute denied');
select ok(not has_function_privilege('authenticated',
  'private.apply_costed_inventory_issue(bigint,bigint,bigint)',
  'EXECUTE'), 'issue authenticated execute denied');
select ok(not has_function_privilege('service_role',
  'private.apply_costed_inventory_issue(bigint,bigint,bigint)',
  'EXECUTE'), 'issue service_role direct execute denied');

-- Same deterministic scenarios as inventory_cost_basis_test.dart.
select ok((select quantity_after = 3000 and cost_basis_after_cents = 480000
  and cost_effect_cents = 480000
  from private.apply_costed_inventory_receipt(0, 0, 3000, 480000)),
  'empty receipt');
select ok((select quantity_after = 13000 and cost_basis_after_cents = 2280000
  and cost_effect_cents = 1800000
  from private.apply_costed_inventory_receipt(3000, 480000, 10000, 1800000)),
  'known cost receipt with higher new cost');
select ok((select quantity_after = 12000 and cost_basis_after_cents = 2000000
  from private.apply_costed_inventory_receipt(2000, 400000, 10000, 1600000)),
  'lower new cost still adds exact bases');
select ok((with first as (
    select * from private.apply_costed_inventory_receipt(0, 0, 10000, 1800000)
  ), second as (
    select r.* from first f cross join lateral
      private.apply_costed_inventory_receipt(
        f.quantity_after, f.cost_basis_after_cents, 5000, 800000) r
  ) select r.quantity_after = 18000 and r.cost_basis_after_cents = 3200000
    from second s cross join lateral private.apply_costed_inventory_receipt(
      s.quantity_after, s.cost_basis_after_cents, 3000, 600000) r),
  'successive receipts never round an average');
select ok((select quantity_after = 12265
  and cost_basis_after_cents = 2151092 and cogs_cents = 128908
  and cost_effect_cents = -128908
  from private.apply_costed_inventory_issue(13000, 2280000, 735)),
  'partial issue uses W2A HALF_UP');
select ok((select cost_basis_after_cents + cogs_cents = 2280000
  and quantity_after + 735 = 13000
  and cogs_cents between 0 and 2280000
  from private.apply_costed_inventory_issue(13000, 2280000, 735)),
  'partial issue conserves quantity and cents');
select ok((select quantity_after = 0 and cost_basis_after_cents = 0
  and cogs_cents = 1 and cost_effect_cents = -1
  from private.apply_costed_inventory_issue(3, 1, 3)),
  'full depletion takes every remaining cent');
select ok((select quantity_after = 300 and cost_basis_after_cents = 0
  and cogs_cents = 0 and cost_effect_cents = 0
  from private.apply_costed_inventory_issue(500, 0, 200)),
  'known zero cost remains known');
select ok((select quantity_after = 300 and cost_basis_after_cents is null
  and cogs_cents is null and cost_effect_cents is null
  from private.apply_costed_inventory_issue(500, null, 200)),
  'unknown partial issue does not invent COGS');
select ok((select quantity_after = 0 and cost_basis_after_cents = 0
  and cogs_cents is null and cost_effect_cents is null
  from private.apply_costed_inventory_issue(500, null, 500)),
  'unknown full issue clears remaining basis without inventing COGS');
select ok((select quantity_after = 600 and cost_basis_after_cents is null
  and cost_effect_cents = 8000
  from private.apply_costed_inventory_receipt(500, null, 100, 8000)),
  'known receipt on unknown stock leaves aggregate cost unknown');
select ok((select quantity_after = 100 and cost_basis_after_cents = 8000
  and cost_effect_cents = 8000
  from private.apply_costed_inventory_receipt(0, null, 100, 8000)),
  'empty NULL stock accepts a known new cost');
select ok((select quantity_after = 10000 and cost_basis_after_cents = 1600000
  from private.apply_costed_inventory_receipt(
    0, 0, 10000, private.calculate_basis_amount_cents(80000, 10000, 500))),
  'W2A quotes 10 kg at 800 COP per commercial pound before W2B receipt');

select throws_ok($$select * from private.apply_costed_inventory_issue(5, 10, 6)$$,
  '22023', null, 'insufficient stock rejected');
select throws_ok($$select * from private.apply_costed_inventory_receipt(-1, 0, 1, 0)$$,
  '22023', null, 'negative prior quantity rejected');
select throws_ok($$select * from private.apply_costed_inventory_receipt(0, 0, 0, 0)$$,
  '22023', null, 'zero incoming quantity rejected');
select throws_ok($$select * from private.apply_costed_inventory_receipt(0, 0, -1, 0)$$,
  '22023', null, 'negative incoming quantity rejected');
select throws_ok($$select * from private.apply_costed_inventory_receipt(0, 0, 1, -1)$$,
  '22023', null, 'negative incoming cost rejected');
select throws_ok($$select * from private.apply_costed_inventory_receipt(1, -1, 1, 0)$$,
  '22023', null, 'negative prior cost rejected on receipt');
select throws_ok($$select * from private.apply_costed_inventory_receipt(0, 1, 1, 0)$$,
  '22023', null, 'empty stock with positive residual basis rejected');
select throws_ok($$select * from private.apply_costed_inventory_issue(0, 0, 1)$$,
  '22023', null, 'issue from empty stock rejected');
select throws_ok($$select * from private.apply_costed_inventory_issue(5, 10, 0)$$,
  '22023', null, 'zero issue quantity rejected');
select throws_ok($$select * from private.apply_costed_inventory_issue(5, 10, -1)$$,
  '22023', null, 'negative issue quantity rejected');
select throws_ok($$select * from private.apply_costed_inventory_issue(5, -1, 1)$$,
  '22023', null, 'negative prior cost rejected on issue');

select ok((select quantity_after = 9223372036854775807
  and cost_basis_after_cents = 9223372036854775807
  from private.apply_costed_inventory_receipt(
    0, 0, 9223372036854775807, 9223372036854775807)),
  'large safe BIGINT values accepted');
select throws_ok($$select * from private.apply_costed_inventory_receipt(
  9223372036854775807, 0, 1, 0)$$,
  '22003', null, 'quantity overflow rejected before BIGINT addition');
select throws_ok($$select * from private.apply_costed_inventory_receipt(
  1, 9223372036854775807, 1, 1)$$,
  '22003', null, 'cost overflow rejected before BIGINT addition');

select ok((with first as (
    select * from private.apply_costed_inventory_receipt(0, 0, 3000, 480000)
  ), combined as (
    select r.* from first f cross join lateral
      private.apply_costed_inventory_receipt(
        f.quantity_after, f.cost_basis_after_cents, 10000, 1800000) r
  ) select combined.quantity_after = 13000
    and combined.cost_basis_after_cents = 2280000
    and issued.quantity_after = 12265
    and issued.cogs_cents = 128908
    and issued.cost_basis_after_cents = 2151092
    from combined cross join lateral private.apply_costed_inventory_issue(
      combined.quantity_after, combined.cost_basis_after_cents, 735) issued),
  '3 kg at 800/libra plus 10 kg at 900/libra then 735 g issue');
select ok((select p.provolatile = 'i' and p.proparallel = 's' from pg_proc p
  where p.oid = to_regprocedure(
    'private.apply_costed_inventory_receipt(bigint,bigint,bigint,bigint)')),
  'receipt helper is immutable and parallel safe');
select ok((select p.provolatile = 'i' and p.proparallel = 's' from pg_proc p
  where p.oid = to_regprocedure(
    'private.apply_costed_inventory_issue(bigint,bigint,bigint)')),
  'issue helper is immutable and parallel safe');

select * from finish();
rollback;
