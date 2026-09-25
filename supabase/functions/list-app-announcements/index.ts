import { createClient } from 'npm:@supabase/supabase-js@2';
import { isAnnouncementVisible } from '../_shared/announcement_audience.ts';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !key) return json({ error: 'Service unavailable' }, 503);
  const client = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  const { data: actor, error: authError } = token
    ? await client.auth.getUser(token)
    : { data: null, error: null };
  if (authError || !actor?.user) return json({ error: 'Sign in required' }, 401);
  const body = await request.json().catch(() => ({}));
  const platform = typeof body?.platform === 'string' ? body.platform : '';
  const isAdmin = actor.user.app_metadata?.is_admin === true;
  const { data, error } = await client.from('app_announcements')
    .select('id,title,message,published_at,audience_kind,target_user_ids,target_platforms')
    .order('published_at', { ascending: false }).limit(1000);
  if (error) return json({ error: 'Unable to load announcements' }, 500);
  const announcements = (data ?? []).filter((row) =>
    isAnnouncementVisible(row, actor.user.id, platform, isAdmin))
    .slice(0, 30).map(({ id, title, message, published_at }) =>
      ({ id, title, message, published_at }));
  return json({ announcements });
});