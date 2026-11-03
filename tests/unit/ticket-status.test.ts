import { describe, expect, it } from 'vitest';
import {
  ACTIVE_TICKET_STATUSES,
  CUSTOMER_STATUS_ACTIONS,
  TICKET_STATUSES,
  TRANSITIONS,
  canTransition,
  getCustomerReopenEligibility,
  isActiveStatus,
  isAwaitingCustomer,
  isAwaitingInternal,
  isTerminal,
  isTicketStatus,
} from '@/domain/ticket-status';

describe('ticket status vocabulary', () => {
  it('defines a transition list for every status', () => {
    for (const status of TICKET_STATUSES) {
      expect(TRANSITIONS[status]).toBeDefined();
    }
  });

  it('only references known statuses', () => {
    for (const [from, targets] of Object.entries(TRANSITIONS)) {
      expect(isTicketStatus(from)).toBe(true);
      for (const target of targets) {
        expect(TICKET_STATUSES).toContain(target);
      }
    }
  });

  it('never allows a status to transition to itself', () => {
    for (const status of TICKET_STATUSES) {
      expect(canTransition(status, status)).toBe(false);
    }
  });

  it('keeps resolution and closure as separate stages', () => {
    expect(canTransition('resolved', 'closed')).toBe(true);
    expect(canTransition('resolved', 'reopened')).toBe(true);
    expect(canTransition('closed', 'resolved')).toBe(false);
  });

  it('does not allow a customer to move a new ticket straight to closed', () => {
    expect(
      (CUSTOMER_STATUS_ACTIONS.new ?? []).includes('closed'),
    ).toBe(false);
  });

  it('allows a customer to reopen a resolved or closed ticket', () => {
    expect(
      (CUSTOMER_STATUS_ACTIONS.resolved ?? []).includes('reopened'),
    ).toBe(true);
    expect(
      (CUSTOMER_STATUS_ACTIONS.closed ?? []).includes('reopened'),
    ).toBe(true);
  });

  it('classifies active and terminal statuses', () => {
    for (const status of ACTIVE_TICKET_STATUSES) {
      expect(isActiveStatus(status)).toBe(true);
    }
    expect(isActiveStatus('resolved')).toBe(false);
    expect(isActiveStatus('closed')).toBe(false);
  });

  it('identifies waiting and terminal statuses', () => {
    expect(isAwaitingCustomer('pending_customer')).toBe(true);
    expect(isAwaitingCustomer('open')).toBe(false);
    expect(isAwaitingInternal('pending_internal')).toBe(true);
    expect(isAwaitingInternal('open')).toBe(false);
    expect(isTerminal('closed')).toBe(true);
    expect(isTerminal('resolved')).toBe(false);
  });
});

describe('customer reopen eligibility', () => {
  const now = new Date('2026-11-02T12:00:00.000Z');

  it('allows a recent resolved ticket', () => {
    const result = getCustomerReopenEligibility({
      status: 'resolved',
      resolvedAt: new Date('2026-11-01T12:00:00.000Z'),
      reopenCount: 0,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result).toEqual({ eligible: true, reason: 'ok' });
  });

  it('rejects a ticket the customer already confirmed', () => {
    const result = getCustomerReopenEligibility({
      status: 'resolved',
      resolvedAt: new Date('2026-11-01T12:00:00.000Z'),
      reopenCount: 0,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: true,
    });
    expect(result.reason).toBe('already_confirmed');
  });

  it('rejects a ticket outside the reopen window', () => {
    const result = getCustomerReopenEligibility({
      status: 'closed',
      resolvedAt: new Date('2026-10-20T12:00:00.000Z'),
      reopenCount: 0,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result.reason).toBe('window_expired');
  });

  it('rejects a resolved ticket that reached the reopen limit', () => {
    const result = getCustomerReopenEligibility({
      status: 'resolved',
      resolvedAt: new Date('2026-11-01T12:00:00.000Z'),
      reopenCount: 2,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result.reason).toBe('max_reopens_reached');
  });

  it('rejects a resolved ticket with no resolution timestamp', () => {
    const result = getCustomerReopenEligibility({
      status: 'resolved',
      resolvedAt: null,
      reopenCount: 0,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result.reason).toBe('not_resolved');
  });

  it('rejects a non-resolved ticket regardless of its reopen count', () => {
    const result = getCustomerReopenEligibility({
      status: 'reopened',
      resolvedAt: new Date('2026-11-01T12:00:00.000Z'),
      reopenCount: 2,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result.reason).toBe('not_resolved');
  });

  it('rejects an open ticket', () => {
    const result = getCustomerReopenEligibility({
      status: 'open',
      resolvedAt: null,
      reopenCount: 0,
      now,
      windowDays: 7,
      maxReopens: 2,
      confirmedByCustomer: false,
    });
    expect(result.reason).toBe('not_resolved');
  });
});
