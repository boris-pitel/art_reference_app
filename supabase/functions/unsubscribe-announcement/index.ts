import { createClient } from 'npm:@supabase/supabase-js@2';

const client = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false, autoRefreshToken: false } },
);

function page(message: string, form = '') {
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1">` +
    `<title>Painter Reference email updates</title>` +
    `<body style="font:16px system-ui;max-width:520px;margin:3rem auto;padding:1rem">` +
    `<h1>Painter Reference</h1><p>${message}</p>${form}</body></html>`, {
      headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' },
    });
}

Deno.serve(async (request) => {
  const requestUrl = new URL(request.url);
  let token = requestUrl.searchParams.get('token') ?? '';
  if (request.method === 'POST') {
    try {
      token = String((await request.formData()).get('token') ?? '');
    } catch {
      return page('Unable to read your request. Please try the link in your email.');
    }
  }
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token)) {
    return page('This unsubscribe link is invalid. Contact support@painterreference.com for help.');
  }
  if (request.method === 'GET') {
    return page('Stop receiving Painter Reference app update emails?',
      `<form method="post"><input type="hidden" name="token" value="${token}">` +
      `<button style="padding:.75rem 1rem" type="submit">Unsubscribe</button></form>`);
  }
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const { error } = await client.from('announcement_email_preferences')
    .update({ updates_enabled: false, updated_at: new Date().toISOString() })
    .eq('unsubscribe_token', token);
  if (error) {
    console.error('Unable to unsubscribe', error);
    return page('We could not save your choice. Please try again or email support@painterreference.com.');
  }
  return page('You have been unsubscribed from app update emails.');
});
