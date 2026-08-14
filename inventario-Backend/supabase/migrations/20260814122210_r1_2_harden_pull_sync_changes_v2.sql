-- R1.2 - Focal authorization hardening for incremental pull_sync_changes_v2.
--
-- Keep the established incremental datasets, window, page tokens, and cursor
-- behavior unchanged. A public wrapper now revalidates active business,
-- explicit active branch, caller membership/access, and the device profile's
-- still-active membership before delegating to the original implementation.

begin;

alter function public.pull_sync_changes_v2(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) rename to pull_sync_changes_v2_incremental_impl;

alter function public.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) set schema private;

revoke all on function private.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from public;
revoke all on function private.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from anon;
revoke all on function private.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from authenticated;
revoke all on function private.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from service_role;

comment on function private.pull_sync_changes_v2_incremental_impl(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) is
'Original incremental pull V2 implementation. Private R1.2 wrapper authorization must run before this function.';

create or replace function public.pull_sync_changes_v2(
  p_app_device_id uuid,
  p_since timestamp without time zone default null,
  p_entities text[] default null,
  p_limit_per_entity integer default 500,
  p_page_tokens jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_device public.app_devices%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_app_device_id is null then
    raise exception 'p_app_device_id is required';
  end if;

  select ad.*
  into v_device
  from public.app_devices ad
  where ad.id = p_app_device_id;

  if v_device.id is null then
    raise exception 'app_device not found';
  end if;

  if v_device.branch_id is null then
    raise exception 'app_device requires an explicit active branch for incremental pull';
  end if;

  perform private.authorize_operational_device_context(
    v_device.business_id,
    v_device.branch_id,
    v_device.id,
    false
  );

  return private.pull_sync_changes_v2_incremental_impl(
    p_app_device_id,
    p_since,
    p_entities,
    p_limit_per_entity,
    p_page_tokens
  );
end;
$$;

revoke all on function public.pull_sync_changes_v2(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from public;
revoke all on function public.pull_sync_changes_v2(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) from anon;

grant execute on function public.pull_sync_changes_v2(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) to authenticated, service_role;

comment on function public.pull_sync_changes_v2(
  uuid,
  timestamp without time zone,
  text[],
  integer,
  jsonb
) is
'Incremental pull V2 with unchanged datasets/cursor behavior and per-call R1.2 revalidation of active membership, business, branch, and app-device context.';

commit;
