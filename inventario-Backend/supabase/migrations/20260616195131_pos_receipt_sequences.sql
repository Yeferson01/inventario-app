-- Fase 4.6 - POS receipt sequences
-- Objetivo:
-- Crear receipt_sequences y una función transaccional para asignar
-- números de recibo únicos por negocio/sucursal.
--
-- Nota:
-- No generamos PDF ni archivos de recibo todavía.
-- Solo dejamos lista la numeración segura.

begin;

-- =========================================================
-- RECEIPT SEQUENCES
-- =========================================================

create table if not exists public.receipt_sequences (
  id uuid primary key default extensions.gen_random_uuid(),

  business_id uuid not null references public.businesses(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,

  name text not null default 'Recibos POS',
  prefix text not null default 'POS',
  current_number bigint not null default 0,
  padding integer not null default 6,

  status text not null default 'active',

  last_issued_at timestamp without time zone,

  created_at timestamp without time zone default now(),
  updated_at timestamp without time zone default now(),
  deleted_at timestamp without time zone,

  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  deleted_by uuid references public.profiles(id) on delete set null,
  delete_reason text,

  version integer not null default 1,
  sync_status text not null default 'synced',
  metadata jsonb not null default '{}'::jsonb,

  constraint receipt_sequences_name_not_blank
    check (length(trim(name)) > 0),

  constraint receipt_sequences_prefix_not_blank
    check (length(trim(prefix)) > 0),

  constraint receipt_sequences_current_number_non_negative
    check (current_number >= 0),

  constraint receipt_sequences_padding_valid
    check (padding between 1 and 20),

  constraint receipt_sequences_status_check
    check (status in ('active', 'inactive')),

  constraint receipt_sequences_version_positive
    check (version >= 1),

  constraint receipt_sequences_sync_status_check
    check (sync_status in ('synced', 'pending', 'conflict', 'error'))
);

comment on table public.receipt_sequences
is 'Receipt numbering sequences by business and branch for POS sales.';

comment on column public.receipt_sequences.current_number
is 'Last issued numeric receipt number. The next receipt increments this value transactionally.';

comment on column public.receipt_sequences.padding
is 'Number of digits used for left-padding receipt numbers.';

-- Una secuencia activa por negocio/sucursal/prefix.
create unique index if not exists receipt_sequences_business_branch_prefix_active_unique
on public.receipt_sequences (business_id, branch_id, lower(prefix))
where deleted_at is null
  and status = 'active';

create index if not exists receipt_sequences_business_branch_active_idx
on public.receipt_sequences (business_id, branch_id, status)
where deleted_at is null;

-- =========================================================
-- Default receipt sequence per active branch
-- =========================================================

insert into public.receipt_sequences (
  business_id,
  branch_id,
  name,
  prefix,
  current_number,
  padding,
  status,
  created_by,
  updated_by
)
select
  br.business_id,
  br.id as branch_id,
  'Recibos POS' as name,
  'POS' as prefix,
  0 as current_number,
  6 as padding,
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
    from public.receipt_sequences rs
    where rs.business_id = br.business_id
      and rs.branch_id = br.id
      and lower(rs.prefix) = lower('POS')
      and rs.deleted_at is null
      and rs.status = 'active'
  );

-- =========================================================
-- updated_at y version
-- =========================================================

drop trigger if exists trg_receipt_sequences_updated_at on public.receipt_sequences;

create trigger trg_receipt_sequences_updated_at
before update on public.receipt_sequences
for each row
execute function public.update_updated_at_column();

drop trigger if exists trg_receipt_sequences_increment_version on public.receipt_sequences;

create trigger trg_receipt_sequences_increment_version
before update on public.receipt_sequences
for each row
execute function public.increment_row_version_on_business_change();

-- =========================================================
-- Integridad branch/business
-- =========================================================

create or replace function private.validate_receipt_sequence_branch_consistency()
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
    raise exception 'receipt_sequences.branch_id must belong to the same business_id';
  end if;

  return new;
end;
$$;

comment on function private.validate_receipt_sequence_branch_consistency()
is 'Ensures receipt_sequences.branch_id belongs to the same business_id.';

drop trigger if exists trg_receipt_sequences_validate_branch_consistency
on public.receipt_sequences;

create trigger trg_receipt_sequences_validate_branch_consistency
before insert or update of business_id, branch_id
on public.receipt_sequences
for each row
execute function private.validate_receipt_sequence_branch_consistency();

-- =========================================================
-- Function: issue_sale_receipt_number
-- =========================================================

create or replace function public.issue_sale_receipt_number(
  p_sale_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sale public.sales%rowtype;
  v_sequence public.receipt_sequences%rowtype;
  v_next_number bigint;
  v_receipt_number text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into v_sale
  from public.sales
  where id = p_sale_id
    and deleted_at is null
  for update;

  if v_sale.id is null then
    raise exception 'Sale not found or deleted';
  end if;

  if v_sale.business_id is null then
    raise exception 'Sale business_id is required';
  end if;

  if v_sale.branch_id is null then
    raise exception 'Sale branch_id is required before issuing receipt';
  end if;

  if v_sale.receipt_number is not null then
    return v_sale.receipt_number;
  end if;

  if not private.has_branch_permission(v_sale.business_id, v_sale.branch_id, 'sales.create') then
    raise exception 'Insufficient permission to issue receipt number';
  end if;

  select *
  into v_sequence
  from public.receipt_sequences rs
  where rs.business_id = v_sale.business_id
    and rs.branch_id = v_sale.branch_id
    and rs.status = 'active'
    and rs.deleted_at is null
  order by
    case when lower(rs.prefix) = lower('POS') then 0 else 1 end,
    rs.created_at asc
  limit 1
  for update;

  if v_sequence.id is null then
    raise exception 'No active receipt sequence found for sale branch';
  end if;

  v_next_number := v_sequence.current_number + 1;

  v_receipt_number :=
    v_sequence.prefix || '-' || lpad(v_next_number::text, v_sequence.padding, '0');

  update public.receipt_sequences
  set
    current_number = v_next_number,
    last_issued_at = now(),
    updated_by = auth.uid()
  where id = v_sequence.id;

  update public.sales
  set
    receipt_number = v_receipt_number,
    updated_by = auth.uid()
  where id = v_sale.id;

  return v_receipt_number;
end;
$$;

comment on function public.issue_sale_receipt_number(uuid)
is 'Issues the next receipt number for a sale using a locked receipt sequence. Safe against duplicate receipt numbers.';

revoke all on function public.issue_sale_receipt_number(uuid) from public;
grant execute on function public.issue_sale_receipt_number(uuid) to authenticated;
grant execute on function public.issue_sale_receipt_number(uuid) to service_role;

-- =========================================================
-- RLS
-- =========================================================

alter table public.receipt_sequences enable row level security;

drop policy if exists receipt_sequences_select_allowed on public.receipt_sequences;
drop policy if exists receipt_sequences_insert_allowed on public.receipt_sequences;
drop policy if exists receipt_sequences_update_allowed on public.receipt_sequences;
drop policy if exists receipt_sequences_soft_delete_allowed on public.receipt_sequences;
drop policy if exists receipt_sequences_delete_blocked on public.receipt_sequences;

create policy receipt_sequences_select_allowed
on public.receipt_sequences
for select
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_access(business_id, branch_id)
  and (
    private.has_business_permission(business_id, 'sales.read')
    or private.has_business_permission(business_id, 'sales.create')
    or private.has_business_permission(business_id, 'settings.business')
    or private.has_business_permission(business_id, 'settings.branches')
  )
);

create policy receipt_sequences_insert_allowed
on public.receipt_sequences
for insert
to authenticated
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and private.has_branch_permission(business_id, branch_id, 'settings.business')
);

create policy receipt_sequences_update_allowed
on public.receipt_sequences
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and (
    private.has_branch_permission(business_id, branch_id, 'settings.business')
    or private.has_branch_permission(business_id, branch_id, 'settings.branches')
  )
)
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is null
  and (
    private.has_branch_permission(business_id, branch_id, 'settings.business')
    or private.has_branch_permission(business_id, branch_id, 'settings.branches')
  )
);

create policy receipt_sequences_soft_delete_allowed
on public.receipt_sequences
for update
to authenticated
using (
  deleted_at is null
  and business_id is not null
  and branch_id is not null
  and private.has_branch_permission(business_id, branch_id, 'settings.business')
)
with check (
  business_id is not null
  and branch_id is not null
  and deleted_at is not null
  and private.has_branch_permission(business_id, branch_id, 'settings.business')
);

create policy receipt_sequences_delete_blocked
on public.receipt_sequences
for delete
to authenticated
using (false);

commit;