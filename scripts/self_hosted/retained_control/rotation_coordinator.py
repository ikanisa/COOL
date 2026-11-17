"""Hold one shared host lock for a full one-use rotation or its rollback."""
import operation_lock
from guard_core import PHASES


def _marker(guard):
    return {'format':operation_lock.FORMAT, 'operation':guard.manifest['fence_operation'],
            'kind':'rotation', 'binding_sha256':guard.manifest_hash}

def _rollback_marker(guard):
    return {'format':operation_lock.FORMAT, 'operation':guard.manifest['rollback_fence_operation'],
            'kind':'rotation_rollback', 'binding_sha256':guard.manifest_hash}


def run_locked(guard, coordinator):
    """Caller holds the one common lock continuously, including journal setup."""
    if coordinator.active() is not None:
        raise operation_lock.OperationBusy('previous_operation_requires_reconciliation')
    guard.step('plan')
    marker = coordinator.begin(guard.manifest['fence_operation'], 'rotation', guard.manifest_hash)
    for phase in PHASES[1:]:
        guard.step(phase)
    coordinator.complete(marker)
    return {'complete':True, 'automatic_retry':False}


def run_all(guard, *, root=None):
    """Do not retry any phase. Failure leaves a durable global marker."""
    with operation_lock.Coordinator(root) as coordinator:
        return run_locked(guard, coordinator)


def reconcile_locked(guard, coordinator):
    if coordinator.active() not in (_marker(guard), _rollback_marker(guard)):
        raise operation_lock.OperationRefused('operation_owner_changed')
    return guard.reconcile()


def reconcile(guard, *, root=None):
    with operation_lock.Coordinator(root) as coordinator:
        return reconcile_locked(guard, coordinator)


def rollback_locked(guard, coordinator):
    # Refuse a repeated rollback before reserving a fresh global marker.
    if guard.journal.exists('rollback-intent.json') or guard.journal.exists('rollback-result.json'):
        raise operation_lock.OperationRefused('rotation_rollback_one_use')
    marker = coordinator.active()
    if marker is None:
        if not guard.journal.exists('final-result.json') or guard.journal.pending():
            raise operation_lock.OperationRefused('completed_rotation_required')
        marker = coordinator.begin(guard.manifest['rollback_fence_operation'], 'rotation_rollback', guard.manifest_hash)
    elif marker != _marker(guard):
        raise operation_lock.OperationRefused('operation_owner_changed')
    result = guard.rollback()
    coordinator.complete(marker)
    return result


def rollback(guard, *, root=None):
    with operation_lock.Coordinator(root) as coordinator:
        return rollback_locked(guard, coordinator)
