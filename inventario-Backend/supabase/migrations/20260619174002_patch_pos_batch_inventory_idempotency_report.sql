-- Fase 6.13A.1 - Patch POS batch inventory idempotency report
-- Objetivo:
-- Corregir el reporte de apply_pos_batch_inventory_movements().
--
-- Antes:
-- La segunda ejecución podía reportar movements_created = 1 aunque no creara
-- un movimiento nuevo, porque confiaba en el retorno de apply_sale_inventory_movements().
--
-- Ahora:
-- Cuenta inventory_movements antes y después de aplicar inventario por venta.
-- Así movements_created refleja movimientos realmente nuevos.

begin;

create or replace function public.apply_pos_batch_inventory_movements(
  p_sync_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_profile_id uuid;
  v_batch record;
  v_sale record;

  v_sales_checked integer := 0;
  v_sales_completed integer := 0;
  v_sales_applied integer := 0;
  v_sales_already_applied integer := 0;

  v_rpc_movements_reported integer := 0;
  v_sale_movements_before integer := 0;
  v_sale_movements_after integer := 0;
  v_actual_movements_created integer := 0;
  v_total_movements_created integer := 0;

  v_errors jsonb := '[]'::jsonb;
  v_applied_sales jsonb := '[]'::jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_sync_batch_id is null then
    raise exception 'p_sync_batch_id is required';
  end if;

  select
    sb.id,
    sb.business_id,
    sb.app_device_id,
    sb.profile_id,
    sb.branch_id,
    sb.direction,
    sb.status,
    sb.deleted_at
  into v_batch
  from public.sync_batches sb
  where sb.id = p_sync_batch_id;

  if v_batch.id is null then
    raise exception 'Sync batch not found';
  end if;

  if v_batch.deleted_at is not null then
    raise exception 'Cannot apply inventory for deleted sync batch';
  end if;

  if v_batch.direction <> 'upload' then
    raise exception 'Inventory can only be applied for upload sync batches';
  end if;

  if v_batch.status not in ('completed', 'partial') then
    raise exception 'Sync batch must be completed or partial before applying inventory';
  end if;

  if v_batch.profile_id <> v_profile_id
     and not (
       private.has_business_permission(v_batch.business_id, 'inventory.adjust')
       or private.has_business_permission(v_batch.business_id, 'settings.business')
     ) then
    raise exception 'Insufficient permission to apply POS batch inventory';
  end if;

  for v_sale in
    with sale_ids as (
      select sm.entity_id as sale_id
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
        and lower(sm.entity_table) = 'sales'

      union

      select nullif(sm.payload ->> 'sale_id', '')::uuid as sale_id
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
        and lower(sm.entity_table) in ('sale_items', 'sale_payments')
        and sm.payload ? 'sale_id'
        and nullif(sm.payload ->> 'sale_id', '') is not null
    )
    select
      s.id,
      s.business_id,
      s.branch_id,
      s.status,
      s.deleted_at,
      s.total,
      s.paid_total
    from sale_ids x
    join public.sales s on s.id = x.sale_id
    where s.business_id = v_batch.business_id
    order by s.created_at asc
  loop
    v_sales_checked := v_sales_checked + 1;

    if v_sale.deleted_at is not null then
      continue;
    end if;

    if v_sale.status <> 'completed' then
      continue;
    end if;

    v_sales_completed := v_sales_completed + 1;

    begin
      select count(*)
      into v_sale_movements_before
      from public.inventory_movements im
      where im.business_id = v_sale.business_id
        and im.branch_id = v_sale.branch_id
        and im.source_type = 'sale'
        and im.source_id = v_sale.id;

      select public.apply_sale_inventory_movements(v_sale.id)
      into v_rpc_movements_reported;

      select count(*)
      into v_sale_movements_after
      from public.inventory_movements im
      where im.business_id = v_sale.business_id
        and im.branch_id = v_sale.branch_id
        and im.source_type = 'sale'
        and im.source_id = v_sale.id;

      v_actual_movements_created := greatest(
        v_sale_movements_after - v_sale_movements_before,
        0
      );

      v_total_movements_created :=
        v_total_movements_created + v_actual_movements_created;

      if v_actual_movements_created > 0 then
        v_sales_applied := v_sales_applied + 1;
      else
        v_sales_already_applied := v_sales_already_applied + 1;
      end if;

      v_applied_sales := v_applied_sales || jsonb_build_array(
        jsonb_build_object(
          'sale_id', v_sale.id,
          'movements_created', v_actual_movements_created,
          'movements_before', v_sale_movements_before,
          'movements_after', v_sale_movements_after,
          'rpc_movements_reported', coalesce(v_rpc_movements_reported, 0)
        )
      );
    exception
      when others then
        v_errors := v_errors || jsonb_build_array(
          jsonb_build_object(
            'sale_id', v_sale.id,
            'error_message', sqlerrm
          )
        );
    end;
  end loop;

  update public.sync_batches sb
  set
    metadata = coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'pos_inventory_apply', jsonb_build_object(
          'applied_at', now(),
          'sales_checked', v_sales_checked,
          'sales_completed', v_sales_completed,
          'sales_applied', v_sales_applied,
          'sales_already_applied', v_sales_already_applied,
          'movements_created', v_total_movements_created,
          'error_count', jsonb_array_length(v_errors)
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sb.id = p_sync_batch_id;

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'sales_checked', v_sales_checked,
    'sales_completed', v_sales_completed,
    'sales_applied', v_sales_applied,
    'sales_already_applied', v_sales_already_applied,
    'movements_created', v_total_movements_created,
    'error_count', jsonb_array_length(v_errors),
    'applied_sales', v_applied_sales,
    'errors', v_errors
  );
end;
$$;

comment on function public.apply_pos_batch_inventory_movements(uuid)
is 'Applies inventory movements for completed sales contained in an already processed POS sync batch. Counts actual newly-created inventory_movements to report idempotency correctly.';

revoke all on function public.apply_pos_batch_inventory_movements(uuid) from public;
grant execute on function public.apply_pos_batch_inventory_movements(uuid) to authenticated;
grant execute on function public.apply_pos_batch_inventory_movements(uuid) to service_role;

commit;