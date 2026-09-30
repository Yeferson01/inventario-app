begin;

-- The canonical entrypoint must authenticate before dispatching apply_cash or
-- reading a reconciled POS batch. Keep the established return and dispatch.
create or replace function public.process_sync_batch(
  p_sync_batch_id uuid,
  p_mode text default 'validate_only'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid := auth.uid();
  v_mode text := lower(trim(coalesce(p_mode, 'validate_only')));
  v_batch public.sync_batches%rowtype;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if v_mode = 'apply_cash' then
    return public.process_cash_sync_batch(p_sync_batch_id);
  end if;

  if v_mode = 'apply_pos' then
    select batch.* into v_batch
    from public.sync_batches batch
    where batch.id = p_sync_batch_id
      and batch.deleted_at is null;

    if v_batch.id is not null
       and v_batch.metadata ? 'sale_reconciliation_id'
       and v_batch.status in ('partial', 'completed')
    then
      if v_batch.profile_id <> v_profile_id
         and not (
           private.has_business_permission(v_batch.business_id, 'settings.business')
           or private.has_business_permission(v_batch.business_id, 'security_events.read')
         )
      then
        raise exception using
          errcode = '42501',
          message = 'Insufficient permission to process this sync batch';
      end if;

      return jsonb_build_object(
        'sync_batch_id', v_batch.id,
        'mode', v_mode,
        'status', v_batch.status,
        'mutation_count', v_batch.mutation_count,
        'processed_count', 0,
        'applied_count', v_batch.applied_count,
        'skipped_count', v_batch.skipped_count,
        'conflict_count', v_batch.conflict_count,
        'error_count', v_batch.error_count,
        'reconciliation_id', v_batch.metadata ->> 'sale_reconciliation_id',
        'idempotent', true
      );
    end if;
  end if;

  return public.process_sync_batch_base_before_cash(p_sync_batch_id, p_mode);
end;
$$;

-- Supabase's explicit anon default grant is not removed by revoking PUBLIC.
revoke all on function public.process_sync_batch(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch(uuid, text)
  to authenticated, service_role;

-- These SECURITY DEFINER delegates are not client RPCs. The wrapper's owner
-- can call them; authenticated clients must use process_sync_batch instead.
revoke all on function public.process_cash_sync_batch(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.process_cash_sync_batch(uuid)
  to service_role;

revoke all on function public.process_sync_batch_base_before_cash(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.process_sync_batch_base_before_cash(uuid, text)
  to service_role;

commit;
