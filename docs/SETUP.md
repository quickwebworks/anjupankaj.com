# AnjuPankaj.com setup

## 1. New Supabase project
Use a separate Supabase project for this publication. The connected account currently exposes the Social Optical organization; the user has not selected the organization for the new project yet. Creating a project may involve plan limits or costs. Do not substitute the Socialoptical or EarlyNews24 database.

After the new project is ready:
1. Open its SQL Editor and run database/install.sql once in the empty project. This is the combined installer for the individual database scripts in this repository. It does not create photo buckets or import sample posts.
2. Copy that project's URL and publishable key into the `url` and `key` fields of db-config.js. Never put a service-role key, database password or Hostinger password there.
3. Create the owner's user through Supabase Authentication > Users. Use the actual UUID from that same project to grant access:

```sql
insert into public.cms_admins(user_id)
values ('ACTUAL_USER_UUID_FROM_THIS_NEW_PROJECT')
on conflict do nothing;
```

For a separate editor-only account, create its Auth user in the same project and grant cms_editors instead:

```sql
insert into public.cms_editors(user_id)
values ('ACTUAL_EDITOR_UUID_FROM_THIS_NEW_PROJECT')
on conflict do nothing;
```

There is no default email or password. Never reuse another project's UUID. After configuring the frontend, /admin/ and /editor/ use email and password. RLS enforces the role and editors' ownership restrictions. Supabase Auth public self-signup should be disabled if accounts are invitation-only.

## 2. Hostinger photos
Create media.anjupankaj.com on your Hostinger hosting with its own document root. This can be in the same hosting account as your other sites, but must be a separate media directory so the publications do not mix uploads. Point its DNS to the Hostinger hosting target supplied in that account, and enable HTTPS. Do not copy the website's Vercel DNS target into the media record.

Deploy these files into that subdomain's document root:
- server/hostinger/cms-upload.php -> cms-upload.php
- server/hostinger/cms-config.php -> cms-config.php
- server/hostinger/cms-uploads/.htaccess -> cms-uploads/.htaccess

Fill cms-config.php with the SAME new Supabase URL and public publishable key used by the frontend. It is a PHP config returning an array; no secret key is required. PHP 8.1+, cURL and fileinfo are required. Set upload_max_filesize >=5M and post_max_size >=6M. Use files 644 and folders 755 with PHP write access, not 777. Preserve Authorization headers in the server configuration.

The endpoint validates the bearer token against Supabase Auth and checks cms_admins/cms_editors under RLS before accepting a file. File content/MIME and image dimensions are checked; filenames are random and existing photos are never overwritten. Successful uploads return URLs such as https://media.anjupankaj.com/cms-uploads/YYYY/MM/random-name.webp. Photos stay on Hostinger. Supabase stores only those URLs along with the post content.

The CORS allowlist contains https://anjupankaj.com, https://www.anjupankaj.com and the exact private Sites preview origin. Localhost is intentionally not an upload origin. A direct unauthenticated upload must return 401; an unapproved origin returns 403. The allowed browser preflight returns 204. This backend has not been deployed to Hostinger by this task.

## 3. GitHub and Vercel
Repository: https://github.com/quickwebworks/anjupankaj.com
Import this repository as a NEW Vercel project. vercel.json configures a static site, no build command, and output directory '.'. Attach anjupankaj.com and www.anjupankaj.com to this new project and copy the exact DNS values Vercel shows for each hostname. Preserve existing email MX, SPF and DKIM records. Vercel serves the website; the media subdomain stays on Hostinger. Custom-domain routing is not configured by this task.

## 4. Acceptance check
1. Sign in as the owner, create a draft and confirm the Overview draft count increases.
2. Upload a small featured photo; verify its URL starts with https://media.anjupankaj.com/cms-uploads/ and opens.
3. Choose a category, add tags, publish the post, then open its public link and check homepage/search/category/tag views.
4. Open Admin > Editor activity to verify the post creation/status change and user identity.
5. Sign in using an editor-only account and verify it cannot edit another editor's posts, manage ads, import SQL or read the admin-only activity log.
6. Verify signed-out users cannot read drafts or invoke write RPCs. Check Supabase Security Advisors after installation.

## Limits
Posts deleted or changed in other publications do not sync into this one. Ad Manager reporting and live campaign setup require their own configuration. The illustrated preview articles are design samples only. Database writes, owner login and uploads cannot be end-to-end verified until the new Supabase project and Hostinger endpoint are configured.
