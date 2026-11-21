# JARVIS — Website + Command Center (Najimul Islam Ahmed)
Files: `index.html` (public site, user dashboard) · `admin.html` (admin command center, also served at /admin on Vercel) · `vercel.json` · `supabase/`.
## Connect to Supabase (project bgjrxpjedynxpzgdvmgm — URL and publishable key are already inside both HTML files)
1. Supabase > SQL Editor > paste `supabase/setup_all.sql` > Run (creates tables, RLS, storage buckets, functions). Run it ONCE (includes v2-v5).
2. Authentication > Providers > Email: keep sign-in on; turn off public sign-ups if you do not want open registration. Authentication > URL Configuration: add your site URL.
3. Open the site, Register your account, then run in SQL Editor: `update profiles set role='admin' where email='YOUR_EMAIL';`
4. Open `admin.html` (or /admin) and sign in. Add a release, features, content.
5. Optional voice: see below.
## Deploy (Vercel): drag this folder into Vercel as a static site. No build step, no secrets in the files.
## Voice (ElevenLabs) — key stays on the server
Deploy `supabase/functions/jarvis-voice/index.ts` with Verify JWT OFF (`supabase functions deploy jarvis-voice --no-verify-jwt`), then add secrets `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID`. Status line under the preview chat shows the exact error if something is missing.
## Security notes
Never put the service_role key or ElevenLabs key into HTML. All admin actions are enforced by RLS/server functions, not by the page.

## Roles
`admin` = everything. `editor` = website content only (features, video, changelog, text/images). Assign in Admin > Users. Use "Set latest" in Releases to pin the version shown on the site.

## Downloads require an account
Guests who press Download are sent to the login/register page; after signing in they land on their dashboard with the download button. Enforced server-side by a storage policy (upgrade_v5.sql).
