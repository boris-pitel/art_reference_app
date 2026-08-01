import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const storageBucket = "reference-images";

type AnalyzeImageRequest = {
  imageId?: string;
};

type AiAnalysis = {
  title: string;
  description: string;
  keywords: string[];
  subject_type: string;
  lighting: string;
  composition: string;
  dominant_colors: string[];
  art_notes: string;
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: corsHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      {
        success: false,
        error: "Only POST requests are supported.",
      },
      405,
    );
  }

  const openAiApiKey = Deno.env.get("OPENAI_API_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get(
    "SUPABASE_SERVICE_ROLE_KEY",
  );

  if (!openAiApiKey) {
    return jsonResponse(
      {
        success: false,
        error: "OPENAI_API_KEY is not configured.",
      },
      500,
    );
  }

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(
      {
        success: false,
        error:
          "Supabase server environment is not configured.",
      },
      500,
    );
  }

  const supabase = createClient(
    supabaseUrl,
    serviceRoleKey,
  );

  let imageId: string | undefined;

  try {
    const body =
      (await request.json()) as AnalyzeImageRequest;

    imageId = body.imageId?.trim();

    if (!imageId) {
      return jsonResponse(
        {
          success: false,
          error: "imageId is required.",
        },
        400,
      );
    }

    /*
     * Find the selected image record.
     */
    const {
      data: imageRecord,
      error: imageError,
    } = await supabase
      .from("image_assets")
      .select("id, storage_path")
      .eq("id", imageId)
      .maybeSingle();

    if (imageError) {
      throw new Error(
        `Unable to read image record: ${imageError.message}`,
      );
    }

    if (!imageRecord) {
      return jsonResponse(
        {
          success: false,
          error: "Image was not found.",
        },
        404,
      );
    }

    if (
      typeof imageRecord.storage_path !== "string" ||
      imageRecord.storage_path.trim().length === 0
    ) {
      return jsonResponse(
        {
          success: false,
          error:
            "The image record does not contain a valid storage_path.",
        },
        400,
      );
    }

    const storagePath =
      imageRecord.storage_path.trim();

    /*
     * Mark this image as being analyzed.
     */
    const {
      error: analyzingStatusError,
    } = await supabase
      .from("image_assets")
      .update({
        ai_analysis_status: "analyzing",
        ai_analysis_error: null,
      })
      .eq("id", imageId);

    if (analyzingStatusError) {
      throw new Error(
        `Unable to update AI status: ${analyzingStatusError.message}`,
      );
    }

    /*
     * Download the original image from Supabase Storage.
     */
    const {
      data: imageBlob,
      error: downloadError,
    } = await supabase.storage
      .from(storageBucket)
      .download(storagePath);

    if (downloadError) {
      throw new Error(
        `Unable to download image from Storage: ${downloadError.message}`,
      );
    }

    if (!imageBlob) {
      throw new Error(
        "Unable to download image from Storage: no image data was returned.",
      );
    }

    /*
     * Convert the downloaded image to a base64 data URL.
     */
    const imageArrayBuffer =
      await imageBlob.arrayBuffer();

    const imageBytes =
      new Uint8Array(imageArrayBuffer);

    if (imageBytes.length === 0) {
      throw new Error(
        "The downloaded image is empty.",
      );
    }

    const mimeType = determineMimeType(
      storagePath,
      imageBlob.type,
    );

    const base64Image =
      uint8ArrayToBase64(imageBytes);

    const imageDataUrl =
      `data:${mimeType};base64,${base64Image}`;

    /*
     * Ask OpenAI to analyze the image specifically as
     * a visual reference for an artist.
     */
    const openAiResponse = await fetch(
      "https://api.openai.com/v1/responses",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${openAiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-5-mini",

          /*
           * This prevents unexpectedly long responses.
           */
          // max_output_tokens: 700,

          input: [
            {
              role: "developer",
              content: [
                {
                  type: "input_text",
                  text: [
                    "You analyze visual reference images",
                    "for painters and pastel artists.",
                    "Be practical, visually observant,",
                    "factual, and extremely concise.",
                    "Do not identify an unknown real person.",
                    "Do not invent details that are not visible.",
                    "Return only valid JSON.",
                    "Do not use Markdown or code fences.",
                    "Follow every requested length limit.",
                  ].join(" "),
                },
              ],
            },
            {
              role: "user",
              content: [
                {
                  type: "input_text",
                  text: `
Analyze this image as an art reference.

Return exactly one JSON object with these fields:

{
  "title": "A descriptive title of no more than 8 words",
  "description": "A factual description using no more than 2 short sentences",
  "keywords": [
    "5 to 7 short search keywords"
  ],
  "subject_type": "portrait, landscape, architecture, still life, abstract, icon, or other",
  "lighting": "One short sentence, no more than 25 words",
  "composition": "One short sentence, no more than 25 words",
  "dominant_colors": [
    "4 to 6 plainly named colors"
  ],
  "art_notes": "Exactly 3 short practical painting suggestions, separated by semicolons. No more than 60 words total."
}

Rules:

- Base the analysis only on what is visible.
- Do not identify a person.
- Do not speculate about private or sensitive traits.
- Use plain, direct language.
- Do not repeat the description in other fields.
- Do not write introductory or concluding text.
- Respect every word and item limit.
- Return JSON only.
                  `.trim(),
                },
                {
                  type: "input_image",
                  image_url: imageDataUrl,
                  detail: "high",
                },
              ],
            },
          ],
        }),
      },
    );

    let openAiData: unknown;

    try {
      openAiData =
        await openAiResponse.json();
    } catch {
      throw new Error(
        `OpenAI returned an unreadable response with status ${openAiResponse.status}.`,
      );
    }

    if (!openAiResponse.ok) {
      const errorMessage =
        extractOpenAiError(openAiData) ??
        `OpenAI request failed with status ${openAiResponse.status}.`;

      throw new Error(errorMessage);
    }

    const outputText =
      extractOutputText(openAiData);

    if (!outputText) {
      throw new Error(
        "OpenAI returned no analysis text.",
      );
    }

    const analysis =
      parseAnalysis(outputText);

    /*
     * Save the completed analysis.
     */
    const {
      error: saveError,
    } = await supabase
      .from("image_assets")
      .update({
        ai_title: analysis.title,
        ai_description: analysis.description,
        ai_keywords: analysis.keywords,
        ai_subject_type:
          analysis.subject_type,
        ai_lighting: analysis.lighting,
        ai_composition: analysis.composition,
        ai_dominant_colors:
          analysis.dominant_colors,
        ai_art_notes: analysis.art_notes,
        ai_analysis_status: "completed",
        ai_analyzed_at:
          new Date().toISOString(),
        ai_analysis_error: null,
      })
      .eq("id", imageId);

    if (saveError) {
      throw new Error(
        `AI analysis was created but could not be saved: ${saveError.message}`,
      );
    }

    return jsonResponse({
      success: true,
      imageId,
      analysis,
    });
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : "Unknown image-analysis error.";

    console.error(
      "analyze-image error:",
      error,
    );

    /*
     * Record the failure on this image, when possible.
     */
    if (imageId) {
      const {
        error: failureStatusError,
      } = await supabase
        .from("image_assets")
        .update({
          ai_analysis_status: "failed",
          ai_analysis_error: message,
        })
        .eq("id", imageId);

      if (failureStatusError) {
        console.error(
          "Unable to save failed AI status:",
          failureStatusError,
        );
      }
    }

    return jsonResponse(
      {
        success: false,
        error: message,
      },
      500,
    );
  }
});

function extractOutputText(
  response: unknown,
): string {
  if (
    !response ||
    typeof response !== "object"
  ) {
    return "";
  }

  const responseObject =
    response as Record<string, unknown>;

  if (
    typeof responseObject.output_text ===
    "string"
  ) {
    return responseObject.output_text.trim();
  }

  if (!Array.isArray(responseObject.output)) {
    return "";
  }

  const textParts: string[] = [];

  for (
    const outputItem of responseObject.output
  ) {
    if (
      !outputItem ||
      typeof outputItem !== "object"
    ) {
      continue;
    }

    const outputObject =
      outputItem as Record<string, unknown>;

    if (
      !Array.isArray(outputObject.content)
    ) {
      continue;
    }

    for (
      const contentItem of outputObject.content
    ) {
      if (
        !contentItem ||
        typeof contentItem !== "object"
      ) {
        continue;
      }

      const contentObject =
        contentItem as Record<
          string,
          unknown
        >;

      if (
        contentObject.type ===
          "output_text" &&
        typeof contentObject.text ===
          "string"
      ) {
        textParts.push(
          contentObject.text,
        );
      }
    }
  }

  return textParts.join("\n").trim();
}

function extractOpenAiError(
  response: unknown,
): string | null {
  if (
    !response ||
    typeof response !== "object"
  ) {
    return null;
  }

  const responseObject =
    response as Record<string, unknown>;

  if (
    !responseObject.error ||
    typeof responseObject.error !==
      "object"
  ) {
    return null;
  }

  const errorObject =
    responseObject.error as Record<
      string,
      unknown
    >;

  if (
    typeof errorObject.message ===
    "string"
  ) {
    return errorObject.message;
  }

  return null;
}

function parseAnalysis(
  outputText: string,
): AiAnalysis {
  const cleanedText = outputText
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  let parsedValue: unknown;

  try {
    parsedValue =
      JSON.parse(cleanedText);
  } catch {
    throw new Error(
      "OpenAI returned invalid JSON.",
    );
  }

  if (
    !parsedValue ||
    typeof parsedValue !== "object" ||
    Array.isArray(parsedValue)
  ) {
    throw new Error(
      "OpenAI returned an invalid analysis object.",
    );
  }

  const data =
    parsedValue as Record<
      string,
      unknown
    >;

  return {
    title: requiredString(
      data.title,
      "title",
    ),

    description: requiredString(
      data.description,
      "description",
    ),

    keywords: requiredStringArray(
      data.keywords,
      "keywords",
    ),

    subject_type: requiredString(
      data.subject_type,
      "subject_type",
    ),

    lighting: requiredString(
      data.lighting,
      "lighting",
    ),

    composition: requiredString(
      data.composition,
      "composition",
    ),

    dominant_colors:
      requiredStringArray(
        data.dominant_colors,
        "dominant_colors",
      ),

    art_notes: requiredString(
      data.art_notes,
      "art_notes",
    ),
  };
}

function requiredString(
  value: unknown,
  fieldName: string,
): string {
  if (
    typeof value !== "string" ||
    value.trim().length === 0
  ) {
    throw new Error(
      `AI response is missing ${fieldName}.`,
    );
  }

  return value.trim();
}

function requiredStringArray(
  value: unknown,
  fieldName: string,
): string[] {
  if (!Array.isArray(value)) {
    throw new Error(
      `AI response is missing ${fieldName}.`,
    );
  }

  const result = value
    .filter(
      (item): item is string =>
        typeof item === "string",
    )
    .map((item) => item.trim())
    .filter(
      (item) => item.length > 0,
    );

  if (result.length === 0) {
    throw new Error(
      `AI response contains no values for ${fieldName}.`,
    );
  }

  return result;
}

function determineMimeType(
  path: string,
  blobMimeType: string,
): string {
  /*
   * Blob.type is preferable when Supabase returned it.
   */
  if (
    blobMimeType &&
    blobMimeType.startsWith("image/")
  ) {
    return blobMimeType;
  }

  const lowerPath =
    path.toLowerCase();

  if (
    lowerPath.endsWith(".jpg") ||
    lowerPath.endsWith(".jpeg")
  ) {
    return "image/jpeg";
  }

  if (lowerPath.endsWith(".png")) {
    return "image/png";
  }

  if (lowerPath.endsWith(".webp")) {
    return "image/webp";
  }

  if (lowerPath.endsWith(".gif")) {
    return "image/gif";
  }

  /*
   * Most images currently uploaded by the app are JPEGs.
   */
  return "image/jpeg";
}

function uint8ArrayToBase64(
  bytes: Uint8Array,
): string {
  /*
   * Process in chunks to avoid exceeding the maximum
   * number of arguments accepted by
   * String.fromCharCode().
   */
  const chunkSize = 0x8000;
  const binaryParts: string[] = [];

  for (
    let offset = 0;
    offset < bytes.length;
    offset += chunkSize
  ) {
    const chunk = bytes.subarray(
      offset,
      Math.min(
        offset + chunkSize,
        bytes.length,
      ),
    );

    binaryParts.push(
      String.fromCharCode(...chunk),
    );
  }

  return btoa(
    binaryParts.join(""),
  );
}

function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type":
          "application/json",
      },
    },
  );
}