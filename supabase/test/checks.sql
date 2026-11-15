\set ON_ERROR_STOP on
\set QUIET on
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@example.com'),
  ('00000000-0000-0000-0000-00000000000b', 'b@example.com');

-- Defaults on a new profile
insert into profiles (user_id) values ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
select 'profile defaults' as check,
  (dry_run and not setup_complete and score_threshold = 60 and distance_miles = 20 and monthly_budget_usd = 5) as pass
  from profiles where user_id = '00000000-0000-0000-0000-00000000000a';

insert into jobs (user_id, source, source_id, dedupe_key, title) values
  ('00000000-0000-0000-0000-00000000000a', 'reed', '1', 'packer acme', 'Packer'),
  ('00000000-0000-0000-0000-00000000000b', 'reed', '1', 'packer acme', 'Packer');
insert into jobs (user_id, source, source_id, dedupe_key) values
  ('00000000-0000-0000-0000-00000000000a', 'reed', '1', 'x') on conflict do nothing;
select 'unique (user_id, source, source_id)' as check, count(*) = 2 as pass from jobs;

-- status_changed_at trigger
update jobs set status_changed_at = now() - interval '1 day' where source_id = '1';
update jobs set status = 'shortlisted' where user_id = '00000000-0000-0000-0000-00000000000a';
select 'status_changed_at updates' as check, status_changed_at > now() - interval '1 minute' as pass
  from jobs where user_id = '00000000-0000-0000-0000-00000000000a';

insert into user_secrets (user_id, name, ciphertext, last4) values
  ('00000000-0000-0000-0000-00000000000a', 'anthropic_key', 'ct', '1234');
insert into tasks (user_id, kind, payload) values
  ('00000000-0000-0000-0000-00000000000a', 'search', '{"term":"packer","source":"reed"}'),
  ('00000000-0000-0000-0000-00000000000a', 'search', '{"term":"picker","source":"reed"}'),
  ('00000000-0000-0000-0000-00000000000a', 'search', '{"term":"driver","source":"reed"}');
insert into tasks (user_id, kind, run_after) values ('00000000-0000-0000-0000-00000000000a', 'score', now() + interval '1 hour');

-- RLS as user A
set role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false); end $$;
select 'RLS: A sees only own jobs' as check, count(*) = 1 as pass from jobs;
select 'RLS: A sees only own profile' as check, count(*) = 1 as pass from profiles;
select 'RLS: no access to user_secrets' as check, count(*) = 0 as pass from user_secrets;
select 'RLS: no access to tasks' as check, count(*) = 0 as pass from tasks;
do $$ begin
  perform claim_tasks(1);
  raise exception 'authenticated could call claim_tasks';
exception when insufficient_privilege then null; end $$;
select 'authenticated cannot call claim_tasks' as check, true as pass;
do $$ begin
  perform get_user_context('00000000-0000-0000-0000-00000000000a');
  raise exception 'authenticated could call get_user_context';
exception when insufficient_privilege then null; end $$;
select 'authenticated cannot call get_user_context' as check, true as pass;
reset role;

-- Functions as service role
set role service_role;
select 'health returns one row' as check, count(*) = 1 as pass from health();
select 'claim_tasks(2) claims 2' as check, count(*) = 2 as pass from claim_tasks(2);
select 'claim_tasks skips future run_after' as check, count(*) = 1 as pass from claim_tasks(10);
update tasks set started_at = now() - interval '20 minutes' where status = 'running' and payload->>'term' = 'packer';
select 'reset_stale_tasks resets 1' as check, reset_stale_tasks() = 1 as pass;
select 'get_user_context has profile + 1 secret' as check,
  (c->'profile'->>'user_id') = '00000000-0000-0000-0000-00000000000a' and jsonb_array_length(c->'secrets') = 1 as pass
  from get_user_context('00000000-0000-0000-0000-00000000000a') c;
reset role;

-- Cascade on account deletion
delete from auth.users where id = '00000000-0000-0000-0000-00000000000a';
select 'delete cascades, B untouched' as check,
  (select count(*) from jobs) = 1 and (select count(*) from tasks) = 0
  and (select count(*) from profiles) = 1 and (select count(*) from user_secrets) = 0 as pass;
