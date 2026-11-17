# Retained runtime controls

This directory preserves the source of the external lock-aware retained runtime
controls. It does not alter the immutable 033 or production release snapshots.
The installed runtime directory contains private, owner-only copies; the
source-bound bootstrap and cutover evidence are held separately under the
COLLECT production qualification directory.

The retained operator wrapper supports only the existing retained Edge path.
It does not expose the generic Compose stack creation, role provisioning or
publication commands. The shared operation lock coordinates supported control
entrypoints; it does not claim to constrain arbitrary direct Docker/root use or
retired historical executors.

Run the synthetic installed-form tests with:

```sh
python3 -B -m unittest discover -s scripts/self_hosted/retained_control -p 'test_retained_control.py' -v
```

The tests copy code to a private temporary directory and exercise only
synthetic files, child processes and mock hosts. They do not deploy, contact a
provider, or access the live database or phone.

## Capacity monitoring in the existing startup watcher

The existing `runtime_startup_lockaware.py --run` loop can collect host capacity
without another service or a database/provider call. An absent `capacity_monitor`
setting preserves the previous behavior. Enable it in a new protected settings
version, using the same owner-only working directory for its state file:

```json
{
  "capacity_monitor": {
    "enabled": true,
    "state_path": "/existing/private/working-directory/capacity-state.private.json",
    "sample_interval_seconds": 300,
    "max_samples": 288,
    "repeat_alert_seconds": 21600,
    "notification": "macos",
    "volumes": [
      {"id": "internal", "path": "/"},
      {"id": "pro_g40", "path": "/Volumes/PRO-G40"},
      {"id": "t7", "path": "/Volumes/T7", "backing_group": "t7_runtime"},
      {"id": "runtime", "path": "/Volumes/SupaRuntime", "backing_group": "t7_runtime"}
    ]
  }
}
```

Every existing watcher cycle measures unprivileged available blocks. An absent,
unmounted or invalid filesystem is explicitly unavailable. Warning thresholds
match `scripts/self_hosted/health.py`: below 10 GiB **or** below 15% available.
Below the existing 2 GiB startup reserve is critical. These observations do not
stop/restart the VM, change the reserve, authorize a write, or alter pending
recovery actions. T7 and runtime observations share a backing group; capacity is
never added across them.

The state file retains at most 288 snapshots and 256 KiB. Ordinary snapshots are
spaced by the configured interval; a status/device transition is retained
immediately. Growth is an observed available-byte delta over a stable device and
time window, with no exhaustion forecast. Missing samples, device changes,
backward clocks and stale state withhold a confirmed growth/health claim. State
is mode 0600, atomically replaced and synchronized. Unexpected state changes,
symlinks/hardlinks, malformed or oversized data are refused rather than erased.
Monitoring failure records `capacity_monitor_unconfirmed` on a best-effort basis
while runtime observation continues; a full state/log volume must not make the
monitor failure escape that boundary. Inspect this event as well as capacity
status; absence of an event does not prove the observer is healthy.

`notification: "macos"` submits a local operator notification on initial
attention, status changes/recovery and at most one repeat per configured period.
`"none"` collects the same local state without notifications. Notification
intent is saved before `osascript`; timeout/unknown outcomes are not immediately
replayed. `submitted` means only that macOS accepted the command. The state
always reports `delivered_or_acknowledged: false`; retain an actual operator
acknowledgement separately before claiming delivered-alert acceptance.

Before activation, stage the exact qualified startup helper beside its protected
`operation_lock.py` sibling (both owner-owned, mode 0600), preserve the installed
helper/settings/plist, and run:

```sh
python3 -I -B /qualified/runtime_startup.py --settings /new/settings.private.json --capacity-check
python3 -I -B /qualified/runtime_startup.py --settings /new/settings.private.json --check
```

Both commands are read-only: no capacity-state creation, notifications, image
attach or VM resume. Capacity-check exit 2 means attention/unconfirmed, not an
instruction to reduce the threshold. Root coordinates adoption of the new exact
helper/settings and existing LaunchAgent, including all wrapper/source bindings.
No new LaunchAgent is installed. After activation, read `--capacity-status`,
wait at least one sample interval, and read it again. Confirm fresh timestamps,
bounded history, real available blocks, unchanged runtime identity/pending
obligations and local notification submission status. Human acknowledgement,
sustained representative workload evidence and independent host/credential/root-
key recovery remain distinct acceptance steps.
