# Data Dictionary

Column-level reference for all **37 public tables**. The DDL in
`supabase/migrations/` is authoritative; this document explains intent and
constraints. `timestamptz` values are UTC.

Legend: **Null** = `No` means `NOT NULL`. Defaults are shown as written in SQL.

---

## 1. Identity and access

### 1.1 `profiles`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | — | PK; FK → `auth.users(id)` cascade |
| `email` | text | No | — | Unique on `lower(email)`; must contain `@` |
| `full_name` | text | No | — | 1–120 characters |
| `phone` | text | Yes | — | Optional contact number |
| `locale` | text | No | `'en'` | `en` or `ar` |
| `account_status` | text | No | `'active'` | `active`, `suspended`, `disabled` |
| `created_at` | timestamptz | No | `now()` | |
| `updated_at` | timestamptz | No | `now()` | Trigger-maintained |

### 1.2 `roles`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `code` | text | No | — | PK: `customer`, `support_agent`, `team_leader`, `system_admin`, `management_viewer` |
| `name_en` | text | No | — | English label |
| `name_ar` | text | No | — | Arabic label |
| `description_en` | text | Yes | — | English description |
| `description_ar` | text | Yes | — | Arabic description |

### 1.3 `user_roles`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `user_id` | uuid | No | — | PK part; FK → profiles cascade |
| `role_code` | text | No | — | PK part; FK → roles |
| `granted_by` | uuid | Yes | — | FK → profiles; deleting the granter is restricted |
| `granted_at` | timestamptz | No | `now()` | |

Index: `user_roles_role_idx(role_code)`.

### 1.4 `organizations`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `name` | text | No | — | Display name |
| `is_active` | boolean | No | `true` | |
| `created_at` | timestamptz | No | `now()` | |

### 1.5 `customer_profiles`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `user_id` | uuid | No | — | PK; FK → profiles cascade |
| `organization_id` | uuid | Yes | — | FK → organizations |
| `job_title` | text | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |

### 1.6 `departments`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `description_en` | text | Yes | — | |
| `description_ar` | text | Yes | — | |
| `is_active` | boolean | No | `true` | |
| `created_at` | timestamptz | No | `now()` | |

### 1.7 `teams`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `department_id` | uuid | Yes | — | FK → departments `on delete set null` |
| `code` | text | No | — | Unique short code |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `is_active` | boolean | No | `true` | |
| `created_at` | timestamptz | No | `now()` | |

### 1.8 `team_members`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `team_id` | uuid | No | — | PK; FK → teams cascade |
| `user_id` | uuid | No | — | PK; FK → profiles cascade |
| `team_role` | text | No | — | `leader` or `agent` |
| `is_active` | boolean | No | `true` | |
| `joined_at` | timestamptz | No | `now()` | |

Partial index `team_members_user_idx(user_id) where is_active`.

### 1.9 `user_invitations`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `email` | text | No | — | Invitee address |
| `role_code` | text | No | — | FK → roles |
| `team_id` | uuid | Yes | — | FK → teams set null |
| `invited_by` | uuid | Yes | — | FK → profiles; deletion restricted |
| `token_hash` | text | No | — | Unique; store a hash, never the raw token |
| `expires_at` | timestamptz | No | — | |
| `accepted_at` | timestamptz | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |

Partial unique index on `lower(email) where accepted_at is null`.

---

## 2. Catalog

### 2.1 `ticket_categories`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `parent_id` | uuid | Yes | — | Self-FK; max depth 2; delete restricted |
| `code` | text | No | — | Unique stable code |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `description_en` | text | Yes | — | |
| `description_ar` | text | Yes | — | |
| `default_team_id` | uuid | Yes | — | FK → teams set null |
| `is_active` | boolean | No | `true` | Hidden from customers when false |
| `sort_order` | int | No | `0` | |
| `created_at` | timestamptz | No | `now()` | |

Indexes: parent, `(is_active, sort_order)`.

### 2.2 `priorities`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `code` | text | No | — | Unique: `critical`, `high`, `normal`, `low` |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `weight` | int | No | — | 1–100; higher = more urgent |
| `is_active` | boolean | No | `true` | |
| `created_at` | timestamptz | No | `now()` | |

### 2.3 `ticket_custom_fields`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `category_id` | uuid | Yes | — | FK → categories cascade; `NULL` = global |
| `code` | text | No | — | Unique per category (`NULLS NOT DISTINCT`) |
| `label_en` | text | No | — | |
| `label_ar` | text | No | — | |
| `help_en` | text | Yes | — | |
| `help_ar` | text | Yes | — | |
| `field_type` | text | No | — | `text`, `long_text`, `number`, `date`, `dropdown`, `multi_select`, `checkbox`, `radio`, `file` |
| `is_required` | boolean | No | `false` | |
| `is_active` | boolean | No | `true` | |
| `options` | jsonb | Yes | — | Choices for select fields |
| `validation` | jsonb | Yes | — | Min/max/pattern rules |
| `visibility` | text | No | `'both'` | `both`, `customer`, `staff` |
| `sort_order` | int | No | `0` | |
| `created_at` | timestamptz | No | `now()` | |

Partial index on `(category_id, sort_order) where is_active`.

---

## 3. Ticketing core

### 3.1 `ticket_number_counters`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `ticket_year` | int | No | — | PK; 2000–9999 |
| `last_value` | bigint | No | `0` | Last allocated sequence; ≥ 0 |

### 3.2 `tickets`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `reference` | text | No | — | Unique; `CTS-YYYY-NNNNNN` |
| `subject` | text | No | — | 5–200 chars |
| `description` | text | No | — | ≥ 10 chars |
| `customer_id` | uuid | No | — | FK → profiles restrict |
| `organization_id` | uuid | Yes | — | FK → organizations set null |
| `category_id` | uuid | No | — | FK → categories restrict |
| `priority_id` | uuid | No | — | FK → priorities restrict |
| `status` | ticket_status | No | `'new'` | Lifecycle state |
| `team_id` | uuid | Yes | — | Queue owner |
| `assignee_id` | uuid | Yes | — | Current agent |
| `locale` | text | No | `'en'` | Customer language at creation |
| `source` | text | No | `'web'` | Only `web` allowed today |
| `first_response_at` | timestamptz | Yes | — | Set on first public staff reply |
| `resolved_at` | timestamptz | Yes | — | |
| `closed_at` | timestamptz | Yes | — | |
| `reopened_at` | timestamptz | Yes | — | |
| `reopen_count` | int | No | `0` | ≥ 0 |
| `resolution_summary` | text | Yes | — | Required by policy on resolve |
| `resolution_by` | uuid | Yes | — | FK → profiles set null |
| `customer_confirmed_at` | timestamptz | Yes | — | Stops reopen |
| `last_public_message_at` | timestamptz | Yes | — | |
| `version` | int | No | `1` | Optimistic concurrency |
| `search_vector` | tsvector | No | generated | Subject weight A, description weight B, `simple` |
| `created_at` | timestamptz | No | `now()` | |
| `updated_at` | timestamptz | No | `now()` | Trigger-maintained |

Indexes: customer/updated, queue, assignee/status, status/updated, GIN search.

### 3.3 `ticket_status_history`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | bigint | No | identity | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `from_status` | ticket_status | Yes | — | `NULL` for the initial state |
| `to_status` | ticket_status | No | — | |
| `changed_by` | uuid | Yes | — | FK → profiles set null; `NULL` for system |
| `actor_type` | text | No | `'user'` | `user` or `system` |
| `reason` | text | Yes | — | Required by RPC when rule says so |
| `is_customer_visible` | boolean | No | `true` | |
| `changed_at` | timestamptz | No | `now()` | |

### 3.4 `ticket_transition_rules`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `from_status` | ticket_status | No | — | PK part |
| `to_status` | ticket_status | No | — | PK part |
| `allowed_roles` | text[] | No | — | At least one role code |
| `customer_allowed` | boolean | No | `false` | UI hint; RPC still checks `allowed_roles` |
| `requires_reason` | boolean | No | `false` | Resolution/reopen reasons |

### 3.5 `ticket_custom_field_values`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `field_id` | uuid | No | — | FK → custom fields cascade |
| `value` | jsonb | Yes | — | Type depends on field definition |
| `created_at` | timestamptz | No | `now()` | |
| `updated_at` | timestamptz | No | `now()` | Trigger-maintained |

Unique `(ticket_id, field_id)`.

### 3.6 `ticket_messages`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `author_id` | uuid | Yes | — | FK → profiles set null |
| `visibility` | message_visibility | No | `'public'` | `public` or `internal` |
| `body` | text | No | — | 1–20,000 chars |
| `is_system` | boolean | No | `false` | System events; author optional |
| `created_at` | timestamptz | No | `now()` | |
| `edited_at` | timestamptz | Yes | — | |
| `deleted_at` | timestamptz | Yes | — | Soft delete |

Check: `is_system OR author_id IS NOT NULL`.

### 3.7 `ticket_attachments`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | Yes | — | FK → tickets cascade; required when linked |
| `message_id` | uuid | Yes | — | FK → messages set null |
| `uploaded_by` | uuid | No | — | FK → profiles restrict |
| `storage_path` | text | No | — | Unique object key |
| `file_name` | text | No | — | 1–255 chars |
| `mime_type` | text | No | — | Must match bucket allow-list at upload |
| `size_bytes` | bigint | No | — | 1–26,214,400 |
| `checksum` | text | Yes | — | Optional integrity hash |
| `visibility` | message_visibility | No | `'public'` | |
| `status` | text | No | `'draft'` | `draft` or `linked` |
| `created_at` | timestamptz | No | `now()` | |

Check: `(status='draft' AND ticket_id IS NULL) OR (status='linked' AND ticket_id IS NOT NULL)`.

### 3.8 `ticket_assignments`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `assigned_to` | uuid | Yes | — | FK → profiles set null |
| `team_id` | uuid | Yes | — | FK → teams set null |
| `assigned_by` | uuid | Yes | — | FK → profiles set null |
| `assigned_at` | timestamptz | No | `now()` | |
| `ended_at` | timestamptz | Yes | — | `NULL` = current assignment |
| `reason` | text | Yes | — | |

Check `ended_at >= assigned_at`. Unique partial index on `ticket_id where ended_at is null`.

---

## 4. SLA and calendars

### 4.1 `business_calendars`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `name` | text | No | — | |
| `timezone` | text | No | `'Asia/Riyadh'` | IANA zone used for business hours |
| `is_24_7` | boolean | No | `false` | If true, ignore intervals/holidays |
| `created_at` | timestamptz | No | `now()` | |

### 4.2 `business_calendar_intervals`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `calendar_id` | uuid | No | — | FK → calendars cascade |
| `day_of_week` | smallint | No | — | 0 = Sunday … 6 = Saturday |
| `start_time` | time | No | — | Local time |
| `end_time` | time | No | — | Local time; must be after start |

Unique `(calendar_id, day_of_week, start_time)`.

### 4.3 `holidays`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `calendar_id` | uuid | No | — | FK → calendars cascade |
| `holiday_date` | date | No | — | |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `is_recurring` | boolean | No | `false` | Stored, but not yet expanded by the calculator |

Unique `(calendar_id, holiday_date)`.

### 4.4 `sla_policies`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `name` | text | No | — | |
| `priority_id` | uuid | Yes | — | Scope; FK → priorities cascade |
| `category_id` | uuid | Yes | — | Scope; FK → categories cascade |
| `team_id` | uuid | Yes | — | Scope; FK → teams cascade |
| `first_response_minutes` | int | No | — | 1–525,600 business minutes |
| `resolution_minutes` | int | No | — | 1–525,600 business minutes |
| `business_calendar_id` | uuid | No | — | FK → calendars |
| `warning_threshold_pct` | int | No | `75` | 1–100 |
| `pause_on_pending_customer` | boolean | No | `true` | |
| `pause_on_pending_internal` | boolean | No | `false` | |
| `is_default` | boolean | No | `false` | One active default maximum |
| `is_active` | boolean | No | `true` | |
| `version` | int | No | `1` | ≥ 1 |
| `effective_from` | timestamptz | No | `now()` | |
| `created_at` | timestamptz | No | `now()` | |

### 4.5 `sla_escalation_rules`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `policy_id` | uuid | No | — | FK → policies cascade |
| `level` | int | No | — | 1–10; unique per policy |
| `threshold_pct` | int | No | — | 1–100 |
| `notify_role` | text | Yes | — | FK → roles |
| `notify_team_id` | uuid | Yes | — | FK → teams set null |
| `created_at` | timestamptz | No | `now()` | |

### 4.6 `ticket_sla_records`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `metric` | text | No | — | `first_response` or `resolution` |
| `cycle` | smallint | No | `1` | ≥ 1; increments on reopen |
| `policy_id` | uuid | No | — | FK → policies (blocks policy deletion) |
| `target_minutes` | int | No | — | Snapshot of policy target |
| `started_at` | timestamptz | No | — | |
| `due_at` | timestamptz | No | — | Precomputed |
| `warning_at` | timestamptz | No | — | Precomputed |
| `paused_at` | timestamptz | Yes | — | |
| `paused_seconds` | int | No | `0` | ≥ 0 |
| `completed_at` | timestamptz | Yes | — | |
| `breached_at` | timestamptz | Yes | — | |
| `state` | sla_state | No | `'on_track'` | |
| `escalation_level` | int | No | `0` | ≥ 0 |
| `last_evaluated_at` | timestamptz | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |

Unique `(ticket_id, metric, cycle)`. Checks: `due_at >= started_at`,
`warning_at <= due_at`.

### 4.7 `sla_events`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | bigint | No | identity | PK |
| `sla_record_id` | uuid | No | — | FK → SLA records cascade |
| `event_type` | text | No | — | `started`, `paused`, `resumed`, `warning`, `breached`, `escalated`, `completed` |
| `occurred_at` | timestamptz | No | `now()` | |
| `metadata` | jsonb | No | `'{}'` | |
| `dedupe_key` | text | No | — | Unique; prevents duplicate events |

### 4.8 `escalations`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | FK → tickets cascade |
| `sla_record_id` | uuid | Yes | — | FK → SLA records set null |
| `level` | int | No | — | 1–10 |
| `escalated_to_role` | text | Yes | — | FK → roles |
| `escalated_to_team` | uuid | Yes | — | FK → teams set null |
| `reason` | text | Yes | — | |
| `acknowledged_at` | timestamptz | Yes | — | |
| `resolved_at` | timestamptz | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |
| `dedupe_key` | text | No | — | Unique |

---

## 5. Operations

### 5.1 `notifications`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `user_id` | uuid | No | — | FK → profiles cascade |
| `ticket_id` | uuid | Yes | — | FK → tickets cascade |
| `type` | text | No | — | Application-defined event key |
| `payload` | jsonb | No | `'{}'` | Display data; no secrets |
| `read_at` | timestamptz | Yes | — | |
| `dedupe_key` | text | No | — | Unique |
| `created_at` | timestamptz | No | `now()` | |

### 5.2 `email_outbox`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `to_email` | text | No | — | Address snapshot; must contain `@` |
| `template_key` | text | No | — | Template identifier |
| `locale` | text | No | — | `en` or `ar` |
| `payload` | jsonb | No | `'{}'` | Template variables |
| `status` | text | No | `'pending'` | `pending`, `sending`, `sent`, `failed`, `cancelled` |
| `attempts` | int | No | `0` | ≥ 0 |
| `next_attempt_at` | timestamptz | No | `now()` | Backoff schedule |
| `sent_at` | timestamptz | Yes | — | |
| `last_error` | text | Yes | — | Redact provider secrets before storing |
| `dedupe_key` | text | No | — | Unique |
| `created_at` | timestamptz | No | `now()` | |

RLS enabled, no policies, no client grants.

### 5.3 `audit_logs`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | bigint | No | identity | PK |
| `actor_id` | uuid | Yes | — | FK → profiles set null |
| `actor_type` | text | No | `'user'` | `user`, `system`, `anonymous` |
| `action` | text | No | — | Verb such as `ticket.status_changed` |
| `entity_type` | text | No | — | Table/domain name |
| `entity_id` | text | Yes | — | String form of the id |
| `before` | jsonb | Yes | — | Redacted snapshot |
| `after` | jsonb | Yes | — | Redacted snapshot |
| `request_id` | text | Yes | — | Correlation id |
| `ip` | inet | Yes | — | |
| `user_agent` | text | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |

Append-only trigger rejects UPDATE/DELETE.

### 5.4 `system_settings`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `key` | text | No | — | PK |
| `value` | jsonb | No | — | Typed by convention |
| `description` | text | Yes | — | |
| `updated_by` | uuid | Yes | — | FK → profiles set null |
| `updated_at` | timestamptz | No | `now()` | Trigger-maintained |

Seeded keys: `customer_priority_selection`, `reopen_window_days`,
`max_reopens`, `auto_close_business_days`, `attachment_max_bytes`,
`attachment_max_per_message`, `reference_prefix`, `default_locale`.

---

## 6. Knowledgebase and feedback

### 6.1 `kb_categories`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `parent_id` | uuid | Yes | — | Self-FK restrict |
| `slug` | text | No | — | Unique |
| `name_en` | text | No | — | |
| `name_ar` | text | No | — | |
| `sort_order` | int | No | `0` | |
| `is_active` | boolean | No | `true` | |
| `created_at` | timestamptz | No | `now()` | |

### 6.2 `kb_articles`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `category_id` | uuid | Yes | — | FK → KB categories set null |
| `slug` | text | No | — | Unique |
| `title_en` | text | No | — | |
| `title_ar` | text | No | — | |
| `summary_en` | text | Yes | — | |
| `summary_ar` | text | Yes | — | |
| `body_en` | text | No | — | Markdown/plain text, rendered safely |
| `body_ar` | text | No | — | |
| `status` | text | No | `'draft'` | `draft`, `published`, `archived` |
| `visibility` | text | No | `'public'` | `public`, `authenticated`, `staff` |
| `author_id` | uuid | Yes | — | FK → profiles set null |
| `published_at` | timestamptz | Yes | — | |
| `view_count` | bigint | No | `0` | ≥ 0 |
| `search_vector` | tsvector | No | generated | Bilingual title/body |
| `created_at` | timestamptz | No | `now()` | |
| `updated_at` | timestamptz | No | `now()` | Trigger-maintained |

### 6.3 `kb_article_feedback`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `article_id` | uuid | No | — | FK → articles cascade |
| `user_id` | uuid | No | — | FK → profiles cascade |
| `is_helpful` | boolean | No | — | |
| `comment` | text | Yes | — | |
| `created_at` | timestamptz | No | `now()` | |

Unique `(article_id, user_id)`.

### 6.4 `kb_article_relations`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `article_id` | uuid | No | — | PK; FK → articles cascade |
| `related_article_id` | uuid | No | — | PK; FK → articles cascade; must differ |

### 6.5 `customer_feedback`

| Column | Type | Null | Default | Description |
| --- | --- | --- | --- | --- |
| `id` | uuid | No | `gen_random_uuid()` | PK |
| `ticket_id` | uuid | No | — | Unique; FK → tickets cascade |
| `customer_id` | uuid | No | — | FK → profiles cascade |
| `rating` | smallint | No | — | 1–5 |
| `comment` | text | Yes | — | ≤ 2,000 chars |
| `created_at` | timestamptz | No | `now()` | |

---

## 7. Enum domains

| Enum | Values | Notes |
| --- | --- | --- |
| `ticket_status` | `new`, `open`, `in_progress`, `pending_customer`, `pending_internal`, `resolved`, `closed`, `reopened` | Adding a value requires a migration; removing is unsupported |
| `message_visibility` | `public`, `internal` | Internal rows are staff-only through RLS |
| `sla_state` | `on_track`, `due_soon`, `breached`, `paused`, `completed` | `due_soon` begins at `warning_at` |

## 8. Data retention notes (not yet enforced)

No retention job exists. Before production launch, decide and implement:

- `audit_logs`: retain at least 12 months; append-only.
- `email_outbox`: purge `sent`/`cancelled` rows after 90 days.
- `notifications`: purge read rows after 90 days.
- `sla_events`: retain with the ticket record.
- Deleted attachment objects: remove from Storage when the DB row is deleted.
- Customer deletion requests: legal review required because ticket history is
  business record data; current FKs restrict customer deletion when tickets
  exist.

These are open decisions, not implemented behaviour.
