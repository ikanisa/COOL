# Release evidence

Collect's current release checks use the records below. Keep their paths and
content together when exporting a checkout for verification.

| Check or workflow | Input |
| --- | --- |
| Member-history decoder in CI | The pinned validation record and eight original synthetic SQL inputs under [test/fixtures/retained-member-history](../test/fixtures/retained-member-history/). |
| Public website copy | The [reviewed content contract](release/public-website-current-content-contract.json) binds the [historical baseline](release/public-website-content-baseline.json), the historical visible text and comparison, and the [current review](release/public-content-provenance/2026-11-22-main-merge-copy-comparison.json). |
| Public app previews | The current PNGs, [manifest](../web/public/app-screens/manifest.json), and [capture and review provenance](../web/public/app-screens/capture-provenance.json). |
| Design authority | The repository [authority adapter](release/revolut-design/authority.json) identifies the owner-selected Revolut Design skill. |
| Google Play | The [console audit packet](release/GOOGLE_PLAY_CONSOLE_AUDIT_PACKET.json), its [screenshot receipt](release/GOOGLE_PLAY_SCREENSHOT_CAPTURE_1.2.4_23.json), and the [historical release-blockers comparison](release/RELEASE_BLOCKERS.md). |
| Mobile release approvals | The [status](release/RELEASE_STATUS.md), [approval packet](release/RELEASE_APPROVAL_PACKET.md), [approval manifest](release/RELEASE_APPROVALS.json), and [template](release/RELEASE_APPROVALS.example.json). |
| UAT | The [evidence manifest](release/UAT_EVIDENCE_MANIFEST.json), [manifest template](release/UAT_EVIDENCE_MANIFEST.example.json), and [owner waiver evidence](release/UAT_OWNER_WAIVER_EVIDENCE_2026-08-05.md). |

Verify the retained member-history inputs and reconstructed defines without
starting Flutter.

```sh
python3 scripts/qa/retained_member_history.py --list-inputs
```

From a sparse checkout, read the same inputs from the committed fixture tree.

```sh
python3 scripts/qa/retained_member_history.py --git-source . HEAD --list-inputs
```

Run `make test-history-retained` to exercise the decoder on the Dart VM and
Chrome. The release and UAT gates read the checked-in manifests unless the
operator sets `RELEASE_APPROVALS_JSON` or `UAT_EVIDENCE_MANIFEST` to an explicitly
selected record.
