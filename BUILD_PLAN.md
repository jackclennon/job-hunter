# Build plan

Source: the "Job Application Assistant — Build Spec" doc (rev 65, 15 November 2026).
The spec's 15 milestones are grouped into six sections. Each milestone must pass its
acceptance test before the next one starts.

| Section | Milestones | What it delivers | Status |
| --- | --- | --- | --- |
| 1. Foundation | 1 Skeleton, migrations, deployed Worker · 2 Free-plan risk checks | Repo, all tables, policies and functions, Worker serving the Svelte app; proof that cron, a 1 MB Gmail attachment and a Claude call all work on the free plan | **M1 deployed by the owner.** M2 not started |
| 2. Accounts and Settings | 3 Sign-in and token check · 4 Profile, master CV, CV files · 5 Gmail token encryption, owner key checks | Signed-in users, per-user query helper, the Settings page | Not started |
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
- `web/`: Vite + Svelte 5 + TypeScript; the Login page, signing in with supabase-js.

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

## Spec changes from the owner, 16 November 2026

These override the spec doc wherever they conflict.

**Owner's API keys for everyone.** Users no longer bring their own keys.
- The Anthropic, Reed and Adzuna keys are Worker secrets: `ANTHROPIC_API_KEY`, `REED_API_KEY`,
  `ADZUNA_APP_ID`, `ADZUNA_APP_KEY`.
- `user_secrets` holds only each user's `gmail_refresh_token`
  (migration `20261116000000_owner_api_keys.sql`).
- The Settings page loses its API keys section and its Test buttons for Anthropic, Reed and
  Adzuna. The email Test button stays. Key checks become a part of milestone 5 the owner runs.
- `setup_complete` needs a master CV, at least one CV file and at least one search term.
- `monthly_budget_usd` is set by the owner in the Supabase dashboard. Users cannot change it.
  The Settings page shows it read-only.
- The daily run searches each source for every user who has finished setup, as before, now with
  the owner's keys.
- Milestone 5 becomes: Gmail token encryption (the only stored secret), plus a check that no
  API response contains a key.

**At most 4 search terms per user** (was 10), sized for up to 6 users sharing the owner's
Adzuna key: 6 × 4 × 30 = 720 calls a month, under the ~1,000 free allowance (a third-party
figure), leaving about 280 for the Fetch new jobs button. Migration
`20261116000100_max_four_search_terms.sql`.

**Stage 2 redesigned: cheap checks first, Claude reads only the relevant paragraphs.**
Replaces the spec's Stage 2 and its scoring prompt. Status: agreed with the owner.

*Once per CV: extract a candidate profile.* When the user saves their master CV, the Worker
makes one Claude call that returns `profiles.cv_terms` (jsonb):

```json
{
  "experience":          [{ "term": "warehouse operative", "synonyms": ["picker", "packer"] }],
  "education":           [{ "term": "GCSE English", "synonyms": [] }],
  "transferable_skills": [{ "term": "stock control", "synonyms": ["inventory", "stock management"] }],
  "licences_and_certificates": [{ "term": "counterbalance forklift", "synonyms": ["FLT", "forklift"] }]
}
```

Settings shows the terms so the user can correct them; the user's edits are saved over the
extracted list. Re-extraction runs only when the master CV changes, and is logged in `usage`
with stage `profile`. Terms must come from the CV only, like every other fact.

*Stage 2, in order, stopping at the first step that decides the job:*

| Step | Claude? | What it does | Outcome when it fails |
| --- | --- | --- | --- |
| a. Duplicate | No | As in the spec (`dedupe_key`) | `filtered_out`, reason `duplicate` |
| b. Hard checks | No | The checks in the table below | `filtered_out`, reason names the check |
| c. Keyword match | No | Split the advert into paragraphs (blank lines, bullets, or sentences for an Adzuna snippet). Match every term and synonym from `cv_terms` as a whole-word, case-insensitive regex. Keep the title plus the 3 best-matching paragraphs, capped at 1,500 characters, plus any paragraph containing an email address | Zero matches: `filtered_out`, reason `no matching terms`, no Claude call |
| d. Fit check | Yes, Haiku | Claude gets the title, the kept paragraphs, `cv_terms` and the list of CV files, never the full CV or full advert. Returns `score`, `reason`, `cv_file_id`, `application_email` in the spec's JSON shape | Below threshold: `filtered_out` |

The email/gated rule is unchanged: `email` only when the returned address appears verbatim in
the advert. Addresses are found by regex in step c, so the paragraph holding one always reaches
Claude.

*Hard checks.* Only two, plus expiry. A job is rejected only when the advert says the thing is
required: the match and a word such as `essential`, `must`, `required`, `need` or `necessary`
in the same sentence, and no `desirable`, `preferred`, `advantage` or `ideally` there. The
title counts as a requirement (a "Delivery Driver" needs a licence). Rejected jobs stay visible
under Show filtered out, with the reason, and can be moved to the shortlist.

| # | Check | Advert pattern (case-insensitive) | Candidate fact |
| --- | --- | --- | --- |
| 1 | Driving licence | `driv(ing\|er'?s) licen[cs]e`, `full (uk\|clean) licen[cs]e`, `licen[cs]ed driver`, title matching `\bdriver\b` or `\bcourier\b` | `profiles.has_full_driving_licence` is false |
| 2 | Degree | `degree` with `required\|essential\|must` | No degree-level item in `education` |
| 3 | Expired | `expires_at` in the past | — |

Data changes this needs, in the milestone 8 migration: `profiles.cv_terms jsonb`,
`profiles.cv_terms_updated_at`, `usage.stage` allows `profile`, and
`profiles.has_full_driving_licence boolean not null default false` (a yes/no in Settings).

Estimated cost for 6 users: the fit check sends about 1,000 tokens in instead of 4,000–5,000,
and steps a–c should remove a share of jobs before any call. Scoring falls from about $4–9 to
about $1–2 a month. Profile extraction is a few cents per CV change. Drafting is unchanged at
about $5–13, because it still needs the full CV to stay truthful.

Risks: plain regex misses wording that is not in the term list ("despatch" vs "dispatch"),
so synonyms matter and users should check them; Adzuna gives only a snippet, so hard checks see
less there and miss more; requirement detection is per sentence and will sometimes misread an
advert, which is why rejections stay visible with a reason.

Owner's answers, 16 November 2026: a yes/no "full driving licence" is enough; adverts with
zero matching terms are rejected without Claude; only the driving licence and degree checks
(plus expiry) are kept.

**Svelte instead of React.** The front end is Svelte 5 with Vite and TypeScript, as a
single-page app, built to static files and served by the Worker as before. No SvelteKit.

## Decisions from the owner

1. **Where the code lives:** in its own repository, `jackclennon/job-hunter`.
2. **Health check:** `/api/health` calls a `health()` function that returns one row, rather than
   reading a table, so the schema stays at the spec's seven tables. Approved.
3. **Deleting a CV file that a draft uses:** `drafts.cv_file_id` is required, so the database
   refuses the delete, and milestone 4 shows an "in use by a draft" error. Approved.

## Next step: owner setup

Follow "Owner setup" in the README, then run `npm run deploy` and open the deployed URL and
`/api/health`. When both work, milestone 1 is done and milestone 2 can start.
