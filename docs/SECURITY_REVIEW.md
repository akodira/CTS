# Security Review

> Phase 1 scope. This review covers what exists today and lists open findings before going live. Items marked **Open** are gaps; items marked **Acceptable for Phase 1** are acknowledged limitations.

## 1. Threat model summary

| Asset | Threat | Impact | Likelihood | Mitigation |
| --- | --- | --- | --- | --- |
| User PII (emails, names) | Data exfiltration via RLS bypass | High | Low | RLS on all tables, `SECURITY DEFINER` with `search_path=''`, session JWT validation, no direct inserts from browser |
| Ticket content | Cross-tenant/role leakage | High | Medium | `private.can_view_ticket` enforces customer/team/assignee/admin; internal messages filtered by `visibility` + RLS |
| Service role key | Exposure in client bundle/logs | Critical | Low | `server-only` on admin client, never prefixed `NEXT_PUBLIC_`, logged as redacted, rotated on exposure |
| Attachments | Unauthorized download | High | Medium | Private bucket, no storage policies yet, downloads planned through authorized route with signed URLs |
| Auth tokens/cookies | Session hijack | High | Low | HttpOnly cookies via `@supabase/ssr`, PKCE callback, session refresh in proxy, HTTPS in prod |
| SLA/email spam | Duplicate dispatch | Medium | Medium | `dedupe_key` on outbox/events/escalations, idempotent cron handlers (planned) |
| Migration abuse | Schema drift/destructive changes | High | Low | Forward-only migrations, CI resets DB, manual prod promotion with environment protection |

## 2. Controls assessment

### Authentication & sessions
| Control | Status | Notes |
| --- | --- | --- |
| Supabase Auth (GoTrue) | Implemented | Email-based auth path prepared |
| PKCE callback at `/auth/callback` | Implemented | Validates relative `next`, exchanges code server-side |
| Session refresh in `src/proxy.ts` | Implemented | Uses `getUser()`-style refresh via Supabase SSR proxy helper |
| Middleware/proxy excludes API/auth/static | Implemented | Prevents locale/session logic from running on route handlers/assets |
| Account status check | **Open** | `profiles.account_status` exists but is not enforced by RLS or RPCs yet (Phase 2) |
| MFA | **Open** | Not configured; consider for admins in production |

### Authorization
| Control | Status | Notes |
| --- | --- | --- |
| RLS enabled on all 37 public tables | Implemented | Verified by schema |
| Helper functions with `security definer` + `search_path=''` | Implemented | Revoked from public, granted to authenticated where needed |
| RPC-centric writes (planned) | **Planned** | No mutation RPCs yet; clients have SELECT grants only |
| Role exclusivity (customer vs staff) | **Open** | DB allows; domain helper `isRoleCombinationAllowed` exists but not enforced by trigger/RPC |
| Management viewer ticket access | **Open (by design)** | Cannot read tickets; aggregate views needed in Phase 6 |
| `email_outbox` service-role only | Implemented | RLS enabled, no policies/grants, SELECT/INSERT/UPDATE/DELETE not granted to authenticated/anon |

### Data protection
| Control | Status | Notes |
| --- | --- | --- |
| Secrets in env, not in git | Implemented | `.env*` gitignored, `.env.example` has placeholders |
| `server-only` on admin/env/logger | Implemented | Prevents accidental client import |
| Pino redaction | Implemented | Headers/cookies/tokens/email/phone/body/message redacted |
| `audit_logs` append-only | Implemented | Trigger blocks UPDATE/DELETE |
| Sensitive columns not exposed | Implemented | No public API returning secrets; health endpoint is safe |
| TLS/HSTS | Implemented | HSTS header set in Next config |

### Input validation & business logic
| Control | Status | Notes |
| --- | --- | --- |
| Zod env validation | Implemented | Public and server schemas |
| Domain rules in pure modules | Implemented | Ticket status/reopen/permissions mirrored with tests |
| DB constraints (enums, checks, FKs) | Implemented | Cover many invariants |
| Transition rules in DB | Implemented | 30 rules seeded |
| Form validation | **Planned** | No forms yet (Phase 2+) |
| File upload validation | **Planned** | Bucket allow-list exists; server validation needed |

### Infrastructure
| Control | Status | Notes |
| --- | --- | --- |
| Security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, HSTS) | Implemented | Set on all routes |
| Powered-by header removed | Implemented | `poweredByHeader: false` |
| CORS same-origin only | Acceptable | No wildcard configured; Next handles same-origin by default |
| CI quality gates | Implemented | typecheck/lint/test/build + DB migration reset |
| Migration promotion workflow | Implemented | Manual with environment protection |
| Dependency audit | Monitored | `npm audit --omit=dev` shows 0 vulnerabilities; full audit shows 15 moderate dev-only advisories in lint chain |

## 3. Open findings

| ID | Severity | Finding | Impact | Recommendation | Phase |
| --- | --- | --- | --- | --- | --- |
| SR-01 | High | `profiles.account_status` not enforced | Suspended/disabled users with valid JWT remain authorized until token expiry | Enforce in RLS policies (check `account_status='active'`) or add to all RPCs; revoke sessions on suspension | Phase 2 |
| SR-02 | High | Role exclusivity not enforced | A user could hold both `customer` and staff roles (DB allows) | Add trigger/RPC `set_user_roles` that rejects mixed roles in one transaction; audit all role grants | Phase 2 |
| SR-03 | High | No mutation RPCs yet | Writes go through client directly only if grants change; currently SELECT-only, but design requires RPCs | Implement RPCs with `SECURITY DEFINER`, transition checks, audit/outbox in same transaction before exposing UI | Phase 3/4 |
| SR-04 | Medium | Management viewer cannot read tickets by design | Role exists but unusable for reporting | Build aggregate read-only views/RPCs with de-identified data; never expose ticket content to this role | Phase 6 |
| SR-05 | Medium | Storage bucket has no policies | Attachments cannot be accessed but also no guardrails exist yet | Implement upload/download routes with authorization checks before enabling uploads; add storage policies when routes exist | Phase 3 |
| SR-06 | Medium | No rate limiting | Signup/ticket creation/upload could be abused | Add per-IP and per-account limits at edge (Vercel WAF/Upstash) before public forms | Phase 2/3 |
| SR-07 | Medium | No cron routes implemented | SLA escalation/email dispatch cannot run | Implement `/api/cron/*` with `CRON_SECRET`, idempotency, advisory locks, batch limits | Phase 5 |
| SR-07b | Medium | ESLint 10 peer dependency warnings | Dev-only, no runtime impact | Monitor upstream updates; suppress warnings or align versions when stable | Ongoing |
| SR-08 | Low | Recurring holidays not expanded | `is_recurring` flag exists but calculator only matches exact dates | Implement recurring holiday expansion (e.g. annual) or require yearly seeding; document requirement | Phase 5 |
| SR-09 | Low | Policy selection function not implemented | Scoped policies exist in schema but no resolver | Implement `private.resolve_sla_policy(...)` with precedence + tests before enabling UI triage | Phase 4/5 |

## 4. Pre-launch gates

Before going to production with user-facing features:

| Gate | Status | Verification |
| --- | --- | --- |
| All migrations applied and verified | **Not done** | Run verification queries in B4 |
| RLS tests pass for all roles | **Not done** | Execute SQL tests per TEST_PLAN |
| Mutation RPCs implemented with audit/outbox | **Not done** | Code review + tests |
| Account status enforcement | **Not done** | Add policy/RPC checks |
| Role exclusivity enforced | **Not done** | Trigger/RPC + tests |
| Attachments secured (routes + policies) | **Not done** | Authorization tests |
| Cron secured and idempotent | **Not done** | Tests with duplicate runs |
| Secrets rotated/secured, env vars per environment | **Pending owner action** | Checklist in DEPLOYMENT_GUIDE |
| E2E smoke tests pass against staging | **Not done** | Playwright after install |
| Security headers verified | **Done** | Checked in next.config.ts |
| `npm audit --omit=dev` clean | **Done** | 0 vulnerabilities |
| Branch protections and environments configured | **Pending owner action** | GitHub settings |

## 5. Incident response notes

- **Key exposure**: Rotate `SUPABASE_SERVICE_ROLE_KEY` immediately, invalidate sessions if needed, review audit logs, check outbox for unauthorized sends.
- **Data leak suspicion**: Review RLS policies, check `audit_logs`, identify affected tickets/users, disable affected accounts, notify as required.
- **Migration failure**: Do not force; use PITR/backup restore or forward fix. Never edit applied migrations.
- **Abuse/spam**: Enable rate limiting, review `email_outbox` backlog, block IPs at edge if needed.

## 6. Compliance notes

- Data is stored in Supabase (Postgres). Data residency depends on project region selection.
- Ticket history is business record data; deletion restrictions apply (see DATABASE_RELATIONSHIPS).
- Audit log is append-only.
- No third-party analytics/tracking included.
- PII handling: minimize, redact in logs, only collect what's needed.
