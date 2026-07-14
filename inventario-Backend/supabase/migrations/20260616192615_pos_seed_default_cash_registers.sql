-- Fase 4.2 - Seed default cash registers
-- Objetivo:
-- Crear una caja principal por cada sucursal activa existente.
--
-- También agregamos validaciones de integridad:
-- 1. cash_registers.branch_id debe pertenecer al mismo business_id.
-- 2. cash_sessions.cash_register_id debe pertenecer al mismo business_id y branch_id.
--
-- Nota:
-- No creamos cash_sessions automáticamente.
-- Las sesiones de caja deben abrirse desde la app/RPC con monto inicial.

begin;

-- =========================================================
-- Validación: cash_registers debe apuntar a una branch del mismo negocio
-- =========================================================

create or replace function private.validate_cash_register_branch_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.branches br
    where br.id = new.branch_id
      and br.business_id = new.business_id
      and br.deleted_at is null
  ) then
    raise exception 'cash_registers branch_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_cash_register_branch_consistency()
is 'Ensures cash_registers.branch_id belongs to the same business_id.';

drop trigger if exists trg_cash_registers_validate_branch_consistency
on public.cash_registers;

create trigger trg_cash_registers_validate_branch_consistency
before insert or update of business_id, branch_id
on public.cash_registers
for each row
execute function private.validate_cash_register_branch_consistency();

-- =========================================================
-- Validación: cash_sessions debe apuntar a caja del mismo negocio/sucursal
-- =========================================================

create or replace function private.validate_cash_session_register_consistency()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.cash_registers cr
    where cr.id = new.cash_register_id
      and cr.business_id = new.business_id
      and cr.branch_id = new.branch_id
      and cr.deleted_at is null
  ) then
    raise exception 'cash_sessions cash_register_id must belong to the same business_id and branch_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_cash_session_register_consistency()
is 'Ensures cash_sessions.cash_register_id belongs to the same business_id and branch_id.';

drop trigger if exists trg_cash_sessions_validate_register_consistency
on public.cash_sessions;

create trigger trg_cash_sessions_validate_register_consistency
before insert or update of business_id, branch_id, cash_register_id
on public.cash_sessions
for each row
execute function private.validate_cash_session_register_consistency();

-- =========================================================
-- Crear Caja Principal por sucursal activa existente
-- =========================================================

insert into public.cash_registers (
  business_id,
  branch_id,
  name,
  status,
  created_by,
  updated_by
)
select
  br.business_id,
  br.id as branch_id,
  'Caja Principal' as name,
  'active' as status,
  owner_member.profile_id as created_by,
  owner_member.profile_id as updated_by
from public.branches br
left join lateral (
  select bm.profile_id
  from public.business_members bm
  join public.roles r on r.id = bm.role_id
  where bm.business_id = br.business_id
    and (bm.branch_id is null or bm.branch_id = br.id)
    and bm.status = 'active'
    and bm.deleted_at is null
    and r.name = 'owner'
  order by bm.created_at asc
  limit 1
) owner_member on true
where br.deleted_at is null
  and br.status = 'active'
  and not exists (
    select 1
    from public.cash_registers cr
    where cr.business_id = br.business_id
      and cr.branch_id = br.id
      and lower(cr.name) = lower('Caja Principal')
      and cr.deleted_at is null
  );

commit;