-- CTS migration 0010
-- Reference data, approved SLA defaults and the transition rules that drive
-- the ticket state machine.

begin;

insert into public.roles (code, name_en, name_ar, description_en, description_ar)
values
  ('customer', 'Customer', 'عميل', 'External customer who submits and tracks tickets', 'عميل خارجي يرفع الطلبات ويتابعها'),
  ('support_agent', 'Support Agent', 'موظف دعم', 'Handles assigned tickets and replies to customers', 'يعالج التذاكر المسندة ويرد على العملاء'),
  ('team_leader', 'Team Leader', 'قائد فريق', 'Assigns tickets, escalates and monitors the team', 'يسند التذاكر ويصعّدها ويراقب أداء الفريق'),
  ('system_admin', 'System Administrator', 'مدير النظام', 'Manages users, settings, SLA and security', 'يدير المستخدمين والإعدادات واتفاقية الخدمة والأمان'),
  ('management_viewer', 'Management Viewer', 'مراقب إداري', 'Read-only access to dashboards and reports', 'يطلع فقط على لوحات المتابعة والتقارير')
on conflict (code) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  description_en = excluded.description_en,
  description_ar = excluded.description_ar;

-- Fixed identifiers keep seeds and future imports deterministic.
insert into public.priorities (id, code, name_en, name_ar, weight)
values
  ('10000000-0000-4000-8000-000000000001', 'critical', 'Critical', 'حرجة', 100),
  ('10000000-0000-4000-8000-000000000002', 'high', 'High', 'عالية', 75),
  ('10000000-0000-4000-8000-000000000003', 'normal', 'Normal', 'عادية', 50),
  ('10000000-0000-4000-8000-000000000004', 'low', 'Low', 'منخفضة', 25)
on conflict (code) do update set
  name_en = excluded.name_en,
  name_ar = excluded.name_ar,
  weight = excluded.weight,
  is_active = true;

insert into public.ticket_transition_rules
  (from_status, to_status, allowed_roles, customer_allowed, requires_reason)
values
  ('new', 'open', array['support_agent','team_leader','system_admin'], false, false),
  ('new', 'in_progress', array['support_agent','team_leader','system_admin'], false, false),
  ('new', 'pending_internal', array['support_agent','team_leader','system_admin'], false, false),
  ('new', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('new', 'closed', array['team_leader','system_admin'], false, true),
  ('open', 'in_progress', array['support_agent','team_leader','system_admin'], false, false),
  ('open', 'pending_customer', array['support_agent','team_leader','system_admin'], false, false),
  ('open', 'pending_internal', array['support_agent','team_leader','system_admin'], false, false),
  ('open', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('open', 'closed', array['team_leader','system_admin'], false, true),
  ('in_progress', 'open', array['support_agent','team_leader','system_admin'], false, false),
  ('in_progress', 'pending_customer', array['support_agent','team_leader','system_admin'], false, false),
  ('in_progress', 'pending_internal', array['support_agent','team_leader','system_admin'], false, false),
  ('in_progress', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('in_progress', 'closed', array['team_leader','system_admin'], false, true),
  ('pending_customer', 'in_progress', array['support_agent','team_leader','system_admin'], false, false),
  ('pending_customer', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('pending_customer', 'closed', array['team_leader','system_admin'], false, true),
  ('pending_internal', 'in_progress', array['support_agent','team_leader','system_admin'], false, false),
  ('pending_internal', 'pending_customer', array['support_agent','team_leader','system_admin'], false, false),
  ('pending_internal', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('pending_internal', 'closed', array['team_leader','system_admin'], false, true),
  ('resolved', 'closed', array['customer','team_leader','system_admin'], true, false),
  ('resolved', 'reopened', array['customer','team_leader','system_admin'], true, true),
  ('closed', 'reopened', array['customer','team_leader','system_admin'], true, true),
  ('reopened', 'in_progress', array['support_agent','team_leader','system_admin'], false, false),
  ('reopened', 'pending_customer', array['support_agent','team_leader','system_admin'], false, false),
  ('reopened', 'pending_internal', array['support_agent','team_leader','system_admin'], false, false),
  ('reopened', 'resolved', array['support_agent','team_leader','system_admin'], false, true),
  ('reopened', 'closed', array['team_leader','system_admin'], false, true)
on conflict (from_status, to_status) do update set
  allowed_roles = excluded.allowed_roles,
  customer_allowed = excluded.customer_allowed,
  requires_reason = excluded.requires_reason;

-- Approved business calendar: Asia/Riyadh, Sunday–Thursday, 08:00–17:00.
insert into public.business_calendars (id, name, timezone, is_24_7)
values (
  '20000000-0000-4000-8000-000000000001',
  'Riyadh Business Hours',
  'Asia/Riyadh',
  false
)
on conflict (id) do update set
  name = excluded.name,
  timezone = excluded.timezone,
  is_24_7 = excluded.is_24_7;

insert into public.business_calendar_intervals (calendar_id, day_of_week, start_time, end_time)
values
  ('20000000-0000-4000-8000-000000000001', 0, '08:00', '17:00'),
  ('20000000-0000-4000-8000-000000000001', 1, '08:00', '17:00'),
  ('20000000-0000-4000-8000-000000000001', 2, '08:00', '17:00'),
  ('20000000-0000-4000-8000-000000000001', 3, '08:00', '17:00'),
  ('20000000-0000-4000-8000-000000000001', 4, '08:00', '17:00')
on conflict (calendar_id, day_of_week, start_time) do nothing;

-- Approved SLA defaults (Phase 0). Resolution targets are separate from
-- first-response targets and are snapshotted per ticket when the clock starts.
insert into public.sla_policies (
  id, name, priority_id, first_response_minutes, resolution_minutes,
  business_calendar_id, warning_threshold_pct,
  pause_on_pending_customer, pause_on_pending_internal,
  is_default, is_active
)
values
  (
    '30000000-0000-4000-8000-000000000001', 'Critical SLA',
    '10000000-0000-4000-8000-000000000001', 15, 240,
    '20000000-0000-4000-8000-000000000001', 75, true, false, false, true
  ),
  (
    '30000000-0000-4000-8000-000000000002', 'High SLA',
    '10000000-0000-4000-8000-000000000002', 60, 480,
    '20000000-0000-4000-8000-000000000001', 75, true, false, false, true
  ),
  (
    '30000000-0000-4000-8000-000000000003', 'Normal SLA',
    '10000000-0000-4000-8000-000000000003', 240, 1440,
    '20000000-0000-4000-8000-000000000001', 75, true, false, false, true
  ),
  (
    '30000000-0000-4000-8000-000000000004', 'Low SLA',
    '10000000-0000-4000-8000-000000000004', 480, 2880,
    '20000000-0000-4000-8000-000000000001', 75, true, false, false, true
  ),
  (
    '30000000-0000-4000-8000-000000000005', 'Default SLA (Normal)',
    null, 240, 1440,
    '20000000-0000-4000-8000-000000000001', 75, true, false, true, true
  )
on conflict (id) do update set
  name = excluded.name,
  priority_id = excluded.priority_id,
  first_response_minutes = excluded.first_response_minutes,
  resolution_minutes = excluded.resolution_minutes,
  business_calendar_id = excluded.business_calendar_id,
  warning_threshold_pct = excluded.warning_threshold_pct,
  pause_on_pending_customer = excluded.pause_on_pending_customer,
  pause_on_pending_internal = excluded.pause_on_pending_internal,
  is_default = excluded.is_default,
  is_active = excluded.is_active;

-- Approved escalation defaults: warn at 75% (team leader) and breach at 100%
-- (system administrator). Team-specific routing can be added when teams exist.
insert into public.sla_escalation_rules (policy_id, level, threshold_pct, notify_role)
select p.id, v.level, v.threshold_pct, v.notify_role
from public.sla_policies p
cross join (
  values
    (1, 75, 'team_leader'),
    (2, 100, 'system_admin')
) as v(level, threshold_pct, notify_role)
on conflict (policy_id, level) do update set
  threshold_pct = excluded.threshold_pct,
  notify_role = excluded.notify_role,
  notify_team_id = null;

insert into public.system_settings (key, value, description)
values
  ('customer_priority_selection', 'false'::jsonb, 'Allow customers to choose priority (approved: disabled)'),
  ('reopen_window_days', '7'::jsonb, 'Days after resolution in which a customer may reopen'),
  ('max_reopens', '2'::jsonb, 'Maximum customer-initiated reopens per ticket'),
  ('auto_close_business_days', '3'::jsonb, 'Business days before a resolved ticket auto-closes'),
  ('attachment_max_bytes', '26214400'::jsonb, 'Hard storage limit per attachment (25 MiB)'),
  ('attachment_max_per_message', '5'::jsonb, 'Maximum attachments per message'),
  ('reference_prefix', '"CTS"'::jsonb, 'Ticket reference prefix'),
  ('default_locale', '"en"'::jsonb, 'Fallback locale')
on conflict (key) do nothing;

commit;
