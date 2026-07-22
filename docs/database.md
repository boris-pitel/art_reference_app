# Database Design

## Current table: `image_assets`

The current table stores the actual image bytes and basic ownership information.

```sql
create table public.image_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  user_email text,
  image_bytes bytea not null,
  date_added timestamptz not null default now(),
  width integer,
  height integer
);
```

## Planned duplicate detection

Add a SHA-256 hash:

```sql
alter table public.image_assets
  add column if not exists image_hash text;
```

Prevent duplicate images for the same user:

```sql
create unique index if not exists image_assets_user_hash_unique
on public.image_assets (user_id, image_hash);
```

The duplicate check is performed in PostgreSQL using the indexed hash. Flutter does not download the full image list.

## Planned structured tables

### `photo_references`

```text
id
user_id
image_asset_id
category
notes
date_added
```

`image_asset_id` should be unique so the same image cannot become more than one photo reference or belong to multiple categories.

### `keywords`

```text
id
user_id
keyword
```

### `photo_reference_keywords`

```text
photo_reference_id
keyword_id
```

### `artworks`

```text
id
user_id
image_asset_id
title
notes
date_added
```

### `reference_artworks`

```text
photo_reference_id
artwork_id
```

This supports multiple artworks related to one photo reference.
