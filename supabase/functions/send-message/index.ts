import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error('Required Supabase environment variables are unavailable');
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const bucketName = 'message-images';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type SendRequest = {
  recipient_id?: unknown;
  body?: unknown;
  image_storage_path?: unknown;
};

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

async function requireUser(request: Request) {
  const authorization = request.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) return null;
  return data.user;
}

function statusForErrorCode(code: string | undefined): number {
  switch (code) {
    case 'P0001':
    case 'P0002':
      return 400;
    case 'P0003':
    case 'P0004':
      return 403;
    default:
      return 500;
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  const user = await requireUser(request);
  if (!user) {
    return jsonResponse({ error: 'You must be signed in.' }, 401);
  }

  let requestBody: SendRequest;
  try {
    requestBody = await request.json();
  } catch {
    return jsonResponse({ error: 'A valid JSON body is required' }, 400);
  }

  const recipientId = requestBody.recipient_id;
  if (typeof recipientId !== 'string' || recipientId.trim().length === 0) {
    return jsonResponse({ error: 'recipient_id is required' }, 400);
  }

  const rawBody = requestBody.body;
  const messageBody =
    typeof rawBody === 'string' && rawBody.trim().length > 0
      ? rawBody.trim()
      : null;

  const rawImagePath = requestBody.image_storage_path;
  const imageStoragePath =
    typeof rawImagePath === 'string' && rawImagePath.trim().length > 0
      ? rawImagePath.trim()
      : null;

  if (messageBody === null && imageStoragePath === null) {
    return jsonResponse({ error: 'A message needs text or an image.' }, 400);
  }

  if (messageBody !== null && messageBody.length > 2000) {
    return jsonResponse({ error: 'Messages must be 2000 characters or fewer.' }, 400);
  }

  if (imageStoragePath !== null && !imageStoragePath.startsWith(`${user.id}/`)) {
    return jsonResponse({ error: 'That image was not uploaded by you.' }, 403);
  }

  const { data, error } = await supabase.rpc('send_message', {
    p_sender_id: user.id,
    p_recipient_id: recipientId.trim(),
    p_body: messageBody,
    p_image_storage_path: imageStoragePath,
  });

  if (error) {
    console.error(error);
    return jsonResponse({ error: error.message }, statusForErrorCode(error.code));
  }

  const row = Array.isArray(data) ? data[0] : data;

  let imageUrl: string | null = null;
  if (imageStoragePath) {
    const { data: signedUrl } = await supabase.storage
      .from(bucketName)
      .createSignedUrl(imageStoragePath, 3600);
    imageUrl = signedUrl?.signedUrl ?? null;
  }

  return jsonResponse(
    {
      message_id: row.message_id,
      conversation_id: row.conversation_id,
      created_at: row.created_at,
      image_url: imageUrl,
    },
    200,
  );
});
