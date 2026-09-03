begin;

-- The permission is intentionally narrower than sales.create or cash.adjust.
insert into public.permissions (key, description)
values (
  'sales.reconcile_stale_cash_session',
  'Reconcile a real rejected Sale into an explicitly selected open cash session.'
)
on conflict (key) do update
set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
join public.permissions permission
  on permission.key = 'sales.reconcile_stale_cash_session'
where role.business_id is null
  and lower(role.name) in ('owner', 'admin')
  and role.deleted_at is null
on conflict (role_id, permission_id) do nothing;

create table if not exists public.sale_reconciliations (
  id uuid primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  sale_id uuid not null,
  original_cash_session_id uuid not null references public.cash_sessions(id) on delete restrict,
  destination_cash_session_id uuid not null references public.cash_sessions(id) on delete restrict,
  sync_conflict_id uuid not null references public.sync_conflicts(id) on delete restrict,
  original_sync_batch_id uuid not null references public.sync_batches(id) on delete restrict,
  original_sync_mutation_id uuid not null references public.sync_mutations(id) on delete restrict,
  seller_profile_id uuid not null references public.profiles(id) on delete restrict,
  original_app_device_id uuid not null references public.app_devices(id) on delete restrict,
  original_installation_id text,
  reconciled_by uuid not null references public.profiles(id) on delete restrict,
  reconciler_app_device_id uuid not null references public.app_devices(id) on delete restrict,
  original_sale_created_at timestamp without time zone not null,
  original_payment_timestamps jsonb not null default '[]'::jsonb,
  cash_treatment text not null,
  cash_reconciled_total numeric(14,2) not null default 0,
  cash_adjustment_total numeric(14,2) not null default 0,
  reason text not null,
  payload_fingerprint text not null,
  idempotency_key text not null,
  reconciled_at timestamp without time zone not null default statement_timestamp(),
  status text not null default 'processing',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamp without time zone not null default statement_timestamp(),
  updated_at timestamp without time zone not null default statement_timestamp(),
  deleted_at timestamp without time zone,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,
  version integer not null default 1,
  sync_status text not null default 'synced',
  constraint sale_reconciliations_sale_unique unique (business_id, sale_id),
  constraint sale_reconciliations_idempotency_unique unique (business_id, idempotency_key),
  constraint sale_reconciliations_treatment_check check (
    cash_treatment in (
      'not_included_in_destination_opening',
      'already_included_in_destination_opening'
    )
  ),
  constraint sale_reconciliations_status_check check (
    status in ('processing', 'completed')
  ),
  constraint sale_reconciliations_cash_total_non_negative check (
    cash_reconciled_total >= 0
  ),
  constraint sale_reconciliations_adjustment_non_positive check (
    cash_adjustment_total <= 0
  ),
  constraint sale_reconciliations_cash_treatment_amount_check check (
    cash_adjustment_total = case
      when cash_treatment = 'already_included_in_destination_opening'
        then -cash_reconciled_total
      else 0
    end
  ),
  constraint sale_reconciliations_reason_not_blank check (length(btrim(reason)) > 0),
  constraint sale_reconciliations_fingerprint_not_blank check (length(btrim(payload_fingerprint)) > 0),
  constraint sale_reconciliations_idempotency_not_blank check (length(btrim(idempotency_key)) > 0),
  constraint sale_reconciliations_payment_timestamps_array check (
    jsonb_typeof(original_payment_timestamps) = 'array'
  ),
  constraint sale_reconciliations_metadata_object check (
    jsonb_typeof(metadata) = 'object'
  )
);

create index if not exists sale_reconciliations_scope_idx
on public.sale_reconciliations (business_id, branch_id, reconciled_at desc)
where deleted_at is null;

create table if not exists public.cash_session_adjustments (
  id uuid primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  cash_session_id uuid not null references public.cash_sessions(id) on delete restrict,
  adjustment_type text not null,
  amount numeric(14,2) not null,
  currency text not null default 'COP',
  source_type text not null,
  source_id uuid not null,
  reconciliation_id uuid not null references public.sale_reconciliations(id) on delete restrict,
  reason text not null,
  occurred_at timestamp without time zone not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamp without time zone not null default statement_timestamp(),
  updated_at timestamp without time zone not null default statement_timestamp(),
  deleted_at timestamp without time zone,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,
  metadata jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  version integer not null default 1,
  sync_status text not null default 'synced',
  constraint cash_session_adjustments_reconciliation_unique unique (reconciliation_id),
  constraint cash_session_adjustments_idempotency_unique unique (business_id, idempotency_key),
  constraint cash_session_adjustments_type_check check (
    adjustment_type = 'reconciled_sale_already_in_opening'
  ),
  constraint cash_session_adjustments_amount_check check (amount < 0),
  constraint cash_session_adjustments_source_check check (source_type = 'sale_reconciliation'),
  constraint cash_session_adjustments_currency_not_blank check (length(btrim(currency)) > 0),
  constraint cash_session_adjustments_reason_not_blank check (length(btrim(reason)) > 0),
  constraint cash_session_adjustments_idempotency_not_blank check (length(btrim(idempotency_key)) > 0),
  constraint cash_session_adjustments_metadata_object check (jsonb_typeof(metadata) = 'object'),
  constraint cash_session_adjustments_version_positive check (version >= 1),
  constraint cash_session_adjustments_sync_status_check check (
    sync_status in ('synced', 'pending', 'conflict', 'error')
  )
);

create index if not exists cash_session_adjustments_session_idx
on public.cash_session_adjustments (cash_session_id, occurred_at, id)
where deleted_at is null;

alter table public.sale_reconciliations enable row level security;
alter table public.cash_session_adjustments enable row level security;

drop policy if exists sale_reconciliations_select_authorized
on public.sale_reconciliations;
create policy sale_reconciliations_select_authorized
on public.sale_reconciliations
for select to authenticated
using (
  private.has_branch_access(business_id, branch_id)
  and (
    private.has_branch_permission(
      business_id,
      branch_id,
      'sales.reconcile_stale_cash_session'
    )
    or private.has_branch_permission(business_id, branch_id, 'audit.read')
  )
);

drop policy if exists cash_session_adjustments_select_authorized
on public.cash_session_adjustments;
create policy cash_session_adjustments_select_authorized
on public.cash_session_adjustments
for select to authenticated
using (
  private.has_branch_access(business_id, branch_id)
  and (
    private.has_branch_permission(business_id, branch_id, 'cash.read')
    or private.has_branch_permission(
      business_id,
      branch_id,
      'sales.reconcile_stale_cash_session'
    )
  )
);

revoke all on table public.sale_reconciliations from public, anon, authenticated;
revoke all on table public.cash_session_adjustments from public, anon, authenticated;
grant select on table public.sale_reconciliations to authenticated;
grant select on table public.cash_session_adjustments to authenticated;
grant all on table public.sale_reconciliations to service_role;
grant all on table public.cash_session_adjustments to service_role;

alter table public.sync_conflicts
  drop constraint if exists sync_conflicts_resolution_strategy_check;
alter table public.sync_conflicts
  add constraint sync_conflicts_resolution_strategy_check
  check (
    resolution_strategy in (
      'server_wins',
      'client_retry',
      'manual_review',
      'manual_resolution',
      'ignored',
      'reconcile_to_open_cash_session'
    )
  )
  not valid;
alter table public.sync_conflicts
  validate constraint sync_conflicts_resolution_strategy_check;

create or replace function private.intentional_stale_sale_reconciliation_result(
  p_reconciliation_id uuid,
  p_idempotent boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'reconciliation_id', reconciliation.id,
    'business_id', reconciliation.business_id,
    'branch_id', reconciliation.branch_id,
    'sale_id', reconciliation.sale_id,
    'cash_register_id', reconciliation.cash_register_id,
    'original_cash_session_id', reconciliation.original_cash_session_id,
    'destination_cash_session_id', reconciliation.destination_cash_session_id,
    'sync_conflict_id', reconciliation.sync_conflict_id,
    'cash_treatment', reconciliation.cash_treatment,
    'cash_reconciled_total', reconciliation.cash_reconciled_total,
    'cash_adjustment_total', reconciliation.cash_adjustment_total,
    'cash_adjustment_amount', coalesce(adjustment.amount, 0),
    'cash_adjustment_id', adjustment.id,
    'original_sale_created_at', reconciliation.original_sale_created_at,
    'reconciled_at', reconciliation.reconciled_at,
    'status', reconciliation.status,
    'idempotent', p_idempotent,
    'projected_expected_cash', (
      select session.opening_amount
        + coalesce((
            select sum(payment.amount)
            from public.sale_payments payment
            join public.sales sale
              on sale.id = payment.sale_id
             and sale.business_id = payment.business_id
            where sale.business_id = reconciliation.business_id
              and sale.branch_id = reconciliation.branch_id
              and sale.cash_session_id = reconciliation.destination_cash_session_id
              and sale.deleted_at is null
              and payment.deleted_at is null
              and lower(payment.payment_method) = 'cash'
              and lower(payment.status) in ('completed', 'paid', 'approved', 'synced')
          ), 0)
        + coalesce((
            select sum(session_adjustment.amount)
            from public.cash_session_adjustments session_adjustment
            where session_adjustment.cash_session_id = reconciliation.destination_cash_session_id
              and session_adjustment.business_id = reconciliation.business_id
              and session_adjustment.branch_id = reconciliation.branch_id
              and session_adjustment.adjustment_type = 'reconciled_sale_already_in_opening'
              and session_adjustment.deleted_at is null
          ), 0)
      from public.cash_sessions session
      where session.id = reconciliation.destination_cash_session_id
    )
  )
  from public.sale_reconciliations reconciliation
  left join public.cash_session_adjustments adjustment
    on adjustment.reconciliation_id = reconciliation.id
   and adjustment.deleted_at is null
  where reconciliation.id = p_reconciliation_id
    and reconciliation.deleted_at is null;
$$;

create or replace function public.reconcile_rejected_sale_to_open_cash_session(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_sale_id uuid,
  p_sync_conflict_id uuid,
  p_destination_cash_session_id uuid,
  p_reconciliation_id uuid,
  p_idempotency_key text,
  p_reason text,
  p_cash_treatment text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_existing public.sale_reconciliations%rowtype;
  v_conflict public.sync_conflicts%rowtype;
  v_sale_mutation public.sync_mutations%rowtype;
  v_original_batch public.sync_batches%rowtype;
  v_original_device public.app_devices%rowtype;
  v_reconciler_device public.app_devices%rowtype;
  v_original_session public.cash_sessions%rowtype;
  v_destination_session public.cash_sessions%rowtype;
  v_sale_payload jsonb;
  v_items_payload jsonb;
  v_payments_payload jsonb;
  v_fingerprint text;
  v_sale_created_at timestamp without time zone;
  v_customer_id uuid;
  v_original_session_id uuid;
  v_cash_register_id uuid;
  v_cash_total numeric(14,2) := 0;
  v_payment_timestamps jsonb := '[]'::jsonb;
  v_child record;
  v_payload jsonb;
  v_product_id uuid;
  v_item_id uuid;
  v_payment_id uuid;
  v_quantity integer;
  v_item_created_at timestamp without time zone;
  v_payment_created_at timestamp without time zone;
  v_adjustment_id uuid;
  v_adjustment_amount numeric(14,2) := 0;
  v_sale_metadata jsonb;
  v_reconciliation_metadata jsonb;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;

  if p_business_id is null
     or p_branch_id is null
     or p_app_device_id is null
     or p_sale_id is null
     or p_sync_conflict_id is null
     or p_destination_cash_session_id is null
     or p_reconciliation_id is null
  then
    raise exception using errcode = '22023', message = 'All reconciliation identifiers are required';
  end if;

  if nullif(btrim(coalesce(p_idempotency_key, '')), '') is null
     or nullif(btrim(coalesce(p_reason, '')), '') is null
  then
    raise exception using errcode = '22023', message = 'idempotency_key and reason are required';
  end if;

  if p_cash_treatment not in (
    'not_included_in_destination_opening',
    'already_included_in_destination_opening'
  ) then
    raise exception using errcode = '22023', message = 'Explicit supported cash_treatment is required';
  end if;

  if not private.has_branch_access(p_business_id, p_branch_id)
     or not private.has_branch_permission(
       p_business_id,
       p_branch_id,
       'sales.reconcile_stale_cash_session'
     )
     or not private.has_branch_permission(
       p_business_id,
       p_branch_id,
       'sales.create'
     )
  then
    raise exception using errcode = '42501', message = 'Stale Sale reconciliation is not authorized';
  end if;

  select device.*
  into v_reconciler_device
  from public.app_devices device
  where device.id = p_app_device_id
    and device.business_id = p_business_id
    and device.profile_id = v_profile_id
    and device.branch_id = p_branch_id
    and device.status = 'active'
    and device.deleted_at is null;

  if v_reconciler_device.id is null then
    raise exception using errcode = '42501', message = 'app_device is not active for this profile and branch';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'sale_reconciliation:' || p_business_id::text || ':' || p_sale_id::text,
      0
    )
  );

  select reconciliation.*
  into v_existing
  from public.sale_reconciliations reconciliation
  where reconciliation.business_id = p_business_id
    and reconciliation.sale_id = p_sale_id
    and reconciliation.deleted_at is null
  for update;

  if v_existing.id is not null then
    if v_existing.id <> p_reconciliation_id
       or v_existing.idempotency_key <> btrim(p_idempotency_key)
       or v_existing.sync_conflict_id <> p_sync_conflict_id
       or v_existing.destination_cash_session_id <> p_destination_cash_session_id
       or v_existing.cash_treatment <> p_cash_treatment
    then
      raise exception using
        errcode = '23505',
        message = 'Sale was already reconciled with another identity, destination, or cash treatment';
    end if;

    if v_existing.status <> 'completed'
       or not exists (
         select 1 from public.sales sale
         where sale.id = p_sale_id
           and sale.business_id = p_business_id
           and sale.branch_id = p_branch_id
           and sale.cash_session_id = p_destination_cash_session_id
           and sale.deleted_at is null
       )
    then
      raise exception 'Existing Sale reconciliation is incomplete';
    end if;

    return private.intentional_stale_sale_reconciliation_result(
      v_existing.id,
      true
    );
  end if;

  select conflict.*
  into v_conflict
  from public.sync_conflicts conflict
  where conflict.id = p_sync_conflict_id
  for update;

  if v_conflict.id is null
     or v_conflict.business_id <> p_business_id
     or v_conflict.branch_id is distinct from p_branch_id
     or v_conflict.entity_table <> 'sales'
     or v_conflict.entity_id <> p_sale_id
     or v_conflict.deleted_at is not null
     or v_conflict.status <> 'open'
     or v_conflict.metadata ->> 'rule' <> 'sale_cash_session_invalid'
     or v_conflict.metadata ->> 'reason' <> 'closed'
  then
    raise exception 'Expected open sale_cash_session_invalid/closed conflict was not found';
  end if;

  select mutation.*
  into v_sale_mutation
  from public.sync_mutations mutation
  where mutation.id = v_conflict.sync_mutation_id
  for update;

  if v_sale_mutation.id is null
     or v_sale_mutation.business_id <> p_business_id
     or v_sale_mutation.branch_id is distinct from p_branch_id
     or v_sale_mutation.entity_table <> 'sales'
     or v_sale_mutation.entity_id <> p_sale_id
     or v_sale_mutation.operation not in ('insert', 'upsert')
     or v_sale_mutation.deleted_at is not null
  then
    raise exception 'Original Sale mutation is missing or inconsistent';
  end if;

  select batch.* into v_original_batch
  from public.sync_batches batch
  where batch.id = v_sale_mutation.sync_batch_id
    and batch.business_id = p_business_id
    and batch.branch_id is not distinct from p_branch_id
    and batch.deleted_at is null;

  select device.* into v_original_device
  from public.app_devices device
  where device.id = v_sale_mutation.app_device_id
    and device.business_id = p_business_id;

  if v_original_batch.id is null or v_original_device.id is null then
    raise exception 'Original sync batch or app_device is missing';
  end if;

  v_sale_payload := coalesce(v_sale_mutation.payload, '{}'::jsonb);
  begin
    v_original_session_id := nullif(v_sale_payload ->> 'cash_session_id', '')::uuid;
    v_cash_register_id := nullif(v_sale_payload ->> 'cash_register_id', '')::uuid;
    v_customer_id := nullif(v_sale_payload ->> 'customer_id', '')::uuid;
    v_sale_created_at := coalesce(
      nullif(v_sale_payload ->> 'created_at', '')::timestamptz at time zone 'UTC',
      v_sale_mutation.created_at
    );
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'Original Sale payload contains invalid identifiers or timestamps';
  end;

  if v_original_session_id is null or v_cash_register_id is null then
    raise exception 'Original Sale cash session and register are required';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mutation_id', mutation.id,
      'entity_id', mutation.entity_id,
      'client_sequence', mutation.client_sequence,
      'payload', mutation.payload
    ) order by mutation.client_sequence, mutation.id
  ), '[]'::jsonb)
  into v_items_payload
  from public.sync_mutations mutation
  where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
    and mutation.business_id = p_business_id
    and mutation.branch_id is not distinct from p_branch_id
    and mutation.entity_table = 'sale_items'
    and mutation.payload ->> 'sale_id' = p_sale_id::text
    and mutation.deleted_at is null;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'mutation_id', mutation.id,
      'entity_id', mutation.entity_id,
      'client_sequence', mutation.client_sequence,
      'payload', mutation.payload
    ) order by mutation.client_sequence, mutation.id
  ), '[]'::jsonb)
  into v_payments_payload
  from public.sync_mutations mutation
  where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
    and mutation.business_id = p_business_id
    and mutation.branch_id is not distinct from p_branch_id
    and mutation.entity_table = 'sale_payments'
    and mutation.payload ->> 'sale_id' = p_sale_id::text
    and mutation.deleted_at is null;

  if jsonb_array_length(v_items_payload) = 0
     or jsonb_array_length(v_payments_payload) = 0
  then
    raise exception 'Original Sale items and payments are required';
  end if;

  v_fingerprint := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'sale', v_sale_payload,
          'items', v_items_payload,
          'payments', v_payments_payload
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  if exists (
       select 1 from public.sales sale where sale.id = p_sale_id
     )
     or exists (
       select 1 from public.sale_items item
       where item.business_id = p_business_id and item.sale_id = p_sale_id
     )
     or exists (
       select 1 from public.sale_payments payment
       where payment.business_id = p_business_id and payment.sale_id = p_sale_id
     )
     or exists (
       select 1 from public.inventory_movements movement
       where movement.business_id = p_business_id
         and movement.branch_id = p_branch_id
         and movement.source_type = 'sale'
         and movement.source_id = p_sale_id
     )
  then
    raise exception 'Remote Sale evidence already exists outside this reconciliation';
  end if;

  if v_customer_id is not null and not exists (
    select 1 from public.customers customer
    where customer.id = v_customer_id
      and customer.business_id = p_business_id
      and customer.deleted_at is null
  ) then
    raise exception 'Original customer is outside the Sale business';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cash_session:' || v_cash_register_id::text, 0)
  );

  select session.* into v_original_session
  from public.cash_sessions session
  where session.id = v_original_session_id
  for update;

  select session.* into v_destination_session
  from public.cash_sessions session
  where session.id = p_destination_cash_session_id
  for update;

  if v_original_session.id is null
     or v_original_session.business_id <> p_business_id
     or v_original_session.branch_id <> p_branch_id
     or v_original_session.cash_register_id <> v_cash_register_id
     or v_original_session.status <> 'closed'
     or v_original_session.deleted_at is not null
  then
    raise exception 'Original closed cash session is not valid for reconciliation';
  end if;

  if v_destination_session.id is null
     or v_destination_session.id = v_original_session.id
     or v_destination_session.business_id <> p_business_id
     or v_destination_session.branch_id <> p_branch_id
     or v_destination_session.cash_register_id <> v_cash_register_id
     or v_destination_session.status <> 'open'
     or v_destination_session.deleted_at is not null
  then
    raise exception 'destination_cash_session_required';
  end if;

  v_reconciliation_metadata := jsonb_build_object(
    'reconciliation_id', p_reconciliation_id,
    'original_cash_session_id', v_original_session_id,
    'destination_cash_session_id', p_destination_cash_session_id,
    'cash_treatment', p_cash_treatment,
    'reconciliation_reason', btrim(p_reason),
    'original_sync_conflict_id', p_sync_conflict_id,
    'original_sync_batch_id', v_original_batch.id,
    'original_sync_mutation_id', v_sale_mutation.id,
    'original_app_device_id', v_sale_mutation.app_device_id,
    'original_installation_id', v_original_device.installation_id,
    'reconciled_by', v_profile_id,
    'reconciler_app_device_id', p_app_device_id,
    'reconciled_at', statement_timestamp()
  );

  for v_child in
    select mutation.*
    from public.sync_mutations mutation
    where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
      and mutation.entity_table = 'sale_payments'
      and mutation.payload ->> 'sale_id' = p_sale_id::text
      and mutation.deleted_at is null
    order by mutation.client_sequence, mutation.id
  loop
    v_payload := coalesce(v_child.payload, '{}'::jsonb);
    begin
      v_payment_created_at := coalesce(
        nullif(v_payload ->> 'paid_at', '')::timestamptz at time zone 'UTC',
        nullif(v_payload ->> 'created_at', '')::timestamptz at time zone 'UTC',
        v_sale_created_at
      );
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Original Sale payment contains an invalid timestamp';
    end;
    v_payment_timestamps := v_payment_timestamps || jsonb_build_array(
      jsonb_build_object(
        'payment_id', v_child.entity_id,
        'payment_method', lower(coalesce(v_payload ->> 'payment_method', 'cash')),
        'paid_at', v_payment_created_at
      )
    );
    if lower(coalesce(v_payload ->> 'payment_method', 'cash')) = 'cash'
       and lower(coalesce(v_payload ->> 'status', 'completed')) in (
         'completed', 'paid', 'approved', 'synced'
       )
    then
      v_cash_total := v_cash_total
        + coalesce(nullif(v_payload ->> 'amount', '')::numeric, 0);
    end if;
  end loop;

  if v_cash_total < 0 then
    raise exception 'Original cash payment total cannot be negative';
  end if;

  v_adjustment_amount := case
    when p_cash_treatment = 'already_included_in_destination_opening'
      then -v_cash_total
    else 0
  end;

  insert into public.sale_reconciliations (
    id, business_id, branch_id, cash_register_id, sale_id,
    original_cash_session_id, destination_cash_session_id,
    sync_conflict_id, original_sync_batch_id, original_sync_mutation_id,
    seller_profile_id, original_app_device_id, original_installation_id,
    reconciled_by, reconciler_app_device_id, original_sale_created_at,
    original_payment_timestamps, cash_treatment, cash_reconciled_total,
    cash_adjustment_total,
    reason, payload_fingerprint, idempotency_key, status, metadata,
    created_by, updated_by
  ) values (
    p_reconciliation_id, p_business_id, p_branch_id, v_cash_register_id,
    p_sale_id, v_original_session_id, p_destination_cash_session_id,
    p_sync_conflict_id, v_original_batch.id, v_sale_mutation.id,
    v_sale_mutation.profile_id, v_sale_mutation.app_device_id,
    v_original_device.installation_id, v_profile_id, p_app_device_id,
    v_sale_created_at, v_payment_timestamps, p_cash_treatment, v_cash_total,
    v_adjustment_amount,
    btrim(p_reason), v_fingerprint, btrim(p_idempotency_key), 'processing',
    v_reconciliation_metadata, v_profile_id, v_profile_id
  );

  v_sale_metadata := coalesce(v_sale_payload -> 'metadata', '{}'::jsonb)
    || v_reconciliation_metadata;

  insert into public.sales (
    id, business_id, branch_id, user_id, customer_id, cash_session_id,
    device_id, subtotal, discount_total, tax_total, total,
    payment_method, status, paid_total, change_amount, currency,
    receipt_number, idempotency_key, created_at, updated_at,
    created_by, updated_by, sync_status, metadata
  ) values (
    p_sale_id, p_business_id, p_branch_id, v_sale_mutation.profile_id,
    v_customer_id, p_destination_cash_session_id, v_sale_mutation.app_device_id,
    coalesce(nullif(v_sale_payload ->> 'subtotal', '')::numeric, 0),
    coalesce(nullif(v_sale_payload ->> 'discount_total', '')::numeric, 0),
    coalesce(nullif(v_sale_payload ->> 'tax_total', '')::numeric, 0),
    coalesce(nullif(v_sale_payload ->> 'total', '')::numeric, 0),
    nullif(v_sale_payload ->> 'payment_method', ''),
    coalesce(nullif(v_sale_payload ->> 'status', ''), 'completed'),
    coalesce(nullif(v_sale_payload ->> 'paid_total', '')::numeric,
      coalesce(nullif(v_sale_payload ->> 'total', '')::numeric, 0)),
    coalesce(nullif(v_sale_payload ->> 'change_amount', '')::numeric, 0),
    coalesce(nullif(v_sale_payload ->> 'currency', ''), 'COP'),
    nullif(v_sale_payload ->> 'receipt_number', ''),
    coalesce(nullif(v_sale_payload ->> 'idempotency_key', ''), v_sale_mutation.idempotency_key),
    v_sale_created_at, statement_timestamp(), v_sale_mutation.profile_id,
    v_profile_id, 'synced', v_sale_metadata
  );

  for v_child in
    select mutation.*
    from public.sync_mutations mutation
    where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
      and mutation.entity_table = 'sale_items'
      and mutation.payload ->> 'sale_id' = p_sale_id::text
      and mutation.deleted_at is null
    order by mutation.client_sequence, mutation.id
  loop
    v_payload := coalesce(v_child.payload, '{}'::jsonb);
    begin
      v_item_id := v_child.entity_id;
      v_product_id := nullif(v_payload ->> 'product_id', '')::uuid;
      v_quantity := nullif(v_payload ->> 'quantity', '')::integer;
      v_item_created_at := coalesce(
        nullif(v_payload ->> 'created_at', '')::timestamptz at time zone 'UTC',
        v_sale_created_at
      );
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Original Sale item contains invalid values';
    end;
    if v_product_id is null or v_quantity is null or v_quantity <= 0
       or not exists (
         select 1 from public.products product
         where product.id = v_product_id
           and product.business_id = p_business_id
           and product.deleted_at is null
       )
    then
      raise exception 'Original Sale item product or quantity is invalid';
    end if;

    insert into public.sale_items (
      id, business_id, sale_id, product_id,
      product_name_snapshot, barcode_snapshot, quantity, unit_price,
      subtotal, discount_amount, tax_amount, total, created_at,
      created_by, updated_by, sync_status, idempotency_key, metadata
    ) values (
      v_item_id, p_business_id, p_sale_id, v_product_id,
      nullif(v_payload ->> 'product_name_snapshot', ''),
      nullif(v_payload ->> 'barcode_snapshot', ''),
      v_quantity,
      coalesce(nullif(v_payload ->> 'unit_price', '')::numeric, 0),
      coalesce(nullif(v_payload ->> 'subtotal', '')::numeric, 0),
      coalesce(nullif(v_payload ->> 'discount_amount', '')::numeric, 0),
      coalesce(nullif(v_payload ->> 'tax_amount', '')::numeric, 0),
      coalesce(nullif(v_payload ->> 'total', '')::numeric,
        coalesce(nullif(v_payload ->> 'subtotal', '')::numeric, 0)),
      v_item_created_at, v_sale_mutation.profile_id, v_profile_id, 'synced',
      coalesce(nullif(v_payload ->> 'idempotency_key', ''), v_child.idempotency_key),
      coalesce(v_payload -> 'metadata', '{}'::jsonb)
        || v_reconciliation_metadata
        || jsonb_build_object('original_sync_mutation_id', v_child.id)
    );

    perform public.create_inventory_movement(
      p_business_id := p_business_id,
      p_branch_id := p_branch_id,
      p_product_id := v_product_id,
      p_movement_type := 'sale',
      p_quantity_change := -v_quantity,
      p_unit_cost := null,
      p_source_type := 'sale',
      p_source_id := p_sale_id,
      p_reference_type := 'sale',
      p_reference_id := p_sale_id,
      p_notes := 'Inventory materialized by stale Sale reconciliation',
      p_idempotency_key := 'sale:' || p_sale_id::text || ':item:' || v_item_id::text,
      p_occurred_at := v_item_created_at at time zone 'UTC',
      p_metadata := v_reconciliation_metadata
        || jsonb_build_object(
          'sale_item_id', v_item_id,
          'original_sync_mutation_id', v_child.id
        )
    );
  end loop;

  for v_child in
    select mutation.*
    from public.sync_mutations mutation
    where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
      and mutation.entity_table = 'sale_payments'
      and mutation.payload ->> 'sale_id' = p_sale_id::text
      and mutation.deleted_at is null
    order by mutation.client_sequence, mutation.id
  loop
    v_payload := coalesce(v_child.payload, '{}'::jsonb);
    begin
      v_payment_id := v_child.entity_id;
      v_payment_created_at := coalesce(
        nullif(v_payload ->> 'paid_at', '')::timestamptz at time zone 'UTC',
        nullif(v_payload ->> 'created_at', '')::timestamptz at time zone 'UTC',
        v_sale_created_at
      );
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Original Sale payment contains invalid values';
    end;

    insert into public.sale_payments (
      id, business_id, sale_id, payment_method, amount, currency,
      reference, reference_number, status, paid_at, created_at, updated_at,
      created_by, updated_by, sync_status, idempotency_key, metadata
    ) values (
      v_payment_id, p_business_id, p_sale_id,
      coalesce(nullif(v_payload ->> 'payment_method', ''), 'cash'),
      coalesce(nullif(v_payload ->> 'amount', '')::numeric, 0),
      coalesce(nullif(v_payload ->> 'currency', ''), 'COP'),
      coalesce(nullif(v_payload ->> 'reference', ''), nullif(v_payload ->> 'reference_number', '')),
      coalesce(nullif(v_payload ->> 'reference_number', ''), nullif(v_payload ->> 'reference', '')),
      coalesce(nullif(v_payload ->> 'status', ''), 'completed'),
      v_payment_created_at, v_payment_created_at, statement_timestamp(),
      v_sale_mutation.profile_id, v_profile_id, 'synced',
      coalesce(nullif(v_payload ->> 'idempotency_key', ''), v_child.idempotency_key),
      coalesce(v_payload -> 'metadata', '{}'::jsonb)
        || v_reconciliation_metadata
        || jsonb_build_object('original_sync_mutation_id', v_child.id)
    );
  end loop;

  if p_cash_treatment = 'already_included_in_destination_opening'
     and v_cash_total > 0
  then
    v_adjustment_id := extensions.gen_random_uuid();
    insert into public.cash_session_adjustments (
      id, business_id, branch_id, cash_register_id, cash_session_id,
      adjustment_type, amount, currency, source_type, source_id,
      reconciliation_id, reason, occurred_at, created_by, updated_by,
      metadata, idempotency_key
    ) values (
      v_adjustment_id, p_business_id, p_branch_id, v_cash_register_id,
      p_destination_cash_session_id, 'reconciled_sale_already_in_opening',
      v_adjustment_amount, coalesce(nullif(v_sale_payload ->> 'currency', ''), 'COP'),
      'sale_reconciliation', p_reconciliation_id, p_reconciliation_id,
      btrim(p_reason), v_sale_created_at, v_profile_id, v_profile_id,
      v_reconciliation_metadata || jsonb_build_object('cash_reconciled_total', v_cash_total),
      btrim(p_idempotency_key) || ':cash-adjustment'
    );
  end if;

  update public.sync_mutations mutation
  set
    status = 'skipped',
    server_processed_at = statement_timestamp(),
    error_code = 'superseded_by_sale_reconciliation',
    error_message = 'Original rejected mutation was superseded by an intentional Sale reconciliation.',
    metadata = coalesce(mutation.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'superseded_by_sale_reconciliation', p_reconciliation_id,
        'cash_treatment', p_cash_treatment,
        'superseded_at', statement_timestamp()
      ),
    updated_at = statement_timestamp(),
    updated_by = v_profile_id
  where mutation.sync_batch_id = v_sale_mutation.sync_batch_id
    and mutation.deleted_at is null
    and (
      (mutation.entity_table = 'sales' and mutation.entity_id = p_sale_id)
      or (
        mutation.entity_table in ('sale_items', 'sale_payments')
        and mutation.payload ->> 'sale_id' = p_sale_id::text
      )
    );

  update public.sync_conflicts conflict
  set
    status = 'resolved',
    resolved_at = statement_timestamp(),
    resolved_by = v_profile_id,
    resolution_strategy = 'reconcile_to_open_cash_session',
    resolution_notes = btrim(p_reason),
    resolved_payload = jsonb_build_object(
      'reconciliation_id', p_reconciliation_id,
      'sale_id', p_sale_id,
      'destination_cash_session_id', p_destination_cash_session_id,
      'cash_treatment', p_cash_treatment,
      'cash_reconciled_total', v_cash_total,
      'cash_adjustment_amount', v_adjustment_amount
    ),
    metadata = coalesce(conflict.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'sale_reconciliation_id', p_reconciliation_id,
        'cash_treatment', p_cash_treatment,
        'destination_cash_session_id', p_destination_cash_session_id,
        'resolved_at', statement_timestamp()
      ),
    updated_at = statement_timestamp(),
    updated_by = v_profile_id
  where conflict.id = p_sync_conflict_id;

  update public.sync_batches batch
  set metadata = coalesce(batch.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'sale_reconciliation_id', p_reconciliation_id,
        'reconciled_sale_id', p_sale_id,
        'cash_treatment', p_cash_treatment
      ),
      updated_at = statement_timestamp(),
      updated_by = v_profile_id
  where batch.id = v_sale_mutation.sync_batch_id;

  perform private.recalculate_sync_batch_counts(v_sale_mutation.sync_batch_id);
  perform private.finalize_sync_batch_from_counts(v_sale_mutation.sync_batch_id);

  update public.sale_reconciliations reconciliation
  set
    status = 'completed',
    reconciled_at = statement_timestamp(),
    updated_at = statement_timestamp(),
    updated_by = v_profile_id,
    metadata = reconciliation.metadata || jsonb_build_object(
      'cash_reconciled_total', v_cash_total,
      'cash_adjustment_id', v_adjustment_id,
      'cash_adjustment_amount', v_adjustment_amount,
      'completed_at', statement_timestamp()
    )
  where reconciliation.id = p_reconciliation_id;

  return private.intentional_stale_sale_reconciliation_result(
    p_reconciliation_id,
    false
  );
end;
$$;

-- Closing remains server authoritative and now includes the restricted ledger.
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
  v_cash_payments numeric(14,2) := 0;
  v_cash_adjustments numeric(14,2) := 0;
  v_expected_amount numeric(14,2);
  v_idempotent boolean := false;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_business_id is null or p_branch_id is null
     or p_cash_register_id is null or p_cash_session_id is null
  then
    raise exception 'business_id, branch_id, cash_register_id and cash_session_id are required';
  end if;
  if p_actual_closing_amount is null or p_actual_closing_amount < 0 then
    raise exception 'actual_closing_amount cannot be negative';
  end if;
  if not private.has_branch_permission(p_business_id, p_branch_id, 'cash.close') then
    raise exception using errcode = '42501', message = 'Effective permissions do not authorize cash closing';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('cash_session:' || p_cash_register_id::text, 0)
  );

  select session.* into v_session
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
      raise exception using errcode = '23505', message = 'Cash session was already closed with another amount';
    end if;
    v_idempotent := true;
  elsif v_session.status <> 'open' then
    raise exception 'Cash session cannot be closed from status %', v_session.status;
  else
    select coalesce(sum(payment.amount), 0)
    into v_cash_payments
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

    select coalesce(sum(adjustment.amount), 0)
    into v_cash_adjustments
    from public.cash_session_adjustments adjustment
    where adjustment.business_id = p_business_id
      and adjustment.branch_id = p_branch_id
      and adjustment.cash_register_id = p_cash_register_id
      and adjustment.cash_session_id = p_cash_session_id
      and adjustment.adjustment_type = 'reconciled_sale_already_in_opening'
      and adjustment.deleted_at is null;

    v_expected_amount := v_session.opening_amount
      + v_cash_payments
      + v_cash_adjustments;

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
    'cash_payments_amount', v_cash_payments,
    'cash_adjustments_amount', v_cash_adjustments,
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

-- `skipped` is retriable in the historical generic batch processor. A Sale
-- reconciliation is different: its original mutations are terminal audit
-- evidence and must never become applicable again.
create or replace function private.prevent_superseded_sale_mutation_reactivation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.metadata ? 'superseded_by_sale_reconciliation'
     and (
       new.status <> 'skipped'
       or new.metadata ->> 'superseded_by_sale_reconciliation'
          is distinct from old.metadata ->> 'superseded_by_sale_reconciliation'
     )
  then
    raise exception using
      errcode = '23514',
      message = 'A Sale mutation superseded by reconciliation is terminal';
  end if;
  return new;
end;
$$;

drop trigger if exists sync_mutations_prevent_superseded_sale_reactivation
on public.sync_mutations;
create trigger sync_mutations_prevent_superseded_sale_reactivation
before update on public.sync_mutations
for each row
execute function private.prevent_superseded_sale_mutation_reactivation();

-- Keep scheduled/manual clients on the canonical public entrypoint. The
-- pre-cash implementation remains an internal delegate and is not an RPC.
revoke all on function public.process_sync_batch_base_before_cash(uuid, text)
from public, anon, authenticated;
grant execute on function public.process_sync_batch_base_before_cash(uuid, text)
to service_role;

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
      if v_profile_id is null then
        raise exception using errcode = '42501', message = 'Authentication required';
      end if;
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

comment on table public.cash_session_adjustments
is 'Restricted auditable cash ledger. The MVP only records cash from a reconciled Sale that was already included in destination opening cash.';
comment on table public.sale_reconciliations
is 'Authoritative audit record for a real Sale rejected because its original cash session was already closed.';
comment on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
is 'Atomically reconstructs a rejected real Sale from its original sync mutations, assigns it to an explicit open session, applies inventory once and resolves its conflict.';
comment on function public.close_cash_session_authoritatively(uuid, uuid, uuid, uuid, numeric, text)
is 'Closes a cash session using opening cash plus valid cash Sale payments plus authorized non-deleted cash session adjustments.';
comment on function public.process_sync_batch(uuid, text)
is 'Canonical batch processor. Reconciled stale-Sale batches are terminal and return an idempotent no-op instead of replaying superseded mutations.';

revoke all on function private.intentional_stale_sale_reconciliation_result(uuid, boolean)
from public, anon, authenticated;
revoke all on function private.prevent_superseded_sale_mutation_reactivation()
from public, anon, authenticated;
revoke all on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
) from public, anon, authenticated;
revoke all on function public.close_cash_session_authoritatively(
  uuid, uuid, uuid, uuid, numeric, text
) from public, anon;

grant execute on function private.intentional_stale_sale_reconciliation_result(uuid, boolean)
to service_role;
grant execute on function private.prevent_superseded_sale_mutation_reactivation()
to service_role;
grant execute on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
) to authenticated, service_role;
grant execute on function public.close_cash_session_authoritatively(
  uuid, uuid, uuid, uuid, numeric, text
) to authenticated, service_role;

commit;
