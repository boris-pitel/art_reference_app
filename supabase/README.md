# Exact live Supabase export

This folder was exported from Supabase project `bbcgcrbvxmertipdjczu` on 2026-08-01. It replaces an earlier client-derived reconstruction.

## Exact contents

- `migrations/20260801000000_live_public_schema.sql`: exact `pg_dump` of the live `public` schema, including tables, sequences, constraints, indexes, grants, and default privileges.
- `migrations/20260801000001_live_configuration_data.sql`: exact built-in category rows and the two live private Storage bucket rows. Customer/user data is deliberately excluded.
- `config.toml`: the exact deployed Edge Function names and current `verify_jwt = false` settings.
- `functions/<name>/index.ts`: editable source extracted from each live Dashboard code editor.
- `deployed-artifacts/*.eszip`: compiled artifacts downloaded from every live Edge Function.
- `functions-manifest.json`: deployment versions, live runtime hashes, and local artifact hashes.

The live public schema currently contains five tables: `image_assets`, `image_categories`, `image_keywords`, `image_relationships`, and `reference_categories`. The public-schema dump contains no custom database functions, triggers, or RLS policies. The Storage schema contains no custom policies. Both `art-images` and `reference-images` are private and currently have no size or MIME restrictions.

## Recreate the database objects

Install Docker and the Supabase CLI. From the repository root:

```powershell
npx.cmd --yes supabase@latest start
npx.cmd --yes supabase@latest db reset
```

For a new hosted project:

```powershell
npx.cmd --yes supabase@latest login
npx.cmd --yes supabase@latest link --project-ref YOUR_NEW_PROJECT_REF
npx.cmd --yes supabase@latest db push
```

Configure Email authentication separately in the Supabase dashboard. Auth users and secrets are not database objects and are intentionally not exported to Git.

## Edge Functions

All 15 live `index.ts` files were extracted from the authenticated Supabase Dashboard code editors. They are suitable for normal source-based deployment:

```powershell
npx.cmd --yes supabase@latest functions deploy FUNCTION_NAME
```

The source references `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL`, and `OPENAI_API_KEY`. Supabase supplies the URL and service-role key in hosted functions; configure the database URL and OpenAI key as project secrets before recreating the deployment. Never commit real secret values.

## Refresh this export

```powershell
npx.cmd --yes supabase@latest link --project-ref bbcgcrbvxmertipdjczu
npx.cmd --yes supabase@latest db dump --linked --schema public --file supabase/migrations/LIVE_SCHEMA.sql
npx.cmd --yes supabase@latest functions list --project-ref bbcgcrbvxmertipdjczu --output json
```

Configuration rows should be refreshed separately so no user data is committed.

## App update announcements

Apply migrations before deploying `get-app-status`, `admin-maintenance`,
`list-app-announcements`, `announcement-email`, and
`unsubscribe-announcement`. Administrators can publish an in-app notice in
Maintenance and preview its email audience before sending. Notices remain in a
recent-notifications list after dismissal. The publisher can choose all users,
specific accounts, or iOS, Android, web, and Windows platforms. The active
banner and history use that audience. Specific-account email uses the same
accounts. Platform-targeted email is disabled until account-device membership
can be verified. Only confirmed account emails are eligible; the absence of a
preference row means update emails are enabled. Users can turn them off in
Account settings or through the email's unsubscribe link. Firebase App
Distribution testers are not included unless they also have a confirmed app
account.

Email delivery uses Resend. Set `RESEND_API_KEY`, a verified
`ANNOUNCEMENT_FROM_EMAIL` (normally `Painter Reference <support@painterreference.com>`),
and `ANNOUNCEMENT_POSTAL_ADDRESS` as Supabase Edge
Function secrets before sending. The admin preview reports whether the key
and postal address are present, but a test delivery is still needed to verify
the sending domain. No email is sent merely by publishing an in-app notice.
The email action sends at most 25 recipients per server request, records each
accepted delivery, and skips recipients already sent the same announcement.
Update notices must remain neutral service/version messages; use a separate
consent-based audience for promotions.
