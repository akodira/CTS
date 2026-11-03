import 'server-only';

import pino from 'pino';
import { getServerEnv } from '@/lib/env';

const globalForLogger = globalThis as unknown as {
  ctsLogger?: pino.Logger;
};

function createLogger(): pino.Logger {
  return pino({
    level: process.env.LOG_LEVEL ?? 'info',
    base: { service: 'cts' },
    redact: {
      paths: [
        'req.headers.authorization',
        'req.headers.cookie',
        'password',
        'token',
        'access_token',
        'refresh_token',
        'email',
        'phone',
        'body',
        'message',
      ],
      censor: '[redacted]',
    },
    timestamp: pino.stdTimeFunctions.isoTime,
  });
}

export const logger = globalForLogger.ctsLogger ?? createLogger();

if (process.env.NODE_ENV !== 'production') {
  globalForLogger.ctsLogger = logger;
}

/** Validate required server configuration early in server-only entry points. */
export function assertServerEnv(): void {
  getServerEnv();
}
