-- C4D2.2: prospective POS payment event time. Existing Hosted paid_at values
-- remain untouched. Legacy mutations without the v1 marker retain their
-- historical apply behavior; new POS mutations must carry immutable UTC time.
begin;

create function private.validate_sale_payment_event_time_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_paid_at timestamptz;
  v_created_at timestamptz;
  v_paid_text text;
  v_created_text text;
begin
  if new.entity_table <> 'sale_payments'
     or new.operation not in ('insert', 'upsert')
     or not (new.payload ? 'payment_event_time_contract') then
    return new;
  end if;

  if new.payload ->> 'payment_event_time_contract' is distinct from 'v1' then
    raise exception using errcode = '22023',
      message = 'Unsupported sale payment event-time contract';
  end if;

  v_paid_text := new.payload ->> 'paid_at';
  v_created_text := new.payload ->> 'created_at';
  if v_paid_text is null
     or v_created_text is null
     or v_paid_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$'
     or v_created_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z$'
  then
    raise exception using errcode = '22023',
      message = 'Sale payment event time must be explicit UTC';
  end if;

  begin
    v_paid_at := v_paid_text::timestamptz;
    v_created_at := v_created_text::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception using errcode = '22023',
      message = 'Sale payment event time is invalid';
  end;
  if v_paid_at is distinct from v_created_at then
    raise exception using errcode = '22023',
      message = 'Sale payment event time differs from local creation time';
  end if;
  return new;
end;
$$;

create trigger trg_sync_mutations_sale_payment_event_time
before insert or update of payload, entity_table, operation
on public.sync_mutations
for each row
execute function private.validate_sale_payment_event_time_mutation();

create function private.keep_sale_payment_paid_at_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.paid_at is distinct from old.paid_at then
    raise exception using errcode = '23514',
      message = 'sale_payments.paid_at is immutable';
  end if;
  return new;
end;
$$;

create trigger trg_sale_payments_immutable_paid_at
before update on public.sale_payments
for each row
execute function private.keep_sale_payment_paid_at_immutable();

comment on function private.validate_sale_payment_event_time_mutation()
is 'Validates explicit UTC paid_at = local payment created_at for v1 POS mutations; unmarked legacy payloads are unchanged.';
comment on function private.keep_sale_payment_paid_at_immutable()
is 'Prevents changes to the economic payment time after a sale_payment is materialized.';

revoke all on function private.validate_sale_payment_event_time_mutation()
  from public, anon, authenticated;
revoke all on function private.keep_sale_payment_paid_at_immutable()
  from public, anon, authenticated;

commit;
