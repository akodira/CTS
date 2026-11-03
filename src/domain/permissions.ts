/**
 * Role and permission vocabulary.
 *
 * These constants keep UI affordances and service-layer guards readable.
 * They never replace database authorization: every mutation is re-checked
 * inside a SECURITY DEFINER RPC and by RLS policies.
 */

export const ROLES = [
  'customer',
  'support_agent',
  'team_leader',
  'system_admin',
  'management_viewer',
] as const;

export type Role = (typeof ROLES)[number];

export const STAFF_ROLES = [
  'support_agent',
  'team_leader',
  'system_admin',
] as const satisfies readonly Role[];

export type Permission =
  | 'ticket.create'
  | 'ticket.view.own'
  | 'ticket.view.team'
  | 'ticket.view.all'
  | 'ticket.reply.public'
  | 'ticket.note.internal'
  | 'ticket.claim'
  | 'ticket.assign'
  | 'ticket.reassign'
  | 'ticket.status.change'
  | 'ticket.priority.change'
  | 'ticket.escalate'
  | 'ticket.resolve'
  | 'ticket.close'
  | 'ticket.confirm_resolution'
  | 'ticket.reopen.own'
  | 'feedback.submit'
  | 'admin.users'
  | 'admin.teams'
  | 'admin.catalog'
  | 'admin.sla'
  | 'admin.kb'
  | 'admin.settings'
  | 'report.view.own'
  | 'report.view.team'
  | 'report.view.all'
  | 'report.export'
  | 'audit.view'
  | 'attachment.upload'
  | 'attachment.download';

export const PERMISSIONS: Record<Permission, readonly Role[]> = {
  'ticket.create': ['customer'],
  'ticket.view.own': ['customer'],
  'ticket.view.team': ['support_agent', 'team_leader', 'system_admin'],
  'ticket.view.all': ['system_admin'],
  'ticket.reply.public': [
    'customer',
    'support_agent',
    'team_leader',
    'system_admin',
  ],
  'ticket.note.internal': [
    'support_agent',
    'team_leader',
    'system_admin',
  ],
  'ticket.claim': ['support_agent', 'team_leader', 'system_admin'],
  'ticket.assign': ['team_leader', 'system_admin'],
  'ticket.reassign': ['team_leader', 'system_admin'],
  'ticket.status.change': [
    'support_agent',
    'team_leader',
    'system_admin',
  ],
  'ticket.priority.change': [
    'support_agent',
    'team_leader',
    'system_admin',
  ],
  'ticket.escalate': ['team_leader', 'system_admin'],
  'ticket.resolve': ['support_agent', 'team_leader', 'system_admin'],
  'ticket.close': ['team_leader', 'system_admin'],
  'ticket.confirm_resolution': ['customer'],
  'ticket.reopen.own': ['customer'],
  'feedback.submit': ['customer'],
  'admin.users': ['system_admin'],
  'admin.teams': ['system_admin'],
  'admin.catalog': ['system_admin'],
  'admin.sla': ['system_admin'],
  'admin.kb': ['system_admin'],
  'admin.settings': ['system_admin'],
  'report.view.own': ['support_agent'],
  'report.view.team': ['team_leader', 'system_admin'],
  'report.view.all': ['system_admin', 'management_viewer'],
  'report.export': [
    'team_leader',
    'system_admin',
    'management_viewer',
  ],
  'audit.view': ['system_admin'],
  'attachment.upload': [
    'customer',
    'support_agent',
    'team_leader',
    'system_admin',
  ],
  'attachment.download': [
    'customer',
    'support_agent',
    'team_leader',
    'system_admin',
  ],
};

export function isRole(value: unknown): value is Role {
  return typeof value === 'string' && (ROLES as readonly string[]).includes(value);
}

export function isStaffRole(role: Role): boolean {
  return (STAFF_ROLES as readonly Role[]).includes(role);
}

export function hasPermission(role: Role, permission: Permission): boolean {
  return PERMISSIONS[permission].includes(role);
}

export function permissionsForRole(role: Role): Permission[] {
  return (Object.entries(PERMISSIONS) as [Permission, readonly Role[]][])
    .filter(([, roles]) => roles.includes(role))
    .map(([permission]) => permission);
}

/**
 * Staff accounts are support employees, not requesters. A user is either a
 * customer or staff; mixed assignments are rejected by the role RPC.
 */
export function isRoleCombinationAllowed(roles: readonly Role[]): boolean {
  const unique = new Set(roles);
  if (unique.size !== roles.length) return false;

  const hasCustomer = unique.has('customer');
  const hasStaff = [...unique].some(isStaffRole);

  return !(hasCustomer && hasStaff);
}
