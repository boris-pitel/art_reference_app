import { createClient } from 'npm:@supabase/supabase-js@2';
import { v5 as uuidV5 } from 'npm:uuid@11';
import { placeName } from './place_name.ts';

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

function coordinate(value: unknown, limit: number): number | null {
  return typeof value === 'number' && Number.isFinite(value) &&
      Math.abs(value) <= limit
    ? value
    : null;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'POST required.' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const geoapifyKey = Deno.env.get('GEOAPIFY_API_KEY');
  if (!supabaseUrl || !serviceRoleKey || !geoapifyKey) {
    return jsonResponse({ error: 'Location lookup is not configured.' }, 503);
  }

  const token = (request.headers.get('authorization') ?? '')
    .replace(/^Bearer\s+/i, '')
    .trim();
  if (!token) return jsonResponse({ error: 'Sign in required.' }, 401);

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  const email = authData.user?.email?.trim().toLowerCase();
  if (authError || !email) {
    return jsonResponse({ error: 'Invalid session.' }, 401);
  }

  let imageId: unknown;
  try {
    imageId = (await request.json()).image_id;
  } catch {
    return jsonResponse({ error: 'Invalid request.' }, 400);
  }
  if (typeof imageId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
        .test(imageId)) {
    return jsonResponse({ error: 'Invalid image ID.' }, 400);
  }

  const ownerId = uuidV5(`art-reference-user:${email}`, uuidV5.URL);
  const { data: image, error: imageError } = await supabase
    .from('image_assets')
    .select('shot_location,photo_metadata')
    .eq('id', imageId)
    .eq('user_id', ownerId)
    .maybeSingle();
  if (imageError) {
    console.error('reverse-geocode-photo image lookup failed:', imageError);
    return jsonResponse({ error: 'Unable to load photo location.' }, 500);
  }
  if (!image) return jsonResponse({ error: 'Image not found.' }, 404);

  const saved = typeof image.shot_location === 'string'
    ? image.shot_location.trim()
    : '';
  if (saved) return jsonResponse({ place: saved, source: 'saved' });

  const metadata = image.photo_metadata as Record<string, unknown> | null;
  const latitude = coordinate(metadata?.latitude, 90);
  const longitude = coordinate(metadata?.longitude, 180);
  if (latitude === null || longitude === null) {
    return jsonResponse({ place: null, source: 'none' });
  }

  const url = new URL('https://api.geoapify.com/v1/geocode/reverse');
  url.searchParams.set('lat', String(latitude));
  url.searchParams.set('lon', String(longitude));
  url.searchParams.set('format', 'json');
  url.searchParams.set('apiKey', geoapifyKey);

  try {
    const response = await fetch(url, {
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) {
      console.error('Geoapify reverse geocoding failed:', response.status);
      return jsonResponse({ error: 'Location lookup is unavailable.' }, 502);
    }
    const data = await response.json() as {
      results?: Record<string, unknown>[];
    };
    const place = data.results?.[0] ? placeName(data.results[0]) : null;
    return jsonResponse({ place, source: 'geoapify' });
  } catch {
    // Fetch errors can include the request URL, which contains the API key.
    console.error('Geoapify reverse geocoding request failed.');
    return jsonResponse({ error: 'Location lookup failed.' }, 502);
  }
});
