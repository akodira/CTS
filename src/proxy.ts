import createMiddleware from 'next-intl/middleware';
import type { NextRequest } from 'next/server';
import { routing } from './i18n/routing';
import { refreshSessionCookies } from './lib/supabase/proxy';

const handleI18nRouting = createMiddleware(routing);

export default async function proxy(request: NextRequest) {
  const refreshedCookies = await refreshSessionCookies(request);
  const response = handleI18nRouting(request);

  for (const { name, value, options } of refreshedCookies) {
    response.cookies.set(name, value, options);
  }

  return response;
}

export const config = {
  // Run on pages only. API routes, auth callbacks, static assets and files
  // with an extension bypass locale routing and session refresh.
  matcher: '/((?!api|auth|_next|_vercel|.*\\..*).*)',
};
