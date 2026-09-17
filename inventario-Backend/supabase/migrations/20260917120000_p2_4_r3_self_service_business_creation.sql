-- P2.4R3 - Secure self-service business creation.
--
-- Authenticated users may create one new tenant for themselves without
-- choosing tenant, branch, profile, role, or runtime identifiers. Durable
-- actor-scoped idempotency maps retries to the same server-generated IDs; the
-- existing create_business RPC remains the only provisioning engine.

begin;

-- =========================================================
-- DURABLE SELF-SERVICE IDEMPOTENCY
-- =========================================================

create table if not exists private.self_service_business_creation_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_user_id uuid not null
    references auth.users(id) on delete restrict,
  idempotency_key text not null,
  request_payload jsonb not null,
  business_id uuid not null default extensions.gen_random_uuid(),
  branch_id uuid not null default extensions.gen_random_uuid(),
  status text not null default 'pending',
  result jsonb,
  created_at timestamptz not null default statement_timestamp(),
  completed_at timestamptz,

  constraint self_service_business_creation_requests_key_not_blank
    check (
      length(btrim(idempotency_key)) > 0
      and length(btrim(idempotency_key)) <= 200
    ),
  constraint self_service_business_creation_requests_payload_object
    check (jsonb_typeof(request_payload) = 'object'),
  constraint self_service_business_creation_requests_status_valid
    check (status in ('pending', 'completed')),
  constraint self_service_business_creation_requests_completion_valid
    check (
      (status = 'pending' and completed_at is null and result is null)
      or
      (status = 'completed' and completed_at is not null and result is not null)
    ),
  constraint self_service_business_creation_requests_actor_key_unique
    unique (actor_user_id, idempotency_key),
  constraint self_service_business_creation_requests_business_unique
    unique (business_id),
  constraint self_service_business_creation_requests_branch_unique
    unique (branch_id),
  constraint self_service_business_creation_requests_business_fkey
    foreign key (business_id)
    references public.businesses(id)
    on delete restrict
    deferrable initially deferred,
  constraint self_service_business_creation_requests_branch_fkey
    foreign key (branch_id)
    references public.branches(id)
    on delete restrict
    deferrable initially deferred
);

alter table private.self_service_business_creation_requests
  enable row level security;

comment on table private.self_service_business_creation_requests is
'Durably binds an authenticated actor and opaque idempotency key to the canonical tenant IDs created by public.create_self_service_business. It is private infrastructure, not a client table or sync outbox.';

revoke all on table private.self_service_business_creation_requests
from public, anon, authenticated, service_role;

-- =========================================================
-- PUBLIC SELF-SERVICE WRAPPER
-- =========================================================

create or replace function public.create_self_service_business(
  p_business_name text,
  p_idempotency_key text,
  p_branch_name text default 'Sucursal Principal'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_user_id uuid;
  v_business_name text;
  v_branch_name text;
  v_idempotency_key text;
  v_request_payload jsonb;
  v_request private.self_service_business_creation_requests%rowtype;
  v_created_request_id uuid;
  v_onboarding jsonb;
  v_result jsonb;
begin
  v_actor_user_id := auth.uid();

  if v_actor_user_id is null then
    raise exception using
      errcode = '42501',
      message = 'Authentication required';
  end if;

  v_business_name := nullif(btrim(coalesce(p_business_name, '')), '');
  v_branch_name := coalesce(
    nullif(btrim(coalesce(p_branch_name, '')), ''),
    'Sucursal Principal'
  );
  v_idempotency_key := nullif(
    btrim(coalesce(p_idempotency_key, '')),
    ''
  );

  if v_business_name is null then
    raise exception using
      errcode = '22023',
      message = 'business_name is required';
  end if;
  if char_length(v_business_name) > 255 then
    raise exception using
      errcode = '22023',
      message = 'business_name exceeds 255 characters';
  end if;
  if char_length(v_branch_name) > 255 then
    raise exception using
      errcode = '22023',
      message = 'branch_name exceeds 255 characters';
  end if;
  if v_idempotency_key is null then
    raise exception using
      errcode = '22023',
      message = 'idempotency_key is required';
  end if;
  if char_length(v_idempotency_key) > 200 then
    raise exception using
      errcode = '22023',
      message = 'idempotency_key exceeds 200 characters';
  end if;

  if not exists (
    select 1
    from auth.users auth_user
    where auth_user.id = v_actor_user_id
      and auth_user.deleted_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'Authenticated user does not exist or is deleted';
  end if;

  v_request_payload := jsonb_build_object(
    'business_name', v_business_name,
    'branch_name', v_branch_name
  );

  insert into private.self_service_business_creation_requests (
    actor_user_id,
    idempotency_key,
    request_payload
  ) values (
    v_actor_user_id,
    v_idempotency_key,
    v_request_payload
  )
  on conflict (actor_user_id, idempotency_key) do nothing
  returning id into v_created_request_id;

  select request.* into v_request
  from private.self_service_business_creation_requests request
  where request.actor_user_id = v_actor_user_id
    and request.idempotency_key = v_idempotency_key
  for update;

  if v_request.id is null then
    raise exception 'Unable to reserve self-service business creation request';
  end if;

  if v_request.request_payload <> v_request_payload then
    raise exception using
      errcode = '23505',
      message = 'self_service_business_creation_idempotency_conflict';
  end if;

  if v_created_request_id is null then
    if v_request.status <> 'completed'
       or v_request.completed_at is null
       or v_request.result is null then
      raise exception using
        errcode = '55000',
        message = 'Self-service business creation request is incomplete';
    end if;

    return v_request.result;
  end if;

  v_onboarding := public.create_business(
    v_request.business_id,
    v_request.branch_id,
    v_business_name,
    v_branch_name,
    'Caja Principal',
    null,
    jsonb_build_object(
      'source', 'public.create_self_service_business',
      'creation_request_id', v_request.id
    )
  );

  if v_onboarding ->> 'business_id' is distinct from v_request.business_id::text
     or v_onboarding ->> 'branch_id' is distinct from v_request.branch_id::text
     or not coalesce((v_onboarding ->> 'runtime_ready')::boolean, false) then
    raise exception 'Self-service onboarding returned an inconsistent result';
  end if;

  v_result := jsonb_build_object(
    'business_id', v_request.business_id,
    'branch_id', v_request.branch_id
  );

  insert into public.activity_logs (
    id,
    business_id,
    user_id,
    action,
    affected_table,
    record_id,
    metadata,
    created_at
  ) values (
    extensions.gen_random_uuid(),
    v_request.business_id,
    v_actor_user_id,
    'BUSINESS_CREATED_SELF_SERVICE',
    'businesses',
    v_request.business_id,
    jsonb_build_object(
      'branch_id', v_request.branch_id,
      'source', 'public.create_self_service_business'
    ),
    statement_timestamp()
  );

  update private.self_service_business_creation_requests request
  set
    status = 'completed',
    result = v_result,
    completed_at = statement_timestamp()
  where request.id = v_request.id
  returning request.* into v_request;

  return v_request.result;
end;
$$;

alter function public.create_self_service_business(text, text, text)
  owner to postgres;

revoke all on function public.create_self_service_business(text, text, text)
from public, anon;

grant execute on function public.create_self_service_business(text, text, text)
to authenticated, service_role;

comment on function public.create_self_service_business(text, text, text) is
'Creates one new business for auth.uid() by delegating to public.create_business. Server-generated tenant IDs are durably bound to an actor-scoped idempotency key; retries with a different normalized payload are rejected.';

commit;
