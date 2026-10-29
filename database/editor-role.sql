create table public.cms_editors(user_id uuid primary key references auth.users(id) on delete cascade);
alter table public.cms_editors enable row level security;
revoke all on public.cms_editors from public,anon,authenticated;
grant select on public.cms_editors to authenticated;
create policy cms_editor_self on public.cms_editors for select to authenticated using(user_id=(select auth.uid()));
alter table public.cms_posts add column created_by uuid default auth.uid() references auth.users(id) on delete set null;
create index cms_posts_created_by_idx on public.cms_posts(created_by);
-- Old imported rows retain NULL ownership. No existing publication content is assigned.
create policy cms_posts_editor_read on public.cms_posts for select to authenticated using(created_by=(select auth.uid()) and exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create policy cms_posts_editor_insert on public.cms_posts for insert to authenticated with check(created_by=(select auth.uid()) and exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create policy cms_posts_editor_update on public.cms_posts for update to authenticated using(created_by=(select auth.uid()) and exists(select 1 from public.cms_editors where user_id=(select auth.uid()))) with check(created_by=(select auth.uid()) and exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create policy cms_terms_editor_read on public.cms_terms for select to authenticated using(exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create policy cms_tags_editor_insert on public.cms_terms for insert to authenticated with check(kind='tag' and exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create policy cms_links_editor on public.cms_post_terms for all to authenticated using(exists(select 1 from public.cms_posts p where p.id=post_id and p.created_by=(select auth.uid())) and exists(select 1 from public.cms_editors where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_posts p where p.id=post_id and p.created_by=(select auth.uid())) and exists(select 1 from public.cms_editors where user_id=(select auth.uid())));
create or replace function public.cms_save_post(document jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare pid uuid; tid uuid; t jsonb; expected timestamptz; actual timestamptz; owner_id uuid; admin_access boolean;
begin
 admin_access:=exists(select 1 from public.cms_admins where user_id=(select auth.uid()));
 if not admin_access and not exists(select 1 from public.cms_editors where user_id=(select auth.uid())) then raise exception 'Publication access required' using errcode='42501'; end if;
 if length(trim(coalesce(document->>'title','')))=0 or length(document->>'title')>500 then raise exception 'Title is required (maximum 500 characters)'; end if;
 if length(coalesce(document->>'content_html',''))>2000000 then raise exception 'Article exceeds 2 MB text limit'; end if;
 if document->>'status' not in ('draft','pending','publish','private','future') then raise exception 'Invalid publication status'; end if;
 if nullif(document->>'id','') is not null then
  pid:=(document->>'id')::uuid;
  select updated_at,created_by into actual,owner_id from public.cms_posts where id=pid for update;
  if not found then raise exception 'Post not found or not editable'; end if;
  if not admin_access and owner_id is distinct from (select auth.uid()) then raise exception 'Editors may only edit their own posts' using errcode='42501'; end if;
  expected:=(document->>'expected_updated_at')::timestamptz;
  if expected is null or expected<>actual then raise exception 'This post changed in another session. Reload before saving.'; end if;
  update public.cms_posts set title=document->>'title',slug=coalesce(nullif(document->>'slug',''),slug),excerpt=coalesce(document->>'excerpt',''),content_html=coalesce(document->>'content_html',''),featured_image_url=nullif(document->>'featured_image_url',''),status=document->>'status',published_at=nullif(document->>'published_at','')::timestamptz,seo_title=coalesce(document->>'seo_title',''),seo_description=coalesce(document->>'seo_description',''),updated_at=now() where id=pid;
 else
  pid:=gen_random_uuid();
  insert into public.cms_posts(id,source_origin,source_id,slug,title,excerpt,content_html,featured_image_url,status,published_at,seo_title,seo_description)
  values(pid,'https://anjupankaj.com','editor-'||pid,coalesce(nullif(document->>'slug',''),pid::text),document->>'title',coalesce(document->>'excerpt',''),coalesce(document->>'content_html',''),nullif(document->>'featured_image_url',''),document->>'status',nullif(document->>'published_at','')::timestamptz,coalesce(document->>'seo_title',''),coalesce(document->>'seo_description',''));
 end if;
 delete from public.cms_post_terms where post_id=pid;
 for t in select value from jsonb_array_elements(coalesce(document->'taxonomy','[]'::jsonb)) loop
  if t->>'kind' not in ('category','tag') or nullif(t->>'slug','') is null or nullif(t->>'name','') is null then continue; end if;
  if admin_access then
   insert into public.cms_terms(kind,name,slug) values(t->>'kind',t->>'name',t->>'slug') on conflict(kind,slug) do update set name=excluded.name returning id into tid;
  elsif t->>'kind'='category' then
   select id into tid from public.cms_terms where kind='category' and slug=t->>'slug';
   if tid is null then raise exception 'Editors must choose an existing category'; end if;
  else
   tid:=null;
   insert into public.cms_terms(kind,name,slug) values('tag',t->>'name',t->>'slug') on conflict(kind,slug) do nothing returning id into tid;
   if tid is null then select id into tid from public.cms_terms where kind='tag' and slug=t->>'slug'; end if;
  end if;
  insert into public.cms_post_terms(post_id,term_id) values(pid,tid) on conflict do nothing;
 end loop;
 return pid;
end; $$;
revoke all on function public.cms_save_post(jsonb) from public,anon;
grant execute on function public.cms_save_post(jsonb) to authenticated;
