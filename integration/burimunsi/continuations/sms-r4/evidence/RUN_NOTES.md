# R4 measured execution notes

The final full run is `verification.json`: 649 executed test/check cases, zero failures, 40 independently counted pinned-source hashes, and 75 input files. The protected-storage suite uses real JVM AES-GCM and synthetic in-memory durable ports; it does not emulate Android Keystore hardware or a real checkpoint backend. R3's separate host persistence suite retains its original 19 child-JVM executions.

Two earlier runner launches were interrupted by the execution-call timeout while later compilation was underway. They were not counted as passes and are not the delivered verification run. The final run completed all suites with unchanged inputs. The independent missing-toolchain run returned exit 2 and blocked every dependent Kotlin suite. No source was changed after the final run began.

No actual Android build, handset, carrier, hosted service, database or Collect checkout test ran. No production access, upload enablement or deployment was performed.
