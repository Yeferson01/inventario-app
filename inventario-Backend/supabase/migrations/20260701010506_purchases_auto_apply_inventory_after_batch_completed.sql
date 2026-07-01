-- 6.18C.37A - Purchases inventory auto-apply after completed purchases sync batch
--
-- When process_sync_batch(..., 'apply_purchases') completes an upload batch,
-- automatically apply inventory movements generated from purchase_items.
--
-- This mirrors the POS auto-apply trigger and keeps the backend as the single
-- source of truth for remote stock effects.

create or replace function private.apply_purchase_inventory_after_sync_batch_completed()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_is_purchase_batch boolean := false;
  v_result jsonb;
begin
  -- Avoid accidental recursion if downstream functions update sync_batches.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.direction is distinct from 'upload' then
    return new;
  end if;

  if new.deleted_at is not null then
    return new;
  end if;

  if new.status is distinct from 'completed' then
    return new;
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  -- Detect purchases batch by metadata or contained mutations.
  v_is_purchase_batch :=
    coalesce(new.metadata::text ilike '%purchase%', false)
    or exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = new.id
        and sm.deleted_at is null
        and sm.entity_table in ('purchases', 'purchase_items')
    );

  if not v_is_purchase_batch then
    return new;
  end if;

  v_result := public.apply_purchase_batch_inventory_movements(new.id);

  update public.sync_batches sb
  set
    metadata =
      coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'purchase_inventory_auto_apply', jsonb_build_object(
          'triggered_at', now(),
          'trigger_name', tg_name,
          'result', v_result
        )
      ),
    updated_at = now()
  where sb.id = new.id;

  return new;
end;
$$;

comment on function private.apply_purchase_inventory_after_sync_batch_completed()
is 'Automatically applies purchase inventory movements when an upload purchases sync batch transitions to completed.';

drop trigger if exists trg_sync_batches_apply_purchase_inventory_after_completed
on public.sync_batches;

create trigger trg_sync_batches_apply_purchase_inventory_after_completed
after update of status
on public.sync_batches
for each row
when (
  old.status is distinct from new.status
  and new.status = 'completed'
)
execute function private.apply_purchase_inventory_after_sync_batch_completed();

comment on trigger trg_sync_batches_apply_purchase_inventory_after_completed
on public.sync_batches
is 'Applies purchase inventory automatically after process_sync_batch(apply_purchases) completes a purchases upload batch.';
