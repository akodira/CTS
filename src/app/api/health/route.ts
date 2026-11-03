import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

/**
 * Liveness/readiness probe. Uses the public (anon or publishable) key and the
 * `health()` RPC. The service-role key is deliberately not used here.
 */
export async function GET() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publicKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !publicKey) {
    return NextResponse.json(
      {
        status: 'unconfigured',
        checks: { environment: false, database: false },
      },
      { status: 503 },
    );
  }

  const startedAt = Date.now();

  try {
    const supabase = createClient(url, publicKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await supabase.rpc('health');

    if (error) {
      return NextResponse.json(
        {
          status: 'error',
          checks: { environment: true, database: false },
          detail: `Database health check failed (${error.code ?? 'unknown'})`,
        },
        { status: 503 },
      );
    }

    return NextResponse.json({
      status: 'ok',
      checks: { environment: true, database: true },
      latencyMs: Date.now() - startedAt,
      database: data,
    });
  } catch {
    return NextResponse.json(
      {
        status: 'error',
        checks: { environment: true, database: false },
        detail: 'Database health check failed',
      },
      { status: 503 },
    );
  }
}
