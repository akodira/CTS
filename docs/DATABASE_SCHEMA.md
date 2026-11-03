# Database Schema

> **Execution status:** all 10 migrations are authored and reviewed statically.
> They have **not** been executed against a live PostgreSQL/Supabase instance
> because Docker and the Supabase CLI were unavailable on the build machine.
> Treat the SQL as unverified until `supabase db reset` and the RLS checks in
> [TEST_PLAN](TEST_PLAN.md) pass. See [TEST_RESULTS](TEST_RESULTS.md).

Target: Supabase PostgreSQL 17.

## 1. Conventions

- Schema: `public` for application data; `private` for helper functions and
  internal state. `private` is not exposed through PostgREST.
- Primary keys: `uuid` with `gen_random_uuid()` unless a natural key is stable
  (`roles.code`, `system_settings.key`). High-volume history tables use
  `bigserial`.
- Timestamps: `timestamptz`, stored in UTC; display in `Asia/Riyadh`.
- Money: none in Phase 1.
- Soft delete: only `ticket_messages.deleted_at`; other deletes are physical and
  respect foreign-key actions.
- Naming: snake_case, plural tables, `*_id` foreign keys, `is_*` booleans.
- All application tables have RLS enabled. `email_outbox` deliberately has no
  policy/grant and is service-role only.
- Migrations are forward-only. There are no `down` scripts.

## 2. Migration inventory

| File | Purpose |
| --- | --- |
| `0001_extensions_and_schemas.sql` | `private` schema, `set_updated_at()` |
| `0002_identity_and_org.sql` | Profiles, roles, organizations, departments, teams, invitations, auth triggers |
| `0003_catalog_and_custom_fields.sql` | Categories, priorities, custom-field definitions, depth guard |
| `0004_ticketing_core.sql` | Enums, counters, tickets, history, transitions, messages, attachments, assignments |
| `0005_sla_and_calendars.sql` | Calendars, holidays, SLA policies, clocks, events, escalations |
| `0006_operations.sql` | Notifications, email outbox, audit log, settings |
| `0007_knowledgebase_and_feedback.sql` | KB categories/articles/feedback/relations, CSAT |
| `0008_functions_and_rls.sql` | Authorization helpers, allocator, business-hours math, RLS, grants |
| `0009_storage_buckets.sql` | Private `attachments` bucket (25 MiB, MIME allow-list) |
| `0010_seed_reference_data.sql` | Roles, priorities, transitions, calendar, SLA policies, escalation rules, settings |

Counts: **37 public tables**, 3 enums, 18 functions (15 `private`, 3 `public`),
1 storage bucket, 5 roles, 4 priorities, 30 transition rules, 4 priority SLA
policies + 1 default policy, 10 escalation rules (2 per policy), 8 system
settings.

## 3. Enums

```sql
create type public.ticket_status as enum (
  'new', 'open', 'in_progress', 'pending_customer',
  'pending_internal', 'resolved', 'closed', 'reopened'
);

create type public.message_visibility as enum ('public', 'internal');

create type public.sla_state as enum (
  'on_track', 'due_soon', 'breached', 'paused', 'completed'
);
```

## 4. Identity and organization (0002)

### `public.profiles`
One row per `auth.users` row, created by trigger `on_auth_user_created`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | FK → `auth.users(id)` on delete cascade |
| `email` | `text` | Required; unique on `lower(email)` |
| `full_name` | `text` | 1–120 chars |
| `phone` | `text` | Optional |
| `locale` | `text` | `en` / `ar`, default `en` |
| `account_status` | `text` | `active` / `suspended` / `disabled` |
| `created_at`, `updated_at` | `timestamptz` | `updated_at` by trigger |

> Known gap: `auth.users.email` is required by this schema. Phone-only auth
> users would fail the trigger. Email signup is the supported method.

### `public.roles`
`code` PK (`customer`, `support_agent`, `team_leader`, `system_admin`,
`management_viewer`), plus `name_en`, `name_ar`, `description_en`,
`description_ar`.

### `public.user_roles`
`(user_id, role_code)` PK. `granted_by` FK → profiles, `granted_at`.
Index on `role_code`. A user may hold multiple roles at the database level; the
domain layer rejects customer+staff combinations, but the database does not
enforce that yet.

### `public.organizations`
`id`, `name`, `is_active`, `created_at`. Organization sharing is deferred.

### `public.customer_profiles`
`user_id` PK/FK → profiles, `organization_id` FK → organizations, `job_title`,
`created_at`.

### `public.departments`
`id`, `name_en`, `name_ar`, `description_en`, `description_ar`, `is_active`,
`created_at`.

### `public.teams`
`id`, `department_id` FK, unique `code`, `name_en`, `name_ar`, `is_active`,
`created_at`.

### `public.team_members`
`(team_id, user_id)` PK, `team_role` (`leader` / `agent`), `is_active`,
`joined_at`. Partial index on active memberships by user.

### `public.user_invitations`
`id`, `email`, `role_code`, `team_id`, `invited_by`, unique `token_hash`,
`expires_at`, `accepted_at`, `created_at`. One pending invitation per email
(partial unique index). Invitation sending is not implemented yet.

### Auth triggers

- `public.handle_new_user()` — `SECURITY DEFINER`, `search_path=''`. Inserts a
  profile (name from metadata or email local-part), grants `customer`, creates
  `customer_profiles`.
- `public.handle_user_email_updated()` — keeps `profiles.email` in sync.

Both are revoked from `public`; they run as the trigger owner.

## 5. Catalog (0003)

### `public.ticket_categories`
`id`, `parent_id` (self-FK, `on delete restrict`), unique `code`, `name_en`,
`name_ar`, descriptions, `default_team_id`, `is_active`, `sort_order`,
`created_at`. One optional subcategory level. Trigger
`private.check_category_depth()` rejects self-parenting, depth > 2, missing
parents and turning a parent with children into a child.

### `public.priorities`
`id`, unique `code`, `name_en`, `name_ar`, `weight` 1–100, `is_active`,
`created_at`.

### `public.ticket_custom_fields`
`id`, `category_id` (nullable = global), `code`, bilingual label/help,
`field_type` (`text`, `long_text`, `number`, `date`, `dropdown`,
`multi_select`, `checkbox`, `radio`, `file`), `is_required`, `is_active`,
`options` jsonb, `validation` jsonb, `visibility`
(`both` / `customer` / `staff`), `sort_order`, `created_at`.
Unique `(category_id, code)` with `NULLS NOT DISTINCT`.

## 6. Ticketing core (0004)

### `public.ticket_number_counters`
`ticket_year` int PK (2000–9999), `last_value` bigint ≥ 0. Incremented under a
row lock by `private.allocate_ticket_reference(int)`.

### `public.tickets`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | |
| `reference` | `text` unique | `^CTS-[0-9]{4}-[0-9]{6}$` |
| `subject` | `text` | 5–200 chars |
| `description` | `text` | ≥ 10 chars |
| `customer_id` | `uuid` | FK → profiles, restrict delete |
| `organization_id` | `uuid` | FK → organizations, set null |
| `category_id` | `uuid` | FK → categories, restrict |
| `priority_id` | `uuid` | FK → priorities, restrict |
| `status` | `ticket_status` | default `new` |
| `team_id` | `uuid` | FK → teams, set null |
| `assignee_id` | `uuid` | FK → profiles, set null |
| `locale` | `text` | `en` / `ar` |
| `source` | `text` | only `web` today |
| `first_response_at` | `timestamptz` | set by future RPC |
| `resolved_at`, `closed_at`, `reopened_at` | `timestamptz` | lifecycle stamps |
| `reopen_count` | `int` | ≥ 0, max enforced by policy/RPC |
| `resolution_summary` | `text` | required by `resolved` transitions |
| `resolution_by` | `uuid` | FK → profiles |
| `customer_confirmed_at` | `timestamptz` | stops reopen eligibility |
| `last_public_message_at` | `timestamptz` | list sorting |
| `version` | `int` | optimistic concurrency, ≥ 1 |
| `search_vector` | `tsvector` generated | subject (A) + description (B), `simple` config |
| `created_at`, `updated_at` | `timestamptz` | trigger-maintained |

Indexes: customer+updated, team/status/priority+updated, assignee+status,
status+updated, GIN on `search_vector`.

### `public.ticket_status_history`
`id` bigserial, `ticket_id` FK cascade, `from_status`, `to_status`,
`changed_by`, `actor_type` (`user` / `system`), `reason`,
`is_customer_visible` (default true), `changed_at`. Index
`(ticket_id, changed_at)`.

### `public.ticket_transition_rules`
`(from_status, to_status)` PK, `allowed_roles text[]`, `customer_allowed`,
`requires_reason`. This table is the database authority for status changes.

### `public.ticket_custom_field_values`
`id`, `ticket_id` FK cascade, `field_id` FK cascade, `value` jsonb,
`created_at`, `updated_at`; unique `(ticket_id, field_id)`. Index by ticket.
RLS restricts customers to fields whose definition is visible to customers.

### `public.ticket_messages`
`id`, `ticket_id` FK cascade, `author_id` FK set null, `visibility`
(`public` / `internal`), `body` 1–20000, `is_system`, `created_at`,
`edited_at`, `deleted_at`. Check: system messages may have no author; all
others require one. Indexes for full thread and public-only thread.

### `public.ticket_attachments`
`id`, `ticket_id` FK cascade (nullable while draft), `message_id` FK set null,
`uploaded_by` FK restrict, unique `storage_path`, `file_name`, `mime_type`,
`size_bytes` 1–26,214,400, `checksum`, `visibility`, `status`
(`draft` / `linked`), `created_at`. Check enforces draft ⇔ no ticket and
linked ⇔ ticket. Indexes by ticket and by uploader for drafts.

### `public.ticket_assignments`
`id`, `ticket_id` FK cascade, `assigned_to`, `team_id`, `assigned_by`,
`assigned_at`, `ended_at`, `reason`. Check `ended_at >= assigned_at`.
**Unique partial index** on `ticket_id where ended_at is null` guarantees one
current assignment. Index by agent+date.

## 7. SLA and calendars (0005)

### `public.business_calendars`
`id`, `name`, `timezone` (default `Asia/Riyadh`), `is_24_7`, `created_at`.

### `public.business_calendar_intervals`
`id`, `calendar_id` FK cascade, `day_of_week` 0–6 (0 = Sunday), `start_time`,
`end_time`, check start < end, unique `(calendar_id, day_of_week, start_time)`.

### `public.holidays`
`id`, `calendar_id` FK cascade, `holiday_date`, `name_en`, `name_ar`,
`is_recurring`, unique `(calendar_id, holiday_date)`.

> `is_recurring` exists but `private.add_business_minutes` currently matches the
> exact date only. Recurring-holiday expansion is not implemented.

### `public.sla_policies`
`id`, `name`, `priority_id`, `category_id`, `team_id`, `first_response_minutes`
(1–525600), `resolution_minutes` (1–525600), `business_calendar_id`,
`warning_threshold_pct` 1–100, `pause_on_pending_customer`,
`pause_on_pending_internal`, `is_default`, `is_active`, `version`,
`effective_from`, `created_at`.

Constraints/indexes:
- One active default policy (`sla_policies_one_default`).
- One active policy per `(priority_id, category_id, team_id)` with
  `NULLS NOT DISTINCT` (`sla_policies_scope_key`).
- Policy selection by specificity is **not implemented yet**. The schema stores
  the scopes; a future function/RPC will resolve them.

### `public.sla_escalation_rules`
`id`, `policy_id` FK cascade, `level` 1–10, `threshold_pct` 1–100,
`notify_role` → roles, `notify_team_id` → teams, `created_at`,
unique `(policy_id, level)`.

### `public.ticket_sla_records`
`id`, `ticket_id` FK cascade, `metric` (`first_response` / `resolution`),
`cycle` ≥ 1, `policy_id`, `target_minutes`, `started_at`, `due_at`,
`warning_at`, `paused_at`, `paused_seconds`, `completed_at`, `breached_at`,
`state`, `escalation_level`, `last_evaluated_at`, `created_at`.
Checks: due ≥ start, warning ≤ due. Unique `(ticket_id, metric, cycle)`.
Partial index on open states for the evaluator.

### `public.sla_events`
`id` bigserial, `sla_record_id` FK cascade, `event_type` (`started`, `paused`,
`resumed`, `warning`, `breached`, `escalated`, `completed`), `occurred_at`,
`metadata` jsonb, unique `dedupe_key`.

### `public.escalations`
`id`, `ticket_id` FK cascade, `sla_record_id`, `level`, `escalated_to_role`,
`escalated_to_team`, `reason`, `acknowledged_at`, `resolved_at`, `created_at`,
unique `dedupe_key`. Index by ticket+date.

## 8. Operations (0006)

### `public.notifications`
`id`, `user_id` FK cascade, `ticket_id` FK cascade, `type`, `payload` jsonb,
`read_at`, unique `dedupe_key`, `created_at`. Indexes for user list and unread.
No notification producer exists yet.

### `public.email_outbox`
`id`, `to_email`, `template_key`, `locale`, `payload` jsonb, `status`
(`pending`/`sending`/`sent`/`failed`/`cancelled`), `attempts`,
`next_attempt_at`, `sent_at`, `last_error`, unique `dedupe_key`, `created_at`.
Partial index on pending/failed for the dispatcher. RLS enabled, **no policy and
no client grant** — service role only.

### `public.audit_logs`
`id` bigserial, `actor_id`, `actor_type` (`user`/`system`/`anonymous`),
`action`, `entity_type`, `entity_id`, `before` jsonb, `after` jsonb,
`request_id`, `ip inet`, `user_agent`, `created_at`.
Trigger `audit_logs_append_only` rejects UPDATE and DELETE. Indexed by entity
and actor. Application code must write meaningful entries; no automatic
table-level audit trigger exists.

### `public.system_settings`
`key` PK, `value` jsonb, `description`, `updated_by`, `updated_at`
(trigger-maintained). Seeded values are listed in §11.

## 9. Knowledgebase and feedback (0007)

### `public.kb_categories`
`id`, `parent_id` self-FK restrict, unique `slug`, `name_en`, `name_ar`,
`sort_order`, `is_active`, `created_at`.

### `public.kb_articles`
`id`, `category_id` FK set null, unique `slug`, bilingual title/summary/body,
`status` (`draft`/`published`/`archived`), `visibility`
(`public`/`authenticated`/`staff`), `author_id`, `published_at`,
`view_count`, generated `search_vector` (title A, body B), timestamps.

### `public.kb_article_feedback`
`id`, `article_id` FK cascade, `user_id` FK cascade, `is_helpful`, `comment`,
`created_at`, unique `(article_id, user_id)`.

### `public.kb_article_relations`
`(article_id, related_article_id)` PK, both FK cascade, check not self.

### `public.customer_feedback`
`id`, `ticket_id` unique FK cascade, `customer_id` FK cascade, `rating` 1–5,
`comment` ≤ 2000, `created_at`. Index by rating/date.

## 10. Functions

| Function | Security | Purpose |
| --- | --- | --- |
| `private.set_updated_at()` | invoker | Trigger helper |
| `public.handle_new_user()` | definer | Provision profile/role/customer profile |
| `public.handle_user_email_updated()` | definer | Sync email |
| `private.check_category_depth()` | invoker | Enforce 2-level category tree |
| `private.prevent_audit_mutation()` | invoker | Block audit UPDATE/DELETE |
| `private.current_roles()` | definer | Roles of `auth.uid()` |
| `private.has_role(text)` | definer | Role check |
| `private.is_staff()` | definer | Agent/leader/admin |
| `private.is_admin()` | definer | `system_admin` |
| `private.is_management_viewer()` | definer | Read-only viewer |
| `private.can_view_ticket(uuid)` | definer | Customer own / staff scope / admin |
| `private.can_manage_ticket(uuid)` | definer | Assignee, team leader or admin |
| `private.can_view_internal(uuid)` | definer | Staff with ticket access |
| `private.can_access_team(uuid)` | definer | Active team member or admin |
| `private.allocate_ticket_reference(int)` | definer | Atomic per-year reference |
| `private.add_business_minutes(timestamptz,int,uuid)` | definer | Calendar-aware deadline math |
| `private.assert_transition(status,status,uuid)` | definer | Transition rule check |
| `public.health()` | definer | Safe JSON health payload |

`private.allocate_ticket_reference` and `private.assert_transition` are revoked
from clients and are intended for use inside future definer RPCs. All helpers
set `search_path = ''` and schema-qualify objects.

## 11. Seed reference data (0010)

**Roles:** `customer`, `support_agent`, `team_leader`, `system_admin`,
`management_viewer`.

**Priorities** (fixed UUIDs):

| Code | Weight |
| --- | --- |
| `critical` | 100 |
| `high` | 75 |
| `normal` | 50 |
| `low` | 25 |

**Calendar:** `Riyadh Business Hours`, `Asia/Riyadh`, Sunday–Thursday
08:00–17:00. No holidays are seeded — the owner must supply the holiday list.

**SLA policies:**

| Policy | Priority | First response | Resolution |
| --- | --- | --- | --- |
| Critical SLA | critical | 15 min | 4 h |
| High SLA | high | 60 min | 8 h |
| Normal SLA | normal | 240 min | 24 h |
| Low SLA | low | 480 min | 48 h |
| Default SLA (Normal) | any (default) | 240 min | 24 h |

All use 75% warning, pause on `pending_customer`, do not pause on
`pending_internal`.

**Transition rules:** 30 rows, enumerated in
[TICKET_WORKFLOW](TICKET_WORKFLOW.md).

**Escalation rules:** 10 rows, 2 per policy: level 1 at 75% notifies
`team_leader`; level 2 at 100% notifies `system_admin`. No team-specific
routing is seeded because no teams exist yet.

**Settings:** `customer_priority_selection=false`, `reopen_window_days=7`,
`max_reopens=2`, `auto_close_business_days=3`,
`attachment_max_bytes=26214400`, `attachment_max_per_message=5`,
`reference_prefix="CTS"`, `default_locale="en"`.

## 12. Storage

`storage.buckets` row: id/name `attachments`, `public=false`, 25 MiB limit,
MIME allow-list: PDF, PNG, JPEG, WebP, DOCX, XLSX, CSV, plain text, ZIP.

No `storage.objects` policies are created. The intended flow is:

1. Server action uploads a draft with the service role after authorization.
2. Client never receives the service-role key.
3. Download goes through a future `/api/attachments/[id]/download` handler that
   checks `private.can_view_ticket` then issues a short-lived signed URL.

Until that handler exists, attachments are not user-accessible.

## 13. RLS coverage

RLS is enabled on all 37 public tables. Highlights:

| Table group | Customer | Staff | Admin |
| --- | --- | --- | --- |
| `tickets` | Own only | Assignee, team, or unassigned queue | All |
| `ticket_messages` | Public messages on own tickets | Public + internal on visible tickets | All |
| `ticket_status_history` | Customer-visible rows on own tickets | Visible rows | All |
| `ticket_attachments` | Own draft + public linked | Public + internal on visible tickets | All |
| `profiles` | Own row | All rows | All rows |
| `user_roles` | Own roles | Own roles | All |
| `teams`/`departments`/`team_members` | None | All | All |
| Catalog | Active categories/priorities, customer-visible fields | All | All |
| SLA config/clocks | None | Visible tickets | All |
| `audit_logs`/`system_settings` | None | None | All |
| KB published public | Anon + authenticated | All | All |
| `email_outbox` | None | None | Service role only |

Management viewers are not staff in the helper functions; they cannot read
tickets. Their reporting access will be implemented through dedicated
read-only views/RPCs in Phase 6. This is intentional and recorded as a gap.

Full policy text: `supabase/migrations/0008_functions_and_rls.sql`.

## 14. Verification queries (to run after migrations)

```sql
-- Expected: 37
select count(*) from pg_tables where schemaname = 'public';

-- Expected: 37 (one row per table, relrowsecurity = true)
select count(*) from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity;

-- Expected: 5 roles, 4 priorities, 30 transitions, 5 policies
select 'roles' as item, count(*) from public.roles
union all select 'priorities', count(*) from public.priorities
union all select 'transitions', count(*) from public.ticket_transition_rules
union all select 'sla_policies', count(*) from public.sla_policies;

-- Expected: one default policy
select id, name from public.sla_policies where is_default and is_active;

-- Expected: calendar + 5 intervals
select c.name, count(i.id)
from public.business_calendars c
left join public.business_calendar_intervals i on i.calendar_id = c.id
group by c.name;
```

Do not treat these as passed until they are actually executed.
