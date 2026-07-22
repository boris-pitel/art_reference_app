# Architecture

## Current technology

- Flutter and Dart for the client application
- Supabase-managed PostgreSQL for structured data
- Supabase Edge Functions for binary image upload and retrieval
- Git for source control

## Current data flow

### Upload

1. The user selects a photo through the device photo picker.
2. Flutter reads the selected photo as raw bytes.
3. Flutter sends the raw bytes to the `upload-image` Edge Function.
4. The Edge Function inserts the bytes into PostgreSQL as `bytea`.
5. PostgreSQL returns the generated image UUID.
6. Flutter refreshes the displayed image grid.

The image is not converted to hexadecimal or Base64.

### Retrieval

1. Flutter calls `list-images`.
2. The function returns image IDs and metadata, not full images.
3. Flutter calls `get-image` for each needed image.
4. `get-image` returns raw binary bytes.
5. Flutter displays the bytes using `Image.memory`.

## Client structure

```text
lib/
  main.dart
  models/
    artwork.dart
    image_asset.dart
    photo_reference.dart
    reference_category.dart
  screens/
    category_screen.dart
  services/
    image_asset_service.dart
```

## Current temporary user identity

The prototype generates a deterministic UUID from a temporary email address and sends it in request headers.

This is temporary identification, not secure authentication.

Future production versions should use real account authentication.

## Security decision

Database Row Level Security is intentionally not being used at this stage.

Customer separation is currently implemented by application and Edge Function filtering with `user_id`.

This is acceptable only for development. Production authorization must eventually be enforced by a trusted server layer or another secure mechanism.
