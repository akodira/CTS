# API Documentation

> **Implemented surface is intentionally small.** Phase 1 ships two HTTP
> endpoints and the localized pages. Ticket APIs are specified as planned
> contracts; they do not exist yet. Do not integrate against them until they
> are implemented and listed under "Implemented".

## 1. Conventions

- Base URL: `NEXT_PUBLIC_APP_URL` (local default `http://localhost:3000`).
- Transport: HTTPS only in deployed environments.
- Auth: Supabase session cookies, refreshed in `src/proxy.ts`. Browser calls to
  Supabase use the anon key; server code uses the request session.
- Content type: `application/json` for API responses; `text/html`/RSC for pages.
- Timestamps: ISO 8601 UTC (`2026-11-02T08:00:00.000Z`). Display in
  `Asia/Riyadh`.
- IDs: UUID v4 unless documented otherwise. Ticket references are
  `CTS-YYYY-NNNNNN`.
- Errors return a JSON object with a stable `code` and a human-readable
  `message`. Do not parse message text.
- No API version prefix yet. Breaking changes require a new path or a version
  header before public consumers exist.
- CORS: same-origin only. No wildcard CORS is configured.

### Error envelope (planned for ticket APIs)

```json
{
  "error": {
    "code": "INVALID_TRANSITION",
    "message": "A ticket cannot move from closed to in_progress.",
    "requestId": "req_01J..."
  }
}
```

`requestId` correlates with server logs and `audit_logs.request_id`.

---

## 2. Implemented endpoints

### 2.1 `GET /api/health`

Liveness/readiness probe. Calls `public.health()` through PostgREST using the
anon key. No authentication required. Safe to expose.

**Responses**

| Status | Condition | Body |
| --- | --- | --- |
| `200` | Env configured and RPC succeeded | `{ "status": "ok", "checks": { "environment": true, "database": true }, "latencyMs": 42, "database": { "status": "ok", "db_time": "...", "schema_version": "0010" } }` |
| `503` | `NEXT_PUBLIC_SUPABASE_URL` or anon key missing | `{ "status": "unconfigured", "checks": { "environment": false, "database": false } }` |
| `503` | RPC returned non-2xx | `{ "status": "error", "checks": { "environment": true, "database": false }, "detail": "Database health check returned 500" }` |
| `503` | Network/parse failure | `{ "status": "error", "checks": { "environment": true, "database": false }, "detail": "Database health check failed" }` |

Notes:

- `Cache-Control` is not explicitly set, but the route is `force-dynamic` and
  uses `cache: 'no-store'`.
- The endpoint does not verify migrations beyond the hardcoded
  `schema_version` returned by the function. Extend it in Phase 5 to report the
  applied migration version and outbox backlog.
- A `503 unconfigured` response is expected on a fresh checkout before
  `.env.local` is filled in.

### 2.2 `GET /auth/callback`

Supabase PKCE callback used for email verification and password recovery.

| Query | Required | Description |
| --- | --- | --- |
| `code` | Yes (else redirects with error) | PKCE authorization code |
| `next` | No | Relative path to redirect to after exchange; default `/en` |

Behaviour:

1. Reject `next` values that are not same-origin relative paths (`//host` and
   absolute URLs are discarded).
2. Exchange the code for a session using the server client.
3. On success: `302` to `${origin}${next}`.
4. On failure/missing code: `302` to `${origin}/en?authError=callback`.

The callback does not render HTML and does not expose tokens in the URL after
the exchange. Phase 2 will route users to the correct localized dashboard.

### 2.3 Localized pages

| Route | Method | Description |
| --- | --- | --- |
| `/` | GET | Redirects to `/en` (or negotiated locale) |
| `/en` | GET | English landing page, `dir="ltr"` |
| `/ar` | GET | Arabic landing page, `dir="rtl"` |
| `/[locale]/*` | GET | Reserved for Phase 2+ pages; unknown paths render 404 |

The proxy excludes `/api`, `/auth`, `_next`, `_vercel` and static files from
locale handling.

---

## 3. Planned endpoints

These are design contracts. They are not implemented and return 404 today.

### 3.1 Cron

| Route | Schedule | Auth | Purpose |
| --- | --- | --- | --- |
| `GET /api/cron/sla` | every 5 min (Pro/pg_cron) | `Authorization: Bearer $CRON_SECRET` | Advance warning/breach/escalation states |
| `GET /api/cron/email` | every 1–5 min | Bearer `CRON_SECRET` | Dispatch `email_outbox` rows |
| `GET /api/cron/auto-close` | hourly/daily | Bearer `CRON_SECRET` | Close resolved tickets after 3 business days |

Responses: `200` with counts, `401` on bad secret, `500` with a request id.
Handlers must be idempotent and safe under overlapping invocations.

### 3.2 Attachments

| Route | Method | Purpose |
| --- | --- | --- |
| `POST /api/attachments/upload` | POST | Authorize, validate MIME/size, store draft, return attachment id |
| `GET /api/attachments/[id]/download` | GET | Authorize `private.can_view_ticket`, return `302` to a short-lived signed URL |

Constraints: 25 MiB max, 5 per message, allow-listed MIME types, private bucket.
Never return a permanent public URL.

### 3.3 Webhooks

| Route | Purpose |
| --- | --- |
| `POST /api/webhooks/resend` | Delivery/bounce events; verify signature; update outbox status |

Not designed in detail yet.

---

## 4. Planned RPC contracts

All are `SECURITY DEFINER` PostgreSQL functions, called through Supabase RPC
with the user's session. Every function validates `auth.uid()`, active account,
role, ticket scope and transition rules. None exist today.

### 4.1 `create_ticket`

```ts
type CreateTicketInput = {
  subject: string;                 // 5..200
  description: string;             // 10..20000
  category_id: string;             // active category or subcategory
  custom_fields?: Record<string, unknown>;
  locale: 'en' | 'ar';
  attachment_ids?: string[];       // drafts owned by the caller
};

type CreateTicketResult = {
  id: string;
  reference: string;               // CTS-YYYY-NNNNNN
};
```

Priority is assigned server-side. Errors: `VALIDATION_ERROR`,
`CATEGORY_INACTIVE`, `ATTACHMENT_NOT_OWNED`, `SLA_POLICY_MISSING`.

### 4.2 `post_message`

```ts
type PostMessageInput = {
  ticket_id: string;
  body: string;                    // 1..20000
  visibility: 'public' | 'internal';
  attachment_ids?: string[];
  expected_version?: number;       // optimistic concurrency
};
```

Customers may only post `public` on their own tickets. Staff internal notes
require `ticket.note.internal`. The first public staff reply sets
`first_response_at` and completes the first-response clock.

### 4.3 `change_ticket_status`

```ts
type ChangeStatusInput = {
  ticket_id: string;
  to_status: TicketStatus;
  reason?: string;                 // required when rule requires_reason
  expected_version?: number;
};
```

Checks `ticket_transition_rules`, role, ownership and domain preconditions.
Writes status history, audit, notification/outbox in one transaction.
Errors: `INVALID_TRANSITION`, `TRANSITION_FORBIDDEN`, `REASON_REQUIRED`,
`TICKET_VERSION_CONFLICT`.

### 4.4 Lifecycle helpers

| Function | Purpose |
| --- | --- |
| `confirm_resolution(ticket_id)` | Customer confirms; `resolved → closed`; sets `customer_confirmed_at` |
| `reopen_ticket(ticket_id, reason)` | Enforces 7 days / 2 reopens / not confirmed; new SLA cycle |
| `claim_ticket(ticket_id)` | Agent self-assigns; ends previous current assignment |
| `assign_ticket(ticket_id, assignee_id, team_id?)` | Leader/admin; validates team membership |
| `change_ticket_priority(ticket_id, priority_id, reason)` | Staff; snapshots future clocks |
| `escalate_ticket(ticket_id, reason)` | Leader/admin manual escalation |

### 4.5 Feedback and admin

| Function | Purpose |
| --- | --- |
| `submit_feedback(ticket_id, rating, comment?)` | Customer, one per ticket, rating 1–5 |
| `set_user_roles(user_id, roles[])` | Admin; rejects customer+staff mix; removes auto-customer |
| `invite_staff(email, role, team_id?)` | Admin; creates invitation + email outbox row |
| `update_sla_policy(...)` | Admin; versions/retires policy safely |
| `upsert_category(...)` / `upsert_priority(...)` | Admin catalog management |
| `publish_kb_article(...)` | Admin KB workflow |

### 4.6 Read RPCs / views

| Name | Purpose |
| --- | --- |
| `my_tickets(cursor, limit, status?)` | Customer list with SLA summary |
| `team_queue(team_id, filters)` | Staff queue, sorted by breach risk |
| `ticket_detail(reference)` | Header + permitted messages + SLA + history |
| `report_*` | Aggregate metrics for leaders/admin/management viewer |
| `search_tickets(query)` | Uses `search_vector`; RLS still applies |

Read RPCs must return only columns the caller may see. Prefer views with RLS
over ad-hoc joins in the client.

---

## 5. Pagination, filtering and concurrency

- Cursor pagination: `?cursor=<opaque>&limit=25`, max 100. Cursors encode
  `(updated_at, id)` or `(created_at, id)` and are signed/opaque server-side.
- Filters: status, priority, team, assignee, category, SLA state, date range.
- Sorting: default `updated_at desc`; queues may sort by `due_at asc`.
- `tickets.version` supports optimistic concurrency. Mutations accept
  `expected_version`; a mismatch returns `TICKET_VERSION_CONFLICT` and the UI
  reloads.
- Idempotency: mutations that create side effects accept an
  `Idempotency-Key` header. The server stores it with the result for 24 hours.
  Not implemented yet.

## 6. Rate limiting and abuse

No rate limiter is implemented. Before exposing ticket creation or public auth
forms:

- Add per-IP and per-account limits at the edge (Vercel WAF or Upstash Redis).
- Cap uploads by count/size and scan files.
- Add bot protection to signup/recovery.
- Log throttled requests without PII.
- Consider a CAPTCHA only if abuse is observed; do not add it pre-emptively.

## 7. API versioning and deprecation

Before the first external integration:

1. Introduce `/api/v1/*` or an `Accept-Version` header.
2. Publish an OpenAPI 3.1 document generated from Zod schemas.
3. Announce deprecations at least one release ahead.
4. Keep error codes stable; add, don't rename.

There is no OpenAPI document today. The TypeScript domain types and SQL
functions are the current contract.
