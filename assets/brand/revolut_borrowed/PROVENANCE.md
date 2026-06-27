# Revolut-Like Borrowed Brand Kit Provenance

Date: 2026-06-27

Installed runtime inputs:

- `logos/wordmark.png`: copied from the existing Collect transparent wordmark fallback.
- `app_icons/app_icon.png`: copied from the existing Collect static app icon.
- `app_icons/web-512.png`: copied and resized from the existing Collect static app icon.
- `splash/splash_mark.png`: copied from the existing Collect transparent mark fallback.
- `splash/splash_background.png`: copied from `/Users/jeanbosco/Downloads/Revolut10/IMG_2739.PNG` as the account-blue reference family background.
- `media/share-preview.png`: copied from `/Users/jeanbosco/Downloads/Revolut10/IMG_2752.PNG` as the content-dark media-card reference.
- `icons/icon-mapping.json`: maps current `CollectIcons` usage to the closest Revolut-like reference intent.

These files close the empty runtime-input paths and make the app use the reserved borrowed asset switchpoints. If a later exact approved asset kit is supplied, replace these files in place without changing the runtime paths.
