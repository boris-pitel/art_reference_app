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
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
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

  if (request.method !== 'GET') {
    return jsonResponse(
      {
        error: 'GET required',
      },
      405,
    );
  }

  const userId =
    request.headers.get('x-user-id');

  const imageId =
    new URL(request.url).searchParams.get('id');

  if (!userId || !imageId) {
    return jsonResponse(
      {
        error:
          'x-user-id and image id are required',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    const result =
        await connection.queryObject<{
      storage_path: string | null;
    }>`
      select storage_path
      from public.image_assets
      where id = ${imageId}
        and user_id = ${userId}
      limit 1
    `;

    if (result.rows.length === 0) {
      return jsonResponse(
        {
          error: 'Image not found',
        },
        404,
      );
    }

    const storagePath =
      result.rows[0].storage_path;

    if (
      storagePath === null ||
      storagePath.trim().length === 0
    ) {
      return jsonResponse(
        {
          error:
            'The image does not have a Storage path',
        },
        404,
      );
    }

    const {
      data,
      error: downloadError,
    } = await supabase.storage
      .from(bucketName)
      .download(storagePath);

    if (downloadError) {
      console.error(
        'Storage download failed:',
        downloadError,
      );

      return jsonResponse(
        {
          error:
            'Unable to download image from Storage: ' +
            downloadError.message,
        },
        500,
      );
    }

    if (!data) {
      return jsonResponse(
        {
          error: 'Storage returned no image data',
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
            'private, max-age=3600',
        },
      },
    );
  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to retrieve image',
      },
      500,
    );
  } finally {
    connection.release();
  }
});