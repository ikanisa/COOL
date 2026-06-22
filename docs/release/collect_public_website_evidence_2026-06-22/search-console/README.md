# Search Console And Bing Evidence

Attach evidence here for T-1 indexing closure.

Code-owned indexing readiness is recorded in `indexing-readiness.json`. That
file proves the live sitemap/robots setup is ready for submission, but it does
not satisfy the completion gate because it is not platform proof from Google
Search Console or Bing Webmaster Tools.

Accepted completion artifacts:

- `google-search-console.json`, `google-search-console.pdf`, or
  `google-search-console.png`
- `bing-webmaster.json`, `bing-webmaster.pdf`, or `bing-webmaster.png`
- or `../owner-approvals/bing-deferral.md` if Bing submission is explicitly
  deferred by the owner.

Templates are provided with `.template.json` filenames. They do not satisfy the
completion gate until replaced by real platform evidence with the accepted
filename.

Required Google evidence:

- sitemap submission for `https://collect.ikanisa.com/sitemap.xml`; or
- URL inspection/indexing request for `https://collect.ikanisa.com/`.

Do not mark T-1 closed without platform evidence or recorded owner deferral.

Do not use deprecated unauthenticated sitemap ping as closure evidence. Save
Search Console/Bing screenshots, exports, or API evidence after owner-approved
submission.

## Optional Owner-Approved IndexNow Path

Codex added deploy-safe support for an owner-provided IndexNow key, but did not
publish a key or submit URLs. To use it after recorded owner approval:

1. Choose or generate an IndexNow key that is 8-128 characters using only
   `A-Z`, `a-z`, `0-9`, or `-`.
2. Build with `PUBLIC_INDEXNOW_KEY=<approved-key>`.
3. Verify with:
   `PUBLIC_INDEXNOW_KEY=<approved-key> scripts/public_website_indexnow_readiness.sh --json`
4. Deploy the resulting static build only after approval.
5. Submit URLs through Bing Webmaster Tools or the IndexNow API only after
   explicit recorded owner approval, then save platform evidence here.

For JSON evidence, the completion gate expects content mentioning
`collect.ikanisa.com` and either sitemap, URL inspection, or indexing evidence.
