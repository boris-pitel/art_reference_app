import { createClient } from 'npm:@supabase/supabase-js@2';
import { selectAudience } from './audience.ts';

const url = Deno.env.get('SUPABASE_URL') ?? '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
const resendKey = Deno.env.get('RESEND_API_KEY');
const fromAddress = Deno.env.get('ANNOUNCEMENT_FROM_EMAIL') ??
  'Painter Reference <support@painterreference.com>';
const postalAddress = Deno.env.get('ANNOUNCEMENT_POSTAL_ADDRESS');
const client = createClient(url, serviceKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

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

function escapeHtml(value: string) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

async function allUsers() {
  const users: Array<{ id: string; email: string }> = [];
  for (let page = 1; ; page++) {
    const { data, error } = await client.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    for (const user of data.users) {
      if (user.email && user.email_confirmed_at) {
        users.push({ id: user.id, email: user.email });
      }
    }
    if (data.users.length < 200) break;
  }
  return users;
}

async function allRows(table: 'announcement_email_preferences' | 'announcement_email_deliveries',
  columns: string, announcementId?: string) {
  const rows: Record<string, unknown>[] = [];
  for (let start = 0; ; start += 1000) {
    let query = client.from(table).select(columns).order('user_id').range(start, start + 999);
    if (announcementId) query = query.eq('announcement_id', announcementId);
    const { data, error } = await query;
    if (error) throw error;
    rows.push(...(data ?? []));
    if ((data?.length ?? 0) < 1000) break;
  }
  return rows;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return json({ error: 'POST required' }, 405);
  const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
  const { data: actor, error: actorError } = await client.auth.getUser(token);
  if (actorError || actor.user?.app_metadata?.is_admin !== true) {
    return json({ error: 'Administrator access required' }, 403);
  }

  let action: string;
  try {
    action = String((await request.json()).action ?? '');
  } catch {
    return json({ error: 'Expected JSON' }, 400);
  }
  if (action !== 'preview' && action !== 'send') return json({ error: 'Unknown action' }, 400);

  try {
    const { data: announcement, error: announcementError } = await client
      .from('app_status')
      .select('announcement_id,announcement_title,announcement_message')
      .eq('id', true).single();
    if (announcementError) throw announcementError;
    if (!announcement?.announcement_id || !announcement.announcement_title ||
        !announcement.announcement_message) {
      return json({ error: 'Publish an announcement before emailing it.' }, 400);
    }

    const users = await allUsers();
    const preferences = await allRows('announcement_email_preferences', 'user_id,updates_enabled');
    const deliveries = await allRows('announcement_email_deliveries',
      'user_id,status', announcement.announcement_id);
    const { eligible, alreadySent, pending } = selectAudience(
      users,
      preferences.map((row) => ({ user_id: String(row.user_id), updates_enabled: row.updates_enabled !== false })),
      deliveries.map((row) => ({ user_id: String(row.user_id), status: String(row.status) })),
    );
    if (action === 'preview') {
      return json({
        title: announcement.announcement_title,
        message: announcement.announcement_message,
        eligible: eligible.length,
        already_sent: alreadySent.size,
        pending: pending.length,
        configured: Boolean(resendKey && postalAddress),
      });
    }

    if (!resendKey || !postalAddress) {
      return json({ error: 'Email sending needs RESEND_API_KEY and ANNOUNCEMENT_POSTAL_ADDRESS.' }, 503);
    }

    let sent = 0;
    const failures: string[] = [];
    for (const user of pending.slice(0, 25)) {
      // Read the preference again immediately before this user's email: they
      // may have opted out while the broadcast was in progress.
      const { data: currentPreference, error: prefError } = await client
        .from('announcement_email_preferences')
        .select('updates_enabled,unsubscribe_token')
        .eq('user_id', user.id).maybeSingle();
      if (prefError) throw prefError;
      if (currentPreference?.updates_enabled === false) continue;
      let unsubscribeToken = currentPreference?.unsubscribe_token;
      if (!unsubscribeToken) {
        const { data: created, error: createError } = await client
          .from('announcement_email_preferences')
          .upsert({ user_id: user.id }, { onConflict: 'user_id', ignoreDuplicates: true })
          .select('unsubscribe_token').single();
        if (createError && createError.code !== 'PGRST116') throw createError;
        unsubscribeToken = created?.unsubscribe_token;
        if (!unsubscribeToken) {
          const { data: existing, error: lookupError } = await client
            .from('announcement_email_preferences')
            .select('updates_enabled,unsubscribe_token')
            .eq('user_id', user.id).single();
          if (lookupError) throw lookupError;
          if (existing.updates_enabled === false) continue;
          unsubscribeToken = existing.unsubscribe_token;
        }
      }

      const existing = deliveries.find((row) => row.user_id === user.id);
      if (existing?.status === 'failed') {
        const { error } = await client.from('announcement_email_deliveries')
          .update({ status: 'sending', updated_at: new Date().toISOString() })
          .eq('announcement_id', announcement.announcement_id).eq('user_id', user.id);
        if (error) throw error;
      } else {
        const { error } = await client.from('announcement_email_deliveries')
          .insert({ announcement_id: announcement.announcement_id, user_id: user.id, status: 'sending' });
        if (error?.code === '23505') continue;
        if (error) throw error;
      }

      const unsubscribeUrl = `${url}/functions/v1/unsubscribe-announcement?token=${unsubscribeToken}`;
      const title = String(announcement.announcement_title);
      const message = String(announcement.announcement_message);
      const text = `${title}\n\n${message}\n\nUnsubscribe from app update emails: ${unsubscribeUrl}\n${postalAddress}`;
      const html = `<h2>${escapeHtml(title)}</h2><p>${escapeHtml(message).replaceAll('\n', '<br>')}</p>` +
        `<hr><p><a href="${unsubscribeUrl}">Unsubscribe from app update emails</a></p>` +
        `<p>${escapeHtml(postalAddress)}</p>`;
      let providerId: string | null = null;
      let failure: string | null = null;
      try {
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
            'Idempotency-Key': `announcement-${announcement.announcement_id}-${user.id}`,
          },
          body: JSON.stringify({ from: fromAddress, to: [user.email], subject: title, text, html }),
        });
        const result = await response.json();
        if (response.ok) providerId = typeof result.id === 'string' ? result.id : null;
        else failure = `Resend ${response.status}: ${JSON.stringify(result)}`;
      } catch (error) {
        failure = String(error);
      }
      const { error: logError } = await client.from('announcement_email_deliveries')
        .update({
          status: failure ? 'failed' : 'sent',
          provider_id: providerId,
          error_message: failure,
          updated_at: new Date().toISOString(),
        }).eq('announcement_id', announcement.announcement_id).eq('user_id', user.id);
      if (logError) throw logError;
      if (failure) failures.push(`${user.email}: ${failure}`);
      else sent++;
    }
    return json({ sent, failures, remaining: Math.max(0, pending.length - 25) });
  } catch (error) {
    console.error('announcement-email failed', error);
    return json({ error: String(error) }, 500);
  }
});
