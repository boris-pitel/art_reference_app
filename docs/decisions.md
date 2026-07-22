# Design Decisions

## Fixed categories

The application uses six fixed categories:

- Portraits
- Landscapes
- Architecture
- Still Life
- Abstract
- Icon

Users cannot create additional categories.

## Unlimited keywords

Each photo reference may have any number of user-defined keywords.

## Figure is not a fixed category

Full-body poses, hands, feet, dancers, and similar subjects are represented with keywords inside Portraits or another appropriate category.

## Button wording

Use:

- **Add Photo Reference**
- **Add Related Artwork**

## Category-first workflow

The user opens a category before adding a photo reference. The category is therefore already known and is not requested again.

## One category per reference

A photo reference belongs to exactly one category.

## Duplicate policy

For one user, the same image bytes may appear only once in the entire library.

The duplicate check uses SHA-256 and a unique database index on:

```text
user_id + image_hash
```

The app must not download all images to detect duplicates.

## Related artworks

A photo reference may have multiple related artworks.

## Image representation

`ImageAsset` represents the underlying image.

Photo references and artworks both refer to an `ImageAsset`.

## Current image storage

For the prototype, raw binary bytes are stored in PostgreSQL `bytea` through Supabase Edge Functions.

Images are transferred as raw binary, not hexadecimal or Base64.

## Current authorization

Row Level Security is not used at this stage.

Temporary user identification is derived from an email address. This must be replaced before production.
