# Art Reference App — 1.2.0 build 48

## Overview

**Multi-tier image architecture** to eliminate blank-screen failures when viewing very large photos on devices with limited GPU texture memory. The fix addresses a real issue where uploading 6000×8000 MP camera photos caused the image viewer to fail silently on mobile devices.

## What's New

### 3-Tier Image Derivatives

Images are now automatically processed into three tiers:

- **Thumbnail** (~500px max) – Used in gallery lists and image tiles; optimized for quick load and scrolling.
- **Display** (~3072px max) – NEW; used for the interactive pinch-zoom viewer; sized to fit safely within any mobile device's GPU texture limits.
- **Original** (full resolution) – Preserved unchanged; used only for export, print, and cropping operations.

### Fixes Blank-Screen Viewing Failures

Mobile devices have GPU texture-size limits (typically 2048–4096 px per side). A raw 6000×8000 photo (~192 MB decoded) exceeds all common limits and causes silent rendering failures. With the new display tier, the viewer uses a device-safe ~3072px version (~30 MB decoded), while keeping the full original available for export and print.

### Automatic Backfill

All 201 existing images in your library have been automatically backfilled with display derivatives, so the new viewer optimization is available immediately — no manual action needed.

## Technical Details

**New database column:** `image_assets.display_storage_path` (nullable, for backward compatibility with old uploads).

**New file storage path:** `{userId}/display/{imageId}.jpg`  
All derivatives are JPEG-encoded for maximum compatibility and size efficiency.

**Image processing:**
- Orientation is corrected before resizing (so landscape photos don't rotate unexpectedly).
- Re-encoding at 88% JPEG quality balances file size with visual fidelity on screens.
- Non-upscaling: if an original is already smaller than 3072 px, it's re-encoded as-is rather than enlarged.

**Viewer behavior:**
- Inline preview cards and pinch-zoom viewer use the display tier where available, falling back to original for images uploaded before this release.
- Cropping, export, share, print, and save operations always use the full original, preserving quality for these workflows.

## Deployment Notes

- Backend Edge Functions (prepare-image-upload, finalize-image-upload, get-image-metadata, list-images, search-images, list-finished-artworks, list-associated-images) updated 2026-08-16 at 10:39 UTC.
- Database migration (20260816000000_display_storage_path.sql) applied.
- All 201 existing images backfilled with display derivatives (0 skipped, 0 failed).
- Android and iOS client builds include the new 3-tier upload flow and display-aware viewer.

## Verification

**If you see a blank screen when opening a very large photo in the new build,** please report it with:
- Device model and OS version
- Photo resolution (width × height) if available
- Error details from Activity tab (if any)

---

**Build Date:** 2026-08-16  
**Version:** 1.2.0 (build 48)  
**Changelog Type:** Feature + Bugfix
