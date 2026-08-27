/// Files a report about a message or a person, and tells the operator.
///
/// Reporting has to survive the thing it describes. A sender who realises what
/// they have done can delete the message, and if the report were only a
/// pointer at a row, deleting the row would delete the evidence. So the
/// message is copied into the report as it stood when it was reported.
///
/// The report is written first and the email sent afterwards, deliberately. If
/// Resend is down, or the domain is still unverified, the report is already
/// safe in the queue and the operator sees it the next time they look. Losing
/// a report because a mail server was unreachable would be the worse failure.

import { createClient } from 'npm:@supabase/supabase-js@2';

const supportAddress = Deno.env.get('SUPPORT_EMAIL') ??
  'support@painterreference.com';
const fromAddress = Deno.env.get('FEEDBACK_FROM_EMAIL') ??
  'Painter Reference <feedback@painterreference.com>';
const resendApiKey = Deno.env.get('RESEND_API_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const reasons = new Set([
  'harassment',
  'sexual',
  'violence',
  'spam',
  'other',
]);

const reasonLabels: Record<string, string> = {
  harassment: 'Harassment or bullying',
  sexual: 'Sexual or explicit content',
  violence: 'Violence or threats',
  spam: 'Spam or scam',
  other: 'Something else',
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ success: false, error: 'POST required.' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(
      { success: false, error: 'Reporting is not configured.' },
      500,
    );
  }

  try {
    const accessToken = (request.headers.get('authorization') ?? '')
      .replace(/^Bearer\s+/i, '')
      .trim();
    if (!accessToken) {
      return jsonResponse({ success: false, error: 'Sign in required.' }, 401);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: authData, error: authError } = await supabase.auth.getUser(
      accessToken,
    );
    const reporter = authData?.user;
    if (authError || !reporter?.id || !reporter.email) {
      return jsonResponse({ success: false, error: 'Invalid session.' }, 401);
    }

    const body = await request.json() as {
      subjectType?: unknown;
      messageId?: unknown;
      conversationId?: unknown;
      reportedUserId?: unknown;
      reason?: unknown;
      details?: unknown;
    };

    const subjectType = String(body.subjectType ?? '').trim();
    if (subjectType !== 'message' && subjectType !== 'user') {
      return jsonResponse(
        { success: false, error: 'Report a message or a person.' },
        400,
      );
    }

    const reason = String(body.reason ?? '').trim();
    if (!reasons.has(reason)) {
      return jsonResponse(
        { success: false, error: 'Choose a reason for the report.' },
        400,
      );
    }

    const details = typeof body.details === 'string'
      ? body.details.trim().slice(0, 2000)
      : null;

    let messageId: string | null = null;
    let conversationId: string | null = null;
    let reportedUserId: string | null = null;
    let snapshot: Record<string, unknown> = {};

    if (subjectType === 'message') {
      messageId = String(body.messageId ?? '').trim();
      if (!messageId) {
        return jsonResponse(
          { success: false, error: 'messageId is required.' },
          400,
        );
      }

      const { data: message, error: messageError } = await supabase
        .from('messages')
        .select('id, conversation_id, sender_id, body, image_storage_path, created_at')
        .eq('id', messageId)
        .maybeSingle();
      if (messageError) throw messageError;
      if (!message) {
        return jsonResponse(
          { success: false, error: 'That message no longer exists.' },
          404,
        );
      }

      const { data: conversation, error: conversationError } = await supabase
        .from('conversations')
        .select('id, user_a_id, user_b_id')
        .eq('id', message.conversation_id)
        .maybeSingle();
      if (conversationError) throw conversationError;

      // A message can only be reported by someone who could see it. Without
      // this, knowing an id would be enough to file a report about a private
      // conversation between two other people.
      const participants = [conversation?.user_a_id, conversation?.user_b_id];
      if (!participants.includes(reporter.id)) {
        return jsonResponse(
          { success: false, error: 'That message is not yours to report.' },
          403,
        );
      }
      if (message.sender_id === reporter.id) {
        return jsonResponse(
          { success: false, error: 'You cannot report your own message.' },
          400,
        );
      }

      messageId = message.id;
      conversationId = message.conversation_id;
      reportedUserId = message.sender_id;
      snapshot = {
        body: message.body ?? '',
        image_storage_path: message.image_storage_path ?? null,
        sent_at: message.created_at,
      };
    } else {
      reportedUserId = String(body.reportedUserId ?? '').trim() || null;
      if (!reportedUserId) {
        return jsonResponse(
          { success: false, error: 'reportedUserId is required.' },
          400,
        );
      }
      if (reportedUserId === reporter.id) {
        return jsonResponse(
          { success: false, error: 'You cannot report yourself.' },
          400,
        );
      }
      conversationId = String(body.conversationId ?? '').trim() || null;
    }

    // Resolved for the operator's benefit: a queue of raw uuids is a queue
    // nobody can triage.
    let reportedEmail: string | null = null;
    if (reportedUserId) {
      const { data: reported } = await supabase.auth.admin.getUserById(
        reportedUserId,
      );
      reportedEmail = reported?.user?.email ?? null;
    }

    const { data: inserted, error: insertError } = await supabase
      .from('content_reports')
      .insert({
        reporter_user_id: reporter.id,
        reporter_email: reporter.email,
        reported_user_id: reportedUserId,
        reported_email: reportedEmail,
        subject_type: subjectType,
        message_id: messageId,
        conversation_id: conversationId,
        reason,
        details,
        content_snapshot: snapshot,
      })
      .select('id, created_at')
      .single();
    if (insertError) throw insertError;

    // Best effort from here. The report is already filed; mail is a courtesy
    // on top of it, and its failure must not read to the user as a failure to
    // report — which would invite them to file it again.
    if (resendApiKey) {
      try {
        const lines = [
          `Reason: ${reasonLabels[reason] ?? reason}`,
          `Reported by: ${reporter.email}`,
          `Reported user: ${reportedEmail ?? reportedUserId ?? 'unknown'}`,
          `Type: ${subjectType}`,
          '',
          details ? `What they said:\n${details}` : 'No further detail given.',
        ];
        if (subjectType === 'message') {
          lines.push(
            '',
            'The reported message:',
            String(snapshot.body ?? '').trim() || '(no text)',
            snapshot.image_storage_path
              ? `Image attached: ${snapshot.image_storage_path}`
              : '(no image)',
          );
        }
        lines.push('', `Report id: ${inserted.id}`);

        await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: fromAddress,
            to: [supportAddress],
            reply_to: reporter.email,
            subject:
              `[Report] ${reasonLabels[reason] ?? reason} — Painter Reference`,
            text: lines.join('\n'),
          }),
        });
      } catch (error) {
        console.error('Report filed but the email failed', error);
      }
    }

    return jsonResponse({ success: true, report_id: inserted.id });
  } catch (error) {
    console.error('Reporting failed', error);
    return jsonResponse(
      {
        success: false,
        error: error instanceof Error
          ? error.message
          : 'The report could not be filed.',
      },
      500,
    );
  }
});
