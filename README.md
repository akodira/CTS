# Customer Ticketing System (CTS)

A bilingual (English / Arabic, full RTL) customer support platform: a customer
portal for raising and tracking service requests, and a support console for
queues, assignments, SLA tracking, internal notes and reporting.

This repository currently contains **Phase 1 — Foundation**. It is a working
Next.js application shell with a prepared PostgreSQL schema. It is **not** a
finished ticketing product: authentication screens, ticket screens, ticket
mutation RPCs, email delivery and background jobs are scheduled for later
phases and do not exist yet.

> **Verification status (2026-11-02)**
>
> | Gate | Result |
> | --- | --- |
> | TypeScript (`npm run typecheck`) | Passing |
> | ESLint (`npm run lint`) | Passing |
> | Unit tests (`npm test`) | 4 files, 31 tests passing |
> | Coverage (`npx vitest run --coverage`) | 98.07% statements, 94.11% branches |
> | Production build (`npm run build`) | Passing |
> | Database migrations executed | **Not executed** — no Docker/Supabase CLI on the build machine |
> | Playwright E2E (`npm run test:e2e`) | **Not executed** — browsers not installed |
> | Deployed and URL tested | **No** — deployment is performed by the project owner |
>
> See [docs/TEST_RESULTS.md](docs/TEST_RESULTS.md) for the exact commands and
> output, and [docs/KNOWN_ISSUES.md](docs/KNOWN_ISSUES.md) for open gaps.

---

## Stack

| Concern | Choice | Version |
| --- | --- | --- |
| Framework | Next.js App Router (Turbopack) | 16.4.3 |
| UI | React | 19.3.1 |
| Language | TypeScript | 5.9.3 |
| Styling | Tailwind CSS v4 + `@tailwindcss/postcss` | 4.3.3 |
| i18n | `next-intl` with `en` / `ar` routing and RTL | 4.14.9 |
| Database / Auth / Storage | Supabase (PostgreSQL 17, GoTrue, Storage) | `@supabase/supabase-js` 2.118.0, `@supabase/ssr` 0.12.7 |
| Validation | Zod | 4.6.7 |
| Logging | Pino (server only, redacted) | 10.4.0 |
| Unit tests | Vitest | 5.0.5 |
| E2E tests | Playwright | 1.64.1 |
| Lint | ESLint flat config + `eslint-config-next` | 10.14.0 / 16.4.3 |
| Hosting | Vercel | — |
| Email (planned) | Resend | — |

No ORM is used. Database access is through the Supabase client and
`SECURITY DEFINER` RPCs; PostgreSQL is the authorization authority.

---

## What Phase 1 delivers

- Next.js 16 application shell with `/[locale]` routing for `en` and `ar`.
- `dir="rtl"` layout, Arabic typography (IBM Plex Sans Arabic), localized
  metadata and a working locale switcher that preserves the current path.
- Bilingual, responsive landing page that describes the product **without fake
  metrics, fake tickets or dead controls**.
- Supabase browser, server, proxy-session and service-role clients with clear
  trust boundaries.
- Session refresh in `src/proxy.ts` (Next 16 proxy convention) combined with
  `next-intl` locale routing.
- Environment validation with Zod, fail-fast on missing server secrets.
- Structured Pino logging with PII redaction.
- `/api/health` endpoint that actually checks the database through a
  `health()` RPC (returns `503 unconfigured` until Supabase is configured).
- `/auth/callback` PKCE exchange route for email verification and recovery.
- Pure domain modules for ticket status transitions, reopen eligibility, role
  permissions and ticket reference formatting, covered by unit tests.
- 10 forward-only SQL migrations: identity, catalog, ticket core, SLA, audit,
  knowledgebase, helpers, RLS, storage bucket and approved reference data.
- GitHub Actions workflows for quality gates and manual migration promotion.
- This documentation set.

## What Phase 1 deliberately does not include

- Registration, sign-in, password reset and profile screens (Phase 2).
- Ticket create/list/detail/message/attachment UI (Phase 3).
- Ticket mutation RPCs such as `create_ticket`, `post_message`,
  `change_status`, `claim_ticket` (Phase 3/4).
- SLA evaluation cron, escalation notifications and email dispatch (Phase 5).
- Knowledgebase, CSAT and reporting screens (Phase 6).
- Categories, departments, teams and branding data — these need business input.

The database schema and RLS policies for those features are prepared, but
**prepared is not the same as verified**. No migration has been executed yet.

---

## Quick start

### Prerequisites

- Node.js 22.12–24 (built and tested here with Node 24.22.0, npm 11.19.1). The upper bound is pinned so a future Node major cannot silently break the Vercel build.
- Git
- Optional for local database work: Docker Desktop and the Supabase CLI
  (see [docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md), step B1)

### Run the web shell

```powershell
npm install
Copy-Item .env.example .env.local
# Edit .env.local and fill the Supabase values.
npm run dev
```

Open <http://localhost:3000> — it redirects to `/en`. The landing page renders
even when Supabase variables are blank because no data is fetched; the health
endpoint will report `503 unconfigured` until real values are supplied.

### Run quality gates

```powershell
npm run typecheck
npm run lint
npm test
npx vitest run --coverage
npm run build
```

### Run end-to-end tests

Playwright browsers must be installed once:

```powershell
npx playwright install chromium
npm run test:e2e
```

The E2E suite starts the dev server automatically unless
`PLAYWRIGHT_BASE_URL` is set.

### Local database

```powershell
supabase start          # requires Docker Desktop
npm run db:reset        # applies supabase/migrations from scratch
npm run db:types        # regenerates src/types/database.types.ts
```

The SQL assumes Supabase-managed roles (`anon`, `authenticated`,
`service_role`), `auth.users` and `storage.buckets`. It will not run on a plain
PostgreSQL instance.

---

## Project structure

```text
.
├── .github/
│   ├── pull_request_template.md
│   └── workflows/
│       ├── ci.yml                 # typecheck, lint, test, build, db reset
│       └── migrations.yml         # manual staging/production migration push
├── docs/                          # 17 design, operations and verification docs
├── messages/
│   ├── en.json                    # English UI strings
│   └── ar.json                    # Arabic UI strings
├── src/
│   ├── app/
│   │   ├── [locale]/              # localized pages and root locale layout
│   │   ├── api/health/            # real database health check
│   │   ├── auth/callback/         # Supabase PKCE callback
│   │   └── globals.css            # Tailwind v4 theme and base styles
│   ├── components/layout/         # header, footer, locale switcher
│   ├── domain/                    # pure business rules + unit tests
│   ├── i18n/                      # routing, navigation, request config
│   ├── lib/
│   │   ├── logging/               # Pino logger
│   │   ├── supabase/              # browser, server, admin, proxy clients
│   │   ├── env.ts                 # Zod environment validation
│   │   └── utils/cn.ts
│   └── proxy.ts                   # locale routing + session refresh
├── supabase/
│   ├── config.toml
│   └── migrations/                # 0001–0010, forward only
├── tests/
│   ├── unit/                      # Vitest
│   └── e2e/                       # Playwright
├── next.config.ts                 # security headers, next-intl plugin
├── playwright.config.ts
├── vitest.config.ts
└── package.json
```

---

## Security model in one page

1. **RLS is the read boundary.** Every application table has row-level security
   enabled. Customers only see their own tickets; staff see their team/queue;
   administrators see everything; management viewers are read-only.
2. **Writes go through RPCs.** Authenticated clients receive `SELECT` grants
   only. Ticket mutations will be `SECURITY DEFINER` functions that validate
   role, transition rules, tenant ownership and optimistic concurrency.
3. **The service-role key never reaches the browser.** It is read through
   `src/lib/supabase/admin.ts`, which imports `server-only`, and is reserved for
   cron jobs, provider webhooks and signed attachment downloads.
4. **Private notes are filtered in the database.** `ticket_messages.visibility`
   plus RLS — not component logic — decides whether a customer can read a row.
5. **Secrets are server-only.** Only `NEXT_PUBLIC_*` values are exposed.
   `.env*` files are git-ignored; `.env.example` contains placeholders only.
6. **Attachments are private.** The `attachments` bucket is non-public; future
   downloads must pass an authorization check before issuing a short-lived
   signed URL.

Full review and open findings: [docs/SECURITY_REVIEW.md](docs/SECURITY_REVIEW.md).

---

## Documentation

| Document | Contents |
| --- | --- |
| [SYSTEM_ARCHITECTURE](docs/SYSTEM_ARCHITECTURE.md) | Components, request flows, trust boundaries, deployment topology |
| [DATABASE_SCHEMA](docs/DATABASE_SCHEMA.md) | Every table, enum, constraint, index and function, by migration |
| [DATABASE_RELATIONSHIPS](docs/DATABASE_RELATIONSHIPS.md) | ERD and relationship/cascade map |
| [DATA_DICTIONARY](docs/DATA_DICTIONARY.md) | Column-level reference for all 37 public tables |
| [ROLES_AND_PERMISSIONS](docs/ROLES_AND_PERMISSIONS.md) | Role matrix and enforcement layers |
| [TICKET_WORKFLOW](docs/TICKET_WORKFLOW.md) | Statuses, transition table, reopen and auto-close rules |
| [SLA_CONFIGURATION](docs/SLA_CONFIGURATION.md) | Approved targets, calendar, pause/escalation behaviour |
| [API_DOCUMENTATION](docs/API_DOCUMENTATION.md) | Implemented routes and planned RPC contracts |
| [DEPLOYMENT_GUIDE](docs/DEPLOYMENT_GUIDE.md) | **B1–B7** step-by-step GitHub/Supabase/Vercel/email/domain runbook |
| [ENVIRONMENT_CONFIGURATION](docs/ENVIRONMENT_CONFIGURATION.md) | Every variable, scope, rotation and CI usage |
| [SECURITY_REVIEW](docs/SECURITY_REVIEW.md) | Threat model, controls, findings and pre-launch gates |
| [TEST_PLAN](docs/TEST_PLAN.md) | Unit, database, RLS, E2E, accessibility and security coverage |
| [TEST_RESULTS](docs/TEST_RESULTS.md) | What was actually executed, with output and gaps |
| [KNOWN_ISSUES](docs/KNOWN_ISSUES.md) | Open defects, limitations and workarounds |
| [MIGRATION_READINESS](docs/MIGRATION_READINESS.md) | Future .NET / Angular / SQL Server mapping (not implemented) |
| [PROGRESS_LOG](docs/PROGRESS_LOG.md) | Dated decisions and work log |
| [BACKLOG](docs/BACKLOG.md) | Phase 2–8 backlog, acceptance criteria and missing inputs |

---

## Deployment

Deployment is owned by the project owner. Follow
[docs/DEPLOYMENT_GUIDE.md](docs/DEPLOYMENT_GUIDE.md) exactly, in order:

- **B1** — install and verify local tooling
- **B2** — create the GitHub repository, branches and protections
- **B3** — create the Supabase project (one project for now)
- **B4** — link the project, apply migrations, configure Auth and Storage
- **B5** — import to Vercel, set environment variables, deploy
- **B6** — cron, email domain and custom domain (only when the related feature
  exists and after choosing Hobby vs Pro)
- **B7** — verify, tag, and know how to roll back

Do not claim a deployment is successful until the deployed URL has been opened
and `/api/health` has been checked. A green Vercel build is not a working
deployment.

---

## Non-negotiables for later phases

- No fake UI, invented metrics or buttons that do nothing.
- No business rule invented in the UI; status and SLA rules stay in the
  database/domain modules.
- No committed secrets.
- No destructive database operation outside a reviewed migration.
- Every new mutation must be authorized server-side and covered by an RLS test.
- English and Arabic (including RTL) must be tested for every screen.
- Documentation and [TEST_RESULTS](docs/TEST_RESULTS.md) are updated in the
  same change that alters behaviour.

## Ownership

This is a private project. No open-source license is granted.
