-- 6.18C.38G - Backfill sales.cash_session_id from POS sync payload
--
-- POS upload was applying sales/items/payments and inventory correctly,
-- but sales.cash_session_id could remain null because the apply_pos mapper
-- did not persist that payload field.
--
-- This patch safely updates sales.cash_session_id after a POS batch completes,
-- using sync_mutations.payload ->> 'cash_session_id'.
--
-- It only writes cash_session_id when the referenced cash_session already
-- exists remotely, avoiding FK failures.

create or replace function private.backfill_pos_sales_cash_session_from_sync_batch(
  p_sync_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_updated_count integer := 0;
  v_sales_with_payload integer := 0;
  v_sales_without_remote_cash_session integer := 0;
begin
  select count(*)
  into v_sales_with_payload
  from public.sync_mutations sm
  where sm.sync_batch_id = p_sync_batch_id
    and sm.deleted_at is null
    and lower(sm.entity_table) = 'sales'
    and nullif(sm.payload ->> 'cash_session_id', '') is not null;

  with candidate_sales as (
    select
      sm.entity_id::uuid as sale_id,
      sm.business_id,
      nullif(sm.payload ->> 'cash_session_id', '')::uuid as cash_session_id
    from public.sync_mutations sm
    where sm.sync_batch_id = p_sync_batch_id
      and sm.deleted_at is null
      and lower(sm.entity_table) = 'sales'
      and nullif(sm.payload ->> 'cash_session_id', '') is not null
  ),
  valid_sales as (
    select
      c.sale_id,
      c.cash_session_id
    from candidate_sales c
    join public.cash_sessions cs
      on cs.id = c.cash_session_id
     and cs.business_id = c.business_id
     and cs.deleted_at is null
  ),
  updated_sales as (
    update public.sales s
    set
      cash_session_id = v.cash_session_id,
      updated_at = now()
    from valid_sales v
    where s.id = v.sale_id
      and s.deleted_at is null
      and (
        s.cash_session_id is null
        or s.cash_session_id is distinct from v.cash_session_id
      )
    returning s.id
  )
  select count(*)
  into v_updated_count
  from updated_sales;

  select count(*)
  into v_sales_without_remote_cash_session
  from public.sync_mutations sm
  where sm.sync_batch_id = p_sync_batch_id
    and sm.deleted_at is null
    and lower(sm.entity_table) = 'sales'
    and nullif(sm.payload ->> 'cash_session_id', '') is not null
    and not exists (
      select 1
      from public.cash_sessions cs
      where cs.id = nullif(sm.payload ->> 'cash_session_id', '')::uuid
        and cs.business_id = sm.business_id
        and cs.deleted_at is null
    );

  return jsonb_build_object(
    'sync_batch_id', p_sync_batch_id,
    'sales_with_cash_session_payload', v_sales_with_payload,
    'sales_updated', v_updated_count,
    'sales_without_remote_cash_session', v_sales_without_remote_cash_session
  );
end;
$$;

comment on function private.backfill_pos_sales_cash_session_from_sync_batch(uuid)
is 'Backfills sales.cash_session_id from POS sync mutation payload after cash_sessions are uploaded.';


create or replace function private.backfill_pos_sales_cash_session_after_batch_completed()
returns trigger
language plpgsql
security definer
set search_path = public, private, extensions
as $$
declare
  v_is_pos_batch boolean := false;
  v_result jsonb;
begin
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

  v_is_pos_batch :=
    lower(coalesce(new.metadata ->> 'domain', '')) = 'pos'
    or lower(coalesce(new.metadata ->> 'sync_domain', '')) = 'pos'
    or lower(coalesce(new.metadata ->> 'batch_domain', '')) = 'pos'
    or exists (
      select 1
      from public.sync_mutations sm
      where sm.sync_batch_id = new.id
        and sm.deleted_at is null
        and lower(sm.entity_table) = 'sales'
    );

  if not v_is_pos_batch then
    return new;
  end if;

  v_result := private.backfill_pos_sales_cash_session_from_sync_batch(new.id);

  update public.sync_batches sb
  set
    metadata =
      coalesce(sb.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'pos_cash_session_backfill', jsonb_build_object(
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

comment on function private.backfill_pos_sales_cash_session_after_batch_completed()
is 'After a POS sync batch completes, backfills sales.cash_session_id from sync mutation payload.';


drop trigger if exists trg_sync_batches_backfill_pos_cash_session_after_completed
on public.sync_batches;

create trigger trg_sync_batches_backfill_pos_cash_session_after_completed
after update of status on public.sync_batches
for each row
when (
  old.status is distinct from new.status
  and new.status = 'completed'
)
execute function private.backfill_pos_sales_cash_session_after_batch_completed();
