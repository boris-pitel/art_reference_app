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

type FinalizeRequest = {
  user_id?: unknown;
  user_email?: unknown;
  category_code?: unknown;
  parent_image_id?: unknown;
  image_hash?: unknown;
  image_id?: unknown;
  storage_path?: unknown;
  thumbnail_storage_path?: unknown;
  original_owner_name?: unknown;
};

type UploadDestination =
  | {
      type: 'category';
      categoryCode: string;
    }
  | {
      type: 'associated';
      parentImageId: string;
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

function optionalString(
  value: unknown,
  fieldName: string,
): string | null {
  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value !== 'string') {
    throw new Error(
      `${fieldName} must be a string`,
    );
  }

  const normalizedValue = value.trim();

  if (normalizedValue.length === 0) {
    return null;
  }

  return normalizedValue;
}

function readUploadDestination(
  body: FinalizeRequest,
): UploadDestination {
  const categoryCode = optionalString(
    body.category_code,
    'category_code',
  );

  const parentImageId = optionalString(
    body.parent_image_id,
    'parent_image_id',
  );

  if (
    categoryCode !== null &&
    parentImageId !== null
  ) {
    throw new Error(
      'Provide either category_code or parent_image_id, not both',
    );
  }

  if (
    categoryCode === null &&
    parentImageId === null
  ) {
    throw new Error(
      'Either category_code or parent_image_id is required',
    );
  }

  if (parentImageId !== null) {
    return {
      type: 'associated',
      parentImageId,
    };
  }

  return {
    type: 'category',
    categoryCode: categoryCode!,
  };
}

async function storageFileExists(
  storagePath: string,
): Promise<boolean> {
  const lastSlashIndex =
    storagePath.lastIndexOf('/');

  if (
    lastSlashIndex <= 0 ||
    lastSlashIndex === storagePath.length - 1
  ) {
    return false;
  }

  const folderPath =
    storagePath.substring(0, lastSlashIndex);

  const fileName =
    storagePath.substring(lastSlashIndex + 1);

  const {
    data,
    error,
  } = await supabase.storage
    .from(bucketName)
    .list(
      folderPath,
      {
        limit: 100,
        search: fileName,
      },
    );

  if (error) {
    throw new Error(
      `Unable to verify uploaded file: ${error.message}`,
    );
  }

  return (data ?? []).some(
    (item) => item.name === fileName,
  );
}

async function removeStorageFiles(
  storagePaths: string[],
): Promise<void> {
  const {
    error,
  } = await supabase.storage
    .from(bucketName)
    .remove(storagePaths);

  if (error) {
    console.error(
      'Unable to remove redundant Storage files:',
      error,
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

  let body: FinalizeRequest;

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
  let userEmail: string;
  let imageHash: string;
  let imageId: string;
  let storagePath: string;
  let thumbnailStoragePath: string;
  let originalOwnerName: string | null;
  let destination: UploadDestination;

  try {
    userId = requiredString(
      body.user_id,
      'user_id',
    );

    userEmail = requiredString(
      body.user_email,
      'user_email',
    ).toLowerCase();

    imageHash = requiredString(
      body.image_hash,
      'image_hash',
    ).toLowerCase();

    imageId = requiredString(
      body.image_id,
      'image_id',
    );

    storagePath = requiredString(
      body.storage_path,
      'storage_path',
    );

    thumbnailStoragePath = requiredString(
      body.thumbnail_storage_path,
      'thumbnail_storage_path',
    );

    originalOwnerName = optionalString(
      body.original_owner_name,
      'original_owner_name',
    );

    destination = readUploadDestination(body);
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

  if (!/^[a-f0-9]{64}$/.test(imageHash)) {
    return jsonResponse(
      {
        error:
          'image_hash must be a SHA-256 hexadecimal value',
      },
      400,
    );
  }

  const expectedStoragePath =
    `${userId}/originals/${imageId}`;

  if (storagePath !== expectedStoragePath) {
    return jsonResponse(
      {
        error:
          'storage_path does not match the user and image ID',
      },
      400,
    );
  }

  const expectedThumbnailStoragePath =
    `${userId}/thumbnails/${imageId}.jpg`;

  if (thumbnailStoragePath !== expectedThumbnailStoragePath) {
    return jsonResponse(
      {
        error:
          'thumbnail_storage_path does not match the user and image ID',
      },
      400,
    );
  }

  if (
    destination.type === 'associated' &&
    destination.parentImageId === imageId
  ) {
    return jsonResponse(
      {
        error:
          'An image cannot be associated with itself',
      },
      400,
    );
  }

  let originalExists: boolean;
  let thumbnailExists: boolean;

  try {
    [originalExists, thumbnailExists] = await Promise.all([
      storageFileExists(storagePath),
      storageFileExists(thumbnailStoragePath),
    ]);
  } catch (error) {
    console.error(error);

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to verify uploaded files',
      },
      500,
    );
  }

  if (!originalExists || !thumbnailExists) {
    return jsonResponse(
      {
        error:
          'The uploaded image files were not found in Storage',
      },
      409,
    );
  }

  const connection = await pool.connect();

  try {
    await connection.queryArray`begin`;

    if (destination.type === 'associated') {
      const parentImage =
        await connection.queryObject<{
          id: string;
        }>`
          select ia.id
          from public.image_assets ia
          where ia.id = ${destination.parentImageId}
            and ia.user_id = ${userId}
          limit 1
        `;

      if (parentImage.rows.length === 0) {
        await connection.queryArray`rollback`;

        await removeStorageFiles([storagePath, thumbnailStoragePath]);

        return jsonResponse(
          {
            error:
              'The parent reference does not exist',
          },
          404,
        );
      }

      const parentCategory =
        await connection.queryObject<{
          image_id: string;
        }>`
          select image_id
          from public.image_categories
          where image_id = ${destination.parentImageId}
          limit 1
        `;

      if (parentCategory.rows.length === 0) {
        await connection.queryArray`rollback`;

        await removeStorageFiles([storagePath, thumbnailStoragePath]);

        return jsonResponse(
          {
            error:
              'Associated images can only be added to a reference image',
          },
          400,
        );
      }
    }

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

      if (destination.type === 'category') {
        const existingParentRelationship =
          await connection.queryObject<{
            parent_image_id: string;
          }>`
            select parent_image_id
            from public.image_relationships
            where child_image_id = ${existingImageId}
            limit 1
          `;

        if (
          existingParentRelationship.rows.length > 0
        ) {
          await connection.queryArray`rollback`;

          if (existingImageId !== imageId) {
            await removeStorageFiles([storagePath, thumbnailStoragePath]);
          }

          return jsonResponse(
            {
              error:
                'This image is already stored as an associated image',
              duplicate: true,
              existing_image: true,
              image_id: existingImageId,
            },
            409,
          );
        }

        const existingCategory =
          await connection.queryObject<{
            image_id: string;
          }>`
            select image_id
            from public.image_categories
            where image_id = ${existingImageId}
              and category_code = ${destination.categoryCode}
            limit 1
          `;

        const categoryAlreadyExists =
          existingCategory.rows.length > 0;

        if (!categoryAlreadyExists) {
          await connection.queryArray`
            insert into public.image_categories (
              image_id,
              category_code
            )
            values (
              ${existingImageId},
              ${destination.categoryCode}
            )
          `;
        }

        await connection.queryArray`commit`;

        if (existingImageId !== imageId) {
          await removeStorageFiles([storagePath, thumbnailStoragePath]);
        }

        return jsonResponse(
          {
            image_id: existingImageId,
            existing_image: true,
            category_added:
              !categoryAlreadyExists,
            category_already_present:
              categoryAlreadyExists,
            relationship_added: false,
            finalized: true,
            upload_type: 'category',
          },
          200,
        );
      }

      if (
        existingImageId ===
        destination.parentImageId
      ) {
        await connection.queryArray`rollback`;

        if (existingImageId !== imageId) {
          await removeStorageFiles([storagePath, thumbnailStoragePath]);
        }

        return jsonResponse(
          {
            error:
              'An image cannot be associated with itself',
          },
          400,
        );
      }

      const existingCategory =
        await connection.queryObject<{
          image_id: string;
        }>`
          select image_id
          from public.image_categories
          where image_id = ${existingImageId}
          limit 1
        `;

      if (existingCategory.rows.length > 0) {
        await connection.queryArray`rollback`;

        if (existingImageId !== imageId) {
          await removeStorageFiles([storagePath, thumbnailStoragePath]);
        }

        return jsonResponse(
          {
            error:
              'This image already exists as a reference',
            duplicate: true,
            existing_image: true,
            image_id: existingImageId,
          },
          409,
        );
      }

      const existingRelationship =
        await connection.queryObject<{
          parent_image_id: string;
        }>`
          select parent_image_id
          from public.image_relationships
          where child_image_id = ${existingImageId}
          limit 1
        `;

      if (
        existingRelationship.rows.length > 0
      ) {
        const existingParentImageId =
          existingRelationship.rows[0]
            .parent_image_id;

        await connection.queryArray`rollback`;

        if (existingImageId !== imageId) {
          await removeStorageFiles([storagePath, thumbnailStoragePath]);
        }

        if (
          existingParentImageId ===
          destination.parentImageId
        ) {
          return jsonResponse(
            {
              error:
                'This image is already associated with this reference',
              duplicate: true,
              relationship_already_present: true,
              existing_image: true,
              image_id: existingImageId,
            },
            409,
          );
        }

        return jsonResponse(
          {
            error:
              'This image is already associated with another reference',
            duplicate: true,
            existing_image: true,
            image_id: existingImageId,
          },
          409,
        );
      }

      await connection.queryArray`
        insert into public.image_relationships (
          parent_image_id,
          child_image_id
        )
        values (
          ${destination.parentImageId},
          ${existingImageId}
        )
      `;

      await connection.queryArray`commit`;

      if (existingImageId !== imageId) {
        await removeStorageFiles([storagePath, thumbnailStoragePath]);
      }

      return jsonResponse(
        {
          image_id: existingImageId,
          existing_image: true,
          category_added: false,
          relationship_added: true,
          finalized: true,
          upload_type: 'associated',
          parent_image_id:
            destination.parentImageId,
        },
        200,
      );
    }

    await connection.queryArray`
      insert into public.image_assets (
        id,
        user_id,
        user_email,
        image_hash,
        storage_path,
        thumbnail_storage_path,
        original_owner_name
      )
      values (
        ${imageId},
        ${userId},
        ${userEmail},
        ${imageHash},
        ${storagePath},
        ${thumbnailStoragePath},
        ${originalOwnerName}
      )
    `;

    if (destination.type === 'category') {
      await connection.queryArray`
        insert into public.image_categories (
          image_id,
          category_code
        )
        values (
          ${imageId},
          ${destination.categoryCode}
        )
      `;

      await connection.queryArray`commit`;

      return jsonResponse(
        {
          image_id: imageId,
          existing_image: false,
          category_added: true,
          category_already_present: false,
          relationship_added: false,
          finalized: true,
          upload_type: 'category',
        },
        201,
      );
    }

    await connection.queryArray`
      insert into public.image_relationships (
        parent_image_id,
        child_image_id
      )
      values (
        ${destination.parentImageId},
        ${imageId}
      )
    `;

    await connection.queryArray`commit`;

    return jsonResponse(
      {
        image_id: imageId,
        existing_image: false,
        category_added: false,
        relationship_added: true,
        finalized: true,
        upload_type: 'associated',
        parent_image_id:
          destination.parentImageId,
      },
      201,
    );
  } catch (error) {
    try {
      await connection.queryArray`rollback`;
    } catch {
      // Ignore rollback errors.
    }

    console.error(error);

    if (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23505'
    ) {
      await removeStorageFiles([storagePath, thumbnailStoragePath]);

      return jsonResponse(
        {
          error:
            'This image or relationship already exists',
          duplicate: true,
        },
        409,
      );
    }

    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Unable to finalize image upload',
      },
      500,
    );
  } finally {
    connection.release();
  }
});