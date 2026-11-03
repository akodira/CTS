import { describe, expect, it } from 'vitest';
import {
  PERMISSIONS,
  ROLES,
  hasPermission,
  isRoleCombinationAllowed,
  permissionsForRole,
} from '@/domain/permissions';

describe('roles and permissions', () => {
  it('gives every role at least one permission', () => {
    for (const role of ROLES) {
      expect(permissionsForRole(role).length).toBeGreaterThan(0);
    }
  });

  it('assigns every declared permission to at least one role', () => {
    for (const roles of Object.values(PERMISSIONS)) {
      expect(roles.length).toBeGreaterThan(0);
    }
  });

  it('keeps private notes away from customers', () => {
    expect(hasPermission('customer', 'ticket.note.internal')).toBe(false);
    expect(hasPermission('support_agent', 'ticket.note.internal')).toBe(true);
  });

  it('prevents agents from assigning tickets or managing users', () => {
    expect(hasPermission('support_agent', 'ticket.assign')).toBe(false);
    expect(hasPermission('support_agent', 'admin.users')).toBe(false);
  });

  it('allows team leaders to assign but not administer the system', () => {
    expect(hasPermission('team_leader', 'ticket.assign')).toBe(true);
    expect(hasPermission('team_leader', 'admin.users')).toBe(false);
  });

  it('gives the system administrator administrative access', () => {
    expect(hasPermission('system_admin', 'admin.users')).toBe(true);
    expect(hasPermission('system_admin', 'admin.sla')).toBe(true);
    expect(hasPermission('system_admin', 'audit.view')).toBe(true);
  });

  it('keeps the management viewer read-only', () => {
    expect(hasPermission('management_viewer', 'report.view.all')).toBe(true);
    expect(hasPermission('management_viewer', 'ticket.status.change')).toBe(
      false,
    );
    expect(hasPermission('management_viewer', 'admin.settings')).toBe(false);
  });

  it('prevents customers from changing status through the generic action', () => {
    expect(hasPermission('customer', 'ticket.status.change')).toBe(false);
    expect(hasPermission('customer', 'ticket.confirm_resolution')).toBe(true);
  });

  it('rejects mixing customer and staff roles', () => {
    expect(isRoleCombinationAllowed(['customer'])).toBe(true);
    expect(isRoleCombinationAllowed(['customer', 'support_agent'])).toBe(false);
    expect(isRoleCombinationAllowed(['team_leader', 'support_agent'])).toBe(true);
    expect(isRoleCombinationAllowed(['customer', 'customer'])).toBe(false);
  });
});
