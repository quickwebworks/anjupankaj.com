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
