-- Fase 2.2 - Multitenancy seed roles and permissions
-- Objetivo:
-- Crear catálogo inicial de permisos y roles globales del sistema.
--
-- Nota:
-- No se crean policies todavía.
-- No se asignan memberships todavía.
-- Esta migración solo siembra datos base para autorización futura.

begin;

-- =========================================================
-- PERMISSIONS
-- =========================================================

insert into public.permissions (key, description)
values
  -- Products
  ('products.read', 'Read products, categories and basic product data.'),
  ('products.create', 'Create products and categories.'),
  ('products.update', 'Update products and categories.'),
  ('products.soft_delete', 'Soft delete products and categories.'),
  ('products.import', 'Import products in bulk.'),

  -- Inventory
  ('inventory.read', 'Read inventory, stock balances and inventory movements.'),
  ('inventory.adjust', 'Create manual inventory adjustments.'),
  ('inventory.transfer', 'Transfer stock between branches.'),
  ('inventory.count', 'Create and manage stock counts.'),
  ('inventory.purchase', 'Create purchases and receive stock.'),

  -- Sales
  ('sales.read', 'Read sales history and sale details.'),
  ('sales.create', 'Create sales and sale items.'),
  ('sales.discount', 'Apply discounts to sales.'),
  ('sales.void', 'Void or cancel sales.'),
  ('sales.refund', 'Create refunds and returns.'),

  -- Cash
  ('cash.open', 'Open cash sessions.'),
  ('cash.close', 'Close cash sessions.'),
  ('cash.read', 'Read cash sessions and cash reports.'),
  ('cash.adjust', 'Create cash adjustments.'),

  -- Customers
  ('customers.read', 'Read customers and customer history.'),
  ('customers.create', 'Create customers.'),
  ('customers.update', 'Update customers.'),
  ('customers.soft_delete', 'Soft delete customers.'),
  ('customers.credit.manage', 'Manage customer credit and payments.'),

  -- Reports
  ('reports.sales', 'Read sales reports.'),
  ('reports.inventory', 'Read inventory reports.'),
  ('reports.cash', 'Read cash reports.'),
  ('reports.export', 'Export reports.'),

  -- Members
  ('members.invite', 'Invite business members.'),
  ('members.update_role', 'Update member roles.'),
  ('members.suspend', 'Suspend business members.'),

  -- Settings
  ('settings.business', 'Manage business settings.'),
  ('settings.branches', 'Manage branches.'),
  ('settings.taxes', 'Manage tax settings.'),
  ('settings.billing', 'Manage billing and subscription settings.'),

  -- Audit / security
  ('audit.read', 'Read audit events.'),
  ('security_events.read', 'Read security events.')
on conflict (key) do update
set description = excluded.description;

-- =========================================================
-- SYSTEM ROLES
-- =========================================================

insert into public.roles (business_id, name, description, is_system_role)
values
  (null, 'owner', 'Business owner with full access to all modules and settings.', true),
  (null, 'admin', 'Administrator with broad operational access except billing ownership controls.', true),
  (null, 'cashier', 'Cashier focused on POS sales, customers and cash sessions.', true),
  (null, 'warehouse', 'Warehouse role focused on products, inventory and purchases.', true),
  (null, 'technician', 'Technician role focused on devices/assets and limited inventory visibility.', true)
on conflict (
  coalesce(business_id, '00000000-0000-0000-0000-000000000000'::uuid),
  lower(name)
)
where deleted_at is null
do update
set
  description = excluded.description,
  is_system_role = excluded.is_system_role,
  updated_at = now();

-- =========================================================
-- ROLE PERMISSIONS: OWNER
-- Owner gets all permissions.
-- =========================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.business_id is null
  and r.name = 'owner'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- ROLE PERMISSIONS: ADMIN
-- Admin gets most operational permissions.
-- =========================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in (
  'products.read',
  'products.create',
  'products.update',
  'products.soft_delete',
  'products.import',

  'inventory.read',
  'inventory.adjust',
  'inventory.transfer',
  'inventory.count',
  'inventory.purchase',

  'sales.read',
  'sales.create',
  'sales.discount',
  'sales.void',
  'sales.refund',

  'cash.open',
  'cash.close',
  'cash.read',
  'cash.adjust',

  'customers.read',
  'customers.create',
  'customers.update',
  'customers.soft_delete',
  'customers.credit.manage',

  'reports.sales',
  'reports.inventory',
  'reports.cash',
  'reports.export',

  'members.invite',
  'members.update_role',
  'members.suspend',

  'settings.business',
  'settings.branches',
  'settings.taxes',

  'audit.read',
  'security_events.read'
)
where r.business_id is null
  and r.name = 'admin'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- ROLE PERMISSIONS: CASHIER
-- =========================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in (
  'products.read',
  'inventory.read',

  'sales.read',
  'sales.create',
  'sales.discount',

  'cash.open',
  'cash.close',
  'cash.read',

  'customers.read',
  'customers.create',
  'customers.update'
)
where r.business_id is null
  and r.name = 'cashier'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- ROLE PERMISSIONS: WAREHOUSE
-- =========================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in (
  'products.read',
  'products.create',
  'products.update',
  'products.import',

  'inventory.read',
  'inventory.adjust',
  'inventory.transfer',
  'inventory.count',
  'inventory.purchase',

  'reports.inventory'
)
where r.business_id is null
  and r.name = 'warehouse'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- ROLE PERMISSIONS: TECHNICIAN
-- Nota:
-- El rol technician queda limitado por ahora.
-- Después, cuando separemos devices/assets de app_devices,
-- podremos hacerlo más fino.
-- =========================================================

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.key in (
  'products.read',
  'inventory.read'
)
where r.business_id is null
  and r.name = 'technician'
on conflict (role_id, permission_id) do nothing;

commit;