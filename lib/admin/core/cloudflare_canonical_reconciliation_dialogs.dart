part of 'cloudflare_canonical_reconciliation_pages.dart';

Future<bool> _confirmCanonicalAttempt(
  BuildContext context,
  CanonicalReconciliationApi api,
  CanonicalFinancialAttempt attempt, {
  required bool Function() canConfirm,
}) async {
  var accepted = false;
  return await showDialog<bool>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (context) => Consumer(
          builder: (context, ref, _) {
            final user = ref
                    .watch(cloudflareAdminSessionProvider)
                    .asData
                    ?.value,
                authorized = identical(
                  api,
                  ref.watch(canonicalReconciliationApiProvider),
                );
            return StatefulBuilder(
              builder: (context, local) => AlertDialog(
                title: Text(
                  attempt.needsLookup
                      ? 'Review identical request'
                      : 'Review member attribution',
                ),
                content: SizedBox(
                  width: 760,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'This records a decision about retained evidence. Provider settlement is not asserted.',
                        ),
                        if (!authorized)
                          const _Note(
                            'Account access changed. Close this review and reopen the payment.',
                          ),
                        if (authorized)
                          _records(
                            'Reviewed request',
                            [
                              {'id': attempt.key, ...attempt.body},
                            ],
                            {
                              for (final key in attempt.body.keys.where(
                                (key) => key != 'expected_payment_identity',
                              ))
                                key: _label(key),
                            },
                          ),
                        if (authorized &&
                            attempt.body['expected_payment_identity'] is Map)
                          _records(
                            'Recorded member identity',
                            [
                              {
                                'id': 'member',
                                ...Map<String, dynamic>.from(
                                  attempt.body['expected_payment_identity']
                                      as Map,
                                ),
                              },
                            ],
                            const {
                              'display_name': 'Name',
                              'momo_provider': 'MoMo provider',
                              'momo_number': 'MoMo number',
                              'momo_pay_code': 'MoMo code',
                            },
                          ),
                        if (authorized)
                          SelectableText('Request reference: ${attempt.key}'),
                        CheckboxListTile(
                          value: accepted,
                          onChanged: !authorized
                              ? null
                              : (value) => local(() => accepted = value!),
                          title: const Text(
                            'I reviewed this exact member, amount and recorded evidence.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed:
                        accepted && _fresh(user) && authorized && canConfirm()
                        ? () => Navigator.pop(context, true)
                        : null,
                    child: const Text('Save reviewed request'),
                  ),
                ],
              ),
            );
          },
        ),
      ) ??
      false;
}

Future<CanonicalFinancialAttempt?> _independentCanonicalReview(
  BuildContext context,
  CanonicalReconciliationApi api,
  CanonicalReconciliationDetail detail,
  CanonicalReconciliationProposal proposal,
) async {
  var checked = false;
  String? error;
  final current = api
      .members(detail, search: proposal.values['member_public_id'] as String)
      .then(
        (page) => page.rows
            .where((member) => member.id == proposal.values['member_user_id'])
            .firstOrNull,
      );
  return await showDialog<CanonicalFinancialAttempt>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) => _CanonicalReviewControllerScope(
      builder: (controller) => Consumer(
        builder: (context, ref, _) {
          final user = ref.watch(cloudflareAdminSessionProvider).asData?.value,
              authorized =
                  _fresh(user) &&
                  identical(api, ref.watch(canonicalReconciliationApiProvider));
          return StatefulBuilder(
            builder: (context, local) => FutureBuilder<ReconciliationMember?>(
              future: current,
              builder: (context, snapshot) {
                final ready = snapshot.connectionState == ConnectionState.done,
                    eligible =
                        ready &&
                        !snapshot.hasError &&
                        proposal.currentFor(detail, snapshot.data);
                void decide(String outcome) {
                  try {
                    final attempt = api.review(
                      detail,
                      proposal,
                      outcome,
                      controller.text,
                      member: snapshot.data,
                    );
                    Navigator.pop(context, attempt);
                  } catch (problem) {
                    local(() => error = _safeError(problem));
                  }
                }

                return AlertDialog(
                  title: const Text('Independent evidence review'),
                  content: SizedBox(
                    width: 800,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!authorized)
                            const _Note(
                              'Account access changed or verification expired. Close this review and reopen the payment.',
                            ),
                          if (authorized)
                            _records(
                              'Retained identity snapshot',
                              [
                                {
                                  'id': proposal.id,
                                  ...?proposal.identity?.json,
                                },
                              ],
                              const {
                                'display_name': 'Name',
                                'momo_provider': 'MoMo provider',
                                'momo_number': 'MoMo number',
                                'momo_pay_code': 'MoMo code',
                              },
                            ),
                          if (!ready) const LinearProgressIndicator(),
                          if (ready && !eligible)
                            const _Note(
                              'The current member, receiver or payment no longer matches the proposal. Approval is unavailable. You can record a rejection.',
                            ),
                          if (authorized)
                            TextField(
                              controller: controller,
                              maxLength: 500,
                              minLines: 2,
                              maxLines: 4,
                              decoration: const InputDecoration(
                                labelText: 'Independent review reason',
                              ),
                              onChanged: (_) => local(() {}),
                            ),
                          CheckboxListTile(
                            value: checked,
                            onChanged: !authorized
                                ? null
                                : (value) => local(() => checked = value!),
                            title: const Text(
                              'I independently reviewed the event-specific evidence reference and this recorded member identity.',
                            ),
                          ),
                          const _Note(
                            'Approval requires an independently reviewed event-specific evidence reference. A missing, ambiguous or repeated statement reference is not a verified transaction ID. Approval records the contribution; it does not confirm provider settlement or move funds.',
                          ),
                          if (error != null) _Note(error!, error: true),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    OutlinedButton(
                      onPressed:
                          ready &&
                              checked &&
                              authorized &&
                              controller.text.trim().length >= 8
                          ? () => decide('rejected')
                          : null,
                      child: const Text('Record rejection'),
                    ),
                    FilledButton(
                      onPressed:
                          eligible &&
                              checked &&
                              authorized &&
                              controller.text.trim().length >= 8
                          ? () => decide('approved')
                          : null,
                      child: const Text('Record independent approval'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    ),
  );
}

class _CanonicalReviewControllerScope extends StatefulWidget {
  const _CanonicalReviewControllerScope({required this.builder});

  final Widget Function(TextEditingController controller) builder;

  @override
  State<_CanonicalReviewControllerScope> createState() =>
      _CanonicalReviewControllerScopeState();
}

class _CanonicalReviewControllerScopeState
    extends State<_CanonicalReviewControllerScope> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}

Future<String?> _reviewRetainedEvidence(
  BuildContext context,
  Object? authority,
) async {
  var accepted = false;
  return showDialog<String>(
    context: context,
    animationStyle: CollectMotion.animationStyle(context),
    builder: (context) => _CanonicalReviewControllerScope(
      builder: (controller) => _CanonicalEvidenceAccess(
        authority: authority,
        protectedSource: true,
        builder: (context, user, authorized) => StatefulBuilder(
          builder: (context, local) => AlertDialog(
            title: const Text('Review SMS-source evidence access'),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This evidence contains an original SMS or its source has not been classified. Revealing it records your account and review reason in the audit history.',
                    ),
                    if (!authorized)
                      _Note(
                        user?.permissions.contains('sms.read') != true ||
                                user?.permissions.contains('sms.reveal') != true
                            ? 'This account does not have permission to reveal SMS-source evidence. Close this review.'
                            : user?.usesEmailVerification == true
                            ? 'Account access changed or email verification expired. Close this review, verify your email and reopen the payment.'
                            : 'Account access changed or verification expired. Close this review, verify your authenticator and reopen the payment.',
                        error: true,
                      ),
                    TextField(
                      controller: controller,
                      enabled: authorized,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Evidence access reason',
                        helperText: '8 to 1000 printable characters.',
                      ),
                      onChanged: (_) => local(() {}),
                    ),
                    CheckboxListTile(
                      value: accepted,
                      onChanged: authorized
                          ? (value) => local(() => accepted = value == true)
                          : null,
                      title: const Text(
                        'I need the original evidence for this review and understand that this access is audited.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    authorized &&
                        accepted &&
                        retainedEvidenceReviewReason(controller.text) != null
                    ? () => Navigator.pop(
                        context,
                        retainedEvidenceReviewReason(controller.text),
                      )
                    : null,
                child: const Text('Reveal retained evidence'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Recheck both authority and proof on provider updates, proof/session expiry
/// and resume. Once concealed, the operator must reopen and audit a new read.
class _CanonicalEvidenceAccess extends ConsumerStatefulWidget {
  const _CanonicalEvidenceAccess({
    required this.authority,
    required this.protectedSource,
    required this.builder,
  });

  final Object? authority;
  final bool protectedSource;
  final Widget Function(BuildContext, CloudflareAdminUser?, bool) builder;

  @override
  ConsumerState<_CanonicalEvidenceAccess> createState() =>
      _CanonicalEvidenceAccessState();
}

class _CanonicalEvidenceAccessState
    extends ConsumerState<_CanonicalEvidenceAccess>
    with WidgetsBindingObserver {
  Timer? _expiry;
  DateTime? _deadline;
  bool _accessLost = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _recheckAt(DateTime? deadline, DateTime now) {
    if (_deadline == deadline) return;
    _expiry?.cancel();
    _deadline = deadline;
    if (deadline == null) return;
    _expiry = Timer(deadline.difference(now), () {
      if (mounted) setState(() => _deadline = null);
    });
  }

  @override
  void dispose() {
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value,
        now = ref.watch(adminClockProvider)();
    final authorized =
        !_accessLost &&
        user != null &&
        user.authorityKey == widget.authority &&
        user.expiresAt.isAfter(now) &&
        user.permissions.contains('payments.evidence.read') &&
        (!widget.protectedSource ||
            user.permissions.contains('sms.read') &&
                user.permissions.contains('sms.reveal') &&
                user.hasRecentSensitiveVerification(now: now));
    DateTime? deadline;
    if (authorized) {
      deadline = user.expiresAt;
      if (widget.protectedSource) {
        final proofDeadline = user.sensitiveVerificationAt!.add(
          const Duration(minutes: 5, milliseconds: 1),
        );
        if (proofDeadline.isBefore(deadline)) deadline = proofDeadline;
      }
    } else {
      _accessLost = true;
    }
    _recheckAt(deadline, now);
    return widget.builder(context, user, authorized);
  }
}

class _CanonicalEvidenceDialog extends StatelessWidget {
  const _CanonicalEvidenceDialog(
    this.text,
    this.authority, {
    required this.protectedSource,
  });
  final String text;
  final Object? authority;
  final bool protectedSource;

  @override
  Widget build(BuildContext context) => _CanonicalEvidenceAccess(
    authority: authority,
    protectedSource: protectedSource,
    builder: (context, user, authorized) => AlertDialog(
      title: const Text('Retained payment evidence'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: authorized
              ? SelectableText(text)
              : Text(
                  protectedSource
                      ? 'Account access changed or verification expired. Close this evidence view.'
                      : 'Account access changed. Close this evidence view.',
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close evidence'),
        ),
      ],
    ),
  );
}
