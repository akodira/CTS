# Database Relationships

Companion to [DATABASE_SCHEMA](DATABASE_SCHEMA.md). Diagrams are split by domain
so they stay readable. Cardinality is shown as `parent ||--o{ child` (one parent
to zero-or-many children).

## 1. Identity and organization

```mermaid
erDiagram
  AUTH_USERS ||--|| PROFILES : "cascade delete"
  PROFILES ||--o{ USER_ROLES : "has"
  ROLES ||--o{ USER_ROLES : "granted"
  PROFILES ||--o| CUSTOMER_PROFILES : "customer data"
  ORGANIZATIONS ||--o{ CUSTOMER_PROFILES : "employs"
  DEPARTMENTS ||--o{ TEAMS : "contains"
  TEAMS ||--o{ TEAM_MEMBERS : "has"
  PROFILES ||--o{ TEAM_MEMBERS : "joins"
  ROLES ||--o{ USER_INVITATIONS : "invites as"
  TEAMS ||--o{ USER_INVITATIONS : "optional team"
  PROFILES ||--o{ USER_INVITATIONS : "invited by"

  AUTH_USERS {
    uuid id PK
    text email
  }
  PROFILES {
    uuid id PK
    text email UK
    text full_name
    text locale
    text account_status
  }
  ROLES {
    text code PK
    text name_en
    text name_ar
  }
  USER_ROLES {
    uuid user_id PK,FK
    text role_code PK,FK
    uuid granted_by FK
  }
  ORGANIZATIONS {
    uuid id PK
    text name
    boolean is_active
  }
  CUSTOMER_PROFILES {
    uuid user_id PK,FK
    uuid organization_id FK
    text job_title
  }
  DEPARTMENTS {
    uuid id PK
    text name_en
    text name_ar
  }
  TEAMS {
    uuid id PK
    uuid department_id FK
    text code UK
  }
  TEAM_MEMBERS {
    uuid team_id PK,FK
    uuid user_id PK,FK
    text team_role
    boolean is_active
  }
  USER_INVITATIONS {
    uuid id PK
    text email
    text role_code FK
    uuid team_id FK
    uuid invited_by FK
    text token_hash UK
    timestamptz expires_at
    timestamptz accepted_at
  }
```

Key rules:

- A profile exists only while its `auth.users` row exists (cascade).
- `user_roles` is many-to-many; the application domain rejects mixing
  `customer` with staff roles, but the database does not enforce it yet.
- `team_members` is many-to-many with a per-membership `leader`/`agent` role.
- Only one **pending** invitation per lowercased email (partial unique index).

## 2. Catalog

```mermaid
erDiagram
  TICKET_CATEGORIES ||--o{ TICKET_CATEGORIES : "parent of"
  TEAMS ||--o{ TICKET_CATEGORIES : "default team"
  TICKET_CATEGORIES ||--o{ TICKET_CUSTOM_FIELDS : "defines"
  PRIORITIES ||--o{ TICKETS : "classifies"

  TICKET_CATEGORIES {
    uuid id PK
    uuid parent_id FK
    text code UK
    text name_en
    text name_ar
    uuid default_team_id FK
    boolean is_active
    int sort_order
  }
  TICKET_CUSTOM_FIELDS {
    uuid id PK
    uuid category_id FK
    text code
    text field_type
    text visibility
    boolean is_required
    jsonb options
    jsonb validation
  }
  PRIORITIES {
    uuid id PK
    text code UK
    int weight
    boolean is_active
  }
```

- Categories are limited to two levels by trigger.
- A custom field with `category_id = NULL` is global.
- `(category_id, code)` is unique with `NULLS NOT DISTINCT`, so a global code
  cannot be duplicated.

## 3. Ticketing core

```mermaid
erDiagram
  PROFILES ||--o{ TICKETS : "customer"
  PROFILES ||--o{ TICKETS : "assignee"
  ORGANIZATIONS ||--o{ TICKETS : "optional org"
  TICKET_CATEGORIES ||--o{ TICKETS : "categorizes"
  PRIORITIES ||--o{ TICKETS : "prioritizes"
  TEAMS ||--o{ TICKETS : "owns queue"
  TICKETS ||--o{ TICKET_MESSAGES : "thread"
  PROFILES ||--o{ TICKET_MESSAGES : "author"
  TICKETS ||--o{ TICKET_ATTACHMENTS : "files"
  TICKET_MESSAGES ||--o{ TICKET_ATTACHMENTS : "optional message"
  PROFILES ||--o{ TICKET_ATTACHMENTS : "uploaded by"
  TICKETS ||--o{ TICKET_STATUS_HISTORY : "audit trail"
  PROFILES ||--o{ TICKET_STATUS_HISTORY : "changed by"
  TICKETS ||--o{ TICKET_ASSIGNMENTS : "assignment history"
  PROFILES ||--o{ TICKET_ASSIGNMENTS : "assigned to"
  TEAMS ||--o{ TICKET_ASSIGNMENTS : "team"
  TICKETS ||--o{ TICKET_CUSTOM_FIELD_VALUES : "values"
  TICKET_CUSTOM_FIELDS ||--o{ TICKET_CUSTOM_FIELD_VALUES : "definition"
  TICKET_STATUS ||--o{ TICKET_TRANSITION_RULES : "from"
  TICKET_STATUS ||--o{ TICKET_TRANSITION_RULES : "to"

  TICKETS {
    uuid id PK
    text reference UK
    text subject
    text description
    uuid customer_id FK
    uuid organization_id FK
    uuid category_id FK
    uuid priority_id FK
    ticket_status status
    uuid team_id FK
    uuid assignee_id FK
    text locale
    timestamptz first_response_at
    timestamptz resolved_at
    timestamptz closed_at
    int reopen_count
    int version
    tsvector search_vector
  }
  TICKET_MESSAGES {
    uuid id PK
    uuid ticket_id FK
    uuid author_id FK
    message_visibility visibility
    text body
    boolean is_system
    timestamptz deleted_at
  }
  TICKET_ATTACHMENTS {
    uuid id PK
    uuid ticket_id FK
    uuid message_id FK
    uuid uploaded_by FK
    text storage_path UK
    text status
    message_visibility visibility
  }
  TICKET_STATUS_HISTORY {
    bigint id PK
    uuid ticket_id FK
    ticket_status from_status
    ticket_status to_status
    uuid changed_by FK
    text actor_type
  }
  TICKET_ASSIGNMENTS {
    uuid id PK
    uuid ticket_id FK
    uuid assigned_to FK
    uuid team_id FK
    uuid assigned_by FK
    timestamptz ended_at
  }
  TICKET_CUSTOM_FIELD_VALUES {
    uuid id PK
    uuid ticket_id FK
    uuid field_id FK
    jsonb value
  }
  TICKET_TRANSITION_RULES {
    ticket_status from_status PK
    ticket_status to_status PK
    text_array allowed_roles
    boolean customer_allowed
  }
```

Key rules:

- `ticket_number_counters` has no FK; it is a per-year sequence table.
- `ticket_transition_rules` references enum values, not rows; it is a lookup
  table keyed by the `(from, to)` pair.
- One current assignment per ticket: partial unique index on
  `ticket_assignments(ticket_id) where ended_at is null`.
- Deleting a ticket cascades messages, history, attachments, SLA records,
  escalations and feedback. Customer/priority/category deletes are restricted.
- `ticket_messages.author_id` and `tickets.assignee_id` become `NULL` if the
  staff profile is deleted, preserving the ticket history.
- Attachments can exist as `draft` (no ticket) and later become `linked`.

## 4. SLA

```mermaid
erDiagram
  BUSINESS_CALENDARS ||--o{ BUSINESS_CALENDAR_INTERVALS : "hours"
  BUSINESS_CALENDARS ||--o{ HOLIDAYS : "closed days"
  BUSINESS_CALENDARS ||--o{ SLA_POLICIES : "measures in"
  PRIORITIES ||--o{ SLA_POLICIES : "priority scope"
  TICKET_CATEGORIES ||--o{ SLA_POLICIES : "category scope"
  TEAMS ||--o{ SLA_POLICIES : "team scope"
  SLA_POLICIES ||--o{ SLA_ESCALATION_RULES : "escalates"
  ROLES ||--o{ SLA_ESCALATION_RULES : "notify role"
  TEAMS ||--o{ SLA_ESCALATION_RULES : "notify team"
  SLA_POLICIES ||--o{ TICKET_SLA_RECORDS : "instantiates"
  TICKETS ||--o{ TICKET_SLA_RECORDS : "tracked by"
  TICKET_SLA_RECORDS ||--o{ SLA_EVENTS : "emits"
  TICKETS ||--o{ ESCALATIONS : "escalated"
  TICKET_SLA_RECORDS ||--o{ ESCALATIONS : "triggered by"
  ROLES ||--o{ ESCALATIONS : "target role"
  TEAMS ||--o{ ESCALATIONS : "target team"

  BUSINESS_CALENDARS {
    uuid id PK
    text name
    text timezone
    boolean is_24_7
  }
  BUSINESS_CALENDAR_INTERVALS {
    uuid id PK
    uuid calendar_id FK
    smallint day_of_week
    time start_time
    time end_time
  }
  HOLIDAYS {
    uuid id PK
    uuid calendar_id FK
    date holiday_date
    boolean is_recurring
  }
  SLA_POLICIES {
    uuid id PK
    uuid priority_id FK
    uuid category_id FK
    uuid team_id FK
    int first_response_minutes
    int resolution_minutes
    int warning_threshold_pct
    boolean pause_on_pending_customer
    boolean is_default
  }
  SLA_ESCALATION_RULES {
    uuid id PK
    uuid policy_id FK
    int level
    int threshold_pct
    text notify_role FK
  }
  TICKET_SLA_RECORDS {
    uuid id PK
    uuid ticket_id FK
    text metric
    smallint cycle
    uuid policy_id FK
    timestamptz due_at
    timestamptz warning_at
    timestamptz completed_at
    sla_state state
  }
  SLA_EVENTS {
    bigint id PK
    uuid sla_record_id FK
    text event_type
    text dedupe_key UK
  }
  ESCALATIONS {
    uuid id PK
    uuid ticket_id FK
    uuid sla_record_id FK
    int level
    text dedupe_key UK
  }
```

Key rules:

- A ticket has at most one record per `(metric, cycle)`.
- A policy scope is unique per `(priority, category, team)` when active, with
  `NULLS NOT DISTINCT`. Exactly one active policy can be the default.
- `ticket_sla_records.policy_id` is a plain FK with the default `NO ACTION`
  behaviour, so a policy cannot be deleted while SLA records reference it.
  This protects historical clocks.
- `sla_events.dedupe_key` and `escalations.dedupe_key` make cron retries
  idempotent.

## 5. Operations, knowledgebase and feedback

```mermaid
erDiagram
  PROFILES ||--o{ NOTIFICATIONS : "receives"
  TICKETS ||--o{ NOTIFICATIONS : "about"
  TICKETS ||--o{ CUSTOMER_FEEDBACK : "rated once"
  PROFILES ||--o{ CUSTOMER_FEEDBACK : "submits"
  KB_CATEGORIES ||--o{ KB_CATEGORIES : "parent of"
  KB_CATEGORIES ||--o{ KB_ARTICLES : "groups"
  PROFILES ||--o{ KB_ARTICLES : "authors"
  KB_ARTICLES ||--o{ KB_ARTICLE_FEEDBACK : "rated"
  PROFILES ||--o{ KB_ARTICLE_FEEDBACK : "submits"
  KB_ARTICLES ||--o{ KB_ARTICLE_RELATIONS : "related from"
  KB_ARTICLES ||--o{ KB_ARTICLE_RELATIONS : "related to"
  PROFILES ||--o{ AUDIT_LOGS : "actor"
  PROFILES ||--o{ SYSTEM_SETTINGS : "updates"

  NOTIFICATIONS {
    uuid id PK
    uuid user_id FK
    uuid ticket_id FK
    text type
    jsonb payload
    timestamptz read_at
    text dedupe_key UK
  }
  EMAIL_OUTBOX {
    uuid id PK
    text to_email
    text template_key
    text locale
    text status
    int attempts
    text dedupe_key UK
  }
  AUDIT_LOGS {
    bigint id PK
    uuid actor_id FK
    text action
    text entity_type
    text entity_id
    jsonb before
    jsonb after
  }
  SYSTEM_SETTINGS {
    text key PK
    jsonb value
  }
  KB_CATEGORIES {
    uuid id PK
    uuid parent_id FK
    text slug UK
  }
  KB_ARTICLES {
    uuid id PK
    uuid category_id FK
    text slug UK
    text status
    text visibility
  }
  KB_ARTICLE_FEEDBACK {
    uuid id PK
    uuid article_id FK
    uuid user_id FK
    boolean is_helpful
  }
  KB_ARTICLE_RELATIONS {
    uuid article_id PK,FK
    uuid related_article_id PK,FK
  }
  CUSTOMER_FEEDBACK {
    uuid id PK
    uuid ticket_id FK,UK
    uuid customer_id FK
    smallint rating
  }
```

Key rules:

- `email_outbox.to_email` is an address snapshot, not an FK. It survives user
  deletion and supports invitations to people who have not signed up.
- `customer_feedback` is one row per ticket (`ticket_id` unique).
- `audit_logs` is append-only and references the actor with `on delete set null`.
- KB relations are a directed pair; the check prevents self-relations only, not
  duplicate reciprocal rows. The application must avoid creating both A→B and
  B→A unless intended.

## 6. Delete and cascade matrix

| Parent deleted | Child | Action |
| --- | --- | --- |
| `auth.users` | `profiles` | CASCADE |
| `profiles` | `user_roles`, `customer_profiles`, `team_members`, `notifications`, `kb_article_feedback`, `customer_feedback` | CASCADE |
| `profiles` | `tickets.customer_id` | RESTRICT (cannot delete a customer with tickets) |
| `profiles` | `ticket_messages.author_id`, `tickets.assignee_id`, `tickets.resolution_by`, `ticket_assignments.assigned_to`, `audit_logs.actor_id`, `kb_articles.author_id` | SET NULL |
| `profiles` | `ticket_attachments.uploaded_by` | RESTRICT |
| `tickets` | messages, attachments, history, custom values, SLA records, escalations, feedback, notifications | CASCADE |
| `ticket_messages` | `ticket_attachments.message_id` | SET NULL |
| `teams` | `tickets.team_id`, `ticket_categories.default_team_id`, `ticket_assignments.team_id`, `sla_escalation_rules.notify_team_id`, `escalations.escalated_to_team` | SET NULL |
| `teams` | `team_members`, `user_invitations.team_id`, `sla_policies.team_id` | CASCADE for members; SET NULL for invitations; CASCADE for policies |
| `departments` | `teams.department_id` | SET NULL |
| `ticket_categories` | `tickets.category_id` | RESTRICT |
| `ticket_categories` | `ticket_custom_fields.category_id`, `sla_policies.category_id` | CASCADE |
| `ticket_categories` (parent) | `ticket_categories.parent_id` | RESTRICT |
| `priorities` | `tickets.priority_id` | RESTRICT |
| `priorities` | `sla_policies.priority_id` | CASCADE |
| `ticket_custom_fields` | `ticket_custom_field_values.field_id` | CASCADE |
| `business_calendars` | intervals, holidays | CASCADE |
| `business_calendars` | `sla_policies.business_calendar_id` | RESTRICT |
| `sla_policies` | `sla_escalation_rules`, `ticket_sla_records` | CASCADE / RESTRICT (records block deletion) |
| `ticket_sla_records` | `sla_events` | CASCADE |
| `ticket_sla_records` | `escalations.sla_record_id` | SET NULL |
| `kb_articles` | feedback, relations | CASCADE |
| `kb_categories` (parent) | child categories | RESTRICT |

> The SLA policy → ticket record relationship is deliberately protective:
> historical SLA clocks must not disappear when a policy is retired. Retire by
> setting `is_active = false`, never by deleting.

## 7. Referential integrity rules that need application logic

The database cannot express every business rule. These require RPC/service
validation and tests:

1. A ticket's `assignee_id` must be an active member of `team_id` (or a leader).
2. A resolution transition requires `resolution_summary` and sets
   `resolved_at`, `resolution_by`.
3. Closing requires either customer confirmation or an auto-close job.
4. `reopen_count` must not exceed `max_reopens`; reopen requires the window.
5. `ticket_status_history` must be written for every status change.
6. `ticket_custom_field_values` must satisfy the field's `is_required`,
   `field_type` and `validation`.
7. An attachment must belong to the same ticket as its message.
8. A customer must not read an internal message through any join, view or RPC.
9. Only one current assignment, already enforced by the partial index.
10. SLA policy selection must pick the most specific active policy and snapshot
    its targets.

These are listed in [TEST_PLAN](TEST_PLAN.md) and [BACKLOG](BACKLOG.md).
