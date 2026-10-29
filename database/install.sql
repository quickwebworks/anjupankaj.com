-- ANJUPANKAJ.COM: RUN ONCE IN A NEW, EMPTY PROJECT ONLY.
begin;

-- anjupankaj.sql
-- Anju Pankaj import and publication schema. No existing tables are removed.
create table public.cms_admins (
 user_id uuid primary key references auth.users(id) on delete cascade,
 created_at timestamptz not null default now()
);
alter table public.cms_admins enable row level security;
revoke all on public.cms_admins from anon, authenticated;
grant select on public.cms_admins to authenticated;
create policy cms_admin_self on public.cms_admins for select to authenticated using (user_id=(select auth.uid()));
create table public.cms_posts (
 id uuid primary key default gen_random_uuid(),
 source_origin text not null check (source_origin ~ '^https?://[^/]+$'),
 source_id text not null,
 slug text not null,
 title text not null,
 excerpt text not null default '',
 content_html text not null default '',
 featured_image_url text check (featured_image_url is null or featured_image_url ~ '^https?://'),
 status text not null default 'draft' check (status in ('draft','pending','publish','private','future')),
 published_at timestamptz,
 imported_at timestamptz not null default now(),
 unique(source_origin,source_id)
);
create index cms_posts_public_feed on public.cms_posts (published_at desc,id) where status='publish';
create table public.cms_terms (
 id uuid primary key default gen_random_uuid(),
 kind text not null check (kind in ('category','tag')),
 name text not null,
 slug text not null,
 unique(kind,slug)
);
create table public.cms_post_terms (
 post_id uuid not null references public.cms_posts(id) on delete cascade,
 term_id uuid not null references public.cms_terms(id) on delete cascade,
 primary key(post_id,term_id)
);
create index cms_post_terms_reverse on public.cms_post_terms(term_id,post_id);
alter table public.cms_posts enable row level security;
alter table public.cms_terms enable row level security;
alter table public.cms_post_terms enable row level security;
revoke all on public.cms_posts,public.cms_terms,public.cms_post_terms from anon,authenticated;
grant select on public.cms_posts,public.cms_terms,public.cms_post_terms to anon,authenticated;
grant insert,update,delete on public.cms_posts,public.cms_terms,public.cms_post_terms to authenticated;
create policy cms_posts_public on public.cms_posts for select to anon,authenticated using(status='publish' and published_at<=now());
create policy cms_posts_admin on public.cms_posts for all to authenticated using(exists(select 1 from public.cms_admins where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));
create policy cms_terms_public on public.cms_terms for select to anon,authenticated using(exists(select 1 from public.cms_post_terms pt join public.cms_posts p on p.id=pt.post_id where pt.term_id=cms_terms.id and p.status='publish' and p.published_at<=now()));
create policy cms_terms_admin on public.cms_terms for all to authenticated using(exists(select 1 from public.cms_admins where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));
create policy cms_links_public on public.cms_post_terms for select to anon,authenticated using(exists(select 1 from public.cms_posts p where p.id=post_id and p.status='publish' and p.published_at<=now()));
create policy cms_links_admin on public.cms_post_terms for all to authenticated using(exists(select 1 from public.cms_admins where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));
create function public.cms_import_batch(source_origin text, records jsonb)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jsonb; t jsonb; post_uuid uuid; term_uuid uuid; k text; pub timestamptz; n integer:=0;
begin
 if not exists(select 1 from public.cms_admins where user_id=(select auth.uid())) then raise exception 'Admin access required' using errcode='42501'; end if;
 if source_origin !~ '^https?://[^/]+$' or jsonb_typeof(records)<>'array' or jsonb_array_length(records)>25 then raise exception 'Invalid origin or batch (maximum 25 posts)'; end if;
 for r in select value from jsonb_array_elements(records) loop
  if coalesce(r->>'source_id','')='' or coalesce(r->>'title','')='' then raise exception 'Source ID and title required'; end if;
  pub:=null;
  if coalesce(r->>'published_at_gmt','') not in ('','0000-00-00 00:00:00') then pub:=((r->>'published_at_gmt')::timestamp at time zone 'UTC');
  elsif coalesce(r->>'published_at_source','') not in ('','0000-00-00 00:00:00') then pub:=((r->>'published_at_source')::timestamp at time zone 'Asia/Kolkata'); end if;
  insert into public.cms_posts as target (source_origin,source_id,slug,title,excerpt,content_html,featured_image_url,status,published_at)
  values(source_origin,r->>'source_id',coalesce(nullif(r->>'slug',''),r->>'source_id'),r->>'title',coalesce(r->>'excerpt',''),coalesce(r->>'content_html',''),nullif(r->>'featured_image_url',''),case when r->>'status' in ('draft','pending','publish','private','future') then r->>'status' else 'draft' end,pub)
  on conflict on constraint cms_posts_source_origin_source_id_key do update set slug=excluded.slug,title=excluded.title,excerpt=excluded.excerpt,content_html=excluded.content_html,featured_image_url=excluded.featured_image_url,status=excluded.status,published_at=excluded.published_at,imported_at=now()
  returning id into post_uuid;
  delete from public.cms_post_terms where post_id=post_uuid;
  for t in select value from jsonb_array_elements(coalesce(r->'taxonomy','[]'::jsonb)) loop
   k:=case when t->>'type'='category' then 'category' when t->>'type'='post_tag' then 'tag' else null end;
   if k is null or coalesce(t->>'slug','')='' or coalesce(t->>'name','')='' then continue; end if;
   insert into public.cms_terms(kind,name,slug) values(k,t->>'name',t->>'slug') on conflict(kind,slug) do update set name=excluded.name returning id into term_uuid;
   insert into public.cms_post_terms(post_id,term_id) values(post_uuid,term_uuid) on conflict do nothing;
  end loop;
  n:=n+1;
 end loop;
 return jsonb_build_object('processed',n);
end; $$;
revoke all on function public.cms_import_batch(text,jsonb) from public,anon;
grant execute on function public.cms_import_batch(text,jsonb) to authenticated;


-- editor-ads.sql
alter table public.cms_posts add column seo_title text not null default '';
alter table public.cms_posts add column seo_description text not null default '';
alter table public.cms_posts add column updated_at timestamptz not null default now();
create function public.cms_save_post(document jsonb) returns uuid language plpgsql security invoker set search_path='' as $$
declare pid uuid; tid uuid; t jsonb; expected timestamptz; actual timestamptz;
begin
 if not exists(select 1 from public.cms_admins where user_id=(select auth.uid())) then raise exception 'Admin access required' using errcode='42501'; end if;
 if length(trim(coalesce(document->>'title','')))=0 or length(document->>'title')>500 then raise exception 'Title is required (maximum 500 characters)'; end if;
 if length(coalesce(document->>'content_html',''))>2000000 then raise exception 'Article exceeds 2 MB text limit'; end if;
 if document->>'status' not in ('draft','pending','publish','private','future') then raise exception 'Invalid publication status'; end if;
 if nullif(document->>'id','') is not null then
  pid:=(document->>'id')::uuid;
  select updated_at into actual from public.cms_posts where id=pid for update;
  if not found then raise exception 'Post not found'; end if;
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
  insert into public.cms_terms(kind,name,slug) values(t->>'kind',t->>'name',t->>'slug') on conflict(kind,slug) do update set name=excluded.name returning id into tid;
  insert into public.cms_post_terms(post_id,term_id) values(pid,tid) on conflict do nothing;
 end loop;
 return pid;
end; $$;
revoke all on function public.cms_save_post(jsonb) from public,anon;
grant execute on function public.cms_save_post(jsonb) to authenticated;
create table public.cms_ad_units(
 placement text primary key check(placement in ('lead_sidebar','feed','article_sidebar','article_inline')),
 name text not null,
 provider text not null default 'sample' check(provider in ('sample','direct','google_ad_manager')),
 enabled boolean not null default false,
 width integer not null default 300 check(width=300),
 height integer not null default 250 check(height=250),
 image_url text check(image_url is null or image_url ~ '^https://'),
 target_url text check(target_url is null or target_url ~ '^https://'),
 ad_unit_path text,
 label text not null default 'Advertisement',
 starts_at timestamptz,
 ends_at timestamptz,
 updated_at timestamptz not null default now(),
 check(ends_at is null or starts_at is null or ends_at>starts_at),
 check(provider<>'direct' or (image_url is not null and target_url is not null)),
 check(provider<>'google_ad_manager' or ad_unit_path ~ '^/[0-9]+/.+')
);
alter table public.cms_ad_units enable row level security;
revoke all on public.cms_ad_units from anon,authenticated;
grant select on public.cms_ad_units to anon,authenticated;
grant insert,update on public.cms_ad_units to authenticated;
create policy cms_ads_public on public.cms_ad_units for select to anon,authenticated using(enabled and (starts_at is null or starts_at<=now()) and (ends_at is null or ends_at>now()));
create policy cms_ads_admin on public.cms_ad_units for all to authenticated using(exists(select 1 from public.cms_admins where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));
insert into public.cms_ad_units(placement,name,provider,enabled) values('lead_sidebar','Homepage lead sidebar','sample',true),('feed','Between news rows','sample',true),('article_sidebar','Article sidebar','sample',true),('article_inline','Inside article content','sample',true);

create function public.cms_touch_post() returns trigger language plpgsql security invoker set search_path='' as $$ begin new.updated_at=now(); return new; end; $$;
revoke all on function public.cms_touch_post() from public,anon,authenticated;
create trigger cms_posts_track_update before update on public.cms_posts for each row execute function public.cms_touch_post();


-- google-tags.sql
create table public.cms_ad_tags(placement text primary key references public.cms_ad_units(placement) on delete cascade, header_code text not null default '' check(length(header_code)<=100000), body_code text not null default '' check(length(body_code)<=100000), updated_at timestamptz not null default now()); alter table public.cms_ad_tags enable row level security; revoke all on public.cms_ad_tags from anon,authenticated; grant select,insert,update on public.cms_ad_tags to authenticated; create policy cms_ad_tags_admin on public.cms_ad_tags for all to authenticated using(exists(select 1 from public.cms_admins where user_id=(select auth.uid()))) with check(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));

create function public.cms_save_ad_with_tags(payload jsonb, header text default '', body text default '') returns void language plpgsql security invoker set search_path='' as $$ begin if not exists(select 1 from public.cms_admins where user_id=(select auth.uid())) then raise exception 'Admin access required' using errcode='42501'; end if; if payload->>'provider'='google_ad_manager' and (length(trim(header))=0 or length(trim(body))=0) then raise exception 'Both header and body tags are required'; end if; insert into public.cms_ad_units(placement,name,provider,enabled,width,height,image_url,target_url,ad_unit_path,label,starts_at,ends_at,updated_at) values(payload->>'placement',payload->>'name',payload->>'provider',(payload->>'enabled')::boolean,300,250,nullif(payload->>'image_url',''),nullif(payload->>'target_url',''),nullif(payload->>'ad_unit_path',''),coalesce(nullif(payload->>'label',''),'Advertisement'),nullif(payload->>'starts_at','')::timestamptz,nullif(payload->>'ends_at','')::timestamptz,now()) on conflict(placement) do update set name=excluded.name,provider=excluded.provider,enabled=excluded.enabled,image_url=excluded.image_url,target_url=excluded.target_url,ad_unit_path=excluded.ad_unit_path,label=excluded.label,starts_at=excluded.starts_at,ends_at=excluded.ends_at,updated_at=now(); if payload->>'provider'='google_ad_manager' then insert into public.cms_ad_tags(placement,header_code,body_code,updated_at) values(payload->>'placement',header,body,now()) on conflict(placement) do update set header_code=excluded.header_code,body_code=excluded.body_code,updated_at=now(); end if; end; $$; revoke all on function public.cms_save_ad_with_tags(jsonb,text,text) from public,anon; grant execute on function public.cms_save_ad_with_tags(jsonb,text,text) to authenticated;


-- publication-menu.sql
alter table public.cms_terms add column if not exists menu_label text;
alter table public.cms_terms add column if not exists menu_position integer;
alter table public.cms_terms add column if not exists menu_group text;
insert into public.cms_terms(kind,name,slug,menu_label,menu_position,menu_group) values
('category','Local','local','Local',1,'main'),('category','Politics','politics','Politics',2,'main'),
('category','Society','society','Society',3,'main'),('category','Culture','culture','Culture',4,'main'),
('category','Opinion','opinion','Opinion',5,'main'),('category','India','india','India',6,'main') on conflict(kind,slug) do nothing;
alter policy cms_terms_public on public.cms_terms using(kind='category' or exists(select 1 from public.cms_post_terms pt join public.cms_posts p on p.id=pt.post_id where pt.term_id=cms_terms.id and p.status='publish' and p.published_at<=now()));


-- editor-role.sql
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


-- editor-activity.sql
-- Run after editor-role.sql. No old editor activity is invented/backfilled.

create schema if not exists cms_audit_private;
revoke all on schema cms_audit_private from public,anon,authenticated;
create table if not exists public.cms_editor_activity (
 id bigint generated always as identity primary key,
 actor_id uuid,
 actor_email text,
 post_id uuid not null,
 post_title text not null,
 action text not null check(action in ('created','updated','status_changed','deleted')),
 old_status text,
 new_status text,
 occurred_at timestamptz not null default now()
);
create index if not exists cms_editor_activity_time on public.cms_editor_activity(occurred_at desc,id desc);
alter table public.cms_editor_activity enable row level security;
revoke all on public.cms_editor_activity from public,anon,authenticated;
grant select on public.cms_editor_activity to authenticated;
drop policy if exists cms_activity_admin_read on public.cms_editor_activity;
create policy cms_activity_admin_read on public.cms_editor_activity for select to authenticated
 using(exists(select 1 from public.cms_admins where user_id=(select auth.uid())));
-- The private trigger is the only writer. Editors cannot forge or delete activity.
create or replace function cms_audit_private.record_post_activity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='DELETE' then
  insert into public.cms_editor_activity(actor_id,actor_email,post_id,post_title,action,old_status)
  values(auth.uid(),auth.jwt()->>'email',old.id,old.title,'deleted',old.status);
  return old;
 end if;
 insert into public.cms_editor_activity(actor_id,actor_email,post_id,post_title,action,old_status,new_status)
 values(auth.uid(),auth.jwt()->>'email',new.id,new.title,
 case when TG_OP='INSERT' then 'created' when old.status is distinct from new.status then 'status_changed' else 'updated' end,
 case when TG_OP='UPDATE' then old.status else null end,new.status);
 return new;
end; $$;
revoke all on function cms_audit_private.record_post_activity() from public,anon,authenticated;
drop trigger if exists cms_record_post_activity on public.cms_posts;
create trigger cms_record_post_activity after insert or update or delete on public.cms_posts
 for each row execute function cms_audit_private.record_post_activity();

-- Verify: save a test draft in the editor, then open Admin > Editor activity.

commit;
