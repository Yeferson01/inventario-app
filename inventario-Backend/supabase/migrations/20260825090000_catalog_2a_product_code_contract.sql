-- CATALOG-2A: close Product/MasterProduct code identity invariants.
--
-- This migration intentionally does not change sync permissions, catalog
-- pagination, contributions, or any operational Product upload contract.

do $$
begin
  if exists (
    select 1
    from public.product_barcodes pb
    where pb.scope = 'global'
      and pb.is_primary = true
      and pb.status = 'active'
      and pb.deleted_at is null
    group by pb.master_product_id
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'Cannot enforce one active primary global code per master product: duplicate rows exist';
  end if;
end
$$;

create unique index if not exists idx_product_barcodes_master_primary_unique
on public.product_barcodes (master_product_id)
where scope = 'global'
  and is_primary = true
  and status = 'active'
  and deleted_at is null;

alter table public.product_barcodes
  add constraint product_barcodes_internal_code_business_scope
  check (
    scope <> 'global'
    or barcode_type not in ('internal', 'local_sku')
  ) not valid;

comment on constraint product_barcodes_internal_code_business_scope
on public.product_barcodes is
'Internal and local SKU codes are tenant-local identities and cannot be global master codes. The NOT VALID constraint protects new writes without rewriting legacy rows.';

comment on index public.idx_product_barcodes_master_primary_unique is
'Allows at most one active primary global code per master product. Business Product primaries remain enforced by idx_product_barcodes_product_primary_unique.';
