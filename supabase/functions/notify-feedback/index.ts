import { createClient } from 'npm:@supabase/supabase-js@2';

/// Emails support when someone sends feedback.
///
/// Feedback used to land in a table and stay there: nothing announced it, so
/// the only way to find out a user had reported a problem was to remember to
/// open the admin console. A report nobody reads is the same as no report.
///
/// Reply-to is set to the person who wrote it, so answering them is a reply
/// rather than a copy-paste into a new message.

const supportAddress = Deno.env.get('SUPPORT_EMAIL') ??
  'support@painterreference.com';
const fromAddress = Deno.env.get('FEEDBACK_FROM_EMAIL') ??
  'Painter Reference <feedback@painterreference.com>';
const resendApiKey = Deno.env.get('RESEND_API_KEY');

const adminClient = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  { auth: { persistSession: false } },
);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

/// Records a delivery failure where it will be seen.
///
/// Written rather than only logged, because a notifier that silently stops
/// working looks exactly like nobody sending feedback.
async function recordFailure(feedbackId: string, reason: string) {
  console.error(`notify-feedback failed for ${feedbackId}: ${reason}`);

  try {
    await adminClient.from('backup_replication_failures').insert({
      operation: 'NOTIFY user_feedback',
      storage_path: feedbackId,
      error_message: reason,
    });
  } catch (error) {
    console.error('could not record the failure:', error);
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  let payload: Record<string, unknown>;

  try {
    payload = await request.json();
  } catch {
    return jsonResponse({ error: 'Expected a JSON body' }, 400);
  }

  const record = (payload.record ?? {}) as Record<string, unknown>;
  const feedbackId = String(record.id ?? '');

  if (!feedbackId) {
    return jsonResponse({ error: 'The feedback row has no id' }, 400);
  }

  if (!resendApiKey) {
    await recordFailure(feedbackId, 'RESEND_API_KEY is not configured');
    return jsonResponse({ error: 'Email is not configured' }, 500);
  }

  const from = String(record.user_email ?? 'unknown');
  const type = String(record.feedback_type ?? 'other');
  const comment = String(record.comment ?? '');
  const screen = String(record.current_screen ?? 'unknown');
  const platform = String(record.platform ?? 'unknown');
  const version = String(record.app_version ?? 'unknown');
  const attachmentPath = record.attachment_path;

  // A link rather than an attached file: the screenshot can be 10 MB, and a
  // mailbox is a bad place to put one. Long-lived so the link still works when
  // the message is read days later.
  let attachmentLink = '';

  if (typeof attachmentPath === 'string' && attachmentPath.length > 0) {
    const { data, error } = await adminClient.storage
      .from('feedback-attachments')
      .createSignedUrl(attachmentPath, 60 * 60 * 24 * 30);

    attachmentLink = error || !data
      ? '(a screenshot was attached but the link could not be created)'
      : `<p><a href="${data.signedUrl}">View the attached screenshot</a></p>`;
  }

  const subject = `[${type}] Painter Reference feedback from ${from}`;
  const body = `
    <p><strong>${escapeHtml(type)}</strong> from ${escapeHtml(from)}</p>
    <blockquote style="border-left:3px solid #ccc;margin:0;padding-left:12px">
      ${escapeHtml(comment).replaceAll('\n', '<br>')}
    </blockquote>
    ${attachmentLink}
    <hr>
    <p style="color:#666;font-size:13px">
      Screen: ${escapeHtml(screen)}<br>
      Platform: ${escapeHtml(platform)}<br>
      App version: ${escapeHtml(version)}<br>
      Feedback id: ${escapeHtml(feedbackId)}
    </p>
  `;

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromAddress,
        to: [supportAddress],
        // Answering the notification answers the user directly.
        reply_to: from,
        subject,
        html: body,
      }),
    });

    if (!response.ok) {
      const detail = await response.text();
      await recordFailure(feedbackId, `Resend ${response.status}: ${detail}`);

      return jsonResponse({ error: 'Email was not accepted' }, 502);
    }

    return jsonResponse({ ok: true, feedback_id: feedbackId });
  } catch (error) {
    await recordFailure(feedbackId, `${error}`);

    return jsonResponse({ error: `${error}` }, 500);
  }
});
