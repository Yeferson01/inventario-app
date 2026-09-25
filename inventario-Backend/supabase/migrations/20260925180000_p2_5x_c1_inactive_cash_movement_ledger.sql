-- C1 foundation ONLY. No public writer, sync dispatcher or recovery activation.
begin;

insert into public.permissions (key, description) values
  ('cash.disburse', 'Create ordinary cash outflows (activation reserved for C2).'),
  ('cash.receive', 'Create ordinary cash inflows (activation reserved for C2).')
on conflict (key) do nothing;
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id from public.roles r cross join public.permissions p
where r.business_id is null and r.is_system_role and r.deleted_at is null
  and r.name in ('owner', 'admin')
  and p.key in ('cash.disburse', 'cash.receive')
on conflict (role_id, permission_id) do nothing;

create table public.cash_movements (
  id uuid primary key,
  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  cash_register_id uuid not null references public.cash_registers(id) on delete restrict,
  cash_session_id uuid not null references public.cash_sessions(id) on delete restrict,
  direction text not null check (direction in ('inflow', 'outflow')),
  category text not null check (category in (
    'supplier_purchase', 'payroll', 'utilities', 'rent', 'maintenance', 'repairs',
    'transport', 'infrastructure', 'cleaning', 'office_supplies',
    'owner_withdrawal', 'owner_contribution', 'other_income', 'other')),
  amount numeric not null check (
    amount > 0 and amount <= 999999999999.99 and amount = trunc(amount, 2)),
  currency text not null check (length(btrim(currency)) > 0),
  source_type text not null check (length(btrim(source_type)) > 0),
  source_id uuid,
  note text,
  occurred_at timestamptz not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  idempotency_key text not null check (length(btrim(idempotency_key)) > 0),
  metadata jsonb not null default '{}' check (jsonb_typeof(metadata) = 'object'),
  reversed_movement_id uuid references public.cash_movements(id) on delete restrict,
  constraint cash_movements_business_idempotency_unique unique (business_id, idempotency_key),
  constraint cash_movements_no_self_reversal check (reversed_movement_id is distinct from id),
  constraint cash_movements_purchase_source check (source_type <> 'purchase' or source_id is not null)
);
create index cash_movements_session_chronology_idx on public.cash_movements
  (business_id, branch_id, cash_session_id, occurred_at desc, id);

create function private.guard_cash_movement_foundation()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '23514', message = 'cash_movements is append-only';
  end if;
  if not exists (
    select 1 from public.cash_sessions s
    join public.cash_registers r on r.id = s.cash_register_id
    join public.branches b on b.id = r.branch_id
    where s.id = new.cash_session_id and s.business_id = new.business_id
      and s.branch_id = new.branch_id and s.cash_register_id = new.cash_register_id
      and r.business_id = new.business_id and r.branch_id = new.branch_id
      and b.business_id = new.business_id
  ) then
    raise exception using errcode = '23514', message = 'cash_movements scope mismatch';
  end if;
  if new.reversed_movement_id is not null and not exists (
    select 1 from public.cash_movements m where m.id = new.reversed_movement_id
      and m.business_id = new.business_id and m.branch_id = new.branch_id
      and m.cash_register_id = new.cash_register_id and m.currency = new.currency
  ) then
    raise exception using errcode = '23514', message = 'cash_movements reversal scope mismatch';
  end if;
  return new;
end;
$$;
revoke all on function private.guard_cash_movement_foundation() from public, anon, authenticated;
create trigger cash_movements_foundation_guard before insert or update or delete
  on public.cash_movements for each row execute function private.guard_cash_movement_foundation();
alter table public.cash_movements enable row level security;
create policy cash_movements_read on public.cash_movements for select to authenticated
using (private.has_branch_access(business_id, branch_id)
  and private.has_branch_permission(business_id, branch_id, 'cash.read'));
revoke all on public.cash_movements from public, anon, authenticated, service_role;
grant select on public.cash_movements to authenticated;
grant select, insert on public.cash_movements to service_role;
comment on table public.cash_movements is
  'Inactive C1 ledger. Cash movement is not automatically an expense. No productive writer/sync until C2 integrates close and recovery.';
commit;
