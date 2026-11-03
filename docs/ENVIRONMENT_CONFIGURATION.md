# Environment Configuration

Every environment variable used by this project, its scope, where it must be set
and how to obtain it. **Never commit real secrets.** Only `NEXT_PUBLIC_*`
values may be exposed to the browser.

## 1. Required variables

| Variable | Scope | Required | Default | Purpose | How to obtain |
| --- | --- | --- | --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Browser + Server | Yes (for DB/auth) | — | Supabase project URL | Supabase → Project Settings → API → Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Browser + Server | Yes (for DB/auth) | — | Public/anon key used by the browser and RLS-scoped server calls | Supabase → Project Settings → API → `anon` `public` key |
| `NEXT_PUBLIC_APP_URL` | Server | Yes | `http://localhost:3000` | Base URL for redirects and emails | `http://localhost:3000` locally; `https://your-domain.com` in prod |
| `SUPABASE_SERVICE_ROLE_KEY` | Server only | Yes for cron/jobs/signing | — | Bypasses RLS. Never prefix with `NEXT_PUBLIC_` | Supabase → Project Settings → API → `service_role` `secret`. Rotate if exposed. |
| `CRON_SECRET` | Server only | Yes when cron is enabled | — | Protects `/api/cron/*` routes | Generate: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"` |
| `LOG_LEVEL` | Server only | No | `info` | Pino log level: `fatal`, `error`, `warn`, `info`, `debug`, `trace` | Set per environment |

## 2. Optional variables (planned)

| Variable | Scope | Required | Purpose | Notes |
| --- | --- | --- | --- | --- |
| `RESEND_API_KEY` | Server only | For email sending | Resend API key | Phase 5; store in Vercel Secrets, never in code |
| `EMAIL_FROM` | Server only | For email sending | Sender address | Must be verified in Resend or match your domain |
| `SUPABASE_DB_URL` | CI/migrations only | For direct DB scripts | Postgres connection string | Use only in GitHub Actions or local migration scripts; **do not** add to Vercel runtime env. Prefer `supabase db push` via the CLI. |
| `PLAYWRIGHT_BASE_URL` | Local/CI E2E | No | Base URL for tests | Defaults to `http://localhost:3000` |

## 3. Local development

1. Copy `.env.example` to `.env.local`:
   ```powershell
   Copy-Item .env.example .env.local
   ```
2. Fill in values from your Supabase project. For local Supabase (`supabase start`),
   the CLI prints `API URL`, the public/anon key and the service-role/secret key
   in its output.
3. Do **not** commit `.env.local`. `.gitignore` already excludes it.
4. Restart `npm run dev` after changing environment variables.

> The application validates public env with Zod at runtime. A missing
> `NEXT_PUBLIC_*` variable will throw on first use; the health endpoint will
> report `503 unconfigured` until values are supplied.

## 4. Vercel configuration

**Current plan: one Supabase project.** Use the same Supabase values for Development, Preview and Production. Add a separate staging project before storing real customer data.

| Variable | Development | Preview | Production | Notes |
| --- | --- | --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | same project | same project | same project | Single-project mode |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | same project | same project | same project | Public key |
| `NEXT_PUBLIC_APP_URL` | `http://localhost:3000` | `https://<preview-url>.vercel.app` | `https://your-domain.com` | Used for redirects/callbacks |
| `SUPABASE_SERVICE_ROLE_KEY` | same project | same project | same project | **Secret**; only server routes see it |
| `CRON_SECRET` | dev value | same value | same value | Required if enabling cron |
| `LOG_LEVEL` | `debug` | `info` | `warn` or `error` | Reduce logs in prod |
| `RESEND_API_KEY` / `EMAIL_FROM` | optional | same sender | same sender | Add when Phase 5 is deployed |

When you add staging later, split Preview onto the staging project and keep Production separate.

In Vercel, use **Environment Variables → Sensitive** for secrets. Do not
expose `SUPABASE_SERVICE_ROLE_KEY` to the browser (it must not be prefixed
`NEXT_PUBLIC_`).

## 5. Supabase Auth configuration

In your Supabase project:

1. **Authentication → URL Configuration**
   - Site URL: `https://your-domain.com` (or the Vercel URL)
   - Additional Redirect URLs: `https://your-domain.com/auth/callback`,
     `https://*.vercel.app/auth/callback`, `http://localhost:3000/auth/callback`
2. **Authentication → Email** — enable email confirmations as required.
3. **Authentication → Providers** — only providers you actually need.
4. **Rate limits** — review defaults; tighten if signup is abused.

The code exchanges the PKCE code at `/auth/callback` and only redirects to
relative, same-origin paths.

## 6. CI/CD secrets

GitHub Actions (workflows in `.github/workflows/`) need the following secrets:

| Secret | Used by | Notes |
| --- | --- | --- |
| `SUPABASE_ACCESS_TOKEN` | `migrations.yml` | Personal access token or org token from Supabase dashboard |
| `SUPABASE_PROJECT_ID` | `migrations.yml` | Project ref (e.g. `abcdefghijklmnop`) |
| `SUPABASE_DB_PASSWORD` | `migrations.yml` | Database password for the linked project |
| `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` | Optional deploy workflow | Not included; Vercel Git integration is used |
| `CRON_SECRET` | Optional e2e/tests | Only if testing cron routes |

Store them in **GitHub → Settings → Secrets and variables → Actions**. With one
project, create a single **Environment** named `production` (required reviewers
optional while the product is private). Add `staging` only when you create a
staging Supabase project.

The `ci.yml` workflow does **not** use real secrets; it sets placeholder
`NEXT_PUBLIC_*` values to allow `npm run build` to compile.

## 7. Security rules

- **Never** log secrets. The Pino logger redacts headers, cookies, tokens and
  email/phone/message bodies.
- **Never** import `src/lib/supabase/admin.ts` into a Client Component.
- **Never** commit `.env*` files except `.env.example`.
- **Rotate** `SUPABASE_SERVICE_ROLE_KEY` if it is ever exposed (Git history,
  logs, screenshots).
- **Use different keys** once you add a staging project; a single project may
  use one key set for now.
- **Restrict** `SUPABASE_ACCESS_TOKEN` to the minimum scope required by the
  migration workflow.
- **Prefer** the Vercel Git integration over long-lived deploy tokens where
  possible.

## 8. Verification

After setting variables:

1. `npm run dev` — landing page loads; no `process.env` crash.
2. `GET /api/health` — returns `200 ok` with DB info once configured, or
   `503 unconfigured` before values are set. Do **not** rely on a `200` from
   placeholders.
3. `npm run build` — passes with placeholder values (CI does this).
4. Typecheck/lint/test — all green.

If `getServerEnv()` throws `Invalid server environment configuration...`, check
for typos and that server-only values are not prefixed with `NEXT_PUBLIC_`.
