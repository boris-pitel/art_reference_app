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

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
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
      },
    },
  );
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

  if (
    request.method !== 'GET' &&
    request.method !== 'POST'
  ) {
    return jsonResponse(
      {
        error: 'GET or POST required',
      },
      405,
    );
  }

  const requestUrl = new URL(request.url);
  const imageId = requestUrl.searchParams.get('id');
  const userId = request.headers.get('x-user-id');

  if (!userId) {
    return jsonResponse(
      {
        error: 'x-user-id is missing',
      },
      400,
    );
  }

  if (!imageId) {
    return jsonResponse(
      {
        error: 'Image id is missing',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    const result = await connection.queryObject<{
      thumbnail_storage_path: string | null;
      thumbnail_bytes: Uint8Array | null;
    }>`
      select
        thumbnail_storage_path,
        thumbnail_bytes
      from public.image_assets
      where id = ${imageId}
        and user_id = ${userId}
      limit 1
    `;

    if (result.rows.length === 0) {
      return jsonResponse(
        {
          error: 'Image was not found',
        },
        404,
      );
    }

    const row = result.rows[0];

    /*
     * New thumbnails will be stored in Supabase Storage.
     */
    if (
      row.thumbnail_storage_path !== null &&
      row.thumbnail_storage_path.trim().length > 0
    ) {
      const {
        data,
        error: downloadError,
      } = await supabase.storage
        .from(bucketName)
        .download(row.thumbnail_storage_path);

      if (downloadError) {
        console.error(
          'Thumbnail Storage download failed:',
          downloadError,
        );

        return jsonResponse(
          {
            error:
              `Unable to download thumbnail from Storage: ${downloadError.message}`,
          },
          500,
        );
      }

      if (!data) {
        return jsonResponse(
          {
            error: 'Storage returned no thumbnail data',
          },
          500,
        );
      }

      return new Response(
        data,
        {
          status: 200,
          headers: {
            ...corsHeaders,
            'Content-Type':
              data.type || 'application/octet-stream',
            'Cache-Control':
              'private, max-age=86400',
          },
        },
      );
    }

    /*
     * Old thumbnails remain in the thumbnail_bytes column.
     */
    if (
      row.thumbnail_bytes !== null &&
      row.thumbnail_bytes.length > 0
    ) {
      return new Response(
        row.thumbnail_bytes,
        {
          status: 200,
          headers: {
            ...corsHeaders,

            /*
             * application/octet-stream prevents the Flutter web
             * Functions client from trying to decode the binary image
             * as UTF-8 text.
             */
            'Content-Type': 'application/octet-stream',
            'Cache-Control':
              'private, max-age=86400',
          },
        },
      );
    }

    return jsonResponse(
      {
        error: 'Thumbnail is not available',
      },
      404,
    );
  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to download thumbnail',
      },
      500,
    );
  } finally {
    connection.release();
  }
});