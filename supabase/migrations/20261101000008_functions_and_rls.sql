-- CTS migration 0008
-- Authorization helpers, reference allocation, SLA math, RLS and grants.
--
-- Security model:
--   1. RLS decides which rows a session may read.
--   2. Ticket mutations are performed by SECURITY DEFINER RPCs (added in
--      Phase 3/4). Clients receive SELECT grants only.
--   3. The service role is never used from the browser.

begin;

-- ─── Authorization helpers ────────────────────────────────────────────────

create or replace function private.current_roles()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(ur.role_code order by ur.role_code), '{}'::text[])
  from public.user_roles ur
  where ur.user_id = (select auth.uid());
$$;

create or replace function private.has_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_roles ur
    where ur.user_id = (select auth.uid())
      and ur.role_code = p_role
  );
$$;

create or replace function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.current_roles() && array[
    'support_agent', 'team_leader', 'system_admin'
  ]::text[];
$$;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('system_admin');
$$;

create or replace function private.is_management_viewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_role('management_viewer');
$$;

create or replace function private.can_view_ticket(p_ticket_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tickets t
    where t.id = p_ticket_id
      and (
        t.customer_id = (select auth.uid())
        or private.is_admin()
        or (
          private.is_staff()
          and (
            t.assignee_id = (select auth.uid())
            or exists (
              select 1
              from public.team_members tm
              where tm.team_id = t.team_id
                and tm.user_id = (select auth.uid())
                and tm.is_active
            )
            or (t.team_id is null and private.has_role('support_agent'))
          )
        )
      )
  );
$$;

create or replace function private.can_manage_ticket(p_ticket_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tickets t
    where t.id = p_ticket_id
      and (
        private.is_admin()
        or (
          private.is_staff()
          and (
            t.assignee_id = (select auth.uid())
            or exists (
              select 1
              from public.team_members tm
              where tm.team_id = t.team_id
                and tm.user_id = (select auth.uid())
                and tm.team_role = 'leader'
                and tm.is_active
            )
          )
        )
      )
  );
$$;

create or replace function private.can_view_internal(p_ticket_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_staff() and private.can_view_ticket(p_ticket_id);
$$;

create or replace function private.can_access_team(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_admin()
    or exists (
      select 1
      from public.team_members tm
      where tm.team_id = p_team_id
        and tm.user_id = (select auth.uid())
        and tm.is_active
    );
$$;

-- ─── Reference allocation ─────────────────────────────────────────────────

/*
 * Concurrency-safe, per-year ticket reference allocator.
 * The upsert takes a row lock for the year and returns the next value, so two
 * concurrent create_ticket calls cannot receive the same sequence.
 * Gaps are allowed if a surrounding transaction rolls back.
 */
create or replace function private.allocate_ticket_reference(p_year int)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sequence bigint;
begin
  if p_year < 2000 or p_year > 9999 then
    raise exception 'INVALID_TICKET_YEAR' using errcode = '22023';
  end if;

  insert into public.ticket_number_counters (ticket_year, last_value)
  values (p_year, 1)
  on conflict (ticket_year) do update
    set last_value = public.ticket_number_counters.last_value + 1
  returning last_value into v_sequence;

  if v_sequence > 999999 then
    raise exception 'TICKET_SEQUENCE_EXHAUSTED' using errcode = '22003';
  end if;

  return 'CTS-' || p_year::text || '-' || lpad(v_sequence::text, 6, '0');
end;
$$;

-- ─── Business-hours arithmetic ────────────────────────────────────────────

/*
 * Adds business minutes to a timestamp inside a calendar, skipping closed
 * days and holidays. Multiple intervals per day are supported (for example
 * a lunch break). Deadline state itself is evaluated by comparing timestamps,
 * so this function is only needed when an SLA clock starts or resumes.
 */
create or replace function private.add_business_minutes(
  p_start timestamptz,
  p_minutes int,
  p_calendar_id uuid
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_timezone       text;
  v_is_24_7        boolean;
  v_remaining      interval;
  v_cursor         timestamptz;
  v_local          timestamp;
  v_day            int;
  v_interval       record;
  v_segment_start  timestamptz;
  v_segment_end    timestamptz;
  v_available      interval;
  v_guard          int := 0;
begin
  select timezone, is_24_7
    into v_timezone, v_is_24_7
    from public.business_calendars
   where id = p_calendar_id;

  if not found then
    raise exception 'BUSINESS_CALENDAR_NOT_FOUND' using errcode = '23503';
  end if;

  if p_minutes <= 0 then
    return p_start;
  end if;

  if v_is_24_7 then
    return p_start + make_interval(mins => p_minutes);
  end if;

  v_remaining := make_interval(mins => p_minutes);
  v_cursor := p_start;

  loop
    v_guard := v_guard + 1;
    if v_guard > 4000 then
      raise exception 'SLA_CALCULATION_EXCEEDED' using errcode = '22003';
    end if;

    v_local := v_cursor at time zone v_timezone;

    if exists (
      select 1
      from public.holidays h
      where h.calendar_id = p_calendar_id
        and h.holiday_date = v_local::date
    ) then
      v_cursor := ((v_local::date + 1)::timestamp at time zone v_timezone);
      continue;
    end if;

    v_day := extract(dow from v_local)::int;

    for v_interval in
      select start_time, end_time
      from public.business_calendar_intervals
      where calendar_id = p_calendar_id
        and day_of_week = v_day
      order by start_time
    loop
      v_segment_start := (v_local::date + v_interval.start_time) at time zone v_timezone;
      v_segment_end := (v_local::date + v_interval.end_time) at time zone v_timezone;

      if v_cursor >= v_segment_end then
        continue;
      end if;

      if v_cursor < v_segment_start then
        v_cursor := v_segment_start;
      end if;

      v_available := v_segment_end - v_cursor;

      if v_available >= v_remaining then
        return v_cursor + v_remaining;
      end if;

      v_remaining := v_remaining - v_available;
      v_cursor := v_segment_end;
    end loop;

    v_cursor := ((v_local::date + 1)::timestamp at time zone v_timezone);
  end loop;
end;
$$;

-- ─── Status transition guard ──────────────────────────────────────────────

create or replace function private.assert_transition(
  p_from public.ticket_status,
  p_to public.ticket_status,
  p_actor uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_allowed_roles text[];
begin
  select allowed_roles
    into v_allowed_roles
    from public.ticket_transition_rules
   where from_status = p_from
     and to_status = p_to;

  if v_allowed_roles is null then
    raise exception 'INVALID_STATUS_TRANSITION' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = p_actor
      and ur.role_code = any (v_allowed_roles)
  ) then
    raise exception 'STATUS_TRANSITION_FORBIDDEN' using errcode = '42501';
  end if;
end;
$$;

-- ─── Health endpoint support ──────────────────────────────────────────────

create or replace function public.health()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'status', 'ok',
    'db_time', now(),
    'schema_version', '0010'
  );
$$;

-- ─── Function privileges ──────────────────────────────────────────────────

revoke all on function private.current_roles() from public;
revoke all on function private.has_role(text) from public;
revoke all on function private.is_staff() from public;
revoke all on function private.is_admin() from public;
revoke all on function private.is_management_viewer() from public;
revoke all on function private.can_view_ticket(uuid) from public;
revoke all on function private.can_manage_ticket(uuid) from public;
revoke all on function private.can_view_internal(uuid) from public;
revoke all on function private.can_access_team(uuid) from public;
revoke all on function private.allocate_ticket_reference(int) from public;
revoke all on function private.add_business_minutes(timestamptz, int, uuid) from public;
revoke all on function private.assert_transition(public.ticket_status, public.ticket_status, uuid) from public;
revoke all on function public.health() from public;

grant execute on function private.current_roles() to authenticated;
grant execute on function private.has_role(text) to authenticated;
grant execute on function private.is_staff() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_management_viewer() to authenticated;
grant execute on function private.can_view_ticket(uuid) to authenticated;
grant execute on function private.can_manage_ticket(uuid) to authenticated;
grant execute on function private.can_view_internal(uuid) to authenticated;
grant execute on function private.can_access_team(uuid) to authenticated;
grant execute on function private.add_business_minutes(timestamptz, int, uuid) to authenticated;
grant execute on function public.health() to anon, authenticated;

-- ─── Row Level Security ───────────────────────────────────────────────────

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'profiles', 'roles', 'user_roles', 'organizations', 'customer_profiles',
    'departments', 'teams', 'team_members', 'user_invitations',
    'ticket_categories', 'priorities', 'ticket_custom_fields',
    'ticket_number_counters', 'tickets', 'ticket_status_history',
    'ticket_transition_rules', 'ticket_custom_field_values',
    'ticket_messages', 'ticket_attachments',
    'ticket_assignments', 'business_calendars',
    'business_calendar_intervals', 'holidays', 'sla_policies',
    'sla_escalation_rules', 'ticket_sla_records', 'sla_events',
    'escalations', 'notifications', 'email_outbox', 'audit_logs',
    'system_settings', 'kb_categories', 'kb_articles',
    'kb_article_feedback', 'kb_article_relations', 'customer_feedback'
  ]::text[]
  loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;
end;
$$;

-- Profiles and identity
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or private.is_staff());

create policy roles_select on public.roles
  for select to authenticated
  using (true);

create policy user_roles_select on public.user_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_admin());

create policy organizations_select on public.organizations
  for select to authenticated
  using (
    private.is_staff()
    or exists (
      select 1
      from public.customer_profiles cp
      where cp.user_id = (select auth.uid())
        and cp.organization_id = organizations.id
    )
  );

create policy customer_profiles_select on public.customer_profiles
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_staff());

create policy departments_select on public.departments
  for select to authenticated
  using (private.is_staff());

create policy teams_select on public.teams
  for select to authenticated
  using (private.is_staff());

create policy team_members_select on public.team_members
  for select to authenticated
  using (private.is_staff());

create policy user_invitations_select on public.user_invitations
  for select to authenticated
  using (private.is_admin());

-- Catalog
create policy ticket_categories_select on public.ticket_categories
  for select to authenticated
  using (is_active or private.is_staff());

create policy priorities_select on public.priorities
  for select to authenticated
  using (is_active or private.is_staff());

create policy ticket_custom_fields_select on public.ticket_custom_fields
  for select to authenticated
  using (
    private.is_staff()
    or (is_active and visibility in ('customer', 'both'))
  );

-- Tickets
create policy tickets_select on public.tickets
  for select to authenticated
  using (private.can_view_ticket(id));

create policy ticket_transition_rules_select on public.ticket_transition_rules
  for select to authenticated
  using (true);

create policy ticket_status_history_select on public.ticket_status_history
  for select to authenticated
  using (
    private.can_view_ticket(ticket_id)
    and (private.is_staff() or is_customer_visible)
  );

create policy ticket_messages_select on public.ticket_messages
  for select to authenticated
  using (
    private.can_view_ticket(ticket_id)
    and (
      visibility = 'public'
      or private.can_view_internal(ticket_id)
    )
  );

create policy ticket_attachments_select on public.ticket_attachments
  for select to authenticated
  using (
    (
      ticket_id is not null
      and private.can_view_ticket(ticket_id)
      and (
        visibility = 'public'
        or private.can_view_internal(ticket_id)
      )
    )
    or (ticket_id is null and uploaded_by = (select auth.uid()))
  );

create policy ticket_assignments_select on public.ticket_assignments
  for select to authenticated
  using (private.is_staff() and private.can_view_ticket(ticket_id));

create policy ticket_custom_field_values_select on public.ticket_custom_field_values
  for select to authenticated
  using (
    private.can_view_ticket(ticket_id)
    and (
      private.is_staff()
      or exists (
        select 1
        from public.ticket_custom_fields f
        where f.id = field_id
          and f.visibility in ('customer', 'both')
      )
    )
  );

-- SLA configuration and clocks
create policy business_calendars_select on public.business_calendars
  for select to authenticated
  using (private.is_staff());

create policy business_calendar_intervals_select on public.business_calendar_intervals
  for select to authenticated
  using (private.is_staff());

create policy holidays_select on public.holidays
  for select to authenticated
  using (private.is_staff());

create policy sla_policies_select on public.sla_policies
  for select to authenticated
  using (private.is_staff());

create policy sla_escalation_rules_select on public.sla_escalation_rules
  for select to authenticated
  using (private.is_staff());

create policy ticket_sla_records_select on public.ticket_sla_records
  for select to authenticated
  using (private.is_staff() and private.can_view_ticket(ticket_id));

create policy sla_events_select on public.sla_events
  for select to authenticated
  using (
    private.is_staff()
    and exists (
      select 1
      from public.ticket_sla_records r
      where r.id = sla_record_id
        and private.can_view_ticket(r.ticket_id)
    )
  );

create policy escalations_select on public.escalations
  for select to authenticated
  using (private.is_staff() and private.can_view_ticket(ticket_id));

-- Operations
create policy notifications_select on public.notifications
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy system_settings_select on public.system_settings
  for select to authenticated
  using (private.is_admin());

create policy audit_logs_select on public.audit_logs
  for select to authenticated
  using (private.is_admin());

-- Knowledgebase
create policy kb_categories_public on public.kb_categories
  for select to anon
  using (is_active);

create policy kb_categories_authenticated on public.kb_categories
  for select to authenticated
  using (is_active or private.is_staff());

create policy kb_articles_public on public.kb_articles
  for select to anon
  using (status = 'published' and visibility = 'public');

create policy kb_articles_authenticated on public.kb_articles
  for select to authenticated
  using (
    (status = 'published' and visibility in ('public', 'authenticated'))
    or private.is_staff()
  );

create policy kb_article_feedback_select on public.kb_article_feedback
  for select to authenticated
  using (user_id = (select auth.uid()) or private.is_admin());

create policy kb_article_relations_public on public.kb_article_relations
  for select to anon
  using (
    exists (
      select 1
      from public.kb_articles a
      where a.id = article_id
        and a.status = 'published'
        and a.visibility = 'public'
    )
  );

create policy kb_article_relations_authenticated on public.kb_article_relations
  for select to authenticated
  using (
    private.is_staff()
    or exists (
      select 1
      from public.kb_articles a
      where a.id = article_id
        and a.status = 'published'
        and a.visibility in ('public', 'authenticated')
    )
  );

-- Customer satisfaction
create policy customer_feedback_select on public.customer_feedback
  for select to authenticated
  using (customer_id = (select auth.uid()) or private.is_admin());

-- ─── Table privileges ─────────────────────────────────────────────────────

grant select on
  public.profiles,
  public.roles,
  public.user_roles,
  public.organizations,
  public.customer_profiles,
  public.departments,
  public.teams,
  public.team_members,
  public.user_invitations,
  public.ticket_categories,
  public.priorities,
  public.ticket_custom_fields,
  public.tickets,
  public.ticket_status_history,
  public.ticket_transition_rules,
  public.ticket_messages,
  public.ticket_attachments,
  public.ticket_assignments,
  public.ticket_custom_field_values,
  public.business_calendars,
  public.business_calendar_intervals,
  public.holidays,
  public.sla_policies,
  public.sla_escalation_rules,
  public.ticket_sla_records,
  public.sla_events,
  public.escalations,
  public.notifications,
  public.system_settings,
  public.audit_logs,
  public.customer_feedback
to authenticated;

grant select on
  public.kb_categories,
  public.kb_articles,
  public.kb_article_relations
to anon, authenticated;

grant select on public.kb_article_feedback to authenticated;

commit;
