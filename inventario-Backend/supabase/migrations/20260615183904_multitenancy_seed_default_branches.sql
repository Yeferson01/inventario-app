-- Fase 2.4 - Multitenancy seed default branches
-- Objetivo:
-- Crear una sucursal principal para cada negocio existente.
--
-- Nota:
-- No asignamos todavía branch_id a ventas, compras, inventario ni memberships.
-- business_members.branch_id null sigue significando acceso a nivel negocio.

begin;

-- =========================================================
-- Crear sucursal principal por negocio existente
-- =========================================================

insert into public.branches (
  business_id,
  name,
  address,
  phone,
  status,
  created_by,
  updated_by
)
select
  b.id as business_id,
  'Principal' as name,
  b.address,
  b.phone,
  'active' as status,
  owner_profile.id as created_by,
  owner_profile.id as updated_by
from public.businesses b
left join lateral (
  select p.id
  from public.profiles p
  where p.business_id = b.id
    and p.role = 'owner'
  order by p.created_at asc
  limit 1
) owner_profile on true
where b.deleted_at is null
  and coalesce(b.status, 'active') = 'active'
  and not exists (
    select 1
    from public.branches br
    where br.business_id = b.id
      and lower(br.name) = lower('Principal')
      and br.deleted_at is null
  );

-- =========================================================
-- Seguridad temporal:
-- Habilitar RLS en las nuevas tablas de multitenancy.
--
-- Todavía no creamos policies finales.
-- Sin policies, estas tablas quedan cerradas para acceso directo
-- desde cliente autenticado/anónimo hasta la Fase 3.
-- =========================================================

alter table public.branches enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.business_members enable row level security;

commit;