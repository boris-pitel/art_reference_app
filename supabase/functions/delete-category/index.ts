import { Pool } from 'jsr:@db/postgres@^0.19.3';
import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 as uuidv5 } from 'npm:uuid@11';

const databaseUrl = Deno.env.get('SUPABASE_DB_URL');
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!databaseUrl || !supabaseUrl || !serviceRoleKey) {
  throw new Error('Required Supabase environment variables are unavailable');
}

const pool = new Pool(databaseUrl, 1, true);
const adminClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    },
  });
}

function dataUserIdForEmail(email: string): string {
  return uuidv5(
    `art-reference-user:${email.trim().toLowerCase()}`,
    uuidv5.URL,
  );
}

async function authenticatedUser(request: Request) {
  const authorization = request.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;

  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data.user?.email) return null;
  return data.user;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required' }, 405);
  }

  const user = await authenticatedUser(request);
  if (!user?.email) {
    return jsonResponse({ error: 'Authentication required' }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: 'A valid JSON body is required' }, 400);
  }

  const categoryId = body.category_id;
  if (
    typeof categoryId !== 'number' ||
    !Number.isSafeInteger(categoryId) ||
    categoryId <= 0
  ) {
    return jsonResponse(
      { error: 'category_id must be a positive integer' },
      400,
    );
  }

  const userId = dataUserIdForEmail(user.email);
  const connection = await pool.connect();

  try {
    await connection.queryArray`begin`;

    const category = await connection.queryObject<{ code: string }>`
      select code
      from public.reference_categories
      where id = ${categoryId}
        and user_id = ${userId}::uuid
        and is_builtin = false
      for update
    `;

    if (category.rows.length === 0) {
      await connection.queryArray`rollback`;
      return jsonResponse({ error: 'Custom category not found' }, 404);
    }

    const categoryCode = category.rows[0].code;
    const inbox = await connection.queryObject`
      select 1
      from public.reference_categories
      where code = 'inbox'
        and is_builtin = true
      limit 1
    `;

    if (inbox.rows.length === 0) {
      await connection.queryArray`rollback`;
      return jsonResponse({ error: 'Inbox category is unavailable' }, 409);
    }

    // Add Inbox first so every affected reference remains visible throughout
    // the transaction. Only images whose last category is being removed move.
    const moved = await connection.queryObject<{ image_id: string }>`
      insert into public.image_categories (image_id, category_code)
      select asset.id, 'inbox'
      from public.image_assets asset
      join public.image_categories target
        on target.image_id = asset.id
       and target.category_code = ${categoryCode}
      where asset.user_id = ${userId}::uuid
        and not exists (
          select 1
          from public.image_categories other
          where other.image_id = asset.id
            and other.category_code <> ${categoryCode}
        )
      on conflict (image_id, category_code) do nothing
      returning image_id
    `;

    await connection.queryArray`
      delete from public.image_categories link
      using public.image_assets asset
      where link.image_id = asset.id
        and link.category_code = ${categoryCode}
        and asset.user_id = ${userId}::uuid
    `;

    await connection.queryArray`
      delete from public.user_category_order
      where auth_user_id = ${user.id}::uuid
        and category_code = ${categoryCode}
    `;

    await connection.queryArray`
      delete from public.reference_categories
      where id = ${categoryId}
        and user_id = ${userId}::uuid
        and is_builtin = false
    `;

    await connection.queryArray`commit`;

    return jsonResponse({
      deleted: true,
      category_code: categoryCode,
      moved_to_inbox: moved.rows.length,
    });
  } catch (error) {
    try {
      await connection.queryArray`rollback`;
    } catch {
      // Ignore rollback errors; the original failure is more useful.
    }
    console.error(error);
    return jsonResponse(
      {
        error: error instanceof Error
          ? error.message
          : 'Category deletion failed',
      },
      500,
    );
  } finally {
    connection.release();
  }
});
