-- P2.5B2A - Server-authoritative inventory movement history.
--
-- This read contract is intentionally separate from pull_sync_changes_v2:
-- the generic pull returns full entity payloads, uses incremental sync order,
-- and advances device/cursor state. History needs cost masking, descending
-- business-time keysets, and no writes.

begin;

create index if not exists inventory_movements_history_scope_idx
on public.inventory_movements (
  business_id,
  branch_id,
  occurred_at desc,
  id desc
);

create index if not exists inventory_movements_history_product_scope_idx
on public.inventory_movements (
  business_id,
  branch_id,
  product_id,
  occurred_at desc,
  id desc
);

create or replace function public.list_inventory_movement_history(
  p_business_id uuid,
  p_branch_id uuid,
  p_product_id uuid default null,
  p_source_type text default null,
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 50
)
returns table (
  id uuid,
  business_id uuid,
  branch_id uuid,
  product_id uuid,
  movement_type text,
  source_type text,
  effective_type text,
  source_id uuid,
  reference_type text,
  reference_id uuid,
  quantity_delta integer,
  occurred_at timestamptz,
  previous_stock integer,
  new_stock integer,
  created_by uuid,
  device_id uuid,
  reversed_movement_id uuid,
  idempotency_key text,
  unit_cost numeric(14,2)
)
language plpgsql
stable
security definer
set search_path = ''
set timezone = 'UTC'
as $$
declare
  v_limit integer := greatest(1, least(coalesce(p_limit, 50), 200));
  v_effective_type text := nullif(lower(btrim(p_source_type)), '');
  v_can_view_costs boolean := false;
  v_branch_is_active boolean := false;
begin
  if auth.uid() is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  if p_business_id is null or p_branch_id is null then
    raise exception using
      errcode = '22023',
      message = 'business_id and branch_id are required';
  end if;

  if (p_cursor_occurred_at is null) <> (p_cursor_id is null) then
    raise exception using
      errcode = '22023',
      message = 'cursor_occurred_at and cursor_id must be provided together';
  end if;

  if p_from is not null and p_to is not null and p_from > p_to then
    raise exception using
      errcode = '22023',
      message = 'from timestamp cannot be greater than to timestamp';
  end if;

  select exists (
    select 1
    from public.branches branch
    where branch.id = p_branch_id
      and branch.business_id = p_business_id
      and branch.status = 'active'
      and branch.deleted_at is null
  )
  into v_branch_is_active;

  if not v_branch_is_active
     or not private.has_branch_access(p_business_id, p_branch_id)
     or not private.has_branch_permission(
       p_business_id,
       p_branch_id,
       'inventory.read'
     )
  then
    raise exception using
      errcode = '42501',
      message = 'Inventory history is not authorized for this branch';
  end if;

  v_can_view_costs := private.has_branch_permission(
    p_business_id,
    p_branch_id,
    'inventory.view_costs'
  );

  return query
  with normalized as (
    select
      movement.id,
      movement.business_id,
      movement.branch_id,
      movement.product_id,
      movement.movement_type::text as movement_type,
      movement.source_type,
      case
        when lower(coalesce(movement.reference_type::text, '')) in (
          'manual_initial_stock',
          'initial_stock'
        ) then 'initial_stock'
        when nullif(lower(btrim(movement.source_type)), '') is not null
          then lower(btrim(movement.source_type))
        else lower(btrim(movement.movement_type::text))
      end as effective_type,
      movement.source_id,
      movement.reference_type::text as reference_type,
      movement.reference_id,
      movement.quantity_change as quantity_delta,
      movement.occurred_at,
      movement.previous_stock,
      movement.new_stock,
      movement.created_by,
      movement.device_id,
      movement.reversed_movement_id,
      movement.idempotency_key,
      movement.unit_cost
    from public.inventory_movements movement
    where movement.business_id = p_business_id
      and movement.branch_id = p_branch_id
      and (p_product_id is null or movement.product_id = p_product_id)
      and (p_from is null or movement.occurred_at >= p_from)
      and (p_to is null or movement.occurred_at <= p_to)
      and (
        p_cursor_occurred_at is null
        or movement.occurred_at < p_cursor_occurred_at
        or (
          movement.occurred_at = p_cursor_occurred_at
          and movement.id < p_cursor_id
        )
      )
  )
  select
    normalized.id,
    normalized.business_id,
    normalized.branch_id,
    normalized.product_id,
    normalized.movement_type,
    normalized.source_type,
    normalized.effective_type,
    normalized.source_id,
    normalized.reference_type,
    normalized.reference_id,
    normalized.quantity_delta,
    normalized.occurred_at,
    normalized.previous_stock,
    normalized.new_stock,
    normalized.created_by,
    normalized.device_id,
    normalized.reversed_movement_id,
    normalized.idempotency_key,
    case
      when v_can_view_costs then normalized.unit_cost
      else null::numeric(14,2)
    end as unit_cost
  from normalized
  where v_effective_type is null
     or normalized.effective_type = v_effective_type
  order by normalized.occurred_at desc, normalized.id desc
  limit v_limit;
end;
$$;

comment on function public.list_inventory_movement_history(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  uuid,
  integer
) is
'Returns branch-scoped immutable inventory history ordered by occurred_at DESC, id DESC. effective_type prefers extended source_type semantics and maps manual initial-stock references to initial_stock. unit_cost is NULL unless the caller has inventory.view_costs. Metadata is deliberately excluded.';

revoke all on function public.list_inventory_movement_history(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  uuid,
  integer
) from public, anon;

grant execute on function public.list_inventory_movement_history(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  uuid,
  integer
) to authenticated, service_role;

commit;
