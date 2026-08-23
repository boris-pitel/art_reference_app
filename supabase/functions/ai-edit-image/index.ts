import { createClient } from "npm:@supabase/supabase-js@2";
import { v5 as uuidV5 } from "npm:uuid@11";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-user-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// gpt-image-2 accepts an arbitrary WIDTHxHEIGHT as long as both sides are
// divisible by 16, the aspect ratio stays within 1:3..3:1, and the result fits
// inside 3840x2160. Asking for a concrete size matters: size="auto" picks a
// small output (a 8000x6000 source came back as 1427x1102), so an edit of a
// large photo loses far more resolution than the model actually requires.
const maxLongSide = 3840;
const maxShortSide = 2160;

// Below this the source is small enough that picking a size buys nothing, and
// scaling to a /16 boundary risks upscaling. Let the model decide instead.
const minLongSide = 512;

function roundDownToMultipleOf16(value: number): number {
  return Math.max(16, Math.floor(value / 16) * 16);
}

function computeEditSize(width: unknown, height: unknown): string {
  if (
    typeof width !== "number" ||
    typeof height !== "number" ||
    !Number.isFinite(width) ||
    !Number.isFinite(height) ||
    width <= 0 ||
    height <= 0
  ) {
    return "auto";
  }

  const isLandscape = width >= height;
  const sourceLong = isLandscape ? width : height;
  const sourceShort = isLandscape ? height : width;

  if (sourceLong < minLongSide) return "auto";

  // Outside the supported aspect range there is no faithful size to request,
  // so defer rather than distorting the image.
  if (sourceLong / sourceShort > 3) return "auto";

  // Never scale up — that would invent detail the source does not have.
  const scale = Math.min(
    maxLongSide / sourceLong,
    maxShortSide / sourceShort,
    1,
  );

  const long = Math.min(roundDownToMultipleOf16(sourceLong * scale), maxLongSide);
  const short = Math.min(roundDownToMultipleOf16(sourceShort * scale), maxShortSide);

  return isLandscape ? `${long}x${short}` : `${short}x${long}`;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "POST required." }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openAiApiKey = Deno.env.get("OPENAI_API_KEY");
  if (!supabaseUrl || !serviceRoleKey || !openAiApiKey) {
    return jsonResponse({ success: false, error: "AI editing is not configured." }, 500);
  }

  try {
    const authorization = request.headers.get("authorization") ?? "";
    const accessToken = authorization.replace(/^Bearer\s+/i, "").trim();
    if (!accessToken) return jsonResponse({ success: false, error: "Sign in required." }, 401);

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
    const email = authData.user?.email?.trim().toLowerCase();
    if (authError || !email) {
      return jsonResponse({ success: false, error: "Invalid session." }, 401);
    }
    const expectedUserId = uuidV5(`art-reference-user:${email}`, uuidV5.URL);
    if (request.headers.get("x-user-id") !== expectedUserId) {
      return jsonResponse({ success: false, error: "Invalid user identity." }, 403);
    }

    const body = await request.json() as {
      imageId?: string;
      prompt?: string;
      quality?: string;
    };
    const imageId = body.imageId?.trim();
    const prompt = body.prompt?.trim();
    const quality = body.quality?.trim() ?? "medium";
    if (!imageId || !prompt) {
      return jsonResponse({ success: false, error: "imageId and prompt are required." }, 400);
    }
    if (prompt.length > 1000) {
      return jsonResponse({ success: false, error: "Prompt cannot exceed 1,000 characters." }, 400);
    }
    if (!["low", "medium", "high"].includes(quality)) {
      return jsonResponse({ success: false, error: "Invalid AI quality." }, 400);
    }

    const { data: record, error: recordError } = await supabase
      .from("image_assets")
      .select("id,storage_path,width,height")
      .eq("id", imageId)
      .eq("user_id", expectedUserId)
      .maybeSingle();
    if (recordError) throw new Error(`Unable to read image: ${recordError.message}`);
    if (!record?.storage_path) {
      return jsonResponse({ success: false, error: "Image not found." }, 404);
    }

    const { data: source, error: downloadError } = await supabase.storage
      .from("reference-images")
      .download(record.storage_path);
    if (downloadError || !source) {
      throw new Error(`Unable to download image: ${downloadError?.message ?? "no data"}`);
    }

    const sourceBytes = new Uint8Array(await source.arrayBuffer());
    const sourceMime = detectImageMime(sourceBytes);

    const buildRequest = (size: string): FormData => {
      const form = new FormData();
      form.append("model", "gpt-image-2");
      form.append(
        "image",
        // Rebuilt with an explicit type: the downloaded Blob reports
        // application/octet-stream, which OpenAI rejects outright.
        new File([sourceBytes], `source.${extensionForMime(sourceMime)}`, {
          type: sourceMime,
        }),
      );
      form.append(
        "prompt",
        [
          "Edit the supplied image according to the user's instruction.",
          "Preserve the original composition, people, lighting, colors, and all details that the user did not ask to change.",
          "Do not add text, borders, signatures, or watermarks.",
          `User instruction: ${prompt}`,
        ].join(" "),
      );
      form.append("quality", quality);
      form.append("size", size);
      form.append("output_format", "jpeg");
      form.append("output_compression", "88");
      return form;
    };

    const callOpenAi = (size: string) =>
      fetch("https://api.openai.com/v1/images/edits", {
        method: "POST",
        headers: { Authorization: `Bearer ${openAiApiKey}` },
        body: buildRequest(size),
      });

    const requestedSize = computeEditSize(record.width, record.height);

    // Taken immediately before the model is called, and not before: a request
    // that fails validation or names a missing image has cost nothing and must
    // not cost the user an edit either.
    const { data: quota, error: quotaError } = await supabase.rpc(
      "consume_ai_quota",
      {
        p_user_id: expectedUserId,
        p_operation: "ai_image_edit",
        // The verified email, so the tier and the admin exemption are resolved
        // in the database rather than asserted by the caller.
        p_email: email,
      },
    );
    if (quotaError) {
      // Refusing is the safe direction. A quota system that fails open is not
      // a quota system, and this is the one call that spends real money.
      console.error("Quota check failed", quotaError);
      return jsonResponse(
        { success: false, error: "AI editing is unavailable right now." },
        503,
      );
    }
    if (quota?.allowed !== true) {
      const message = quota?.reason === "service"
        // Never phrased as the user's fault: this ceiling is the service
        // protecting itself, and blaming them for it would be a lie.
        ? "AI editing has reached its limit for today across all users. Please try again tomorrow."
        : quota?.reason === "monthly"
        ? `You have used all ${quota?.limit} AI edits for this month.`
        : `You have used all ${quota?.limit} AI edits for today. They reset tomorrow.`;

      return jsonResponse(
        { success: false, error: message, quota_reason: quota?.reason },
        429,
      );
    }

    const refundQuota = async () => {
      await supabase.rpc("refund_ai_quota", {
        p_user_id: expectedUserId,
        p_operation: "ai_image_edit",
      });
    };

    let openAiResponse: Response;
    let result: Record<string, unknown>;

    try {
      openAiResponse = await callOpenAi(requestedSize);
      result = await openAiResponse.json();
    } catch (error) {
      // The request never reached OpenAI, so nothing was charged and the
      // allowance goes back. Once a response exists the money is spent
      // whatever it says, and the unit stays consumed.
      await refundQuota();
      throw error;
    }

    // Sizes above 2560x1440 are documented as experimental, so a rejected size
    // falls back to letting the model choose rather than failing the edit.
    if (!openAiResponse.ok && requestedSize !== "auto" && openAiResponse.status < 500) {
      console.warn(
        `OpenAI rejected size ${requestedSize}; retrying with auto.`,
        result?.error?.message,
      );
      try {
        openAiResponse = await callOpenAi("auto");
        result = await openAiResponse.json();
      } catch (error) {
        await refundQuota();
        throw error;
      }
    }

    if (!openAiResponse.ok) {
      console.error("OpenAI image edit failed", openAiResponse.status, result);
      return jsonResponse(
        { success: false, error: result?.error?.message ?? "AI image editing failed." },
        openAiResponse.status >= 500 ? 502 : 400,
      );
    }
    const imageBase64 = result?.data?.[0]?.b64_json;
    if (typeof imageBase64 !== "string" || imageBase64.length === 0) {
      throw new Error("OpenAI returned no edited image.");
    }
    return jsonResponse({
      success: true,
      image_base64: imageBase64,
      output_format: "jpeg",
      quality,
      usage: result.usage ?? null,
    });
  } catch (error) {
    console.error("AI image edit error", error);
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : "AI image editing failed." },
      500,
    );
  }
});

function extensionForMime(mime: string): string {
  if (mime.includes("png")) return "png";
  if (mime.includes("webp")) return "webp";
  return "jpg";
}

/// The image's real format, read from its leading bytes.
///
/// Storage records the correct type, but the download client hands back a Blob
/// typed application/octet-stream, and FormData takes the part's Content-Type
/// from the Blob — so OpenAI rejected the upload as an unsupported mimetype
/// however correct the filename was. The bytes themselves cannot be mislabelled.
function detectImageMime(bytes: Uint8Array): string {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }

  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e && bytes[3] === 0x47
  ) {
    return "image/png";
  }

  // RIFF....WEBP
  if (
    bytes.length >= 12 &&
    bytes[0] === 0x52 && bytes[1] === 0x49 &&
    bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 &&
    bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    return "image/webp";
  }

  // Everything stored here is one of the three; JPEG is the overwhelming case.
  return "image/jpeg";
}
