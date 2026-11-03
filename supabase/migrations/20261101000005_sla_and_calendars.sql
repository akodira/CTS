-- CTS migration 0005
-- SLA policies, business calendars, clocks and escalations.

begin;

create type public.sla_state as enum (
  'on_track',
  'due_soon',
  'breached',
  'paused',
  'completed'
);

create table public.business_calendars (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  timezone   text not null default 'Asia/Riyadh',
  is_24_7    boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.business_calendar_intervals (
  id          uuid primary key default gen_random_uuid(),
  calendar_id uuid not null references public.business_calendars (id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  start_time  time not null,
  end_time    time not null,
  check (start_time < end_time),
  unique (calendar_id, day_of_week, start_time)
);

create index business_calendar_intervals_calendar_idx
  on public.business_calendar_intervals (calendar_id, day_of_week, start_time);

create table public.holidays (
  id           uuid primary key default gen_random_uuid(),
  calendar_id  uuid not null references public.business_calendars (id) on delete cascade,
  holiday_date date not null,
  name_en      text not null,
  name_ar      text not null,
  is_recurring boolean not null default false,
  unique (calendar_id, holiday_date)
);

create index holidays_calendar_date_idx
  on public.holidays (calendar_id, holiday_date);

create table public.sla_policies (
  id                        uuid primary key default gen_random_uuid(),
  name                      text not null,
  priority_id               uuid references public.priorities (id) on delete cascade,
  category_id               uuid references public.ticket_categories (id) on delete cascade,
  team_id                   uuid references public.teams (id) on delete cascade,
  first_response_minutes    int not null check (first_response_minutes between 1 and 525600),
  resolution_minutes        int not null check (resolution_minutes between 1 and 525600),
  business_calendar_id      uuid not null references public.business_calendars (id),
  warning_threshold_pct     int not null default 75 check (warning_threshold_pct between 1 and 100),
  pause_on_pending_customer boolean not null default true,
  pause_on_pending_internal boolean not null default false,
  is_default                boolean not null default false,
  is_active                 boolean not null default true,
  version                   int not null default 1 check (version >= 1),
  effective_from            timestamptz not null default now(),
  created_at                timestamptz not null default now()
);

create unique index sla_policies_one_default
  on public.sla_policies (is_default)
  where is_default and is_active;

create unique index sla_policies_scope_key
  on public.sla_policies (priority_id, category_id, team_id) nulls not distinct
  where is_active;

create table public.sla_escalation_rules (
  id             uuid primary key default gen_random_uuid(),
  policy_id      uuid not null references public.sla_policies (id) on delete cascade,
  level          int not null check (level between 1 and 10),
  threshold_pct  int not null check (threshold_pct between 1 and 100),
  notify_role    text references public.roles (code),
  notify_team_id uuid references public.teams (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (policy_id, level)
);

create table public.ticket_sla_records (
  id                uuid primary key default gen_random_uuid(),
  ticket_id         uuid not null references public.tickets (id) on delete cascade,
  metric            text not null check (metric in ('first_response', 'resolution')),
  cycle             smallint not null default 1 check (cycle >= 1),
  policy_id         uuid not null references public.sla_policies (id),
  target_minutes    int not null check (target_minutes > 0),
  started_at        timestamptz not null,
  due_at            timestamptz not null,
  warning_at        timestamptz not null,
  paused_at         timestamptz,
  paused_seconds    int not null default 0 check (paused_seconds >= 0),
  completed_at      timestamptz,
  breached_at       timestamptz,
  state             public.sla_state not null default 'on_track',
  escalation_level  int not null default 0 check (escalation_level >= 0),
  last_evaluated_at timestamptz,
  created_at        timestamptz not null default now(),
  constraint ticket_sla_due_after_start check (due_at >= started_at),
  constraint ticket_sla_warning_before_due check (warning_at <= due_at),
  unique (ticket_id, metric, cycle)
);

create index ticket_sla_open_idx
  on public.ticket_sla_records (state, due_at)
  where state in ('on_track', 'due_soon');

create index ticket_sla_ticket_idx
  on public.ticket_sla_records (ticket_id);

create table public.sla_events (
  id            bigserial primary key,
  sla_record_id uuid not null references public.ticket_sla_records (id) on delete cascade,
  event_type    text not null check (event_type in (
                  'started', 'paused', 'resumed', 'warning',
                  'breached', 'escalated', 'completed'
                )),
  occurred_at   timestamptz not null default now(),
  metadata      jsonb not null default '{}'::jsonb,
  dedupe_key    text not null unique
);

create index sla_events_record_idx
  on public.sla_events (sla_record_id, occurred_at);

create table public.escalations (
  id                 uuid primary key default gen_random_uuid(),
  ticket_id          uuid not null references public.tickets (id) on delete cascade,
  sla_record_id      uuid references public.ticket_sla_records (id) on delete set null,
  level              int not null check (level between 1 and 10),
  escalated_to_role  text references public.roles (code),
  escalated_to_team  uuid references public.teams (id) on delete set null,
  reason             text,
  acknowledged_at    timestamptz,
  resolved_at        timestamptz,
  created_at         timestamptz not null default now(),
  dedupe_key         text not null unique
);

create index escalations_ticket_idx on public.escalations (ticket_id, created_at desc);

commit;
