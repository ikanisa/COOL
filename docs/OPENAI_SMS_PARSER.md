# OpenAI SMS Parser

`parse-payment-sms` calls OpenAI from Supabase Edge Functions only. Flutter never calls OpenAI directly.

The parser uses the Responses API with `text.format.type = json_schema`, `strict = true`, and schema version `collect.sms_parser.v1`. This follows OpenAI structured output guidance that schema adherence requires Structured Outputs rather than plain JSON mode.

Parser output is not authoritative. It stores extracted facts and confidence only. Allocation is performed by deterministic Postgres logic.

Rules:

- Do not invent missing values.
- Return `null` for unknown fields.
- Only incoming received-money SMS can become payment events.
- Promotional, balance-only, failed, loan, airtime, and outgoing SMS are ignored or sent to review.
- Balance fragments are redacted before model submission where possible.

