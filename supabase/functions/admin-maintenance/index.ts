import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 as uuidv5 } from 'npm:uuid@11';

const supabaseUrl = Deno.env.get('SUPABASE_URL');
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error('Required Supabase environment variables are unavailable');
}

const adminClient = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
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

async function requireAdmin(request: Request) {
  const authorization = request.headers.get('authorization') ?? '';
  const token = authorization.replace(/^Bearer\s+/i, '').trim();
  if (!token) return null;
  const { data, error } = await adminClient.auth.getUser(token);
  if (error || !data.user || data.user.app_metadata?.is_admin !== true) {
    return null;
  }
  return data.user;
}

async function listAllUsers() {
  const users = [];
  for (let page = 1; ; page += 1) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage: 200,
    });
    if (error) throw error;
    users.push(...data.users);
    if (data.users.length < 200) break;
  }
  const { data: profiles, error: profilesError } = await adminClient
    .from('user_profiles')
    .select('auth_user_id,login_name');
  if (profilesError) throw profilesError;
  const profilesByUserId = new Map(
    (profiles ?? []).map((profile) => [profile.auth_user_id, profile]),
  );
  return users
    .sort((a, b) => (a.email ?? '').localeCompare(b.email ?? ''))
    .map((user) => ({
      id: user.id,
      email: user.email,
      login_name: profilesByUserId.get(user.id)?.login_name ?? null,
      is_admin: user.app_metadata?.is_admin === true,
      created_at: user.created_at,
      last_sign_in_at: user.last_sign_in_at,
    }));
}

function dataUserIdForEmail(email: string) {
  return uuidv5(
    `art-reference-user:${email.trim().toLowerCase()}`,
    uuidv5.URL,
  );
}

async function listStorageTree(bucket: string, root: string) {
  const paths: string[] = [];
  async function walk(folder: string) {
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await adminClient.storage.from(bucket).list(
        folder,
        { limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } },
      );
      if (error) throw error;
      for (const entry of data ?? []) {
        const path = folder ? `${folder}/${entry.name}` : entry.name;
        if (entry.id) paths.push(path);
        else await walk(path);
      }
      if ((data?.length ?? 0) < 1000) break;
    }
  }
  await walk(root);
  return paths;
}

async function userInventory(userId: string, currentAdminId: string) {
  const { data: userResult, error: userError } =
    await adminClient.auth.admin.getUserById(userId);
  if (userError || !userResult.user) {
    throw new Error('User not found');
  }
  const user = userResult.user;
  const email = user.email ?? '';
  const dataUserId = dataUserIdForEmail(email);
  const [imagesResult, categoriesResult, profileResult] = await Promise.all([
    adminClient
      .from('image_assets')
      .select('storage_path,thumbnail_storage_path')
      .eq('user_id', dataUserId),
    adminClient
      .from('reference_categories')
      .select('thumbnail_asset')
      .eq('user_id', dataUserId)
      .eq('is_builtin', false),
    adminClient
      .from('user_profiles')
      .select('login_name')
      .eq('auth_user_id', user.id)
      .maybeSingle(),
  ]);
  if (imagesResult.error) throw imagesResult.error;
  if (categoriesResult.error) throw categoriesResult.error;
  if (profileResult.error) throw profileResult.error;

  const paths: Record<string, Set<string>> = {
    'reference-images': new Set<string>(),
    'art-images': new Set<string>(),
    'category-covers': new Set<string>(),
    'feedback-attachments': new Set<string>(),
  };
  for (const image of imagesResult.data ?? []) {
    for (const field of ['storage_path', 'thumbnail_storage_path']) {
      const value = image[field as keyof typeof image];
      if (typeof value === 'string' && value) {
        paths['reference-images'].add(value);
      }
    }
  }
  for (const category of categoriesResult.data ?? []) {
    const value = category.thumbnail_asset;
    const prefix = 'storage://category-covers/';
    if (typeof value === 'string' && value.startsWith(prefix)) {
      paths['category-covers'].add(value.substring(prefix.length));
    }
  }
  const storageRoots: Array<[string, string]> = [
    ['reference-images', dataUserId],
    ['art-images', dataUserId],
    ['category-covers', user.id],
    ['feedback-attachments', user.id],
  ];
  for (const [bucket, root] of storageRoots) {
    for (const path of await listStorageTree(bucket, root)) {
      paths[bucket].add(path);
    }
  }
  const storageFileCount = Object.values(paths).reduce(
    (total, entries) => total + entries.size,
    0,
  );
  return {
    user,
    dataUserId,
    paths,
    details: {
      id: user.id,
      email,
      login_name: profileResult.data?.login_name ?? null,
      phone: user.phone,
      is_admin: user.app_metadata?.is_admin === true,
      is_current_user: user.id === currentAdminId,
      created_at: user.created_at,
      last_sign_in_at: user.last_sign_in_at,
      image_count: imagesResult.data?.length ?? 0,
      category_count: categoriesResult.data?.length ?? 0,
      storage_file_count: storageFileCount,
    },
  };
}

async function setLoginName(userId: string, loginName: string | null) {
  const normalized = loginName?.trim();
  const value = !normalized ? null : normalized;
  if (value !== null && value.length > 50) {
    throw new Error('Login name must be 50 characters or fewer.');
  }
  const { error } = await adminClient
    .from('user_profiles')
    .update({ login_name: value })
    .eq('auth_user_id', userId);
  if (error) {
    if (error.code === '23505') {
      throw new Error('That login name is already taken.');
    }
    throw error;
  }
}

async function logAdminAction(
  adminId: string,
  adminEmail: string,
  operation: string,
  // Null for global actions such as a service-status change, which have no
  // subject user.
  targetId: string | null,
  details: Record<string, unknown>,
  targetType = 'user',
) {
  const { error } = await adminClient.from('user_activity_logs').insert({
    user_id: adminId,
    user_email: adminEmail,
    session_id: crypto.randomUUID(),
    operation,
    status: 'succeeded',
    target_type: targetType,
    target_id: targetId,
    platform: 'admin-maintenance',
    app_version: 'server',
    details,
  });
  if (error) {
    console.error('Unable to record admin activity log', error);
  }
}

async function impersonateUser(userId: string, adminId: string) {
  if (userId === adminId) {
    throw new Error('You cannot impersonate your own account');
  }
  const { data: userResult, error: userError } =
    await adminClient.auth.admin.getUserById(userId);
  if (userError || !userResult.user) {
    throw new Error('User not found');
  }
  const email = userResult.user.email;
  if (!email) {
    throw new Error('That user has no email address to sign in with');
  }
  const { data: linkData, error: linkError } =
    await adminClient.auth.admin.generateLink({
      type: 'magiclink',
      email,
    });
  if (linkError || !linkData?.properties?.hashed_token) {
    throw new Error(
      linkError?.message ?? 'Unable to generate an impersonation token',
    );
  }
  return { email, token_hash: linkData.properties.hashed_token };
}

async function removeUser(userId: string, email: string, adminId: string) {
  if (userId === adminId) throw new Error('You cannot remove your own account');
  const inventory = await userInventory(userId, adminId);
  if (inventory.details.email.toLowerCase() !== email.trim().toLowerCase()) {
    throw new Error('Email confirmation does not match the selected user');
  }
  for (const [bucket, entries] of Object.entries(inventory.paths)) {
    const paths = [...entries];
    for (let start = 0; start < paths.length; start += 1000) {
      const { error } = await adminClient.storage
        .from(bucket)
        .remove(paths.slice(start, start + 1000));
      if (error) throw error;
    }
  }
  const { error: databaseError } = await adminClient.rpc(
    'admin_delete_user_data',
    {
      target_user_id: inventory.dataUserId,
      target_email: inventory.details.email,
    },
  );
  if (databaseError) throw databaseError;
  const { error: authError } = await adminClient.auth.admin.deleteUser(userId);
  if (authError) throw authError;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (
    request.method !== 'GET' &&
    request.method !== 'POST' &&
    request.method !== 'PATCH' &&
    request.method !== 'DELETE'
  ) {
    return jsonResponse(
      { error: 'GET, POST, PATCH, or DELETE required' },
      405,
    );
  }

  const admin = await requireAdmin(request);
  if (!admin) {
    return jsonResponse({ error: 'Administrator access required' }, 403);
  }

  try {
    if (request.method === 'POST') {
      const body = await request.json().catch(() => null);
      const action = body?.action;

      // Handled before the user_id check below: service status is global and
      // has no subject user.
      if (action === 'set_app_status') {
        const enabled = body?.maintenance_enabled === true;
        const rawMessage = body?.message;
        const message = typeof rawMessage === 'string' && rawMessage.trim().length > 0
          ? rawMessage.trim()
          : null;

        const { error } = await adminClient
          .from('app_status')
          .update({
            maintenance_enabled: enabled,
            message,
            updated_at: new Date().toISOString(),
            updated_by: admin.email ?? admin.id,
          })
          .eq('id', true);

        if (error) {
          return jsonResponse(
            { error: `Unable to update service status: ${error.message}` },
            500,
          );
        }

        await logAdminAction(
          admin.id,
          admin.email ?? '',
          'admin_set_app_status',
          null,
          { maintenance_enabled: enabled, message },
          'system',
        );

        return jsonResponse({ maintenance_enabled: enabled, message });
      }

      const userId = body?.user_id;
      if (typeof userId !== 'string' || userId.trim().length === 0) {
        return jsonResponse({ error: 'User ID is required' }, 400);
      }
      if (action === 'impersonate') {
        const result = await impersonateUser(userId, admin.id);
        await logAdminAction(
          admin.id,
          admin.email ?? '',
          'admin_impersonate_user',
          userId,
          { impersonated_email: result.email },
        );
        return jsonResponse(result);
      }
      return jsonResponse({ error: 'Unsupported action' }, 400);
    }

    if (request.method === 'DELETE') {
      const body = await request.json().catch(() => null);
      const userId = body?.user_id;
      const email = body?.email;
      if (typeof userId !== 'string' || typeof email !== 'string') {
        return jsonResponse({ error: 'User ID and email are required' }, 400);
      }
      await removeUser(userId, email, admin.id);
      return jsonResponse({ removed: true });
    }

    if (request.method === 'PATCH') {
      const body = await request.json().catch(() => null);
      const userId = body?.user_id;
      const loginName = body?.login_name;
      if (typeof userId !== 'string' || userId.trim().length === 0) {
        return jsonResponse({ error: 'User ID is required' }, 400);
      }
      if (loginName !== null && typeof loginName !== 'string') {
        return jsonResponse({ error: 'login_name must be a string or null' }, 400);
      }
      await setLoginName(userId, loginName);
      const inventory = await userInventory(userId, admin.id);
      return jsonResponse({ user: inventory.details });
    }

    const userId = new URL(request.url).searchParams.get('user_id');
    if (userId) {
      const inventory = await userInventory(userId, admin.id);
      return jsonResponse({ user: inventory.details });
    }

    const [users, feedbackResult, activityResult] = await Promise.all([
      listAllUsers(),
      adminClient
        .from('user_feedback')
        .select(
          'id,user_email,feedback_type,comment,status,platform,app_version,created_at',
        )
        .order('created_at', { ascending: false })
        .limit(200),
      adminClient
        .from('user_activity_logs')
        .select(
          'id,user_email,operation,status,target_type,target_id,duration_ms,error_code,error_message,created_at',
        )
        .order('created_at', { ascending: false })
        .limit(300),
    ]);
    if (feedbackResult.error) throw feedbackResult.error;
    if (activityResult.error) throw activityResult.error;
    return jsonResponse({
      requested_by: admin.email,
      users,
      feedback: feedbackResult.data ?? [],
      activity: activityResult.data ?? [],
    });
  } catch (error) {
    console.error('admin-maintenance failed', error);
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse(
      { error: message || 'Maintenance operation failed' },
      500,
    );
  }
});
