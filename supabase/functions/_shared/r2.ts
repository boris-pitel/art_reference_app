/// A minimal S3 client for Cloudflare R2, signed with AWS Signature V4.
///
/// Hand-rolled rather than pulling in the AWS SDK: an Edge Function pays its
/// dependency cost on every cold start, and the four operations needed here —
/// put, get, delete, list — are a small fraction of that SDK.
///
/// Signing is the part that must be exactly right, so it is written once here
/// and shared, rather than repeated per function where the copies would drift.

export interface R2Config {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
}

/// R2 has no regions, but SigV4 requires one in the credential scope and it
/// must match what R2 expects.
const REGION = 'auto';
const SERVICE = 's3';

export function r2ConfigFromEnv(): R2Config | null {
  const accountId = Deno.env.get('R2_ACCOUNT_ID');
  const accessKeyId = Deno.env.get('R2_ACCESS_KEY_ID');
  const secretAccessKey = Deno.env.get('R2_SECRET_ACCESS_KEY');
  const bucket = Deno.env.get('R2_BUCKET');

  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) return null;

  return { accountId, accessKeyId, secretAccessKey, bucket };
}

async function sha256Hex(data: Uint8Array | string): Promise<string> {
  const bytes = typeof data === 'string' ? new TextEncoder().encode(data) : data;
  const digest = await crypto.subtle.digest('SHA-256', bytes as BufferSource);

  return hex(new Uint8Array(digest));
}

function hex(bytes: Uint8Array): string {
  return [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
}

async function hmac(key: Uint8Array, message: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    key as BufferSource,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'HMAC',
    cryptoKey,
    new TextEncoder().encode(message) as BufferSource,
  );

  return new Uint8Array(signature);
}

/// Each path segment is encoded separately so that slashes stay as separators
/// while everything else in a key is escaped.
function encodeKey(key: string): string {
  return key
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

/// Signs and sends one request. Everything else here is a thin wrapper.
export async function r2Request(
  config: R2Config,
  method: string,
  key: string,
  options: {
    body?: Uint8Array;
    query?: Record<string, string>;
    contentType?: string;
  } = {},
): Promise<Response> {
  const host = `${config.accountId}.r2.cloudflarestorage.com`;
  const path = `/${config.bucket}${key ? `/${encodeKey(key)}` : ''}`;

  // Query parameters must be sorted by name for the canonical request, or the
  // signature will not match what the server computes.
  const query = options.query ?? {};
  const canonicalQuery = Object.keys(query)
    .sort()
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(query[k])}`)
    .join('&');

  const now = new Date();
  const amzDate = now.toISOString().replace(/[:-]|\.\d{3}/g, '');
  const dateStamp = amzDate.slice(0, 8);
  const payloadHash = await sha256Hex(options.body ?? new Uint8Array());

  const headers: Record<string, string> = {
    host,
    'x-amz-content-sha256': payloadHash,
    'x-amz-date': amzDate,
  };

  if (options.contentType) headers['content-type'] = options.contentType;

  const signedHeaders = Object.keys(headers).sort();
  const canonicalHeaders = signedHeaders
    .map((name) => `${name}:${headers[name].trim()}\n`)
    .join('');
  const signedHeaderList = signedHeaders.join(';');

  const canonicalRequest = [
    method,
    path,
    canonicalQuery,
    canonicalHeaders,
    signedHeaderList,
    payloadHash,
  ].join('\n');

  const scope = `${dateStamp}/${REGION}/${SERVICE}/aws4_request`;
  const stringToSign = [
    'AWS4-HMAC-SHA256',
    amzDate,
    scope,
    await sha256Hex(canonicalRequest),
  ].join('\n');

  const encoder = new TextEncoder();
  let signingKey = await hmac(
    encoder.encode(`AWS4${config.secretAccessKey}`),
    dateStamp,
  );
  signingKey = await hmac(signingKey, REGION);
  signingKey = await hmac(signingKey, SERVICE);
  signingKey = await hmac(signingKey, 'aws4_request');

  const signature = hex(await hmac(signingKey, stringToSign));

  const url = `https://${host}${path}${
    canonicalQuery ? `?${canonicalQuery}` : ''
  }`;

  return fetch(url, {
    method,
    headers: {
      ...headers,
      Authorization:
        `AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/${scope}, ` +
        `SignedHeaders=${signedHeaderList}, Signature=${signature}`,
    },
    body: options.body as BodyInit | undefined,
  });
}

export async function r2Put(
  config: R2Config,
  key: string,
  body: Uint8Array,
  contentType = 'application/octet-stream',
): Promise<void> {
  const response = await r2Request(config, 'PUT', key, { body, contentType });

  if (!response.ok) {
    throw new Error(`R2 PUT ${key} failed: ${response.status} ${await response.text()}`);
  }

  await response.body?.cancel();
}

export async function r2Get(
  config: R2Config,
  key: string,
): Promise<Uint8Array | null> {
  const response = await r2Request(config, 'GET', key);

  if (response.status === 404) {
    await response.body?.cancel();
    return null;
  }

  if (!response.ok) {
    throw new Error(`R2 GET ${key} failed: ${response.status}`);
  }

  return new Uint8Array(await response.arrayBuffer());
}

/// Whether an object exists, and how large it is, without transferring it.
export async function r2Head(
  config: R2Config,
  key: string,
): Promise<{ size: number } | null> {
  const response = await r2Request(config, 'HEAD', key);
  await response.body?.cancel();

  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`R2 HEAD ${key} failed: ${response.status}`);

  return { size: Number(response.headers.get('content-length') ?? 0) };
}

export async function r2Delete(config: R2Config, key: string): Promise<void> {
  const response = await r2Request(config, 'DELETE', key);
  await response.body?.cancel();

  // 404 is the desired end state, so it is not an error.
  if (!response.ok && response.status !== 404) {
    throw new Error(`R2 DELETE ${key} failed: ${response.status}`);
  }
}

/// Lists keys under a prefix, following continuation tokens.
export async function r2List(
  config: R2Config,
  prefix = '',
): Promise<Array<{ key: string; size: number }>> {
  const found: Array<{ key: string; size: number }> = [];
  let token: string | undefined;

  do {
    const query: Record<string, string> = { 'list-type': '2', prefix };
    if (token) query['continuation-token'] = token;

    const response = await r2Request(config, 'GET', '', { query });

    if (!response.ok) {
      throw new Error(`R2 list failed: ${response.status} ${await response.text()}`);
    }

    const xml = await response.text();

    for (const match of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
      const key = /<Key>([\s\S]*?)<\/Key>/.exec(match[1])?.[1];
      const size = /<Size>(\d+)<\/Size>/.exec(match[1])?.[1];

      if (key) {
        found.push({
          key: key
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>'),
          size: Number(size ?? 0),
        });
      }
    }

    token = /<NextContinuationToken>([\s\S]*?)<\/NextContinuationToken>/
      .exec(xml)?.[1];
  } while (token);

  return found;
}
