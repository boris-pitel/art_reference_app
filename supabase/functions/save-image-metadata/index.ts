import { Pool } from 'jsr:@db/postgres@^0.19.3';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');

if (!databaseUrl) {
  throw new Error('SUPABASE_DB_URL is not available');
}

const pool = new Pool(databaseUrl, 1, true);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

function nullableText(value: unknown): string | null {
  if (typeof value !== 'string') {
    return null;
  }

  const normalized = value.trim();

  return normalized.length === 0
    ? null
    : normalized;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders,
    });
  }

  if (request.method !== 'POST') {
    return jsonResponse(
      {
        error: 'Method not allowed',
      },
      405,
    );
  }

  let body: Record<string, unknown>;

  try {
    body = await request.json();
  } catch {
    return jsonResponse(
      {
        error: 'Request body must be valid JSON',
      },
      400,
    );
  }

  const userId =
    typeof body.user_id === 'string'
      ? body.user_id.trim()
      : '';

  const imageId =
    typeof body.image_id === 'string'
      ? body.image_id.trim()
      : '';

  if (!userId) {
    return jsonResponse(
      {
        error: 'Missing user_id',
      },
      400,
    );
  }

  if (!imageId) {
    return jsonResponse(
      {
        error: 'Missing image_id',
      },
      400,
    );
  }

  const title = nullableText(body.title);
  const notes = nullableText(body.notes);
  const sourceUrl = nullableText(body.source_url);
  const isFavorite = body.is_favorite === true;
  const isFinishedArtwork = body.is_finished_artwork === true;

  const connection = await pool.connect();

  try {
    if (isFinishedArtwork) {
      const relationships = await connection.queryObject<{ count: number }>`
        select count(*)::int as count
        from public.image_relationships relationship
        join public.image_assets child
          on child.id = relationship.child_image_id
        where relationship.child_image_id = ${imageId}::uuid
          and child.user_id = ${userId}::uuid
      `;
      const parentCount = relationships.rows[0]?.count ?? 0;
      if (parentCount > 1) {
        return jsonResponse(
          {
            error: 'A finished painting can belong to only one photo reference.',
          },
          409,
        );
      }
      if (parentCount === 0) {
        return jsonResponse(
          { error: 'Only an attached sketch can be marked as finished.' },
          409,
        );
      }
    }

    const result = await connection.queryObject<{
      id: string;
      title: string | null;
      notes: string | null;
      source_url: string | null;
      is_favorite: boolean;
      is_finished_artwork: boolean;
    }>`
      update image_assets
      set
        title = ${title},
        notes = ${notes},
        source_url = ${sourceUrl},
        is_favorite = ${isFavorite},
        is_finished_artwork = ${isFinishedArtwork}
      where id = ${imageId}::uuid
        and user_id = ${userId}::uuid
      returning
        id,
        title,
        notes,
        source_url,
        is_favorite,
        is_finished_artwork
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
      saved: true,
      image_id: row.id,
      title: row.title,
      notes: row.notes,
      source_url: row.source_url,
      is_favorite: row.is_favorite,
      is_finished_artwork: row.is_finished_artwork,
    });
  } catch (error) {
    console.error('save-image-metadata failed:', error);

    return jsonResponse(
      {
        error: 'Unable to save image metadata',
        details: String(error),
      },
      500,
    );
  } finally {
    connection.release();
  }
});
