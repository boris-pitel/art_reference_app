import { Pool } from 'jsr:@db/postgres@^0.19.3';

/// Counts the images in every category in one call.
///
/// The home screen used to get these numbers by listing each category in full
/// and taking the length. That meant one Edge Function invocation per category,
/// each fetching every image row and signing two storage URLs per image, all of
/// it discarded except the count — roughly fourteen hundred signed URLs to
/// render a dozen numbers, and a refresh that took minutes on a phone.
///
/// Counting belongs in the database. This is one invocation, two grouped
/// queries, no URL signing, and a response of a few hundred bytes that does not
/// grow as the library does.

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');

if (!databaseUrl) {
  throw new Error('SUPABASE_DB_URL is not available');
}

const pool = new Pool(databaseUrl, 1, true);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (request.method !== 'GET' && request.method !== 'POST') {
    return jsonResponse({ error: 'GET or POST required' }, 405);
  }

  const userId = request.headers.get('x-user-id');

  if (!userId) {
    return jsonResponse({ error: 'x-user-id is missing' }, 400);
  }

  let connection: Awaited<ReturnType<typeof pool.connect>> | null = null;

  try {
    let connectionError: unknown;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      try {
        connection = await pool.connect();
        break;
      } catch (error) {
        connectionError = error;
        if (attempt < 2) {
          await new Promise((resolve) =>
            setTimeout(resolve, attempt === 0 ? 150 : 450)
          );
        }
      }
    }

    if (!connection) throw connectionError ?? new Error('Database unavailable');

    const grouped = await connection.queryObject<{
      category_code: string;
      total: number;
    }>`
      select
        ic.category_code,
        count(*)::int as total
      from public.image_assets ia
      join public.image_categories ic
        on ic.image_id = ia.id
      where ia.user_id = ${userId}::uuid
      group by ic.category_code
    `;

    // My Art is not a row in image_categories: it is the set of finished
    // artworks with exactly one parent. Counted the same way the listing
    // builds it, so the number on the home screen matches what opening the
    // category shows.
    const artwork = await connection.queryObject<{ total: number }>`
      select count(*)::int as total
      from (
        select artwork.id
        from public.image_assets artwork
        join public.image_relationships relationship
          on relationship.child_image_id = artwork.id
        join public.image_assets parent
          on parent.id = relationship.parent_image_id
          and parent.user_id = artwork.user_id
        where artwork.user_id = ${userId}::uuid
          and artwork.is_finished_artwork = true
        group by artwork.id
        having count(*) = 1
      ) as solo_parented
    `;

    // Every image this person owns, so the device can drop cached copies of
    // anything deleted elsewhere. Deliberately not derived from the category
    // counts: a third of all images are sketches, which belong to no category
    // at all and would be invisible to anything built on those.
    //
    // Ids only — about 48 bytes each, so a few hundred images cost less than a
    // tenth of one photograph, on a call that already happens every refresh.
    const owned = await connection.queryObject<{ id: string }>`
      select id
      from public.image_assets
      where user_id = ${userId}::uuid
    `;

    const counts: Record<string, number> = {};

    for (const row of grouped.rows) {
      counts[row.category_code] = Number(row.total);
    }

    return jsonResponse(
      {
        counts,
        finished_artwork_count: Number(artwork.rows[0]?.total ?? 0),
        image_ids: owned.rows.map((row) => row.id),
      },
      200,
    );
  } catch (error) {
    console.error('count-images-by-category failed:', error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to count images',
      },
      500,
    );
  } finally {
    connection?.release();
  }
});
