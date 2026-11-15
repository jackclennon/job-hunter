-- Job Application Assistant: all tables, Row Level Security policies and functions.
-- Every table carries user_id referencing auth.users. Deleting the auth user
-- cascades to every row the user owns.

-- ---------------------------------------------------------------------------
-- profiles: one row per user
-- ---------------------------------------------------------------------------
create table public.profiles (
  user_id               uuid primary key references auth.users (id) on delete cascade,
  master_cv             text,
  location              text,
  distance_miles        integer not null default 20,
  search_terms          text[] not null default '{}',
  score_threshold       integer not null default 60,
  answers               jsonb not null default '{}'::jsonb,
  gmail_address         text,
  monthly_budget_usd    numeric not null default 5,
  dry_run               boolean not null default true,
  setup_complete        boolean not null default false,
  last_manual_fetch_at  timestamptz,
  constraint profiles_master_cv_length check (master_cv is null or char_length(master_cv) <= 20000),
  constraint profiles_search_terms_max check (cardinality(search_terms) <= 10),
  constraint profiles_score_threshold_range check (score_threshold between 0 and 100),
  constraint profiles_distance_nonnegative check (distance_miles >= 0),
  constraint profiles_budget_nonnegative check (monthly_budget_usd >= 0)
);

-- ---------------------------------------------------------------------------
-- user_secrets: one row per saved secret, encrypted by the Worker
-- ---------------------------------------------------------------------------
create table public.user_secrets (
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null,
  ciphertext  text not null,
  last4       text not null,
  updated_at  timestamptz not null default now(),
  primary key (user_id, name),
  constraint user_secrets_name check (
    name in ('anthropic_key', 'reed_key', 'adzuna_app_id', 'adzuna_app_key', 'gmail_refresh_token')
  )
);

-- ---------------------------------------------------------------------------
-- cv_files: one row per uploaded CV (file itself lives in storage bucket cvs)
-- ---------------------------------------------------------------------------
create table public.cv_files (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  label         text not null,
  use_for       text not null,
  storage_path  text not null
);
create index cv_files_user_id_idx on public.cv_files (user_id);

-- ---------------------------------------------------------------------------
-- jobs: one row per listing per user
-- ---------------------------------------------------------------------------
create table public.jobs (
  id                 bigint generated always as identity primary key,
  user_id            uuid not null references auth.users (id) on delete cascade,
  source             text not null,
  source_id          text not null,
  dedupe_key         text not null,
  title              text,
  employer           text,
  location           text,
  salary_min         numeric,
  salary_max         numeric,
  description        text,
  listing_url        text,
  apply_url          text,
  posted_at          timestamptz,
  expires_at         timestamptz,
  fetched_at         timestamptz not null default now(),
  score              integer,
  score_reason       text,
  cv_file_id         uuid references public.cv_files (id) on delete set null,
  application_type   text,
  application_email  text,
  status             text not null default 'new',
  status_changed_at  timestamptz not null default now(),
  constraint jobs_unique_listing unique (user_id, source, source_id),
  constraint jobs_source check (source in ('reed', 'adzuna')),
  constraint jobs_score_range check (score is null or score between 0 and 100),
  constraint jobs_application_type check (application_type is null or application_type in ('email', 'gated')),
  constraint jobs_status check (
    status in ('new', 'filtered_out', 'shortlisted', 'dismissed', 'selected', 'drafted', 'sent', 'applied')
  )
);
create index jobs_user_status_idx on public.jobs (user_id, status);
create index jobs_user_dedupe_idx on public.jobs (user_id, dedupe_key);

-- Keep status_changed_at in step with status.
create function public.jobs_touch_status_changed_at() returns trigger
language plpgsql as $$
begin
  if new.status is distinct from old.status then
    new.status_changed_at := now();
  end if;
  return new;
end;
$$;
create trigger jobs_status_changed
  before update on public.jobs
  for each row execute function public.jobs_touch_status_changed_at();

-- ---------------------------------------------------------------------------
-- drafts: at most one current row per job
-- ---------------------------------------------------------------------------
create table public.drafts (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  job_id        bigint not null references public.jobs (id) on delete cascade,
  subject       text,
  body          text not null,
  form_answers  jsonb,
  cv_file_id    uuid not null references public.cv_files (id),
  model         text not null,
  created_at    timestamptz not null default now(),
  edited_at     timestamptz,
  sent_at       timestamptz,
  message_id    text,
  constraint drafts_one_per_job unique (job_id)
);
create index drafts_user_id_idx on public.drafts (user_id);

-- ---------------------------------------------------------------------------
-- usage: one row per Claude call
-- ---------------------------------------------------------------------------
create table public.usage (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users (id) on delete cascade,
  at             timestamptz not null default now(),
  stage          text not null,
  model          text not null,
  input_tokens   integer not null,
  output_tokens  integer not null,
  cost_usd       numeric not null,
  constraint usage_stage check (stage in ('score', 'draft'))
);
create index usage_user_at_idx on public.usage (user_id, at);

-- ---------------------------------------------------------------------------
-- tasks: the queue for background work
-- ---------------------------------------------------------------------------
create table public.tasks (
  id           bigint generated always as identity primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  kind         text not null,
  payload      jsonb not null default '{}'::jsonb,
  status       text not null default 'pending',
  attempts     integer not null default 0,
  run_after    timestamptz not null default now(),
  started_at   timestamptz,
  finished_at  timestamptz,
  error        text,
  constraint tasks_kind check (kind in ('search', 'detail', 'score')),
  constraint tasks_status check (status in ('pending', 'running', 'done', 'failed'))
);
create index tasks_pending_idx on public.tasks (run_after) where status = 'pending';
create index tasks_running_idx on public.tasks (started_at) where status = 'running';

-- ---------------------------------------------------------------------------
-- Row Level Security
-- The Worker uses the service role key, which bypasses RLS; every Worker query
-- filters on the verified user id. RLS is the second layer.
-- ---------------------------------------------------------------------------
alter table public.profiles     enable row level security;
alter table public.user_secrets enable row level security;
alter table public.cv_files     enable row level security;
alter table public.jobs         enable row level security;
alter table public.drafts       enable row level security;
alter table public.usage        enable row level security;
alter table public.tasks        enable row level security;

create policy "Users read own profile"   on public.profiles for select to authenticated using (user_id = auth.uid());
create policy "Users read own CV files"  on public.cv_files for select to authenticated using (user_id = auth.uid());
create policy "Users read own jobs"      on public.jobs     for select to authenticated using (user_id = auth.uid());
create policy "Users read own drafts"    on public.drafts   for select to authenticated using (user_id = auth.uid());
create policy "Users read own usage"     on public.usage    for select to authenticated using (user_id = auth.uid());
-- user_secrets and tasks have no policies: only the Worker (service role) can read them.

-- ---------------------------------------------------------------------------
-- Functions (callable by the service role only)
-- ---------------------------------------------------------------------------

-- Health check for /api/health: returns exactly one row.
create function public.health() returns table (ok boolean, checked_at timestamptz)
language sql stable as $$
  select true, now();
$$;

-- Runner step 1: put tasks stuck in running for more than 15 minutes back to pending.
create function public.reset_stale_tasks() returns integer
language sql as $$
  with reset as (
    update public.tasks
       set status = 'pending', started_at = null
     where status = 'running'
       and started_at < now() - interval '15 minutes'
    returning 1
  )
  select count(*)::integer from reset;
$$;

-- Runner step 2: claim up to n pending tasks whose run_after has passed.
create function public.claim_tasks(n integer) returns setof public.tasks
language sql as $$
  update public.tasks t
     set status = 'running', started_at = now()
   where t.id in (
     select id from public.tasks
      where status = 'pending' and run_after <= now()
      order by run_after, id
      limit n
      for update skip locked
   )
  returning t.*;
$$;

-- Load one user's profile and secret rows in one request.
create function public.get_user_context(p_user_id uuid) returns jsonb
language sql stable as $$
  select jsonb_build_object(
    'profile', (select to_jsonb(p) from public.profiles p where p.user_id = p_user_id),
    'secrets', coalesce(
      (select jsonb_agg(jsonb_build_object('name', s.name, 'ciphertext', s.ciphertext))
         from public.user_secrets s where s.user_id = p_user_id),
      '[]'::jsonb)
  );
$$;

-- Postgres grants EXECUTE to PUBLIC by default, and Supabase also grants to
-- anon and authenticated. These functions bypass nothing themselves, but
-- claim_tasks and get_user_context must never be reachable from a browser.
revoke execute on function public.health()                       from public, anon, authenticated;
revoke execute on function public.reset_stale_tasks()            from public, anon, authenticated;
revoke execute on function public.claim_tasks(integer)           from public, anon, authenticated;
revoke execute on function public.get_user_context(uuid)         from public, anon, authenticated;
revoke execute on function public.jobs_touch_status_changed_at() from public, anon, authenticated;
grant  execute on function public.health()               to service_role;
grant  execute on function public.reset_stale_tasks()    to service_role;
grant  execute on function public.claim_tasks(integer)   to service_role;
grant  execute on function public.get_user_context(uuid) to service_role;
