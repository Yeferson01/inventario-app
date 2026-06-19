-- Fase 6.12A.2 - Disable legacy stock triggers
-- Objetivo:
-- Eliminar triggers antiguos que modifican products.stock_quantity directamente
-- desde sale_items o purchase_items.
--
-- Motivo:
-- La arquitectura profesional de inventario ahora usa:
-- - inventory_movements
-- - product_stock_balances
-- - create_inventory_movement()
-- - apply_sale_inventory_movements()
-- - apply_purchase_inventory_movements()
--
-- Por lo tanto, sale_items y purchase_items NO deben modificar stock directamente.

begin;

do $$
declare
  r record;
begin
  for r in
    select
      ns.nspname as table_schema,
      cls.relname as table_name,
      tg.tgname as trigger_name,
      p.proname as function_name,
      pn.nspname as function_schema
    from pg_trigger tg
    join pg_class cls on cls.oid = tg.tgrelid
    join pg_namespace ns on ns.oid = cls.relnamespace
    join pg_proc p on p.oid = tg.tgfoid
    join pg_namespace pn on pn.oid = p.pronamespace
    where not tg.tgisinternal
      and ns.nspname = 'public'
      and cls.relname in ('sale_items', 'purchase_items')
      and pg_get_functiondef(p.oid) ilike '%stock_quantity%'
  loop
    raise notice
      'Dropping legacy stock trigger %.% using function %.%',
      r.table_name,
      r.trigger_name,
      r.function_schema,
      r.function_name;

    execute format(
      'drop trigger if exists %I on %I.%I',
      r.trigger_name,
      r.table_schema,
      r.table_name
    );
  end loop;
end;
$$;

comment on table public.inventory_movements
is 'Append-only inventory ledger. Stock must be changed through inventory_movements/product_stock_balances, not legacy products.stock_quantity triggers.';

comment on column public.products.stock_quantity
is 'Legacy/display stock field. Authoritative stock is product_stock_balances.quantity_on_hand. Do not update this through sale_items/purchase_items triggers.';

commit;