# Route and state truth corrections — 28 September 2026

Three local behavior corrections were made under the owner-selected `revolut-design` authority, using the product's existing components and routes:

1. A group detail page with an initial data-load failure now shows its existing retry state. It no longer tells the member that the group link was removed or expired when the real outcome was a failed read.
2. The Admin platform-access panel invalidates its cached approval snapshot when the authenticated operator, target user, realtime tick or repository instance changes. Another operator's approval/revocation is no longer left displayed as the previous state after a realtime refresh.
3. The public homepage CTA says “How groups work” for the `/group-savings` explainer. It no longer says “Create Group” for a route that has no creation form.

Focused and related Flutter tests passed **89/89**, and targeted analysis was clean. These are local behavior/copy checks. Current signed-in data, responsive layout, accessibility, deployed Admin realtime and the exact visual references still require review; no screenshot baseline was changed or approved.
