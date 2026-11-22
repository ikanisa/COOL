# Public photograph delivery

These dependencies reproduce the existing Collect photographs as full-resolution
WebP delivery files. PNG originals remain unchanged and are the browser fallback.
The pipeline does not resize, crop, replace or redraw the photographs.

Use Node 24.19.0 and install the locked dependencies:

```sh
npm ci --prefix tools/public-photography --ignore-scripts
make public-photography-check
```

After an intentional source or encoder change, regenerate the delivery files:

```sh
NODE_PATH="$PWD/tools/public-photography/node_modules" node scripts/assets/build_public_photography.mjs --write
```

The check re-encodes every original and verifies the committed artifact and
manifest. It also checks dimensions, alpha and colour-profile preservation.
Encoding changes colour-channel values because WebP uses quality 92 for opaque
photographs and 95 for photographs with alpha. Review the rendered before/after
pages and repeat performance measurements after a change. File size or a passing
packaging check does not establish visual fidelity or performance acceptance.

The website builder validates the manifest before replacing its output, uses
hashed asset filenames, supplies PNG fallbacks and versions its styles/scripts
from current source. Its native app screenshot freshness gate remains mandatory.
