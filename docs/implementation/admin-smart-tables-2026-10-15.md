# Collect Admin tables — 15 October 2026

The owner explicitly selected **tables on every page, including Overview**. This supersedes the earlier Overview-card exception. Authentication/input forms and status/error instructions remain controls; they do not present record collections as cards.

The canonical Cloudflare Admin now uses dedicated-column tables for Groups, Users, Members, Payees, Transactions, Ledgers, Reconciliations, SMS receipts, gateway devices/capture grants, member receipts, email events, request history, team access policy/accounts and related/detail/confirmation records. Overview measurements and the current operator are tables too. Collect identity, amounts, full authorized contacts, zero-preserving codes, row links and permissions remain intact.

## Smart controls

Core lists query and sort the complete authorized server dataset. Sortable headers and the sort menu use per-area allowlisted SQL expressions with stable tie-breakers, bounded pages and nulls last. Search, sort, status and page are retained in list URLs and validated when returning from details. Explicit sort governs ordering; normal time ordering retains existing person relevance ranking. Data tables expose a visible horizontal scrollbar and keyboard horizontal navigation.

Core search handles multiple terms, quoted phrases, case and supported accent/phone normalization, exact identifiers and tested concepts: `active private groups`, `staff users`, `direct members`, `users without groups`, `unallocated transactions`, `partial transactions`, `balanced posted journals`, and typed fields such as `name:"Alpha savings"`, `momo:0787654321`, `reference:RW-REF`, `type:staff`, `group:Beta`, `role:member`. Unsupported structured fields/sorts fail explicitly. Contacts and provider facts remain data, never instructions or identity inference. The search is deterministic concept interpretation/ranking; no embedding or generative model service was added or claimed.

Other multi-row tables provide quoted/multiple-term loaded-row search, column-specific contains filters and header sorting. Their visible label says that these tools apply to the loaded page; existing server status filters and pagination remain available. They do not claim to sort or search unseen pages. Full global field search/order for every integration endpoint remains a possible follow-up; it is not established by local filtering.

## Verification and release boundary

291 Admin/session/runtime Flutter cases passed on the integrated table/journal source, including original-key recovery, permission/session changes and complete journal confirmation. The new real D1 smart-query regression verifies global ordering across separate pages, exact large amounts, concept/field filters, invalid SQL-sort rejection and zero operating writes. Earlier failed assertions and source preimages are preserved in the ignored task evidence folder.

The canonical isolated checkout receives released source by path and hash; it excludes unrelated recovered consumer work. Final analyzer/build/native evidence is kept under `.cache/admin-smart-tables-20261015/` in the original workspace. Those local files are not hosted deployment acceptance and may contain fictional private fixture material.

Revolut Design from Jean Bosco Skills remains the sole visual authority. The isolated authority hygiene check passes; a diagnostic against the large original workspace also identified two immutable historical cache JSON metadata declarations, which were preserved rather than rewritten as new appearance authority. Exact visual fidelity, physical devices and spoken accessibility remain unverified.

Production was still serving the earlier implementation in the preceding readback. Hosted migrations 0008–0012, missing private receipt storage, Owner activation, actual role/provider/security/finance acceptance, successful exact-source CI, recovery/performance/device evidence and approved production cutover remain open. No production mutation or real payment is implied by this update.
