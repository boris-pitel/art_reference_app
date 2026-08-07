# Painter Reference Admin for Windows

A local Windows desktop application for privileged Painter Reference administration. It uses the same Supabase operations and `.env.admin` configuration as the `painter-admin` CLI.

## Security model

- The Supabase secret/service-role key remains only on the administrator computer.
- `.env.admin` and `.admin-audit/` are ignored by Git.
- Passwords and secret keys are never written to the audit log.
- Permanent deletion requires typing the exact user email confirmation.
- Keep the CLI available as an emergency fallback.

Do not distribute this application together with `.env.admin`. Anyone who has the secret key can bypass Row Level Security.

## Configuration

Create `.env.admin` in the repository root or beside the executable:

```text
SUPABASE_URL=https://PROJECT_REF.supabase.co
SUPABASE_SECRET_KEY=sb_secret_...
SUPABASE_PASSWORD_REDIRECT_URL=https://painterreference.com
```

The redirect setting is optional. The URL must also be allowed in Supabase Authentication redirect settings.

The application searches for `.env.admin` beside the working directory and
executable, then walks up enough parent folders to find the repository root
from a packaged Windows Release directory. Process environment variables
override file values.

## Run for development

From the repository root:

```powershell
cd admin_console
flutter run -d windows
```

## Build the Windows release

```powershell
cd admin_console
flutter build windows --release
```

The release directory is:

```text
admin_console/build/windows/x64/runner/Release/
```

Copy the complete `Release` directory when moving the application. Do not copy only the `.exe`, because Flutter plugins and runtime DLLs are stored beside it.

## Features

- List and search registered users.
- Inspect Auth IDs, image/category counts, and Storage inventory.
- Send a password recovery email.
- Directly set a password of 12 or more characters.
- Permanently delete a user, database records, and stored files after typed confirmation.
- List and filter feedback.
- View feedback details and temporary private attachment URLs.
- Change feedback status.
- Review the shared local audit log.

## Backend prerequisite

The database migration below must already be applied before account deletion:

```text
supabase/migrations/20260803000000_admin_delete_user_data.sql
```

Feedback administration requires:

```text
supabase/migrations/20260803010000_user_feedback.sql
```
