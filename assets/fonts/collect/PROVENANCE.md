# Collect Runtime Font Provenance

Date: 2026-06-30

The repo-local `Collect Runtime` UI family is backed by Inter static OTF files
from the official `rsms/inter` 4.0 release. The repo-local `Collect Display`
family is backed by Inter Display static OTF files from the same release.

Installed runtime UI files:

- `CollectRuntime-Regular.otf` from `Inter-Regular.otf`
- `CollectRuntime-Medium.otf` from `Inter-Medium.otf`
- `CollectRuntime-SemiBold.otf` from `Inter-SemiBold.otf`
- `CollectRuntime-Bold.otf` from `Inter-Bold.otf`
- `CollectRuntime-ExtraBold.otf` from `Inter-ExtraBold.otf`

Installed display files:

- `CollectDisplay-Regular.otf` from `InterDisplay-Regular.otf`
- `CollectDisplay-Medium.otf` from `InterDisplay-Medium.otf`
- `CollectDisplay-SemiBold.otf` from `InterDisplay-SemiBold.otf`
- `CollectDisplay-Bold.otf` from `InterDisplay-Bold.otf`
- `CollectDisplay-ExtraBold.otf` from `InterDisplay-ExtraBold.otf`

Rationale:

- The supplied Revolut10 screenshots show a cleaner, more neutral UI/body
  typography rhythm than the previous Poligon-backed runtime files.
- Inter is the app UI/body target when exact proprietary or paid heading fonts
  are not available.
- Inter Display is used as the local display fallback for large headings and
  money hierarchy until licensed Aeonik/Aeonik Pro files are supplied.

License:

- Inter is distributed under the SIL Open Font License 1.1.
- Source archive used for this install:
  `https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip`.

Keep the `Collect Runtime` and `Collect Display` family names stable unless
typography is renamed in a dedicated app-wide refactor.
