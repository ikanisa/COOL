import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/money_format.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/repositories/payment_help_pending_store.dart';
import '../../shared/widgets/collect_components.dart';

class PaymentHelpSheet extends ConsumerStatefulWidget {
  const PaymentHelpSheet({
    required this.intent,
    required this.groupTitle,
    required this.repository,
    required this.isCurrent,
    required this.isScopeCurrent,
    super.key,
  });
  final PaymentIntentModel intent;
  final String groupTitle;
  final MemberPaymentRepository repository;
  final bool Function() isCurrent;
  final bool Function() isScopeCurrent;
  @override
  ConsumerState<PaymentHelpSheet> createState() => _PaymentHelpSheetState();
}

class _PaymentHelpSheetState extends ConsumerState<PaymentHelpSheet> {
  final _reference = TextEditingController(), _note = TextEditingController();
  PaymentHelpCheckpoint? _attempt;
  String? _error;
  bool _busy = false, _restoring = true, _recoveryFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    if (!widget.isCurrent()) return;
    setState(() {
      _restoring = true;
      _error = null;
    });
    try {
      final saved = await widget.repository.paymentHelpForIntent(
        widget.intent.id,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() {
        _attempt = saved;
        _recoveryFailed = false;
      });
    } catch (_) {
      if (mounted && widget.isCurrent()) {
        setState(() {
          _recoveryFailed = true;
          _error =
              'Saved payment help could not be restored. Try again before sending a request.';
        });
      }
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _restoring || _recoveryFailed || !widget.isCurrent()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.repository.requestPaymentHelp(
        intentId: widget.intent.id,
        providerReference: _reference.text,
        note: _note.text,
      );
      if (!mounted || !widget.isCurrent()) return;
      setState(() => _attempt = receipt);
    } catch (error) {
      if (mounted && widget.isCurrent()) {
        try {
          _attempt = await widget.repository.paymentHelpForIntent(
            widget.intent.id,
          );
        } catch (_) {
          _recoveryFailed = true;
        }
        if (!mounted || !widget.isCurrent()) return;
        setState(
          () => _error = error is StateError
              ? error.message
              : 'The result is not confirmed. Retry the same request when connected. Your payment status is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(memberPaymentStateProvider);
    final current = widget.isCurrent();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CollectBottomSheet(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Payment help',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close payment help',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                if (!widget.isScopeCurrent())
                  const Text(
                    'Group information changed. Close this sheet and refresh before reopening payment help.',
                  )
                else if (!current)
                  const Text('Account changed. Close and reopen payment help.')
                else ...[
                  Text(
                    '${widget.groupTitle} · ${formatRwf(widget.intent.expectedAmountRwf)}',
                  ),
                  CollectSpacing.gap12,
                  if (_restoring)
                    Semantics(
                      liveRegion: true,
                      child: const Text('Restoring payment help…'),
                    )
                  else if (_recoveryFailed) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error ?? 'Saved payment help could not be restored.',
                      ),
                    ),
                    CollectSpacing.gap16,
                    CollectButton(
                      label: 'Try recovery',
                      onPressed: _restore,
                      expand: true,
                    ),
                  ] else if (_attempt?.received == true) ...[
                    Text(
                      'Request received',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text(
                      'Your request was saved for review. It does not confirm payment or credit a contribution.',
                    ),
                    CollectSpacing.gap12,
                    SelectableText('Request ID · ${_attempt!.requestId}'),
                  ] else ...[
                    Text(
                      _attempt == null
                          ? 'Ask for a check of this payment request. You can add the provider reference or an evidence note. Your payment status and balances stay unchanged.'
                          : 'Your original details are saved. You can retry this request. Your payment status and balances stay unchanged.',
                    ),
                    if (_attempt == null) ...[
                      TextField(
                        controller: _reference,
                        enabled: !_busy,
                        maxLength: 160,
                        decoration: const InputDecoration(
                          labelText: 'Reference',
                        ),
                      ),
                      TextField(
                        controller: _note,
                        enabled: !_busy,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Evidence note',
                        ),
                      ),
                    ] else ...[
                      CollectSpacing.gap12,
                      if (_attempt!.reference?.isNotEmpty == true)
                        SelectableText('Reference · ${_attempt!.reference}'),
                      if (_attempt!.note?.isNotEmpty == true)
                        Text(_attempt!.note!),
                    ],
                    if (_error != null) ...[
                      CollectSpacing.gap12,
                      Semantics(liveRegion: true, child: Text(_error!)),
                    ],
                    CollectSpacing.gap16,
                    CollectButton(
                      label: _busy
                          ? 'Sending request'
                          : _attempt != null
                          ? 'Retry request'
                          : 'Request check',
                      onPressed: _busy ? null : _submit,
                      expand: true,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
