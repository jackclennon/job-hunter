-- Spec change, 16 November 2026: the owner's Anthropic, Reed and Adzuna keys are
-- used for every user, held as Worker secrets. user_secrets now holds only each
-- user's Gmail refresh token.
delete from public.user_secrets where name <> 'gmail_refresh_token';

alter table public.user_secrets drop constraint user_secrets_name;
alter table public.user_secrets add constraint user_secrets_name check (name = 'gmail_refresh_token');

comment on column public.profiles.monthly_budget_usd is
  'Set by the owner in the Supabase dashboard. The API never lets a user change it, because Claude calls are paid with the owner''s key.';
