-- =========================================================
-- Patch - Fix create_activity_log search_path issue
-- Problema:
-- - Triggers legacy usan create_activity_log().
-- - La función hacía INSERT INTO activity_logs sin schema.
-- - RPCs nuevas usan search_path = '', entonces activity_logs no se encuentra.
--
-- Solución:
-- - Reemplazar create_activity_log() usando public.activity_logs.
-- - Usar extensions.gen_random_uuid().
-- - Usar auth.uid() calificado.
-- - Leer business_id / id vía to_jsonb para ser más robusto.
-- =========================================================

create or replace function public.create_activity_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb;
  v_new jsonb;

  v_business_id uuid;
  v_record_id uuid;
  v_user_id uuid;
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old);
    v_new := null;
  elsif tg_op = 'INSERT' then
    v_old := null;
    v_new := to_jsonb(new);
  else
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
  end if;

  v_business_id := nullif(
    coalesce(
      v_new->>'business_id',
      v_old->>'business_id'
    ),
    ''
  )::uuid;

  v_record_id := nullif(
    coalesce(
      v_new->>'id',
      v_old->>'id'
    ),
    ''
  )::uuid;

  v_user_id := auth.uid();

  insert into public.activity_logs (
    id,
    business_id,
    user_id,
    action,
    affected_table,
    record_id,
    metadata,
    created_at
  )
  values (
    extensions.gen_random_uuid(),
    v_business_id,
    v_user_id,
    tg_op,
    tg_table_name,
    v_record_id,
    jsonb_build_object(
      'old_data', v_old,
      'new_data', v_new,
      'trigger_schema', tg_table_schema,
      'trigger_table', tg_table_name,
      'fixed_via', 'patch_activity_log_search_path'
    ),
    now()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

comment on function public.create_activity_log() is
'Creates activity log records using fully-qualified public.activity_logs, safe for RPCs with empty search_path.';