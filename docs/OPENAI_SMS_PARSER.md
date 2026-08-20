# OpenAI SMS Parser

`parse-payment-sms` runs in Supabase Edge Functions only. Flutter never calls OpenAI directly.

The parser uses the Responses API with `text.format.type = json_schema`, `strict = true`, and schema version `collect.sms_parser.openai.v2`. The configured `OPENAI_MODEL` is required; there is no client-side model call or deterministic parsing substitute.

If OpenAI parsing succeeds but the following transactional allocation call is temporarily unavailable, the parsed event remains `unallocated`. A retry reuses that saved model result and reruns only the idempotent allocation; it does not call OpenAI twice or create a second payment.

OpenAI performs the SMS parsing; there is no deterministic SMS parser or
regex fallback. Its structured output stores extracted facts and confidence.
Postgres then enforces exact payer, amount, time, receiver-ownership, and
single-intent conditions before posting. One exact match calls the locked,
idempotent database function that creates the payment, allocation, group credit,
payer credit, audit record, intent transition, and notification atomically.
Incomplete, conflicting, duplicate, low-confidence, or ambiguous results stay
unposted and reviewable.

Every accepted MTN MoMo or Airtel Money message is parsed by the OpenAI
Responses API in the Supabase Edge Function. The request uses a strict schema,
disables response storage, bounds input/output and runtime, treats SMS text as
untrusted data, detects refusals, and validates every returned value before it
is persisted. If OpenAI is unavailable or does not return a complete valid
structured result, the raw SMS parse status is marked failed, the native queue
is not acknowledged, and the message remains retryable and unallocated.

Rules:

- Do not invent missing values.
- Return `null` for unknown fields.
- Only incoming received-money SMS can become payment events.
- Promotional, balance-only, failed, loan, airtime, and outgoing SMS are ignored or sent to review.
- Balance fragments are redacted before model submission where possible.
- Opted-in SMS content is sent through Collect servers to the OpenAI API; this
  is disclosed before SMS access is enabled and in the privacy policy.
- Do not extract or store payer names, receiver names, payment reasons, or raw reference text.
- Extract only transaction ID, amount, currency, phones for hashing, transaction time, network, direction, explicit 6-digit Collect ID, and confidence.
- If a provider message omits its receiving number, the model is not trusted
  to choose a group. Postgres may derive the route only when exactly one active
  intent matches the payer, amount, time window, and a receiver owned by the
  authenticated SMS account; otherwise the event stays in review.
