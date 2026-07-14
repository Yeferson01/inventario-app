-- Fase 6.15C - Aplicar inventario de compras desde sync batch
-- Objetivo:
-- Crear public.apply_purchase_batch_inventory_movements(sync_batch_id)
-- para aplicar movimientos de inventario de compras offline ya procesadas.
--
-- Nota:
-- La función es idempotente a nivel funcional porque public.apply_purchase_inventory_movements
-- debe usar idempotency keys por purchase/item. Además, esta wrapper mide movimientos reales
-- antes/después para reportar correctamente si ya estaba aplicado.

begin;

create or replace function public.apply_purchase_batch_inventory_movements(
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
  v_purchase record;

  v_purchases_checked integer := 0;
  v_purchases_completed integer := 0;
  v_purchases_applied integer := 0;
  v_purchases_already_applied integer := 0;

  v_rpc_movements_reported integer := 0;
  v_purchase_movements_before integer := 0;
  v_purchase_movements_after integer := 0;
  v_actual_movements_created integer := 0;
  v_total_movements_created integer := 0;

  v_errors jsonb := '[]'::jsonb;
  v_applied_purchases jsonb := '[]'::jsonb;
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

  if not (
    private.has_business_permission(v_batch.business_id, 'inventory.purchase')
    or private.has_business_permission(v_batch.business_id, 'inventory.adjust')
    or private.has_business_permission(v_batch.business_id, 'settings.business')
  ) then
    raise exception 'Insufficient permission to apply purchase batch inventory';
  end if;

  for v_purchase in
    with purchase_ids as (
      select sm.entity_id as purchase_id
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
        and lower(sm.entity_table) = 'purchases'

      union

      select nullif(sm.payload ->> 'purchase_id', '')::uuid as purchase_id
      from public.sync_mutations sm
      where sm.sync_batch_id = p_sync_batch_id
        and sm.deleted_at is null
        and sm.status = 'applied'
        and lower(sm.entity_table) = 'purchase_items'
        and sm.payload ? 'purchase_id'
        and nullif(sm.payload ->> 'purchase_id', '') is not null
    )
    select
      p.id,
      p.business_id,
      p.branch_id,
      p.status,
      p.deleted_at,
      p.total
    from purchase_ids x
    join public.purchases p on p.id = x.purchase_id
    where p.business_id = v_batch.business_id
    order by p.created_at asc
  loop
    v_purchases_checked := v_purchases_checked + 1;

    if v_purchase.deleted_at is not null then
      continue;
    end if;

    -- Por ahora aplicamos inventario solo para compras completadas.
    if v_purchase.status <> 'completed' then
      continue;
    end if;

    v_purchases_completed := v_purchases_completed + 1;

    begin
      select count(*)
      into v_purchase_movements_before
      from public.inventory_movements im
      where im.business_id = v_purchase.business_id
        and im.branch_id is not distinct from v_purchase.branch_id
        and im.source_type = 'purchase'
        and im.source_id = v_purchase.id;

      select public.apply_purchase_inventory_movements(v_purchase.id)
      into v_rpc_movements_reported;

      select count(*)
      into v_purchase_movements_after
      from public.inventory_movements im
      where im.business_id = v_purchase.business_id
        and im.branch_id is not distinct from v_purchase.branch_id
        and im.source_type = 'purchase'
        and im.source_id = v_purchase.id;

      v_actual_movements_created := greatest(
        v_purchase_movements_after - v_purchase_movements_before,
        0
      );

      v_total_movements_created := v_total_movements_created + v_actual_movements_created;

      if v_actual_movements_created > 0 then
        v_purchases_applied := v_purchases_applied + 1;
      else
        v_purchases_already_applied := v_purchases_already_applied + 1;
      end if;

      v_applied_purchases := v_applied_purchases || jsonb_build_array(
        jsonb_build_object(
          'purchase_id', v_purchase.id,
          'movements_created', v_actual_movements_created,
          'movements_before', v_purchase_movements_before,
          'movements_after', v_purchase_movements_after,
          'rpc_movements_reported', coalesce(v_rpc_movements_reported, 0)
        )
      );

    exception when others then
      v_errors := v_errors || jsonb_build_array(
        jsonb_build_object(
          'purchase_id', v_purchase.id,
          'error_message', sqlerrm
        )
      );
    end;
  end loop;

  update public.sync_batches sb
  set
    metadata = coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'purchase_inventory_apply',
        jsonb_build_object(
          'applied_at', now(),
          'purchases_checked', v_purchases_checked,
          'purchases_completed', v_purchases_completed,
          'purchases_applied', v_purchases_applied,
          'purchases_already_applied', v_purchases_already_applied,
          'movements_created', v_total_movements_created,
          'error_count', jsonb_array_length(v_errors)
        )
      ),
    updated_at = now(),
    updated_by = v_profile_id
  where sb.id = p_sync_batch_id;

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'purchases_checked', v_purchases_checked,
    'purchases_completed', v_purchases_completed,
    'purchases_applied', v_purchases_applied,
    'purchases_already_applied', v_purchases_already_applied,
    'movements_created', v_total_movements_created,
    'error_count', jsonb_array_length(v_errors),
    'applied_purchases', v_applied_purchases,
    'errors', v_errors
  );
end;
$$;

comment on function public.apply_purchase_batch_inventory_movements(uuid)
is 'Applies purchase inventory movements for completed purchases in a processed upload sync batch. Reports real movements created before/after for idempotency accuracy.';

revoke all on function public.apply_purchase_batch_inventory_movements(uuid) from public;
grant execute on function public.apply_purchase_batch_inventory_movements(uuid) to authenticated;
grant execute on function public.apply_purchase_batch_inventory_movements(uuid) to service_role;

commit;