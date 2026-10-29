-- Run in project lxocgmwtfnhtbwffsfos AFTER database/install.sql.
-- The UUID must belong to an existing Auth user in this same project.
do $$
begin
 if not exists(select 1 from auth.users where id='06d667e1-094f-4912-a94c-46fe9facba0e') then
  raise exception 'That user ID is not in this project. Create the owner in Authentication > Users and use its actual UUID.';
 end if;
 insert into public.cms_admins(user_id)
 values ('06d667e1-094f-4912-a94c-46fe9facba0e')
 on conflict do nothing;
end $$;
select exists(select 1 from public.cms_admins where user_id='06d667e1-094f-4912-a94c-46fe9facba0e') as admin_access_granted;
