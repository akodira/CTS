import 'server-only';

import { createClient as createSupabaseClient } from '@supabase/supabase-js';
import { getServerEnv } from '@/lib/env';

/**
 * Privileged client that bypasses RLS. Only for:
 * - scheduled jobs (SLA evaluation, email dispatch)
 * - provider webhooks
 * - storage signing after an explicit authorization check
 *
 * Never import this module from a Client Component.
 */
export function createAdminClient() {
  const env = getServerEnv();

  return createSupabaseClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    },
  );
}
