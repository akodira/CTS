-- CTS migration 0004
-- Ticket core: references, thread, assignments and status history.

begin;

create type public.ticket_status as enum (
  'new',
  'open',
  'in_progress',
  'pending_customer',
  'pending_internal',
  'resolved',
  'closed',
  'reopened'
);

create type public.message_visibility as enum ('public', 'internal');

create table public.ticket_number_counters (
  ticket_year int primary key check (ticket_year between 2000 and 9999),
  last_value  bigint not null default 0 check (last_value >= 0)
);

create table public.tickets (
  id                     uuid primary key default gen_random_uuid(),
  reference              text not null unique
                         check (reference ~ '^CTS-[0-9]{4}-[0-9]{6}$'),
  subject                text not null check (char_length(subject) between 5 and 200),
  description            text not null check (char_length(description) >= 10),
  customer_id            uuid not null references public.profiles (id) on delete restrict,
  organization_id        uuid references public.organizations (id) on delete set null,
  category_id            uuid not null references public.ticket_categories (id) on delete restrict,
  priority_id            uuid not null references public.priorities (id) on delete restrict,
  status                 public.ticket_status not null default 'new',
  team_id                uuid references public.teams (id) on delete set null,
  assignee_id            uuid references public.profiles (id) on delete set null,
  locale                 text not null default 'en' check (locale in ('en', 'ar')),
  source                 text not null default 'web' check (source = 'web'),
  first_response_at      timestamptz,
  resolved_at            timestamptz,
  closed_at              timestamptz,
  reopened_at            timestamptz,
  reopen_count           int not null default 0 check (reopen_count >= 0),
  resolution_summary     text,
  resolution_by          uuid references public.profiles (id) on delete set null,
  customer_confirmed_at  timestamptz,
  last_public_message_at timestamptz,
  version                int not null default 1 check (version >= 1),
  search_vector          tsvector generated always as (
                           setweight(to_tsvector('simple', coalesce(subject, '')), 'A') ||
                           setweight(to_tsvector('simple', coalesce(description, '')), 'B')
                         ) stored,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index tickets_customer_idx on public.tickets (customer_id, updated_at desc);
create index tickets_queue_idx on public.tickets (team_id, status, priority_id, updated_at desc);
create index tickets_assignee_idx on public.tickets (assignee_id, status);
create index tickets_status_idx on public.tickets (status, updated_at desc);
create index tickets_search_idx on public.tickets using gin (search_vector);

create trigger tickets_set_updated_at
before update on public.tickets
for each row execute function private.set_updated_at();

create table public.ticket_status_history (
  id                  bigserial primary key,
  ticket_id           uuid not null references public.tickets (id) on delete cascade,
  from_status         public.ticket_status,
  to_status           public.ticket_status not null,
  changed_by          uuid references public.profiles (id) on delete set null,
  actor_type          text not null default 'user' check (actor_type in ('user', 'system')),
  reason              text,
  is_customer_visible boolean not null default true,
  changed_at          timestamptz not null default now()
);

create index ticket_status_history_ticket_idx
  on public.ticket_status_history (ticket_id, changed_at);

create table public.ticket_transition_rules (
  from_status     public.ticket_status not null,
  to_status       public.ticket_status not null,
  allowed_roles   text[] not null check (array_length(allowed_roles, 1) >= 1),
  customer_allowed boolean not null default false,
  requires_reason boolean not null default false,
  primary key (from_status, to_status)
);

create table public.ticket_custom_field_values (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets (id) on delete cascade,
  field_id   uuid not null references public.ticket_custom_fields (id) on delete cascade,
  value      jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (ticket_id, field_id)
);

create index ticket_custom_field_values_ticket_idx
  on public.ticket_custom_field_values (ticket_id);

create trigger ticket_custom_field_values_set_updated_at
before update on public.ticket_custom_field_values
for each row execute function private.set_updated_at();

create table public.ticket_messages (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets (id) on delete cascade,
  author_id   uuid references public.profiles (id) on delete set null,
  visibility  public.message_visibility not null default 'public',
  body        text not null check (char_length(body) between 1 and 20000),
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  deleted_at  timestamptz,
  constraint ticket_messages_author_required
    check (is_system or author_id is not null)
);

create index ticket_messages_thread_idx
  on public.ticket_messages (ticket_id, created_at);
create index ticket_messages_public_idx
  on public.ticket_messages (ticket_id, created_at)
  where visibility = 'public' and deleted_at is null;

create table public.ticket_attachments (
  id           uuid primary key default gen_random_uuid(),
  ticket_id    uuid references public.tickets (id) on delete cascade,
  message_id   uuid references public.ticket_messages (id) on delete set null,
  uploaded_by  uuid not null references public.profiles (id) on delete restrict,
  storage_path text not null unique,
  file_name    text not null check (char_length(file_name) between 1 and 255),
  mime_type    text not null,
  size_bytes   bigint not null check (size_bytes between 1 and 26214400),
  checksum     text,
  visibility   public.message_visibility not null default 'public',
  status       text not null default 'draft' check (status in ('draft', 'linked')),
  created_at   timestamptz not null default now(),
  constraint ticket_attachments_status_consistency check (
    (status = 'draft' and ticket_id is null) or
    (status = 'linked' and ticket_id is not null)
  )
);

create index ticket_attachments_ticket_idx
  on public.ticket_attachments (ticket_id, created_at);
create index ticket_attachments_draft_idx
  on public.ticket_attachments (uploaded_by, created_at)
  where status = 'draft';

create table public.ticket_assignments (
  id          uuid primary key default gen_random_uuid(),
  ticket_id   uuid not null references public.tickets (id) on delete cascade,
  assigned_to uuid references public.profiles (id) on delete set null,
  team_id     uuid references public.teams (id) on delete set null,
  assigned_by uuid references public.profiles (id) on delete set null,
  assigned_at timestamptz not null default now(),
  ended_at    timestamptz,
  reason      text,
  check (ended_at is null or ended_at >= assigned_at)
);

create unique index ticket_assignments_current_key
  on public.ticket_assignments (ticket_id)
  where ended_at is null;

create index ticket_assignments_agent_idx
  on public.ticket_assignments (assigned_to, assigned_at desc);

commit;
