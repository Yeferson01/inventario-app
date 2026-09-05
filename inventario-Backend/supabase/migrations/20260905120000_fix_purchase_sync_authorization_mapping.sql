-- Purchase sync authorization closure.
--
-- Purchases and purchase_items are one inventory purchasing domain. The
-- authoritative capability used by the permission seed, direct-table RLS and
-- Flutter is inventory.purchase. Keep every other sync mapping unchanged.

begin;

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
  v_entity text := lower(trim(coalesce(p_entity_table, '')));
  v_operation text := lower(trim(coalesce(p_operation, '')));
  v_action text;
begin
  v_action := case
    when v_operation in ('insert', 'upsert') then 'create'
    when v_operation = 'update' then 'update'
    when v_operation in ('soft_delete', 'delete') then 'soft_delete'
    else null
  end;

  if v_entity = '' or v_action is null or v_operation = 'delete' then
    return array[]::text[];
  end if;

  if v_entity = 'products' then
    return case v_operation
      when 'insert' then array['products.create']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'product_barcodes' then
    return case v_operation
      when 'insert' then array['products.create', 'products.update']
      when 'upsert' then array['products.create', 'products.update']
      when 'update' then array['products.update']
      when 'soft_delete' then array['products.soft_delete']
      else array[]::text[]
    end;
  end if;

  if v_entity = 'categories' then
    return array[
      'categories.' || v_action,
      'products.' || v_action,
      'inventory.' || case when v_action = 'create' then 'adjust' else 'read' end
    ];
  end if;

  if v_entity = 'customers' then
    return array[
      'customers.' || v_action,
      'sales.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity = 'suppliers' then
    return array[
      'suppliers.' || v_action,
      'purchases.' || case when v_action = 'create' then 'create' else 'update' end
    ];
  end if;

  if v_entity in ('purchases', 'purchase_items') then
    return array['inventory.purchase'];
  end if;

  if v_entity in ('sales', 'sale_items', 'sale_payments') then
    return array['sales.' || v_action];
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
    return array['inventory.count'];
  end if;

  if v_entity in ('inventory_transfers', 'inventory_transfer_items') then
    return array['inventory.transfer'];
  end if;

  return array[]::text[];
end;
$$;

comment on function private.sync_entity_permission_candidates(text, text) is
'Returns explicit candidate permissions for supported sync entity/operation pairs. Purchases use inventory.purchase; unknown pairs and hard deletes fail closed.';

commit;
