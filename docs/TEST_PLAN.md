# Test Plan

> This plan describes the full intended test surface for CTS. Phase 1 ships a
> small executable subset. Anything not listed as **Executed** in
> [TEST_RESULTS](TEST_RESULTS.md) has **not** been run.

## 1. Objectives

1. Prove the bilingual shell renders correctly in English (LTR) and Arabic (RTL).
2. Prove business rules in the domain layer match the database seeds.
3. Prove PostgreSQL RLS prevents cross-role and cross-tenant reads.
4. Prove every mutation RPC enforces role, ownership, transition and concurrency rules.
5. Prove SLA calculations respect business calendars, holidays and pauses.
6. Prove email/SLA cron jobs are idempotent and do not duplicate side effects.
7. Prove secrets, service-role clients and internal messages never reach the browser.

## 2. Layers

| Layer | Tool | Location | Current state |
| --- | --- | --- | --- |
| Unit (domain) | Vitest | `tests/unit/**/*.test.ts` | Implemented, 4 files, 31 tests |
| Database / RLS | Supabase CLI + SQL | `supabase/tests/` (empty) | Not implemented |
| E2E browser | Playwright | `tests/e2e/landing.spec.ts` | Written, not executed |
| Accessibility | Playwright + axe (planned) | `tests/e2e/` | Not implemented |
| Security | Manual + SQL + dependency audit | — | Partially executed (audit) |
| Build/type/lint | npm scripts | repo root | Executed |

## 3. Commands

```powershell
# Static + unit gates
npm run typecheck
npm run lint
npm test
npx vitest run --coverage
npm run build

# Database (requires Docker Desktop + Supabase CLI)
supabase start
supabase db reset
# then run SQL tests from supabase/tests via psql or the SQL editor

# E2E (requires browser install)
npx playwright install chromium
npm run test:e2e
```

## 4. Unit test coverage

### 4.1 Ticket status (`tests/unit/ticket-status.test.ts`)

| Case | Expected |
| --- | --- |
| Every status has a transition list | Defined |
| Transitions reference known statuses only | Pass |
| No self-transition | Rejected |
| `resolved → closed` and `resolved → reopened` allowed | True |
| `closed → resolved` rejected | False |
| Customer cannot move `new → closed` | Rejected |
| Active vs terminal classification | Correct |
| Reopen allowed within 7 days, 0 reopens, not confirmed | `ok` |
| Reconfirmed ticket rejected | `already_confirmed` |
| Past window rejected | `window_expired` |
| Max reopens reached rejected | `max_reopens_reached` |
| Open ticket rejected | `not_resolved` |
| Customer can reopen `closed` ticket (`closed → reopened`) | True (added for parity with seed) |

### 4.2 Permissions (`tests/unit/permissions.test.ts`)

- Every role is recognized; unknown strings are rejected.
- Staff role classification includes agent/leader/admin, excludes customer/viewer.
- Representative permission checks per role (create, view, assign, close, admin).
- `permissionsForRole` returns stable sets.
- Mixed customer + staff roles are rejected.
- Duplicate roles are rejected.

### 4.3 Ticket reference (`tests/unit/ticket-reference.test.ts`)

- `CTS-YYYY-NNNNNN` formatting.
- Zero padding, valid years, rejects malformed input.

### 4.4 Localization (`tests/unit/messages.test.ts`)

| Case | Expected |
| --- | --- |
| EN and AR expose the same key set | 28 keys each, exact match |
| No empty or whitespace-only translation | Rejected |

### 4.5 Required additions (not yet written)

- Domain tests mirroring each of the 30 seeded transition rules, including role restrictions.
- Reopen boundary tests (exactly 7 days, exactly max reopens).
- Permission matrix snapshot test comparing TS constants with the documented table.
- SLA business-minute calculator tests after it is implemented in TypeScript (or DB tests).

## 5. Database and RLS tests (planned, `supabase/tests/`)

Use `pgTAP` or plain SQL assertion scripts run after `supabase db reset`. Create test users in `auth.users`/`profiles`/`user_roles`/`team_members` inside a transaction, then `set role authenticated` and `set request.jwt.claims` to impersonate.

### 5.1 Schema integrity

| # | Assertion |
| --- | --- |
| D1 | `pg_tables` reports 37 public tables |
| D2 | Every public table has `relrowsecurity = true` |
| D3 | Seeded roles = 5, priorities = 4, transitions = 30, policies = 5 |
| D4 | Exactly one active default SLA policy |
| D5 | Calendar has 5 intervals (Sun–Thu) |
| D6 | Escalation rules = 10 (2 per policy) |
| D7 | `audit_logs` rejects UPDATE/DELETE |
| D8 | Category depth trigger rejects depth > 2 and self-parenting |
| D9 | `ticket_assignments` partial unique index rejects two open assignments |
| D10 | `ticket_messages` check rejects non-system message without author |

### 5.2 Reference allocator

| # | Assertion |
| --- | --- |
| A1 | First call for a year returns `CTS-YYYY-000001` |
| A2 | Sequential calls increment |
| A3 | Concurrent transactions never return the same sequence |
| A4 | Rollback leaves a gap (allowed) but no duplicate |
| A5 | Year < 2000 or > 9999 raises |
| A6 | Sequence > 999999 raises |

### 5.3 SLA math

| # | Assertion |
| --- | --- |
| S1 | 15 business minutes from Sunday 08:05 = Sunday 08:20 |
| S2 | Thursday 16:30 + 60 = Sunday 08:30 |
| S3 | 1,440 business minutes from Sunday 08:00 = Tuesday 14:00 |
| S4 | 2,880 business minutes from Sunday 08:00 = next Sunday 11:00 |
| S5 | Holiday is skipped |
| S6 | Friday/Saturday are skipped |
| S7 | 24/7 calendar ignores intervals/holidays |
| S8 | Zero/negative minutes returns start |
| S9 | Missing calendar raises `BUSINESS_CALENDAR_NOT_FOUND` |

### 5.4 RLS matrix

For each row, test `SELECT` visibility with `set role authenticated` and JWT claims for the given user.

| # | Actor | Target | Expected |
| --- | --- | --- | --- |
| R1 | Customer A | Own ticket | Visible |
| R2 | Customer A | Customer B ticket | Hidden |
| R3 | Customer A | Internal message on own ticket | Hidden |
| R4 | Customer A | Public message on own ticket | Visible |
| R5 | Customer A | Other customer's message | Hidden |
| R6 | Support agent (team member) | Team ticket | Visible |
| R7 | Support agent | Other team ticket | Hidden |
| R8 | Support agent | Unassigned `team_id is null` ticket | Visible (queue rule) |
| R9 | Team leader | Team tickets, internal messages | Visible |
| R10 | Admin | All tickets/messages/audit | Visible |
| R11 | Management viewer | Any ticket | Hidden |
| R12 | Any user | `email_outbox` | No access (no grant) |
| R13 | Customer | Other profile | Hidden |
| R14 | Staff | All profiles | Visible |
| R15 | Customer | Internal-visibility custom field value | Hidden |
| R16 | Anon | Published public KB article | Visible |
| R17 | Anon | Draft/staff KB article | Hidden |
| R18 | Customer | Draft attachment owned by them | Visible |
| R19 | Customer | Draft attachment owned by another | Hidden |
| R20 | Customer | Internal linked attachment | Hidden |

### 5.5 Transition guard

| # | Assertion |
| --- | --- |
| T1 | Every seeded transition is accepted for each allowed role |
| T2 | Unknown pairs raise `INVALID_STATUS_TRANSITION` |
| T3 | Role not in `allowed_roles` raises `STATUS_TRANSITION_FORBIDDEN` |
| T4 | `requires_reason` transitions reject empty reason (RPC-level) |
| T5 | `customer_allowed=false` blocks the customer RPC path |

## 6. E2E tests

### 6.1 Public shell (`tests/e2e/landing.spec.ts`)

| # | Case | Status |
| --- | --- | --- |
| E1 | `/en` renders `lang=en`, `dir=ltr`, H1 | Written |
| E2 | `/ar` renders `lang=ar`, `dir=rtl`, Arabic H1 | Written |
| E3 | Locale switcher toggles `/en ↔ /ar` | Written |
| E4 | `/api/health` returns JSON with `status`, `checks` (200 or 503) | Written |
| E5 | Unknown route returns 404 | Not written |
| E6 | Header/footer links resolve and are not dead | Partially (health link only) |

### 6.2 Phase 2+ (planned)

- Register → verify email → sign in → sign out.
- Password reset callback.
- Profile edit in both locales.
- Role-based redirect after sign-in.

### 6.3 Phase 3+ (planned)

- Create ticket with required custom fields.
- Upload allowed and rejected attachment types/sizes.
- Post public reply and verify internal note invisibility for customer.
- Status lifecycle: open → in progress → pending customer → resolved → reopened → closed.
- Customer confirmation and reopen within/after window.
- Optimistic concurrency conflict handling.

### 6.4 Phase 5+ (planned)

- SLA warning/breach transitions after simulated clock advancement.
- Duplicate cron invocation does not duplicate email/escalation.
- Email outbox retry/backoff.

## 7. Accessibility

Planned with Playwright + `@axe-core/playwright`:

- No critical/serious axe violations on `/en` and `/ar`.
- Keyboard-only navigation reaches skip link, header, locale switcher, main content.
- Focus ring visible on all interactive elements.
- Arabic page announces correct language/direction.
- Color contrast meets WCAG AA for text and controls.
- Reduced-motion preference respected.

## 8. Security tests

| # | Case |
| --- | --- |
| S1 | Service-role key absent from all client bundles (`grep` built assets) |
| S2 | `.env*` not tracked by git |
| S3 | `/api/health` does not reveal secrets or row data |
| S4 | Auth callback rejects absolute/protocol-relative `next` values |
| S5 | Direct `INSERT`/`UPDATE` on tickets fails for authenticated role |
| S6 | Internal messages cannot be fetched via PostgREST filters for a customer |
| S7 | RLS prevents UUID guessing attacks (all R-matrix cases) |
| S8 | `npm audit --omit=dev` reports 0 vulnerabilities |
| S9 | Security headers present on deployed responses |
| S10 | Cron routes reject missing/incorrect `CRON_SECRET` (Phase 5) |

## 9. Localization tests

| # | Case | Status |
| --- | --- | --- |
| L1 | Every key in `messages/en.json` exists in `messages/ar.json` and vice versa | **Executed** — `tests/unit/messages.test.ts` (28 keys each, no empties) |
| L2 | No hardcoded English strings in components (review) | Manual review only |
| L3 | Dates/numbers use `next-intl` formatters, not `toLocaleString` with hardcoded locale | Manual review only |
| L4 | RTL layout uses logical properties; no fixed `left`/`right` where direction matters | Visual check only |
| L5 | Build fails on missing message keys | Verified indirectly by build |

## 10. CI gates

`ci.yml` runs: `npm ci`, typecheck, lint, unit tests, build, and a clean Supabase `db reset`. A PR should not merge if any job fails. The database job is currently the only automated execution of the migrations; it has not run yet because the repo is not on GitHub.

## 11. Exit criteria for Phase 1 sign-off

- [x] Typecheck, lint, unit tests, build pass locally
- [x] Unit test coverage of domain modules documented
- [ ] All migrations apply cleanly on a clean Supabase instance
- [ ] Schema verification queries pass
- [ ] At least the E2E smoke suite passes against a running app
- [ ] No open High findings in [SECURITY_REVIEW](SECURITY_REVIEW.md) that block the phase
- [ ] Documentation matches implementation
