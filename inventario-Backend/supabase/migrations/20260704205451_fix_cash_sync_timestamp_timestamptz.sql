-- Fix 6.18C.38F.2 - Add timestamptz overload for cash_sync_timestamp
--
-- The original helper accepted:
--   private.cash_sync_timestamp(text, timestamp without time zone)
--
-- But apply_sync_cash_mutation calls it with now(), and now() is
-- timestamp with time zone. This overload keeps apply_cash working safely.

create or replace function private.cash_sync_timestamp(
  p_value text,
  p_fallback timestamp with time zone default null
)
returns timestamp without time zone
language plpgsql
immutable
as $$
begin
  if p_value is null or btrim(p_value) = '' then
    if p_fallback is null then
      return null;
    end if;

    return p_fallback at time zone 'UTC';
  end if;

  return (p_value::timestamptz at time zone 'UTC');
exception
  when others then
    if p_fallback is null then
      return null;
    end if;

    return p_fallback at time zone 'UTC';
end;
$$;

comment on function private.cash_sync_timestamp(text, timestamp with time zone)
is 'Safely converts sync JSON timestamp strings into UTC timestamp without time zone. Overload for now()/timestamptz fallback.';
