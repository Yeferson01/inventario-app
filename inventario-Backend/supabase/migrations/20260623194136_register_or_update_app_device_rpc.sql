-- =========================================================
-- Fase 6.19A - register_or_update_app_device RPC
-- Objetivo:
-- - Centralizar el registro/actualización de instalaciones Flutter.
-- - Evitar duplicados por business_id + installation_id.
-- - Validar membresía, sucursal y permisos por RLS/helpers.
-- - Devolver app_device_id estable para la app.
-- =========================================================

-- 1. Índice único lógico por negocio + instalación activa.
-- Esto evita que el mismo dispositivo/app installation se registre varias veces
-- para el mismo negocio.
create unique index if not exists idx_app_devices_business_installation_active_unique
on public.app_devices (business_id, installation_id)
where deleted_at is null;

-- 2. Índice auxiliar para búsquedas por perfil/dispositivo.
create index if not exists idx_app_devices_profile_business_status
on public.app_devices (profile_id, business_id, status)
where deleted_at is null;

-- 3. RPC principal.
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
  -- Auth obligatoria.
  v_profile_id := private.current_profile_id();

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

  -- La persona debe pertenecer al negocio.
  if not private.is_business_member(p_business_id) then
    raise exception 'Insufficient permission to register app device for this business';
  end if;

  -- La sucursal debe pertenecer al negocio y el usuario debe tener acceso.
  if not private.has_branch_access(p_business_id, p_branch_id) then
    raise exception 'Insufficient permission to register app device for this branch';
  end if;

  -- Verificar que la sucursal esté activa.
  if not exists (
    select 1
    from public.branches b
    where b.id = p_branch_id
      and b.business_id = p_business_id
      and b.deleted_at is null
      and coalesce(b.status, 'active') = 'active'
  ) then
    raise exception 'Branch does not exist or is not active for this business';
  end if;

  -- Buscar dispositivo existente activo por negocio + installation_id.
  select ad.*
  into v_existing
  from public.app_devices ad
  where ad.business_id = p_business_id
    and ad.installation_id = v_installation_id
    and ad.deleted_at is null
  limit 1
  for update;

  if v_existing.id is null then
    -- Crear nuevo app_device.
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
    -- Actualizar dispositivo existente.
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

-- 4. Permisos.
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

grant execute on function public.register_or_update_app_device(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  jsonb
) to authenticated;

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
'Registers or updates a Flutter app installation device for offline-first sync. Returns a stable app_device_id for the app.';