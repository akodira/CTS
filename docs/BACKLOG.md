# Backlog

Prioritized work after Phase 1. Each item lists acceptance criteria and missing
inputs. Nothing here is implemented unless stated. Business rules must be
approved before implementation; do not invent categories, teams, holidays or
SLA changes.

## Phase 2 — Authentication and profiles

| ID | Item | Acceptance criteria | Missing input / dependency |
| --- | --- | --- | --- |
| P2-01 | Registration page (EN/AR) | Customer can register with email/password; Zod validation; localized errors; verification email enqueued; no duplicate email | Email template copy; sender identity |
| P2-02 | Email verification flow | Verification link hits `/auth/callback`; verified state shown; unverified users cannot create tickets | None beyond Supabase Auth config |
| P2-03 | Sign-in / sign-out | Session established; redirect to locale-aware dashboard; sign-out clears session; no open redirect | Dashboard route design |
| P2-04 | Password reset | Request + callback + set new password; token single-use; localized emails | Email template copy |
| P2-05 | Profile page | View/edit `full_name`, `phone`, `locale`; RLS prevents editing others; updated_at maintained | Field-level policy (which fields editable) |
| P2-06 | Staff provisioning | Admin invites staff; invitation stored with hashed token; role granted on accept; auto-`customer` role removed | Invitation email copy; who approves staff |
| P2-07 | `set_user_roles` RPC | Rejects customer+staff mix; only `system_admin`; writes audit; transaction-safe | Confirm staff roles can be multiple (e.g. leader+admin?) |
| P2-08 | Enforce `account_status` | Suspended/disabled users cannot read via RLS/RPC; sessions revoked; tests | Decision: immediate revoke vs token expiry |
| P2-09 | Auth rate limiting | Per-IP/per-email limits on register/login/reset; localized throttle message | Provider choice (Vercel WAF/Upstash) |
| P2-10 | Auth E2E tests | Register → verify → sign in → sign out in EN and AR | Test email strategy |
| P2-11 | Account deletion request | Policy and flow documented; legal review; no destructive cascade of tickets | Legal/retention decision |

## Phase 3 — Customer ticket portal

| ID | Item | Acceptance criteria | Missing input / dependency |
| --- | --- | --- | --- |
| P3-01 | `create_ticket` RPC | Validates role/account, active category, required custom fields, allowed attachments; allocates reference; inserts ticket + first message + history + SLA clocks + audit + outbox in one transaction | Category tree; priority triage rule; SLA policy resolver |
| P3-02 | Ticket creation form | Bilingual, RTL, dynamic custom fields, attachment upload, server-side validation, no priority selector | Category tree; field definitions |
| P3-03 | Ticket list (customer) | Own tickets only; cursor pagination; status/SLA labels localized; empty/error states; no fake data | None |
| P3-04 | Ticket detail (customer) | Public messages only; internal notes never fetched; status timeline customer-visible; SLA summary; attachments authorized | None |
| P3-05 | Public reply | Customer can reply on own ticket; blocked on `closed`; `pending_customer → in_progress`; resumes SLA; audit/outbox | Confirm behavior on `resolved` (reply should reopen? define) |
| P3-06 | Attachments | Upload/download routes; MIME + size validation; private bucket; signed URL short TTL; max 5/message; orphan cleanup | Storage policies; malware scanning decision |
| P3-07 | Confirm resolution | Customer sets `customer_confirmed_at`, `resolved → closed`, writes history/audit | None |
| P3-08 | Reopen ticket | Enforces 7 days / 2 reopens / not confirmed; new SLA cycle; reason required; audit/outbox | Confirm calendar days vs business days (approved: calendar) |
| P3-09 | CSAT | One rating per ticket after resolution; 1–5 + optional comment; RLS own only | Survey timing/copy |
| P3-10 | Portal E2E | Create → reply → resolve → confirm/reopen in EN and AR | Test fixtures |
| P3-11 | Optimistic concurrency | Mutations accept `expected_version`; conflict shows reload message; tests | None |

## Phase 4 — Support console

| ID | Item | Acceptance criteria | Missing input / dependency |
| --- | --- | --- | --- |
| P4-01 | Queue/list for staff | Team/assignee/unassigned queue; filters; sorted by SLA risk; RLS-scoped; pagination | Team structure |
| P4-02 | Ticket detail (staff) | Public + internal messages; assignment history; status history; SLA clocks; audit link (admin) | None |
| P4-03 | Claim/assign/reassign | Team membership validated; one current assignment; history row; audit; leader/admin only for assign | Team membership rules |
| P4-04 | Internal notes | `visibility='internal'`; never in customer email; RLS-enforced; no first-response effect | None |
| P4-05 | Status actions | Transition rules enforced; reason required; history/audit/outbox; version check | None |
| P4-06 | Priority change | Staff permission; audit; current SLA target not rewritten; next cycle uses new policy | Confirm policy-change semantics |
| P4-07 | Resolve/close | Resolution summary required; `resolved_at`/`resolution_by`; close from resolved; auto-close not included | Resolution summary requirements/copy |
| P4-08 | Escalate manually | Leader/admin only; reason; escalation row; notifications/outbox | Escalation reason taxonomy |
| P4-09 | Search | Uses `search_vector`; RLS applies; bilingual query behavior documented | Search relevance expectations |
| P4-10 | Console E2E | Claim → reply → resolve → close; internal note invisible to customer | Test fixtures |

## Phase 5 — SLA, email and jobs

| ID | Item | Acceptance criteria | Missing input / dependency |
| --- | --- | --- | --- |
| P5-01 | `resolve_sla_policy` | Precedence implemented; newest effective; active only; tests | None (precedence approved in SLA doc) |
| P5-02 | SLA evaluator | Computes warning/breach on business-minute axis; idempotent; batch limit; advisory lock; updates `last_evaluated_at` | Cron strategy (Vercel Pro vs pg_cron) |
| P5-03 | Pause/resume | Pauses only `pending_customer`; shifts deadlines once; events; tests | None |
| P5-04 | Auto-close job | Closes `resolved` after 3 business days; system actor; no customer confirmation; idempotent | Holiday list |
| P5-05 | Escalation notifications | 75% → team_leader; 100% → system_admin; dedupe; notification + outbox | Team routing once teams exist |
| P5-06 | Email dispatcher | Reads outbox with `FOR UPDATE SKIP LOCKED`; retries with backoff; marks sent/failed; never logs payload secrets; idempotent | Resend account + verified domain |
| P5-07 | Email templates | Bilingual EN/AR; ticket reference; no internal content; unsubscribe/legal footer if required | Copy, branding, legal text |
| P5-08 | Webhook handling | Verify Resend signature; update delivery status; reject unsigned | Resend webhook secret |
| P5-09 | Health extension | Report migration version, outbox backlog, stale clocks | None |
| P5-10 | SLA/job tests | Duplicate runs create no duplicates; boundary tests pass; calendar tests pass | Holiday list |
| P5-11 | Cron routes secured | `CRON_SECRET` required; 401 otherwise; no secret in logs | None |

## Phase 6 — Knowledgebase, reporting and management viewer

| ID | Item | Acceptance criteria | Missing input / dependency |
| --- | --- | --- | --- |
| P6-01 | KB public browsing | Published public articles visible to anon; bilingual; search | Content plan |
| P6-02 | KB authoring | Admin CRUD; draft/published/archived; audit | Authoring workflow |
| P6-03 | KB feedback | Authenticated helpful/unhelpful + comment; one per user | None |
| P6-04 | Reporting views/RPCs | Aggregate, de-identified for `management_viewer`; no ticket content; tested | Metric definitions (see below) |
| P6-05 | Team/department reports | Leader sees own team; admin all; export permission | Org structure |
| P6-06 | CSAT reporting | Aggregated by team/priority/period | None |
| P6-07 | Report export | CSV/Excel with permission checks; no PII beyond approved scope | Export format/fields |
| P6-08 | Dashboards | Real data only; no hardcoded stats; empty states | KPI definitions |

### Reporting metric inputs needed

- First-response compliance definition (completed before `due_at` / all).
- Resolution compliance definition.
- Whether paused time is excluded (yes) and how it is displayed.
- Reopen rate denominator.
- CSAT response rate.
- Time zone and date-range defaults.
- Which roles see which dimensions (team, agent, priority, category).

## Phase 7 — Hardening and launch

| ID | Item | Acceptance criteria |
| --- | --- | --- |
| P7-01 | Full RLS test suite | All TEST_PLAN §5.4 cases pass in CI |
| P7-02 | Accessibility audit | No critical/serious axe issues; keyboard/focus/contrast verified EN/AR |
| P7-03 | Load test | Define target throughput; p95 acceptable; no N+1 queries; SLA job bounded |
| P7-04 | Security review sign-off | No open High findings; threat model updated; pen-test if required |
| P7-05 | Backup/restore drill | Restore tested in staging; RTO/RPO documented |
| P7-06 | Monitoring/alerts | Health, error rate, outbox backlog, SLA job freshness, DB connections |
| P7-07 | Runbooks | Incident, rollback, key rotation, migration failure |
| P7-08 | Legal/privacy | Retention, deletion, PII, terms/privacy pages approved |
| P7-09 | Production checklist | All gates in SECURITY_REVIEW §4 complete |

## Phase 8 — .NET / Angular / SQL Server (optional)

| ID | Item | Acceptance criteria |
| --- | --- | --- |
| P8-01 | Migration design | Mapping approved; no production cutover without a rollback plan |
| P8-02 | Schema conversion | SQL Server schema with equivalent constraints/indexes |
| P8-03 | Data migration | Counts/FKs validated; no data loss; PII handled |
| P8-04 | API parity | Contract tests pass against both implementations |
| P8-05 | UI parity | Bilingual/RTL parity; accessibility parity |
| P8-06 | Auth migration | Users can sign in; roles preserved; MFA strategy |
| P8-07 | Parallel run | Read-only comparison; discrepancy report |
| P8-08 | Cutover/rollback | DNS switch, health checks, rollback window |

## Missing business inputs (blockers for later phases)

| Input | Needed for | Status |
| --- | --- | --- |
| Category tree (EN/AR codes, parent/child) | Ticket creation, triage, SLA scoping | **Not provided** |
| Departments and teams (codes, names, members) | Assignment, queue, escalation routing | **Not provided** |
| Priority/triage rule | Server-side priority assignment | **Not provided** |
| Official holiday list by year | SLA deadlines, auto-close | **Not provided** |
| Branding (logo, colors, copy) | UI polish, emails | **Not provided** |
| Email sender/domain and templates | Verification, notifications | **Not provided** |
| Legal/privacy text and retention policy | Registration, launch | **Not provided** |
| Management reporting metrics | Phase 6 dashboards | **Not provided** |
| Staff invitation approval flow | Phase 2 provisioning | **Not provided** |
| Vercel plan choice (Hobby vs Pro) | SLA cron frequency | **Not decided** |
| Malware scanning policy for attachments | Upload route | **Not decided** |
| Organization sharing requirements | Ticket scoping | **Deferred** |

## Definition of done (every item)

1. Implemented server-side with authorization re-checked (never UI-only).
2. RLS/RPC tests added and passing.
3. EN and AR (including RTL) verified.
4. Error/empty/loading states implemented; no dead buttons.
5. Audit/outbox side effects written where applicable.
6. Documentation updated in the same change.
7. `typecheck`, `lint`, `test`, `build` pass; TEST_RESULTS updated.
