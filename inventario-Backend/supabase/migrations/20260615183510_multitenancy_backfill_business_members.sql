-- Fase 2.3 - Multitenancy backfill business_members
-- Objetivo:
-- Crear memberships iniciales desde profiles.business_id y profiles.role.
--
-- Nota:
-- No se eliminan profiles.business_id ni profiles.role.
-- No se cambian policies todavía.
-- No se crean memberships para profiles sin business_id o sin rol válido.

begin;

-- =========================================================
-- Backfill business_members from profiles
-- =========================================================

insert into public.business_members (
  business_id,
  profile_id,
  branch_id,
  role_id,
  status,
  accepted_at,
  created_by,
  updated_by
)
select
  p.business_id,
  p.id as profile_id,
  null as branch_id,
  r.id as role_id,
  case
    when coalesce(p.status, 'active') = 'active' then 'active'
    else 'suspended'
  end as status,
  now() as accepted_at,
  p.id as created_by,
  p.id as updated_by
from public.profiles p
join public.roles r
  on r.business_id is null
 and r.name = p.role::text
 and r.deleted_at is null
where p.business_id is not null
  and p.role is not null
  and not exists (
    select 1
    from public.business_members bm
    where bm.business_id = p.business_id
      and bm.profile_id = p.id
      and bm.branch_id is null
      and bm.deleted_at is null
      and bm.status <> 'removed'
  );

commit;