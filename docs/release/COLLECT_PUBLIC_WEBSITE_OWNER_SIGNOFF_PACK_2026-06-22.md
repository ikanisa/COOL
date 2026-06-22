# Collect Public Website Owner Sign-Off Pack

Generated: 2026-06-22

Use this document to close the remaining non-code audit items for
`https://collect.ikanisa.com`. Codex has completed and deployed the code-owned
static-first remediation; the items below require owner approval, platform
access, or human review.

## Production Evidence Snapshot

- Production URL: `https://collect.ikanisa.com`
- Current Cloudflare Workers static-assets version:
  `40b3f4a4-6a63-476e-b878-8c45ef13a9da`
- Static gate: `scripts/public_website_quality_gate.sh --json` passes 34/34.
- Live gate: `scripts/public_website_live_gate.sh --json` passes 28/28.
- Live evidence file:
  `docs/release/collect_public_website_evidence_2026-06-22/live_audit_evidence.json`
- Latest live evidence recorded:
  - root response: 275 ms in latest completion audit run;
  - root HTML: 8,871 bytes;
  - CSS: 8,534 bytes;
  - JS: 377 bytes;
  - critical first-party bytes: 177,445;
  - Cloudflare cache: `HIT`;
  - valid JSON-LD types: `Organization`, `SoftwareApplication`.
- Crawlability evidence:
  - `https://collect.ikanisa.com/robots.txt` allows `/` and references the sitemap;
  - `https://collect.ikanisa.com/sitemap.xml` has 18 absolute trailing-slash URLs;
  - every sitemap URL returns direct HTTP 200 content;
  - every live sitemap URL has `lastmod=2026-06-22`.
- Localized SEO evidence:
  - `/`, `/rw/`, and `/fr/` expose reciprocal `hreflang` alternates;
  - OG locale metadata is `en_US`, `rw_RW`, and `fr_FR` respectively.
- Lighthouse evidence:
  - mobile: Performance 98, Accessibility 96, Best Practices 100, SEO 100;
  - desktop: Performance 100, Accessibility 96, Best Practices 100, SEO 100.
- Visual QA evidence:
  - `docs/release/collect_public_website_evidence_2026-06-22/browser_visual_qa.json`;
  - screenshots at 390x844, 430x932, 768x1024, and 1440x1000.

## Required Owner Decisions

| ID | Decision | Approve / Defer / Reject | Evidence to attach |
| --- | --- | --- | --- |
| T-1 | Submit `https://collect.ikanisa.com/sitemap.xml` in Google Search Console and Bing Webmaster Tools, then record URL inspection/submission proof. Optionally approve IndexNow key publication and URL submission. | Pending | Screenshot/export from Search Console and Bing; IndexNow/Bing evidence if used. |
| U-2 | Approve Collect-specific proof to publish, or approve deferral. | Pending | Exact metric/testimonial/partner wording with source/date, or signed deferral. |
| U-4 | Approve Kinyarwanda and French public copy, or provide corrections. | Pending | Reviewer name, date, and final copy notes. |
| Play Console | Approve any Play Console privacy URL/listing update or resubmission. | Pending | Play Console change evidence, if performed. |

## Claim Approval Rules

Do not publish or add any of the following without explicit approval:

- bank, insurer, regulator, BNR, MoMo, or partner endorsement;
- exact customer counts, transaction counts, savings totals, default rates, or
  reliability claims;
- testimonials, logos, or named pilots;
- credit approval, insurance coverage, deposit-taking, or regulated-status
  claims.

Approved claim text must include:

- source owner;
- source date;
- exact public wording;
- approval owner;
- approval date;
- expiry/review date if the claim can become stale.

## Search Submission Steps

1. Open Google Search Console for `collect.ikanisa.com`.
2. Submit sitemap: `https://collect.ikanisa.com/sitemap.xml`.
3. Use URL Inspection for:
   - `https://collect.ikanisa.com/`
   - `https://collect.ikanisa.com/privacy/`
   - `https://collect.ikanisa.com/trust/`
4. Request indexing where available.
5. Save screenshots or exported evidence in:
   `docs/release/collect_public_website_evidence_2026-06-22/search-console/`.
6. Repeat equivalent sitemap/URL submission in Bing Webmaster Tools if required.

Platform note: Codex verified the live sitemap and robots setup, but did not
submit Search Console, Bing Webmaster, or IndexNow requests because those are
external platform actions requiring recorded owner approval or account access.

Optional IndexNow note: Codex added support for an owner-provided
`PUBLIC_INDEXNOW_KEY` and a readiness validator at
`scripts/public_website_indexnow_readiness.sh`. No key has been published and no
IndexNow URL submission has been made.

## Lighthouse Evidence

Codex generated local Lighthouse JSON evidence on 2026-06-22:

- `docs/release/collect_public_website_evidence_2026-06-22/lighthouse/mobile.json`
- `docs/release/collect_public_website_evidence_2026-06-22/lighthouse/desktop.json`

Both reports pass the 90+ target for Performance, Accessibility, Best
Practices, and SEO. Earlier PageSpeed Insights API attempts returned
`429 RESOURCE_EXHAUSTED`; those raw responses are saved in
`docs/release/collect_public_website_evidence_2026-06-22/pagespeed/`.

## Translation Review Checklist

Reviewer must confirm:

- `/rw/` Kinyarwanda copy is accurate, respectful, and locally natural;
- `/fr/` French copy is accurate, respectful, and locally natural;
- financial and credit-readiness language does not imply guaranteed credit,
  insurance, or regulated status;
- WhatsApp/contact wording is appropriate for customers.

## Visual QA Evidence

Codex generated the final viewport evidence on 2026-06-22:

- `docs/release/collect_public_website_evidence_2026-06-22/browser_visual_qa.json`
- `docs/release/collect_public_website_evidence_2026-06-22/screenshots/mobile_390x844.png`
- `docs/release/collect_public_website_evidence_2026-06-22/screenshots/mobile_430x932.png`
- `docs/release/collect_public_website_evidence_2026-06-22/screenshots/tablet_768x1024.png`
- `docs/release/collect_public_website_evidence_2026-06-22/screenshots/desktop_1440x1000.png`

## Visual Review Checklist

Reviewer must confirm:

- first viewport clearly states what Collect is and what action to take;
- no clipped mobile navigation;
- no duplicate CTA clutter in the first viewport;
- product visual appears in the first viewport on mobile and desktop;
- trust/security/policy surfaces are easy to find;
- the visual system feels Collect-owned and not copied from Stripe, Revolut,
  Wise, M-Pesa, Tala, or MoMo.

## Sign-Off

Owner name:

Owner role:

Date:

Approved items:

Deferred items and reason:

Rejected items and required changes:

Signature or written approval reference:
