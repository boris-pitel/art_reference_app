# Admin-only Unison matching experiment

Branch: codex/admin-unison-matching. Windows-only experiment, build 1.2.3+108. Not published.

Open a reference in its full-screen image window. Administrators see a colour-picker icon labelled Match Unison colour (admin). It opens a separate view of the current image; it does not edit or save the image. Click/tap samples a 5x5 area and ranks the catalogue with CIEDE2000; pinch/scroll zoom and pan are available. The image is orientation-corrected and capped at 2000 pixels on its longest edge for the sampling preview. Results show three actual swatch crops, their codes, provisional names, sampled solid colours, and Delta E values.

Admin access is checked using server-managed app_metadata.is_admin in the viewer and matching screen. The screen reads the existing authenticated catalogue; no additional backend endpoint or permission change is required. The catalogue's existing authenticated read policy is unchanged; this is an admin-only matching tool, not a change to catalogue visibility. Signed Storage links are used for swatch previews.

Restricted to native Windows with platform checks at the viewer entry point and matching screen. No web or phone release is included. No backend migration is required beyond the catalogue already created. Provisional scan names and the YGR14 printed-code discrepancy remain flagged.

Validation: sRGB/Lab numerical reference values and five CIEDE2000 reference pairs (both directions, identity, neutral and hue-wrap cases) pass. Manual phone and live admin/non-admin session checks remain required before release.

