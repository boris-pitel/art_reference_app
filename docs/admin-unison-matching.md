# Admin-only Unison matching experiment

Branch: codex/admin-unison-matching. Not deployed.

Open a reference in its full-screen image window. Administrators see a colour-picker icon labelled Match Unison colour (admin). It opens a separate view of the current image; it does not edit or save the image. Click/tap samples a 5x5 area and ranks the catalogue with CIEDE2000; pinch/scroll zoom and pan are available. The image is orientation-corrected and capped at 2000 pixels on its longest edge for the sampling preview. Results show three actual swatch crops, their codes, provisional names, sampled solid colours, and Delta E values.

Admin access is checked using server-managed app_metadata.is_admin in the viewer and matching screen. The admin_unison_catalogue RPC repeats the permission check on the server. The catalogue's existing authenticated read policy is unchanged; this is an admin-only matching tool, not a change to catalogue visibility. Signed Storage links are used for swatch previews.

Deployment prerequisite: apply 20261015010000_admin_unison_matching.sql before publishing the client. Migration dry-run identifies only this pending migration. No production client or new RPC has been deployed for this experiment. Provisional scan names and the YGR14 printed-code discrepancy remain flagged.

Validation: sRGB/Lab numerical reference values and five CIEDE2000 reference pairs (both directions, identity, neutral and hue-wrap cases) pass. Manual phone and live admin/non-admin session checks remain required before release.
