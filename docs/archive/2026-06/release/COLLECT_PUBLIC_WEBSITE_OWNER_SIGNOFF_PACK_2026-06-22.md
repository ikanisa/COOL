# Collect Public Website Owner Sign-Off Pack

Generated: 2026-06-22

Use this document to close the remaining non-code audit items for
`https://collect.ikanisa.com`. Codex has completed and deployed the code-owned
static-first remediation; the items below require owner approval, platform
access, or human review.

## Production Evidence Snapshot

- Production URL: `https://collect.ikanisa.com`
- Current Cloudflare Workers static-assets version:
  `2ca0058b-bd5f-4e21-9d20-5e0f93d38258`
- Static gate: `scripts/public_website_quality_gate.sh --json` passes 34/34.
- Live gate: `scripts/public_website_live_gate.sh --json` passes 25/25.
- Live evidence file:
  `output/public_website_evidence/live_audit_evidence.json`
- Latest live evidence recorded:
  - root response: 727 ms in latest completion audit run;
  - root HTML: 15,234 bytes;
  - CSS: 12,206 bytes;
  - JS: 377 bytes;
  - critical first-party bytes: 187,480;
  - Cloudflare cache: `HIT`;
  - valid JSON-LD types: `Organization`, `SoftwareApplication`.
- Original-content restoration evidence:
  - the live static root restores the original Collect positioning, CTA labels,
    USSD example, ibimina flow, diaspora/collateral story, embedded insurance,
    CRaaS, customer journey sections, and all original interior public pages.
- Crawlability evidence:
  - `https://collect.ikanisa.com/robots.txt` allows `/` and references the sitemap;
  - `https://collect.ikanisa.com/sitemap.xml` has 17 absolute trailing-slash URLs;
  - every sitemap URL returns direct HTTP 200 content;
  - every live sitemap URL has `lastmod=2026-06-22`.
- English-only SEO evidence:
  - the root exposes `<html lang="en">` and OG locale metadata `en_US`;
  - the sitemap and root metadata do not advertise `/rw/`, `/fr/`, or localized `hreflang`.
- Browser visual and Lighthouse boundary:
  - fresh screenshot and Lighthouse evidence is not currently attached after
    the full page restore because browser automation timed out in this
    environment.

## Required Owner Decisions

| ID | Decision | Approve / Defer / Reject | Evidence to attach |
| --- | --- | --- | --- |
| T-1 | Submit `https://collect.ikanisa.com/sitemap.xml` in Google Search Console and Bing Webmaster Tools, then record URL inspection/submission proof. Optionally approve IndexNow key publication and URL submission. | Pending | Screenshot/export from Search Console and Bing; IndexNow/Bing evidence if used. |
| U-2 | Approve Collect-specific proof to publish, or approve deferral. | Pending | Exact metric/testimonial/partner wording with source/date, or signed deferral. |

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
   `output/public_website_evidence/search-console/`.
6. Repeat equivalent sitemap/URL submission in Bing Webmaster Tools if required.

Platform note: Codex verified the live sitemap and robots setup, but did not
submit Search Console, Bing Webmaster, or IndexNow requests because those are
external platform actions requiring recorded owner approval or account access.

Optional IndexNow note: Codex added support for an owner-provided
`PUBLIC_INDEXNOW_KEY` and a readiness validator at
`scripts/public_website_indexnow_readiness.sh`. No key has been published and no
IndexNow URL submission has been made.

## Lighthouse Evidence

Fresh Lighthouse evidence is still open after the full original-content
restore. Browser automation timed out in this environment, so no current
Lighthouse JSON/HTML/PDF artifact is claimed for the restored production
version.

Required destination when regenerated:

- `output/public_website_evidence/lighthouse/mobile.json`
- `output/public_website_evidence/lighthouse/desktop.json`
- or accepted PageSpeed/Lighthouse exports under
  `output/public_website_evidence/pagespeed/`

## Visual QA Evidence

Fresh screenshot evidence is still open after the full original-content
restore. In-app browser and Playwright screenshot automation timed out in this
environment, so no current post-restore screenshot set is claimed.

Required destination when regenerated:

- `output/public_website_evidence/browser_visual_qa.json`
- `output/public_website_evidence/screenshots/mobile_390x844.png`
- `output/public_website_evidence/screenshots/mobile_430x932.png`
- `output/public_website_evidence/screenshots/tablet_768x1024.png`
- `output/public_website_evidence/screenshots/desktop_1440x1000.png`

## Visual Review Checklist

Reviewer must confirm:

- first viewport clearly states what Collect is and what action to take;
- no clipped mobile navigation;
- no duplicate CTA clutter in the first viewport;
- product visual appears in the first viewport on mobile and desktop;
- trust/security/policy surfaces are easy to find;
- the visual system follows the borrowed Revolut alignment target,
  Wise, M-Pesa, Tala, or MoMo.

## Sign-Off

Owner name:

Owner role:

Date:

Approved items:

Deferred items and reason:

Rejected items and required changes:

Signature or written approval reference:
