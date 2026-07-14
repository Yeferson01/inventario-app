begin;

-- No tocamos sale_payments_method_check porque la BD ya usa
-- el valor canónico bank_transfer, además de nequi, daviplata, credit y other.
-- Flutter debe enviar bank_transfer, no transfer.

drop function if exists private.create_sync_conflict_for_mutation(
  uuid,
  text,
  text,
  jsonb,
  text,
  jsonb
);

create function private.create_sync_conflict_for_mutation(
  p_sync_mutation_id uuid,
  p_conflict_type text,
  p_severity text,
  p_server_payload jsonb default null,
  p_error_message text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_conflict_id uuid := gen_random_uuid();
begin
  update public.sync_mutations
  set
    status = case
      when p_severity in ('warning', 'info') then status
      else 'error'
    end,
    error_code = coalesce(p_conflict_type, error_code, 'sync_conflict'),
    error_message = coalesce(p_error_message, error_message),
    updated_at = now()
  where id = p_sync_mutation_id
    and status <> 'applied';

  if to_regclass('public.sync_conflicts') is not null then
    begin
      execute '
        insert into public.sync_conflicts (
          id,
          sync_mutation_id,
          conflict_type,
          severity,
          server_payload,
          error_message,
          metadata,
          created_at,
          updated_at
        )
        values ($1, $2, $3, $4, $5, $6, $7, now(), now())
        on conflict do nothing
      '
      using
        v_conflict_id,
        p_sync_mutation_id,
        coalesce(p_conflict_type, 'sync_conflict'),
        coalesce(p_severity, 'error'),
        p_server_payload,
        p_error_message,
        coalesce(p_metadata, '{}'::jsonb);
    exception
      when undefined_table or undefined_column then
        null;
    end;
  end if;

  return v_conflict_id;
end;
$$;

grant execute on function private.create_sync_conflict_for_mutation(
  uuid,
  text,
  text,
  jsonb,
  text,
  jsonb
) to authenticated, service_role;

commit;
