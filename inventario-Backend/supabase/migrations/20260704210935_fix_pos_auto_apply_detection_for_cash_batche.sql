-- Fix 6.18C.38F.2 - POS inventory trigger must not run for cash batches
--
-- Previous POS auto-apply detection used metadata::text ilike '%pos%'.
-- Cash batches can contain metadata like "pos_after_cash", which incorrectly
-- triggered POS inventory application.
--
-- New rule:
-- - POS batch is detected by actual POS mutations, or exact metadata domain.
-- - Never by broad text matching.

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

  -- Exact metadata detection only.
  v_is_pos_batch :=
    lower(coalesce(new.metadata ->> 'domain', '')) = 'pos'
    or lower(coalesce(new.metadata ->> 'sync_domain', '')) = 'pos'
    or lower(coalesce(new.metadata ->> 'batch_domain', '')) = 'pos'
    or exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = new.id
        and sm.deleted_at is null
        and lower(sm.entity_table) in (
          'sales',
          'sale_items',
          'sale_payments'
        )
    );

  if not v_is_pos_batch then
    return new;
  end if;

  v_result := public.apply_pos_batch_inventory_movements(new.id);

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
is 'Applies POS inventory automatically after POS sync batch completion. Detects POS by exact domain or POS mutation tables only.';

