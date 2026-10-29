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
