# Roster extraction dispatch policy

The `prepare-roster-import` function denies a new PDF/image AI extraction with
`roster_extraction_unavailable` (HTTP 503) unless its represented server policy
passes validation. The check runs before resource reservation and again at the
actual decoder/provider fetch boundaries. Stored-result and recovery paths
retain their existing behavior. This document describes the current code; it
does not approve a processor, deployment or production release.

The upload passes through authenticated import validation, the signed decoder,
and the immutable original-source acknowledgement. When model processing is
used, the request includes the original PDF/image bytes. PDF requests use the
generic filename `collect-roster.pdf`; this minimizes the filename, not the
document content. The Responses request sets `store: false` and fixes its URL to
`https://api.openai.com/v1/responses`. Human review remains required for an import.

Four server environment values supplement the existing model/API-key and
decoder settings:

| Value | Required binding |
| --- | --- |
| `ROSTER_AI_APPROVAL_JSON` | The exact represented approval bytes, at most 8 KiB |
| `ROSTER_AI_APPROVAL_SHA256` | Independent lowercase SHA-256 of those complete bytes |
| `OPENAI_ORGANIZATION_ID` | Exact match to the policy organization |
| `OPENAI_PROJECT_ID` | Exact match to the policy project |

The closed JSON object contains exactly these twenty fields:

| Fields | Validation |
| --- | --- |
| `schema_version`, `purpose`, `provider` | `1`, `collect_roster_pdf_image_extraction`, `openai` |
| `enabled`, `status` | `true`, `approved` |
| `approval_id`, `approval_evidence_sha256` | UUID and lowercase SHA-256 |
| `approved_at`, `valid_until` | Valid zoned instants with a currently active window |
| `organization_id`, `project_id`, `model` | Exact effective runtime configuration matches |
| `responses_endpoint` | The fixed Responses URL above |
| `decoder_url`, `decoder_build_sha256` | Exact configured endpoint/build; `/decode`, no credentials/query/fragment, HTTPS except the explicitly permitted local test hosts |
| `processing_region_evidence_ref`, `retention_evidence_ref` | Bounded ASCII evidence references |
| `decoder_processor_evidence_ref`, `decoder_region_evidence_ref`, `decoder_retention_evidence_ref` | Bounded ASCII evidence references |

Use compact JSON serialization. Duplicate/unknown fields or a mismatched whole
byte digest are rejected. Leading/trailing whitespace is included in the
digest. The model, API key and decoder URL retain their existing trim/default
normalization; the nine-value snapshot binds effective configuration. Changes
to that snapshot or expiry of the window abort the dispatch. No valid production
approval record or organization/project values are supplied by the test fixtures.

`store: false` is not proof of zero retention. OpenAI separately documents abuse
monitoring, application state, approved retention controls and image/file
exceptions. Residency is configured per project and can require a regional
domain prefix. These account settings and processor terms must be evidenced
independently; the current fixed global endpoint and evidence-reference strings
do not establish regional processing. [OpenAI data controls, reviewed 2 October
2026](https://developers.openai.com/api/docs/guides/your-data).

The remaining BE-13 work includes actual processor/region/transfer/retention
acceptance, durable policy lineage, source/derivative/backup erasure and holds,
spend and model-quality controls, and accurate Admin disclosure. The current
policy hash is not added to the existing three-field SQL AI metadata contract.
After a request may have left the process, a transport failure retains its
ambiguous charge/lease and does not establish that the provider stopped or
refunded it. Expiry/revocation and any processor-routing change need fresh
scoped verification before use.

Implementation sources: `supabase/functions/_shared/roster_ai_dispatch_policy.ts`,
`supabase/functions/_shared/openai_roster.ts`, and
`supabase/functions/prepare-roster-import/{index,handler}.ts`.
