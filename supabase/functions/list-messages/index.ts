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
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (request.method !== 'GET') {
    return jsonResponse({ error: 'GET required' }, 405);
  }

  const user = await requireUser(request);
  if (!user) {
    return jsonResponse({ error: 'You must be signed in.' }, 401);
  }

  const url = new URL(request.url);
  const conversationId = (url.searchParams.get('conversation_id') ?? '').trim();

  if (conversationId.length === 0) {
    return jsonResponse({ error: 'conversation_id is required' }, 400);
  }

  const { data: conversation, error: conversationError } = await supabase
    .from('conversations')
    .select('id,user_a_id,user_b_id')
    .eq('id', conversationId)
    .maybeSingle();

  if (conversationError) {
    console.error(conversationError);
    return jsonResponse({ error: 'Unable to load messages.' }, 500);
  }

  if (
    !conversation ||
    (conversation.user_a_id !== user.id && conversation.user_b_id !== user.id)
  ) {
    return jsonResponse({ error: 'Conversation not found.' }, 404);
  }

  const { data: messages, error: messagesError } = await supabase
    .from('messages')
    .select('id,sender_id,body,image_storage_path,created_at,read_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true });

  if (messagesError) {
    console.error(messagesError);
    return jsonResponse({ error: 'Unable to load messages.' }, 500);
  }

  const imagePaths = (messages ?? [])
    .map((m) => m.image_storage_path)
    .filter((path): path is string => typeof path === 'string' && path.length > 0);

  let imageUrlByPath = new Map<string, string>();
  if (imagePaths.length > 0) {
    const { data: signedUrls, error: signedUrlsError } = await supabase.storage
      .from(bucketName)
      .createSignedUrls(imagePaths, 3600);

    if (signedUrlsError) {
      console.error(signedUrlsError);
      return jsonResponse({ error: 'Unable to load message images.' }, 500);
    }

    imageUrlByPath = new Map(
      (signedUrls ?? [])
        .filter((entry) => !entry.error && entry.signedUrl)
        .map((entry) => [entry.path ?? '', entry.signedUrl]),
    );
  }

  return jsonResponse(
    {
      messages: (messages ?? []).map((m) => ({
        id: m.id,
        sender_id: m.sender_id,
        body: m.body,
        image_url: m.image_storage_path
          ? imageUrlByPath.get(m.image_storage_path) ?? null
          : null,
        created_at: m.created_at,
        read_at: m.read_at,
        is_mine: m.sender_id === user.id,
      })),
    },
    200,
  );
});
