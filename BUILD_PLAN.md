# Build plan

Source: the "Job Application Assistant — Build Spec" doc (rev 65, 15 November 2026).
The spec's 15 milestones are grouped into six sections. Each milestone must pass its
acceptance test before the next one starts.

| Section | Milestones | What it delivers | Status |
| --- | --- | --- | --- |
| 1. Foundation | 1 Skeleton, migrations, deployed Worker · 2 Free-plan risk checks | Repo, all tables, policies and functions, Worker serving the React app; proof that cron, a 1 MB Gmail attachment and a Claude call all work on the free plan | **M1 built and tested locally; deploy pending.** M2 not started |
| 2. Accounts and Settings | 3 Sign-in and token check · 4 Profile, master CV, CV files · 5 Secrets, encryption, Test buttons | Signed-in users, per-user query helper, the Settings page, encrypted keys | Not started |
| 3. Job pipeline | 6 Task queue, enqueue, runner, Reed search · 7 Adzuna, Reed details, de-duplication · 8 Scoring and classification | The daily background run that fills each user's shortlist | Not started |
| 4. User workflow | 9 Shortlist page · 10 Drafting · 11 Drafts page and hand-off modes | Select, draft, review, copy, mark as applied or sent | Not started |
| 5. Sending and budget | 12 Gmail connect and send, dry run · 13 Budget cap | Sending from the user's Gmail; spend limits | Not started |
| 6. History and isolation | 14 History page and account deletion · 15 Two-user isolation test | Clean account removal; automated proof users cannot see each other's data | Not started |

## Milestone 1 — what was done

Passes when: the deployed URL shows the Login page, and `/api/health` reads one row from Supabase.

- Folder layout as in the spec (`web/`, `worker/src/`, `supabase/migrations/`, `wrangler.jsonc`).
  Files for later milestones are added when those milestones start.
- `supabase/migrations/20261115000000_initial_schema.sql`: the seven tables, check constraints,
  RLS on every table, read-own-rows policies on `profiles`, `cv_files`, `jobs`, `drafts`, `usage`,
  none on `user_secrets` and `tasks`, and the functions `health()`, `reset_stale_tasks()`,
  `claim_tasks(n)` (`FOR UPDATE SKIP LOCKED`) and `get_user_context(user_id)`. Execute on these is
  revoked from `anon` and `authenticated`, so only the Worker can call them.
- `worker/src/index.ts`: Hono app under `/api`, `GET /api/health`, JSON 404 and 500 handlers, and a
  `scheduled` handler stub for the two Cron Triggers.
- `web/`: Vite + React + TypeScript; the Login page, signing in with supabase-js.

### Verified locally

- `npm run test:db`: applies the migration to a throwaway Postgres 16 with a stub of Supabase's
  `auth` schema and roles; 15 checks pass (defaults, unique keys, RLS isolation between two users,
  no browser access to `user_secrets`, `tasks`, `claim_tasks`, `get_user_context`, claim and reset
  behaviour, cascade on account deletion).
- `npm run typecheck` and `npm run build` pass.
- Under `wrangler dev`: `/` serves the Login page, `/shortlist` falls back to `index.html`,
  `/api/health` makes `POST /rest/v1/rpc/health` and returns 200 with the row, unknown `/api`
  paths return JSON 404, and `/cdn-cgi/handler/scheduled?cron=...` runs the scheduled handler.
  Supabase was stood in for by a local stub of its REST endpoint.

### Still needed to pass Milestone 1

The owner's setup steps (README) and one deploy. The build environment has no Cloudflare or
Supabase account and cannot reach their documentation sites, so the deploy and the live
`/api/health` check have not been run. Config keys were checked against the JSON schema shipped
in wrangler 4.162.0 instead of the online docs.

## Decisions from the owner

1. **Where the code lives:** in its own repository, `jackclennon/job-hunter`.
2. **Health check:** `/api/health` calls a `health()` function that returns one row, rather than
   reading a table, so the schema stays at the spec's seven tables. Approved.
3. **Deleting a CV file that a draft uses:** `drafts.cv_file_id` is required, so the database
   refuses the delete, and milestone 4 shows an "in use by a draft" error. Approved.

## Next step: owner setup

Follow "Owner setup" in the README, then run `npm run deploy` and open the deployed URL and
`/api/health`. When both work, milestone 1 is done and milestone 2 can start.
