import { createClient } from "npm:@supabase/supabase-js@2";
import { isAnnouncementVisible } from '../_shared/announcement_audience.ts';

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}

// Deliberately unauthenticated: the maintenance notice has to reach signed-out
// users, and it has to keep working when auth itself is the thing being
// worked on. Audience details are returned only to authenticated admins.
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // An unconfigured or unreachable status service must never be able to lock
  // everyone out, so every failure path reports "not in maintenance".
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("get-app-status is not configured");
    return jsonResponse({ maintenance_enabled: false, message: null });
  }

  try {
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data, error } = await supabase
      .from("app_status")
      .select("maintenance_enabled,message,announcement_title,announcement_message,announcement_id")
      .eq("id", true)
      .maybeSingle();

    if (error) {
      console.error("Unable to read app_status", error);
      return jsonResponse({ maintenance_enabled: false, message: null });
    }

    let audienceVisible = false;
    let audience: { audience_kind: string; target_user_ids: string[]; target_platforms: string[] } | null = null;
    let isAdmin = false;
    if (data?.announcement_id) {
      const { data: row, error: audienceError } = await supabase
        .from('app_announcements')
        .select('audience_kind,target_user_ids,target_platforms')
        .eq('id', data.announcement_id).maybeSingle();
      if (audienceError) console.error('Unable to read announcement audience', audienceError);
      audience = row;
      const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '').trim();
      const { data: actor } = token ? await supabase.auth.getUser(token) : { data: null };
      isAdmin = actor?.user?.app_metadata?.is_admin === true;
      const body = request.method === 'POST' ? await request.json().catch(() => ({})) : {};
      const platform = typeof body?.platform === 'string' ? body.platform : '';
      audienceVisible = isAnnouncementVisible(audience, actor?.user?.id ?? null, platform, isAdmin);
    }
    return jsonResponse({
      maintenance_enabled: data?.maintenance_enabled === true,
      message: typeof data?.message === "string" && data.message.trim().length > 0
        ? data.message.trim()
        : null,
      announcement_title: audienceVisible ? data?.announcement_title : null,
      announcement_message: audienceVisible ? data?.announcement_message : null,
      announcement_id: audienceVisible ? data?.announcement_id : null,
      ...(isAdmin && audience ? audience : {}),
    });
  } catch (error) {
    console.error("get-app-status failed", error);
    return jsonResponse({ maintenance_enabled: false, message: null });
  }
});
