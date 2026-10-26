import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../shared/models/contribution_record_copy.dart';

/// English-only product copy boundary.
///
/// Collect localizes country, currency, phone, payment-rail, and settlement
/// behavior. It intentionally does not translate the interface.
class CollectLocalizations {
  const CollectLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en')];
  static const delegate = _CollectLocalizationsDelegate();

  static CollectLocalizations of(BuildContext context) =>
      Localizations.of<CollectLocalizations>(context, CollectLocalizations) ??
      const CollectLocalizations(Locale('en'));

  String text(String key) => _english[key] ?? key;
}

class _CollectLocalizationsDelegate
    extends LocalizationsDelegate<CollectLocalizations> {
  const _CollectLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<CollectLocalizations> load(Locale locale) =>
      SynchronousFuture(const CollectLocalizations(Locale('en')));

  @override
  bool shouldReload(_CollectLocalizationsDelegate old) => false;
}

const Map<String, String> _english = {
  'contributionUnavailable': 'Contribution unavailable',
  'noActivePaymentRoute': 'This group has no active payment route.',
  'noApprovedDestination':
      'Collect could not load an approved MoMo receiver. No payment details will be guessed.',
  'backToGroup': 'Back to group',
  'momoContribution': 'MoMo contribution',
  'confirmInMomo': 'Confirm in MoMo',
  'preparingMomo': 'Preparing MoMo',
  'continueToMomo': 'Continue to MoMo',
  'openingMomo': 'Opening MoMo',
  'openMomoUssd': 'Open MoMo USSD',
  'editAmount': 'Edit amount',
  'joinRequired': 'Join required',
  'joinBeforeContributing': 'Join this group before contributing.',
  'privateMembershipMomo':
      'Membership links your MoMo receipt to the correct private group ledger.',
  'openGroup': 'Open group',
  'step1Rwf': 'Step 1 of 2 · RWF amount',
  'step2Momo': 'Step 2 of 2 · MoMo approval',
  'contributionAmount': 'Contribution amount',
  'enterWholeRwf': 'Enter whole Rwanda francs.',
  'enterAmountAboveZero': 'Enter an amount above RWF 0.',
  'airtelReceiver': 'Airtel Money',
  'mtnReceiver': 'MTN MoMo',
  'exactGroupReceiver': 'Exact group receiver',
  'approveOnlyInsideMomo': 'Approve only inside MoMo',
  'approveOnlyInsideMomoMessage':
      'Collect opens the USSD request with the exact receiver and amount. Review it and enter your PIN only in the mobile-network prompt.',
  'momoRequestOpened': ContributionRecordCopy.handoffTitle,
  'momoRequestOpenedMessage': ContributionRecordCopy.handoffMessage,
  'momoCouldNotContinue': 'MoMo could not continue',
  'checkConnection': 'Check your connection and try again.',
  'paymentDetailsChanged':
      'Payment details changed. Review the group receiver and prepare again.',
  'paymentDetailsUnavailable':
      'Payment details could not be confirmed. Prepare again when the group receiver is available.',
  'payingTo': 'PAYING TO',
  'approveInMomo': 'Approve in MoMo',
  'howMuch': 'How much?',
  'quickAmounts': 'Quick pick',
  'reviewContribution': 'Review contribution',
  'youWillContribute': 'You will contribute',
  'copied': 'copied',
  'approvedBeneficiary': 'Approved beneficiary',
  'name': 'Name',
};
