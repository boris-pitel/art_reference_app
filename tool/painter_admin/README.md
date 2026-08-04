# Painter Reference administration console

This local command-line tool performs privileged Supabase administration for Painter Reference. Run it only from a trusted administrator computer. It uses a Supabase secret/service-role key, which bypasses Row Level Security.

## Source layout

- `painter_admin.dart` — command dispatcher
- `src/admin_service.dart` — Auth, database, and Storage operations
- `src/admin_config.dart` — environment-only credential loading
- `src/console_io.dart` — prompts and hidden password input
- `src/audit_log.dart` — secret-free local JSONL audit trail
- `../../supabase/migrations/20260803000000_admin_delete_user_data.sql` — service-role-only transactional database cleanup

## Configure credentials

Retrieve the project URL and a secret key from the Supabase project settings. Prefer a current `sb_secret_...` key; the legacy service-role JWT is also supported. Never paste either key into a tracked file.

Copy `.env.admin.example` to `.env.admin` and insert the real values. Both launchers automatically load `.env.admin`, and Git ignores it.

Alternatively, set the process environment directly.

PowerShell:

```powershell
$env:SUPABASE_URL = 'https://PROJECT_REF.supabase.co'
$env:SUPABASE_SECRET_KEY = 'sb_secret_...'
```

macOS/Linux:

```bash
export SUPABASE_URL='https://PROJECT_REF.supabase.co'
export SUPABASE_SECRET_KEY='sb_secret_...'
```

Optional recovery-email redirect:

```powershell
$env:SUPABASE_PASSWORD_REDIRECT_URL = 'https://painterreference.com'
```

The URL must be present in Supabase Authentication's allowed redirect URLs. A recovery link also requires the destination application to provide a password-update screen.

## Deploy the cleanup migration

Before using `users remove`, link the Supabase CLI to the correct project and apply migrations:

```powershell
supabase link --project-ref PROJECT_REF
supabase db push
```

If the Supabase CLI is not installed, open the Supabase SQL Editor and run `supabase/migrations/20260803000000_admin_delete_user_data.sql` once. The migration grants the cleanup function only to `service_role`.

## Commands

On Windows:

```powershell
.\painter-admin.ps1 users list
.\painter-admin.ps1 users show user@example.com
.\painter-admin.ps1 users remove user@example.com --dry-run
.\painter-admin.ps1 users remove user@example.com
.\painter-admin.ps1 users password-reset user@example.com
.\painter-admin.ps1 users set-password user@example.com
```

On macOS/Linux:

```bash
chmod +x painter-admin
./painter-admin users list
./painter-admin users show user@example.com
./painter-admin users remove user@example.com --dry-run
```

`users remove` inventories data first and requires typing `REMOVE user@example.com` exactly. It removes database rows, files in `reference-images`, legacy `art-images`, category covers, and finally the Auth user. Supabase JWTs already issued to a deleted user can remain valid until they expire.

`users set-password` requires an exact warning confirmation and reads the password twice with terminal echo disabled. Passwords must contain at least 12 characters and are never logged.

## Audit trail

Mutating commands append JSON records to `.admin-audit/painter-admin.jsonl`. Git ignores this directory. The audit log records who ran the command, the target, counts, time, and result; it never records passwords or credentials.

## Safety

- Do not put secret keys on the command line; shell history may retain them.
- Start with `users show` or `users remove EMAIL --dry-run`.
- Confirm the target project and email before a permanent removal.
- Keep database backups appropriate to your retention policy.
## Feedback administration

Apply `supabase/migrations/20260803010000_user_feedback.sql` before releasing the
feedback screen. It creates the private table, Row Level Security policies, and
the private `feedback-attachments` bucket.

```powershell
.\painter-admin.ps1 feedback list
.\painter-admin.ps1 feedback list --status new
.\painter-admin.ps1 feedback show FEEDBACK_ID
.\painter-admin.ps1 feedback status FEEDBACK_ID reviewed
.\painter-admin.ps1 feedback status FEEDBACK_ID planned
.\painter-admin.ps1 feedback status FEEDBACK_ID resolved
```

`feedback show` prints a one-hour signed URL when the user attached a
screenshot. Changing status requires typing the exact confirmation shown by the
console and is recorded in the local audit trail.
