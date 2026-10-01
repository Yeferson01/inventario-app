begin;
select plan(9);

insert into public.businesses (id, name, status)
values ('a7400000-0000-0000-0000-000000000001', 'W4D Business', 'active');
insert into public.products (id, business_id, name, sale_price, unit)
values ('a7400000-0000-0000-0000-000000000201',
  'a7400000-0000-0000-0000-000000000001', 'Legacy kg label', 800, 'kg');
insert into public.products (id, business_id, name, sale_price, sale_mode)
values ('a7400000-0000-0000-0000-000000000202',
  'a7400000-0000-0000-0000-000000000001', 'New weighted', 800, 'weight');

select is((select sale_mode from public.products where id =
  'a7400000-0000-0000-0000-000000000201'), 'unit',
  'legacy unit label does not change sale mode');
select is((select sale_mode from public.products where id =
  'a7400000-0000-0000-0000-000000000202'), 'weight',
  'WEIGHT mode is valid at initial creation');
select throws_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7400000-0000-0000-0000-000000000201'$$,
  'P0001', 'product_sale_mode_immutable_after_creation',
  'UNIT cannot transition to WEIGHT without history');
select throws_ok($$update public.products set sale_mode = 'unit'
  where id = 'a7400000-0000-0000-0000-000000000202'$$,
  'P0001', 'product_sale_mode_immutable_after_creation',
  'WEIGHT cannot transition to UNIT without history');
select lives_ok($$update public.products set sale_mode = 'unit',
  sale_price = 900.25
  where id = 'a7400000-0000-0000-0000-000000000201'$$,
  'same UNIT mode and price-only edit remain valid');
select is((select sale_price_cents from public.products where id =
  'a7400000-0000-0000-0000-000000000201'), 90025::bigint,
  'price-only edit derives exact cents from sale_price');
select lives_ok($$update public.products set sale_mode = 'weight'
  where id = 'a7400000-0000-0000-0000-000000000202'$$,
  'same WEIGHT mode remains valid');
select throws_ok($$update public.products set sale_price = 901
  where id = 'a7400000-0000-0000-0000-000000000202'$$,
  'P0001', 'weight_product_price_requires_versioned_sync',
  'direct WEIGHT price edit still requires verified sync');
select is((select sale_price_cents from public.products where id =
  'a7400000-0000-0000-0000-000000000202'), 80000::bigint,
  'rejected direct WEIGHT price edit leaves price unchanged');

select * from finish();
rollback;
