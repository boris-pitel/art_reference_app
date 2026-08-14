import { Pool } from 'jsr:@db/postgres@^0.19.3';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');

if (!databaseUrl) {
  throw new Error('SUPABASE_DB_URL is not available');
}

const pool = new Pool(databaseUrl, 1, true);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id, x-image-id',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

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
        'Content-Type': 'application/json',
      },
    },
  );
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders,
    });
  }

  if (request.method !== 'GET') {
    return jsonResponse(
      {
        error: 'Method not allowed',
      },
      405,
    );
  }

  const userId = request.headers.get('x-user-id')?.trim();
  const imageId = request.headers.get('x-image-id')?.trim();

  if (!userId) {
    return jsonResponse(
      {
        error: 'Missing x-user-id header',
      },
      400,
    );
  }

  if (!imageId) {
    return jsonResponse(
      {
        error: 'Missing x-image-id header',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    const result = await connection.queryObject<{
      id: string;
      title: string | null;
      notes: string | null;
      source_url: string | null;
      original_owner_name: string | null;
      is_favorite: boolean;
      is_finished_artwork: boolean;

      ai_title: string | null;
      ai_description: string | null;
      ai_keywords: string[] | null;
      ai_subject_type: string | null;
      ai_lighting: string | null;
      ai_composition: string | null;
      ai_dominant_colors: string[] | null;
      ai_art_notes: string | null;

      ai_analysis_status: string | null;
      ai_analyzed_at: Date | null;
      ai_analysis_error: string | null;
    }>`
      select
        id,
        title,
        notes,
        source_url,
        original_owner_name,
        is_favorite,
        is_finished_artwork,

        ai_title,
        ai_description,
        ai_keywords,
        ai_subject_type,
        ai_lighting,
        ai_composition,
        ai_dominant_colors,
        ai_art_notes,

        ai_analysis_status,
        ai_analyzed_at,
        ai_analysis_error
      from image_assets
      where id = ${imageId}::uuid
        and user_id = ${userId}::uuid
      limit 1
    `;

    if (result.rows.length == 0) {
      return jsonResponse(
        {
          error: 'Image not found',
        },
        404,
      );
    }

    const row = result.rows[0];

    return jsonResponse({
      image_id: row.id,
      title: row.title,
      notes: row.notes,
      source_url: row.source_url,
      original_owner_name: row.original_owner_name,
      is_favorite: row.is_favorite,
      is_finished_artwork: row.is_finished_artwork,

      ai_title: row.ai_title,
      ai_description: row.ai_description,
      ai_keywords: row.ai_keywords ?? [],
      ai_subject_type: row.ai_subject_type,
      ai_lighting: row.ai_lighting,
      ai_composition: row.ai_composition,
      ai_dominant_colors: row.ai_dominant_colors ?? [],
      ai_art_notes: row.ai_art_notes,

      ai_analysis_status:
        row.ai_analysis_status ?? 'not_analyzed',

      ai_analyzed_at:
        row.ai_analyzed_at?.toISOString() ?? null,

      ai_analysis_error: row.ai_analysis_error,
    });
  } catch (error) {
    console.error('get-image-metadata failed:', error);

    return jsonResponse(
      {
        error: 'Unable to load image metadata',
        details: String(error),
      },
      500,
    );
  } finally {
    connection.release();
  }
});
