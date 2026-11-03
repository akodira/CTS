# Migration Readiness

> This document describes how the current domain vocabulary maps to a future
> .NET / Angular / SQL Server migration. **Nothing in this document has been
> implemented.** It is a planning aid, not a commitment.

## 1. Objective

Preserve the business rules while replacing the Supabase/Next.js stack with a
more traditional enterprise stack. The goal is to avoid re-inventing the ticket
lifecycle, SLA logic or authorization model.

## 2. Mapping

| Concern | Current (Phase 1) | Future target | Notes |
| --- | --- | --- | --- |
| Frontend | Next.js 16 App Router, React 19, `next-intl` | Angular (latest LTS) + Angular i18n or `@ngx-translate` | Port bilingual routing/RTL and component structure. Keep `messages/*.json` as a starting point. |
| API | Next.js Route Handlers + planned Supabase RPCs | ASP.NET Core Web API (minimal or controllers) | Replace RPCs with application services and explicit DTOs/validators (FluentValidation). |
| Auth | Supabase Auth (GoTrue), PKCE | ASP.NET Core Identity, Entra ID, or OIDC provider | Migrate users/tokens; must preserve roles. Plan a session/token strategy and account linking. |
| Authorization | PostgreSQL RLS + helper functions + role matrix | Application authorization (policies/handlers) + SQL Server RLS (optional) | Keep the same permission matrix and transition rules in code/DB. Never rely on client filtering. |
| Database | Supabase PostgreSQL 17 | SQL Server (latest) | Map enums, `jsonb`, arrays, `tsvector`, functions, triggers. See §3. |
| ORM | None (raw SQL + Supabase client) | Entity Framework Core | Use migrations (EF Core Migrations) or Flyway/Liquibase. Avoid lazy loading; use explicit queries. |
| Storage | Supabase Storage (private bucket) | Azure Blob Storage or AWS S3 | Replace signed URLs with a download proxy that checks authorization. |
| Email | Resend (planned) | SMTP / SendGrid / Azure Communication Services | Keep the transactional outbox pattern. |
| Cron/Jobs | Vercel Cron / Supabase `pg_cron` (planned) | Hangfire / Quartz.NET / Azure Functions / Worker Service | Port SLA evaluation and email dispatch with the same idempotency rules. |
| Logging | Pino (server JSON) | Serilog / Microsoft.Extensions.Logging | Preserve redaction patterns for PII/secrets. |
| Validation | Zod | FluentValidation or DataAnnotations | Mirror schemas to server-side validation. |
| Types | TypeScript, Supabase-generated types | C# DTOs, OpenAPI generated clients | Generate contracts from OpenAPI to keep FE/BE in sync. |

## 3. PostgreSQL → SQL Server migration notes

| Feature | PostgreSQL | SQL Server | Migration strategy |
| --- | --- | --- | --- |
| Enums | `CREATE TYPE ... AS ENUM` | `CHECK` constraints or lookup tables | Prefer lookup tables for extensibility (`ticket_statuses`, `message_visibilities`) |
| UUIDs | `gen_random_uuid()`, `uuid` type | `NEWID()`, `UNIQUEIDENTIFIER` | Map 1:1; ensure defaults and comparisons work |
| JSON | `jsonb` | `NVARCHAR(MAX)` with `ISJSON`/JSON functions | Validate JSON at application layer; consider JSON schema checks |
| Arrays | `text[]`, `array[]` | Junction tables | Replace `allowed_roles text[]` with `ticket_transition_rule_roles` |
| Full-text search | `tsvector`, `to_tsvector`, GIN | Full-Text Search (CONTAINS/FREETEXT) or Azure AI Search | Rebuild indexes; adjust ranking |
| Triggers | `CREATE TRIGGER` | `AFTER/INSTEAD OF TRIGGER` | Port `set_updated_at`, `audit_logs_append_only`, `check_category_depth` |
| Functions/Procedures | `plpgsql` functions (definer) | Stored procedures / T-SQL or move to C# services | Many helpers can become application services; keep security-sensitive logic in SPs with explicit permissions |
| RLS | Row Level Security with policies | Row-Level Security or application filters | SQL Server RLS is possible; application-layer authorization is often clearer. Defense in depth is still required. |
| Timestamps | `timestamptz` (UTC) | `DATETIMEOFFSET` or `DATETIME2` with UTC convention | Store UTC, convert in UI using `Asia/Riyadh` |
| Partial/unique indexes | Many partial unique indexes | Filtered indexes | SQL Server supports filtered indexes |
| Sequences | `bigserial`, custom counters | `IDENTITY` or sequences | Port `ticket_number_counters` logic |
| `INET` | `audit_logs.ip` | `VARCHAR(45)` or `SYSNAME` | Store as string or use appropriate type |

## 4. What to preserve

- **Domain vocabulary:** Statuses, roles, transition names and SLA states must
  remain identical or be mapped with a compatibility layer.
- **Business rules:** Reopen window (7 days), max reopens (2), auto-close (3
  business days), pause-on-pending-customer, escalation at 75%/100%.
- **Authorization matrix:** The role/permission matrix in
  [ROLES_AND_PERMISSIONS](ROLES_AND_PERMISSIONS.md) is the source of truth.
- **Auditability:** Append-only audit log, status history, assignment history.
- **Idempotency:** Dedupe keys on outbox/events/escalations.
- **Bilingual data:** `name_en`/`name_ar` columns and message localization.
- **SLA precomputation:** Snapshotted deadlines and business-hour calendar.

## 5. Migration strategy

1. **Inventory** — Confirm every table, function, trigger, policy and seed.
2. **Schema conversion** — Use a tool (e.g. AWS SCT) as a starting point, then
   manually fix enums/arrays/json/tsvector.
3. **Data migration** — Export from Supabase (COPY/pg_dump) and import to SQL
   Server with type conversions. Validate counts and foreign keys.
4. **Auth migration** — Plan user migration (password hashes may not transfer
   directly). Use a migration flow or re-provision with invitations.
5. **API parity** — Port RPCs to services; write contract tests against the same
   OpenAPI spec.
6. **UI port** — Port components and i18n; maintain RTL support.
7. **Parallel run** — Run both systems in parallel with read-only comparison
   before cutover.
8. **Cutover** — DNS switch, verify health, monitor errors and SLA jobs.
9. **Rollback plan** — Keep Supabase read-only or have a rollback window.

## 6. Effort estimate (rough)

| Area | Effort | Notes |
| --- | --- | --- |
| Schema & data | Medium-High | JSON/arrays/FTS are the hardest parts |
| Auth & authorization | High | Must be correct; security-critical |
| API services | Medium-High | Reimplement RPC logic with tests |
| UI port to Angular | High | Depends on component complexity |
| SLA/jobs | Medium | Port calendar logic carefully |
| Testing & cutover | Medium-High | RLS parity tests are essential |

**This is planning only. No code has been written for this migration.**
