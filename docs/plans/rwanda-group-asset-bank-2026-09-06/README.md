# Collect Rwanda group-image bank — production and integration plan

Prepared 6 September 2026 for the owner's Browser Comment 1 on the Collect mobile review gallery.

**Deliverable status: 44 active image concepts generated and saved, with 44 current prompts and provenance records. Runtime integration: implemented locally; database deployed and verified; application distribution and full native acceptance pending.** Open the [local review gallery](http://collect.localhost:4194/) or read [generation status](production/GENERATION-STATUS.md). This document plans the image bank and its use in group creation; it does not close the skill-owned MOBILE-DESIGN-100 rule.

## The intended experience

A creator should recognise their group's purpose in the image library: neighbours saving together, a wedding committee, a choir buying equipment, relatives helping with care, traders pooling resources, supporters organising travel, or a diaspora community contributing to a shared project. The imagery should show present-day Rwanda with the same care given to Collect's interface.

Keep the group photo optional. At the existing appearance step, show a few relevant suggestions, an easy way to browse themes, and “Choose your own photo”. Choosing a picture must be deliberate, and the saved picture must remain the same after refresh and for another authorised member. A photograph never changes the group's category, visibility, ownership, eligibility or payment route.

The original bank of 40 photographs has expanded to **44 active concepts**, including four additional card covers and six refreshed wedding photographs. The six first wedding versions remain preserved. Existing selectable Rwanda photos and marketing imagery are not counted. The bank is extensible; it is not a claim to exhaust all Rwandan customs, religious traditions or ways of contributing.

## What the current Collect implementation establishes

These observations record the implementation before integration on 6 September. The subsequent changes and current verification are recorded in [INTEGRATION-STATUS.md](INTEGRATION-STATUS.md).

| Current surface or contract | Observed behaviour | Consequence for this plan |
| --- | --- | --- |
| docs/PRODUCT.md and collect_repository.dart | Collect organises contributions; it does not hold funds, issue insurance or originate loans. Rwanda and diaspora use distinct payment rails. | Show the purpose and people around a contribution; avoid loan approvals, guaranteed returns or financial-provider claims. |
| CollectionType in collect_models.dart | The five storage types are ikimina, sport, church, wedding and other. The configurable catalogue contains existing subtypes. | The eight image families and 44 image themes are a richer photo taxonomy, not replacement database group types. |
| CollectionCreateScreen | Five steps: name/description; type; MoMo receiver/SMS; colour/photo; review/create. | Add suggestions and browsing within the fourth step. No additional required setup step. |
| group_creation_platform.dart and repository creation guards | Ordinary user creation requires Android and a Rwanda profile; production also checks consent and device attestation. A browser evidence build is a separate QA surface. | Do not enable creation on iOS, web or diaspora profiles because a photo library is available. |
| collect_group_photo_picker.dart | Five photos, an own-photo action and an optional dismissible sheet; selected bundled bytes become an XFile. No theme search or type input. | Add shared catalogue-backed selection, filtering, explicit confirmation and useful preview. Preserve own-photo selection. |
| group_profile_screen.dart | The owner can choose, remove and save group media through the profile edit flow. | Reuse the picker for edits; save/cancel and owner-only permissions remain authoritative. |
| collect_runtime_tokens.dart | Editorial card aspect ratio is 358/438, with 24dp corners and content that can grow. | Produce portrait-first images and test crops with actual card content. These are current Collect adapters, not newly measured source tokens. |
| collect_group_card_media.dart | Saved image data/URLs take priority; generated defaults are selected by type/seed. Wedding and Sport currently share a general “Shared goals” image. | Map only suitable neutral defaults after integration. Existing user media must keep priority. |
| createCollection live request | The attested groupRequest includes name/type/purpose/receiver but not imageUrl. The returned collection is later copied with imageUrl locally. | Durable selected-cover persistence is a required implementation task; a local preview is insufficient. This is source evidence, not a reproduced production incident. |

Source pointers: [product contract](../../PRODUCT.md), `revolut-design` skill authority, [creation flow](../../../lib/features/collections/collection_create_screen.dart), [current picker](../../../lib/shared/widgets/collect_group_photo_picker.dart), [type catalogue](../../../lib/shared/models/collect_models.dart), [repository](../../../lib/shared/repositories/collect_repository.dart), [group-media renderer](../../../lib/shared/widgets/collect_group_card_media.dart).

The catalogue supplies labels/subtypes dynamically; the current creation screen passes the chosen type's default subtype/purpose. Do not rank a photo as though a user explicitly selected a subtype they were never shown. Use type initially and the photo theme they choose in the library; a future visible subtype selector can supply a real subtype signal.


### Dedicated cards and vibrant wedding revision

Buri munsi (41) is a dedicated public-savings card; Gikundiro (42) is a dedicated Rayon Sports supporter card with blue-and-white matchday energy. Church congregation (43) and general football fans (44) extend the ordinary library. The user supplied these named-group purposes; docs/PRODUCT.md identifies Buri Munsi and Gikundiro among platform-created or approved public groups.

Named covers are excluded from generic suggestions and defaults. The local integration assigns their fallback through the governed platform slug and public/sponsored status, never a typed name match. The assets create no group record or automatic public-group approval. Names and category labels remain UI overlays; no logos, text or payment claims are baked into the PNGs.

All six wedding concepts (09–14) now select version 2: brighter coral, teal, emerald, royal blue and ivory; natural laughter, family participation and candid celebration. The first versions and their provenance remain available. These are realistic generated scenes, not photographs of documented real weddings. See [the ten-image revision run](production/refresh-01/generation-run.json) and [current generation status](production/GENERATION-STATUS.md).

## Rwanda context and editorial decisions

Rwandan contribution groups span recurring savings, a one-off event, mutual help and shared practical projects. That breadth is why a single banking scene is inadequate.

The FinScope 2024 indexed savings discussion identifies savings groups as a major informal savings channel. The plan gives savings and livelihoods nine images, including the dedicated Buri munsi cover, while keeping informal groups distinct from licensed SACCOs. These are editorial coverage choices, not proportional population quotas. [NISR FinScope 2024](https://www.statistics.gov.rw/sites/default/files/documents/2024-09/Rwanda-Finscope-2024-Report_compressed.pdf), [RCA background on SACCOs](https://www.rca.gov.rw/cooperatives/about-saccos).

A Caritas Rwanda programme account connects savings groups with school needs, food, housing and practical mutual help. It supports including everyday household purposes alongside enterprise. The programme's credit arrangements are not features being added to Collect. [Caritas Rwanda, 8 January 2026](https://caritasrwanda.org/savings-groups-supported-by-the-ecd-project-empower-parents-to-care-for-their-children-in-hbecd/).

Wedding imagery should cover planning, family participation, attire, reception preparation and household gifts. The RCHA material supports the gusaba/gukwa context and the occasion-specific use of umushanana. Contemporary families vary; historical descriptions do not establish that everyone follows one ceremony or financing custom. [RCHA wedding publication](https://www.rwandaheritage.gov.rw/fileadmin/user_upload/RCHA/Publications/Published_Books/Ubukwe_bwa_kinyarwanda.pdf), [RCHA fashion exhibit](https://artsandculture.google.com/story/the-evolution-of-fashion-in-rwanda-rwanda-cultural-heritage-academy/0AXhd6Bj8G1ZHQ?hl=en).

Faith choices must include Christian, Muslim and neutral community-giving imagery. Religion is an explicit image-theme choice. The census material supports religious diversity; the particular offering, choir, mosque and Ramadan scenes are creative concepts, not census findings about fundraising. [NISR social-cultural characteristics](https://www.statistics.gov.rw/sites/default/files/documents/2025-02/Social-cultural%20characteristics.pdf).

There is documented precedent for communities combining money and work toward infrastructure, and for organised diaspora connections to Rwanda. This motivates project and diaspora imagery without suggesting an official levy, government campaign or bank integration. [MINALOC's Kirehe example](https://www.minaloc.gov.rw/news-detail/kirehe-residents-hailed-for-commitment-to-bring-solutions-to-the-community-through-umuganda), [MINAFFET's Rwanda Community Abroad](https://www.minaffet.gov.rw/rwanda-community-abroad).

Mutuelle is a separate RSSB service. The health-cover image represents a group organising contributions; it must never read as Collect issuing cover or confirming that a premium has been paid. [IremboGov service guidance](https://support.irembo.gov.rw/en/support/solutions/articles/47001199252-how-to-apply-and-pay-for-community-based-health-insurance-mutuelle-).

The three initial NISR/RCHA PDF references were available as search-index excerpts; full direct fetches timed out or returned 403. A further RCHA ingoma reference was added during generation; its indexed excerpt identifies the wooden imirishyo drumsticks, while detailed instrument geometry still needs local review. The access limitations and claim boundaries for all eleven sources are recorded in [SOURCE-REVIEW.md](production/SOURCE-REVIEW.md). Source photographs, real beneficiaries, named organisations and quotes are not generation inputs.

## The 44-image production list

Each row has its own standalone prompt, labels, search terms, output paths and review notes in the catalogue and prompt book. “Other” below is the current product category; a photo theme does not silently rename it.

| No. | Photograph / asset concept | Current group type(s) | Relevant contribution purpose |
| --- | --- | --- | --- |
| 01 | Neighbourhood savings circle | Ikimina | Recurring neighbourhood savings and shared goals |
| 02 | Women building a shared fund | Ikimina | Women's savings and mutual support |
| 03 | Friends saving for a goal | Ikimina | Friends and young professionals planning together |
| 04 | Market traders' shared stock | Ikimina / Other | Shared stock purchases and working-capital goals |
| 05 | Moto riders' shared goal | Ikimina / Other | Equipment, maintenance and rider group savings |
| 06 | Farmers preparing the season | Ikimina / Other | Seeds, seasonal inputs and shared farming needs |
| 07 | Saving for a family home | Ikimina / Other | Housing improvements and a family savings goal |
| 08 | Tools for a shared workshop | Ikimina / Other | Tailoring, craft and cooperative equipment |
| 09 | Wedding planning together | Wedding | Wedding committee contributions |
| 10 | Gusaba and gukwa gathering | Wedding | Family participation and ceremony preparation |
| 11 | Preparing wedding attire | Wedding | Attire and bridal-party preparation |
| 12 | A reception taking shape | Wedding | Reception, food and venue preparation |
| 13 | A gift for the new home | Wedding / Other | Shared household gift |
| 14 | Family on the wedding day | Wedding | General ceremony and wedding-day support |
| 15 | Church community giving | Church | Offerings and voluntary giving |
| 16 | A shared church project | Church | Building maintenance and a congregation project |
| 17 | Supporting the choir | Church | Rehearsal equipment, clothing or transport |
| 18 | Muslim community giving | Other | Explicitly selected Muslim giving context |
| 19 | Preparing a Ramadan meal | Other | Community iftar preparation |
| 20 | Community giving together | Church / Other | Neutral outreach and practical parcels |
| 21 | Support in bereavement | Other | Practical funeral and household support |
| 22 | Helping someone reach care | Other | Family care and healthcare travel support |
| 23 | Contributing toward health cover | Other | Household contributions toward Mutuelle |
| 24 | Neighbours helping a household recover | Other | Recovery and practical emergency support |
| 25 | Family support across generations | Ikimina / Other | Family and friends' everyday mutual support |
| 26 | Welcoming a new family member | Other | A practical baby gift or family gathering |
| 27 | Preparing for school | Other / Ikimina | School supplies and school-term needs |
| 28 | Supporting school meals | Other | A school-community meal contribution |
| 29 | Supporting the next stage of study | Other / Ikimina | Higher study and education support |
| 30 | Learning practical skills | Other / Ikimina | Training fees, tools and practical skills |
| 31 | Preparing a community work project | Other / Ikimina | Tools or materials for a community project |
| 32 | A shared water improvement | Other | Water-point maintenance or improvement |
| 33 | Improving a shared hall | Other | Neighbourhood meeting-space improvements |
| 34 | Growing a greener neighbourhood | Other / Ikimina | Seedlings and environmental activity |
| 35 | Supporting the team together | Sport | Supporter group contributions |
| 36 | Kit for a local team | Sport | Equipment and training supplies |
| 37 | Travelling together for the match | Sport | Away-match transport and shared travel costs |
| 38 | Supporting music and dance | Other | Cultural troupe instruments, costumes or travel |
| 39 | Family contributing from abroad | Ikimina / Wedding / Other | Diaspora participation in a family goal |
| 40 | A community connected to home | Other / Ikimina | Diaspora association and a shared project |
| 41 | Buri munsi | Ikimina · named group only | Public savings group card |
| 42 | Gikundiro | Sport · named group only | Rayon Sports supporters contributing to the club |
| 43 | Church congregation together | Church | Congregation giving and church projects |
| 44 | Football fans together | Sport | General supporter contributions and matchday community |

Coverage totals: savings/livelihoods 9; weddings 6; faith/giving 7; family/solidarity 6; education/skills 4; community projects 4; sport/culture 6; diaspora 2 = **44**.

The two diaspora scenes can be chosen by an eligible Rwanda organiser, or later by an authorised editor. They do not create a diaspora self-service group-creation journey. Institutions and sponsored public groups use their existing administrative permissions.

## Art direction and crop contract

Create original photorealistic editorial photography with natural light, believable materials and ordinary settings that feel cared for. Premium means thoughtful composition and visual quality, not only expensive homes, suits or large sums of money. Show informal and formal work, small towns, cultivated rural settings, Kigali and overseas connections. These settings are creative directions, not inferred attributes of actual users.

Use varied fictional adults and balanced participation. Women organise, trade, ride, learn and lead; men participate in care, household planning and collaborative work. Include older adults, young adults and credible disability representation where specified. Object-led alternatives let sensitive and practical purposes read clearly without a depicted beneficiary. Do not make children recognisable in this first bank.

Reserve umushanana and related formal dress for the occasion-specific wedding/culture briefs. Most everyday scenes use contemporary clothing. Avoid generic “African village” shorthand, safari landscapes, costume mixtures, extreme poverty imagery, cash piles, luxury-only success cues and foreign corporate-office stereotypes. Keep photographs independent of the UI palette: do not tint every scene teal or copy another product's art.

| Deliverable | Proposed specification | Review requirement |
| --- | --- | --- |
| Master | One portrait 3:4 image, ideally 1536 × 2048; retain actual original output and record actual dimensions | No upscaling to conceal a small output; regenerate for unusable composition |
| Runtime cover | 768 × 1024 WebP, target ceiling 175 KiB | Inspect compression on skin, fabric, grass, hair and lettering-like artefacts |
| Picker thumbnail | 192 × 256 WebP, target ceiling 15 KiB | Recognisable central subject and no critical crop loss |
| Group card | Actual 358:438 layout, growing with content | Category icon at top, title/totals/supporter content at bottom, real overlays |
| Other crops | Square/circular avatar and current 3:2 picker preview | Faces, meaningful objects and scene purpose remain understandable |

The common prompt reserves the upper 15% and lower 25% for interface overlays, with a compact central story. Every focal point starts at x=0.50, y=0.47 **provisionally**; measure and amend it after seeing the generated image. Do not label a crop as approved just because the prompt asked for it. If one composition cannot serve all crops, regenerate it or add a reviewed derivative within that same concept. Forty concepts may produce more than forty technical files.

The runtime cover/thumbnail ceiling totals 8,560,640 bytes, about 8.16 MiB for the bank. This is a budget, not a measured result. Bundle only reviewed covers/thumbnails and a small runtime catalogue; omit masters, prompts, research and production records. Decode thumbnails for scrolling and covers only for visible/previewed items. Do not decode all 44 full-resolution masters in memory.

No text, bank UI, flags, logos, branded uniforms, phone numbers, membership lists, real beneficiaries or claims of payment belong inside the generated pictures. Collect renders its own text and contrast layers. Sensitive funeral, healthcare and faith details get specific local review; these are ordinary editorial checks, not a new permission process for preparing this plan.

## How suggestions and filtering should work

Inputs come from deliberate choices: current group type, a subtype only if actually selected, an optional image theme and library search. The library uses a local index over English, Kinyarwanda and French draft labels and search terms. Do not send group names, descriptions, contacts or payment history to an image-generation or recommendation service.

The catalogue's eight families are browsing shortcuts. Its 44 theme keys identify precise intents such as traditional_wedding, moto_goal, school_supplies or muslim_giving. They do not change CollectionType or the stored purpose of a group.

1. Open with six suggested thumbnails for the current type, no photo preselected, and the own-photo action visible. Fewer than six is acceptable when that is the relevant set.
2. Offer “Browse themes” and “All photos”. Changing an image theme does not change the group type. “All photos” may cross the type mapping but retains the explicit-context rule.
3. Apply explicit context eligibility first. Church type deliberately opens Christian suggestions. Muslim giving, Ramadan, health, bereavement and new-baby artwork open when the creator chooses that named theme/context. The broad Family or Faith family alone does not choose a specific sensitive context.
4. Match the selected theme first, then type, a real subtype and search tokens. Use deterministic editorial priority and stable ID to break ties. Keep image order stable when returning from preview.
5. Normalise case, accents and apostrophes. Match all entered search tokens; do not fall back to unrelated results for an unknown query. Synonyms include ikimina/ibimina/tontine, ubukwe/gutwerera, umupira/football and mutuelle/mituweli.
6. A no-match state says “No matching photos” with “Clear filters”, theme browsing and “Choose your own photo”. A search such as “zakat” without a context choice can offer the named Muslim giving theme, before opening its artwork.
7. Tap a thumbnail to preview the full card and avatar crop. “Use photo” commits only to the form draft. Dismissal, Back or Cancel retains the previous draft choice. Saving is a separate existing group action.
8. Changing type reranks suggestions but never silently discards an already selected photo. The creator can replace it, keep it or remove it.

The preparation script implements the proposed deterministic metadata filters so their logic is reviewable now. It is **not imported into the Flutter runtime**. The draft rules give theme +100, suggested type +50, actual subtype +20, matching query tokens +5 each, and editorial priority 0–9. A selected precise theme is a filter; all-library mode removes the type restriction/boost. These are product decisions, not machine-learning inferences.

Ordinary library suggestions are different from automatic fallback art. Automatic fallbacks can use only context-neutral general-default entries and must not create a stored image record. Faith-specific, bereavement, health and new-baby assets never become a generic default. Uploaded/saved user media always takes priority.

## Create, edit and member journeys

### Create group

Keep steps 1–3 intact, including actual name/type/receiver inputs and permission messages. In step 4, retain the existing colour controls, then show the photo row with a current selection or a neutral optional state. The library sheet contains own-photo, Suggested, theme browsing, search, the thumbnail grid and preview. Choosing an image returns to step 4. Step 5 shows the chosen cover alongside the actual group details before Create group.

Use a focused neutral sheet consistent with the `revolut-design` skill; the Groups overview remains teal. Reuse the existing typography, spacing, sheet and control tokens. Two thumbnail columns may work at ordinary phone widths; collapse to one at narrow widths or enlarged text. Keep title labels wrapping and targets at least 48dp. No fixed-height grid cell may clip an accessible label.

The source comparator is the owner-selected Cards.png card composition and existing focused-task/selection-sheet patterns from the Revolut skill. The filtered library itself is a **Collect-specific adaptation without a verified direct Revolut comparator**. Do not invent exact source geometry or call the new picker 100% matched from this document.

### Edit group

An authorised owner opens the current group profile. The existing selected image is highlighted even if it does not match the current filter. Own photo, bank photo and no explicit photo are separate choices. The preview shows what will change. Cancel makes no group write; Save persists the selected media kind and the chosen asset/version or uploaded-media reference. Removal clears the explicit selection only on Save.

Keep existing owner/member distinctions. An ordinary member can view the result but cannot edit the group image. Administrative editing of public/sponsored groups remains a separate permissioned path.

### After save

The same selected picture and crop must appear in Home's My groups, Groups, group detail/profile and any existing authorised group preview that uses group media. Existing private/public discovery restrictions remain intact. Do not introduce a new invitation/share/public surface merely to display the photo.

A failed catalogue or image decode yields a stable neutral placeholder and retry/own-photo options. The create form remains usable without a photo. A failed group save preserves the image draft and all other entered values. Do not confirm “saved” before authoritative readback; do not duplicate group creation if only photo persistence needs recovery.

## Persistence and file integration design

Recommended durable representation: a nullable cover_asset_id plus cover_asset_version for a selected bank image, alongside the existing imageUrl for user media. The database stores the chosen stable reference, not a device filesystem path and not a re-encoded copy of the same bundled image per group.

Represent the draft picker result as a typed choice: existing media / own-photo XFile / bank asset id and version / none. For a committed choice, custom image data and a bank asset reference are mutually exclusive. Switching media kinds clears the superseded reference atomically only when saving. Existing records keep working without a migration that rewrites their images.

The current creation path needs the new cover fields carried through its attested request, server validation and transaction. Extend the authorised RPC/attestation payload coherently; do not bypass the existing signature, consent, profile or owner checks. The server should allow only published asset IDs/versions. The owner profile-update RPC needs the same fields and permissions, and the model, live reader and offline cache need matching read/write fields.

Prefer atomic group-and-cover creation. If an implementation uses a two-stage create then owner update, it must explicitly preserve the new group ID, show a recoverable “Group created; photo not saved” state and retry only the media update. Never rerun create for a media-only failure. Verify actual persisted values and a second authorised session.

| Files / module | Planned change |
| --- | --- |
| assets/group_covers/rwanda/catalog.v1.json | Production authority for the 44 concepts, draft labels, prompts and planned paths |
| assets/group_covers/rwanda/source/ | Original generated PNGs, saved per returned tool result; no dummy images |
| assets/group_covers/rwanda/covers/ and thumbs/ | Reviewed runtime derivatives with immutable versioned names |
| assets/group_covers/rwanda/production/ | Source/derivative hashes, actual dimensions, generation provenance and review outcomes |
| Proposed runtime catalogue / shared cover model | Small image-only index; exclude prompts, source notes and unfinished assets |
| pubspec.yaml | Explicitly register reviewed covers/thumbnails and the runtime index, not the whole planning directory |
| collect_group_photo_picker.dart | Shared type/theme/search/preview picker; explicit typed selection and labelled states |
| collection_create_screen.dart and collection_create_widgets.dart | Pass real type/theme intent, preserve photo draft and show selected image at review |
| group_profile_screen.dart / group_profile_media.dart | Reuse selection, save/cancel/removal and owner permissions |
| collect_models.dart, repository, live reader, offline cache | Stable selected asset id/version, existing custom-media compatibility and durable reload |
| Supabase migrations / attestation / group RPCs | Validate published asset IDs and persist media choice through authorised operations |
| collect_group_card_media.dart | Resolve custom media, chosen bank asset and appropriate neutral fallback in that order |
| Existing gallery and mobile route/state evidence | Add actual new picker states and saved-image proof after implementation |

This new bank is separate from assets/marketing/rwanda/ and its existing SOURCE.json. Preserve those current files and provenance. A curated subset may later be reused by marketing with the appropriate crops and context, but this plan does not replace the public website hero or existing marketing imagery.

## Production sequence and completion criteria

| Phase | Concrete work | Completion evidence |
| --- | --- | --- |
| 1. Prepare | Finalise the 44 briefs, metadata, draft localisations and this integration plan | Catalogue validation and exported 44-job pack; completed in this task |
| 2. Generate eight anchors | 01, 10, 15, 18, 21, 27, 35, 39 | Eight original outputs saved; contact sheet and all intended crops actually inspected |
| 3. Refine and generate remaining 32 | Batches 2–5 in the catalogue, eight concepts each | Forty distinct saved masters with hashes; revise failed concepts instead of counting duplicate crops as new concepts |
| 3b. Owner-requested expansion | Add Buri munsi, Gikundiro, church and football cards; refresh all six weddings | Ten new originals saved; 44 active concepts, six previous wedding versions preserved |
| 4. Prepare runtime assets | Review local plausibility/dress/objects; compress derivatives; refine focal points and labels | Forty-four reviewed covers/thumbs, source/derivative provenance, measured sizes and no missing files |
| 5. Integrate picker and persistence | Shared picker, draft state, schema/RPC/model/cache/media updates | Selection survives authoritative reload and appears for another authorised viewer |
| 6. Validate affected journeys | Meaningful filter, permission, save/recovery and responsive/accessibility evidence | Current implementation and native evidence; applicable mobile-design gate remains authoritative |

The initial generation phase produced 40 selected originals, including the eight calibration anchors. There were 42 built-in calls: the first bereavement and cultural-troupe candidates were replaced after initial inspection. The selected originals and exact prompt hashes are recorded in [generation-run.json](production/generation-run.json). Every source copy matches the returned original byte for byte. Cultural review and the full native crop matrix remain separate from generation. The batch structure does not request approval after every eight calls.

All label translations in the manifest are drafts. Before release, a Kinyarwanda reviewer should check idiom, spelling, cultural labels and the sensitive themes. The French and English labels also need ordinary copy review. Store reviewed locale strings separately from search aliases where appropriate.

### Focused acceptance cases for the later implementation

| Case | Required outcome |
| --- | --- |
| Ikimina, Wedding, Church, Sport, Other | Each opens relevant suggestions using actual type; no hidden subtype inference |
| Muslim giving / Ramadan | Available by deliberate theme selection under current Other; never silently reclassified as Church |
| Neutral all-library opening | No unsolicited bereavement, healthcare or faith-specific artwork |
| Kinyarwanda/French search | Expected matches despite case/accents; unknown search yields an honest empty state |
| Selected bank cover, own image and no explicit image | Each persists correctly and has distinct save/removal behaviour |
| Change type, Back, dismiss, Cancel, retry | Preserve prior photo and non-photo form drafts; never duplicate a group |
| Create then kill/relaunch; reload; second authorised member | Same persisted image id/version and crop, subject to ordinary group access |
| Owner, member, guest, public/platform context | Same existing edit, read and discovery permissions; private groups remain private |
| Android/Rwanda versus iOS/web/diaspora creator | No creation capability added by image availability |
| Offline, missing file, corrupt image, permission denial | Stable geometry, readable fallback, retry or own-photo option, no crash |
| 320dp, ordinary phone, tablet, landscape, keyboard, 200% text | Reachable controls, growing labels, safe areas, no overlap or clipped selection |
| TalkBack/VoiceOver and keyboard | Clear photo name and selected state, meaningful preview labels, correct focus return, close/confirm reachable |
| Light, dark, high contrast and reduced motion | Existing semantic tokens, non-colour selected indicator, suitable text contrast and no required animation |
| Long group name, multiple currency totals, supporter count | Subjects and text stay legible on the actual tall card; photography never obscures financial meaning |
| Build and affected gate evidence | Current source/artifact binding and actual visual review; a passing script or gallery alone is insufficient |

Keep the existing MOBILE-DESIGN-100 criteria and all required cases. Do not lower scores, remove required evidence or regenerate baselines merely to get a pass. This task prepares documentation/tooling and changes no visible mobile surface, so it makes no new mobile acceptance or APK production-GO claim.

## Use the saved generation pack

- [Machine-readable catalogue](../../../assets/group_covers/rwanda/catalog.v1.json)
- [All 44 standalone prompts](production/PROMPTBOOK.md)
- [44 built-in generation jobs](production/imagegen-jobs.jsonl)
- [Spreadsheet-friendly asset index](production/asset-index.csv)
- [Source review and access limits](production/SOURCE-REVIEW.md)
- [Preparation and save helper](../../../scripts/assets/rwanda_group_asset_bank.py)

From /Volumes/PRO-G40/COOL:

~~~sh
python3 scripts/assets/rwanda_group_asset_bank.py validate
python3 scripts/assets/rwanda_group_asset_bank.py export
python3 scripts/assets/rwanda_group_asset_bank.py suggest --type wedding --query gusaba
python3 scripts/assets/rwanda_group_asset_bank.py suggest --type other --theme muslim_giving
python3 scripts/assets/rwanda_group_asset_bank.py suggest --type sport --subtype away_travel
python3 scripts/assets/rwanda_group_asset_bank.py suggest --named-group buri_munsi
python3 scripts/assets/rwanda_group_asset_bank.py suggest --named-group gikundiro
~~~

The export command produces 44 individual TXT prompts, a consolidated prompt book, the CSV index and 44 JSONL jobs. It expands common art direction into every prompt, so a job can run on its own without previous conversation context. Re-export only regenerates the planning outputs; it does not make a network call or generate image pixels.

For image production, read each job and pass only its arguments object to the built-in image_gen tool (the orchestration name is tools.image_gen__imagegen). Do not pass the planning job's id, batch or output path as tool arguments. New images require no reference-image field. After generation, inspect the output and use its actual returned local path. Save a PNG using:

~~~sh
python3 scripts/assets/rwanda_group_asset_bank.py save-source rw-01-neighbourhood-ikimina /actual/path/returned-by-imagegen.png
~~~

The actual input path must come from the generation result; the example is not an existing file. The helper copies bytes to the named asset path, records dimensions and SHA-256, marks the output generated_unreviewed and refuses replacement. It does not prove visual quality, generator provenance or editorial approval. If the tool returns a different format, keep its actual format and update the versioned production record rather than renaming bytes to PNG. Derivatives and a published runtime index follow actual review.

**Current handoff:** all 44 active image concepts, prompts, scripts and provenance records are saved, and the local filtering/crop gallery is available. Optimised derivatives, the shared picker and atomic persistence are now implemented locally. The database migration is deployed and verified. Remaining production work is local cultural/language review, final native framing/acceptance and application distribution through the existing release gate. See [integration status](INTEGRATION-STATUS.md). See [GENERATION-STATUS.md](production/GENERATION-STATUS.md) for current evidence and limitations; VERIFICATION.json records the earlier prompt-preparation phase.
