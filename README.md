# AnjuPankaj.com — The Reporter’s Desk

A separate reporter news portal with an modern photo-led red-and-charcoal newsroom design, with a responsive mobile interface. This uses the same production architecture as the current EarlyNews24 site: a buildless HTML/CSS/JavaScript frontend, Supabase Postgres/Auth for the CMS, and an authenticated PHP image endpoint on Hostinger. It is not a Next.js project. No content, accounts, project keys or ads are shared with the other publications.

## Included
- Responsive app-style homepage, latest-three featured slider, scrolling headlines, category/tag pages, global search and article pages. Phones have sticky headers, horizontal category chips, photo-led latest-headline lists, a topic bottom sheet and fixed bottom navigation. Saved stories stay on the reader’s device using localStorage; no account is required.
- /admin/ publication administration: post editor, drafts/pending/published counts, taxonomy, 400 MB plain MySQL import, ad editing and editor post-activity records.
- /editor/ restricted workspace: users can enter and edit their own posts and choose existing categories. No import, advertisement or user administration access.
- 300 × 250 direct or Google Ad Manager placements, with validated ad-unit settings and diagnostics. Google reporting API integration is not included. No live paid ad unit is preconfigured.
- Hostinger-only uploads of JPEG, PNG, WebP and GIF up to 5 MB; no Supabase Storage bucket.

## Current state
The frontend is runnable and shows clearly marked illustrative sample stories while db-config.js is empty. Sample stories are never written to a database. Production database/authentication, Hostinger upload deployment and custom-domain routing are not active yet. The Supabase organization/project still needs to be selected. No default account or password exists.

## Repository layout
GitHub's root contains the contents of the local dist/ folder: index.html, portal.js, portal.css, admin/, editor/, assets/ and supporting scripts. database/, server/, docs/ and tests/ live alongside those files. Vercel uses outputDirectory '.'. The Sites source checkout keeps the public files in dist/.

## Run in free VS Code
Clone this repository, open the folder in VS Code and run `python -m http.server 8000`. Open http://localhost:8000/ and http://localhost:8000/admin/. No npm install, Prisma or build step is required. For the Sites source checkout, serve dist/ instead of the repository root.

## Connect services
Follow docs/SETUP.md. Use a dedicated new Supabase project, then install database/install.sql ONCE in that empty project. It sets up all application tables and permissions inside a transaction. Do not run this installer against either existing publication's project. Fill db-config.js with the new project's URL and public publishable key only. Hostinger images use media.anjupankaj.com; configure that subdomain and deploy server/hostinger separately from Vercel.

Only after connection should the owner create Supabase Auth users and explicitly grant cms_admins or cms_editors membership. No automatic import or sync from another publication is enabled.

Design-preview stock image sources and usage notes are in docs/IMAGE-CREDITS.md. Production photos remain Hostinger-only.
