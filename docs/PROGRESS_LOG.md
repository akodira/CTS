# Progress Log

Chronological record of decisions and delivered work. Dates are local working
dates; the repository was not under Git until the owner pushes it.

## 2026-11-01 — Phase 0 design approval

### Approved decisions

| Topic | Decision |
| --- | --- |
| Architecture | Modular monolith, RPC-centric writes, RLS-centric reads |
| Stack | Next.js + TypeScript, Supabase (Postgres/Auth/Storage), Tailwind, Vercel, GitHub |
| SLA — Critical | First response 15 min, resolution 4 h |
| SLA — High | First response 1 h, resolution 8 h |
| SLA — Normal | First response 4 h, resolution 24 h |
| SLA — Low | First response 8 h, resolution 48 h |
| SLA warning | 75% of target |
| Business calendar | `Asia/Riyadh`, Sunday–Thursday, 08:00–17:00 |
| Pause rule | Pause only on `pending_customer` |
| Auto-close | 3 business days after `resolved` |
| Customer reopen | 7 calendar days, max 2 reopens, not after explicit confirmation |
| Escalation | Level 1 at 75% → `team_leader`; level 2 at 100% → `system_admin` |
| Customer priority selection | Disabled |
| Ticket reference | `CTS-YYYY-NNNNNN`; gaps allowed |
| Organization sharing | Deferred |
| Categories | To be supplied by the owner (not invented) |
| Writes | `SECURITY DEFINER` RPCs; clients get SELECT only |
| Email | Transactional outbox (not direct send in request) |
| SLA deadlines | Precomputed at clock start, snapshotted targets |
| Messages | Single table with `public` / `internal` visibility |
| Status rules | Stored in `ticket_transition_rules` |

### Deferred / open at approval

- Categories, departments, teams and branding data.
- Holiday list.
- Organization sharing.
- Final decision on Vercel Hobby vs Pro (needed only when cron is implemented).
- Email provider domain verification.

## 2026-11-02 — Phase 1 foundation

### Application scaffold

- Initialized Next.js 16 App Router project with TypeScript 5.9.3 and Tailwind
  CSS v4.
- Pinned versions and added `"type": "module"` to silence the Vitest ESM config
  warning.
- Added ESLint flat config and upgraded to ESLint 10.14.0 (9.39.5 was
  deprecated).
- Added Vitest, Playwright, coverage and npm scripts.

### Internationalization and UI shell

- Added `next-intl` routing with `en`/`ar`, `localePrefix: 'always'`, RTL
  support and the IBM Plex Sans Arabic font.
- Built bilingual landing page, header/footer, skip link and working locale
  switcher.
- Added metadata and localized strings; missing keys fail the build (this caught
  a missing `Footer.healthLink` during the first build).
- Fixed a `globals.css` import path and an ESLint rule for the `/api/health`
  anchor.

### Supabase foundation

- Added browser, server, proxy and admin clients with clear trust boundaries.
- Added `src/proxy.ts` for locale routing + session refresh (Next 16 proxy
  convention).
- Added `src/lib/env.ts` (Zod) and Pino logger with redaction.
- Added `/api/health` using the public key and `public.health()` RPC.
- Added `/auth/callback` PKCE exchange with relative-only `next` validation.

### Domain modules and tests

- Added `src/domain/ticket-status.ts` (8 statuses, transitions, reopen
  eligibility).
- Added `src/domain/permissions.ts` (5 roles, 30 permissions, exclusivity
  helper).
- Added `src/domain/ticket-reference.ts`.
- Added unit tests; final run: 4 files, 31 tests passing, 98.07% statements /
  94.11% branches coverage.

### Database design

- Wrote 10 forward-only migrations (0001–0010).
- 37 public tables, 3 enums, 18 functions (15 private, 3 public), 1 private
  storage bucket.
- Seed: 5 roles, 4 priorities, 30 transition rules, 1 calendar + 5 intervals,
  5 SLA policies, 10 escalation rules, 8 settings.
- Added missing `ticket_custom_field_values` table and RLS coverage.
- Added customer permission on `closed → reopened` to match reopen policy.
- Added escalation rules: 75% → team_leader, 100% → system_admin.
- Added private `attachments` bucket (25 MiB, MIME allow-list).
- `audit_logs` append-only trigger; `email_outbox` service-role only.

### CI and documentation

- Added `ci.yml` (typecheck, lint, test, build, clean Supabase reset).
- Added `migrations.yml` (manual staging/production push with environments).
- Added PR template.
- Wrote docs: README, SYSTEM_ARCHITECTURE, DATABASE_SCHEMA,
  DATABASE_RELATIONSHIPS, DATA_DICTIONARY, ROLES_AND_PERMISSIONS,
  TICKET_WORKFLOW, SLA_CONFIGURATION, API_DOCUMENTATION,
  ENVIRONMENT_CONFIGURATION, DEPLOYMENT_GUIDE, SECURITY_REVIEW, TEST_PLAN,
  TEST_RESULTS, KNOWN_ISSUES, MIGRATION_READINESS, PROGRESS_LOG, BACKLOG.

### Quality gates (executed)

| Gate | Result |
| --- | --- |
| `npm run typecheck` | Pass |
| `npm run lint` | Pass |
| `npm test` | 4 files, 31 tests pass |
| `npx vitest run --coverage` | 98.07% statements / 94.11% branches |
| `npm run build` | Pass (5 routes) |
| `npm audit --omit=dev` | 0 vulnerabilities |
| `npm audit` | 15 moderate, dev-only lint chain |

### Not executed

- No migration has run (no Docker/Supabase CLI).
- No RLS or SLA math test has run.
- Playwright browsers not installed; E2E not run.
- No Git repository, GitHub remote, Vercel project, email provider or domain.
  The owner has created one Supabase project, but it is not linked and no
  migration has been applied to it.
- No deployment URL exists.

## Decisions made during implementation

| Decision | Reason |
| --- | --- |
| No ORM; use Supabase client + SQL | Keeps RLS, constraints and transaction boundaries visible |
| No React Query | Server Components cover Phase 1; avoids duplicate cache |
| TypeScript 5.9.3 | Tooling compatibility; TS 7 not yet supported by all plugins |
| ESLint 10.14.0 | Avoid deprecated 9.x; accept temporary peer warnings |
| `"type": "module"` | Removes Vitest config-loading warning |
| Health via `@supabase/supabase-js` `.rpc('health')` | Works with legacy anon keys and new publishable keys |
| Customer reopen from `closed` | Matches approved reopen policy and UI flow |
| Precomputed SLA timestamps | Fast queue sorting without per-row business-hour math |
| Forward-only migrations | Predictable promotion; rollback by restore/forward fix |

## Next milestones

| Phase | Scope | Status |
| --- | --- | --- |
| Phase 2 | Auth screens, email verification, profiles, role provisioning, account-status enforcement | Not started |
| Phase 3 | Ticket create/list/detail, messages, attachments, customer portal | Not started |
| Phase 4 | Support console, assignment, status actions, internal notes | Not started |
| Phase 5 | SLA evaluator, cron, email dispatcher, escalation notifications | Not started |
| Phase 6 | Knowledgebase, CSAT, reporting, management viewer views | Not started |
| Phase 7 | Hardening, accessibility, load/security testing, launch | Not started |
| Phase 8 | .NET / Angular / SQL Server migration (if approved) | Not started |
