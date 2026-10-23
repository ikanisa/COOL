part of 'cloudflare_admin_operating_pages.dart';

Future<String?> _reviewRequestCancellation(
  BuildContext context,
  String key, {
  required bool Function() current,
}) => showDialog<String>(
  context: context,
  animationStyle: CollectMotion.animationStyle(context),
  builder: (_) => _RequestCancellationReview(reference: key, current: current),
);

class _RequestCancellationReview extends ConsumerStatefulWidget {
  const _RequestCancellationReview({
    required this.reference,
    required this.current,
  });
  final String reference;
  final bool Function() current;

  @override
  ConsumerState<_RequestCancellationReview> createState() =>
      _RequestCancellationReviewState();
}

class _RequestCancellationReviewState
    extends ConsumerState<_RequestCancellationReview> {
  final _reason = TextEditingController();

  bool get _verified {
    final user = ref.read(cloudflareAdminSessionProvider).asData?.value;
    return user?.usesCanonicalEvidence == true &&
        user?.hasRecentSensitiveVerification() == true &&
        user!.permissions.contains('account.manage') &&
        widget.current();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cloudflareAdminSessionProvider);
    final verified = _verified;
    return AlertDialog(
      title: const Text('Cancel the original request reference'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'A committed change will be returned. Otherwise, the original reference will be blocked so a delayed retry cannot apply it.',
              ),
              if (widget.current())
                SelectableText('Original reference: ${widget.reference}'),
              if (!verified)
                Text(
                  ref
                              .read(cloudflareAdminSessionProvider)
                              .asData
                              ?.value
                              ?.usesEmailVerification ==
                          true
                      ? 'Verify your email before cancelling this reference.'
                      : 'Complete a current authenticator check before cancelling this reference.',
                ),
              if (widget.current())
                TextField(
                  controller: _reason,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  enabled: verified,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation reason',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              if (!widget.current())
                const Text(
                  'Account access changed. Close this cancellation review.',
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep reference'),
        ),
        FilledButton(
          onPressed: verified && _reason.text.trim().length >= 8
              ? () {
                  if (_verified) Navigator.pop(context, _reason.text.trim());
                }
              : null,
          child: const Text('Cancel uncommitted request'),
        ),
      ],
    );
  }
}
