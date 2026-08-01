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
const signedUrlLifetimeSeconds = 60 * 60;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id, x-category-code',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
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

type ImageRow = {
  id: string;
  date_added: string;
  storage_path: string;
  thumbnail_storage_path: string | null;
};

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

  const userId = request.headers.get('x-user-id');
  const categoryCode =
    request.headers.get('x-category-code');

  if (!userId) {
    return jsonResponse(
      {
        error: 'x-user-id is missing',
      },
      400,
    );
  }

  if (!categoryCode) {
    return jsonResponse(
      {
        error: 'x-category-code is missing',
      },
      400,
    );
  }

  const connection = await pool.connect();

  try {
    const result =
        await connection.queryObject<ImageRow>`
      select
        ia.id,
        ia.date_added,
        ia.storage_path,
        ia.thumbnail_storage_path
      from public.image_assets ia
      inner join public.image_categories ic
        on ic.image_id = ia.id
      where ia.user_id = ${userId}
        and ic.category_code = ${categoryCode}
      order by ia.date_added desc
    `;

    const allPaths = <string>[];

    for (const row of result.rows) {
      allPaths.push(row.storage_path);

      if (row.thumbnail_storage_path) {
        allPaths.push(row.thumbnail_storage_path);
      }
    }

    const uniquePaths = [...new Set(allPaths)];
    const signedUrlByPath = new Map<string, string>();

    if (uniquePaths.length > 0) {
      const {
        data: signedUrlData,
        error: signedUrlError,
      } = await supabase.storage
        .from(bucketName)
        .createSignedUrls(
          uniquePaths,
          signedUrlLifetimeSeconds,
        );

      if (signedUrlError) {
        throw new Error(
          'Unable to create signed image URLs: ' +
            signedUrlError.message,
        );
      }

      for (const item of signedUrlData ?? []) {
        if (item.path && item.signedUrl) {
          signedUrlByPath.set(
            item.path,
            item.signedUrl,
          );
        }
      }
    }

    const responseRows = result.rows.map((row) => {
      const imageUrl =
        signedUrlByPath.get(row.storage_path) ??
        null;

      const thumbnailUrl =
        row.thumbnail_storage_path === null
          ? null
          : signedUrlByPath.get(
                row.thumbnail_storage_path,
              ) ?? null;

      return {
        id: row.id,
        date_added: row.date_added,
        image_url: imageUrl,
        thumbnail_url: thumbnailUrl,
      };
    });

    return jsonResponse(responseRows, 200);
  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to list images',
      },
      500,
    );
  } finally {
    connection.release();
  }
});