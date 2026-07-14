-- 6.18C.36 - POS inventory auto-apply after completed POS sync batch
--
-- Goal:
-- When process_sync_batch(..., 'apply_pos') completes a POS upload batch,
-- automatically apply inventory movements generated from sale_items.
--
-- This avoids relying on every client to remember calling:
-- public.apply_pos_batch_inventory_movements(batch_id)
--
-- The target function is expected to be idempotent, so reprocessing the same
-- batch must not duplicate inventory_movements or double-decrement stock.

create or replace function private.apply_pos_inventory_after_sync_batch_completed()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_is_pos_batch boolean := false;
  v_result jsonb;
begin
  -- Avoid accidental recursion if downstream functions update sync_batches.
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  -- Only upload batches can generate server-side business mutations.
  if new.direction is distinct from 'upload' then
    return new;
  end if;

  if new.deleted_at is not null then
    return new;
  end if;

  -- Only when the batch transitions to completed.
  if new.status is distinct from 'completed' then
    return new;
  end if;

  if old.status is not distinct from new.status then
    return new;
  end if;

  -- Detect POS batch by metadata or by contained POS mutations.
  v_is_pos_batch :=
    coalesce(new.metadata::text ilike '%pos%', false)
    or exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = new.id
        and sm.deleted_at is null
        and sm.entity_table in ('sales', 'sale_items', 'sale_payments')
    );

  if not v_is_pos_batch then
    return new;
  end if;

  v_result := public.apply_pos_batch_inventory_movements(new.id);

  -- Record a lightweight trace in sync_batches.metadata.
  update public.sync_batches sb
  set
    metadata =
      coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'pos_inventory_auto_apply', jsonb_build_object(
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

comment on function private.apply_pos_inventory_after_sync_batch_completed()
is 'Automatically applies POS inventory movements when an upload POS sync batch transitions to completed.';

drop trigger if exists trg_sync_batches_apply_pos_inventory_after_completed
on public.sync_batches;

create trigger trg_sync_batches_apply_pos_inventory_after_completed
after update of status
on public.sync_batches
for each row
when (
  old.status is distinct from new.status
  and new.status = 'completed'
)
execute function private.apply_pos_inventory_after_sync_batch_completed();

comment on trigger trg_sync_batches_apply_pos_inventory_after_completed
on public.sync_batches
is 'Applies POS inventory automatically after process_sync_batch(apply_pos) completes a POS upload batch.';
