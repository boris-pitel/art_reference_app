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

type MoveRequest = {
  user_id?: unknown;
  image_id?: unknown;
  from_category?: unknown;
  to_category?: unknown;
};

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status,
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/json',
        'Cache-Control': 'no-store',
      },
    },
  );
}

function requiredString(
  value: unknown,
  fieldName: string,
): string {
  if (
    typeof value !== 'string' ||
    value.trim().length === 0
  ) {
    throw new Error(`${fieldName} must be a non-empty string`);
  }

  return value.trim();
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders,
    });
  }

  if (request.method !== 'POST') {
    return jsonResponse(
      {
        error: 'POST required',
      },
      405,
    );
  }

  let body: MoveRequest;

  try {
    body = await request.json();
  } catch {
    return jsonResponse(
      {
        error: 'A valid JSON body is required',
      },
      400,
    );
  }

  let userId: string;
  let imageId: string;
  let fromCategory: string;
  let toCategory: string;

  try {
    userId = requiredString(body.user_id, 'user_id');
    imageId = requiredString(body.image_id, 'image_id');
    fromCategory = requiredString(
      body.from_category,
      'from_category',
    );
    toCategory = requiredString(
      body.to_category,
      'to_category',
    );
  } catch (error) {
    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Invalid request',
      },
      400,
    );
  }

  if (fromCategory == toCategory) {
    return jsonResponse(
      {
        error:
          'Source and destination categories are identical.',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    await connection.queryArray`begin`;

    //
    // Verify ownership
    //
    const owned =
      await connection.queryObject<{
        id: string;
      }>`
        select id
        from public.image_assets
        where id = ${imageId}
          and user_id = ${userId}
      `;

    if (owned.rows.length == 0) {
      await connection.queryArray`rollback`;

      return jsonResponse(
        {
          error: 'Image not found.',
        },
        404,
      );
    }

    //
    // Verify image currently belongs to source category
    //
    const source =
      await connection.queryObject`
        select 1
        from public.image_categories
        where image_id = ${imageId}
          and category_code = ${fromCategory}
      `;

    if (source.rows.length == 0) {
      await connection.queryArray`rollback`;

      return jsonResponse(
        {
          error:
            'Image is not in the source category.',
        },
        404,
      );
    }

    //
    // Already in destination?
    //
    const destination =
      await connection.queryObject`
        select 1
        from public.image_categories
        where image_id = ${imageId}
          and category_code = ${toCategory}
      `;

    if (destination.rows.length > 0) {
      await connection.queryArray`rollback`;

      return jsonResponse(
        {
          error:
            'Image already belongs to destination category.',
        },
        409,
      );
    }

    //
    // Add destination FIRST
    //
    await connection.queryArray`
      insert into public.image_categories
      (
        image_id,
        category_code
      )
      values
      (
        ${imageId},
        ${toCategory}
      )
    `;

    //
    // Remove source SECOND
    //
    await connection.queryArray`
      delete
      from public.image_categories
      where image_id = ${imageId}
        and category_code = ${fromCategory}
    `;

    await connection.queryArray`commit`;

    return jsonResponse(
      {
        moved: true,
        image_id: imageId,
        from_category: fromCategory,
        to_category: toCategory,
      },
      200,
    );
  } catch (error) {
    try {
      await connection.queryArray`rollback`;
    } catch (_) {}

    console.error(error);

    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : 'Move failed.',
      },
      500,
    );
  } finally {
    connection.release();
  }
});