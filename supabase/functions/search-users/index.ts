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

  const url = new URL(request.url);
  const query = (url.searchParams.get('q') ?? '').trim();

  if (query.length === 0) {
    return jsonResponse({ users: [] }, 200);
  }

  const [blockedByMe, blockingMe] = await Promise.all([
    supabase.from('user_blocks').select('blocked_id').eq('blocker_id', user.id),
    supabase.from('user_blocks').select('blocker_id').eq('blocked_id', user.id),
  ]);

  if (blockedByMe.error || blockingMe.error) {
    console.error(blockedByMe.error ?? blockingMe.error);
    return jsonResponse({ error: 'Unable to search users.' }, 500);
  }

  const excludedIds = new Set<string>([user.id]);
  for (const row of blockedByMe.data ?? []) excludedIds.add(row.blocked_id);
  for (const row of blockingMe.data ?? []) excludedIds.add(row.blocker_id);

  let builder = supabase
    .from('user_profiles')
    .select('auth_user_id,login_name')
    .eq('is_discoverable', true)
    .not('login_name', 'is', null)
    .ilike('login_name', `%${query}%`)
    .order('login_name', { ascending: true })
    .limit(20);

  for (const id of excludedIds) {
    builder = builder.neq('auth_user_id', id);
  }

  const { data, error } = await builder;

  if (error) {
    console.error(error);
    return jsonResponse({ error: 'Unable to search users.' }, 500);
  }

  return jsonResponse(
    {
      users: (data ?? []).map((row) => ({
        id: row.auth_user_id,
        login_name: row.login_name,
      })),
    },
    200,
  );
});
