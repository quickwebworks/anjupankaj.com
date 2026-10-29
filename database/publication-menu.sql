alter table public.cms_terms add column if not exists menu_label text;
alter table public.cms_terms add column if not exists menu_position integer;
alter table public.cms_terms add column if not exists menu_group text;
insert into public.cms_terms(kind,name,slug,menu_label,menu_position,menu_group) values
('category','Local','local','Local',1,'main'),('category','Politics','politics','Politics',2,'main'),
('category','Society','society','Society',3,'main'),('category','Culture','culture','Culture',4,'main'),
('category','Opinion','opinion','Opinion',5,'main'),('category','India','india','India',6,'main') on conflict(kind,slug) do nothing;
alter policy cms_terms_public on public.cms_terms using(kind='category' or exists(select 1 from public.cms_post_terms pt join public.cms_posts p on p.id=pt.post_id where pt.term_id=cms_terms.id and p.status='publish' and p.published_at<=now()));
