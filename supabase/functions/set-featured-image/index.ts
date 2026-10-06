import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 as uuidv5 } from 'npm:uuid@11';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!databaseUrl || !supabaseUrl || !serviceRoleKey) {
  throw new Error('Supabase configuration is missing');
}
const pool = new Pool(databaseUrl, 1, true);
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-id',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return respond({ error: 'POST required' }, 405);
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  const userId = request.headers.get('x-user-id');
  if (!token || !userId) return respond({ error: 'Authentication required' }, 401);
  const { data: auth, error: authError } = await supabase.auth.getUser(token);
  if (authError || !auth.user?.email) return respond({ error: 'Invalid session' }, 401);
  const expectedUserId = uuidv5(
    `art-reference-user:${auth.user.email.trim().toLowerCase()}`,
    uuidv5.URL,
  );
  if (userId !== expectedUserId) return respond({ error: 'Invalid user' }, 403);

  let body: { parentImageId?: string; childImageId?: string | null; onlyIfUnset?: boolean };
  try {
    body = await request.json();
  } catch (_) {
    return respond({ error: 'Invalid JSON body' }, 400);
  }
  const parentId = body.parentImageId;
  const childId = body.childImageId ?? null;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!parentId || !uuid.test(parentId) || (childId !== null && !uuid.test(childId))) {
    return respond({ error: 'Invalid image ID' }, 400);
  }

  const connection = await pool.connect();
  try {
    await connection.queryArray('begin');
    const parent = await connection.queryObject<{
      user_id: string;
      featured_child_image_id: string | null;
    }>`
      select user_id, featured_child_image_id
      from public.image_assets where id = ${parentId} for update
    `;
    const row = parent.rows[0];
    if (!row || row.user_id !== userId) {
      await connection.queryArray('rollback');
      return respond({ error: 'Reference not found' }, 404);
    }
    if (body.onlyIfUnset && row.featured_child_image_id) {
      await connection.queryArray('commit');
      return respond({ featured_image_id: row.featured_child_image_id });
    }
    if (childId) {
      const child = await connection.queryObject<{ id: string }>`
        select child.id from public.image_relationships relation
        join public.image_assets child on child.id = relation.child_image_id
        where relation.parent_image_id = ${parentId}
          and relation.child_image_id = ${childId}
          and child.user_id = ${userId}
        limit 1
      `;
      if (child.rows.length === 0) {
        await connection.queryArray('rollback');
        return respond({ error: 'Associated image not found' }, 404);
      }
    }
    await connection.queryArray`
      update public.image_assets
      set featured_child_image_id = ${childId}
      where id = ${parentId}
    `;
    await connection.queryArray('commit');
    return respond({ featured_image_id: childId });
  } catch (error) {
    await connection.queryArray('rollback');
    console.error(error);
    return respond({ error: 'Unable to update featured image' }, 500);
  } finally {
    connection.release();
  }
});
