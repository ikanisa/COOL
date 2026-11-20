# Native SMS processing control

This runbook describes the existing Collect lanes. It does not authorize a live
change, replace the existing release/fence procedure, or introduce a new service.

The authenticated Admin health response reports configuration separately:

- `momo_processing`: the managed MoMo gateway lane, controlled by
  `MOMO_PROCESSING_PAUSED`.
- `native_auto_processing`: automatic native SMS extraction, controlled by
  `BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED`.
- `native_sms_ledger`: native SMS-to-Collect posting, controlled by the same
  `BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED` setting.

These are configuration states, not proof of worker heartbeat, provider
availability, receipt delivery, completed processing or an actual halt. A
managed-lane pause does not stop the native lane. Setting the native flag to
`false` does not erase already captured messages or itself stop capture on a
phone. An in-flight invocation can retain the configuration with which it
started, so a flag change alone is not a completed emergency stop.

## Coordinated halt

1. Use the existing Collect application-fence and release procedure to quiesce
   new admissions and stop the scheduler; wait for admitted work to finish or
   retain its outcome as unresolved under the existing recovery rules. Preserve
   queued observations, ledger state and any unknown obligations. Do not infer
   that in-flight work finished merely because the scheduler stopped.
2. Through the existing sealed configuration and release process, set
   `BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED=false`. If the managed MoMo lane
   also needs to stop, set `MOMO_PROCESSING_PAUSED=true` independently. Bind the
   revised configuration to the actual release and restart the existing runtime
   with scheduling stopped and the fence still quiesced. Read back the actual
   running runtime's native setting without exposing private values. Do not send
   a jobs tick while the sealed file and running runtime disagree: the tick can
   process work before its response reveals that disagreement.
3. Once the runtime's intended disabled settings are confirmed and the existing
   fence procedure permits reopening, verify the fresh authenticated health
   response before restarting the scheduler. Independently verify the application fence/admission state,
   completed or unresolved in-flight work, scheduler outcome and unchanged
   source/ledger records. Configuration alone does not prove no financial work
   remains in flight. Do not dispatch a real SMS, provider request or synthetic
   payment against the live service for this check.
4. Record the incident, the exact configuration/release identity, outstanding
   unknown outcomes and the responsible operator using existing operational
   records. Never put credentials or SMS content in the runbook.

## Resume

After the cause is resolved, reconcile every unresolved operation and retained
queue item before returning the native setting to `true` through the same
source-bound deployment procedure. Re-enable the managed lane only if separately
intended and its existing admission requirements are met. Restore the scheduler,
confirm current lane configuration and bounded processing, then verify the
existing idempotency and financial reconciliation evidence for retries. A saved
configuration or an HTTP health response alone is not proof that new messages
have been processed.
