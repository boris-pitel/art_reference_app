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
    'authorization, x-client-info, apikey, content-type, x-user-id, x-image-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
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

  if (request.method !== 'POST') {
    return jsonResponse(
      {
        error: 'POST required',
      },
      405,
    );
  }

  const userId = request.headers.get('x-user-id');
  const imageId = request.headers.get('x-image-id');

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
        error: 'x-image-id is missing',
      },
      400,
    );
  }

  let thumbnailStoragePath: string | null = null;

  try {
    const thumbnailBuffer =
      await request.arrayBuffer();

    const thumbnailBytes =
      new Uint8Array(thumbnailBuffer);

    if (thumbnailBytes.length === 0) {
      return jsonResponse(
        {
          error: 'Thumbnail body is empty',
        },
        400,
      );
    }

    const connection = await pool.connect();

    try {
      const imageResult =
        await connection.queryObject<{
          id: string;
        }>`
          select id
          from public.image_assets
          where id = ${imageId}
            and user_id = ${userId}
          limit 1
        `;

      if (imageResult.rows.length === 0) {
        return jsonResponse(
          {
            error: 'Image was not found',
          },
          404,
        );
      }

      thumbnailStoragePath =
        `${userId}/thumbnails/${imageId}.jpg`;

      const {
        error: storageUploadError,
      } = await supabase.storage
        .from(bucketName)
        .upload(
          thumbnailStoragePath,
          thumbnailBytes,
          {
            contentType: 'image/jpeg',
            cacheControl: '86400',
            upsert: true,
          },
        );

      if (storageUploadError) {
        throw new Error(
          'Thumbnail Storage upload failed: ' +
            storageUploadError.message,
        );
      }

      /*
       * thumbnail_bytes was removed from the database.
       * We now update only thumbnail_storage_path.
       */
      const updateResult =
        await connection.queryObject<{
          id: string;
        }>`
          update public.image_assets
          set thumbnail_storage_path =
            ${thumbnailStoragePath}
          where id = ${imageId}
            and user_id = ${userId}
          returning id
        `;

      if (updateResult.rows.length === 0) {
        throw new Error(
          'Image disappeared before its thumbnail could be saved',
        );
      }

      return jsonResponse(
        {
          id: updateResult.rows[0].id,
          thumbnail_saved: true,
          thumbnail_storage_path:
            thumbnailStoragePath,
        },
        200,
      );
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error(error);

    if (thumbnailStoragePath !== null) {
      try {
        const {
          error: cleanupError,
        } = await supabase.storage
          .from(bucketName)
          .remove([thumbnailStoragePath]);

        if (cleanupError) {
          console.error(
            'Unable to remove thumbnail after failure:',
            cleanupError,
          );
        }
      } catch (cleanupError) {
        console.error(
          'Thumbnail cleanup failed:',
          cleanupError,
        );
      }
    }

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to save thumbnail',
      },
      500,
    );
  }
});