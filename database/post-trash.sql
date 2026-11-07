-- Recoverable post trash. Keeps content, images, categories and tags.
-- Run once in this publication's Supabase SQL Editor. Safe to rerun.
begin;
alter table public.cms_posts drop constraint if exists cms_posts_status_check;
alter table public.cms_posts add constraint cms_posts_status_check
 check (status in ('draft','pending','publish','private','future','trash'));
commit;
-- Existing public RLS only exposes published posts. Ownership/admin policies remain unchanged.
select pg_get_constraintdef(oid) from pg_constraint
 where conrelid='public.cms_posts'::regclass and conname='cms_posts_status_check';
