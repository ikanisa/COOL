# Non-secret examples — intentionally blocked

The six example manifests show the required top-level field layout for each product and phase. They are deliberately unusable: an old timestamp, placeholder version/digests, nonexistent references, no artifacts and no executed qualifications. A build/promotion designation in an example is **not** approval. The validator must reject these files.

Do not repair them by merely changing dates or booleans. Produce evidence from the actual qualification systems following `docs/EVIDENCE_CONTRACT.md`. `docs/required-policies.json` records the current immutable policy requirements for inspection. The executable guard, not an edited copy of that JSON, defines the accepted policy.

Default integration layout (outside the source digest):

```text
.release-evidence/
  source/release-manifest.json
  build/release-manifest.json
  promotion/release-manifest.json
```

Within each phase directory keep referenced source/dependency manifests, exact candidate artifacts, qualification results and logs. Product legacy evidence is required by the combined release entrypoints as described in `docs/INTEGRATION.md`.

No private signing keys, service-role credentials, personal SMS bodies, real account identifiers or production passwords belong in this delivery. Key material stays in its approved signing or runtime secret store. A literal configuration placeholder does not fulfill production configuration or evidence requirements.

## r4 provenance templates

`trust-policy-UNCONFIGURED.example.json` is empty and expired; `provenance-UNSIGNED.example.json` has no signatures. Both intentionally fail. No production roots or private keys are included. Configure real trust separately outside candidate/evidence directories using `docs/PROVENANCE_SETUP.md`. Build/promotion requires `provenance.json` beside the phase manifest plus protected external policy/pin settings.
