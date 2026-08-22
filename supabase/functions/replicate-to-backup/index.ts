import { createClient } from 'npm:@supabase/supabase-js@2';

import {
  r2ConfigFromEnv,
  r2Delete,
  r2Get,
  r2Head,
  r2Put,
} from '../_shared/r2.ts';

/// Copies one stored file to the backup bucket as soon as its row appears.
///
/// Driven by a database webhook on image_assets rather than a schedule, so a
/// newly uploaded image is protected within seconds instead of at the next
/// sweep. The row is written by finalize-image-upload only after the file is
/// already in storage, so by the time this runs the object exists.
///
/// Deletes are deliberately soft. Propagating a delete immediately would make
/// the backup mirror the mistake it exists to undo — an accidental removal, a
/// bad migration, a compromised account — so the object is moved under
/// deleted/ and swept up later instead.
///
/// This is best effort by design: pg_net does not retry, so some events will
/// be missed. The sweep in reconcile-backup is what turns "usually replicated"
/// into "verifiably replicated"; without it, drift here would be silent.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const adminClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false } },
);

const SOURCE_BUCKET = 'reference-images';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// The backup key mirrors the source layout, prefixed by bucket, so a restore
/// is a straight copy back rather than a mapping exercise.
function backupKey(bucket: string, path: string): string {
  return `${bucket}/${path}`;
}

async function copyToBackup(
  config: NonNullable<ReturnType<typeof r2ConfigFromEnv>>,
  path: string,
): Promise<'copied' | 'already-held' | 'missing'> {
  const { data, error } = await adminClient.storage
    .from(SOURCE_BUCKET)
    .download(path);

  if (error || !data) return 'missing';

  const bytes = new Uint8Array(await data.arrayBuffer());
  const key = backupKey(SOURCE_BUCKET, path);

  // Skipping an object already held at the same size keeps a retried webhook
  // cheap, and makes this safe to call repeatedly.
  const existing = await r2Head(config, key);
  if (existing && existing.size === bytes.length) return 'already-held';

  await r2Put(config, key, bytes, data.type || 'application/octet-stream');

  return 'copied';
}

async function softDelete(
  config: NonNullable<ReturnType<typeof r2ConfigFromEnv>>,
  path: string,
): Promise<'retired' | 'not-held'> {
  const key = backupKey(SOURCE_BUCKET, path);
  const existing = await r2Head(config, key);

  if (!existing) return 'not-held';

  const body = await adminClient.storage.from(SOURCE_BUCKET).download(path);

  // The source file is usually gone by now, so the copy already in the backup
  // is what gets moved. Read it back rather than the source.
  const held = body.data
    ? new Uint8Array(await body.data.arrayBuffer())
    : await r2Get(config, key);

  if (!held) return 'not-held';

  const stamp = new Date().toISOString().slice(0, 10);
  await r2Put(config, `deleted/${stamp}/${key}`, held);
  await r2Delete(config, key);

  return 'retired';
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  const config = r2ConfigFromEnv();

  if (!config) {
    // Loud rather than quiet: without credentials nothing is being backed up,
    // and that must not look like success.
    console.error('R2 credentials are not configured');
    return jsonResponse({ error: 'Backup destination is not configured' }, 500);
  }

  let payload: Record<string, unknown>;

  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: 'Expected a JSON body' }, 400);
  }

  const type = String(payload.type ?? '');
  const record = (payload.record ?? {}) as Record<string, unknown>;
  const oldRecord = (payload.old_record ?? {}) as Record<string, unknown>;

  const paths = (source: Record<string, unknown>) =>
    ['storage_path', 'thumbnail_storage_path']
      .map((field) => source[field])
      .filter((value): value is string =>
        typeof value === 'string' && value.length > 0
      );

  try {
    const results: Record<string, string> = {};

    if (type === 'INSERT' || type === 'UPDATE') {
      // A forged insert can only cause an image that already belongs in the
      // backup to be copied there, so this path needs no authentication.
      for (const path of paths(record)) {
        results[path] = await copyToBackup(config, path);
      }
    } else if (type === 'DELETE') {
      // Retiring a backup object is the one destructive thing here, so it is
      // checked against the database rather than trusted: the row must
      // actually be gone. A forged delete for a live image is refused, which
      // makes a shared secret unnecessary — the check is against the truth
      // rather than against a token that could leak.
      for (const path of paths(oldRecord)) {
        const { data: stillPresent } = await adminClient
          .from('image_assets')
          .select('id')
          .or(
            `storage_path.eq.${path},thumbnail_storage_path.eq.${path}`,
          )
          .limit(1)
          .maybeSingle();

        results[path] = stillPresent
          ? 'refused-row-still-exists'
          : await softDelete(config, path);
      }
    } else {
      return jsonResponse({ error: `Unsupported event type: ${type}` }, 400);
    }

    return jsonResponse({ ok: true, results });
  } catch (error) {
    console.error('replicate-to-backup failed:', error);

    return jsonResponse({ error: `${error}` }, 500);
  }
});
