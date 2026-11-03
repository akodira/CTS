-- CTS migration 0001
-- Schemas, shared helpers and extension-free foundations.
-- Target: Supabase PostgreSQL 17.
--
-- No extensions are required: gen_random_uuid() is core in PostgreSQL 13+,
-- and email uniqueness is enforced with a lower(email) index instead of citext.

begin;

create schema if not exists private;

revoke all on schema private from public;
grant usage on schema private to postgres, service_role, authenticated;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public;

comment on schema private is
  'Internal helper functions and rate-limit state. Not exposed through PostgREST.';

commit;
