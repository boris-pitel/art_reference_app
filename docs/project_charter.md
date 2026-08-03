# Painter Reference — Project Charter

## Purpose

Build a simple visual reference library for artists. The application helps users collect photo references, organize them into fixed categories, add unlimited keywords, search the library, and link finished artwork to the reference photo that inspired it.

## Intended users

Artists who work from photographic references, including pastel, oil, drawing, watercolor, and mixed-media artists.

The application is intended to support many customer accounts, not only one personal library.

## Core workflow

1. Open the home screen.
2. Select a fixed category.
3. Choose **Add Photo Reference**.
4. Select a photo from the device.
5. Add optional keywords and notes.
6. Save the photo reference.
7. Later, open the reference and choose **Add Related Artwork**.
8. Attach one or more photographs of artwork made from the reference.

## Fixed categories

- Portraits
- Landscapes
- Architecture
- Still Life
- Abstract
- Icon

A photo reference belongs to exactly one category.

## Keywords

Each photo reference may have any number of user-defined keywords.

Examples:

- old man
- profile
- side lighting
- red chair
- winter
- hands visible
- Lisbon
- dramatic sky

## Product rules

- The same image may not be uploaded more than once by the same user.
- Duplicate detection applies across the entire user library, not only inside one category.
- One photo reference belongs to exactly one category.
- One photo reference may have multiple related artworks.
- The interface should remain simple.
- Complexity should be added only when it provides clear value.
