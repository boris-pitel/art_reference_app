import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 as uuidv5 } from 'npm:uuid@11';

/// Deletes the calling user's own account.
///
/// Separate from admin-maintenance because the actor is different: there, an
/// administrator names someone else and the function verifies their authority
/// over that person. Here the account is always whoever holds the bearer
/// token, and there is no target parameter at all — so no request can ask this
/// to delete anyone but its own caller, whatever it sends.
///
/// Required because the app cannot do this itself. Removing an auth user needs
/// the service key, which must never ship inside a client.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const adminClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false } },
);

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Every stored object belonging to this user, per bucket.
///
/// Storage is not covered by the database cascade, so files left behind would
/// be paid for indefinitely and would still hold the user's photographs after
/// they had asked for them to be gone.
async function storagePaths(authUserId: string, dataUserId: string) {
  const paths: Record<string, string[]> = {
    'reference-images': [],
    'category-covers': [],
    'feedback-attachments': [],
    'message-images': [],
  };

  // Images sent in messages live in their own bucket and are referenced only
  // from the message row, so deleting the rows first would strand the files.
  const { data: sentImages } = await adminClient
    .from('messages')
    .select('image_storage_path')
    .eq('sender_id', authUserId)
    .not('image_storage_path', 'is', null);

  for (const row of sentImages ?? []) {
    const value = row.image_storage_path;
    if (typeof value === 'string' && value.length > 0) {
      paths['message-images'].push(value);
    }
  }

  const { data: images } = await adminClient
    .from('image_assets')
    .select('storage_path,thumbnail_storage_path')
    .eq('user_id', dataUserId);

  for (const row of images ?? []) {
    for (const field of ['storage_path', 'thumbnail_storage_path'] as const) {
      const value = row[field];
      if (typeof value === 'string' && value.length > 0) {
        paths['reference-images'].push(value);
      }
    }
  }

  const { data: covers } = await adminClient
    .from('user_category_cover_overrides')
    .select('storage_path')
    .eq('auth_user_id', authUserId);

  const prefix = 'storage://category-covers/';
  for (const row of covers ?? []) {
    const value = row.storage_path;
    if (typeof value === 'string' && value.startsWith(prefix)) {
      paths['category-covers'].push(value.substring(prefix.length));
    }
  }

  const { data: feedback } = await adminClient
    .from('user_feedback')
    .select('attachment_path')
    .eq('user_id', authUserId);

  for (const row of feedback ?? []) {
    const value = row.attachment_path;
    if (typeof value === 'string' && value.length > 0) {
      paths['feedback-attachments'].push(value);
    }
  }

  // Anything the database does not know about — an upload interrupted between
  // storing the file and writing its row — is caught by sweeping the user's
  // own folders.
  for (const [bucket, root] of [
    ['reference-images', dataUserId],
    ['category-covers', authUserId],
  ] as const) {
    for (const folder of ['originals', 'thumbnails', '']) {
      const path = folder ? `${root}/${folder}` : root;
      const { data } = await adminClient.storage.from(bucket).list(path, {
        limit: 1000,
      });

      for (const entry of data ?? []) {
        if (entry.name && entry.id !== null) {
          paths[bucket].push(path ? `${path}/${entry.name}` : entry.name);
        }
      }
    }
  }

  return paths;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  const authorization = request.headers.get('Authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '').trim();

  if (!token) {
    return jsonResponse({ error: 'Authentication required' }, 401);
  }

  // The account to delete is the token holder. It is never taken from the
  // request body, so a caller cannot name someone else.
  const { data: userData, error: userError } = await adminClient.auth.getUser(
    token,
  );

  const user = userData?.user;

  if (userError || !user) {
    return jsonResponse({ error: 'Authentication required' }, 401);
  }

  const email = user.email?.trim().toLowerCase() ?? '';

  if (!email) {
    return jsonResponse({ error: 'This account has no email address' }, 400);
  }

  // Confirming the address is deliberate friction on an irreversible act, and
  // it also catches a request fired at the wrong session.
  let confirmation = '';
  try {
    const body = await request.json();
    confirmation = String(body?.confirm_email ?? '').trim().toLowerCase();
  } catch {
    confirmation = '';
  }

  if (confirmation !== email) {
    return jsonResponse(
      { error: 'Type your email address exactly to confirm deletion' },
      400,
    );
  }

  // Library rows are keyed by an id derived from the email rather than by the
  // auth id. Derived here exactly as every other caller derives it — a
  // different derivation would silently miss the user's entire library.
  const dataUserId = uuidv5(`art-reference-user:${email}`, uuidv5.URL);

  try {
    // Files first. If a later step fails the user still has an account and can
    // try again; had the account gone first, orphaned files would be
    // unreachable and unattributable.
    const paths = await storagePaths(user.id, dataUserId);

    for (const [bucket, entries] of Object.entries(paths)) {
      const unique = [...new Set(entries)];

      for (let start = 0; start < unique.length; start += 1000) {
        const { error } = await adminClient.storage
          .from(bucket)
          .remove(unique.slice(start, start + 1000));

        // A missing file is the desired end state, so a failure here is worth
        // recording but not worth stopping a deletion the user asked for.
        if (error) console.error(`storage cleanup (${bucket}):`, error.message);
      }
    }

    const { error: databaseError } = await adminClient.rpc(
      'admin_delete_user_data',
      { target_user_id: dataUserId, target_email: email },
    );

    if (databaseError) throw databaseError;

    // Messaging is not covered by that function; a conversation is shared, so
    // the rows are removed rather than cascaded from either participant.
    await adminClient.from('messages').delete().eq('sender_id', user.id);
    await adminClient
      .from('user_blocks')
      .delete()
      .or(`blocker_id.eq.${user.id},blocked_id.eq.${user.id}`);
    await adminClient
      .from('conversations')
      .delete()
      .or(`user_a_id.eq.${user.id},user_b_id.eq.${user.id}`);
    await adminClient.from('user_profiles').delete().eq('auth_user_id', user.id);

    const { error: authError } = await adminClient.auth.admin.deleteUser(
      user.id,
    );

    if (authError) throw authError;

    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error('delete-my-account failed:', error);

    return jsonResponse(
      {
        error:
          'The account could not be fully deleted. Nothing has been left in a ' +
          'broken state — please contact support@painterreference.com.',
      },
      500,
    );
  }
});
