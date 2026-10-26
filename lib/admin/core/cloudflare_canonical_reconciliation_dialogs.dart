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

class _CanonicalEvidenceDialog extends ConsumerWidget {
  const _CanonicalEvidenceDialog(this.text, this.authority);
  final String text;
  final Object? authority;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(cloudflareAdminSessionProvider).asData?.value;
    final authorized =
        user != null &&
        user.authorityKey == authority &&
        user.expiresAt.isAfter(DateTime.now()) &&
        user.permissions.contains('payments.evidence.read');
    return AlertDialog(
      title: const Text('Retained payment evidence'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: authorized
              ? SelectableText(text)
              : const Text('Account access changed. Close this evidence view.'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close evidence'),
        ),
      ],
    );
  }
}
