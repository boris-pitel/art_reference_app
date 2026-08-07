# Installation

## Version 1.2.0

- Categories opens from a per-user local snapshot and refreshes live data in
  the background.
- Gallery ingestion accepts multiple images, confirms the batch, reports
  per-image progress, continues after failures, and can retry failed items.
- About discloses that optional analysis currently uses OpenAI GPT-5 mini and
  only runs when the user requests it.

## Version 1.1.8

- Sketch saving now shows its current stage and exits with a clear timeout error if a network operation stalls.

## Version 1.1.7

- Associated Image Details now provides a visible Edit action that opens the sketch editor directly.

## Version 1.1.6

- Added a Home button to authenticated secondary screens. It returns directly to the Categories page.

## Version 1.1.5

- Attached-image thumbnails now refresh automatically after returning from an edited sketch.

## Version 1.1.4

- Improved visibility of the editor's Cancel and Save actions.
- Added a blocking progress indicator while a sketch is processed and uploaded.

## Version 1.1.3

- Top-level images now offer **Create sketch** in the Image window.
- A sketch is created only after an edit, preserving the original image and metadata.
- Save remains disabled until the user makes a crop, rotation, or straighten adjustment.

Copy the `docs` folder into the root of your Flutter project:

```text
C:\Development\art_reference_app\docs
```

Then commit it with Git:

```powershell
cd C:\Development\art_reference_app
git add docs
git commit -m "Add project architecture documentation"
```
