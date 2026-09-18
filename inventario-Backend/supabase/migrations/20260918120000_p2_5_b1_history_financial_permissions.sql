-- P2.5B1 - Explicit financial permissions for operational history.
--
-- History access and financial detail access remain independent:
-- - sales.read permits sale history/detail; sales.view_costs additionally
--   permits unit_cost_snapshot, COGS and gross-margin fields.
-- - inventory.read permits inventory history/movements;
--   inventory.view_costs additionally permits sensitive inventory costs.
--
-- A missing cost permission must omit protected financial fields without
-- denying the base record. Historical unknown cost remains NULL; it must never
-- be replaced with zero, current average_cost or products.purchase_price.

begin;

insert into public.permissions (key, description)
values
  (
    'inventory.view_costs',
    'View inventory costs, historical purchase costs and stock valuation data.'
  ),
  (
    'sales.view_costs',
    'View historical sales costs, COGS and gross margin data.'
  )
on conflict (key) do update
set description = excluded.description;

insert into public.role_permissions (role_id, permission_id)
select role.id, permission.id
from public.roles role
cross join public.permissions permission
where role.business_id is null
  and role.name in ('owner', 'admin')
  and role.is_system_role
  and role.deleted_at is null
  and permission.key in ('inventory.view_costs', 'sales.view_costs')
on conflict (role_id, permission_id) do nothing;

commit;
