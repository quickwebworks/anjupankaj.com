-- Run after editor-role.sql. No old editor activity is invented/backfilled.
begin;
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
commit;
-- Verify: save a test draft in the editor, then open Admin > Editor activity.
