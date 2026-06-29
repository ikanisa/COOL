# Collect Runtime Brand Kit Provenance

Date: 2026-06-29

Installed runtime inputs:

- `logos/wordmark.png`: copied from `assets/brand/generated/collect_wordmark_transparent.png`.
- `app_icons/app_icon.png`: copied from `assets/brand/generated/collect_app_icon_rule.png`.
- `app_icons/web-512.png`: copied from `assets/brand/generated/collect_app_icon_rule.png`.
- `splash/splash_mark.png`: copied from `assets/brand/generated/collect_mark_transparent.png`.
- `splash/splash_background.png`: copied from `assets/brand/source_variants/collect_logo_gradient_4096.png`.
- `media/share-preview.png`: copied from `assets/brand/generated/collect_visual_group_momentum.png`.
- `icons/icon-mapping.json`: maps current `CollectIcons` usage to the active Collect product intent.

These files keep the runtime switchpoints clean while preserving Collect-owned
brand assets. Do not replace them with external screenshots. Future asset
updates should be made from Collect-owned source artwork and copied into these
stable runtime paths.
