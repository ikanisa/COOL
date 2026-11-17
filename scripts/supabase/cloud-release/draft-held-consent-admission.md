# Held SMS consent admission draft

This source is a default-off design candidate. `draft-held-consent-admission.sql`
is not an ordered migration and must not be applied or used to activate recovery.
Promote it only with a reviewed, correctly ordered migration, fenced Cloud
qualification, catalog/ACL readback and release-operator support.

The new held-only request and exact ACK require `expectedConsentGeneration`.
The intended Android implementation must atomically retain the originally
confirmed value with the complete protected request before marking it
ATTEMPTING, and must reuse that value without substitution. Old pending entries
do not contain it and cannot safely synthesize it from current consent. The
client still has no resend implementation and the recovery flag stays off.

The held request fingerprint includes the expected generation. First admission
must lock the current consent row and compare that generation before creating
the request, witness or hold. The draft wrapper takes that lock for the calling
transaction and then invokes the existing exact-key admission. Previously
admitted requests retain their original generation, grant and request hash.
The ACK remains read-only and never authorizes a resend. Ordinary observation
requests and their fingerprint stay unchanged. Existing clients cannot send the
new field: with recovery off they receive 404, and if it were enabled they fail
closed with 400. That incompatibility must be integrated before activation.

The generation is a client-supplied claim, not a cryptographic proof of its
history. Before any server admission, a modified client can replace an old value
with the current one; the server cannot distinguish that from a new request.
Therefore these changes do not establish original grant identity/version, nor
resistance to a compromised client or journal replacement. The current actor,
consent row and current grant must match at admission. The existing consent
setter requires an increment when changing grant ID/version or enabled state,
and later request/hold checks compare the stored grant against current state.
This is only continuity under the retained monotonic-row and honest-client
assumptions; it is not independent proof of the original grant. Decide whether
those assumptions are acceptable. An adversarial guarantee would need a
server-authenticated witness bound to this request/source and a durable rule
that prevents reissuing a newer witness for the same intent after a grant
change. Issuance would have to occur before the client records ATTEMPTING;
that is a different protocol and needs separate qualification.

The local PGlite test executes the actual draft wrapper and predecessor key
admission with synthetic dependencies. PGlite serializes one backend; it does
not establish two-connection locking behavior, the full migration chain, live
RLS/catalog state, provider effects, or Android interoperability. Qualify
concurrent revoke/regrant and exact retries with independently reviewed,
two-connection tests before promotion.
