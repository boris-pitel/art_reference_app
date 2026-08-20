# Test plan — 18 August 2026

Verification pass covering the display-tier rollback, Windows sharing, desktop
Save as…, the iOS share handoff, AI edit resolution, the maintenance gate,
thumbnail sizing, and gallery filenames.

A styled version with saved progress is published at
<https://claude.ai/code/artifact/6b04fc15-208b-4f95-a963-858d5b6f55f5>.

Work top to bottom — later steps assume earlier ones passed, so a failure
narrows the cause rather than leaving it ambiguous.

## Before you start

| | |
|---|---|
| Windows | `build\windows\x64\runner\Release\art_reference_app.exe` |
| Web | painterreference.com — hard-refresh first |
| Android | Installed release build |
| Accounts | Your admin login, plus one non-admin login on a second device |

Have ready: one very large photo (~6000×8000), one small image (under 500px on
its longest side), and an empty folder such as `C:\testimages`.

> **Print on iPhone works.** An earlier report that it did nothing turned out to
> be a cached Safari build. Confirmed 18 August: Print opens the share sheet,
> which offers Print, which reaches a printer dialog. A change to hide the
> control on mobile web was written against that false report and has been
> reverted — Print stays everywhere.

## A. Windows desktop app

Covers the empty-share-sheet fix, the Save as… dialog, and the false-success
bug on cancel.

- [ ] **A1** Launch and sign in. → Categories load within a few seconds.
- [ ] **A2** Upload the 6000×8000 photo to a category. → Completes with a
      thumbnail. No error mentioning `display_storage_path`.
- [ ] **A3** Open details → Technical panel. → Reads **6000 × 8000**, the true
      original.
- [ ] **A4** Upload the small image and view its thumbnail. → Not blurry or
      enlarged; small images are no longer upscaled to 500px.
- [ ] **A5** Press Share from image details. → Windows share sheet lists real
      targets, **not** an empty "Try that again" panel.
- [ ] **A6** Share from a category tile, then from a chat image. → All three
      behave alike; they are separate call sites.
- [ ] **A7** Choose **Save as…** and save into `C:\testimages`. → Native dialog;
      file lands there as `art_reference_<id>.jpg`.
- [ ] **A8** Save a second image. → Dialog reopens already in `C:\testimages`.
- [ ] **A9** Start a save, then cancel. → **No** success message.
- [ ] **A10** Complete another save. → Confirmation names the real path.
- [ ] **A11** Press Print. → Windows print dialog opens.
- [ ] **A12** Crop or rotate the large photo and save. → New sketch created,
      original untouched. Note the duration; large edits are slow.

## B. Web — desktop browser

The AI resolution change is the substance here. It is a backend fix, already
live regardless of builds.

- [ ] **B1** Open painterreference.com, hard-refresh, sign in. → The app loads,
      not the old maintenance page.
- [ ] **B2** Open a large image, press Download. → Downloads with a proper
      filename.
- [ ] **B3** Press Print. → Browser print dialog opens; Print stays on desktop.
- [ ] **B4** Open **Edit with AI**. → A notice appears before any credits are
      spent, explaining the result is new and smaller and the original is kept.
- [ ] **B5** Run an AI edit and accept it. → Slower than before; more pixels.
- [x] **B6** Check the result's Technical panel. **Key check.** → Confirmed 18 August:
      **2880 × 2160**, not the old 1427×1102.
- [ ] **B7** Re-check the source image. → Still **6000 × 8000**; the result is
      stored alongside, never in place of it.
- [ ] **B8** Send an image in a conversation, then save it from the chat. →
      Both work; messaging shares the delivery code that changed.

## C. Web — iPhone Safari

The most fragile surface. Safari only allows a share from a live tap, which is
why saving now takes two steps.

- [ ] **C1** Open and hard-refresh (Safari caches aggressively).
- [x] **C2** Press Print, tap **Continue**, choose **Print** in the share sheet.
      → A printer dialog appears. *Confirmed 18 August.* Safari cannot show a
      print dialog directly, so it routes through the share sheet's AirPrint.
- [ ] **C3** Check the save button wording. → Reads **Save image**.
- [ ] **C4** Tap it, wait for the confirmation, tap **Continue**. → iOS share
      sheet opens. The extra tap is deliberate.
- [ ] **C5** Choose **Save Image**, then open Photos. → It is in the camera roll.
- [ ] **C6** Repeat but dismiss the sheet. → No success message.
- [x] **C7** Save the 6000×8000 photo. → A red warning appears saying the image
      is 48 megapixels and Photos will not take it. *Confirmed 18 August.*
      Choosing another destination saves it at full resolution.
- [ ] **C8** Open the 6000×8000 photo full-screen. → **Known risk**: may blank
      or fail. Record it; do not treat it as new.

## D. Android app

The gallery filename fix is the thing to confirm. Existing saves are named
`image (1)` … `image (8)`.

- [ ] **D1** Launch and sign in. → Loads normally. If it hangs, see Known below.
- [ ] **D2** Open an image, choose **Save to Photos**. → Confirms it saved.
- [ ] **D3** Read the new file's name in the gallery. **Key check.** →
      `art_reference_<id>.jpg` in Pictures, **not** `image (9).jpg`.
- [ ] **D4** Save a second image, then re-save the first. → Distinct names; a
      repeat gains a numeric suffix rather than overwriting.
- [ ] **D5** Press Print. → The native Android print dialog opens.

## D-web. Android browser

Confirmed 19 August; listed so the behaviour is not mistaken for a defect.

- [x] **DW1** Press Print on a small image, then on the 6000×8000 photo. → The
      browser's print dialog opens for both. No download, no app chooser.
- [x] **DW2** Save a large photo, choose Photos in the share sheet. → It does
      not arrive. Google Photos accepts the file, shows progress, and drops it.
- [x] **DW3** Save the same photo, choose Files. → Saves intact, proving the
      file handed to the sheet is sound.
- [ ] **DW4** Save an ordinary-sized photo and choose Photos. → Expected to
      work; the size at which Android starts dropping them is unmeasured.
- [ ] **D6** Share an image, and upload a camera photo. → Share sheet appears;
      upload completes.

## E. Maintenance gate

The toggle and the block are already proven. What is untested is the custom
message — every toggle so far sent none.

- [ ] **E1** As admin: gear → Maintenance → wrench icon in that screen's top bar.
      → Dialog with a switch and a message field.
- [ ] **E2** Switch on, type a real message, Apply. **The untested path.** →
      Confirms on; wrench turns orange.
- [ ] **E3** Stay on the admin session. → Orange banner, app still usable.
      Admins are exempt so the off switch stays reachable.
- [ ] **E4** Open the app on the non-admin device. → Blocking screen showing
      **your message**, not the generic fallback.
- [ ] **E5** Press **Try again** while still on. → Stays blocked.
- [ ] **E6** Turn off as admin, press **Try again** on the other device. → Loads
      without reinstall or restart.
- [ ] **E7** Repeat the cycle on the other platforms to hand. → Identical; one
      flag drives web, Windows, and Android.

## Known — do not raise these

- **Photo libraries drop large images silently, on both phones.** Confirmed 19
  August: a 6000×8000 photo shared to Google Photos on Android showed an upload
  progress bar and never appeared, while the same file saved through Files
  intact — so what the app hands over is sound and the destination is not. iOS
  behaves the same way (see below). Neither reports back once the share sheet
  accepts a file, so this cannot be detected, only anticipated: above 32
  megapixels the save dialog now recommends Files instead of Photos.
- **Android web saves through the share sheet, not a download.** A browser
  download can only write to the downloads folder — no web API reaches the
  photo library — so Photos and Gallery are reachable only by sharing. Desktop
  web still downloads, which is what is wanted there.
- **Android web prints an HTML page, not a PDF.** Chrome has no PDF viewer
  inside a frame, so the printing package's PDF route downloads a file and
  offers an app chooser instead of printing, and for a large photo fails with
  ERR_BLOB_OUT_OF_MEMORY. Printing a page works at any size; confirmed 19
  August on both a small image and the 6000×8000 photo.
- **iPhone Photos refuses images above ~32 megapixels.** iOS decodes a JPEG
  only to about that size and importing to Photos requires a decode, so a 48MP
  photo is accepted by the share sheet and silently dropped. Not an app defect
  and not detectable — iOS reports nothing back — so the app warns beforehand
  instead. Other destinations take the full-resolution file: confirmed by
  uploading the same 6000×8000 photo to a cloud app intact, since an upload
  copies bytes without decoding them.
- **Printing on iPhone goes via the share sheet.** Safari cannot open a print
  dialog directly, so Print builds a PDF and hands it to iOS, where AirPrint
  does the printing. The extra tap is required, not a defect.
- **A network blip at launch strands the app.** No timeout, retry, or message.
  Force-quit and reopen. Unfixed.
- **Very large images may fail on mobile.** Consequence of removing the display
  tier; no graceful message exists.
- **Older Android saves keep `image (N)` names.** Only new saves get real names.
- **AI editing cannot return 48MP.** It generates a new image, capped near
  2880×2160 for a 4:3 source.
- **Large-image editing is slow.** Crop and rotate run at full resolution by
  choice, to protect quality.

If the admin gear icon disappears, the session token has likely expired — admin
status silently resolves to false when the check fails. Sign out and back in.
