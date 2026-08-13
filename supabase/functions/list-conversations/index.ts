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

  const { data: conversations, error: conversationsError } = await supabase
    .from('conversations')
    .select('id,user_a_id,user_b_id,last_message_at')
    .or(`user_a_id.eq.${user.id},user_b_id.eq.${user.id}`)
    .order('last_message_at', { ascending: false });

  if (conversationsError) {
    console.error(conversationsError);
    return jsonResponse({ error: 'Unable to load conversations.' }, 500);
  }

  if (!conversations || conversations.length === 0) {
    return jsonResponse({ conversations: [] }, 200);
  }

  const otherUserIds = conversations.map((c) =>
    c.user_a_id === user.id ? c.user_b_id : c.user_a_id
  );

  const [profilesResult, ...perConversation] = await Promise.all([
    supabase
      .from('user_profiles')
      .select('auth_user_id,login_name')
      .in('auth_user_id', otherUserIds),
    ...conversations.map((c) =>
      Promise.all([
        supabase
          .from('messages')
          .select('body,image_storage_path,created_at')
          .eq('conversation_id', c.id)
          .order('created_at', { ascending: false })
          .limit(1)
          .maybeSingle(),
        supabase
          .from('messages')
          .select('id', { count: 'exact', head: true })
          .eq('conversation_id', c.id)
          .neq('sender_id', user.id)
          .is('read_at', null),
      ])
    ),
  ]);

  if (profilesResult.error) {
    console.error(profilesResult.error);
    return jsonResponse({ error: 'Unable to load conversations.' }, 500);
  }

  const loginNameByUserId = new Map(
    (profilesResult.data ?? []).map((row) => [row.auth_user_id, row.login_name]),
  );

  const result = conversations.map((c, index) => {
    const otherUserId = c.user_a_id === user.id ? c.user_b_id : c.user_a_id;
    const [lastMessageResult, unreadCountResult] = perConversation[index];
    const lastMessage = lastMessageResult.data;

    return {
      conversation_id: c.id,
      other_user_id: otherUserId,
      other_login_name: loginNameByUserId.get(otherUserId) ?? null,
      last_message_preview: lastMessage
        ? (lastMessage.body ?? (lastMessage.image_storage_path ? 'Sent an image' : ''))
        : null,
      last_message_at: lastMessage?.created_at ?? c.last_message_at,
      unread_count: unreadCountResult.count ?? 0,
    };
  });

  return jsonResponse({ conversations: result }, 200);
});
