begin;

alter table public.products
  add constraint products_minimum_stock_non_negative
  check (minimum_stock is null or minimum_stock >= 0)
  not valid;

alter table public.products
  validate constraint products_minimum_stock_non_negative;

commit;
