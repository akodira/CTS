-- CTS migration 0006
-- Notifications, transactional email outbox, audit trail and settings.

begin;

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  ticket_id  uuid references public.tickets (id) on delete cascade,
  type       text not null,
  payload    jsonb not null default '{}'::jsonb,
  read_at    timestamptz,
  dedupe_key text not null unique,
  created_at timestamptz not null default now()
);

create index notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index notifications_unread_idx
  on public.notifications (user_id)
  where read_at is null;

create table public.email_outbox (
  id              uuid primary key default gen_random_uuid(),
  to_email        text not null check (position('@' in to_email) > 1),
  template_key    text not null,
  locale          text not null check (locale in ('en', 'ar')),
  payload         jsonb not null default '{}'::jsonb,
  status          text not null default 'pending'
                  check (status in ('pending', 'sending', 'sent', 'failed', 'cancelled')),
  attempts        int not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  sent_at         timestamptz,
  last_error      text,
  dedupe_key      text not null unique,
  created_at      timestamptz not null default now()
);

create index email_outbox_pending_idx
  on public.email_outbox (next_attempt_at)
  where status in ('pending', 'failed');

create table public.audit_logs (
  id          bigserial primary key,
  actor_id    uuid references public.profiles (id) on delete set null,
  actor_type  text not null default 'user' check (actor_type in ('user', 'system', 'anonymous')),
  action      text not null,
  entity_type text not null,
  entity_id   text,
  before      jsonb,
  after       jsonb,
  request_id  text,
  ip          inet,
  user_agent  text,
  created_at  timestamptz not null default now()
);

create index audit_logs_entity_idx
  on public.audit_logs (entity_type, entity_id, created_at desc);
create index audit_logs_actor_idx
  on public.audit_logs (actor_id, created_at desc);

create or replace function private.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'AUDIT_LOGS_ARE_APPEND_ONLY' using errcode = '42501';
end;
$$;

revoke all on function private.prevent_audit_mutation() from public;

create trigger audit_logs_append_only
before update or delete on public.audit_logs
for each row execute function private.prevent_audit_mutation();

create table public.system_settings (
  key         text primary key,
  value       jsonb not null,
  description text,
  updated_by  uuid references public.profiles (id) on delete set null,
  updated_at  timestamptz not null default now()
);

create trigger system_settings_set_updated_at
before update on public.system_settings
for each row execute function private.set_updated_at();

commit;
