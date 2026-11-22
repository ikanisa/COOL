import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shared/widgets/collect_components.dart';
import 'privacy_contract.dart';
import 'privacy_review_contract.dart';

class PrivacyRequestReceiptCard extends StatelessWidget {
  const PrivacyRequestReceiptCard({
    required this.receipt,
    required this.review,
    required this.checking,
    super.key,
  });
  final PrivacyIntakeReceipt receipt;
  final PrivacyReviewStatus? review;
  final bool checking;

  (String, String) get _status => switch (review?.state) {
    PrivacyReviewState.notStarted || PrivacyReviewState.awaitingReview => (
      'Pending review',
      'Your account has not been deleted. Your request is awaiting review.',
    ),
    PrivacyReviewState.claimActive => (
      'Review in progress',
      'When last checked, a reviewer had started reviewing your request. Your account has not been deleted.',
    ),
    PrivacyReviewState.claimExpired => (
      'Waiting to resume review',
      'Your review needs to be resumed. Your account has not been deleted.',
    ),
    PrivacyReviewState.blocked => (
      'Waiting for policy approval',
      'A policy blocker has been recorded. Deletion cannot proceed until the required data retention and deletion policy is approved. Your account has not been deleted.',
    ),
    null => (
      checking ? 'Checking review status' : 'Review status unavailable',
      'Your request is recorded. Its current review status has not been verified. Your account has not been deleted.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (title, description) = _status;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: CollectStatusChip(
              label: title,
              tone:
                  review == null || review?.state == PrivacyReviewState.blocked
                  ? CollectStatusTone.warning
                  : CollectStatusTone.info,
              icon: CollectIcons.pending,
            ),
          ),
          CollectSpacing.gap16,
          Text(
            'Request recorded',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          CollectSpacing.gap8,
          Text(description),
          if (review != null) ...[
            CollectSpacing.gap12,
            Text(
              'Review status checked at ${DateFormat('yMMMd HH:mm:ss', 'en').format(review!.checkedAt)} UTC. Refresh to check again.',
            ),
          ],
          CollectSpacing.gap16,
          Text(
            'Recorded on ${DateFormat.yMMMd('en').format(receipt.acceptedAt.toLocal())}',
          ),
          CollectSpacing.gap12,
          Text(
            'Request reference',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          CollectSpacing.gap8,
          SelectableText(receipt.requestId),
        ],
      ),
    );
  }
}
