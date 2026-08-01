import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!databaseUrl) {
  throw new Error('SUPABASE_DB_URL is not available');
}

if (!supabaseUrl) {
  throw new Error('SUPABASE_URL is not available');
}

if (!serviceRoleKey) {
  throw new Error('SUPABASE_SERVICE_ROLE_KEY is not available');
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
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type SearchRequest = {
  user_id?: unknown;
  query?: unknown;
};

type SearchRow = {
  id: string;
  date_added: string;
  title: string | null;
  notes: string | null;
  storage_path: string;
  thumbnail_storage_path: string | null;
  title_matches: boolean;
  notes_match: boolean;
  matching_keywords: string[] | null;
};

function jsonResponse(
  body: Record<string, unknown> | unknown[],
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
    throw new Error(
      `${fieldName} must be a non-empty string`,
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
    .createSignedUrl(storagePath, 60 * 60);

  if (error) {
    throw new Error(
      `Unable to create signed URL for ${storagePath}: ${error.message}`,
    );
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

  if (request.method !== 'POST') {
    return jsonResponse(
      {
        error: 'POST required',
      },
      405,
    );
  }

  let body: SearchRequest;

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
  let query: string;

  try {
    userId = requiredString(
      body.user_id,
      'user_id',
    );

    query = requiredString(
      body.query,
      'query',
    );
  } catch (error) {
    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Invalid request',
      },
      400,
    );
  }

  if (query.length > 100) {
    return jsonResponse(
      {
        error: 'query must be 100 characters or fewer',
      },
      400,
    );
  }

  const normalizedQuery = query.toLowerCase();

  const connection = await pool.connect();

  try {
    const result =
      await connection.queryObject<SearchRow>`
        select
          image.id,
          image.date_added::text,
          image.title,
          image.notes,
          image.storage_path,
          image.thumbnail_storage_path,

          position(
            ${normalizedQuery}
            in lower(coalesce(image.title, ''))
          ) > 0 as title_matches,

          position(
            ${normalizedQuery}
            in lower(coalesce(image.notes, ''))
          ) > 0 as notes_match,

          coalesce(
            array_agg(
              distinct keyword.keyword
              order by keyword.keyword
            ) filter (
              where position(
                ${normalizedQuery}
                in lower(coalesce(keyword.keyword, ''))
              ) > 0
            ),
            array[]::text[]
          ) as matching_keywords

        from public.image_assets image

        left join public.image_keywords keyword
          on keyword.image_id = image.id
         and keyword.user_id = image.user_id::text

        where image.user_id = ${userId}::uuid

          and exists (
            select 1
            from public.image_categories category_link
            where category_link.image_id = image.id
          )

          and (
            position(
              ${normalizedQuery}
              in lower(coalesce(image.title, ''))
            ) > 0

            or position(
              ${normalizedQuery}
              in lower(coalesce(image.notes, ''))
            ) > 0

            or exists (
              select 1
              from public.image_keywords matching_keyword
              where matching_keyword.image_id = image.id
                and matching_keyword.user_id = image.user_id::text
                and position(
                  ${normalizedQuery}
                  in lower(coalesce(matching_keyword.keyword, ''))
                ) > 0
            )
          )

        group by
          image.id,
          image.date_added,
          image.title,
          image.notes,
          image.storage_path,
          image.thumbnail_storage_path

        order by image.date_added desc

        limit 500
      `;

    const rows = await Promise.all(
      result.rows.map(async (row) => {
        const [
          imageUrl,
          thumbnailUrl,
        ] = await Promise.all([
          createSignedUrl(row.storage_path),
          createSignedUrl(row.thumbnail_storage_path),
        ]);

        if (imageUrl === null) {
          throw new Error(
            `Image ${row.id} does not have a Storage path`,
          );
        }

        const matchedIn: string[] = [];

        if (row.title_matches) {
          matchedIn.push('Title');
        }

        if (row.notes_match) {
          matchedIn.push('Notes');
        }

        if ((row.matching_keywords ?? []).length > 0) {
          matchedIn.push('Keyword');
        }

        return {
          id: row.id,
          date_added: row.date_added,
          image_url: imageUrl,
          thumbnail_url: thumbnailUrl,
          title: row.title,
          notes: row.notes,
          matching_keywords: row.matching_keywords ?? [],
          matched_in: matchedIn,
        };
      }),
    );

    return jsonResponse(rows, 200);
  } catch (error) {
    console.error(
      'search-images failed:',
      error,
    );

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to search images',
      },
      500,
    );
  } finally {
    connection.release();
  }
});