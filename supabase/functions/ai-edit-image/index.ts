import { createClient } from "npm:@supabase/supabase-js@2";
import { v5 as uuidV5 } from "npm:uuid@11";
import {
  computeEditSize,
  inspectJpeg,
  stripApplicationSegments,
  withOrientation,
} from "./source_image.ts";

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
      imageBase64?: string;
      prompt?: string;
      quality?: string;
    };
    const imageId = body.imageId?.trim();
    const adjustedImageBase64 = body.imageBase64?.trim();
    const prompt = body.prompt?.trim();
    const quality = body.quality?.trim() ?? "medium";
    if ((!imageId && !adjustedImageBase64) || !prompt) {
      return jsonResponse({ success: false, error: "An image and prompt are required." }, 400);
    }
    if (prompt.length > 1000) {
      return jsonResponse({ success: false, error: "Prompt cannot exceed 1,000 characters." }, 400);
    }
    if (!["low", "medium", "high"].includes(quality)) {
      return jsonResponse({ success: false, error: "Invalid AI quality." }, 400);
    }

    let record: { width: number | null; height: number | null } | null = null;
    let originalBytes: Uint8Array;
    if (adjustedImageBase64) {
      try {
        const binary = atob(adjustedImageBase64);
        originalBytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) {
          originalBytes[index] = binary.charCodeAt(index);
        }
      } catch (_) {
        return jsonResponse({ success: false, error: "The adjusted image is invalid." }, 400);
      }
    } else {
      const { data, error: recordError } = await supabase
        .from("image_assets")
        .select("id,storage_path,width,height")
        .eq("id", imageId!)
        .eq("user_id", expectedUserId)
        .maybeSingle();
      if (recordError) throw new Error(`Unable to read image: ${recordError.message}`);
      if (!data?.storage_path) {
        return jsonResponse({ success: false, error: "Image not found." }, 404);
      }
      record = data;

      const { data: source, error: downloadError } = await supabase.storage
        .from("reference-images")
        .download(data.storage_path);
      if (downloadError || !source) {
        throw new Error(`Unable to download image: ${downloadError?.message ?? "no data"}`);
      }
      originalBytes = new Uint8Array(await source.arrayBuffer());
    }
    const sourceMime = detectImageMime(originalBytes);

    // Some photographs were refused outright with "Invalid image file or mode
    // for image 1" while much larger ones edited fine — an 8000x6000 source
    // succeeded where a 4284x5712 one failed every time, on every platform.
    // What the refused files had in common was not their size but their
    // wrapping: Apple HDR photographs carrying EXIF, XMP, extra APP2 segments
    // and an APP10 gain map. Rebuilding them without that wrapping is a byte
    // copy, so nothing about the picture itself changes.
    const profile = sourceMime === "image/jpeg" ? inspectJpeg(originalBytes) : null;
    const sourceBytes = profile?.needsRebuild
      ? stripApplicationSegments(originalBytes)
      : originalBytes;

    // Deliberately the frame's own dimensions rather than the record's. The
    // record stores the size the photograph *displays* at, which for a rotated
    // camera file is the transpose of how its pixels are actually stored — so
    // using it asked for a portrait result while supplying a landscape image,
    // quietly instructing the model to turn the picture on its side. Stripping
    // the EXIF above removes the rotation flag, so the frame is now the whole
    // truth; the turn is put back on the result further down.
    const requestedSize = profile
      ? computeEditSize(profile.frameWidth, profile.frameHeight)
      : computeEditSize(record?.width, record?.height);
    const restoreOrientation = profile?.needsRebuild ? profile.orientation : 1;

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
      // The next level up, so the message can name something specific rather
      // than telling somebody to go and find out what their options are.
      const { data: upgrade } = quota?.reason === "service"
        ? { data: null }
        : await supabase
          .from("ai_quota_tiers")
          .select("level,display_name,per_user_daily,per_user_monthly")
          .gt("level", quota?.level ?? 0)
          .lt("level", 9)
          .order("level", { ascending: true })
          .limit(1)
          .maybeSingle();

      const message = quota?.reason === "service"
        // Never phrased as the user's fault: this ceiling is the service
        // protecting itself, and blaming them for it would be a lie.
        ? "AI editing is unavailable for the rest of today. This is a limit on the service as a whole, not on your account."
        : quota?.reason === "monthly"
        ? `You have used all ${quota?.limit} AI edits included this month. They start again on the first of next month.`
        : `You have used your ${quota?.limit} AI edit${
          quota?.limit === 1 ? "" : "s"
        } for today. More become available tomorrow.`;

      return jsonResponse({
        success: false,
        error: message,
        quota_reason: quota?.reason,
        current_level: quota?.level ?? null,
        upgrade_level: upgrade?.level ?? null,
        upgrade_name: upgrade?.display_name ?? null,
        upgrade_daily: upgrade?.per_user_daily ?? null,
        upgrade_monthly: upgrade?.per_user_monthly ?? null,
      }, 429);
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

    // The model worked from the stripped frame, so its answer is stored the
    // same way round. Recording the camera's own turn on it puts it upright
    // without touching a pixel.
    const edited = restoreOrientation === 1
      ? imageBase64
      : reencodeBase64(imageBase64, restoreOrientation);

    return jsonResponse({
      success: true,
      image_base64: edited,
      output_format: "jpeg",
      quality,
      // Reported so the caller can record what was actually asked for. Output
      // size is the dominant term in what an edit costs, and until now nothing
      // wrote it down.
      size: requestedSize,
      source_rebuilt: profile?.needsRebuild ?? false,
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

/**
 * Stamps an orientation onto a base64 JPEG.
 *
 * Base64 in, base64 out, with only the metadata block changed. A failure here
 * must never lose the edit the user just paid for, so anything unexpected
 * returns the image as it came back — upright is worth less than present.
 */
function reencodeBase64(encoded: string, orientation: number): string {
  try {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);

    const stamped = withOrientation(bytes, orientation);
    if (stamped === bytes) return encoded;

    let out = "";
    for (let i = 0; i < stamped.length; i += 0x8000) {
      out += String.fromCharCode(...stamped.subarray(i, i + 0x8000));
    }
    return btoa(out);
  } catch (error) {
    console.error("Could not stamp orientation on the edited image", error);
    return encoded;
  }
}

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
