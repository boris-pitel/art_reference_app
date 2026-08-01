import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get(
  'SUPABASE_SERVICE_ROLE_KEY',
);

if (!databaseUrl) {
  throw new Error('SUPABASE_DB_URL is not available');
}

if (!supabaseUrl) {
  throw new Error('SUPABASE_URL is not available');
}

if (!serviceRoleKey) {
  throw new Error(
    'SUPABASE_SERVICE_ROLE_KEY is not available',
  );
}

const pool = new Pool(databaseUrl, 1, true);

const supabase = createClient(
  supabaseUrl,
  serviceRoleKey,
  {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  },
);

const bucketName = 'reference-images';

const signedUrlDurationSeconds = 60 * 60;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id, x-parent-image-id',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

function jsonResponse(
  body: unknown,
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

function requiredHeader(
  request: Request,
  headerName: string,
): string {
  const value = request.headers.get(headerName);

  if (value === null || value.trim().length === 0) {
    throw new Error(
      `${headerName} header is required`,
    );
  }

  return value.trim();
}

async function createSignedUrl(
  storagePath: string | null,
): Promise<string | null> {
  if (
    storagePath === null ||
    storagePath.trim().length === 0
  ) {
    return null;
  }

  const {
    data,
    error,
  } = await supabase.storage
    .from(bucketName)
    .createSignedUrl(
      storagePath,
      signedUrlDurationSeconds,
    );

  if (error) {
    console.error(
      `Unable to create signed URL for ${storagePath}:`,
      error,
    );

    return null;
  }

  return data.signedUrl;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response(
      'ok',
      {
        status: 200,
        headers: corsHeaders,
      },
    );
  }

  if (request.method !== 'GET') {
    return jsonResponse(
      {
        error: 'GET required',
      },
      405,
    );
  }

  let userId: string;
  let parentImageId: string;

  try {
    userId = requiredHeader(
      request,
      'x-user-id',
    );

    parentImageId = requiredHeader(
      request,
      'x-parent-image-id',
    );
  } catch (error) {
    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Invalid request headers',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    const parentImage =
      await connection.queryObject<{
        id: string;
      }>`
        select ia.id
        from public.image_assets ia
        where ia.id = ${parentImageId}
          and ia.user_id = ${userId}
        limit 1
      `;

    if (parentImage.rows.length === 0) {
      return jsonResponse(
        {
          error:
            'The parent reference does not exist',
        },
        404,
      );
    }

    const associatedImages =
      await connection.queryObject<{
        id: string;
        date_added: Date;
        storage_path: string;
        thumbnail_storage_path: string | null;
      }>`
        select
          child.id,
          child.date_added,
          child.storage_path,
          child.thumbnail_storage_path
        from public.image_relationships relationship
        join public.image_assets child
          on child.id = relationship.child_image_id
        where relationship.parent_image_id = ${parentImageId}
          and child.user_id = ${userId}
        order by
          relationship.date_added desc,
          child.date_added desc
      `;

    const results = await Promise.all(
      associatedImages.rows.map(
        async (row) => {
          const imageUrl = await createSignedUrl(
            row.storage_path,
          );

          if (imageUrl === null) {
            throw new Error(
              `Unable to create image URL for ${row.id}`,
            );
          }

          const thumbnailUrl = await createSignedUrl(
            row.thumbnail_storage_path,
          );

          return {
            id: row.id,
            date_added:
              row.date_added instanceof Date
                ? row.date_added.toISOString()
                : String(row.date_added),
            image_url: imageUrl,
            thumbnail_url: thumbnailUrl,
          };
        },
      ),
    );

    return jsonResponse(
      results,
      200,
    );
  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to list associated images',
      },
      500,
    );
  } finally {
    connection.release();
  }
});