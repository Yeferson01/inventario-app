-- =========================================================
-- Fase 6.19B - Business runtime onboarding RPC
-- Objetivo:
-- - Asegurar que un business existente tenga runtime mínimo POS/offline:
--   owner membership, branch principal, cash register principal y receipt sequence.
-- - Ser idempotente.
-- - Evitar que Flutter tenga que crear manualmente la estructura base.
-- =========================================================

-- Helper interno para validar columnas existentes sin romper migraciones futuras.
create or replace function private.public_column_exists(
  p_table_name text,
  p_column_name text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.table_name = p_table_name
      and c.column_name = p_column_name
  );
$$;

-- RPC principal.
create or replace function public.ensure_business_runtime_setup(
  p_business_id uuid,
  p_default_branch_name text default 'Principal',
  p_default_cash_register_name text default 'Caja Principal',
  p_receipt_prefix text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile_id uuid;

  v_business_exists boolean := false;
  v_is_business_owner_reference boolean := false;
  v_is_business_creator_reference boolean := false;
  v_has_membership boolean := false;
  v_can_manage boolean := false;

  v_owner_role_id uuid;
  v_membership_id uuid;
  v_membership_created boolean := false;

  v_branch_id uuid;
  v_branch_created boolean := false;
  v_branch_name text;

  v_cash_register_id uuid;
  v_cash_register_created boolean := false;
  v_cash_register_name text;

  v_receipt_sequence_id uuid;
  v_receipt_sequence_created boolean := false;
  v_receipt_prefix text;

  v_metadata jsonb;

  v_cols text;
  v_vals text;
  v_sql text;

  v_code text;
begin
  -- Auth obligatoria.
  v_profile_id := private.current_profile_id();

  if v_profile_id is null then
    raise exception 'Authentication required';
  end if;

  if p_business_id is null then
    raise exception 'business_id is required';
  end if;

  v_branch_name := nullif(btrim(coalesce(p_default_branch_name, '')), '');
  if v_branch_name is null then
    v_branch_name := 'Principal';
  end if;

  v_cash_register_name := nullif(btrim(coalesce(p_default_cash_register_name, '')), '');
  if v_cash_register_name is null then
    v_cash_register_name := 'Caja Principal';
  end if;

  v_receipt_prefix := upper(nullif(btrim(coalesce(p_receipt_prefix, '')), ''));
  if v_receipt_prefix is null then
    v_receipt_prefix := 'POS';
  end if;

  v_metadata := coalesce(p_metadata, '{}'::jsonb);

  if jsonb_typeof(v_metadata) <> 'object' then
    raise exception 'metadata must be a JSON object';
  end if;

  -- Verificar business existente.
  select exists (
    select 1
    from public.businesses b
    where b.id = p_business_id
      and b.deleted_at is null
  )
  into v_business_exists;

  if not v_business_exists then
    raise exception 'Business does not exist or is deleted';
  end if;

  -- Detectar si el usuario aparece como owner_id del business.
  if private.public_column_exists('businesses', 'owner_id') then
    execute
      'select exists (
         select 1
         from public.businesses b
         where b.id = $1
           and b.deleted_at is null
           and b.owner_id = $2
       )'
    using p_business_id, v_profile_id
    into v_is_business_owner_reference;
  end if;

  -- Detectar si el usuario aparece como created_by del business.
  if private.public_column_exists('businesses', 'created_by') then
    execute
      'select exists (
         select 1
         from public.businesses b
         where b.id = $1
           and b.deleted_at is null
           and b.created_by = $2
       )'
    using p_business_id, v_profile_id
    into v_is_business_creator_reference;
  end if;

  -- Verificar membership existente.
  select exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.profile_id = v_profile_id
      and bm.deleted_at is null
      and coalesce(bm.status, 'active') = 'active'
  )
  into v_has_membership;

  -- Si el usuario es owner/creator del business pero aún no tiene membership,
  -- crear membership owner automáticamente.
  if not v_has_membership
     and (v_is_business_owner_reference or v_is_business_creator_reference)
  then
    select r.id
    into v_owner_role_id
    from public.roles r
    where r.name = 'owner'
      and r.deleted_at is null
      and (r.business_id is null or r.business_id = p_business_id)
    order by r.business_id nulls first, r.created_at
    limit 1;

    if v_owner_role_id is null then
      raise exception 'Owner role not found';
    end if;

    -- Insert dinámico para tolerar columnas futuras/opcionales.
    v_cols := 'business_id, profile_id, role_id';
    v_vals := format(
      '%L::uuid, %L::uuid, %L::uuid',
      p_business_id::text,
      v_profile_id::text,
      v_owner_role_id::text
    );

    if private.public_column_exists('business_members', 'status') then
      v_cols := v_cols || ', status';
      v_vals := v_vals || format(', %L', 'active');
    end if;

    if private.public_column_exists('business_members', 'branch_id') then
      v_cols := v_cols || ', branch_id';
      v_vals := v_vals || ', null::uuid';
    end if;

    if private.public_column_exists('business_members', 'created_by') then
      v_cols := v_cols || ', created_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('business_members', 'updated_by') then
      v_cols := v_cols || ', updated_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('business_members', 'metadata') then
      v_cols := v_cols || ', metadata';
      v_vals := v_vals || format(
        ', %L::jsonb',
        (
          v_metadata
          || jsonb_build_object(
            'created_via', 'public.ensure_business_runtime_setup',
            'phase', '6.19B'
          )
        )::text
      );
    end if;

    v_sql := format(
      'insert into public.business_members (%s) values (%s) returning id',
      v_cols,
      v_vals
    );

    execute v_sql into v_membership_id;

    v_membership_created := true;
    v_has_membership := true;
  end if;

  -- Validar permisos.
  v_can_manage :=
    private.has_business_permission(p_business_id, 'settings.business')
    or private.has_business_permission(p_business_id, 'business.update')
    or private.has_business_permission(p_business_id, 'branches.update')
    or private.has_business_permission(p_business_id, 'branches.create')
    or (
      v_has_membership
      and (v_is_business_owner_reference or v_is_business_creator_reference)
    );

  if not v_can_manage then
    raise exception 'Insufficient permission to initialize business runtime';
  end if;

  -- Si ya existía membership, obtener su id.
  if v_membership_id is null then
    select bm.id
    into v_membership_id
    from public.business_members bm
    join public.roles r on r.id = bm.role_id
    where bm.business_id = p_business_id
      and bm.profile_id = v_profile_id
      and bm.deleted_at is null
      and coalesce(bm.status, 'active') = 'active'
    order by
      case when r.name = 'owner' then 0 else 1 end,
      bm.created_at
    limit 1;
  end if;

  -- =========================================================
  -- 1. Asegurar branch principal por nombre
  -- =========================================================

  select br.id
  into v_branch_id
  from public.branches br
  where br.business_id = p_business_id
    and br.deleted_at is null
    and lower(br.name) = lower(v_branch_name)
  order by br.created_at
  limit 1
  for update;

  if v_branch_id is null then
    v_code := 'BR-' || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 8));

    v_cols := 'business_id, name';
    v_vals := format('%L::uuid, %L', p_business_id::text, v_branch_name);

    if private.public_column_exists('branches', 'code') then
      v_cols := v_cols || ', code';
      v_vals := v_vals || format(', %L', v_code);
    end if;

    if private.public_column_exists('branches', 'status') then
      v_cols := v_cols || ', status';
      v_vals := v_vals || format(', %L', 'active');
    end if;

    if private.public_column_exists('branches', 'is_default') then
      v_cols := v_cols || ', is_default';
      v_vals := v_vals || ', true';
    end if;

    if private.public_column_exists('branches', 'sync_status') then
      v_cols := v_cols || ', sync_status';
      v_vals := v_vals || format(', %L', 'synced');
    end if;

    if private.public_column_exists('branches', 'version') then
      v_cols := v_cols || ', version';
      v_vals := v_vals || ', 1';
    end if;

    if private.public_column_exists('branches', 'created_by') then
      v_cols := v_cols || ', created_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('branches', 'updated_by') then
      v_cols := v_cols || ', updated_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('branches', 'metadata') then
      v_cols := v_cols || ', metadata';
      v_vals := v_vals || format(
        ', %L::jsonb',
        (
          v_metadata
          || jsonb_build_object(
            'created_via', 'public.ensure_business_runtime_setup',
            'runtime_role', 'default_branch',
            'phase', '6.19B'
          )
        )::text
      );
    end if;

    v_sql := format(
      'insert into public.branches (%s) values (%s) returning id',
      v_cols,
      v_vals
    );

    execute v_sql into v_branch_id;
    v_branch_created := true;
  end if;

  -- =========================================================
  -- 2. Asegurar caja principal por branch
  -- =========================================================

  select cr.id
  into v_cash_register_id
  from public.cash_registers cr
  where cr.business_id = p_business_id
    and cr.branch_id = v_branch_id
    and cr.deleted_at is null
    and lower(cr.name) = lower(v_cash_register_name)
  order by cr.created_at
  limit 1
  for update;

  if v_cash_register_id is null then
    v_code := 'REG-' || upper(substr(replace(extensions.gen_random_uuid()::text, '-', ''), 1, 8));

    v_cols := 'business_id, branch_id, name';
    v_vals := format(
      '%L::uuid, %L::uuid, %L',
      p_business_id::text,
      v_branch_id::text,
      v_cash_register_name
    );

    if private.public_column_exists('cash_registers', 'code') then
      v_cols := v_cols || ', code';
      v_vals := v_vals || format(', %L', v_code);
    end if;

    if private.public_column_exists('cash_registers', 'status') then
      v_cols := v_cols || ', status';
      v_vals := v_vals || format(', %L', 'active');
    end if;

    if private.public_column_exists('cash_registers', 'sync_status') then
      v_cols := v_cols || ', sync_status';
      v_vals := v_vals || format(', %L', 'synced');
    end if;

    if private.public_column_exists('cash_registers', 'version') then
      v_cols := v_cols || ', version';
      v_vals := v_vals || ', 1';
    end if;

    if private.public_column_exists('cash_registers', 'created_by') then
      v_cols := v_cols || ', created_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('cash_registers', 'updated_by') then
      v_cols := v_cols || ', updated_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('cash_registers', 'metadata') then
      v_cols := v_cols || ', metadata';
      v_vals := v_vals || format(
        ', %L::jsonb',
        (
          v_metadata
          || jsonb_build_object(
            'created_via', 'public.ensure_business_runtime_setup',
            'runtime_role', 'default_cash_register',
            'phase', '6.19B'
          )
        )::text
      );
    end if;

    v_sql := format(
      'insert into public.cash_registers (%s) values (%s) returning id',
      v_cols,
      v_vals
    );

    execute v_sql into v_cash_register_id;
    v_cash_register_created := true;
  end if;

  -- =========================================================
  -- 3. Asegurar receipt_sequence para la branch
  -- =========================================================

  select rs.id
  into v_receipt_sequence_id
  from public.receipt_sequences rs
  where rs.business_id = p_business_id
    and rs.branch_id = v_branch_id
    and rs.deleted_at is null
  order by rs.created_at
  limit 1
  for update;

  if v_receipt_sequence_id is null then
    v_cols := 'business_id, branch_id';
    v_vals := format('%L::uuid, %L::uuid', p_business_id::text, v_branch_id::text);

    if private.public_column_exists('receipt_sequences', 'name') then
      v_cols := v_cols || ', name';
      v_vals := v_vals || format(', %L', 'Recibos ' || v_branch_name);
    end if;

    if private.public_column_exists('receipt_sequences', 'prefix') then
      v_cols := v_cols || ', prefix';
      v_vals := v_vals || format(', %L', v_receipt_prefix);
    end if;

    if private.public_column_exists('receipt_sequences', 'sequence_type') then
      v_cols := v_cols || ', sequence_type';
      v_vals := v_vals || format(', %L', 'sale_receipt');
    end if;

    if private.public_column_exists('receipt_sequences', 'document_type') then
      v_cols := v_cols || ', document_type';
      v_vals := v_vals || format(', %L', 'sale_receipt');
    end if;

    if private.public_column_exists('receipt_sequences', 'current_number') then
      v_cols := v_cols || ', current_number';
      v_vals := v_vals || ', 0';
    end if;

    if private.public_column_exists('receipt_sequences', 'current_value') then
      v_cols := v_cols || ', current_value';
      v_vals := v_vals || ', 0';
    end if;

    if private.public_column_exists('receipt_sequences', 'last_number') then
      v_cols := v_cols || ', last_number';
      v_vals := v_vals || ', 0';
    end if;

    if private.public_column_exists('receipt_sequences', 'next_number') then
      v_cols := v_cols || ', next_number';
      v_vals := v_vals || ', 1';
    end if;

    if private.public_column_exists('receipt_sequences', 'padding_length') then
      v_cols := v_cols || ', padding_length';
      v_vals := v_vals || ', 6';
    end if;

    if private.public_column_exists('receipt_sequences', 'status') then
      v_cols := v_cols || ', status';
      v_vals := v_vals || format(', %L', 'active');
    end if;

    if private.public_column_exists('receipt_sequences', 'sync_status') then
      v_cols := v_cols || ', sync_status';
      v_vals := v_vals || format(', %L', 'synced');
    end if;

    if private.public_column_exists('receipt_sequences', 'version') then
      v_cols := v_cols || ', version';
      v_vals := v_vals || ', 1';
    end if;

    if private.public_column_exists('receipt_sequences', 'created_by') then
      v_cols := v_cols || ', created_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('receipt_sequences', 'updated_by') then
      v_cols := v_cols || ', updated_by';
      v_vals := v_vals || format(', %L::uuid', v_profile_id::text);
    end if;

    if private.public_column_exists('receipt_sequences', 'metadata') then
      v_cols := v_cols || ', metadata';
      v_vals := v_vals || format(
        ', %L::jsonb',
        (
          v_metadata
          || jsonb_build_object(
            'created_via', 'public.ensure_business_runtime_setup',
            'runtime_role', 'default_receipt_sequence',
            'phase', '6.19B'
          )
        )::text
      );
    end if;

    v_sql := format(
      'insert into public.receipt_sequences (%s) values (%s) returning id',
      v_cols,
      v_vals
    );

    execute v_sql into v_receipt_sequence_id;
    v_receipt_sequence_created := true;
  end if;

  return jsonb_build_object(
    'business_id', p_business_id,
    'profile_id', v_profile_id,

    'owner_membership_id', v_membership_id,
    'owner_membership_created', v_membership_created,

    'branch_id', v_branch_id,
    'branch_name', v_branch_name,
    'branch_created', v_branch_created,

    'cash_register_id', v_cash_register_id,
    'cash_register_name', v_cash_register_name,
    'cash_register_created', v_cash_register_created,

    'receipt_sequence_id', v_receipt_sequence_id,
    'receipt_prefix', v_receipt_prefix,
    'receipt_sequence_created', v_receipt_sequence_created,

    'runtime_ready',
      v_branch_id is not null
      and v_cash_register_id is not null
      and v_receipt_sequence_id is not null,

    'created_anything',
      v_membership_created
      or v_branch_created
      or v_cash_register_created
      or v_receipt_sequence_created
  );
end;
$$;

revoke all on function public.ensure_business_runtime_setup(
  uuid,
  text,
  text,
  text,
  jsonb
) from public;

grant execute on function public.ensure_business_runtime_setup(
  uuid,
  text,
  text,
  text,
  jsonb
) to authenticated;

comment on function public.ensure_business_runtime_setup(
  uuid,
  text,
  text,
  text,
  jsonb
) is
'Ensures an existing business has the minimum runtime setup for POS/offline: owner membership if needed, default branch, cash register, and receipt sequence.';