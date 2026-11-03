# Known Issues

Open defects, limitations and workarounds as of **2026-11-02**. Severity is
relative to a production launch. Anything not listed as **Verified** has not
been executed.

## 1. Blocking / High

| ID | Issue | Impact | Workaround / next step |
| --- | --- | --- | --- |
| KI-01 | **No migration has been executed.** No Docker, Supabase CLI or Supabase project was available on the build machine. | The schema, seeds, RLS and constraints are unverified. A migration may fail or behave differently on PostgreSQL 17. | Follow DEPLOYMENT_GUIDE B1–B4; run `supabase db reset` and the verification SQL in TEST_PLAN §5. |
| KI-02 | **No deployment exists.** One Supabase project has been created by the owner, but no GitHub repository, Vercel project, email provider or domain exists yet, and no migration has been applied. | There is no URL to test. A green local build is not a deployment. | Perform B2–B7; test `/api/health`, `/en`, `/ar` on the deployed URL before claiming success. |
| KI-03 | **No mutation RPCs.** `create_ticket`, `post_message`, `change_status`, `claim_ticket`, `resolve`, `reopen`, etc. do not exist. | No ticket can be created or changed through the application. Client grants are SELECT-only by design. | Implement RPCs in Phase 3/4 with `SECURITY DEFINER`, transition checks, audit + outbox in one transaction. |
| KI-04 | **No auth UI.** Registration, email verification screens, sign-in, sign-out, password reset and profile pages are not built. `/auth/callback` exists but no form initiates the flow. | Users cannot sign in through the app. | Phase 2. |
| KI-05 | **`profiles.account_status` is not enforced.** RLS and helpers do not check `active`. | A suspended or disabled user with a valid JWT can keep reading until the token expires. | Add an active-account predicate to helper functions/policies and revoke sessions on suspension (Phase 2). See SECURITY_REVIEW SR-01. |
| KI-06 | **Role exclusivity is not enforced in the database.** `user_roles` can hold `customer` plus a staff role. | A misconfigured account could have ambiguous permissions. | Add `set_user_roles` RPC or trigger that rejects mixed roles in one transaction (Phase 2). See SR-02. |

## 2. Medium

| ID | Issue | Impact | Workaround / next step |
| --- | --- | --- | --- |
| KI-07 | **No SLA evaluator or cron.** `ticket_sla_records`, `sla_events`, `escalations` and the escalation seed exist, but nothing advances states or sends notifications. | SLA targets and escalations are inert. No warning/breach behavior in production. | Implement `/api/cron/sla` (or Supabase `pg_cron`) in Phase 5 with idempotent dedupe keys. |
| KI-08 | **No email dispatcher.** `email_outbox` is a durable table only; no worker reads it. `RESEND_API_KEY`/`EMAIL_FROM` are unused. | No acknowledgement, reply, resolution or escalation emails. | Implement `/api/cron/email` and Resend integration in Phase 5. |
| KI-09 | **SLA policy selection is not implemented.** Scoped policies exist (priority/category/team), but no function resolves the most specific one. | Triage cannot compute deadlines automatically. | Implement `private.resolve_sla_policy(...)` with the documented precedence and tests. |
| KI-10 | **Attachments are not accessible.** The `attachments` bucket exists and is private, but no upload/download route exists and no `storage.objects` policy is defined. | Users cannot attach or retrieve files. | Build authorized upload/download routes, then add narrow storage policies. See SR-05. |
| KI-11 | **Management viewer has no reporting surface.** The role is intentionally not staff, so it cannot read tickets; no aggregate views exist. | The role can sign in but can do nothing useful. | Build de-identified aggregate reports in Phase 6. |
| KI-12 | **No rate limiting or bot protection.** | Public forms (once built) could be abused. | Add edge/Redis rate limits and bot protection before exposing signup/ticket creation. |
| KI-13 | **No OpenAPI document or versioned API.** | Integrations have no machine-readable contract. | Add `/api/v1` or an `Accept-Version` header and OpenAPI 3.1 before external consumers. |
| KI-14 | **Recurring holidays are not expanded.** `holidays.is_recurring` is stored, but `private.add_business_minutes` matches only the exact date. | Annual holidays must be inserted for every year or SLA deadlines will be wrong. | Implement recurrence expansion or document yearly seeding. |
| KI-15 | **Health `schema_version` is hardcoded.** It returns `0010` without checking `supabase_migrations` or a version table. | It can drift from the actual applied migration if a new migration is added. | Replace with a real migration lookup in Phase 5. |
| KI-16 | **No database tests in CI yet.** `supabase/tests/` is empty. The `database` CI job only proves migrations apply. | RLS and constraint regressions would go unnoticed. | Add pgTAP/SQL tests from TEST_PLAN §5. |
| KI-17 | **ESLint 10 peer-range warnings and 15 moderate dev advisories.** Some `eslint-config-next` plugins declare peer support up to ESLint 9. | Dev-only; `npm audit --omit=dev` is clean. Could break on a future plugin update. | Track upstream releases; align when plugins support ESLint 10. Do not "fix" by downgrading to a deprecated ESLint. |
| KI-18 | **Next.js build rewrites `tsconfig.json` `jsx` to `react-jsx`.** | A build can modify the working tree. | Accept the change and commit it (the automatic runtime is correct for Next.js). |
| KI-19 | **No CI run has occurred.** The repository is not on GitHub. | `ci.yml` and `migrations.yml` are unproven. | Push to GitHub and verify both workflows. |

## 3. Low

| ID | Issue | Impact | Workaround / next step |
| --- | --- | --- | --- |
| KI-20 | **No test for every seeded transition rule in TypeScript.** The domain mirror is tested for representative cases, not all 30 rows. | A seed/TS drift is possible. | Generate or hand-write a parity test that reads the expected table. |
| KI-21 | **No CSAT UI or KB UI.** Tables and RLS exist; no screens. | Features are not usable. | Phase 6. |
| KI-22 | **No organization sharing.** `organizations`/`customer_profiles` exist, but tickets are scoped to the individual customer. | Organizations cannot see each other's tickets. | Deferred by decision; revisit when required. |
| KI-23 | **Categories/teams/departments are not seeded.** They need business input. | Ticket creation cannot validate real categories yet. | Owner supplies the category tree and teams. |
| KI-24 | **No holiday list seeded.** | SLA deadlines ignore public holidays until rows are added. | Owner supplies official holidays per year. |
| KI-25 | **`audit_logs` is not automatically populated.** The table exists with an append-only trigger, but no application code or DB trigger writes entries yet. | No audit trail until RPCs write it. | Every mutation RPC must insert audit rows; add tests. |
| KI-26 | **No attachment deletion lifecycle.** Deleting a DB row does not remove the Storage object. | Orphaned objects and potential cost. | Add a cleanup job or delete objects in the same server flow. |
| KI-27 | **No data retention job.** | `audit_logs`, `email_outbox`, `notifications` grow without bounds. | Implement retention per DATA_DICTIONARY §8. |
| KI-28 | **No health check for outbox backlog or migration drift.** | Operational issues may go unnoticed. | Extend `/api/health` in Phase 5. |
| KI-29 | **No Playwright browser installed; E2E suite unexecuted.** | Locale/RTL regressions are not automatically caught. | `npx playwright install chromium` then `npm run test:e2e`. |
| KI-30 | **No accessibility automation.** | WCAG compliance is unverified. | Add axe checks per TEST_PLAN §7. |

## 4. Known non-issues (intentional)

- **Customers cannot choose priority.** Approved setting
  `customer_priority_selection=false`.
- **Customers cannot see internal notes.** Enforced by RLS, not component logic.
- **Management viewers cannot read tickets.** Intentional; aggregate reporting is
  a separate surface.
- **`email_outbox` has no policies.** Service-role only by design.
- **Migrations are forward-only.** No down scripts; rollback is restore or
  forward fix.
- **No ORM / no React Query.** Deliberate architecture decisions.

## 5. Verification statement

The following have **not** been verified and must not be described as working:

- Any SQL migration on PostgreSQL/Supabase
- Any RLS policy at runtime
- Any SLA calculation
- Any email delivery
- Any deployed URL
- Any Playwright test

The following **have** been executed successfully: `npm run typecheck`,
`npm run lint`, `npm test` (31 tests), `npx vitest run --coverage`,
`npm run build`, and `npm audit --omit=dev` (0 vulnerabilities). See
[TEST_RESULTS](TEST_RESULTS.md).
