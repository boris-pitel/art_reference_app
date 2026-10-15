# Unison scanned pastel catalogue

Created in linked Supabase project on 15 October 2026.

- public.pastel_swatches: 380 unique (brand, code) records.
- public.pastel_catalogue_sources: five original scans, SHA-256 hashes and dimensions.
- Private Storage bucket pastel-catalogue: 380 PNG crops and five original JPEGs. Authenticated read access; client writes prohibited.
- display_name contains approximate generated descriptions, not official manufacturer names.
- Central patch channel medians are interpreted as sRGB and converted to CIELAB D65. These are uncalibrated scanner measurements; no color enhancement or paper normalization applied.
- Crop coordinates use original scan pixels. Crops focus on pigment and exclude labels; retain source scans for full stroke inspection.
- YGE14 is provisional: chart prints YGR14; printed_code preserves that label and verification_status is label_needs_review. Other entries remain unreviewed pending catalogue review.
- Page 4 uses img20261015_12532890.jpg, replacing the earlier clipped scan.

Verification: database counts 380 rows, five sources, 385 stored files; zero missing swatch or source paths. Contact sheet visually checked for cell/label alignment. App matching UI is not implemented.

Reproduce extraction with tool/catalogue/extract_unison.py and generate migration with tool/catalogue/build_unison_migration.py using bundled Python/Pillow. Generated assets and contact sheet are in output/unison-catalogue. Migration has already been applied; do not regenerate or reapply an edited copy to the live database.
