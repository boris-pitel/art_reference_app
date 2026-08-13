import { createClient } from 'npm:@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error('Required Supabase environment variables are unavailable');
}

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type UnblockRequest = {
  user_id?: unknown;
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

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  const user = await requireUser(request);
  if (!user) {
    return jsonResponse({ error: 'You must be signed in.' }, 401);
  }

  let requestBody: UnblockRequest;
  try {
    requestBody = await request.json();
  } catch {
    return jsonResponse({ error: 'A valid JSON body is required' }, 400);
  }

  const blockedId = requestBody.user_id;
  if (typeof blockedId !== 'string' || blockedId.trim().length === 0) {
    return jsonResponse({ error: 'user_id is required' }, 400);
  }

  const { error } = await supabase
    .from('user_blocks')
    .delete()
    .eq('blocker_id', user.id)
    .eq('blocked_id', blockedId.trim());

  if (error) {
    console.error(error);
    return jsonResponse({ error: 'Unable to unblock this user.' }, 500);
  }

  return jsonResponse({ blocked: false }, 200);
});
