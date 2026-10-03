# ARC03 maintained integration

Applied the exact reviewed three-file proposal after all 36 source fences matched. Originals are preserved here. Readiness denial probe names and policies now derive from each reviewed manifest entry's auth mode. The source/config/auth plan validates before any live inventory or HTTP call. Current 13 endpoint behavior, empty POST JSON, content-type-only headers, JWT/internal body-discard behavior and custom auth error checks are preserved. Probe order follows manifest order.

Actual maintained verification: Ruby 2.6.10 inventory suite: 22 tests, 258 assertions, 0 failures/errors/skips; all 17 original methods retained plus 5 new methods. Three existing Python unsigned-probe regressions pass on pinned Python 3.12.14 with installed Node 24.19.0. The first Python attempt had three CANDIDATE_NODE_REQUIRED fixture-setup errors because controlled PATH omitted Node; that failure remains retained. Only PATH changed before the successful second run. The relevant 389 fixture/consumer source inputs remained unchanged.

No fourth maintained source file was changed. No builds, DB/provider calls, deployment, app/SDK/cache or readiness-register changes were performed by this agent. The readiness tests use shell mocks and temporary fixtures; production readiness main is not executed. All three command process groups were absent at completion.

ARC03 remains open for its original deployed/source hash equality, migrated SQL dependency, approved scheduler configuration, approved staging positive/denial HTTP and authorized production-readback acceptance.
