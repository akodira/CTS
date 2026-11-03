# Deployment Guide

This guide is written for the project owner to perform the deployment themselves. Follow steps **B1–B7** in order. Do **not** claim success until the deployed URL has been opened and `/api/health` has been checked.

> **Status:** Phase 1 foundation only. No migrations have been executed against a live Supabase project yet and Playwright has not been run. Treat everything below as instructions, not confirmation.

## Prerequisites

- A GitHub account
- A Supabase account
- A Vercel account
- Access to your DNS/domain registrar (if using a custom domain)
- An email provider (Resend) or SMTP (only needed when Phase 5 email is enabled)

## B1: Install and verify local tooling

Do this on the machine you will use for Git pushes and CLI work.

### 1) Git
Install Git from [git-scm.com](https://git-scm.com/download/win). Verify:

```powershell
git --version
```

### 2) GitHub CLI (recommended)
Install [GitHub CLI](https://cli.github.com/). Authenticate:

```powershell
gh auth login
```

### 3) Node.js
Use Node.js 22.12–24 (project tested with 24.22.0; the `engines` range blocks Node 25+ so a new major cannot break the Vercel build). Verify:

```powershell
node --version
npm --version
```

### 4) Docker Desktop (for local Supabase)
Install [Docker Desktop](https://www.docker.com/products/docker-desktop/). Start it and ensure WSL2 is enabled on Windows. Verify:

```powershell
docker version
```

### 5) Supabase CLI
Install the [Supabase CLI](https://supabase.com/docs/guides/cli/getting-started). Verify:

```powershell
supabase --version
```

> If Docker is not running, `supabase start` will fail. That is expected; you can still proceed with remote Supabase projects.

## B2: Create GitHub repository, branches and protections

### 1) Initialize git (if not already)
From `E:\CTS-OpenCode`:

```powershell
git init
git add .
git commit -m "feat: initial CTS Phase 1 foundation"
```

### 2) Create the repository
Using GitHub CLI:

```powershell
gh repo create <your-org-or-user>/cts --private --source=. --remote=origin --push
```

Or create it on github.com and push:

```powershell
git branch -M main
git remote add origin https://github.com/<your-org-or-user>/cts.git
git push -u origin main
```

### 3) Create develop branch (recommended)
```powershell
git checkout -b develop
git push -u origin develop
```

### 4) Branch protections (recommended)
In GitHub → Settings → Branches, protect `main`:
- Require a pull request before merging
- Require status checks to pass (select `quality` from CI)
- Require conversation resolution
- Restrict who can push (optional)
- Include administrators as appropriate

Protect `develop` similarly if you use it for integration.

### 5) Environments for migrations
**Single-project mode (current):** you only need one Supabase project. Create a `production` GitHub Environment if you want to run `migrations.yml`, or skip GitHub Actions and use the Supabase CLI (B4 Option A). A separate `staging` project can be added later without changing the app.

If you later add staging: create a `staging` environment too, add the same three secrets, and require reviewers on `production`.

## B3: Create the Supabase project

**Current plan: one Supabase project only.** It acts as both development and production while the product is being built. Do not store real customer data until you add a separate staging project.

### 1) Create the project
In the [Supabase Dashboard](https://supabase.com/dashboard):
1. Create project `cts` (pick a strong database password; save it)
2. Note the **Project Reference** (`xxxxxxxxxxxxxxxxxxxx`)

> Optional later: create `cts-staging` and point Vercel Preview at it. Never point Preview at production once real data exists.

### 2) Get API keys
Project → Project Settings → API:
- **Project URL** (`https://<ref>.supabase.co`)
- **anon public key** (`eyJ...` or the new `sb_publishable_...` format if present)
- **service_role secret key** (`eyJ...` or `sb_secret_...`) — treat as highly sensitive

> Supabase may issue publishable/secret keys in newer projects. The code uses `NEXT_PUBLIC_SUPABASE_ANON_KEY` for the public key and `SUPABASE_SERVICE_ROLE_KEY` for the service role; use whichever format your project provides in those roles.

### 3) Auth URL configuration
Project → Authentication → URL Configuration:
- **Site URL**: your deployed URL (for example `https://cts.vercel.app`, or `http://localhost:3000` while testing locally)
- **Redirect URLs**: add `http://localhost:3000/auth/callback`, `https://*.vercel.app/auth/callback`, and your real domain when you add one

### 4) Email/Auth settings
Review Authentication → Providers and Email settings. Email confirmation is recommended before exposing registration publicly.

## B4: Link the project, apply migrations, configure Auth and Storage

### Option A: Use Supabase CLI locally (recommended)
From the repo root:

```powershell
supabase login
```

Link the project:
```powershell
supabase link --project-ref <project-ref>
```

Push migrations to the hosted project. **Supabase CLI v3 targets the local stack by default**, so `--remote` is required:
```powershell
supabase db push --remote --yes
```

Regenerate types (optional but useful):
```powershell
supabase gen types typescript --linked > src/types/database.types.ts
```

You only have one project, so run this once. If you add staging later, link and push to it separately.

### Option B: Use GitHub Actions (`migrations.yml`)
1. Add secrets to the `production` GitHub Environment:
   - `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_ID`, `SUPABASE_DB_PASSWORD`
2. Get a [Supabase Personal Access Token](https://supabase.com/dashboard/account/tokens)
3. Run **Actions → Database migrations → Run workflow**, choose `production`

> With one project, only choose `production`. The `staging` option is unused until you create a staging project.

### Verify migrations applied
Connect to the database (SQL Editor or `psql`) and run:

```sql
select count(*) from pg_tables where schemaname = 'public';        -- expect 37
select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity;   -- expect 37
select 'roles' item, count(*) from public.roles
union all select 'priorities', count(*) from public.priorities
union all select 'transitions', count(*) from public.ticket_transition_rules
union all select 'sla_policies', count(*) from public.sla_policies; -- expect 5,4,30,5
select id,name from public.sla_policies where is_default and is_active; -- one row
```

### Storage
Migration `20261101000009_storage_buckets.sql` creates the private `attachments` bucket (25 MiB, allow-listed MIME types). No storage policies are created. Until a download route with authorization exists, direct client access is not possible — this is intentional.

## B5: Import to Vercel, set environment variables, deploy

### 1) Import project
In [Vercel](https://vercel.com/):
1. Add New Project → Import Git Repository → select `cts`
2. Framework Preset: Next.js (auto-detected)
3. Root Directory: `./`
4. Build Command: `next build` (default)
5. Install Command: `npm ci` (default)

### 2) Environment variables
You have one Supabase project, so use the same values for Production and Preview for now. **Do not** store real customer data while Preview shares the production database.

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | `https://<project-ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon/publishable key |
| `NEXT_PUBLIC_APP_URL` | `https://<your-production-domain>` |
| `SUPABASE_SERVICE_ROLE_KEY` | service role/secret key (Sensitive) |
| `CRON_SECRET` | generate a strong random value |
| `LOG_LEVEL` | `info` |

When you add staging later, give Preview its own project/key values and keep Production separate.

### 3) Deploy
Deploy from `main` for production, or let Vercel create Preview deployments from PRs/branches. After deployment:
1. Open the deployed URL
2. Navigate to `/api/health` — expect `200 ok` with `checks.environment=true` and `checks.database=true` once Supabase is configured correctly
3. Navigate to `/en` and `/ar` — check RTL/LTR and locale switcher

> A green Vercel build does **not** mean the deployment works. You must test the live URL.

## B6: Cron, email domain and custom domain

### Cron (only when features exist)
Phase 1 has no cron routes. **Do not** configure cron yet.

When Phase 5 is ready:
- **Vercel Cron**: requires Pro for sub-daily schedules (Hobby allows daily only). A 5-minute SLA loop needs Pro or an alternative.
- **Supabase `pg_cron`**: can run SQL inside Supabase; notification/email dispatch may need an Edge Function. Independent of Vercel plan.
- Protect routes with `CRON_SECRET` and make them idempotent.

### Email (Resend)
When enabling transactional email:
1. Create a [Resend](https://resend.com/) account
2. Verify your domain (add DNS records) or use a verified sender
3. Add `RESEND_API_KEY` and `EMAIL_FROM` to Vercel environment variables
4. Ensure `NEXT_PUBLIC_APP_URL` is correct (links in emails)

### Custom domain
1. In Vercel → Project → Settings → Domains, add your domain
2. Configure DNS at your registrar (A/ALIAS/CNAME as instructed)
3. Update Supabase Auth Site URL and Redirect URLs to the custom domain
4. Update `NEXT_PUBLIC_APP_URL` to the custom domain
5. Re-deploy if needed and test

## B7: Verify, tag, and rollback

### Verification checklist
- [ ] Git repo created with `main`/`develop`, CI passing on a PR
- [ ] Supabase project created, all 10 migrations applied, verification queries pass
- [ ] Vercel deployment tested (`/api/health`, `/en`, `/ar`)
- [ ] Supabase Auth redirect URLs updated for localhost and the deployed URL
- [ ] Secrets stored securely (never in git)
- [ ] Branch protections enabled
- [ ] No secrets in build logs
- [ ] (Later) staging project created before real customer data is stored

### Tag a release
```powershell
git tag -a v0.1.0-phase1 -m "Phase 1 foundation"
git push origin v0.1.0-phase1
```

### Rollback
**Database:** Migrations are forward-only. Do not try to "undo" SQL. Options:
- Restore from a Supabase backup/PITR (if available on your plan)
- Deploy a forward-fix migration that corrects the issue
- Revert the application deployment in Vercel to a previous build

**Application:** In Vercel → Deployments, promote the last known good deployment to Production, or redeploy a previous commit.

**Environment variables:** Revert changed env vars in Vercel and redeploy.

> Test rollback in a copy or in staging once a staging project exists.

## Troubleshooting

| Issue | Cause | Fix |
| --- | --- | --- |
| `supabase start` fails | Docker not running | Start Docker Desktop, retry |
| Migrations fail on remote | Wrong project linked/password | Check `supabase link` and DB password; use `migrations.yml` with correct secrets |
| `/api/health` returns `503 unconfigured` | Missing env vars | Check Vercel env vars for the environment |
| `/api/health` returns `503 error` | Wrong URL/key or RLS/network | Verify Supabase URL/key, check Supabase project status |
| Build fails on Vercel | Missing placeholders or type errors | Ensure CI passes locally; check build logs |
| Auth callback fails | Redirect URL not whitelisted | Add the exact URL to Supabase Auth → Redirect URLs |
| Locale redirects oddly | Proxy config | Check `src/proxy.ts` matcher excludes `/api` and `/auth` |

## Notes

- The SQL assumes Supabase roles (`anon`, `authenticated`, `service_role`) and `auth.users`/`storage.buckets`. It will not run on plain PostgreSQL.
- `email_outbox` has RLS enabled with no policies/grants — only the service role can access it.
- Management viewers cannot read tickets by design (intentional gap until Phase 6).
- ESLint uses v10 with transitive plugins that still declare peer ranges up to v9 (see KNOWN_ISSUES).
- Playwright browsers are not installed; run `npx playwright install chromium` locally before `npm run test:e2e`.
