/**
 * Ticket lifecycle vocabulary.
 *
 * This module is the TypeScript mirror of the rules seeded into
 * public.ticket_transition_rules. PostgreSQL remains the authority: the
 * transitions below only drive UI affordances and must be kept in parity
 * with migration 0010_seed_reference_data.sql.
 */

export const TICKET_STATUSES = [
  'new',
  'open',
  'in_progress',
  'pending_customer',
  'pending_internal',
  'resolved',
  'closed',
  'reopened',
] as const;

export type TicketStatus = (typeof TICKET_STATUSES)[number];

export const ACTIVE_TICKET_STATUSES = [
  'new',
  'open',
  'in_progress',
  'pending_customer',
  'pending_internal',
  'reopened',
] as const satisfies readonly TicketStatus[];

export const TRANSITIONS: Record<TicketStatus, readonly TicketStatus[]> = {
  new: ['open', 'in_progress', 'pending_internal', 'resolved', 'closed'],
  open: [
    'in_progress',
    'pending_customer',
    'pending_internal',
    'resolved',
    'closed',
  ],
  in_progress: [
    'open',
    'pending_customer',
    'pending_internal',
    'resolved',
    'closed',
  ],
  pending_customer: ['in_progress', 'resolved', 'closed'],
  pending_internal: ['in_progress', 'pending_customer', 'resolved', 'closed'],
  resolved: ['closed', 'reopened'],
  closed: ['reopened'],
  reopened: [
    'in_progress',
    'pending_customer',
    'pending_internal',
    'resolved',
    'closed',
  ],
};

export const CUSTOMER_STATUS_ACTIONS: Partial<
  Record<TicketStatus, readonly TicketStatus[]>
> = {
  resolved: ['closed', 'reopened'],
  closed: ['reopened'],
};

export function isTicketStatus(value: unknown): value is TicketStatus {
  return (
    typeof value === 'string' &&
    (TICKET_STATUSES as readonly string[]).includes(value)
  );
}

export function canTransition(from: TicketStatus, to: TicketStatus): boolean {
  return TRANSITIONS[from].includes(to);
}

export function isActiveStatus(status: TicketStatus): boolean {
  return (ACTIVE_TICKET_STATUSES as readonly TicketStatus[]).includes(status);
}

export function isAwaitingCustomer(status: TicketStatus): boolean {
  return status === 'pending_customer';
}

export function isAwaitingInternal(status: TicketStatus): boolean {
  return status === 'pending_internal';
}

export function isTerminal(status: TicketStatus): boolean {
  return status === 'closed';
}

export type ReopenEligibilityInput = {
  status: TicketStatus;
  resolvedAt: Date | null;
  reopenCount: number;
  now: Date;
  windowDays: number;
  maxReopens: number;
  confirmedByCustomer: boolean;
};

export type ReopenEligibility = {
  eligible: boolean;
  reason:
    | 'ok'
    | 'not_resolved'
    | 'already_confirmed'
    | 'window_expired'
    | 'max_reopens_reached';
};

/**
 * Customer self-service reopen policy (defaults approved in Phase 0):
 * resolved or auto-closed tickets, within 7 days of resolution, up to 2 times,
 * and never after the customer has explicitly confirmed the resolution.
 */
export function getCustomerReopenEligibility(
  input: ReopenEligibilityInput,
): ReopenEligibility {
  if (input.status !== 'resolved' && input.status !== 'closed') {
    return { eligible: false, reason: 'not_resolved' };
  }
  if (input.confirmedByCustomer) {
    return { eligible: false, reason: 'already_confirmed' };
  }
  if (input.reopenCount >= input.maxReopens) {
    return { eligible: false, reason: 'max_reopens_reached' };
  }
  if (!input.resolvedAt) {
    return { eligible: false, reason: 'not_resolved' };
  }

  const windowMs = input.windowDays * 24 * 60 * 60 * 1000;
  if (input.now.getTime() - input.resolvedAt.getTime() > windowMs) {
    return { eligible: false, reason: 'window_expired' };
  }

  return { eligible: true, reason: 'ok' };
}
