import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!databaseUrl || !supabaseUrl || !serviceRoleKey) {
  throw new Error('Required Supabase environment variables are unavailable');
}

const pool = new Pool(databaseUrl, 1, true);
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'GET') {
    return jsonResponse({ error: 'GET required' }, 405);
  }
  const userId = request.headers.get('x-user-id')?.trim();
  if (!userId) {
    return jsonResponse({ error: 'x-user-id is missing' }, 400);
  }

  const connection = await pool.connect();
  try {
    const result = await connection.queryObject<{
      id: string;
      date_added: Date;
      storage_path: string;
      thumbnail_storage_path: string | null;
      parent_image_id: string;
      parent_storage_path: string;
    }>`
      select
        artwork.id,
        artwork.date_added,
        artwork.storage_path,
        artwork.thumbnail_storage_path,
        min(relationship.parent_image_id::text) as parent_image_id,
        min(parent.storage_path) as parent_storage_path
      from public.image_assets artwork
      join public.image_relationships relationship
        on relationship.child_image_id = artwork.id
      join public.image_assets parent
        on parent.id = relationship.parent_image_id
        and parent.user_id = artwork.user_id
      where artwork.user_id = ${userId}::uuid
        and artwork.is_finished_artwork = true
      group by artwork.id
      having count(*) = 1
      order by artwork.date_added desc
    `;

    const paths = result.rows.flatMap((row) => [
      row.storage_path,
      ...(row.thumbnail_storage_path ? [row.thumbnail_storage_path] : []),
      row.parent_storage_path,
    ]);
    if (paths.length === 0) {
      return jsonResponse([]);
    }
    const { data, error } = await supabase.storage
      .from('reference-images')
      .createSignedUrls([...new Set(paths)], 60 * 60);
    if (error) throw error;
    const urls = new Map(
      (data ?? []).flatMap((item) =>
        item.path && item.signedUrl ? [[item.path, item.signedUrl]] : [],
      ),
    );
    return jsonResponse(
      result.rows.map((row) => ({
        id: row.id,
        date_added:
          row.date_added instanceof Date
            ? row.date_added.toISOString()
            : String(row.date_added),
        image_url: urls.get(row.storage_path) ?? null,
        thumbnail_url: row.thumbnail_storage_path
          ? urls.get(row.thumbnail_storage_path) ?? null
          : null,
        parent_image_id: row.parent_image_id,
        parent_image_url: urls.get(row.parent_storage_path) ?? null,
      })),
    );
  } catch (error) {
    console.error(error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : 'Unable to list artwork' },
      500,
    );
  } finally {
    connection.release();
  }
});
