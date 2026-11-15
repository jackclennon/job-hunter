-- Spec change, 16 November 2026: the owner's Adzuna key is shared by up to 6 users.
-- 6 users x 4 terms x 30 days = 720 calls a month, leaving room under the ~1,000 free
-- allowance for the Fetch new jobs button. Keep in step with MAX_SEARCH_TERMS in config.ts.
update public.profiles set search_terms = search_terms[1:4] where cardinality(search_terms) > 4;
alter table public.profiles drop constraint profiles_search_terms_max;
alter table public.profiles add constraint profiles_search_terms_max check (cardinality(search_terms) <= 4);
