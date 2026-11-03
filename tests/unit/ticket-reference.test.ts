import { describe, expect, it } from 'vitest';
import {
  formatTicketReference,
  parseTicketReference,
} from '@/domain/ticket-reference';

describe('ticket reference', () => {
  it('formats the approved CTS-YYYY-NNNNNN shape', () => {
    expect(formatTicketReference(2026, 1)).toBe('CTS-2026-000001');
    expect(formatTicketReference(2026, 123456)).toBe('CTS-2026-123456');
  });

  it('rejects invalid years and sequences', () => {
    expect(() => formatTicketReference(26, 1)).toThrow(RangeError);
    expect(() => formatTicketReference(2026, 0)).toThrow(RangeError);
    expect(() => formatTicketReference(2026, 1_000_000)).toThrow(RangeError);
    expect(() => formatTicketReference(2026, 1.5)).toThrow(RangeError);
  });

  it('parses valid references', () => {
    expect(parseTicketReference('CTS-2026-000001')).toEqual({
      year: 2026,
      sequence: 1,
    });
    expect(parseTicketReference(' cts-2026-000042 ')).toEqual({
      year: 2026,
      sequence: 42,
    });
  });

  it('rejects malformed references', () => {
    expect(parseTicketReference('CTS-2026-000000')).toBeNull();
    expect(parseTicketReference('CTS-2026-1')).toBeNull();
    expect(parseTicketReference('TICKET-2026-000001')).toBeNull();
    expect(parseTicketReference('CTS-2026-000001-extra')).toBeNull();
  });

  it('round-trips a formatted reference', () => {
    const reference = formatTicketReference(2027, 98765);
    expect(parseTicketReference(reference)).toEqual({
      year: 2027,
      sequence: 98765,
    });
  });
});
