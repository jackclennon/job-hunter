# Job Application Assistant

Hosted web app for a few invited users: finds jobs daily, lets each user pick the ones
worth applying to, drafts applications with Claude from their own CV, and sends or hands
off each one after a confirming click. Cloudflare Worker (Hono) + Svelte (Vite) + Supabase.
Claude, Reed and Adzuna are called with the owner's keys, shared by every user.

Progress and open questions: [BUILD_PLAN.md](BUILD_PLAN.md).

## Owner setup, before the first deploy

1. Create a Supabase project and turn off "Allow new users to sign up".
2. Create a private storage bucket named `cvs`.
3. Apply `supabase/migrations/*.sql` (SQL editor, or `supabase db push`).
4. Create a Cloudflare account and run `npx wrangler login`.
5. Set up the Google Cloud project (see the spec's Gmail connection section; needed from milestone 12).
6. Set the Worker secrets:

```bash
npx wrangler secret put SUPABASE_URL
```

```bash
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
```

```bash
openssl rand -base64 32   # value for SECRETS_KEY
```

```bash
npx wrangler secret put SECRETS_KEY
```

```bash
npx wrangler secret put GOOGLE_CLIENT_ID
```

```bash
npx wrangler secret put GOOGLE_CLIENT_SECRET
```

```bash
npx wrangler secret put ANTHROPIC_API_KEY
```

```bash
npx wrangler secret put REED_API_KEY
```

```bash
npx wrangler secret put ADZUNA_APP_ID
```

```bash
npx wrangler secret put ADZUNA_APP_KEY
```

7. Fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in `web/.env.local` (committed: both are
   public). Never put the service role key there.
8. Create each user in the Supabase dashboard with a temporary password.
9. Set each user's `profiles.monthly_budget_usd` in the Supabase table editor (default $5). Users
   cannot change it, because their Claude calls are paid with your key.

## Commands

```bash
npm install
```

```bash
npm run test:db     # migrations + RLS checks against a throwaway local Postgres
```

```bash
npm run typecheck
```

```bash
npm run dev         # builds the web app, then wrangler dev on :8787 (needs .dev.vars, see .dev.vars.example)
```

```bash
npm run deploy      # builds the web app and deploys the Worker
```

Test a Cron Trigger locally while `npm run dev` runs:

```bash
curl "http://localhost:8787/cdn-cgi/handler/scheduled?cron=*/2+*+*+*+*"
```

Cloudflare does not enforce free-plan limits in local development, so any test that
mentions a limit must run against the deployed Worker.
