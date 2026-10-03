# Collect Rwanda image bank — generated originals

6 September 2026. **44 active image concepts are generated and saved.** This includes dedicated Buri munsi and Gikundiro cards, additional church and football images, and six vibrant wedding revisions. The group-creation and owner-edit picker is now implemented locally. See [integration status](../INTEGRATION-STATUS.md); database deployment is verified; application distribution and full native acceptance remain pending.

Open the [local review gallery](http://collect.localhost:4194/). Restart it with `python3 scripts/assets/serve_rwanda_group_bank.py --port 4194` when needed. It provides named-group buttons, group type, image family, explicit context and EN/RW/FR keyword search, plus tall card, square, circle and landscape previews. This is a read-only asset review page.

## Current files and provenance

- 44 selected PNGs, each **1086 × 1448 pixels**, with matching current prompts and provenance records.
- Six preserved first wedding versions: **50 source PNGs** and 50 corresponding records in the project.
- **52 built-in generation calls** in total: initial 42 calls, including two rejected candidates, followed by ten successful additions/revisions. The rejected originals remain in the tool output folder. No source pixels were edited, deleted or overwritten.
- Active originals: **98,796,942 bytes**. Including preserved wedding versions: **113,087,135 bytes**. The 88 runtime WebP derivatives total 4,651,698 measured bytes; hashes and dimensions are recorded in the runtime manifest.
- All 44 active project copies match the returned originals byte for byte. PNG checksums and compressed streams are valid, prompt digests match, and all 44 images are served intact by the local gallery.

Current checks: [refresh-01/VERIFICATION.json](refresh-01/VERIFICATION.json). The [revision run](refresh-01/generation-run.json) records the ten new sources and exact prompts. [generation-run.json](generation-run.json) and [GENERATION-VERIFICATION.json](GENERATION-VERIFICATION.json) are historical evidence for the first 40-image phase. `../VERIFICATION.json` records the earlier prompt-preparation phase.

Coverage: savings and livelihoods 9; weddings 6; faith and giving 7; family and solidarity 6; education and skills 4; community projects 4; sport and culture 6; diaspora 2. These themes map to Collect's five existing group types.

## Dedicated cards and wedding revision

**Buri munsi (41)** depicts a savings circle and carries the proposed UI label “Public savings group”. **Gikundiro (42)** depicts blue-and-white Rayon Sports supporters, with names and purpose overlaid by the card UI. Neither contains baked-in club marks, text or payment information. Their catalogue scope is named-group-only; generic filtering excludes them. The local runtime fallback uses the governed platform slug and public/sponsored status, never an inferred typed-name match.

**Church congregation (43)** and **football fans (44)** extend the general library. Verified filters return five Church options and four generic Sport options; Gikundiro remains separately selectable for its named group.

**Weddings 09–14 now select version 2.** The new scenes use lively coral, emerald, turquoise, royal blue and ivory, with natural family interaction, candid laughter and celebratory Rwandan settings. They are original generated illustrations, not evidence of real weddings. Version 1 files and prompts remain preserved in their receipts and the previous catalogue snapshot.

## Initial visual review

All 44 active original images were inspected in tool output for broad scene fit and obvious defects. The local browser review checked Buri munsi and Gikundiro as tall cards, Gikundiro as a circular crop, all six revised weddings as tall cards and landscape crops, and the expanded Church and Sport sets. These are initial agent checks, not local cultural approval or native design acceptance.

Wedding v2 focal positions 09 and 11 were adjusted in metadata to retain complete heads in the sampled wide crops. **Concept 13 v2 now retains both faces and gift context in its sampled landscape preview**; the v1 wide-framing issue is historical. Final framing in all actual native slots remains pending.

The initial bereavement candidate was replaced after it added people to a still-life brief. The first cultural-troupe candidate was replaced to improve the instrument and remove a brand-like shoe mark. RCHA source S11 supports ingoma/imirishyo terminology, while cultural accuracy still needs local review; source access limits are recorded in [SOURCE-REVIEW.md](SOURCE-REVIEW.md).

## Integration follow-up

The shared picker, versioned reference renderer, generated runtime catalogue and atomic creation-media migration are implemented locally. The own-photo option, explicit confirmation, cancel, image removal and existing owner/geographic/device rules are retained. No live group record or payment behaviour was changed. See [current integration evidence and deployment order](../INTEGRATION-STATUS.md).

Cultural/language review, final native acceptance and application distribution remain pending. Historical generation evidence above does not certify runtime release.
