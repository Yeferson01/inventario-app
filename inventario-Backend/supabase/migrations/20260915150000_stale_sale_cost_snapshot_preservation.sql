-- P2.2C2 - Preserve original sale cost through stale-sale reconciliation.

begin;

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
  v_unit_cost_snapshot numeric(14,2);
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
      v_unit_cost_snapshot :=
        nullif(v_payload ->> 'unit_cost_snapshot', '')::numeric;
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
      unit_cost_snapshot, subtotal, discount_amount, tax_amount, total,
      created_at,
      created_by, updated_by, sync_status, idempotency_key, metadata
    ) values (
      v_item_id, p_business_id, p_sale_id, v_product_id,
      nullif(v_payload ->> 'product_name_snapshot', ''),
      nullif(v_payload ->> 'barcode_snapshot', ''),
      v_quantity,
      coalesce(nullif(v_payload ->> 'unit_price', '')::numeric, 0),
      v_unit_cost_snapshot,
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
      p_unit_cost := v_unit_cost_snapshot,
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

comment on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
)
is 'Reconciles an intentional stale Sale while preserving its original nullable unit cost snapshots.';

revoke all on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
) from public;
grant execute on function public.reconcile_rejected_sale_to_open_cash_session(
  uuid, uuid, uuid, uuid, uuid, uuid, uuid, text, text, text
) to authenticated, service_role;

commit;
