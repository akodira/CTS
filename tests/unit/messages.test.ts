import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

type Messages = { [key: string]: string | Messages };

function load(locale: 'en' | 'ar'): Messages {
  const path = fileURLToPath(
    new URL(`../../messages/${locale}.json`, import.meta.url),
  );
  return JSON.parse(readFileSync(path, 'utf8')) as Messages;
}

function flatten(value: Messages, prefix = ''): string[] {
  return Object.entries(value).flatMap(([key, child]) => {
    const keyPath = prefix ? `${prefix}.${key}` : key;
    return typeof child === 'string' ? [keyPath] : flatten(child, keyPath);
  });
}

describe('localized messages', () => {
  const en = new Set(flatten(load('en')));
  const ar = new Set(flatten(load('ar')));

  it('defines the same keys in English and Arabic', () => {
    expect([...en].sort()).toEqual([...ar].sort());
  });

  it('does not ship empty translations', () => {
    for (const locale of ['en', 'ar'] as const) {
      const messages = load(locale);
      const walk = (value: Messages): void => {
        for (const child of Object.values(value)) {
          if (typeof child === 'string') {
            expect(child.trim().length).toBeGreaterThan(0);
          } else {
            walk(child);
          }
        }
      };
      walk(messages);
    }
  });
});
