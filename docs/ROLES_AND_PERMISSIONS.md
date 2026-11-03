# Roles and Permissions

Authorization exists at three layers. A permission shown here is not a promise
that a screen or RPC exists yet; it defines the intended rule that the UI, the
server action and PostgreSQL must all enforce consistently.

1. **UI affordance** — hide actions the role cannot perform.
2. **Server action / route handler / RPC** — reject unauthorized calls.
3. **PostgreSQL RLS and grants** — the final authority for reads and writes.

> The TypeScript matrix in `src/domain/permissions.ts` mirrors the table below.
> If you change one, change both and add a unit test.

## 1. Roles

| Code | Display (EN / AR) | Purpose | Default? |
| --- | --- | --- | --- |
| `customer` | Customer / عميل | External requester. Creates tickets, replies publicly, confirms resolution, reopens within policy. | Yes — auto-granted on signup |
| `support_agent` | Support Agent / موظف دعم | Works assigned/team tickets, replies, internal notes, resolves. | No |
| `team_leader` | Team Leader / قائد فريق | Assigns/reassigns, escalates, closes, monitors team reports. | No |
| `system_admin` | System Administrator / مدير النظام | Full operational and configuration access, including users, SLA, audit. | No |
| `management_viewer` | Management Viewer / مراقب إداري | Read-only aggregate reporting. No ticket content access by default. | No |

Roles are additive in the database (`user_roles` is many-to-many), but the
application forbids mixing `customer` with any staff role. A user is either an
external customer or an employee.

## 2. Permission matrix

`✓` = allowed. Blank = denied.

| Permission | customer | support_agent | team_leader | system_admin | management_viewer |
| --- | :---: | :---: | :---: | :---: | :---: |
| `ticket.create` | ✓ | | | | |
| `ticket.view.own` | ✓ | | | | |
| `ticket.view.team` | | ✓ | ✓ | ✓ | |
| `ticket.view.all` | | | | ✓ | |
| `ticket.reply.public` | ✓ | ✓ | ✓ | ✓ | |
| `ticket.note.internal` | | ✓ | ✓ | ✓ | |
| `ticket.claim` | | ✓ | ✓ | ✓ | |
| `ticket.assign` | | | ✓ | ✓ | |
| `ticket.reassign` | | | ✓ | ✓ | |
| `ticket.status.change` | | ✓ | ✓ | ✓ | |
| `ticket.priority.change` | | ✓ | ✓ | ✓ | |
| `ticket.escalate` | | | ✓ | ✓ | |
| `ticket.resolve` | | ✓ | ✓ | ✓ | |
| `ticket.close` | | | ✓ | ✓ | |
| `ticket.confirm_resolution` | ✓ | | | | |
| `ticket.reopen.own` | ✓ | | | | |
| `feedback.submit` | ✓ | | | | |
| `admin.users` | | | | ✓ | |
| `admin.teams` | | | | ✓ | |
| `admin.catalog` | | | | ✓ | |
| `admin.sla` | | | | ✓ | |
| `admin.kb` | | | | ✓ | |
| `admin.settings` | | | | ✓ | |
| `report.view.own` | | ✓ | | | |
| `report.view.team` | | | ✓ | ✓ | |
| `report.view.all` | | | | ✓ | ✓ |
| `report.export` | | | ✓ | ✓ | ✓ |
| `audit.view` | | | | ✓ | |
| `attachment.upload` | ✓ | ✓ | ✓ | ✓ | |
| `attachment.download` | ✓ | ✓ | ✓ | ✓ | |

Design notes:

- Customers cannot choose priority; the setting
  `customer_priority_selection=false` and the matrix enforce this. Priority is
  set/triaged by staff.
- A support agent cannot assign or close. Closing is a team-leader/admin action
  (or an automated auto-close job), which keeps quality control explicit.
- `ticket.reply.public` includes customers because a reply on their own ticket
  is allowed; the RPC must still verify ticket ownership.
- `management_viewer` has no ticket-content permission. Its reports must use
  aggregate, de-identified views/RPCs built in Phase 6. Until then, this role can
  sign in but has no reporting surface.
- `ticket.reopen.own` is bounded by the reopen policy (7 days, max 2, not after
  confirmation), not just by role.

## 3. What RLS actually allows today

RLS policies were written in `20261101000008_functions_and_rls.sql`. No ticket mutation
RPCs exist yet, so the practical surface is read-only.

| Data | Customer | Support agent | Team leader | Admin | Management viewer |
| --- | --- | --- | --- | --- | --- |
| Own profile | ✓ | ✓ | ✓ | ✓ | ✓ |
| All profiles | | ✓ (is_staff) | ✓ | ✓ | |
| Own roles | ✓ | ✓ | ✓ | ✓ | ✓ |
| All roles/grants | | | | ✓ | |
| Own tickets | ✓ | ✓ if assignee/team/unassigned queue | ✓ if team | ✓ | |
| Internal messages | | ✓ on visible tickets | ✓ | ✓ | |
| Status history | customer-visible only | visible tickets | visible tickets | ✓ | |
| Teams/departments/members | | ✓ | ✓ | ✓ | |
| Categories/priorities | active only | all | all | all | |
| Custom fields | customer-visible | all | all | all | |
| SLA policies/clocks | | visible tickets | visible tickets | ✓ | |
| Audit/settings | | | | ✓ | |
| Published public KB | anon + ✓ | ✓ | ✓ | ✓ | ✓ |
| Unpublished/staff KB | | ✓ | ✓ | ✓ | |
| CSAT own | ✓ | | | ✓ | |

The helper `private.is_staff()` is true for `support_agent`, `team_leader` and
`system_admin`. `management_viewer` is deliberately **not** staff, so it cannot
read tickets through the generic policies.

### Read scope for staff tickets

`private.can_view_ticket(ticket_id)` returns true when any of these hold:

- the ticket belongs to the current user as `customer_id`;
- the user is `system_admin`;
- the user is staff **and** one of:
  - `tickets.assignee_id = auth.uid()`;
  - the user is an active member of `tickets.team_id`;
  - the ticket has no team and the user is a `support_agent` (unassigned queue).

`private.can_manage_ticket` is narrower: admin, current assignee, or an active
**leader** of the ticket's team. It does not include ordinary team agents.

## 4. Role assignment rules

1. Every `auth.users` insert triggers `handle_new_user()`:
   - creates `profiles`;
   - grants `customer`;
   - creates `customer_profiles`.
2. Staff provisioning must:
   - create/invite the auth user;
   - **remove** the auto-granted `customer` role;
   - grant exactly one staff role;
   - optionally add an active `team_members` row.
3. The database does not yet enforce step 2's exclusivity. A future
   `set_user_roles` RPC must reject customer+staff combinations in one
   transaction. This is a known gap (see [KNOWN_ISSUES](KNOWN_ISSUES.md)).
4. Only `system_admin` may grant roles (`admin.users`). Team leaders cannot
   promote users.
5. `granted_by` records the administrator. Do not delete staff profiles that
   granted roles; the FK restricts it. Deactivate instead
   (`profiles.account_status='disabled'`).
6. `account_status` is **not yet checked by RLS**. A suspended user with a valid
   JWT can still read until the token expires. Phase 2 must add an active-account
   check to policies or revoke sessions on suspension.

## 5. Enforcement in future RPCs

Every ticket mutation RPC must perform, in this order:

```text
1. auth.uid() is not null
2. profile.account_status = 'active'
3. required role is held (or ownership check for customers)
4. ticket is visible/manageable by the actor
5. transition exists in ticket_transition_rules
6. transition allows the actor's role
7. reason supplied when requires_reason
8. domain preconditions (resolution summary, reopen window, version match)
9. write ticket + history + audit + outbox in one transaction
```

Suggested RPC-to-permission map (planned):

| RPC | Permission |
| --- | --- |
| `create_ticket` | `ticket.create` |
| `post_message` (public) | `ticket.reply.public` + ticket access |
| `post_internal_note` | `ticket.note.internal` |
| `claim_ticket` | `ticket.claim` |
| `assign_ticket` / `reassign_ticket` | `ticket.assign` / `ticket.reassign` |
| `change_ticket_status` | `ticket.status.change` + transition rule |
| `change_ticket_priority` | `ticket.priority.change` |
| `escalate_ticket` | `ticket.escalate` |
| `resolve_ticket` | `ticket.resolve` + summary |
| `close_ticket` | `ticket.close` |
| `confirm_resolution` | `ticket.confirm_resolution` + ownership |
| `reopen_ticket` | `ticket.reopen.own` + policy |
| `submit_feedback` | `feedback.submit` + ownership |
| `set_user_roles` | `admin.users` + exclusivity |
| `update_sla_policy` | `admin.sla` |

## 6. Separation of duties

- Agents cannot assign themselves work outside their team by changing
  `team_id`; assignment RPCs must validate team membership.
- Team leaders can assign within their team, not across teams, unless admin.
- Admins configure SLA but should not silently change an active policy without
  versioning. Historical clocks snapshot `target_minutes`, so edits do not
  rewrite the past.
- Audit logs are append-only, including for admins.
- The service-role key is not a role. It bypasses RLS and must never be used to
  serve a user request that could be served with the user's session.

## 7. Testing requirements

For every role, test at minimum:

1. Can read the rows the matrix allows.
2. Cannot read one row outside scope, even by guessing a UUID.
3. Cannot call a mutation RPC without the permission.
4. Cannot change `customer_id`, `reference`, `status` or `assignee_id` through a
   direct table update (no update grant).
5. Customer cannot see any `visibility='internal'` message, including through
   nested joins and API filters.
6. Management viewer cannot read ticket content but can read the aggregate
   reporting surface once it exists.
7. Suspended/disabled accounts are blocked after the Phase 2 change.

SQL and E2E cases are listed in [TEST_PLAN](TEST_PLAN.md). None of the RLS cases
have been executed yet.
