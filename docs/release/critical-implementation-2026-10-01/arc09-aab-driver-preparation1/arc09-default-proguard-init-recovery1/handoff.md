# Included-build init recovery

The prior real readback failed because Gradle propagated the init script into Flutter's included `:gradle` build, where `:app` does not exist. The new init script skips every root except the exact physical Collect APP/android directory before project lookup. The rest of its producer and rule-file checks are byte-for-byte unchanged. Actual Groovy/Gradle behavior remains unverified until root executes the next controlled observation.

The copied driver retains exact SHA 6aec0de17f91f3981d2def8be12cc7f0f10eba40fca6c17ffea6f11166a893fc. The helper adds one optional explicit root-selected override with fixed plan/init path and SHA values. It admits only the init-script argument substitution, preserving all other plan fields, flags, task, cwd and 300-second bound. Original two-file APP overlay, source fence, archived native evidence, lifecycle controller and 42 prepared pins stay unchanged.

Root owns actual admission and execution. `root-admission-template.json` targets observation9. Retain AAB8 as failed; no graphs or AAB were accepted there. Twenty-seven pure fixtures passed (14 override cases and 13 affected overlay fixtures); the original 58 tracker fixtures are reused for unchanged driver scope. No Gradle, process metadata probes, signals, maintained/APP/SDK/cache/register mutation occurred here.
