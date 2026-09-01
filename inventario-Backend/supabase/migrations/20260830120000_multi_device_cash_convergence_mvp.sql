-- Multi-device cash convergence MVP.
--
-- Opening is coordinated on the server so two installations cannot create
-- competing open sessions for the same register. Closing computes expected
-- cash from all synchronized payments associated with the session.

begin;

create or replace function public.open_or_reuse_cash_session(
  p_business_id uuid,
  p_branch_id uuid,
  p_cash_register_id uuid,
  p_opening_amount numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_session public.cash_sessions%rowtype;
  v_reused boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null or p_branch_id is null or p_cash_register_id is null then
    raise exception 'business_id, branch_id and cash_register_id are required';
  end if;

  if p_opening_amount is null or p_opening_amount < 0 then
    raise exception 'opening_amount cannot be negative';
  end if;

  if not private.has_branch_permission(
    p_business_id,
    p_branch_id,
    'cash.open'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Effective permissions do not authorize cash opening';
  end if;

  if not exists (
    select 1
    from public.branches branch
    where branch.id = p_branch_id
      and branch.business_id = p_business_id
      and branch.status = 'active'
      and branch.deleted_at is null
  ) then
    raise exception using errcode = '42501', message = 'Branch is not available';
  end if;

  if not exists (
    select 1
    from public.cash_registers register
    where register.id = p_cash_register_id
      and register.business_id = p_business_id
      and register.branch_id = p_branch_id
      and register.status = 'active'
      and register.deleted_at is null
  ) then
    raise exception using errcode = '42501', message = 'Cash register is not available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cash_session:' || p_cash_register_id::text,
      0
    )
  );

  select session.*
  into v_session
  from public.cash_sessions session
  where session.business_id = p_business_id
    and session.branch_id = p_branch_id
    and session.cash_register_id = p_cash_register_id
    and session.status = 'open'
    and session.deleted_at is null
  order by session.opened_at desc, session.id
  limit 1
  for update;

  if v_session.id is null then
    insert into public.cash_sessions (
      business_id,
      branch_id,
      cash_register_id,
      opened_by,
      opening_amount,
      status,
      opened_at,
      created_by,
      updated_by,
      sync_status
    ) values (
      p_business_id,
      p_branch_id,
      p_cash_register_id,
      v_profile_id,
      p_opening_amount,
      'open',
      statement_timestamp(),
      v_profile_id,
      v_profile_id,
      'synced'
    )
    returning * into v_session;
  else
    v_reused := true;
  end if;

  return jsonb_build_object(
    'cash_session_id', v_session.id,
    'business_id', v_session.business_id,
    'branch_id', v_session.branch_id,
    'cash_register_id', v_session.cash_register_id,
    'opened_by_profile_id', v_session.opened_by,
    'closed_by_profile_id', v_session.closed_by,
    'opened_at', v_session.opened_at,
    'closed_at', v_session.closed_at,
    'opening_cash_amount', v_session.opening_amount,
    'expected_cash_amount', v_session.expected_closing_amount,
    'closing_cash_amount', v_session.actual_closing_amount,
    'difference_amount', v_session.difference_amount,
    'status', v_session.status,
    'version', v_session.version,
    'notes', v_session.notes,
    'created_at', v_session.created_at,
    'updated_at', v_session.updated_at,
    'reused_open_session', v_reused
  );
end;
$$;

create or replace function public.close_cash_session_authoritatively(
  p_business_id uuid,
  p_branch_id uuid,
  p_cash_register_id uuid,
  p_cash_session_id uuid,
  p_actual_closing_amount numeric,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_session public.cash_sessions%rowtype;
  v_expected_amount numeric(14,2);
  v_idempotent boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null
     or p_branch_id is null
     or p_cash_register_id is null
     or p_cash_session_id is null
  then
    raise exception 'business_id, branch_id, cash_register_id and cash_session_id are required';
  end if;

  if p_actual_closing_amount is null or p_actual_closing_amount < 0 then
    raise exception 'actual_closing_amount cannot be negative';
  end if;

  if not private.has_branch_permission(
    p_business_id,
    p_branch_id,
    'cash.close'
  ) then
    raise exception using
      errcode = '42501',
      message = 'Effective permissions do not authorize cash closing';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'cash_session:' || p_cash_register_id::text,
      0
    )
  );

  select session.*
  into v_session
  from public.cash_sessions session
  join public.cash_registers register
    on register.id = session.cash_register_id
   and register.business_id = session.business_id
   and register.branch_id = session.branch_id
   and register.deleted_at is null
  where session.id = p_cash_session_id
    and session.business_id = p_business_id
    and session.branch_id = p_branch_id
    and session.cash_register_id = p_cash_register_id
    and session.deleted_at is null
  for update of session;

  if v_session.id is null then
    raise exception using errcode = '42501', message = 'Cash session is not available';
  end if;

  if v_session.status = 'closed' then
    if v_session.actual_closing_amount is distinct from p_actual_closing_amount then
      raise exception using
        errcode = '23505',
        message = 'Cash session was already closed with another amount';
    end if;
    v_idempotent := true;
  elsif v_session.status <> 'open' then
    raise exception 'Cash session cannot be closed from status %', v_session.status;
  else
    select
      v_session.opening_amount + coalesce(sum(payment.amount), 0)
    into v_expected_amount
    from public.sale_payments payment
    join public.sales sale
      on sale.id = payment.sale_id
     and sale.business_id = payment.business_id
    where sale.business_id = p_business_id
      and sale.branch_id = p_branch_id
      and sale.cash_session_id = p_cash_session_id
      and sale.deleted_at is null
      and payment.deleted_at is null
      and lower(payment.payment_method) = 'cash'
      and lower(payment.status) in ('completed', 'paid', 'approved', 'synced');

    update public.cash_sessions session
    set
      closed_by = v_profile_id,
      closed_at = statement_timestamp(),
      expected_closing_amount = v_expected_amount,
      actual_closing_amount = p_actual_closing_amount,
      difference_amount = p_actual_closing_amount - v_expected_amount,
      status = 'closed',
      notes = coalesce(nullif(btrim(p_notes), ''), session.notes),
      updated_by = v_profile_id,
      sync_status = 'synced'
    where session.id = p_cash_session_id
    returning * into v_session;
  end if;

  return jsonb_build_object(
    'cash_session_id', v_session.id,
    'business_id', v_session.business_id,
    'branch_id', v_session.branch_id,
    'cash_register_id', v_session.cash_register_id,
    'opened_by_profile_id', v_session.opened_by,
    'closed_by_profile_id', v_session.closed_by,
    'opened_at', v_session.opened_at,
    'closed_at', v_session.closed_at,
    'opening_cash_amount', v_session.opening_amount,
    'expected_cash_amount', v_session.expected_closing_amount,
    'closing_cash_amount', v_session.actual_closing_amount,
    'difference_amount', v_session.difference_amount,
    'status', v_session.status,
    'version', v_session.version,
    'notes', v_session.notes,
    'created_at', v_session.created_at,
    'updated_at', v_session.updated_at,
    'idempotent', v_idempotent
  );
end;
$$;

revoke all on function public.open_or_reuse_cash_session(uuid, uuid, uuid, numeric) from public, anon;
revoke all on function public.close_cash_session_authoritatively(uuid, uuid, uuid, uuid, numeric, text) from public, anon;

grant execute on function public.open_or_reuse_cash_session(uuid, uuid, uuid, numeric) to authenticated, service_role;
grant execute on function public.close_cash_session_authoritatively(uuid, uuid, uuid, uuid, numeric, text) to authenticated, service_role;

comment on function public.open_or_reuse_cash_session(uuid, uuid, uuid, numeric)
is 'Atomically opens or reuses the single server-authoritative open session for an authorized cash register.';

comment on function public.close_cash_session_authoritatively(uuid, uuid, uuid, uuid, numeric, text)
is 'Idempotently closes one cash session using expected cash calculated from all synchronized cash payments in that session.';

commit;
