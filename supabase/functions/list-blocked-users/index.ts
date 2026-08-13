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

  const { data: blocks, error: blocksError } = await supabase
    .from('user_blocks')
    .select('blocked_id,created_at')
    .eq('blocker_id', user.id)
    .order('created_at', { ascending: false });

  if (blocksError) {
    console.error(blocksError);
    return jsonResponse({ error: 'Unable to load blocked users.' }, 500);
  }

  if (!blocks || blocks.length === 0) {
    return jsonResponse({ users: [] }, 200);
  }

  const { data: profiles, error: profilesError } = await supabase
    .from('user_profiles')
    .select('auth_user_id,login_name')
    .in(
      'auth_user_id',
      blocks.map((b) => b.blocked_id),
    );

  if (profilesError) {
    console.error(profilesError);
    return jsonResponse({ error: 'Unable to load blocked users.' }, 500);
  }

  const loginNameByUserId = new Map(
    (profiles ?? []).map((row) => [row.auth_user_id, row.login_name]),
  );

  return jsonResponse(
    {
      users: blocks.map((b) => ({
        id: b.blocked_id,
        login_name: loginNameByUserId.get(b.blocked_id) ?? null,
        blocked_at: b.created_at,
      })),
    },
    200,
  );
});
