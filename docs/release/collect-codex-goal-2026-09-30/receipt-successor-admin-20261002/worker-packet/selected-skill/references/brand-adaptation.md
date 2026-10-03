# Own-app identity, Revolut UI/UX reference

**Authoritative clarification from the user, 5 September 2026:** use Revolut's UI/UX design to design our apps, while keeping our own app names and logos. Remove Revolut-specific names from the target experience. This supersedes earlier instructions to use source-brand masters or partnership lockups.

## What to match and what to preserve

Match the selected source's visual typologies, colours, typography, spacing, hierarchy, component anatomy, surfaces and navigation treatment. Keep each target's established app name, logo, icon, logo colours/proportions, screen names, navigation structure, workflows, task sequences, entity identity, content and backend behavior. Match common controls' presentation while adapting their operation to the existing target workflow. Visual families can be reused across different business purposes; the target need not work like Revolut.

Observe the full applicable Revolut colour system, including component, state, surface and theme treatments. The Collect route examples below demonstrate adaptation; they do not restrict the colours, typologies or screens this skill must cover.

The owner's illustrative mapping is **Collect Home blue, Groups teal, Activity purple, Profile bright violet/blue and WhatsApp login blue-indigo**, retaining all existing workflows. Collect is an example for constructing this skill, not an instruction to change that application. These are visual-family mappings across different product purposes. When implementation is requested, preserve actual logo artwork but completely replace previous hardcoded/logo-derived colours in application styling with the selected reference colours. The logo's surrounding UI is not part of the artwork exemption. See [screen typologies and colour migration](screen-typologies.md) for the mapping, source comparators and required sweep.

Source names remain permissible in internal research, citations, manifests and the `$revolut-design` skill identifier so evidence stays traceable. Original source screenshots are retained unchanged as private reference evidence. They are not runtime artwork. This rule applies to app-facing output and implementation, not falsification of source provenance.

| Source reference | Target implementation |
|---|---|
| Revolut wordmark, R symbol, app icon or partner lockup | The target's existing logo and app icon in a source-informed placement, with the target mark's own geometry and clear space |
| Revolut company/app name | The target's actual app name and legal entity where appropriate |
| RevPoints | The target's existing screen/feature name; reusing this visual family does not require a rewards/loyalty workflow |
| AIR | The target's existing assistant name, only if that capability exists |
| Revolut Pro, Revolut X, branded plan names or other source product labels | The target's actual product/plan names and capabilities; omit unsupported offerings |
| Source-specific feature terminology | The target's established terminology for its own task; record the visual mapping without requiring business-function equivalence |
| Generic labels such as Home, Search, Settings or Payments | May stay when they describe the target's real task; they are not exclusive source branding |
| Source-branded card, hero, badge or promotional artwork | The target's own approved artwork fitted to the equivalent composition; never a screenshot or graphic with residual source marks |

Use the repository's existing product config, localisation strings, logo masters and icon assets as the starting point. Do not invent a replacement app name or redraw a logo. If an essential target logo cannot be found, continue independent layout work and flag that specific missing asset rather than substituting a Revolut logo.

Inspect the full identity footprint: onboarding, headers, navigation, assistant/reward/plan labels, cards, loaders, splash/launch screens, app icons, favicons, document/page titles, manifest `name`/`short_name`, install prompts, accessible labels, empty states, notifications, receipts and metadata. Preserve actual domains and integration identifiers; a UI reference is not permission to change backend/provider configuration. Do not add a branded payment integration solely because it appears in Revolut reference material.

## Fidelity review

Record source-to-target naming and identity mappings in [comparison-template.md](comparison-template.md). Treat these as required, intentional differences, not mismatches to revert. Check layout around the real logo and actual text lengths, including wrapping and enlarged text. Do not squeeze the target logo into the source mark's proportions or use name substitutions to excuse unrelated spacing/type errors.

Before declaring the design complete, inspect rendered screens and the target's runtime assets/strings for residual source branding. Searching `Revolut`, `RevPoints`, `AIR` and source-specific plan/product names can assist, but classify each hit: source documentation, real integration identifiers and generic words are not automatically UI defects. Visually inspect logos and embedded artwork too; a text search cannot detect a mark inside an image. Do not delete legitimate product content because of an ambiguous match.

The user explicitly requires the Revolut reusable asset library, including logos, to remain available as reference. Keep all source assets and their hashes intact. The installed/portable skill retains the 13 source logo masters, marked `reference-only` and `copy_to_target: false` in the [asset manifest](../assets/manifest.json). Use them to specify equivalent behavior for the target's own marks; never substitute them for the target logo in runtime output.

## Logo behavior mapping

| Property to inspect in the source | How to apply it to the target's own logo |
|---|---|
| Role and variant | Map wordmark, symbol and app-icon roles to the corresponding existing target assets; preserve the target artwork and identity |
| Placement and hierarchy | Reproduce source-informed anchor, alignment, surrounding spacing and prominence using the actual target mark's bounds |
| Responsive sizing | Measure source containers and breakpoint behavior; apply equivalent constraints and logo-role switches without stretching or clipping the target artwork |
| Clear space and optical balance | Compare perceived scale and surrounding space, preserving the target's required clear space and natural proportions |
| Light/dark/inverse variants | Select the target's corresponding approved variant for the same background/theme context; preserve contrast and legibility |
| Rendering and assets | Use appropriate vector/raster density, transparency and crisp scaling for the target's own files, with equivalent layout stability while loading |
| Interaction and accessibility | Reproduce evidenced home-link/navigation behavior using the target's destinations and accessible name; decorative marks should not produce redundant announcements |
| Motion or transitions | Reproduce only behavior observed in a working source or motion record; a static logo file does not establish animation, timing or hover behavior |
| Launch and install contexts | Map the source app-icon/launch role to the target's own icon, splash, favicon and manifest identity; verify platform-specific clipping/safe areas |

Save source/target logo variant paths, theme, container dimensions, scaling constraints and comparison evidence with the implementation. Required identity substitution is compatible with the user's 100% UI/UX fidelity target. The app remains the target's own product.
