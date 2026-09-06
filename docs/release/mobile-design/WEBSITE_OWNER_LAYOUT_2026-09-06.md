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

Published source: `6b0f7cc71eb78b085c65685edaee35f08a9aa5a0`. Cloudflare confirms
100% traffic on version `1a9f290f-a8f3-462c-a88e-30effd09a502`; all 49 served
files match the build. The public live gate passed 35/35 and the Partners
layout checks passed 27/27 on the live domain across the same nine widths.

These corrections close the specified website layout requests. They do not
replace the separate mobile design acceptance gate or owner comparison review.
