import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get(
  'SUPABASE_SERVICE_ROLE_KEY',
);

if (!databaseUrl) {
  throw new Error(
    'SUPABASE_DB_URL is not available',
  );
}

if (!supabaseUrl) {
  throw new Error(
    'SUPABASE_URL is not available',
  );
}

if (!serviceRoleKey) {
  throw new Error(
    'SUPABASE_SERVICE_ROLE_KEY is not available',
  );
}

const pool = new Pool(
  databaseUrl,
  1,
  true,
);

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
    'authorization, x-client-info, apikey, content-type, x-user-id, x-parent-image-id, x-child-image-id',
  'Access-Control-Allow-Methods':
    'POST, OPTIONS',
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
  const value = request.headers.get(
    headerName,
  );

  if (
    value === null ||
    value.trim().length === 0
  ) {
    throw new Error(
      `${headerName} header is required`,
    );
  }

  return value.trim();
}

async function deleteStorageObjects(
  storagePath: string | null,
  thumbnailStoragePath: string | null,
): Promise<void> {
  const paths: string[] = [];

  if (
    storagePath !== null &&
    storagePath.trim().length > 0
  ) {
    paths.push(
      storagePath.trim(),
    );
  }

  if (
    thumbnailStoragePath !== null &&
    thumbnailStoragePath.trim().length > 0
  ) {
    paths.push(
      thumbnailStoragePath.trim(),
    );
  }

  if (paths.length === 0) {
    return;
  }

  const {
    error,
  } = await supabase.storage
    .from(bucketName)
    .remove(paths);

  if (error) {
    throw new Error(
      `Unable to delete image files: ${error.message}`,
    );
  }
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

  let userId: string;
  let parentImageId: string;
  let childImageId: string;

  try {
    userId = requiredHeader(
      request,
      'x-user-id',
    );

    parentImageId = requiredHeader(
      request,
      'x-parent-image-id',
    );

    childImageId = requiredHeader(
      request,
      'x-child-image-id',
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

  if (parentImageId === childImageId) {
    return jsonResponse(
      {
        error:
          'An image cannot be associated with itself',
      },
      400,
    );
  }

  const connection = await pool.connect();

  let transactionStarted = false;

  try {
    await connection.queryArray`
      begin
    `;

    transactionStarted = true;

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
      await connection.queryArray`
        rollback
      `;

      transactionStarted = false;

      return jsonResponse(
        {
          error:
            'The parent reference does not exist',
        },
        404,
      );
    }

    const childImage =
      await connection.queryObject<{
        id: string;
        storage_path: string | null;
        thumbnail_storage_path:
          string | null;
      }>`
        select
          ia.id,
          ia.storage_path,
          ia.thumbnail_storage_path
        from public.image_assets ia
        where ia.id = ${childImageId}
          and ia.user_id = ${userId}
        for update
      `;

    if (childImage.rows.length === 0) {
      await connection.queryArray`
        rollback
      `;

      transactionStarted = false;

      return jsonResponse(
        {
          error:
            'The associated image does not exist',
        },
        404,
      );
    }

    const relationship =
      await connection.queryObject<{
        parent_image_id: string;
        child_image_id: string;
      }>`
        select
          relationship.parent_image_id,
          relationship.child_image_id
        from public.image_relationships relationship
        where relationship.parent_image_id =
            ${parentImageId}
          and relationship.child_image_id =
            ${childImageId}
        limit 1
      `;

    if (relationship.rows.length === 0) {
      await connection.queryArray`
        rollback
      `;

      transactionStarted = false;

      return jsonResponse(
        {
          error:
            'This image is not associated with the specified reference',
        },
        404,
      );
    }

    await connection.queryArray`
      delete from public.image_relationships
      where parent_image_id = ${parentImageId}
        and child_image_id = ${childImageId}
    `;

    const remainingRelationships =
      await connection.queryObject<{
        relationship_count: number;
      }>`
        select
          count(*)::integer
            as relationship_count
        from public.image_relationships
        where child_image_id = ${childImageId}
      `;

    const remainingRelationshipCount =
      remainingRelationships
        .rows[0]
        ?.relationship_count ?? 0;

    if (remainingRelationshipCount > 0) {
      await connection.queryArray`
        commit
      `;

      transactionStarted = false;

      return jsonResponse(
        {
          removed: true,
          image_deleted: false,
          remaining_relationships:
            remainingRelationshipCount,
        },
        200,
      );
    }

    const storagePath =
      childImage.rows[0].storage_path;

    const thumbnailStoragePath =
      childImage.rows[0]
        .thumbnail_storage_path;

    await connection.queryArray`
      delete from public.image_assets
      where id = ${childImageId}
        and user_id = ${userId}
    `;

    await connection.queryArray`
      commit
    `;

    transactionStarted = false;

    /*
     * Storage deletion happens after the database commit.
     *
     * This avoids leaving a database record that points to
     * files that were already deleted if the transaction
     * itself fails.
     *
     * In the unlikely event that Storage deletion fails,
     * unused files may remain in the bucket, but the app and
     * database remain consistent.
     */
    try {
      await deleteStorageObjects(
        storagePath,
        thumbnailStoragePath,
      );
    } catch (storageError) {
      console.error(
        'The database record was deleted, but Storage cleanup failed:',
        storageError,
      );

      return jsonResponse(
        {
          removed: true,
          image_deleted: true,
          storage_deleted: false,
          warning:
            storageError instanceof Error
              ? storageError.message
              : 'Storage cleanup failed',
        },
        200,
      );
    }

    return jsonResponse(
      {
        removed: true,
        image_deleted: true,
        storage_deleted: true,
        remaining_relationships: 0,
      },
      200,
    );
  } catch (error) {
    if (transactionStarted) {
      try {
        await connection.queryArray`
          rollback
        `;
      } catch (rollbackError) {
        console.error(
          'Rollback failed:',
          rollbackError,
        );
      }
    }

    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to remove associated image',
      },
      500,
    );
  } finally {
    connection.release();
  }
});