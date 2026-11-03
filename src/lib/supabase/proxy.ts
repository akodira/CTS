import { createServerClient } from '@supabase/ssr';
import type { NextRequest } from 'next/server';

export type RefreshedCookie = {
  name: string;
  value: string;
  options?: {
    path?: string;
    domain?: string;
    maxAge?: number;
    expires?: Date;
    httpOnly?: boolean;
    secure?: boolean;
    sameSite?: boolean | 'lax' | 'strict' | 'none';
  };
};

/**
 * Refreshes the Supabase session during proxy execution and returns the
 * cookies that must be written to the outgoing response.
 *
 * Proxy runs before rendering, so this is the only place where an expired
 * access token can be rotated and persisted for both the browser and the
 * downstream server render.
 */
export async function refreshSessionCookies(
  request: NextRequest,
): Promise<RefreshedCookie[]> {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    return [];
  }

  const refreshed: RefreshedCookie[] = [];

  const supabase = createServerClient(url, anonKey, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => {
          request.cookies.set(name, value);
        });
        refreshed.push(...cookiesToSet);
      },
    },
  });

  // Must use getUser() (validates with the Auth server), not getSession().
  await supabase.auth.getUser();

  return refreshed;
}
