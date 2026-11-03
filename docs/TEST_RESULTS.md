# Test Results

> **Run date:** 2026-11-02
> **Machine:** Windows, Node.js v24.22.0, npm 11.19.1
> **Repository state:** Phase 1 foundation, no Git repository initialized, no
> Supabase project linked, no deployment performed.

This document records what was **actually executed**. Anything not listed here
was not run. See [TEST_PLAN](TEST_PLAN.md) for the full intended surface.

## 1. Summary

| Gate | Command | Result |
| --- | --- | --- |
| TypeScript | `npm run typecheck` | **Pass** (no output) |
| ESLint | `npm run lint` | **Pass** (no output) |
| Unit tests | `npm test` | **Pass** — 4 files, 31 tests |
| Coverage | `npx vitest run --coverage` | **Pass** — 98.07% statements, 94.11% branches, 93.75% functions, 97.95% lines |
| Production build | `npm run build` | **Pass** — 5 routes generated |
| Dependency audit (runtime) | `npm audit --omit=dev` | **Pass** — 0 vulnerabilities |
| Dependency audit (full) | `npm audit` | **15 moderate** — dev-only lint chain, no runtime impact |
| Database migrations | `supabase db reset` | **Not executed** — no Docker/Supabase CLI on the machine |
| Schema verification queries | SQL in B4 | **Not executed** — no live project |
| RLS tests | `supabase/tests/` | **Not implemented / not executed** |
| Playwright E2E | `npm run test:e2e` | **Not executed** — browsers not installed |
| Deployed URL tested | manual | **Not done** — deployment is owner-performed |

## 2. Unit tests

Command:

```powershell
npm test
```

Output:

```text
> cts@0.1.0 test
> vitest run

 RUN  v5.0.5 E:/CTS-OpenCode

 Test Files  4 passed (4)
      Tests  31 passed (31)
   Start at  10:45:11
   Duration  2.84s
```

Coverage command:

```powershell
npx vitest run --coverage
```

Output summary:

```text
 Test Files  4 passed (4)
      Tests  31 passed (31)

 % Coverage report from v8
-------------------|---------|----------|---------|---------|
File               | % Stmts | % Branch | % Funcs | % Lines |
-------------------|---------|----------|---------|---------|
All files          |   98.07 |    94.11 |   93.75 |   97.95 |
 permissions.ts    |   93.33 |    66.66 |   85.71 |   92.85 |
-------------------|---------|----------|---------|---------|
Statements   : 98.07% ( 51/52 )
Branches     : 94.11% ( 32/34 )
Functions    : 93.75% ( 15/16 )
Lines        : 97.95% ( 48/49 )
```

Files executed:

- `tests/unit/ticket-status.test.ts`
- `tests/unit/permissions.test.ts`
- `tests/unit/ticket-reference.test.ts`
- `tests/unit/messages.test.ts`

New in this run:

- Localization parity test (`messages.test.ts`): EN and AR expose the same 28
  keys and no translation is empty.
- Customer reopen of a **closed** ticket (`closed → reopened`) asserted for parity
  with the database seed.
- Waiting/terminal helper assertions (`isAwaitingCustomer`,
  `isAwaitingInternal`, `isTerminal`).
- Explicit `max_reopens_reached` branch and missing-`resolved_at` branch.

## 3. Static checks

```powershell
npm run typecheck
npm run lint
```

Both exited with code 0 and produced no diagnostics.

## 4. Production build

Command:

```powershell
npm run build
```

Output (abridged):

```text
▲ Next.js 16.4.3 (Turbopack)
✓ Running next.config.ts took 129ms
✓ Compiled successfully in 13.0s
  Running TypeScript ...
  Finished TypeScript in 3.0s
✓ Generating static pages using 6 workers (5/5) in 777ms

Route (app)
┌ ○ /_not-found
├   /[locale]
│ ├ ● /en
│ └ ● /ar
├ ƒ /api/health
└ ƒ /auth/callback

ƒ Proxy (Middleware)
```

Notes:

- `/[locale]` is statically generated for `en` and `ar`.
- `/api/health` and `/auth/callback` are dynamic route handlers.
- Missing message keys fail the build (this happened once for
  `Footer.healthLink` and was fixed).

## 5. Dependency audit

```powershell
npm audit --omit=dev
```

```text
found 0 vulnerabilities
```

Full audit:

```powershell
npm audit
```

Result: **15 moderate** advisories, all in the development lint chain
(`eslint`, `@typescript-eslint/*`, `@eslint/*`, `minimatch`,
`@next/eslint-plugin-next`). They are not shipped in the runtime bundle. Cause:
ESLint 10.14.0 is newer than some transitive plugins' declared peer ranges
(`^9`). This is recorded in [KNOWN_ISSUES](KNOWN_ISSUES.md).

## 6. Not executed — database

**Reason:** Docker Desktop and the Supabase CLI are not installed on this
machine, and no Supabase project exists yet.

Consequences:

- None of the 10 migrations has ever run.
- The 37-table count, RLS coverage, seed counts, transition guard, SLA math,
  reference allocator and constraint behaviour are **unverified**.
- The `ci.yml` `database` job (clean `supabase db reset`) has not run because the
  repository is not on GitHub.
- The queries in [DATABASE_SCHEMA](DATABASE_SCHEMA.md) §14 are a checklist, not
  evidence.

To verify, follow [DEPLOYMENT_GUIDE](DEPLOYMENT_GUIDE.md) B1 → B4 and run the
SQL in [TEST_PLAN](TEST_PLAN.md) §5.

## 7. Not executed — Playwright E2E

**Reason:** Playwright browsers are not installed and no dev server was left
running for the suite.

The suite exists at `tests/e2e/landing.spec.ts` and covers:

1. `/en` → `lang=en`, `dir=ltr`, English H1, health link.
2. `/ar` → `lang=ar`, `dir=rtl`, Arabic H1.
3. Locale switcher `/en ↔ /ar` without leaving the page.
4. `/api/health` JSON shape and `200`/`503` status.

To run:

```powershell
npx playwright install chromium
npm run test:e2e
```

Expected on a fresh checkout without Supabase env: `/api/health` returns `503
unconfigured`; the test accepts `200` or `503`.

## 8. Not executed — deployment

No Vercel project, email provider or custom domain has been created. One
Supabase project exists (owner-created) but it is not linked and no migration
has been applied to it. No deployed URL has been opened. **Do not claim the
application is deployed.**

## 9. Environment and tooling facts

| Item | Value |
| --- | --- |
| OS | Windows |
| Node.js | v24.22.0 |
| npm | 11.19.1 |
| Next.js | 16.4.3 |
| React | 19.3.1 |
| TypeScript | 5.9.3 |
| Vitest | 5.0.5 |
| ESLint | 10.14.0 |
| Playwright | 1.64.1 (not run) |
| Docker | Not installed |
| Supabase CLI | Not installed |
| Git | Not initialized in this directory |

## 10. Reproduction

```powershell
cd E:\CTS-OpenCode
npm install
npm run typecheck
npm run lint
npm test
npx vitest run --coverage
npm run build
npm audit --omit=dev
```

Database and E2E reproduction requires the missing tooling described above.
