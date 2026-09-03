import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
      'Collect could not load an approved MoMo or bank destination. No payment details will be guessed.',
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
  'waitingForReceipt': 'Waiting for the receipt SMS',
  'waitingForReceiptMessage':
      'The contribution stays pending until the consented Android receipt is parsed and allocated, or an administrator reconciles an exception.',
  'momoCouldNotContinue': 'MoMo could not continue',
  'checkConnection': 'Check your connection and try again.',
  'payingTo': 'PAYING TO',
  'approveInMomo': 'Approve in MoMo',
  'howMuch': 'How much?',
  'quickAmounts': 'Quick pick',
  'reviewContribution': 'Review contribution',
  'youWillContribute': 'You will contribute',
  'privateMembershipBank':
      'Membership links your bank transfer request to the correct private group ledger.',
  'bankTransfer': 'Bank transfer',
  'reviewTransfer': 'Review transfer',
  'preparingTransfer': 'Preparing transfer',
  'openingRevolut': 'Opening Revolut',
  'openRevolut': 'Open Revolut',
  'step1BankAmount': 'Step 1 of 2 · Amount',
  'step2BankReview': 'Step 2 of 2 · Review',
  'loadingBankDetails': 'Loading bank details',
  'checkingApprovedBeneficiary': 'Checking the approved beneficiary version.',
  'bankTransfersInactive': 'Bank transfers are not active yet.',
  'bankTransfersInactiveMessage':
      'Transfers stay disabled until two administrators approve routable bank details.',
  'enterEurosAndCents': 'Enter euros and cents.',
  'enterEuroAboveZero': 'Enter a valid amount above EUR 0.00.',
  'confirmInsideBankApp': 'Confirm inside your bank app',
  'confirmInsideBankAppMessage':
      'Collect opens Revolut only. Select the saved beneficiary, enter the exact amount and reference, then review and approve the transfer in Revolut. Collect never initiates or signs it.',
  'waitingForBankConfirmation': 'Waiting for bank confirmation',
  'waitingForBankConfirmationMessage':
      'Your request remains pending. A bank notification creates evidence; the contribution is confirmed only after statement reconciliation.',
  'transferCouldNotContinue': 'Transfer could not continue',
  'bankDetailsCouldNotLoad':
      'Approved bank details could not be loaded. Try again.',
  'revolutCouldNotOpen': 'Revolut could not open on this device.',
  'copied': 'copied',
  'approvedBeneficiary': 'Approved beneficiary',
  'name': 'Name',
  'iban': 'IBAN',
  'bic': 'BIC',
  'bank': 'Bank',
  'scheme': 'Scheme',
  'sepaInstant': 'SEPA · Instant supported',
  'sepaCreditTransfer': 'SEPA credit transfer',
  'beneficiary': 'Beneficiary',
  'exactReference': 'Exact reference',
};
