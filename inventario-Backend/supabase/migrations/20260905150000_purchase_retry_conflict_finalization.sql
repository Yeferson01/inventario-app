begin;

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
      'reconcile_to_open_cash_session',
      'sale_did_not_occur',
      'retry_after_permission_fix'
    )
  )
  not valid;
alter table public.sync_conflicts
  validate constraint sync_conflicts_resolution_strategy_check;

create or replace function private.purchase_retry_permission_evidence(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_profile_id uuid,
  p_purchase_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_purchase_conflicts integer;
  v_item_conflicts integer;
  v_target_conflicts integer;
  v_applied_mutations integer;
  v_remote_purchase_count integer;
  v_remote_item_count integer;
  v_remote_movement_count integer;
  v_incompatible_conflicts integer;
  v_conflicts_valid boolean;
  v_remote_absent boolean;
  v_remote_materialized boolean;
begin
  with target_conflicts as (
    select conflict.*, mutation.payload, mutation.idempotency_key,
           mutation.status as mutation_status
    from public.sync_conflicts conflict
    join public.sync_mutations mutation on mutation.id = conflict.sync_mutation_id
    where conflict.business_id = p_business_id
      and conflict.branch_id = p_branch_id
      and conflict.app_device_id = p_app_device_id
      and conflict.profile_id = p_profile_id
      and conflict.deleted_at is null
      and mutation.business_id = p_business_id
      and mutation.branch_id = p_branch_id
      and mutation.app_device_id = p_app_device_id
      and mutation.profile_id = p_profile_id
      and mutation.deleted_at is null
      and mutation.operation in ('insert', 'upsert')
      and coalesce(conflict.error_code, conflict.conflict_type) = 'permission_denied'
      and (
        (conflict.entity_table = 'purchases' and conflict.entity_id = p_purchase_id)
        or (
          conflict.entity_table = 'purchase_items'
          and mutation.payload ->> 'purchase_id' = p_purchase_id::text
        )
      )
      and (
        conflict.status = 'open'
        or (
          conflict.status = 'resolved'
          and conflict.resolution_strategy = 'retry_after_permission_fix'
        )
      )
  )
  select
    count(*) filter (where entity_table = 'purchases'),
    count(*) filter (where entity_table = 'purchase_items'),
    count(*),
    count(*) filter (where mutation_status = 'applied')
  into
    v_purchase_conflicts,
    v_item_conflicts,
    v_target_conflicts,
    v_applied_mutations
  from target_conflicts;

  select count(*) into v_remote_purchase_count
  from public.purchases purchase
  where purchase.id = p_purchase_id;

  select count(*) into v_remote_item_count
  from public.purchase_items item
  where item.purchase_id = p_purchase_id;

  select count(*) into v_remote_movement_count
  from public.inventory_movements movement
  where movement.source_type = 'purchase'
    and movement.source_id = p_purchase_id;

  select count(*) into v_incompatible_conflicts
  from public.sync_conflicts conflict
  join public.sync_mutations mutation on mutation.id = conflict.sync_mutation_id
  where conflict.business_id = p_business_id
    and conflict.branch_id = p_branch_id
    and conflict.status = 'open'
    and conflict.deleted_at is null
    and (
      (conflict.entity_table = 'purchases' and conflict.entity_id = p_purchase_id)
      or (
        conflict.entity_table = 'purchase_items'
        and mutation.payload ->> 'purchase_id' = p_purchase_id::text
      )
    )
    and not (
      conflict.app_device_id = p_app_device_id
      and conflict.profile_id = p_profile_id
      and coalesce(conflict.error_code, conflict.conflict_type) = 'permission_denied'
    );

  v_conflicts_valid := v_purchase_conflicts = 1
    and v_item_conflicts > 0
    and v_incompatible_conflicts = 0;

  v_remote_absent := v_remote_purchase_count = 0
    and v_remote_item_count = 0
    and v_remote_movement_count = 0;

  v_remote_materialized := v_remote_purchase_count = 1
    and v_remote_item_count = v_item_conflicts
    and v_remote_movement_count = v_item_conflicts
    and not exists (
      select 1
      from public.sync_conflicts conflict
      join public.sync_mutations mutation on mutation.id = conflict.sync_mutation_id
      left join public.purchases purchase
        on conflict.entity_table = 'purchases' and purchase.id = conflict.entity_id
      left join public.purchase_items item
        on conflict.entity_table = 'purchase_items' and item.id = conflict.entity_id
      where conflict.business_id = p_business_id
        and conflict.branch_id = p_branch_id
        and conflict.app_device_id = p_app_device_id
        and conflict.profile_id = p_profile_id
        and conflict.deleted_at is null
        and coalesce(conflict.error_code, conflict.conflict_type) = 'permission_denied'
        and (
          (conflict.entity_table = 'purchases' and conflict.entity_id = p_purchase_id)
          or (
            conflict.entity_table = 'purchase_items'
            and mutation.payload ->> 'purchase_id' = p_purchase_id::text
          )
        )
        and (
          (conflict.entity_table = 'purchases' and (
            purchase.id is null
            or purchase.business_id is distinct from p_business_id
            or purchase.branch_id is distinct from p_branch_id
            or purchase.idempotency_key is distinct from mutation.idempotency_key
            or purchase.total is distinct from coalesce(nullif(mutation.payload ->> 'total', '')::numeric, 0)
          ))
          or
          (conflict.entity_table = 'purchase_items' and (
            item.id is null
            or item.purchase_id is distinct from p_purchase_id
            or item.business_id is distinct from p_business_id
            or item.branch_id is distinct from p_branch_id
            or item.idempotency_key is distinct from mutation.idempotency_key
            or item.product_id is distinct from nullif(mutation.payload ->> 'product_id', '')::uuid
            or item.quantity is distinct from nullif(mutation.payload ->> 'quantity', '')::integer
            or item.unit_cost is distinct from nullif(mutation.payload ->> 'unit_cost', '')::numeric
            or item.subtotal is distinct from nullif(mutation.payload ->> 'subtotal', '')::numeric
            or not exists (
              select 1
              from public.inventory_movements movement
              where movement.business_id = p_business_id
                and movement.branch_id = p_branch_id
                and movement.source_type = 'purchase'
                and movement.source_id = p_purchase_id
                and movement.product_id = item.product_id
                and movement.quantity_change = item.quantity
                and movement.unit_cost is not distinct from item.unit_cost
                and movement.idempotency_key =
                  'purchase:' || p_purchase_id::text || ':item:' || item.id::text
                and movement.metadata ->> 'purchase_item_id' = item.id::text
            )
          ))
        )
    );

  return pg_catalog.jsonb_build_object(
    'business_id', p_business_id,
    'branch_id', p_branch_id,
    'app_device_id', p_app_device_id,
    'purchase_id', p_purchase_id,
    'safe_to_retry', v_conflicts_valid and (v_remote_absent or v_remote_materialized),
    'remote_absent', v_remote_absent,
    'remote_materialized', v_remote_materialized,
    'finalizable', v_conflicts_valid and v_remote_materialized
      and v_applied_mutations = v_target_conflicts,
    'purchase_conflict_count', v_purchase_conflicts,
    'purchase_item_conflict_count', v_item_conflicts,
    'target_conflict_count', v_target_conflicts,
    'applied_mutation_count', v_applied_mutations,
    'remote_purchase_count', v_remote_purchase_count,
    'remote_item_count', v_remote_item_count,
    'remote_movement_count', v_remote_movement_count,
    'incompatible_conflict_count', v_incompatible_conflicts
  );
end;
$$;

create or replace function public.inspect_retriable_purchase_permission_conflicts(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_purchase_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_business_id is null or p_branch_id is null
     or p_app_device_id is null or p_purchase_id is null then
    raise exception using errcode = '22023', message =
      'business_id, branch_id, app_device_id and purchase_id are required';
  end if;
  if not private.has_branch_permission(
    p_business_id, p_branch_id, 'inventory.purchase'
  ) then
    raise exception using errcode = '42501', message =
      'inventory.purchase permission is required';
  end if;
  if not exists (
    select 1 from public.app_devices device
    where device.id = p_app_device_id
      and device.business_id = p_business_id
      and device.branch_id = p_branch_id
      and device.profile_id = v_profile_id
      and device.status = 'active'
      and device.deleted_at is null
  ) then
    raise exception using errcode = '42501', message =
      'app_device is not active for this profile and branch';
  end if;

  return private.purchase_retry_permission_evidence(
    p_business_id, p_branch_id, p_app_device_id, v_profile_id, p_purchase_id
  );
end;
$$;

create or replace function public.finalize_retried_purchase_permission_conflicts(
  p_business_id uuid,
  p_branch_id uuid,
  p_app_device_id uuid,
  p_purchase_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_profile_id uuid := auth.uid();
  v_evidence jsonb;
  v_resolved integer := 0;
begin
  if v_profile_id is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if p_business_id is null or p_branch_id is null
     or p_app_device_id is null or p_purchase_id is null then
    raise exception using errcode = '22023', message =
      'business_id, branch_id, app_device_id and purchase_id are required';
  end if;
  if not private.has_branch_permission(
    p_business_id, p_branch_id, 'inventory.purchase'
  ) then
    raise exception using errcode = '42501', message =
      'inventory.purchase permission is required';
  end if;
  if not exists (
    select 1 from public.app_devices device
    where device.id = p_app_device_id
      and device.business_id = p_business_id
      and device.branch_id = p_branch_id
      and device.profile_id = v_profile_id
      and device.status = 'active'
      and device.deleted_at is null
  ) then
    raise exception using errcode = '42501', message =
      'app_device is not active for this profile and branch';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'purchase_retry_conflicts:' || p_business_id::text || ':' || p_purchase_id::text,
      0
    )
  );

  perform 1
  from public.sync_conflicts conflict
  join public.sync_mutations mutation on mutation.id = conflict.sync_mutation_id
  where conflict.business_id = p_business_id
    and conflict.branch_id = p_branch_id
    and conflict.app_device_id = p_app_device_id
    and conflict.profile_id = v_profile_id
    and conflict.deleted_at is null
    and coalesce(conflict.error_code, conflict.conflict_type) = 'permission_denied'
    and (
      (conflict.entity_table = 'purchases' and conflict.entity_id = p_purchase_id)
      or (
        conflict.entity_table = 'purchase_items'
        and mutation.payload ->> 'purchase_id' = p_purchase_id::text
      )
    )
  for update of conflict, mutation;

  v_evidence := private.purchase_retry_permission_evidence(
    p_business_id, p_branch_id, p_app_device_id, v_profile_id, p_purchase_id
  );

  if not coalesce((v_evidence ->> 'finalizable')::boolean, false) then
    raise exception using errcode = '23514', message =
      'Retried Purchase evidence is incomplete or incompatible';
  end if;

  update public.sync_conflicts conflict
  set
    status = 'resolved',
    resolved_at = statement_timestamp(),
    resolved_by = v_profile_id,
    resolution_strategy = 'retry_after_permission_fix',
    resolution_notes =
      'The same Purchase operation was authoritatively applied after its permission was corrected.',
    resolved_payload = pg_catalog.jsonb_build_object(
      'purchase_id', p_purchase_id,
      'remote_materialized', true
    ),
    metadata = coalesce(conflict.metadata, '{}'::jsonb)
      || pg_catalog.jsonb_build_object(
        'resolution_strategy', 'retry_after_permission_fix',
        'retried_purchase_id', p_purchase_id,
        'retry_finalized_at', statement_timestamp(),
        'retry_finalized_by', v_profile_id,
        'retry_app_device_id', p_app_device_id
      ),
    updated_at = statement_timestamp(),
    updated_by = v_profile_id
  from public.sync_mutations mutation
  where mutation.id = conflict.sync_mutation_id
    and conflict.business_id = p_business_id
    and conflict.branch_id = p_branch_id
    and conflict.app_device_id = p_app_device_id
    and conflict.profile_id = v_profile_id
    and conflict.status = 'open'
    and conflict.deleted_at is null
    and coalesce(conflict.error_code, conflict.conflict_type) = 'permission_denied'
    and (
      (conflict.entity_table = 'purchases' and conflict.entity_id = p_purchase_id)
      or (
        conflict.entity_table = 'purchase_items'
        and mutation.payload ->> 'purchase_id' = p_purchase_id::text
      )
    );
  get diagnostics v_resolved = row_count;

  if v_resolved > 0 then
    insert into public.activity_logs (
      id, business_id, user_id, action, affected_table, record_id, metadata, created_at
    ) values (
      extensions.gen_random_uuid(),
      p_business_id,
      v_profile_id,
      'PURCHASE_PERMISSION_RETRY_FINALIZED',
      'purchases',
      p_purchase_id,
      pg_catalog.jsonb_build_object(
        'branch_id', p_branch_id,
        'app_device_id', p_app_device_id,
        'resolved_conflict_count', v_resolved,
        'idempotent', false
      ),
      statement_timestamp()
    );
  end if;

  return v_evidence || pg_catalog.jsonb_build_object(
    'status', 'resolved',
    'resolution_strategy', 'retry_after_permission_fix',
    'resolved_conflict_count', v_resolved,
    'idempotent', v_resolved = 0
  );
end;
$$;

comment on function public.inspect_retriable_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) is 'Returns scoped authoritative evidence for retrying a Purchase rejected by historical permission_denied conflicts.';

comment on function public.finalize_retried_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) is 'Resolves the exact historical Purchase and PurchaseItem permission_denied conflicts after proving their mutations, entities and inventory effects are applied; applied mutations are never modified.';

revoke all on function private.purchase_retry_permission_evidence(
  uuid, uuid, uuid, uuid, uuid
) from public;
revoke all on function private.purchase_retry_permission_evidence(
  uuid, uuid, uuid, uuid, uuid
) from anon, authenticated;
grant execute on function private.purchase_retry_permission_evidence(
  uuid, uuid, uuid, uuid, uuid
) to service_role;

revoke all on function public.inspect_retriable_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) from public;
revoke all on function public.inspect_retriable_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) from anon;
grant execute on function public.inspect_retriable_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

revoke all on function public.finalize_retried_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) from public;
revoke all on function public.finalize_retried_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) from anon;
grant execute on function public.finalize_retried_purchase_permission_conflicts(
  uuid, uuid, uuid, uuid
) to authenticated, service_role;

commit;
