part of 'contribution_flow_screen.dart';

extension _ContributionRequestRecovery on _ContributionFlowState {
  Future<void> _restoreCommand({bool preserveError = false}) async {
    final repository = ref.read(memberPaymentRepositoryProvider);
    final owner = _captureOwner(
      repository,
      ref.read(memberPaymentStateProvider).currentProfile?.id,
    );
    final operation = ++_flowGeneration;
    bool current() => _ownsOperation(operation, owner);
    if (owner.profileId == null) {
      if (current()) _updateFlow(() => _restoringRecovery = false);
      return;
    }
    try {
      final recovery = await repository.restoreContributionCommand(
        widget.collectionId,
      );
      if (!current()) return;
      _updateFlow(() {
        _commandRecovery = recovery;
        _working = false;
        _restoringRecovery = false;
        _recoveryReadFailed = false;
        if (!preserveError) _error = null;
      });
    } catch (_) {
      if (current()) {
        _updateFlow(() {
          _working = false;
          _restoringRecovery = false;
          _recoveryReadFailed = true;
          _error =
              'Saved payment requests could not be read. Check again before another payment.';
        });
      }
    } finally {
      // A scope change can invalidate this read while it is nested inside a
      // payment operation. Wait for this old read to settle before retrying
      // custody for the new scope.
      if (mounted && _pendingScopeOperation == operation) {
        _finishOperation(operation, () => false);
      }
    }
  }

  Future<void> _checkCommand() async {
    if (_working || _restoringRecovery) return;
    final recovery = _commandRecovery;
    if (recovery == null) {
      if (_unverifiedIntent != null) {
        await _checkUnverifiedIntent();
        return;
      }
      _updateFlow(() => _restoringRecovery = true);
      await _restoreCommand();
      return;
    }
    final repository = ref.read(memberPaymentRepositoryProvider);
    final owner = _captureOwner(
      repository,
      ref.read(memberPaymentStateProvider).currentProfile?.id,
    );
    final operation = ++_flowGeneration;
    bool current() => _ownsOperation(operation, owner);
    _updateFlow(() {
      _working = true;
      _error = null;
    });
    try {
      final checked = await repository.checkContributionCommand(
        recovery.body.requestId,
      );
      if (!current()) return;
      _updateFlow(() => _commandRecovery = checked);
      final intentId = checked.intentId;
      if (intentId == null) {
        _updateFlow(
          () => _error =
              'The outcome is still unknown. This does not prove that no payment occurred.',
        );
        return;
      }
      if (ref.read(memberPaymentStateProvider).memberScopeUncertain) {
        _updateFlow(
          () => _error = 'Refresh your groups before checking payment details.',
        );
        return;
      }
      final scopeGeneration = repository.memberScopeGeneration;
      final refreshed = await repository.refreshPaymentIntent(intentId);
      if (!_ownsOperation(operation, owner, scopeGeneration: scopeGeneration)) {
        return;
      }
      if (refreshed.id != intentId ||
          refreshed.collectionId != recovery.body.collectionId ||
          refreshed.expectedAmountRwf != recovery.body.amountRwf) {
        throw const FormatException(
          'Payment status does not match the original request.',
        );
      }
      if (refreshed.hasCommittedContribution) {
        await repository.acknowledgeCommittedContribution(refreshed);
      } else {
        _updateFlow(() {
          _unverifiedIntent = refreshed;
          _error =
              'A matching request was found. Its payment outcome is not confirmed; check your mobile money provider before another transfer.';
        });
        return;
      }
      if (!_ownsOperation(operation, owner, scopeGeneration: scopeGeneration)) {
        return;
      }
      _updateFlow(() {
        _commandRecovery = null;
        _unverifiedIntent = null;
        _intent = refreshed;
        _preparedOwner = (
          repository: repository,
          profileId: owner.profileId,
          sessionGeneration: owner.sessionGeneration,
          scopeGeneration: scopeGeneration,
        );
        _awaitingConfirmation = true;
        _momoRequestOpened = false;
        _manualInstructions = false;
      });
    } catch (_) {
      if (current()) {
        _updateFlow(
          () => _error =
              'The original request remains saved. Check your connection and try again.',
        );
      }
    } finally {
      _finishOperation(operation, current);
    }
  }

  Future<void> _checkUnverifiedIntent() async {
    final intent = _unverifiedIntent;
    if (_working || _restoringRecovery || intent == null) return;
    final repository = ref.read(memberPaymentRepositoryProvider);
    final state = ref.read(memberPaymentStateProvider);
    final owner = _captureOwner(repository, state.currentProfile?.id);
    if (owner.profileId == null || state.memberScopeUncertain) {
      _updateFlow(
        () => _error = 'Refresh your groups before checking payment details.',
      );
      return;
    }
    final operation = ++_flowGeneration;
    bool current() =>
        _ownsOperation(
          operation,
          owner,
          scopeGeneration: owner.scopeGeneration,
        ) &&
        _unverifiedIntent?.id == intent.id;
    _updateFlow(() {
      _working = true;
      _error = null;
    });
    try {
      final refreshed = await repository.refreshPaymentIntent(intent.id);
      if (!current()) return;
      if (refreshed.id != intent.id ||
          refreshed.collectionId != intent.collectionId ||
          refreshed.expectedAmountRwf != intent.expectedAmountRwf ||
          (intent.hasCommittedContribution &&
              !refreshed.hasCommittedContribution) ||
          (intent.confirmationStatus == 'reversed' &&
              refreshed.confirmationStatus != 'reversed')) {
        throw const FormatException('Payment status could not be verified');
      }
      if (!refreshed.hasCommittedContribution) {
        _updateFlow(
          () => _error =
              'A matching request was found. Its payment outcome is not confirmed; check your mobile money provider before another transfer.',
        );
        return;
      }
      await repository.acknowledgeCommittedContribution(refreshed);
      if (!current()) return;
      _updateFlow(() {
        _unverifiedIntent = refreshed;
        _error = null;
      });
    } catch (_) {
      if (current()) {
        _updateFlow(
          () => _error =
              'The original request remains available. Check your connection and try again.',
        );
      }
    } finally {
      _finishOperation(operation, current);
    }
  }
}
