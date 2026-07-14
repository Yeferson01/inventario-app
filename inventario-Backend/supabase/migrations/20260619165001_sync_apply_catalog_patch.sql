-- Fase 6.9.1 - Patch apply_catalog
-- Objetivo:
-- Corregir compatibilidad entre apply_catalog y el esquema real.
--
-- Corrige:
-- 1. Agrega metadata jsonb a tablas de catálogo.
-- 2. Ajusta permisos candidatos para suppliers.

begin;

-- =========================================================
-- AGREGAR METADATA A CATÁLOGO
-- =========================================================

alter table public.categories
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.customers
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.suppliers
add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.products
add column if not exists metadata jsonb not null default '{}'::jsonb;

comment on column public.categories.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

comment on column public.customers.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

comment on column public.suppliers.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

comment on column public.products.metadata
is 'Flexible metadata for offline sync, integrations and future extensions.';

-- =========================================================
-- PATCH PERMISSION CANDIDATES
-- =========================================================

create or replace function private.sync_entity_permission_candidates(
  p_entity_table text,
  p_operation text
)
returns text[]
language plpgsql
stable
security definer
set search_path = public, private, extensions
as $$
declare
  v_entity text;
  v_operation text;
  v_action text;
begin
  v_entity := lower(trim(coalesce(p_entity_table, '')));
  v_operation := lower(trim(coalesce(p_operation, '')));

  v_action := case
    when v_operation in ('insert', 'upsert') then 'create'
    when v_operation = 'update' then 'update'
    when v_operation in ('soft_delete', 'delete') then 'soft_delete'
    else null
  end;

  if v_entity = '' or v_action is null then
    return array[]::text[];
  end if;

  -- Catálogo
  if v_entity = 'categories' then
    return array[
      'categories.' || v_action,
      'products.' || v_action,
      'settings.business'
    ];
  end if;

  if v_entity = 'products' then
    return array[
      'products.' || v_action,
      'inventory.' || case
        when v_action in ('create', 'update') then 'adjust'
        else 'read'
      end,
      'settings.business'
    ];
  end if;

  if v_entity = 'customers' then
    return array[
      'customers.' || v_action,
      'sales.' || case
        when v_action = 'create' then 'create'
        else 'update'
      end,
      'settings.business'
    ];
  end if;

  if v_entity = 'suppliers' then
    return array[
      'suppliers.' || v_action,
      'purchases.' || case
        when v_action = 'create' then 'create'
        else 'update'
      end,
      'settings.business'
    ];
  end if;

  -- Compras
  if v_entity in ('purchases', 'purchase_items') then
    return array[
      'purchases.' || v_action
    ];
  end if;

  -- Ventas / POS
  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array[
      'sales.' || v_action
    ];
  end if;

  if v_entity in ('cash_sessions', 'cash_registers') then
    return array[
      'sales.' || case
        when v_action = 'create' then 'create'
        when v_action = 'update' then 'update'
        else 'soft_delete'
      end
    ];
  end if;

  -- Inventario
  if v_entity = 'inventory_movements' then
    if v_operation in ('insert', 'upsert') then
      return array[
        'inventory.adjust',
        'inventory.count',
        'inventory.transfer',
        'purchases.create',
        'sales.create'
      ];
    end if;

    return array[]::text[];
  end if;

  if v_entity in ('stock_counts', 'stock_count_items') then
    return array[
      'inventory.count'
    ];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array[
      'inventory.transfer'
    ];
  end if;

  -- Fallback conservador
  return array[
    v_entity || '.' || v_action,
    'settings.business'
  ];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text)
is 'Returns candidate permissions required to sync a given entity/operation. Patched for catalog sync compatibility.';

revoke all on function private.sync_entity_permission_candidates(text, text) from public;
grant execute on function private.sync_entity_permission_candidates(text, text) to authenticated, service_role;

commit;