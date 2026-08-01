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
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type RemoveRequest = {
  user_id?: unknown;
  image_id?: unknown;
  category_code?: unknown;
};

type StoredImage = {
  id: string;
  storage_path: string | null;
  thumbnail_storage_path: string | null;
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
    throw new Error(
      `${fieldName} must be a non-empty string`,
    );
  }

  return value.trim();
}

async function removeStorageFiles(
  images: StoredImage[],
): Promise<string[]> {
  const paths = new Set<string>();

  for (const image of images) {
    if (
      image.storage_path !== null &&
      image.storage_path.trim().length > 0
    ) {
      paths.add(image.storage_path);
    }

    if (
      image.thumbnail_storage_path !== null &&
      image.thumbnail_storage_path.trim().length > 0
    ) {
      paths.add(image.thumbnail_storage_path);
    }
  }

  if (paths.size === 0) {
    return [];
  }

  const pathList = [...paths];

  const {
    error,
  } = await supabase.storage
    .from(bucketName)
    .remove(pathList);

  if (error) {
    throw new Error(
      `Storage cleanup failed: ${error.message}`,
    );
  }

  return pathList;
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

  let body: RemoveRequest;

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
  let categoryCode: string;

  try {
    userId = requiredString(
      body.user_id,
      'user_id',
    );

    imageId = requiredString(
      body.image_id,
      'image_id',
    );

    categoryCode = requiredString(
      body.category_code,
      'category_code',
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

  const connection = await pool.connect();

  let imagesToDelete: StoredImage[] = [];
  let databaseDeletionCommitted = false;

  try {
    await connection.queryArray`begin`;

    const ownedImage =
      await connection.queryObject<{
        id: string;
      }>`
        select id
        from public.image_assets
        where id = ${imageId}
          and user_id = ${userId}
        limit 1
      `;

    if (ownedImage.rows.length === 0) {
      await connection.queryArray`rollback`;

      return jsonResponse(
        {
          error: 'Image not found',
        },
        404,
      );
    }

    const removedCategory =
      await connection.queryObject<{
        image_id: string;
        category_code: string;
      }>`
        delete from public.image_categories
        where image_id = ${imageId}
          and category_code = ${categoryCode}
        returning
          image_id,
          category_code
      `;

    if (removedCategory.rows.length === 0) {
      await connection.queryArray`rollback`;

      return jsonResponse(
        {
          error:
            'This image is not currently in the specified category',
        },
        404,
      );
    }

    const remainingCategoryResult =
      await connection.queryObject<{
        category_count: number;
      }>`
        select count(*)::int as category_count
        from public.image_categories
        where image_id = ${imageId}
      `;

    const remainingCategories =
      remainingCategoryResult.rows[0]?.category_count ?? 0;

    if (remainingCategories > 0) {
      await connection.queryArray`commit`;

      return jsonResponse(
        {
          removed: true,
          removed_from_category: true,
          image_deleted: false,
          image_id: imageId,
          category_code: categoryCode,
          remaining_categories: remainingCategories,
        },
        200,
      );
    }

    /*
     * Find the parent reference and every associated child image.
     *
     * image_relationships uses:
     *
     * parent_image_id = reference image
     * child_image_id  = associated image
     */
    const relatedImages =
      await connection.queryObject<StoredImage>`
        with recursive image_tree as (
          select
            image.id
          from public.image_assets image
          where image.id = ${imageId}
            and image.user_id = ${userId}

          union

          select
            child.id
          from image_tree parent
          join public.image_relationships relationship
            on relationship.parent_image_id = parent.id
          join public.image_assets child
            on child.id = relationship.child_image_id
          where child.user_id = ${userId}
        )
        select
          image.id,
          image.storage_path,
          image.thumbnail_storage_path
        from public.image_assets image
        join image_tree tree
          on tree.id = image.id
      `;

    imagesToDelete = relatedImages.rows;

    if (imagesToDelete.length === 0) {
      throw new Error(
        'The image deletion set could not be determined',
      );
    }

    for (const image of imagesToDelete) {
      await connection.queryArray`
        delete from public.image_relationships
        where parent_image_id = ${image.id}
           or child_image_id = ${image.id}
      `;
    }

    for (const image of imagesToDelete) {
      await connection.queryArray`
        delete from public.image_categories
        where image_id = ${image.id}
      `;
    }

    for (
      let index = imagesToDelete.length - 1;
      index >= 0;
      index--
    ) {
      const image = imagesToDelete[index];

      await connection.queryArray`
        delete from public.image_assets
        where id = ${image.id}
          and user_id = ${userId}
      `;
    }

    await connection.queryArray`commit`;

    databaseDeletionCommitted = true;
  } catch (error) {
    if (!databaseDeletionCommitted) {
      try {
        await connection.queryArray`rollback`;
      } catch {
        // Ignore rollback errors.
      }
    }

    console.error(
      'remove-image-from-category failed:',
      error,
    );

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to remove image from category',
      },
      500,
    );
  } finally {
    connection.release();
  }

  try {
    const deletedStoragePaths =
      await removeStorageFiles(imagesToDelete);

    return jsonResponse(
      {
        removed: true,
        removed_from_category: true,
        image_deleted: true,
        image_id: imageId,
        category_code: categoryCode,
        remaining_categories: 0,
        deleted_image_count: imagesToDelete.length,
        deleted_storage_file_count:
          deletedStoragePaths.length,
      },
      200,
    );
  } catch (error) {
    console.error(
      'The database rows were deleted, but Storage cleanup failed:',
      error,
    );

    return jsonResponse(
      {
        removed: true,
        removed_from_category: true,
        image_deleted: true,
        image_id: imageId,
        category_code: categoryCode,
        remaining_categories: 0,
        deleted_image_count: imagesToDelete.length,
        storage_cleanup_failed: true,
        storage_cleanup_error:
          error instanceof Error
            ? error.message
            : String(error),
      },
      200,
    );
  }
});