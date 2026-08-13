-- R1.1 - Harden register_or_update_app_device.
--
-- The deployed project contains an unversioned overload with p_app_device_id
-- that makes PostgREST resolution ambiguous. Remove only that known obsolete
-- signature, retain the versioned business + installation identity contract,
-- and prevent normal self-registration from unblocking a device.

begin;

drop function if exists public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  uuid,
  text,
  text,
  text,
  text,
  jsonb
);

create or replace function public.register_or_update_app_device(
  p_business_id uuid,
  p_branch_id uuid,
  p_installation_id text,
  p_device_name text default null,
  p_platform text default null,
  p_app_version text default null,
  p_os_version text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;
  v_existing public.app_devices%rowtype;
  v_app_device public.app_devices%rowtype;
  v_created_or_updated text;
  v_installation_id text;
  v_device_name text;
  v_platform text;
  v_metadata jsonb;
begin
  v_profile_id := auth.uid();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  if p_branch_id is null then
    raise exception 'branch_id is required';
  end if;

  v_installation_id := nullif(btrim(coalesce(p_installation_id, '')), '');

  if v_installation_id is null then
    raise exception 'installation_id is required';
  end if;

  if length(v_installation_id) < 8 then
    raise exception 'installation_id is too short';
  end if;

  v_device_name := nullif(btrim(coalesce(p_device_name, '')), '');
  v_platform := lower(nullif(btrim(coalesce(p_platform, '')), ''));

  if v_platform is null then
    v_platform := 'unknown';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  if not exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  )
  then
    raise exception 'Business does not exist or is not active';
  end if;

  if not exists (
    select 1
    from public.branches br
    where br.id = p_branch_id
      and br.business_id = p_business_id
      and br.deleted_at is null
      and coalesce(br.status, 'active') = 'active'
  )
  then
    raise exception 'Branch does not exist or is not active for this business';
  end if;

  if not exists (
    select 1
    from public.business_members bm
    where bm.profile_id = v_profile_id
      and bm.business_id = p_business_id
      and bm.status = 'active'
      and bm.deleted_at is null
      and (
        bm.branch_id is null
        or bm.branch_id = p_branch_id
      )
  )
  then
    raise exception 'No active membership grants access to this business and branch';
  end if;

  select ad.*
  into v_existing
  from public.app_devices ad
  where ad.business_id = p_business_id
    and ad.installation_id = v_installation_id
    and ad.deleted_at is null
  order by ad.created_at, ad.id
  limit 1
  for update;

  if v_existing.id is not null
     and v_existing.status = 'blocked'
  then
    raise exception using
      errcode = 'P0001',
      message = 'App device is blocked and cannot be reactivated by self-registration',
      hint = 'An explicit administrative unblock action is required.';
  end if;

  if v_existing.id is null then
    insert into public.app_devices (
      business_id,
      profile_id,
      branch_id,
      installation_id,
      device_name,
      platform,
      app_version,
      os_version,
      status,
      last_seen_at,
      sync_status,
      version,
      metadata,
      created_by,
      updated_by
    )
    values (
      p_business_id,
      v_profile_id,
      p_branch_id,
      v_installation_id,
      coalesce(v_device_name, 'Dispositivo sin nombre'),
      v_platform,
      p_app_version,
      p_os_version,
      'active',
      now(),
      'synced',
      1,
      v_metadata
        || jsonb_build_object(
          'registered_via', 'public.register_or_update_app_device',
          'last_registration_at', now()
        ),
      v_profile_id,
      v_profile_id
    )
    returning *
    into v_app_device;

    v_created_or_updated := 'created';
  else
    update public.app_devices ad
    set
      profile_id = v_profile_id,
      branch_id = p_branch_id,
      device_name = coalesce(v_device_name, ad.device_name),
      platform = coalesce(v_platform, ad.platform),
      app_version = coalesce(p_app_version, ad.app_version),
      os_version = coalesce(p_os_version, ad.os_version),
      status = 'active',
      last_seen_at = now(),
      sync_status = 'synced',
      metadata = coalesce(ad.metadata, '{}'::jsonb)
        || v_metadata
        || jsonb_build_object(
          'updated_via', 'public.register_or_update_app_device',
          'last_registration_at', now()
        ),
      updated_at = now(),
      updated_by = v_profile_id
    where ad.id = v_existing.id
    returning *
    into v_app_device;

    v_created_or_updated := 'updated';
  end if;

  return jsonb_build_object(
    'app_device_id', v_app_device.id,
    'business_id', v_app_device.business_id,
    'branch_id', v_app_device.branch_id,
    'profile_id', v_app_device.profile_id,
    'installation_id', v_app_device.installation_id,
    'device_name', v_app_device.device_name,
    'platform', v_app_device.platform,
    'app_version', v_app_device.app_version,
    'os_version', v_app_device.os_version,
    'status', v_app_device.status,
    'last_seen_at', v_app_device.last_seen_at,
    'created_or_updated', v_created_or_updated,
    'sync_status', v_app_device.sync_status,
    'version', v_app_device.version
  );
end;
$$;

revoke all on function public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
) from public;

revoke all on function public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
) from anon;

grant execute on function public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
) to authenticated, service_role;

comment on function public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
) is
'Registers or updates a business + installation device for an explicitly authorized active branch. Blocked devices require administrative unblock.';

commit;
