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
    'authorization, x-client-info, apikey, content-type, x-user-id, x-user-email, x-category-code',
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

async function calculateSha256(
  imageBytes: Uint8Array,
): Promise<string> {
  const hashBuffer = await crypto.subtle.digest(
    'SHA-256',
    imageBytes,
  );

  return Array.from(
    new Uint8Array(hashBuffer),
  )
    .map(
      (byte) =>
        byte.toString(16).padStart(2, '0'),
    )
    .join('');
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

  const userId =
    request.headers.get('x-user-id');

  const userEmail =
    request.headers.get('x-user-email');

  const categoryCode =
    request.headers.get('x-category-code');

  if (!userId || !userEmail) {
    return jsonResponse(
      {
        error:
          'User identification headers are missing',
      },
      400,
    );
  }

  if (!categoryCode) {
    return jsonResponse(
      {
        error: 'Category code is missing',
      },
      400,
    );
  }

  let uploadedStoragePath: string | null = null;

  try {
    const arrayBuffer =
      await request.arrayBuffer();

    const imageBytes =
      new Uint8Array(arrayBuffer);

    if (imageBytes.length === 0) {
      return jsonResponse(
        {
          error: 'Image body is empty',
        },
        400,
      );
    }

    const imageHash =
      await calculateSha256(imageBytes);

    const connection =
      await pool.connect();

    try {
      await connection.queryArray`begin`;

      const existingImage =
        await connection.queryObject<{
          id: string;
        }>`
          select id
          from public.image_assets
          where user_id = ${userId}
            and image_hash = ${imageHash}
          limit 1
        `;

      if (existingImage.rows.length > 0) {
        const existingImageId =
          existingImage.rows[0].id;

        const existingCategory =
          await connection.queryObject<{
            image_id: string;
          }>`
            select image_id
            from public.image_categories
            where image_id = ${existingImageId}
              and category_code = ${categoryCode}
            limit 1
          `;

        if (existingCategory.rows.length > 0) {
          await connection.queryArray`rollback`;

          return jsonResponse(
            {
              error:
                'This image is already in this category',
              duplicate: true,
              existing_id: existingImageId,
              category_already_present: true,
            },
            409,
          );
        }

        await connection.queryArray`
          insert into public.image_categories (
            image_id,
            category_code
          )
          values (
            ${existingImageId},
            ${categoryCode}
          )
        `;

        await connection.queryArray`commit`;

        return jsonResponse(
          {
            id: existingImageId,
            duplicate: false,
            existing_image: true,
            category_added: true,
            blob_uploaded: false,
          },
          200,
        );
      }

      const imageId = crypto.randomUUID();

      uploadedStoragePath =
        `${userId}/originals/${imageId}`;

      const contentType =
        request.headers.get('content-type') ??
        'application/octet-stream';

      const {
        error: storageUploadError,
      } = await supabase.storage
        .from(bucketName)
        .upload(
          uploadedStoragePath,
          imageBytes,
          {
            contentType,
            upsert: false,
            cacheControl: '3600',
          },
        );

      if (storageUploadError) {
        throw new Error(
          'Storage upload failed: ' +
            storageUploadError.message,
        );
      }

      await connection.queryObject<{
        id: string;
      }>`
        insert into public.image_assets (
          id,
          user_id,
          user_email,
          image_hash,
          storage_path
        )
        values (
          ${imageId},
          ${userId},
          ${userEmail},
          ${imageHash},
          ${uploadedStoragePath}
        )
      `;

      await connection.queryArray`
        insert into public.image_categories (
          image_id,
          category_code
        )
        values (
          ${imageId},
          ${categoryCode}
        )
      `;

      await connection.queryArray`commit`;

      return jsonResponse(
        {
          id: imageId,
          duplicate: false,
          existing_image: false,
          category_added: true,
          blob_uploaded: true,
          storage_path: uploadedStoragePath,
        },
        201,
      );
    } catch (error) {
      try {
        await connection.queryArray`rollback`;
      } catch {
        // Ignore rollback errors.
      }

      throw error;
    } finally {
      connection.release();
    }
  } catch (error) {
    console.error(error);

    if (uploadedStoragePath !== null) {
      try {
        const {
          error: cleanupError,
        } = await supabase.storage
          .from(bucketName)
          .remove([uploadedStoragePath]);

        if (cleanupError) {
          console.error(
            'Unable to remove orphaned Storage file:',
            cleanupError,
          );
        }
      } catch (cleanupError) {
        console.error(
          'Storage cleanup failed:',
          cleanupError,
        );
      }
    }

    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23505'
    ) {
      return jsonResponse(
        {
          error:
            'This image or category relationship already exists',
          duplicate: true,
        },
        409,
      );
    }

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unknown upload error',
      },
      500,
    );
  }
});