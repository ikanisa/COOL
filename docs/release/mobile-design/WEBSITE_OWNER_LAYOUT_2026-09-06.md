# Website owner layout corrections

The September 6 browser annotations are implemented in the shared public
stylesheet `web/public/revolut.css`.

At widths above 980 px, these fourteen headings are vertically centered beside
their complete neighboring content grid. Their text remains left aligned.

| Page | Heading IDs |
| --- | --- |
| Home | `daily-rhythm-heading`, `ibimina-heading`, `diaspora-heading`, `credit-boundary-heading` |
| Group Savings | `group-workflow-heading`, `group-features-heading`, `group-use-heading` |
| Diaspora | `diaspora-change-heading` |
| Insurance | `insurance-work-heading` |
| CRaaS | `craas-specialist-heading`, `craas-bank-heading`, `craas-benefits-heading` |
| Our Partners | `partner-growth-heading`, `partner-operating-heading` |

Premium finance uses two equal columns above 980 px. The Growth Engines heading
uses a narrower column, allowing all four cards to share a row from 1200 px.
The cards use two columns at intermediate widths and one column on phones.
Section headings remain above their content in the stacked layout.

The local browser review passed 144 unique checks across widths 320, 390, 834,
980, 981, 1199, 1200, 1280 and 1542 px. It measured heading centers, equal column
widths, card rows, card text overflow and document overflow. No page errors were
recorded. Desktop and phone screenshots were retained and representative
screenshots were visually inspected. The static website CI gate also passed,
including all 56 content/quality checks and seven media tests.

Evidence: `.cache/revolut-gap-closure-20260906/owner-layout-verified.json`, with
source reports and screenshots in `owner-layout-review/` and
`owner-partners-review/`. Publication readback belongs in
`docs/release/LIVE_DEPLOYMENTS.json`.

Initial heading-correction source: `6b0f7cc71eb78b085c65685edaee35f08a9aa5a0`. That release used
version `1a9f290f-a8f3-462c-a88e-30effd09a502`; all 49 served
files match the build. The public live gate passed 35/35 and the Partners
layout checks passed 27/27 on the live domain across the same nine widths.

## Follow-up card rows and partner copy

The later browser annotations narrow the heading columns beside Home's
products and audiences, Group Savings' workflow/features/use cases, and
CRaaS' specialist services. At desktop widths of at least 1200 px:

- Both four-item Home sections, the four Diaspora barriers, and the four bank
  workflow items share one row.
- The eight Group Savings features, eight use cases and eight specialist
  services use two rows of four.
- From 1440 px, all five actual Group Savings workflow steps share one row,
  as do the six Insurance barriers. The five workflow steps are preserved.

The fourteen heading centers and equal Premium finance columns remain in
place. Intermediate layouts use fewer columns before text becomes cramped;
phones use one column. The three partner operating cards use two columns
below 1280 px to keep their text within the cards.

The owner's marked removal deletes only “Stronger customer retention” and
“New diaspora banking relationships” from the commercial-value list on
Our Partners and its alias. Four bullets remain, and the cards shrink to their
content. The normalized visible-text comparison verifies exactly those two
removals across the sixteen governed routes; all other visible copy is
unchanged. Only the two affected content hashes were updated after visual
review, with the change recorded in the shared content baseline.

The follow-up browser review passes 494 checks: 351 on the six primary pages
and 143 on their three applicable aliases. It covers 320, 390, 720, 721, 834,
980, 981, 1199, 1200, 1280, 1439, 1440 and 1542 px. Checks cover exact card
counts/rows, text bounds, horizontal overflow, heading alignment, equal finance
columns and the retained commercial-value bullets. No page errors occurred.
Desktop screenshots and representative phone screenshots were visually
inspected. Evidence is retained in
`.cache/revolut-gap-closure-20260906/owner-row-review-corrected/`,
`owner-row-alias-review-verified/` and `owner-row-content-verification.json`.
The earlier failed row reports remain as correction history.

The follow-up is published from `0e5f06000838cd0d431fe5b3bc2711c0588c0cf6` on Cloudflare
version `453a68f9-31ee-41cc-b7c3-c7eaf8f2febb`, with 100% traffic verified. All
49 served files match the clean build. The live gate passes 35/35 and the
complete 494-check follow-up layout review passes on the live domain. The
previous heading-correction version is retained as the rollback target.

These corrections implement the specified website layout requests. They do not
replace the separate mobile design acceptance gate or owner comparison review.
