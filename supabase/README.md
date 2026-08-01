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
