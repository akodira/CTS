export const TICKET_REFERENCE_PREFIX = 'CTS';
export const TICKET_REFERENCE_PATTERN = /^CTS-(\d{4})-(\d{6})$/;

/**
 * Formats the human-readable ticket reference. The database allocates the
 * sequence atomically inside the create_ticket transaction; this helper is
 * for display, tests and imports — never for generating references.
 */
export function formatTicketReference(year: number, sequence: number): string {
  if (!Number.isInteger(year) || year < 2000 || year > 9999) {
    throw new RangeError('Ticket year must be a four-digit integer');
  }
  if (!Number.isInteger(sequence) || sequence < 1 || sequence > 999_999) {
    throw new RangeError('Ticket sequence must be between 1 and 999999');
  }

  return `${TICKET_REFERENCE_PREFIX}-${year}-${String(sequence).padStart(6, '0')}`;
}

export type ParsedTicketReference = {
  year: number;
  sequence: number;
};

export function parseTicketReference(
  reference: string,
): ParsedTicketReference | null {
  const match = TICKET_REFERENCE_PATTERN.exec(reference.trim().toUpperCase());
  if (!match) return null;

  const year = Number(match[1]);
  const sequence = Number(match[2]);
  if (sequence < 1) return null;

  return { year, sequence };
}
