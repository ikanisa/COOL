# Private Auth fixture boundary proposal

Promote only `proposal/test/core/auth_fixture_token_test.dart` and
`proposal/test/support/synthetic_jwt.dart` to their repository-relative paths,
after checking `proposal.json` preimages. Use the existing target source mode
0644 for both maintained files. The new support path must still be absent.

The project Auth test currently imports a fixture from `third_party/gotrue/test`,
which the source exporter correctly excludes as upstream QA source. Moving the
project test's dependency into its own `test/support` boundary keeps the captured
candidate self-contained. The sole edit to the 3-case Auth test is its fixture
import. Everything from `void main()` onward, including all test names, assertions
and callbacks, is byte-identical. The helper is an exact 508-byte copy of the
existing authored dummy JWT fixture. Its signature remains invalid. The original
vendor fixture and tests, exporter, analysis options, gates, dependencies and
production Auth code are untouched.

Actual private proof: `execution1/result.json` reports PASS for all 3 existing
semantic scenarios against the pinned GoTrue implementation, using direct Dart
without Flutter, pub or package-tool commands. Each proposed fixture token equals
the original fixture token; expiry validation rejects the expired token; future
claims parse unchanged; the asymmetric token requests only the mocked JWKS path,
is rejected as AuthException, and leaves currentSession null. The completed child
ran for 1.169149 seconds within 60 seconds, with its process group absent afterward.
All 1,180 captured inputs, including dependency library closure and Dart SDK
library sources, retained identical hashes, sizes and modes before/after.

This direct proof is not a canonical Flutter-test or strict-analysis result.
Root must integrate the two files, capture the new source candidate, and execute
the affected canonical Auth test plus the current aggregate acceptance checks.
No maintained source, root APP/SDK outputs, canonical records, provider state or
release approvals were written by this worker.
