import { createClient } from "npm:@supabase/supabase-js@2";

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
// worked on. The response carries no user data.
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
      .select("maintenance_enabled,message")
      .eq("id", true)
      .maybeSingle();

    if (error) {
      console.error("Unable to read app_status", error);
      return jsonResponse({ maintenance_enabled: false, message: null });
    }

    return jsonResponse({
      maintenance_enabled: data?.maintenance_enabled === true,
      message: typeof data?.message === "string" && data.message.trim().length > 0
        ? data.message.trim()
        : null,
    });
  } catch (error) {
    console.error("get-app-status failed", error);
    return jsonResponse({ maintenance_enabled: false, message: null });
  }
});
