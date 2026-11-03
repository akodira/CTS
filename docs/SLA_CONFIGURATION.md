# SLA Configuration

Approved Phase 0 defaults. They are seeded in `20261101000010_seed_reference_data.sql` and
**not yet enforced by any running job**. The database stores policies, calendars
and clock rows; the evaluator/cron that advances states and sends escalations is
scheduled for Phase 5.

## 1. Approved targets

Targets are **business minutes**, not wall-clock minutes.

| Priority | First response | Resolution | Warning at | Escalation at breach |
| --- | --- | --- | --- | --- |
| Critical | 15 min | 240 min (4 h) | 75% | 100% |
| High | 60 min | 480 min (8 h) | 75% | 100% |
| Normal | 240 min (4 h) | 1440 min (24 h) | 75% | 100% |
| Low | 480 min (8 h) | 2880 min (48 h) | 75% | 100% |
| Default (no priority match) | 240 min | 1440 min | 75% | 100% |

Both clocks start when the ticket is created. First response completes on the
first **public staff reply**; an internal note never counts. Resolution
completes when the ticket enters `resolved`.

> "24 h" and "48 h" are 1,440 and 2,880 **business** minutes. With a 9-hour
> business day they span about 2.7 and 5.3 business days, not one and two
> calendar days. This is intentional and must be reflected in customer-facing
> wording.

## 2. Business calendar

Seeded calendar: **Riyadh Business Hours**.

| Property | Value |
| --- | --- |
| Time zone | `Asia/Riyadh` (UTC+03, no daylight saving) |
| Working days | Sunday–Thursday |
| Hours | 08:00–17:00 local, one interval per day |
| Minutes per day | 540 |
| Week | 45 business hours |
| Holidays | **None seeded** — the owner must supply the official holiday list |

Friday and Saturday are closed. `business_calendar_intervals` supports multiple
intervals per day (e.g. a lunch break), but only 08:00–17:00 is seeded.

`is_24_7 = true` makes a calendar ignore intervals and holidays; useful for a
future "critical 24/7" policy. No 24/7 policy is seeded.

### Holiday handling

Add rows to `public.holidays` with `calendar_id`, `holiday_date`, and bilingual
names. The calculator matches the **exact date**; `is_recurring` is stored but
not expanded yet. Recurring holidays (e.g. an annual fixed-date holiday) need a
Phase 5 enhancement or must be inserted for each year.

## 3. Deadline computation

`private.add_business_minutes(start, minutes, calendar_id)` walks forward:

1. If the calendar is 24/7, add wall-clock minutes.
2. If the local date is a holiday, jump to 00:00 the next day.
3. For each interval that day, skip intervals already ended; clamp the cursor to
   the interval start; consume available minutes.
4. If minutes remain, jump to the next local day and repeat.
5. Guard at 4,000 iterations to prevent infinite loops on misconfigured
   calendars.

At clock start the system snapshots:

```text
target_minutes = policy target
started_at     = now()
due_at         = add_business_minutes(started_at, target_minutes, calendar)
warning_at     = started_at + (target_minutes * warning_threshold_pct / 100)
```

`warning_at` is computed on the **business-minute axis**, not by subtracting
wall-clock time from `due_at`. The schema only checks `warning_at <= due_at`;
the evaluator must compute it consistently.

### Worked examples

All times Asia/Riyadh.

| Scenario | Result |
| --- | --- |
| Critical first response, created Sunday 08:05 | Due Sunday 08:20; warning Sunday 08:16:15 |
| High first response, created Thursday 16:30 | 30 business minutes remain Thursday; Friday/Saturday closed; due Sunday 08:30 |
| Normal resolution, created Sunday 08:00 | 2 full days (1,080 min) + 360 min on Tuesday → due Tuesday 14:00 |
| Low resolution, created Sunday 08:00 | 5 full days (2,700 min) + 180 min → due next Sunday 11:00 (Friday/Saturday skipped) |
| Any clock started Friday 10:00 | Starts at Sunday 08:00; the closed period is not counted |

The implementation of these examples is a **test requirement**, not evidence
that they already pass.

## 4. Warning and escalation

| Milestone | State/event | Action |
| --- | --- | --- |
| 75% of target | `warning_at`, state `due_soon`, `sla_events.event_type='warning'` | Notify team leader (seeded escalation level 1), show "due soon" in queue |
| 100% of target | `due_at`, state `breached`, `breached_at`, `sla_events.event_type='breached'` | Notify system administrator (level 2), create/maintain an escalation row |
| Clock completed | `completed_at`, state `completed`, event `completed` | Stop evaluating |

Seeded escalation rules (10 rows: 2 per policy):

| Level | Threshold | Notify role | Notify team |
| --- | --- | --- | --- |
| 1 | 75% | `team_leader` | none (routes to role) |
| 2 | 100% | `system_admin` | none |

No teams exist yet, so role-based routing is used. When teams are created, add
team-specific rules or update these rows. `sla_escalation_rules` is unique per
`(policy_id, level)`.

Idempotency:

- `sla_events.dedupe_key` is unique. Use a key such as
  `sla:{record_id}:warning`, `sla:{record_id}:breached`,
  `sla:{record_id}:escalated:{level}`.
- `escalations.dedupe_key` is unique. Use
  `ticket:{ticket_id}:sla:{record_id}:level:{level}`.
- A cron retry must not create duplicate events, escalations, notifications or
  emails.

## 5. Pausing

Approved default: pause **only** on `pending_customer`.

| Status | Pause first response | Pause resolution |
| --- | --- | --- |
| `pending_customer` | Yes (default) | Yes (default) |
| `pending_internal` | No | No |
| `open`, `in_progress`, `new`, `reopened` | No | No |
| `resolved`, `closed` | Clock completed | Clock completed |

Pause/resume procedure (Phase 5):

1. On entering `pending_customer`, set `paused_at = now()` for open clocks,
   write a `paused` event.
2. On leaving, compute `paused_seconds += now() - paused_at`, shift `due_at` and
   `warning_at` forward by the paused duration, clear `paused_at`, write a
   `resumed` event.
3. Clamp negative or zero durations; never shift twice for the same interval.
4. Store `last_evaluated_at` for observability.
5. If a clock is already breached, pausing does not "un-breach" it.

The auto-close timer is separate: **3 business days** after `resolved_at`.
Auto-closing does not pause.

## 6. Policy selection (planned)

The schema supports scoped policies:

- priority-specific (`priority_id`);
- category-specific (`category_id`);
- team-specific (`team_id`);
- a single active default (`is_default`).

The **selection function is not implemented**. The intended precedence, from
most to least specific, is:

```text
team + category + priority
team + category
team + priority
category + priority
team
category
priority
default
```

Tie-break on the newest `effective_from`. A policy must be active and its
calendar must exist. The resolved policy's targets are snapshotted into
`ticket_sla_records`; later policy edits do not rewrite existing clocks.

Do not build the Phase 4 UI assuming selection works until the function and its
tests exist.

## 7. Reopen and new cycles

On customer/staff reopen:

1. Complete or abandon the current `resolution` cycle; keep history.
2. Increment the cycle for both metrics (`cycle = reopen_count + 1`).
3. Resolve the current policy and compute fresh deadlines from the reopen time.
4. Reset `state='on_track'`, `escalation_level=0`, clear pause fields.
5. Write `started` events with new dedupe keys.

Prior cycles remain in `ticket_sla_records` and `sla_events` for reporting.
A reopen is capped at 2 per ticket.

## 8. Processing architecture

```text
Vercel Cron (Pro, every 5 min)  ──┐
                                  ├── GET /api/cron/sla (CRON_SECRET)
Supabase pg_cron + Edge Function ─┘        │
                                           ├── select open clocks (state, due_at)
                                           ├── transition warning/breached
                                           ├── insert sla_events/escalations (dedupe)
                                           └── enqueue notifications/emails
```

**Neither cron route nor scheduler exists in Phase 1.** Configuration notes:

- **Vercel Hobby** allows only **daily** cron jobs. A 5-minute SLA loop requires
  **Vercel Pro**.
- **Supabase `pg_cron`** can run SQL on a schedule and is independent of the
  Vercel plan, but the notification/email logic must live in SQL or an Edge
  Function. This is an alternative for cost control.
- Protect the route with `CRON_SECRET`; Vercel Cron sends
  `Authorization: Bearer $CRON_SECRET` when configured.
- Make the handler idempotent and safe to run concurrently. Use `FOR UPDATE SKIP
  LOCKED` or a single advisory lock.
- Bound the batch size (e.g. 500 clocks per run) and record the run result.
- Alert on a growing backlog of open clocks whose `last_evaluated_at` is stale.

Do not configure any cron in B6 until the route exists and has been tested.

## 9. Reporting metrics

Planned reports (Phase 6) use the clock rows, not recomputation:

- first-response compliance: completed before `due_at` / total;
- resolution compliance;
- average first response and resolution in business minutes;
- breach count by priority/team;
- paused time;
- reopened rate and CSAT correlation.

Because targets are snapshotted, historical compliance stays stable after a
policy change.

## 10. Configuration changes

To change a target or calendar:

1. Create a new migration; never edit an applied migration in place.
2. Prefer inserting a new policy row with `is_active=true` and deactivating the
   old one in the same transaction. The unique scope index allows only one
   active policy per scope.
3. Bump `version` and set `effective_from`.
4. Do not delete a policy that has `ticket_sla_records` (FK blocks it). Retire
   with `is_active=false`.
5. Add/extend tests for the new calendar/interval/holiday.
6. Announce the change; existing clocks keep their snapshotted targets.

## 11. Test checklist (not yet executed)

- [ ] 15 business minutes across a closed period returns the next opening + 15.
- [ ] Thursday 16:30 + 60 minutes = Sunday 08:30.
- [ ] 1,440 business minutes from Sunday 08:00 = Tuesday 14:00.
- [ ] Holiday is skipped; a ticket created on a holiday starts next business day.
- [ ] Friday/Saturday are skipped.
- [ ] Pause/resume shifts deadlines exactly once.
- [ ] Warning fires at 75%, not earlier or later.
- [ ] Breach fires at 100%, once, even with repeated cron runs.
- [ ] Escalation dedupe prevents duplicates.
- [ ] 24/7 calendar ignores intervals and holidays.
- [ ] Reopen creates cycle 2 with fresh targets.
- [ ] Policy scoping picks the intended row (after selection is implemented).
