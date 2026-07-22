# Edge Function API

## `upload-image`

### Purpose

Upload one image as raw binary data.

### Request

```text
POST /functions/v1/upload-image
Content-Type: application/octet-stream
x-user-id: <temporary user UUID>
x-user-email: <temporary email>
Body: raw image bytes
```

### Success response

```json
{
  "id": "generated-image-uuid"
}
```

### Planned duplicate response

```json
{
  "duplicate": true,
  "id": "existing-image-uuid",
  "category": "portrait"
}
```

## `list-images`

### Purpose

List image IDs and metadata for one user without returning full binary image data.

### Request

```text
GET /functions/v1/list-images
x-user-id: <temporary user UUID>
```

### Response

```json
[
  {
    "id": "image-uuid",
    "date_added": "2026-07-21T12:00:00Z"
  }
]
```

## `get-image`

### Purpose

Download one image as raw bytes.

### Request

```text
GET /functions/v1/get-image?id=<image-uuid>
x-user-id: <temporary user UUID>
```

### Response

```text
Content-Type: application/octet-stream
Body: raw image bytes
```

## Browser support

Every Edge Function used by Flutter Web must handle the `OPTIONS` method and return CORS headers, including any custom request headers.
