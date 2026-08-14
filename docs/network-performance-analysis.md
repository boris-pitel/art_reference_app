# Network Performance & DNS Analysis

Date: 2026-08-14

Architectural analysis of reported slow upload/download performance and intermittent DNS resolution problems. Based on a direct read of the codebase (client, edge functions, config) — not speculation. This is an analysis document only; no code changes were made as part of it.

## Why uploads/downloads are slow

**1. Uploads are 4 strictly sequential round trips, never parallelized.**
A new-image upload does: `prepare-image-upload` → PUT to Storage → `finalize-image-upload` → `upload-thumbnail` (`lib/services/image_asset_service.dart:303-435`), each fully awaited before the next starts. Each hop pays its own TLS handshake + request/response latency, and none of it overlaps. This is the single biggest contributor to perceived upload slowness — it's architecturally serial where at least the finalize call and thumbnail upload could plausibly be parallelized, or the thumbnail could be uploaded to a pre-signed URL fetched earlier alongside the original.

**2. No caching layer for downloads.**
No `cached_network_image` or any disk cache is in the dependency tree (`pubspec.yaml`/`pubspec.lock` confirmed absent). Every `Image.network(...)` call (category grids, image details, conversations, keyword search, category cover thumbnails) re-fetches over the network on every screen visit, even for an image just viewed. Combined with Storage's 1-hour signed URLs, revisiting the same image later re-signs and re-downloads it from scratch.

**3. No client-side timeouts anywhere.**
None of the `http`/`supabase_flutter` calls set an explicit timeout (`Supabase.initialize(url: ..., publishableKey: ...)` in `lib/main.dart:27-44` passes no custom `SupabaseClientOptions`, no custom `http.Client`). A slow/stalled DNS resolution or hung TCP connection just sits there rather than failing fast — so what should be a quick retry instead reads as "the app is frozen."

**4. Edge Function cold starts add DB-connection latency on top of DNS.**
Each function (`prepare-image-upload`, `finalize-image-upload`, `upload-thumbnail`, `list-images`, etc.) is its own isolated Deno deployment with its own module-level `Pool(databaseUrl, 1, true)` — pool size hardcoded to 1, connection lazily opened on first request. A cold isolate (after idle/scale-to-zero) pays full DB-connect cost on top of whatever DNS/network latency exists, and a burst of concurrent requests to the same warm isolate serializes on that single pooled connection.

**5. Supabase project region is unknowable from the repo.**
It's a dashboard-time setting, not stored anywhere in `supabase/config.toml` (only `project_id` is present). If it's provisioned far from where the app is actually used, that's baseline latency no code change fixes.

## Why the DNS problem is "intermittent" and hits everything at once

**Everything — REST, Auth, Storage, and every Edge Function — resolves the same single hostname**, `bbcgcrbvxmertipdjczu.supabase.co` (confirmed in the `supabase_flutter`/`supabase` package internals: `_storageUrl = '$supabaseUrl/storage/v1'`, `_functionsUrl = '$supabaseUrl/functions/v1'`; `env` file: `SUPABASE_URL=https://bbcgcrbvxmertipdjczu.supabase.co`). There's no separate `*.functions.supabase.co` or CDN subdomain. This is consistent with the reported symptom: when DNS resolution for that one name hiccups, uploads, downloads, login, and search all appear to fail together — it's not several separate problems, it's one shared hostname having a bad moment.

Compounding that: **there is essentially zero retry logic on any DNS/network-dependent call that matters.** Only the *list* endpoints (`listImages`, `listFinishedArtworks`, `listAssociatedImages` in `image_asset_service.dart`, plus category loading in `main.dart`) have a 3-attempt retry wrapper with 350ms/900ms backoff. Upload, finalize, thumbnail upload, metadata save, move/remove-category, and search all throw immediately on first failure — no retry. On the edge-function side, only `list-images/index.ts` retries `pool.connect()` (150ms/450ms backoff); `prepare-image-upload`, `finalize-image-upload`, and `upload-thumbnail` call `pool.connect()` with no retry at all.

So a DNS blip that would resolve itself in a second or two on retry instead surfaces directly as a user-facing error. There's already a precedent for this exact class of bug: `docs/releases/1.2.0+31.md` mentions fixing logout being blocked by "network/DNS failures" — so this isn't a new failure mode, just one that's been patched in one spot (logout) and not the others.

## Supporting facts

- **HTTP client:** No `dio`, no raw `dart:io HttpClient`. All Supabase calls go through `supabase_flutter` (`^2.16.0`) built on the plain `http` package (`^1.6.0`). Export/print/share/download flows also use `http` directly against signed Storage URLs.
- **Downloads:** List/search edge functions (`list-images/index.ts:163-189`) return direct Supabase Storage *signed* URLs (1-hour TTL) via `createSignedUrls`. The client just consumes these — no separate host, but every fetch is a fresh HTTPS request to the same `supabase.co` host, no persistent cache.
- **Legacy unused pass-through functions** `get-image` and `get-thumbnail` still exist and are registered in `config.toml` (`verify_jwt = false`) but nothing in the current client code calls them.
- **Fire-and-forget activity logging:** Every upload/logout/etc. fires an `unawaited` REST insert via `UserActivityLogger.record` (`lib/services/user_activity_logger.dart:32`) — doesn't block the main flow, but it's another concurrent DNS-dependent call layered on top.
- **No `connectivity_plus`** or any network-state awareness dependency — the app can't distinguish "fully offline" from "DNS temporarily failed," so both surface as the same generic error with no smart retry-on-reconnect behavior.

## Bottom line

The architecture funnels every kind of traffic through one hostname with no retry safety net anywhere except list/category loads, no timeouts, and a fully serial 4-step upload path — so any transient DNS or network hiccup is maximally visible, and normal latency has nowhere to hide via parallelism or caching.

## Possible next steps (not yet scoped or implemented)

- Add a shared retry+timeout wrapper (matching the existing 3-attempt/350ms/900ms pattern already used for list endpoints) around the upload/finalize/thumbnail calls and the `pool.connect()` calls in `prepare-image-upload`/`finalize-image-upload`/`upload-thumbnail`.
- Add `cached_network_image` (or equivalent) for a basic persistent image cache, cutting redundant re-downloads on repeat views.
- Consider parallelizing parts of the upload sequence (e.g. thumbnail upload alongside finalize) where the data dependency allows it.
