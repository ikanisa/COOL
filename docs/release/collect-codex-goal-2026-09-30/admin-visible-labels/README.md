# Visible group and member field labels

Group and member operation cards now keep each field label visible alongside its value and icon. The prior `iconOnlyFields` option and icon-only heading branch have been removed from the shared operation components and their callers. Existing semantics, statuses, identities and routes remain in place. The existing Admin PWA assertions were updated to reflect these visible headings and the currently supported gateway, Automations and exceptions routes; no new tests were added for this reversible presentation change.

`validation.json` binds the three selected source files before and after analysis. Dart analysis passed with no issues, and `make revolut-design-authority` passed. Exact source bytes and both command logs are retained. The existing Admin PWA and operations-readability checks passed33/33 in the linked Admin-exceptions packet. The three selected files still match the retained analysis hashes; a continuous shared-checkout freeze is not attested.

This is a local source and analysis check. Actual authenticated group/member captures, keyboard and screen-reader use, responsive route/state coverage and the required Revolut comparator evidence remain open. Design-authority hygiene does not certify visual fidelity or production readiness. This change is later than the captured source05 Admin bundle.

`MANIFEST.json` covers the retained files and excludes itself.
