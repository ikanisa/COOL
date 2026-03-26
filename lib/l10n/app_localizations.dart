import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get navGroups;

  /// No description provided for @navMobility.
  ///
  /// In en, this message translates to:
  /// **'Mobility'**
  String get navMobility;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Cool'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Community savings group funds'**
  String get welcomeSubtitle;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get signIn;

  /// No description provided for @verifyWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Verify via WhatsApp'**
  String get verifyWhatsapp;

  /// No description provided for @verifyWhatsappSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a one-time'**
  String get verifyWhatsappSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneLabel;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'+250 7XX XXX XXX'**
  String get phoneHint;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send WhatsApp Code'**
  String get sendCode;

  /// No description provided for @enterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get enterCode;

  /// No description provided for @enterCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get enterCodeSubtitle;

  /// No description provided for @verifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify & Continue'**
  String get verifyButton;

  /// No description provided for @resendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend Code'**
  String get resendCode;

  /// No description provided for @resendCodeIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendCodeIn(Object seconds);

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code Please try'**
  String get invalidCode;

  /// No description provided for @codeSent.
  ///
  /// In en, this message translates to:
  /// **'Code sent to WhatsApp.'**
  String get codeSent;

  /// No description provided for @setupProfile.
  ///
  /// In en, this message translates to:
  /// **'Setup Profile'**
  String get setupProfile;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get nameLabel;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Amara Banda'**
  String get nameHint;

  /// No description provided for @countryLabel.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get countryLabel;

  /// No description provided for @momoNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'MOMO Number'**
  String get momoNumberLabel;

  /// No description provided for @momoNumberHint.
  ///
  /// In en, this message translates to:
  /// **'e g 0788 123'**
  String get momoNumberHint;

  /// No description provided for @totalBalance.
  ///
  /// In en, this message translates to:
  /// **'Total Balance'**
  String get totalBalance;

  /// No description provided for @rwf.
  ///
  /// In en, this message translates to:
  /// **'RWF'**
  String get rwf;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @sendMoney.
  ///
  /// In en, this message translates to:
  /// **'Send Money'**
  String get sendMoney;

  /// No description provided for @requestPay.
  ///
  /// In en, this message translates to:
  /// **'Request Pay'**
  String get requestPay;

  /// No description provided for @payViaMomo.
  ///
  /// In en, this message translates to:
  /// **'Pay via MOMO'**
  String get payViaMomo;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @noActivity.
  ///
  /// In en, this message translates to:
  /// **'No recent activity to'**
  String get noActivity;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @sendMoneyTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Money'**
  String get sendMoneyTitle;

  /// No description provided for @sendMoneyHint.
  ///
  /// In en, this message translates to:
  /// **'Transfer instantly to a'**
  String get sendMoneyHint;

  /// No description provided for @sendAction.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendAction;

  /// No description provided for @recipientLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient ID'**
  String get recipientLabel;

  /// No description provided for @recipientHint.
  ///
  /// In en, this message translates to:
  /// **'Enter member ID'**
  String get recipientHint;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (RWF)'**
  String get amountLabel;

  /// No description provided for @amountHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 5,000'**
  String get amountHint;

  /// No description provided for @confirmSend.
  ///
  /// In en, this message translates to:
  /// **'Confirm & Send'**
  String get confirmSend;

  /// No description provided for @sendSuccess.
  ///
  /// In en, this message translates to:
  /// **'Transfer initiated via MOMO.'**
  String get sendSuccess;

  /// No description provided for @myGroups.
  ///
  /// In en, this message translates to:
  /// **'My Groups'**
  String get myGroups;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get newGroup;

  /// No description provided for @createGroup.
  ///
  /// In en, this message translates to:
  /// **'Create Group'**
  String get createGroup;

  /// No description provided for @joinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join Group'**
  String get joinGroup;

  /// No description provided for @leaveGroup.
  ///
  /// In en, this message translates to:
  /// **'Leave Group'**
  String get leaveGroup;

  /// No description provided for @groupSaving.
  ///
  /// In en, this message translates to:
  /// **'Group Saving'**
  String get groupSaving;

  /// No description provided for @communityFund.
  ///
  /// In en, this message translates to:
  /// **'Community Fund'**
  String get communityFund;

  /// No description provided for @public.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get public;

  /// No description provided for @private.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get private;

  /// No description provided for @publicGroup.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicGroup;

  /// No description provided for @privateGroup.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateGroup;

  /// No description provided for @contribute.
  ///
  /// In en, this message translates to:
  /// **'Contribute'**
  String get contribute;

  /// No description provided for @contribution.
  ///
  /// In en, this message translates to:
  /// **'Contribution'**
  String get contribution;

  /// No description provided for @contributionAmount.
  ///
  /// In en, this message translates to:
  /// **'Contribution Amount'**
  String get contributionAmount;

  /// No description provided for @cycleDays.
  ///
  /// In en, this message translates to:
  /// **'Cycle (days)'**
  String get cycleDays;

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String memberCount(Object count);

  /// No description provided for @groupMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get groupMembers;

  /// No description provided for @recentContributions.
  ///
  /// In en, this message translates to:
  /// **'Recent contributions'**
  String get recentContributions;

  /// No description provided for @shareInvite.
  ///
  /// In en, this message translates to:
  /// **'Share / QR'**
  String get shareInvite;

  /// No description provided for @groupCreated.
  ///
  /// In en, this message translates to:
  /// **'Group created successfully.'**
  String get groupCreated;

  /// No description provided for @groupNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupNameLabel;

  /// No description provided for @groupNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Nyamirambo Savers'**
  String get groupNameHint;

  /// No description provided for @groupDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get groupDescriptionLabel;

  /// No description provided for @discoverGroups.
  ///
  /// In en, this message translates to:
  /// **'Discover Groups'**
  String get discoverGroups;

  /// No description provided for @noGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t joined any'**
  String get noGroupsYet;

  /// No description provided for @noPublicGroups.
  ///
  /// In en, this message translates to:
  /// **'No public groups available.'**
  String get noPublicGroups;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @basket.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get basket;

  /// No description provided for @emptyBasket.
  ///
  /// In en, this message translates to:
  /// **'Your basket is empty.'**
  String get emptyBasket;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @totalItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String totalItems(Object count);

  /// No description provided for @momoTitle.
  ///
  /// In en, this message translates to:
  /// **'MOMO Pay'**
  String get momoTitle;

  /// No description provided for @payViaUssd.
  ///
  /// In en, this message translates to:
  /// **'Pay via MOMO USSD'**
  String get payViaUssd;

  /// No description provided for @momoDialerError.
  ///
  /// In en, this message translates to:
  /// **'open the USSD failed'**
  String get momoDialerError;

  /// No description provided for @scheduleTripReturnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drivers offer discounts on'**
  String get scheduleTripReturnSubtitle;

  /// No description provided for @scheduleTripReturnFieldsLabel.
  ///
  /// In en, this message translates to:
  /// **'Return Date & Time'**
  String get scheduleTripReturnFieldsLabel;

  /// No description provided for @scheduleTripRecurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring Trip'**
  String get scheduleTripRecurringTitle;

  /// No description provided for @scheduleTripRecurringSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Daily / Weekly repeat'**
  String get scheduleTripRecurringSubtitle;

  /// No description provided for @scheduleTripRecurringDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Repeat Days'**
  String get scheduleTripRecurringDaysLabel;

  /// No description provided for @scheduleTripExpiryTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip expires automatically'**
  String get scheduleTripExpiryTitle;

  /// No description provided for @scheduleTripExpirySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Trips are removed 60'**
  String get scheduleTripExpirySubtitle;

  /// No description provided for @scheduleTripPostCta.
  ///
  /// In en, this message translates to:
  /// **'Post Trip on Board'**
  String get scheduleTripPostCta;

  /// No description provided for @scheduleTripPostedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Trip posted successfully.'**
  String get scheduleTripPostedSuccess;

  /// No description provided for @scheduleTripPostedPendingSync.
  ///
  /// In en, this message translates to:
  /// **'Trip saved offline and'**
  String get scheduleTripPostedPendingSync;

  /// No description provided for @scheduleTripPostingGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'Posting behavior'**
  String get scheduleTripPostingGuideTitle;

  /// No description provided for @scheduleTripPostingGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Make sure the trip'**
  String get scheduleTripPostingGuideSubtitle;

  /// No description provided for @scheduleTripPostingVisibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Visible to others'**
  String get scheduleTripPostingVisibilityLabel;

  /// No description provided for @scheduleTripPostingPrecisionLabel.
  ///
  /// In en, this message translates to:
  /// **'Pickup precision'**
  String get scheduleTripPostingPrecisionLabel;

  /// No description provided for @scheduleTripPostingCoordinationLabel.
  ///
  /// In en, this message translates to:
  /// **'After posting'**
  String get scheduleTripPostingCoordinationLabel;

  /// No description provided for @scheduleTripPostingOfflineLabel.
  ///
  /// In en, this message translates to:
  /// **'Offline fallback'**
  String get scheduleTripPostingOfflineLabel;

  /// No description provided for @scheduleTripPostingPassengerVisibility.
  ///
  /// In en, this message translates to:
  /// **'Drivers see your route'**
  String get scheduleTripPostingPassengerVisibility;

  /// No description provided for @scheduleTripPostingDriverVisibility.
  ///
  /// In en, this message translates to:
  /// **'Riders see your route'**
  String get scheduleTripPostingDriverVisibility;

  /// No description provided for @scheduleTripPostingPrecisionExact.
  ///
  /// In en, this message translates to:
  /// **'Exact pickup and destination'**
  String get scheduleTripPostingPrecisionExact;

  /// No description provided for @scheduleTripPostingPrecisionPartial.
  ///
  /// In en, this message translates to:
  /// **'One place pin is'**
  String get scheduleTripPostingPrecisionPartial;

  /// No description provided for @scheduleTripPostingPrecisionTextOnly.
  ///
  /// In en, this message translates to:
  /// **'Text route only Confirm'**
  String get scheduleTripPostingPrecisionTextOnly;

  /// No description provided for @scheduleTripPostingPassengerCoordination.
  ///
  /// In en, this message translates to:
  /// **'Drivers contact you after'**
  String get scheduleTripPostingPassengerCoordination;

  /// No description provided for @scheduleTripPostingDriverCoordination.
  ///
  /// In en, this message translates to:
  /// **'Riders contact you after'**
  String get scheduleTripPostingDriverCoordination;

  /// No description provided for @scheduleTripPostingOfflineBehavior.
  ///
  /// In en, this message translates to:
  /// **'If the network drops'**
  String get scheduleTripPostingOfflineBehavior;

  /// No description provided for @scheduleTripFromRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a departure point.'**
  String get scheduleTripFromRequired;

  /// No description provided for @scheduleTripToRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a destination.'**
  String get scheduleTripToRequired;

  /// No description provided for @scheduleTripRouteSameError.
  ///
  /// In en, this message translates to:
  /// **'Departure and destination must'**
  String get scheduleTripRouteSameError;

  /// No description provided for @scheduleTripReturnInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Return date and time'**
  String get scheduleTripReturnInvalidError;

  /// No description provided for @scheduleTripRecurringDaysError.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one'**
  String get scheduleTripRecurringDaysError;

  /// No description provided for @scheduleTripDepartureInPastError.
  ///
  /// In en, this message translates to:
  /// **'Departure time is in the past.'**
  String get scheduleTripDepartureInPastError;

  /// No description provided for @scheduleTripDateFieldPrefix.
  ///
  /// In en, this message translates to:
  /// **'📅'**
  String get scheduleTripDateFieldPrefix;

  /// No description provided for @scheduleTripTimeFieldPrefix.
  ///
  /// In en, this message translates to:
  /// **'🕐'**
  String get scheduleTripTimeFieldPrefix;

  /// No description provided for @driverMode.
  ///
  /// In en, this message translates to:
  /// **'Driver Mode'**
  String get driverMode;

  /// No description provided for @driverOnlineMessage.
  ///
  /// In en, this message translates to:
  /// **'Online now'**
  String get driverOnlineMessage;

  /// No description provided for @online.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @statusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get statusHealthy;

  /// No description provided for @statusWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get statusWarning;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @pendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending Review'**
  String get pendingReview;

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Pay via MOMO USSD'**
  String get subscribe;

  /// No description provided for @unlockUnlimitedTrips.
  ///
  /// In en, this message translates to:
  /// **'Unlock Unlimited Trips'**
  String get unlockUnlimitedTrips;

  /// No description provided for @tripsUsedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have used {used}'**
  String tripsUsedMessage(Object used);

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} days remaining'**
  String daysRemaining(Object count);

  /// No description provided for @addReturnTrip.
  ///
  /// In en, this message translates to:
  /// **'Add Return Trip'**
  String get addReturnTrip;

  /// No description provided for @myScheduledTrips.
  ///
  /// In en, this message translates to:
  /// **'My Scheduled Trips'**
  String get myScheduledTrips;

  /// No description provided for @noScheduledTrips.
  ///
  /// In en, this message translates to:
  /// **'No scheduled trips yet.'**
  String get noScheduledTrips;

  /// No description provided for @perMonth.
  ///
  /// In en, this message translates to:
  /// **'/month'**
  String get perMonth;

  /// No description provided for @vehicleMoto.
  ///
  /// In en, this message translates to:
  /// **'Moto'**
  String get vehicleMoto;

  /// No description provided for @vehicleCab.
  ///
  /// In en, this message translates to:
  /// **'Cab'**
  String get vehicleCab;

  /// No description provided for @vehicleAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get vehicleAny;

  /// No description provided for @weekdayMonShort.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get weekdayMonShort;

  /// No description provided for @weekdayTueShort.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get weekdayTueShort;

  /// No description provided for @weekdayWedShort.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get weekdayWedShort;

  /// No description provided for @weekdayThuShort.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get weekdayThuShort;

  /// No description provided for @weekdayFriShort.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get weekdayFriShort;

  /// No description provided for @weekdaySatShort.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get weekdaySatShort;

  /// No description provided for @weekdaySunShort.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get weekdaySunShort;

  /// No description provided for @partnersTitle.
  ///
  /// In en, this message translates to:
  /// **'Partners'**
  String get partnersTitle;

  /// No description provided for @partners.
  ///
  /// In en, this message translates to:
  /// **'Partners'**
  String get partners;

  /// No description provided for @football.
  ///
  /// In en, this message translates to:
  /// **'Football'**
  String get football;

  /// No description provided for @banks.
  ///
  /// In en, this message translates to:
  /// **'Banks'**
  String get banks;

  /// No description provided for @organizations.
  ///
  /// In en, this message translates to:
  /// **'Orgs'**
  String get organizations;

  /// No description provided for @ticketsAndShop.
  ///
  /// In en, this message translates to:
  /// **'Tickets & Shop'**
  String get ticketsAndShop;

  /// No description provided for @upcomingMatches.
  ///
  /// In en, this message translates to:
  /// **'Upcoming Matches'**
  String get upcomingMatches;

  /// No description provided for @fanRegistry.
  ///
  /// In en, this message translates to:
  /// **'Fan Registry'**
  String get fanRegistry;

  /// No description provided for @fanClubs.
  ///
  /// In en, this message translates to:
  /// **'Fan Clubs'**
  String get fanClubs;

  /// No description provided for @ticketing.
  ///
  /// In en, this message translates to:
  /// **'Ticketing'**
  String get ticketing;

  /// No description provided for @clubShop.
  ///
  /// In en, this message translates to:
  /// **'Club Shop'**
  String get clubShop;

  /// No description provided for @fansCount.
  ///
  /// In en, this message translates to:
  /// **'{count} fans'**
  String fansCount(Object count);

  /// No description provided for @clubsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} clubs'**
  String clubsCount(Object count);

  /// No description provided for @gamesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} games'**
  String gamesCount(Object count);

  /// No description provided for @fansTitle.
  ///
  /// In en, this message translates to:
  /// **'Fans'**
  String get fansTitle;

  /// No description provided for @membership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get membership;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @fanDirectory.
  ///
  /// In en, this message translates to:
  /// **'Fan Directory'**
  String get fanDirectory;

  /// No description provided for @joinClub.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get joinClub;

  /// No description provided for @joinedClub.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get joinedClub;

  /// No description provided for @leaveClub.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leaveClub;

  /// No description provided for @goldMember.
  ///
  /// In en, this message translates to:
  /// **'GOLD MEMBER'**
  String get goldMember;

  /// No description provided for @silverMember.
  ///
  /// In en, this message translates to:
  /// **'SILVER MEMBER'**
  String get silverMember;

  /// No description provided for @bronzeMember.
  ///
  /// In en, this message translates to:
  /// **'BRONZE MEMBER'**
  String get bronzeMember;

  /// No description provided for @earnedBadge.
  ///
  /// In en, this message translates to:
  /// **'Earned'**
  String get earnedBadge;

  /// No description provided for @lockedBadge.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedBadge;

  /// No description provided for @ticketingTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticketing'**
  String get ticketingTitle;

  /// No description provided for @tickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get tickets;

  /// No description provided for @myTickets.
  ///
  /// In en, this message translates to:
  /// **'My Tickets'**
  String get myTickets;

  /// No description provided for @purchasedTickets.
  ///
  /// In en, this message translates to:
  /// **'Purchased Tickets'**
  String get purchasedTickets;

  /// No description provided for @buyTicket.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get buyTicket;

  /// No description provided for @purchaseTicket.
  ///
  /// In en, this message translates to:
  /// **'Purchase Ticket'**
  String get purchaseTicket;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @seatCategory.
  ///
  /// In en, this message translates to:
  /// **'Seat Category'**
  String get seatCategory;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @vip.
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get vip;

  /// No description provided for @generalSeat.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSeat;

  /// No description provided for @vipSeat.
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get vipSeat;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @payViaMomoUssd.
  ///
  /// In en, this message translates to:
  /// **'Pay via MOMO'**
  String get payViaMomoUssd;

  /// No description provided for @whatsappConfirmation.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp confirmation will be'**
  String get whatsappConfirmation;

  /// No description provided for @viewTicket.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewTicket;

  /// No description provided for @showAtGate.
  ///
  /// In en, this message translates to:
  /// **'Show this at the'**
  String get showAtGate;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @goldDiscount.
  ///
  /// In en, this message translates to:
  /// **'Gold Members get 10'**
  String get goldDiscount;

  /// No description provided for @noTicketsYet.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get noTicketsYet;

  /// No description provided for @buyTicketsToUpcomingMatches.
  ///
  /// In en, this message translates to:
  /// **'Buy tickets to upcoming'**
  String get buyTicketsToUpcomingMatches;

  /// No description provided for @cartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String cartItemCount(Object count);

  /// No description provided for @creditScore.
  ///
  /// In en, this message translates to:
  /// **'Credit Score'**
  String get creditScore;

  /// No description provided for @coolCreditScore.
  ///
  /// In en, this message translates to:
  /// **'COOL CREDIT SCORE'**
  String get coolCreditScore;

  /// No description provided for @excellentGrade.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get excellentGrade;

  /// No description provided for @goodStanding.
  ///
  /// In en, this message translates to:
  /// **'Good Standing'**
  String get goodStanding;

  /// No description provided for @fairGrade.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get fairGrade;

  /// No description provided for @needsImprovement.
  ///
  /// In en, this message translates to:
  /// **'Needs Improvement'**
  String get needsImprovement;

  /// No description provided for @scoreFactors.
  ///
  /// In en, this message translates to:
  /// **'Score Factors'**
  String get scoreFactors;

  /// No description provided for @savingConsistency.
  ///
  /// In en, this message translates to:
  /// **'Saving Consistency'**
  String get savingConsistency;

  /// No description provided for @groupParticipation.
  ///
  /// In en, this message translates to:
  /// **'Group Participation'**
  String get groupParticipation;

  /// No description provided for @paymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment History'**
  String get paymentHistory;

  /// No description provided for @communityActivity.
  ///
  /// In en, this message translates to:
  /// **'Community Activity'**
  String get communityActivity;

  /// No description provided for @howToImprove.
  ///
  /// In en, this message translates to:
  /// **'💡 How to Improve'**
  String get howToImprove;

  /// No description provided for @improveOnTime.
  ///
  /// In en, this message translates to:
  /// **'Contribute on time every'**
  String get improveOnTime;

  /// No description provided for @improveJoinGroups.
  ///
  /// In en, this message translates to:
  /// **'Join 2+ savings groups'**
  String get improveJoinGroups;

  /// No description provided for @improveCommunityFunds.
  ///
  /// In en, this message translates to:
  /// **'Contribute to 3 community'**
  String get improveCommunityFunds;

  /// No description provided for @improveConsecutiveMonths.
  ///
  /// In en, this message translates to:
  /// **'6 consecutive months saving'**
  String get improveConsecutiveMonths;

  /// No description provided for @scoreHistory.
  ///
  /// In en, this message translates to:
  /// **'Score History'**
  String get scoreHistory;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @momoNumber.
  ///
  /// In en, this message translates to:
  /// **'MOMO Number'**
  String get momoNumber;

  /// No description provided for @momoLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked ✅'**
  String get momoLinked;

  /// No description provided for @momoNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get momoNotLinked;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @pinBiometric.
  ///
  /// In en, this message translates to:
  /// **'PIN / Biometric'**
  String get pinBiometric;

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @whatsappOtp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp OTP'**
  String get whatsappOtp;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @helpAndSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpAndSupport;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signOutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOutConfirmTitle;

  /// No description provided for @signOutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Sign out now?'**
  String get signOutConfirmMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @vehicle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicle;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @expiringInDays.
  ///
  /// In en, this message translates to:
  /// **'Expiring in {count} days'**
  String expiringInDays(Object count);

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get error;

  /// No description provided for @genericErrorText.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String genericErrorText(String error);

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get noConnection;

  /// No description provided for @offlineNotice.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline Showing cached'**
  String get offlineNotice;

  /// No description provided for @goodMorningUser.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name} 👋'**
  String goodMorningUser(Object name);

  /// No description provided for @memberIdPrefix.
  ///
  /// In en, this message translates to:
  /// **'ID:'**
  String get memberIdPrefix;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @inviteToGroup.
  ///
  /// In en, this message translates to:
  /// **'Invite to {groupName}'**
  String inviteToGroup(String groupName);

  /// No description provided for @scanQrOrShareLink.
  ///
  /// In en, this message translates to:
  /// **'Scan QR or share'**
  String get scanQrOrShareLink;

  /// No description provided for @shareViaWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Share via WhatsApp'**
  String get shareViaWhatsapp;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied!'**
  String get linkCopied;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @whatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsapp;

  /// No description provided for @topUp.
  ///
  /// In en, this message translates to:
  /// **'Top Up'**
  String get topUp;

  /// No description provided for @savingsRank.
  ///
  /// In en, this message translates to:
  /// **'Savings Rank'**
  String get savingsRank;

  /// No description provided for @officialPartner.
  ///
  /// In en, this message translates to:
  /// **'Official Partner'**
  String get officialPartner;

  /// No description provided for @bankingPartner.
  ///
  /// In en, this message translates to:
  /// **'Banking Partner'**
  String get bankingPartner;

  /// No description provided for @activeGroups.
  ///
  /// In en, this message translates to:
  /// **'Active Groups'**
  String get activeGroups;

  /// No description provided for @rwfHeld.
  ///
  /// In en, this message translates to:
  /// **'RWF Held'**
  String get rwfHeld;

  /// No description provided for @members.
  ///
  /// In en, this message translates to:
  /// **'members'**
  String get members;

  /// No description provided for @moreOrganizationsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'More organizations coming soon'**
  String get moreOrganizationsComingSoon;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @returnLabel.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnLabel;

  /// No description provided for @daily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get daily;

  /// No description provided for @expiresSoon.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get expiresSoon;

  /// No description provided for @departed.
  ///
  /// In en, this message translates to:
  /// **'departed'**
  String get departed;

  /// No description provided for @inMinutesShort.
  ///
  /// In en, this message translates to:
  /// **'in {count}min'**
  String inMinutesShort(Object count);

  /// No description provided for @inHoursShort.
  ///
  /// In en, this message translates to:
  /// **'in {count}h'**
  String inHoursShort(Object count);

  /// No description provided for @inDaysShort.
  ///
  /// In en, this message translates to:
  /// **'in {count}d'**
  String inDaysShort(Object count);

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @targetAmount.
  ///
  /// In en, this message translates to:
  /// **'Target: {amount} RWF'**
  String targetAmount(Object amount);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get seeMore;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard.'**
  String get copied;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @openAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openAction;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @supportLabel.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportLabel;

  /// No description provided for @appearanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceLabel;

  /// No description provided for @appearanceSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose how Cool looks'**
  String get appearanceSheetSubtitle;

  /// No description provided for @appearanceSystemLabel.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get appearanceSystemLabel;

  /// No description provided for @appearanceSystemDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow your phone\'s light'**
  String get appearanceSystemDescription;

  /// No description provided for @appearanceLightLabel.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLightLabel;

  /// No description provided for @appearanceLightDescription.
  ///
  /// In en, this message translates to:
  /// **'Always use the light'**
  String get appearanceLightDescription;

  /// No description provided for @appearanceDarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDarkLabel;

  /// No description provided for @appearanceDarkDescription.
  ///
  /// In en, this message translates to:
  /// **'Always use the dark'**
  String get appearanceDarkDescription;

  /// No description provided for @notificationsLabel.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsLabel;

  /// No description provided for @statementsLabel.
  ///
  /// In en, this message translates to:
  /// **'Statements'**
  String get statementsLabel;

  /// No description provided for @walletLabel.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletLabel;

  /// No description provided for @savingsLabel.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get savingsLabel;

  /// No description provided for @allTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTimeLabel;

  /// No description provided for @last30DaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30DaysLabel;

  /// No description provided for @last90DaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get last90DaysLabel;

  /// No description provided for @incomingLabel.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incomingLabel;

  /// No description provided for @outgoingLabel.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoingLabel;

  /// No description provided for @counterpartyLabel.
  ///
  /// In en, this message translates to:
  /// **'Counterparty'**
  String get counterpartyLabel;

  /// No description provided for @referenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get referenceLabel;

  /// No description provided for @detailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsLabel;

  /// No description provided for @otpUseWhatsappTitle.
  ///
  /// In en, this message translates to:
  /// **'Use your WhatsApp number'**
  String get otpUseWhatsappTitle;

  /// No description provided for @otpUseWhatsappSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will send a'**
  String get otpUseWhatsappSubtitle;

  /// No description provided for @otpPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get otpPhoneRequired;

  /// No description provided for @otpContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get otpContinue;

  /// No description provided for @otpGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong Please'**
  String get otpGenericError;

  /// No description provided for @openLinkError.
  ///
  /// In en, this message translates to:
  /// **'Open link failed'**
  String get openLinkError;

  /// No description provided for @otpLegalPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing you accept'**
  String get otpLegalPrefix;

  /// No description provided for @otpLegalAnd.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get otpLegalAnd;

  /// No description provided for @termsLabel.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get termsLabel;

  /// No description provided for @privacyPolicyLabel.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyLabel;

  /// No description provided for @homeMissionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get homeMissionsTitle;

  /// No description provided for @homeMonthlyNet.
  ///
  /// In en, this message translates to:
  /// **'Monthly net'**
  String get homeMonthlyNet;

  /// No description provided for @homeActionPay.
  ///
  /// In en, this message translates to:
  /// **'MoMo'**
  String get homeActionPay;

  /// No description provided for @homeActionTrips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get homeActionTrips;

  /// No description provided for @homeFallbackGroupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Savings and invites'**
  String get homeFallbackGroupsSubtitle;

  /// No description provided for @homeFallbackPaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive, send, and statements'**
  String get homeFallbackPaySubtitle;

  /// No description provided for @homeFallbackPartnersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Banks and clubs'**
  String get homeFallbackPartnersSubtitle;

  /// No description provided for @homeFallbackTripsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ride or drive'**
  String get homeFallbackTripsSubtitle;

  /// No description provided for @homePriorityLabel.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get homePriorityLabel;

  /// No description provided for @homePriorityGroupsTitle.
  ///
  /// In en, this message translates to:
  /// **'Start with a group'**
  String get homePriorityGroupsTitle;

  /// No description provided for @homePriorityGroupsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create or join a'**
  String get homePriorityGroupsSubtitle;

  /// No description provided for @homePriorityMomoTitle.
  ///
  /// In en, this message translates to:
  /// **'Open Mobile Money'**
  String get homePriorityMomoTitle;

  /// No description provided for @homePriorityMomoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send request or receive'**
  String get homePriorityMomoSubtitle;

  /// No description provided for @homePriorityStatementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Review statements'**
  String get homePriorityStatementsTitle;

  /// No description provided for @homePriorityStatementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your monthly trend is'**
  String get homePriorityStatementsSubtitle;

  /// No description provided for @homePriorityMomentumTitle.
  ///
  /// In en, this message translates to:
  /// **'Keep contributions moving'**
  String get homePriorityMomentumTitle;

  /// No description provided for @homePriorityMomentumSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You have active group'**
  String get homePriorityMomentumSubtitle;

  /// No description provided for @homeActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String homeActiveCount(Object count);

  /// No description provided for @homeNoActivityTitle.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get homeNoActivityTitle;

  /// No description provided for @homeNoActivityMessage.
  ///
  /// In en, this message translates to:
  /// **'Activity will appear here.'**
  String get homeNoActivityMessage;

  /// No description provided for @homeLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this section'**
  String get homeLoadErrorTitle;

  /// No description provided for @homeLoadErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get homeLoadErrorMessage;

  /// No description provided for @profileMobileMoney.
  ///
  /// In en, this message translates to:
  /// **'Mobile Money'**
  String get profileMobileMoney;

  /// No description provided for @profileCreditScore.
  ///
  /// In en, this message translates to:
  /// **'Credit score'**
  String get profileCreditScore;

  /// No description provided for @profileNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get profileNotLinked;

  /// No description provided for @profileCreditReadiness.
  ///
  /// In en, this message translates to:
  /// **'Credit readiness'**
  String get profileCreditReadiness;

  /// No description provided for @profileDriverTools.
  ///
  /// In en, this message translates to:
  /// **'Driver tools'**
  String get profileDriverTools;

  /// No description provided for @profileCoolStatus.
  ///
  /// In en, this message translates to:
  /// **'COOL status'**
  String get profileCoolStatus;

  /// No description provided for @profileAdminPanel.
  ///
  /// In en, this message translates to:
  /// **'Admin panel'**
  String get profileAdminPanel;

  /// No description provided for @officialNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Official name'**
  String get officialNameLabel;

  /// No description provided for @identityLabel.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get identityLabel;

  /// No description provided for @moneySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get moneySectionTitle;

  /// No description provided for @preferencesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferencesSectionTitle;

  /// No description provided for @moreToolsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'More tools'**
  String get moreToolsSectionTitle;

  /// No description provided for @profileMoreToolsShowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show extra actions and'**
  String get profileMoreToolsShowSubtitle;

  /// No description provided for @profileMoreToolsHideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide QR driver and'**
  String get profileMoreToolsHideSubtitle;

  /// No description provided for @vehicleLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicleLabel;

  /// No description provided for @accountActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Account actions'**
  String get accountActionsTitle;

  /// No description provided for @signOutAction.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOutAction;

  /// No description provided for @deleteAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountAction;

  /// No description provided for @deleteAccountQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteAccountQuestion;

  /// No description provided for @deleteAccountMessage.
  ///
  /// In en, this message translates to:
  /// **'This permanently removes your'**
  String get deleteAccountMessage;

  /// No description provided for @signOutMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to verify'**
  String get signOutMessage;

  /// No description provided for @completeProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get completeProfileTitle;

  /// No description provided for @completeProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Finish setup to unlock'**
  String get completeProfileSubtitle;

  /// No description provided for @profileSavingMomoInfo.
  ///
  /// In en, this message translates to:
  /// **'Saving MoMo info...'**
  String get profileSavingMomoInfo;

  /// No description provided for @profileDeletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account...'**
  String get profileDeletingAccount;

  /// No description provided for @profileMomoUpdated.
  ///
  /// In en, this message translates to:
  /// **'MoMo info updated'**
  String get profileMomoUpdated;

  /// No description provided for @profileMomoUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update MoMo'**
  String get profileMomoUpdateFailed;

  /// No description provided for @profileSupportOpenError.
  ///
  /// In en, this message translates to:
  /// **'Open WhatsApp Please failed'**
  String get profileSupportOpenError;

  /// No description provided for @profileSupportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Support is unavailable right'**
  String get profileSupportUnavailable;

  /// No description provided for @profileMomoQrTitle.
  ///
  /// In en, this message translates to:
  /// **'MoMo QR'**
  String get profileMomoQrTitle;

  /// No description provided for @profileMomoQrSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan to pay {number}'**
  String profileMomoQrSubtitle(Object number);

  /// No description provided for @profileEditMomoInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit MoMo Info'**
  String get profileEditMomoInfo;

  /// No description provided for @profileEditMomoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This number will be'**
  String get profileEditMomoSubtitle;

  /// No description provided for @profileMomoCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'MOMO CODE (OPTIONAL)'**
  String get profileMomoCodeOptional;

  /// No description provided for @kycNeedsUpdate.
  ///
  /// In en, this message translates to:
  /// **'Needs update'**
  String get kycNeedsUpdate;

  /// No description provided for @kycUnverified.
  ///
  /// In en, this message translates to:
  /// **'Unverified'**
  String get kycUnverified;

  /// No description provided for @userFallbackName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userFallbackName;

  /// No description provided for @notSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetLabel;

  /// No description provided for @momoStatementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statements & Ledger'**
  String get momoStatementsTitle;

  /// No description provided for @momoRefreshStatements.
  ///
  /// In en, this message translates to:
  /// **'Refresh statements'**
  String get momoRefreshStatements;

  /// No description provided for @statementOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Statement overview'**
  String get statementOverviewTitle;

  /// No description provided for @walletEntriesMetric.
  ///
  /// In en, this message translates to:
  /// **'Wallet entries'**
  String get walletEntriesMetric;

  /// No description provided for @savingsEntriesMetric.
  ///
  /// In en, this message translates to:
  /// **'Savings entries'**
  String get savingsEntriesMetric;

  /// No description provided for @walletEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No wallet entries yet'**
  String get walletEmptyTitle;

  /// No description provided for @walletEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Wallet activity will appear'**
  String get walletEmptyMessage;

  /// No description provided for @walletLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet ledger'**
  String get walletLedgerTitle;

  /// No description provided for @walletLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{shown}/{total} shown'**
  String walletLedgerSubtitle(Object shown, Object total);

  /// No description provided for @savingsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No savings entries yet'**
  String get savingsEmptyTitle;

  /// No description provided for @savingsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Savings contributions will appear'**
  String get savingsEmptyMessage;

  /// No description provided for @savingsStatementTitle.
  ///
  /// In en, this message translates to:
  /// **'Savings statement'**
  String get savingsStatementTitle;

  /// No description provided for @savingsStatementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{shown}/{total} shown'**
  String savingsStatementSubtitle(Object shown, Object total);

  /// No description provided for @coolMemberFallback.
  ///
  /// In en, this message translates to:
  /// **'COOL member'**
  String get coolMemberFallback;

  /// No description provided for @momoStatementsPeriodDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get momoStatementsPeriodDay;

  /// No description provided for @momoStatementsPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get momoStatementsPeriodWeek;

  /// No description provided for @momoStatementsPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get momoStatementsPeriodMonth;

  /// No description provided for @momoStatementsPeriodCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get momoStatementsPeriodCustom;

  /// No description provided for @momoStatementsPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get momoStatementsPeriodAll;

  /// No description provided for @momoStatementsSortNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get momoStatementsSortNewestFirst;

  /// No description provided for @momoStatementsSortOldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get momoStatementsSortOldestFirst;

  /// No description provided for @momoStatementsSortAmountHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Amount: high → low'**
  String get momoStatementsSortAmountHighToLow;

  /// No description provided for @momoStatementsSortAmountLowToHigh.
  ///
  /// In en, this message translates to:
  /// **'Amount: low → high'**
  String get momoStatementsSortAmountLowToHigh;

  /// No description provided for @momoStatementsSortNameAz.
  ///
  /// In en, this message translates to:
  /// **'Name: A → Z'**
  String get momoStatementsSortNameAz;

  /// No description provided for @momoStatementsSortNameZa.
  ///
  /// In en, this message translates to:
  /// **'Name: Z → A'**
  String get momoStatementsSortNameZa;

  /// No description provided for @momoStatementsWalletFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching wallet entries'**
  String get momoStatementsWalletFilteredEmptyTitle;

  /// No description provided for @momoStatementsWalletFilteredEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters'**
  String get momoStatementsWalletFilteredEmptyMessage;

  /// No description provided for @momoStatementsSavingsFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching savings entries'**
  String get momoStatementsSavingsFilteredEmptyTitle;

  /// No description provided for @momoStatementsSavingsFilteredEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters'**
  String get momoStatementsSavingsFilteredEmptyMessage;

  /// No description provided for @fansScreenUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Fan Hub Moved'**
  String get fansScreenUnavailableTitle;

  /// No description provided for @fansScreenHeadline.
  ///
  /// In en, this message translates to:
  /// **'Fan Hub'**
  String get fansScreenHeadline;

  /// No description provided for @fansScreenBody.
  ///
  /// In en, this message translates to:
  /// **'Fan features for {clubName}'**
  String fansScreenBody(Object clubName);

  /// No description provided for @fansScreenMembershipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Membership features live inside'**
  String get fansScreenMembershipUnavailable;

  /// No description provided for @fansScreenClubsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Fan clubs are now'**
  String get fansScreenClubsUnavailable;

  /// No description provided for @fansScreenRayonDedicatedHub.
  ///
  /// In en, this message translates to:
  /// **'Rayon Sports has a'**
  String get fansScreenRayonDedicatedHub;

  /// No description provided for @fansScreenRouteKeptReachable.
  ///
  /// In en, this message translates to:
  /// **'Legacy route'**
  String get fansScreenRouteKeptReachable;

  /// No description provided for @fansScreenBackToPartners.
  ///
  /// In en, this message translates to:
  /// **'Back to Partners'**
  String get fansScreenBackToPartners;

  /// No description provided for @fansScreenOpenRayon.
  ///
  /// In en, this message translates to:
  /// **'Open Rayon Sports'**
  String get fansScreenOpenRayon;

  /// No description provided for @ticketWalletInvalidLink.
  ///
  /// In en, this message translates to:
  /// **'Invalid Google Wallet link.'**
  String get ticketWalletInvalidLink;

  /// No description provided for @ticketWalletUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Google Wallet is not'**
  String get ticketWalletUnavailable;

  /// No description provided for @ticketWalletOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Open Google Wallet failed'**
  String get ticketWalletOpenFailed;

  /// No description provided for @ticketConfirmationScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get ticketConfirmationScreenTitle;

  /// No description provided for @ticketConfirmationNotFound.
  ///
  /// In en, this message translates to:
  /// **'Ticket not found.'**
  String get ticketConfirmationNotFound;

  /// No description provided for @ticketAddToGoogleWallet.
  ///
  /// In en, this message translates to:
  /// **'Add to Google Wallet'**
  String get ticketAddToGoogleWallet;

  /// No description provided for @ticketBackToTickets.
  ///
  /// In en, this message translates to:
  /// **'Back to Tickets'**
  String get ticketBackToTickets;

  /// No description provided for @ticketShareMatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Match'**
  String get ticketShareMatchTitle;

  /// No description provided for @ticketShareMatchText.
  ///
  /// In en, this message translates to:
  /// **'Check out {matchTitle} on!'**
  String ticketShareMatchText(Object matchTitle);

  /// No description provided for @ticketStatusPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Pending'**
  String get ticketStatusPendingTitle;

  /// No description provided for @ticketStatusPendingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Waiting for MoMo confirmation.'**
  String get ticketStatusPendingSubtitle;

  /// No description provided for @ticketStatusPendingNote.
  ///
  /// In en, this message translates to:
  /// **'Ticket reserved'**
  String get ticketStatusPendingNote;

  /// No description provided for @ticketStatusValidTitle.
  ///
  /// In en, this message translates to:
  /// **'Valid Ticket'**
  String get ticketStatusValidTitle;

  /// No description provided for @ticketStatusValidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show this at the'**
  String get ticketStatusValidSubtitle;

  /// No description provided for @ticketStatusValidNote.
  ///
  /// In en, this message translates to:
  /// **'Present the QR code'**
  String get ticketStatusValidNote;

  /// No description provided for @ticketStatusUsedTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Used'**
  String get ticketStatusUsedTitle;

  /// No description provided for @ticketStatusUsedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket already scanned'**
  String get ticketStatusUsedSubtitle;

  /// No description provided for @ticketStatusUsedNote.
  ///
  /// In en, this message translates to:
  /// **'Ticket already used'**
  String get ticketStatusUsedNote;

  /// No description provided for @ticketStatusCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Cancelled'**
  String get ticketStatusCancelledTitle;

  /// No description provided for @ticketStatusCancelledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket invalid'**
  String get ticketStatusCancelledSubtitle;

  /// No description provided for @ticketStatusCancelledNote.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get ticketStatusCancelledNote;

  /// No description provided for @partnersHomeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Partners Home'**
  String get partnersHomeTooltip;

  /// No description provided for @partnersServicesTab.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get partnersServicesTab;

  /// No description provided for @partnersRayonWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Rayon Sports!'**
  String get partnersRayonWelcomeTitle;

  /// No description provided for @partnersRayonWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your fan membership has'**
  String get partnersRayonWelcomeSubtitle;

  /// No description provided for @partnersOpenRayonSports.
  ///
  /// In en, this message translates to:
  /// **'Open Rayon Sports'**
  String get partnersOpenRayonSports;

  /// No description provided for @partnersMembershipPerkRegistryAccess.
  ///
  /// In en, this message translates to:
  /// **'Fan registry access'**
  String get partnersMembershipPerkRegistryAccess;

  /// No description provided for @partnersMembershipPerkClubUpdates.
  ///
  /// In en, this message translates to:
  /// **'Club updates'**
  String get partnersMembershipPerkClubUpdates;

  /// No description provided for @partnersMembershipPerkMemberQueue.
  ///
  /// In en, this message translates to:
  /// **'Member queue priority'**
  String get partnersMembershipPerkMemberQueue;

  /// No description provided for @partnersMembershipPerkPriorityTickets.
  ///
  /// In en, this message translates to:
  /// **'Priority ticket access'**
  String get partnersMembershipPerkPriorityTickets;

  /// No description provided for @partnersMembershipPerkShopDiscount.
  ///
  /// In en, this message translates to:
  /// **'Shop discount'**
  String get partnersMembershipPerkShopDiscount;

  /// No description provided for @partnersMembershipPerkVipQueue.
  ///
  /// In en, this message translates to:
  /// **'VIP queue access'**
  String get partnersMembershipPerkVipQueue;

  /// No description provided for @partnersMembershipPerkVipAccess.
  ///
  /// In en, this message translates to:
  /// **'VIP event access'**
  String get partnersMembershipPerkVipAccess;

  /// No description provided for @partnersMembershipPerkExclusiveEvents.
  ///
  /// In en, this message translates to:
  /// **'Exclusive events'**
  String get partnersMembershipPerkExclusiveEvents;

  /// No description provided for @partnersNoFootballPartners.
  ///
  /// In en, this message translates to:
  /// **'No football partners yet'**
  String get partnersNoFootballPartners;

  /// No description provided for @partnersComingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'{partnerName} is coming soon!'**
  String partnersComingSoonMessage(Object partnerName);

  /// No description provided for @partnersRayonHubBadge.
  ///
  /// In en, this message translates to:
  /// **'Official Fan Hub'**
  String get partnersRayonHubBadge;

  /// No description provided for @partnersGamesMetricLabel.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get partnersGamesMetricLabel;

  /// No description provided for @partnersLoadingMessage.
  ///
  /// In en, this message translates to:
  /// **'Loading partners…'**
  String get partnersLoadingMessage;

  /// No description provided for @partnersNoFinancePartners.
  ///
  /// In en, this message translates to:
  /// **'No finance partners yet'**
  String get partnersNoFinancePartners;

  /// No description provided for @partnersFinancePrepTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial Readiness'**
  String get partnersFinancePrepTitle;

  /// No description provided for @partnersFinancePrepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your credit readiness'**
  String get partnersFinancePrepSubtitle;

  /// No description provided for @partnersReadinessChecklistCta.
  ///
  /// In en, this message translates to:
  /// **'Credit Readiness Checklist'**
  String get partnersReadinessChecklistCta;

  /// No description provided for @partnersWhatsappMessage.
  ///
  /// In en, this message translates to:
  /// **'Hi I\'d like to'**
  String get partnersWhatsappMessage;

  /// No description provided for @partnersNoServicePartners.
  ///
  /// In en, this message translates to:
  /// **'No service partners yet'**
  String get partnersNoServicePartners;

  /// No description provided for @partnersInsurancePartnerBadge.
  ///
  /// In en, this message translates to:
  /// **'Insurance Partner'**
  String get partnersInsurancePartnerBadge;

  /// No description provided for @partnersProfessionalServicesBadge.
  ///
  /// In en, this message translates to:
  /// **'Professional Services'**
  String get partnersProfessionalServicesBadge;

  /// No description provided for @partnersServicePartnerBadge.
  ///
  /// In en, this message translates to:
  /// **'Service Partner'**
  String get partnersServicePartnerBadge;

  /// No description provided for @partnersLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Load partners failed'**
  String get partnersLoadErrorTitle;

  /// No description provided for @partnersEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Partners will appear here'**
  String get partnersEmptyMessage;

  /// No description provided for @partnersClubShopSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Official merchandise'**
  String get partnersClubShopSubtitle;

  /// No description provided for @partnersFootballTab.
  ///
  /// In en, this message translates to:
  /// **'Football'**
  String get partnersFootballTab;

  /// No description provided for @partnersFinanceTab.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get partnersFinanceTab;

  /// No description provided for @partnersFeaturesTitle.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get partnersFeaturesTitle;

  /// No description provided for @momoNfcInvalidRequest.
  ///
  /// In en, this message translates to:
  /// **'Invalid NFC payment request.'**
  String get momoNfcInvalidRequest;

  /// No description provided for @momoLaunchingUssd.
  ///
  /// In en, this message translates to:
  /// **'Launching USSD…'**
  String get momoLaunchingUssd;

  /// No description provided for @momoNfcLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'NFC launch failed Please'**
  String get momoNfcLaunchFailed;

  /// No description provided for @momoScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobile Money'**
  String get momoScreenTitle;

  /// No description provided for @momoNfcLaunchingOverlay.
  ///
  /// In en, this message translates to:
  /// **'Launching MoMo…'**
  String get momoNfcLaunchingOverlay;

  /// No description provided for @momoSendValidationError.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid'**
  String get momoSendValidationError;

  /// No description provided for @momoSendLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Launch MoMo payment failed'**
  String get momoSendLaunchFailed;

  /// No description provided for @momoFromNumber.
  ///
  /// In en, this message translates to:
  /// **'From {number}'**
  String momoFromNumber(Object number);

  /// No description provided for @momoRoutePhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get momoRoutePhoneLabel;

  /// No description provided for @momoRouteCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'MoMo Code'**
  String get momoRouteCodeLabel;

  /// No description provided for @momoRecipientCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient MoMo Code'**
  String get momoRecipientCodeLabel;

  /// No description provided for @momoRecipientPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient Phone'**
  String get momoRecipientPhoneLabel;

  /// No description provided for @momoAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String momoAmountLabel(Object currency);

  /// No description provided for @momoSendCompletesViaUssd.
  ///
  /// In en, this message translates to:
  /// **'Completes via USSD on'**
  String get momoSendCompletesViaUssd;

  /// No description provided for @momoContinueToUssd.
  ///
  /// In en, this message translates to:
  /// **'Continue to USSD'**
  String get momoContinueToUssd;

  /// No description provided for @momoTrustCardTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you pay'**
  String get momoTrustCardTitle;

  /// No description provided for @momoTrustCardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'COOL opens the network'**
  String get momoTrustCardSubtitle;

  /// No description provided for @momoTrustFeesTitle.
  ///
  /// In en, this message translates to:
  /// **'Fees show before confirmation'**
  String get momoTrustFeesTitle;

  /// No description provided for @momoTrustFeesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The USSD prompt displays'**
  String get momoTrustFeesSubtitle;

  /// No description provided for @momoTrustApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'You approve on your'**
  String get momoTrustApprovalTitle;

  /// No description provided for @momoTrustApprovalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'COOL never completes the'**
  String get momoTrustApprovalSubtitle;

  /// No description provided for @momoTrustReceiptTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipts land in statements'**
  String get momoTrustReceiptTitle;

  /// No description provided for @momoTrustReceiptSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Matching Mobile Money SMS'**
  String get momoTrustReceiptSubtitle;

  /// No description provided for @momoReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review before USSD'**
  String get momoReviewTitle;

  /// No description provided for @momoReviewRecipientLabel.
  ///
  /// In en, this message translates to:
  /// **'Recipient'**
  String get momoReviewRecipientLabel;

  /// No description provided for @momoReviewAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get momoReviewAmountLabel;

  /// No description provided for @momoReviewRouteLabel.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get momoReviewRouteLabel;

  /// No description provided for @momoReviewFromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get momoReviewFromLabel;

  /// No description provided for @momoReviewMissingRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add a recipient'**
  String get momoReviewMissingRecipient;

  /// No description provided for @momoReviewMissingAmount.
  ///
  /// In en, this message translates to:
  /// **'Add amount'**
  String get momoReviewMissingAmount;

  /// No description provided for @momoWhatHappensNextTitle.
  ///
  /// In en, this message translates to:
  /// **'What happens next'**
  String get momoWhatHappensNextTitle;

  /// No description provided for @momoWhatHappensNextOpen.
  ///
  /// In en, this message translates to:
  /// **'COOL opens the {countryName}'**
  String momoWhatHappensNextOpen(Object countryName);

  /// No description provided for @momoWhatHappensNextConfirm.
  ///
  /// In en, this message translates to:
  /// **'You confirm the amount'**
  String get momoWhatHappensNextConfirm;

  /// No description provided for @momoWhatHappensNextReceipt.
  ///
  /// In en, this message translates to:
  /// **'A matching SMS confirmation'**
  String get momoWhatHappensNextReceipt;

  /// No description provided for @momoConfirmSendLabel.
  ///
  /// In en, this message translates to:
  /// **'Send Money'**
  String get momoConfirmSendLabel;

  /// No description provided for @momoStatementsPayerLabel.
  ///
  /// In en, this message translates to:
  /// **'Payer'**
  String get momoStatementsPayerLabel;

  /// No description provided for @momoStatementsAllPayers.
  ///
  /// In en, this message translates to:
  /// **'All payers'**
  String get momoStatementsAllPayers;

  /// No description provided for @momoStatementsAllGroups.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get momoStatementsAllGroups;

  /// No description provided for @momoStatementsSelectCustomPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select custom period'**
  String get momoStatementsSelectCustomPeriod;

  /// No description provided for @momoStatementsNothingToDownload.
  ///
  /// In en, this message translates to:
  /// **'Nothing to download yet.'**
  String get momoStatementsNothingToDownload;

  /// No description provided for @momoStatementsSavedFile.
  ///
  /// In en, this message translates to:
  /// **'Saved {fileName}'**
  String momoStatementsSavedFile(Object fileName);

  /// No description provided for @momoStatementsDownloadedFile.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {fileName}'**
  String momoStatementsDownloadedFile(Object fileName);

  /// No description provided for @momoStatementsDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Statement download failed.'**
  String get momoStatementsDownloadFailed;

  /// No description provided for @momoStatementsFilterSummaryPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period: {period}'**
  String momoStatementsFilterSummaryPeriod(Object period);

  /// No description provided for @momoStatementsFilterSummaryParty.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String momoStatementsFilterSummaryParty(Object label, Object value);

  /// No description provided for @momoStatementsFilterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filters & exports'**
  String get momoStatementsFilterTitle;

  /// No description provided for @momoStatementsSortByLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get momoStatementsSortByLabel;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetAction;

  /// No description provided for @momoStatementsPreparingLabel.
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get momoStatementsPreparingLabel;

  /// No description provided for @momoStatementsPdfLabel.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get momoStatementsPdfLabel;

  /// No description provided for @momoStatementsExcelLabel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get momoStatementsExcelLabel;

  /// No description provided for @groupsTabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get groupsTabAll;

  /// No description provided for @groupsTabSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get groupsTabSaving;

  /// No description provided for @groupsTabCommunity.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get groupsTabCommunity;

  /// No description provided for @groupsTabPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get groupsTabPublic;

  /// No description provided for @groupsTabPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get groupsTabPrivate;

  /// No description provided for @groupsShareText.
  ///
  /// In en, this message translates to:
  /// **'Join {groupName} on Cool'**
  String groupsShareText(Object groupName);

  /// No description provided for @groupsCreateNewTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a New Group'**
  String get groupsCreateNewTitle;

  /// No description provided for @groupsCreateNewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Saving or Community'**
  String get groupsCreateNewSubtitle;

  /// No description provided for @groupsEmptyPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'No public groups found'**
  String get groupsEmptyPublicTitle;

  /// No description provided for @groupsEmptyPublicMessage.
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get groupsEmptyPublicMessage;

  /// No description provided for @groupsEmptyPrivateMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a group or'**
  String get groupsEmptyPrivateMessage;

  /// No description provided for @groupsBankCustodianMeta.
  ///
  /// In en, this message translates to:
  /// **'Bank custodian · {partnerName}'**
  String groupsBankCustodianMeta(Object partnerName);

  /// No description provided for @groupsMomoRouteMeta.
  ///
  /// In en, this message translates to:
  /// **'MoMo route · {number}'**
  String groupsMomoRouteMeta(Object number);

  /// No description provided for @groupsSavingGroupMeta.
  ///
  /// In en, this message translates to:
  /// **'Saving group'**
  String get groupsSavingGroupMeta;

  /// No description provided for @groupsCommunityFundMeta.
  ///
  /// In en, this message translates to:
  /// **'Community fund'**
  String get groupsCommunityFundMeta;

  /// No description provided for @groupsRaisedLabel.
  ///
  /// In en, this message translates to:
  /// **'raised'**
  String get groupsRaisedLabel;

  /// No description provided for @groupsShareAction.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get groupsShareAction;

  /// No description provided for @groupsLoadErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get groupsLoadErrorTitle;

  /// No description provided for @profileTierBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get profileTierBlue;

  /// No description provided for @profileTierSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get profileTierSilver;

  /// No description provided for @profileTierGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get profileTierGold;

  /// No description provided for @profileTierPlatinum.
  ///
  /// In en, this message translates to:
  /// **'Platinum'**
  String get profileTierPlatinum;

  /// No description provided for @profileSavingIdentity.
  ///
  /// In en, this message translates to:
  /// **'Saving identity details...'**
  String get profileSavingIdentity;

  /// No description provided for @profileIdentityUpdated.
  ///
  /// In en, this message translates to:
  /// **'Identity details updated'**
  String get profileIdentityUpdated;

  /// No description provided for @profileIdentityUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update identity'**
  String get profileIdentityUpdateFailed;

  /// No description provided for @profileAppAccess.
  ///
  /// In en, this message translates to:
  /// **'App access'**
  String get profileAppAccess;

  /// No description provided for @profileManageAction.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get profileManageAction;

  /// No description provided for @profileCoolStatusValue.
  ///
  /// In en, this message translates to:
  /// **'{tier} · {points} Tokens'**
  String profileCoolStatusValue(Object points, Object tier);

  /// No description provided for @profileUserIdLabel.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get profileUserIdLabel;

  /// No description provided for @profileWalletLabel.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get profileWalletLabel;

  /// No description provided for @profileSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile setup'**
  String get profileSetupTitle;

  /// No description provided for @profilePublicProfileLabel.
  ///
  /// In en, this message translates to:
  /// **'Public profile'**
  String get profilePublicProfileLabel;

  /// No description provided for @profileOfficialIdentityLabel.
  ///
  /// In en, this message translates to:
  /// **'Official identity'**
  String get profileOfficialIdentityLabel;

  /// No description provided for @profileMomoCodeNotSet.
  ///
  /// In en, this message translates to:
  /// **'MoMo code not set'**
  String get profileMomoCodeNotSet;

  /// No description provided for @momoSendMoneyOpensUssd.
  ///
  /// In en, this message translates to:
  /// **'Open {countryName} MoMo USSD'**
  String momoSendMoneyOpensUssd(Object countryName);

  /// No description provided for @momoMoreToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Statements QR and NFC'**
  String get momoMoreToolsSubtitle;

  /// No description provided for @momoStatementsToolSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review wallet and savings'**
  String get momoStatementsToolSubtitle;

  /// No description provided for @momoNfcToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'NFC tools'**
  String get momoNfcToolsTitle;

  /// No description provided for @momoNfcToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap-to-pay and share route'**
  String get momoNfcToolsSubtitle;

  /// No description provided for @basketScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get basketScreenTitle;

  /// No description provided for @basketScreenHeadline.
  ///
  /// In en, this message translates to:
  /// **'Basket is not live'**
  String get basketScreenHeadline;

  /// No description provided for @basketScreenBody.
  ///
  /// In en, this message translates to:
  /// **'Legacy route'**
  String get basketScreenBody;

  /// No description provided for @basketScreenCardBody.
  ///
  /// In en, this message translates to:
  /// **'Basket products are paused'**
  String get basketScreenCardBody;

  /// No description provided for @basketScreenExpectationBalances.
  ///
  /// In en, this message translates to:
  /// **'No live basket balances'**
  String get basketScreenExpectationBalances;

  /// No description provided for @basketScreenExpectationCreation.
  ///
  /// In en, this message translates to:
  /// **'New basket creation is'**
  String get basketScreenExpectationCreation;

  /// No description provided for @basketScreenExpectationLinks.
  ///
  /// In en, this message translates to:
  /// **'Existing deep links still'**
  String get basketScreenExpectationLinks;

  /// No description provided for @basketScreenBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back Home'**
  String get basketScreenBackHome;

  /// No description provided for @activeMissions.
  ///
  /// In en, this message translates to:
  /// **'Active Missions'**
  String get activeMissions;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @scanThisQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code to join Cool'**
  String get scanThisQrCode;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// No description provided for @qrCode.
  ///
  /// In en, this message translates to:
  /// **'QR Code'**
  String get qrCode;

  /// No description provided for @sendInvite.
  ///
  /// In en, this message translates to:
  /// **'Send Invite'**
  String get sendInvite;

  /// No description provided for @friendJoins.
  ///
  /// In en, this message translates to:
  /// **'Friend Joins'**
  String get friendJoins;

  /// No description provided for @earnTokens.
  ///
  /// In en, this message translates to:
  /// **'Earn Tokens'**
  String get earnTokens;

  /// No description provided for @waysToEarn.
  ///
  /// In en, this message translates to:
  /// **'Ways to Earn'**
  String get waysToEarn;

  /// No description provided for @rewardsMarketplace.
  ///
  /// In en, this message translates to:
  /// **'Rewards Marketplace'**
  String get rewardsMarketplace;

  /// No description provided for @topEarners.
  ///
  /// In en, this message translates to:
  /// **'Top Earners'**
  String get topEarners;

  /// No description provided for @currentStreak.
  ///
  /// In en, this message translates to:
  /// **'Current Streak'**
  String get currentStreak;

  /// No description provided for @bestStreak.
  ///
  /// In en, this message translates to:
  /// **'Best Streak'**
  String get bestStreak;

  /// No description provided for @grace.
  ///
  /// In en, this message translates to:
  /// **'Grace'**
  String get grace;

  /// No description provided for @yourGroupIsClose.
  ///
  /// In en, this message translates to:
  /// **'Your group is close!'**
  String get yourGroupIsClose;

  /// No description provided for @attendAMatch.
  ///
  /// In en, this message translates to:
  /// **'Attend a match'**
  String get attendAMatch;

  /// No description provided for @earn10TokensFor.
  ///
  /// In en, this message translates to:
  /// **'Earn 10 Tokens for attending'**
  String get earn10TokensFor;

  /// No description provided for @oneMoreTrip.
  ///
  /// In en, this message translates to:
  /// **'One more trip!'**
  String get oneMoreTrip;

  /// No description provided for @postYourRoute.
  ///
  /// In en, this message translates to:
  /// **'Post your route'**
  String get postYourRoute;

  /// No description provided for @helpOthersFindA.
  ///
  /// In en, this message translates to:
  /// **'Help others find a ride'**
  String get helpOthersFindA;

  /// No description provided for @confirmTransaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm transaction'**
  String get confirmTransaction;

  /// No description provided for @joinASavingsGroup.
  ///
  /// In en, this message translates to:
  /// **'Join a savings group'**
  String get joinASavingsGroup;

  /// No description provided for @earn10TokensPer.
  ///
  /// In en, this message translates to:
  /// **'Earn 10 Tokens per contribution'**
  String get earn10TokensPer;

  /// No description provided for @becomeARayonFan.
  ///
  /// In en, this message translates to:
  /// **'Become a Rayon fan'**
  String get becomeARayonFan;

  /// No description provided for @joinTheClubAnd.
  ///
  /// In en, this message translates to:
  /// **'Join the club and earn rewards'**
  String get joinTheClubAnd;

  /// No description provided for @streakAtRisk.
  ///
  /// In en, this message translates to:
  /// **'Streak at risk!'**
  String get streakAtRisk;

  /// No description provided for @doAnActionToday.
  ///
  /// In en, this message translates to:
  /// **'Do an action today'**
  String get doAnActionToday;

  /// No description provided for @yourFriend.
  ///
  /// In en, this message translates to:
  /// **'Your friend '**
  String get yourFriend;

  /// No description provided for @invitedYouToJoin.
  ///
  /// In en, this message translates to:
  /// **' invited you to join Cool.'**
  String get invitedYouToJoin;

  /// No description provided for @momoPay.
  ///
  /// In en, this message translates to:
  /// **'MoMo Pay'**
  String get momoPay;

  /// No description provided for @payAtShopsAnd.
  ///
  /// In en, this message translates to:
  /// **'Pay at shops and partners'**
  String get payAtShopsAnd;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @loan.
  ///
  /// In en, this message translates to:
  /// **'Loan'**
  String get loan;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @groups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get groups;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get explore;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode;

  /// No description provided for @fans.
  ///
  /// In en, this message translates to:
  /// **'Fans'**
  String get fans;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @buyTickets.
  ///
  /// In en, this message translates to:
  /// **'Buy Tickets'**
  String get buyTickets;

  /// No description provided for @shop.
  ///
  /// In en, this message translates to:
  /// **'Shop'**
  String get shop;

  /// No description provided for @walletCashflow.
  ///
  /// In en, this message translates to:
  /// **'Wallet Cashflow'**
  String get walletCashflow;

  /// No description provided for @savingsDiscipline.
  ///
  /// In en, this message translates to:
  /// **'Savings Discipline'**
  String get savingsDiscipline;

  /// No description provided for @groupReliability.
  ///
  /// In en, this message translates to:
  /// **'Group Reliability'**
  String get groupReliability;

  /// No description provided for @profileStrength.
  ///
  /// In en, this message translates to:
  /// **'Profile Strength'**
  String get profileStrength;

  /// No description provided for @officialNameOnFile.
  ///
  /// In en, this message translates to:
  /// **'Official name on file'**
  String get officialNameOnFile;

  /// No description provided for @officialPhoneConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Official phone confirmed'**
  String get officialPhoneConfirmed;

  /// No description provided for @kycReviewStarted.
  ///
  /// In en, this message translates to:
  /// **'KYC review started'**
  String get kycReviewStarted;

  /// No description provided for @kycFullyVerified.
  ///
  /// In en, this message translates to:
  /// **'KYC fully verified'**
  String get kycFullyVerified;

  /// No description provided for @creditReportGenerated.
  ///
  /// In en, this message translates to:
  /// **'Credit report generated'**
  String get creditReportGenerated;

  /// No description provided for @walletHistoryDepth.
  ///
  /// In en, this message translates to:
  /// **'Wallet history depth'**
  String get walletHistoryDepth;

  /// No description provided for @activeMonths.
  ///
  /// In en, this message translates to:
  /// **'Active months'**
  String get activeMonths;

  /// No description provided for @savingsAndGroupEvidence.
  ///
  /// In en, this message translates to:
  /// **'Savings and group evidence'**
  String get savingsAndGroupEvidence;

  /// No description provided for @bankAccountOpening.
  ///
  /// In en, this message translates to:
  /// **'Bank Account Opening'**
  String get bankAccountOpening;

  /// No description provided for @loanApplication.
  ///
  /// In en, this message translates to:
  /// **'Loan Application'**
  String get loanApplication;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @bankReportGeneratedIn.
  ///
  /// In en, this message translates to:
  /// **'Bank Report generated in Google Docs!'**
  String get bankReportGeneratedIn;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'OPEN'**
  String get open;

  /// No description provided for @failedToGenerateBank.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate bank report.'**
  String get failedToGenerateBank;

  /// No description provided for @generateGoogleDoc.
  ///
  /// In en, this message translates to:
  /// **'Generate Google Doc'**
  String get generateGoogleDoc;

  /// No description provided for @incomeStability.
  ///
  /// In en, this message translates to:
  /// **'Income Stability'**
  String get incomeStability;

  /// No description provided for @strengths.
  ///
  /// In en, this message translates to:
  /// **'STRENGTHS'**
  String get strengths;

  /// No description provided for @risks.
  ///
  /// In en, this message translates to:
  /// **'RISKS'**
  String get risks;

  /// No description provided for @connectYourMomoTo.
  ///
  /// In en, this message translates to:
  /// **'Connect your MoMo to see AI insights.'**
  String get connectYourMomoTo;

  /// No description provided for @recentApplications.
  ///
  /// In en, this message translates to:
  /// **'Recent applications'**
  String get recentApplications;

  /// No description provided for @eligiblePartners.
  ///
  /// In en, this message translates to:
  /// **'Eligible partners'**
  String get eligiblePartners;

  /// No description provided for @kyc.
  ///
  /// In en, this message translates to:
  /// **'KYC'**
  String get kyc;

  /// No description provided for @score.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get score;

  /// No description provided for @checks.
  ///
  /// In en, this message translates to:
  /// **'Checks'**
  String get checks;

  /// No description provided for @viewAllPartners.
  ///
  /// In en, this message translates to:
  /// **'View all partners'**
  String get viewAllPartners;

  /// No description provided for @readiness.
  ///
  /// In en, this message translates to:
  /// **'Readiness'**
  String get readiness;

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get created;

  /// No description provided for @applicationPath.
  ///
  /// In en, this message translates to:
  /// **'Application path'**
  String get applicationPath;

  /// No description provided for @loanApplication1.
  ///
  /// In en, this message translates to:
  /// **'Loan application'**
  String get loanApplication1;

  /// No description provided for @accountOpening.
  ///
  /// In en, this message translates to:
  /// **'Account opening'**
  String get accountOpening;

  /// No description provided for @requestedProduct.
  ///
  /// In en, this message translates to:
  /// **'Requested product'**
  String get requestedProduct;

  /// No description provided for @internalNote.
  ///
  /// In en, this message translates to:
  /// **'Internal note'**
  String get internalNote;

  /// No description provided for @saveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get saveDraft;

  /// No description provided for @openReadiness.
  ///
  /// In en, this message translates to:
  /// **'Open readiness'**
  String get openReadiness;

  /// No description provided for @window.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get window;

  /// No description provided for @engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engine;

  /// No description provided for @walletIn.
  ///
  /// In en, this message translates to:
  /// **'Wallet In'**
  String get walletIn;

  /// No description provided for @walletOut.
  ///
  /// In en, this message translates to:
  /// **'Wallet Out'**
  String get walletOut;

  /// No description provided for @savings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get savings;

  /// No description provided for @averageSave.
  ///
  /// In en, this message translates to:
  /// **'Average Save'**
  String get averageSave;

  /// No description provided for @walletHistoryIsStill.
  ///
  /// In en, this message translates to:
  /// **'Wallet history is still'**
  String get walletHistoryIsStill;

  /// No description provided for @incomingCashflowNeedsMore.
  ///
  /// In en, this message translates to:
  /// **'Incoming cashflow needs more'**
  String get incomingCashflowNeedsMore;

  /// No description provided for @savingsPatternIsNot.
  ///
  /// In en, this message translates to:
  /// **'Savings pattern is not'**
  String get savingsPatternIsNot;

  /// No description provided for @noConfirmedGroupFound.
  ///
  /// In en, this message translates to:
  /// **'No confirmed group found'**
  String get noConfirmedGroupFound;

  /// No description provided for @groupContributionActivityIs.
  ///
  /// In en, this message translates to:
  /// **'Group contribution activity is'**
  String get groupContributionActivityIs;

  /// No description provided for @profileVerificationIsHolding.
  ///
  /// In en, this message translates to:
  /// **'Profile verification is holding'**
  String get profileVerificationIsHolding;

  /// No description provided for @verifiedBehaviourLooksHealthy.
  ///
  /// In en, this message translates to:
  /// **'Verified behaviour looks healthy'**
  String get verifiedBehaviourLooksHealthy;

  /// No description provided for @mobileMoneyNumber.
  ///
  /// In en, this message translates to:
  /// **'Mobile Money Number'**
  String get mobileMoneyNumber;

  /// No description provided for @resendVerificationCode.
  ///
  /// In en, this message translates to:
  /// **'Resend verification code'**
  String get resendVerificationCode;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @mobileMoney.
  ///
  /// In en, this message translates to:
  /// **'Mobile Money'**
  String get mobileMoney;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get credit;

  /// No description provided for @rejectAllocation.
  ///
  /// In en, this message translates to:
  /// **'Reject allocation'**
  String get rejectAllocation;

  /// No description provided for @thisWillRemoveThe.
  ///
  /// In en, this message translates to:
  /// **'This removes the pending allocation.'**
  String get thisWillRemoveThe;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @str07xxxxxxxx.
  ///
  /// In en, this message translates to:
  /// **'07XXXXXXXX'**
  String get str07xxxxxxxx;

  /// No description provided for @allocateToMember.
  ///
  /// In en, this message translates to:
  /// **'Allocate to member'**
  String get allocateToMember;

  /// No description provided for @groups1.
  ///
  /// In en, this message translates to:
  /// **'GROUPS'**
  String get groups1;

  /// No description provided for @members1.
  ///
  /// In en, this message translates to:
  /// **'MEMBERS'**
  String get members1;

  /// No description provided for @contributions.
  ///
  /// In en, this message translates to:
  /// **'CONTRIBUTIONS'**
  String get contributions;

  /// No description provided for @ledgers.
  ///
  /// In en, this message translates to:
  /// **'LEDGERS'**
  String get ledgers;

  /// No description provided for @allocations.
  ///
  /// In en, this message translates to:
  /// **'ALLOCATIONS'**
  String get allocations;

  /// No description provided for @loans.
  ///
  /// In en, this message translates to:
  /// **'LOANS'**
  String get loans;

  /// No description provided for @baskets.
  ///
  /// In en, this message translates to:
  /// **'BASKETS'**
  String get baskets;

  /// No description provided for @bankAdmin.
  ///
  /// In en, this message translates to:
  /// **'Bank Admin'**
  String get bankAdmin;

  /// No description provided for @addVehicleType.
  ///
  /// In en, this message translates to:
  /// **'Add vehicle type'**
  String get addVehicleType;

  /// No description provided for @adminWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Admin Workspaces'**
  String get adminWorkspaces;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @globalAppOperationsContent.
  ///
  /// In en, this message translates to:
  /// **'Global app operations content'**
  String get globalAppOperationsContent;

  /// No description provided for @platformAdmin.
  ///
  /// In en, this message translates to:
  /// **'Platform Admin'**
  String get platformAdmin;

  /// No description provided for @usersPartnersServicesApp.
  ///
  /// In en, this message translates to:
  /// **'Users partners services app'**
  String get usersPartnersServicesApp;

  /// No description provided for @partnerWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Partner Workspaces'**
  String get partnerWorkspaces;

  /// No description provided for @partnerscopedAdminSurfacesFor.
  ///
  /// In en, this message translates to:
  /// **'Partner-scoped admin surfaces for'**
  String get partnerscopedAdminSurfacesFor;

  /// No description provided for @bankCustodianWorkspaces.
  ///
  /// In en, this message translates to:
  /// **'Bank Custodian Workspaces'**
  String get bankCustodianWorkspaces;

  /// No description provided for @groupSavingsOversightLedgers.
  ///
  /// In en, this message translates to:
  /// **'Group savings oversight ledgers'**
  String get groupSavingsOversightLedgers;

  /// No description provided for @openTheBankCustodian.
  ///
  /// In en, this message translates to:
  /// **'Open the bank custodian'**
  String get openTheBankCustodian;

  /// No description provided for @addPartner.
  ///
  /// In en, this message translates to:
  /// **'Add partner'**
  String get addPartner;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @mock.
  ///
  /// In en, this message translates to:
  /// **'Mock'**
  String get mock;

  /// No description provided for @website.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// No description provided for @releaseDashboard.
  ///
  /// In en, this message translates to:
  /// **'Release Dashboard'**
  String get releaseDashboard;

  /// No description provided for @triageQueue.
  ///
  /// In en, this message translates to:
  /// **'Triage Queue'**
  String get triageQueue;

  /// No description provided for @recentSignals.
  ///
  /// In en, this message translates to:
  /// **'Recent Signals'**
  String get recentSignals;

  /// No description provided for @service.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get service;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @table.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get table;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @component.
  ///
  /// In en, this message translates to:
  /// **'Component'**
  String get component;

  /// No description provided for @function.
  ///
  /// In en, this message translates to:
  /// **'Function'**
  String get function;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @addConfigEntry.
  ///
  /// In en, this message translates to:
  /// **'Add config entry'**
  String get addConfigEntry;

  /// No description provided for @rolloutGovernance.
  ///
  /// In en, this message translates to:
  /// **'Rollout Governance'**
  String get rolloutGovernance;

  /// No description provided for @addRecipient.
  ///
  /// In en, this message translates to:
  /// **'Add Recipient'**
  String get addRecipient;

  /// No description provided for @partnerPaymentRoutes.
  ///
  /// In en, this message translates to:
  /// **'Partner Payment Routes'**
  String get partnerPaymentRoutes;

  /// No description provided for @additionalConfig.
  ///
  /// In en, this message translates to:
  /// **'Additional Config'**
  String get additionalConfig;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get admins;

  /// No description provided for @drivers.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get drivers;

  /// No description provided for @momo.
  ///
  /// In en, this message translates to:
  /// **'MoMo'**
  String get momo;

  /// No description provided for @driver.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get driver;

  /// No description provided for @deleteBatch.
  ///
  /// In en, this message translates to:
  /// **'Delete Batch'**
  String get deleteBatch;

  /// No description provided for @bank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get bank;

  /// No description provided for @rayon.
  ///
  /// In en, this message translates to:
  /// **'Rayon'**
  String get rayon;

  /// No description provided for @revoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revoke;

  /// No description provided for @pasteUserUuid.
  ///
  /// In en, this message translates to:
  /// **'Paste user UUID'**
  String get pasteUserUuid;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @addQuickAction.
  ///
  /// In en, this message translates to:
  /// **'Add quick action'**
  String get addQuickAction;

  /// No description provided for @partnerAdmin.
  ///
  /// In en, this message translates to:
  /// **'Partner Admin'**
  String get partnerAdmin;

  /// No description provided for @openRayonSportsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Open Rayon Sports Admin'**
  String get openRayonSportsAdmin;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @emoji.
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @starts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get starts;

  /// No description provided for @ends.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get ends;

  /// No description provided for @rewardsDescription.
  ///
  /// In en, this message translates to:
  /// **'Rewards Description'**
  String get rewardsDescription;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @deleteContent.
  ///
  /// In en, this message translates to:
  /// **'Delete content?'**
  String get deleteContent;

  /// No description provided for @editChildTextedit.
  ///
  /// In en, this message translates to:
  /// **'edit\', child: Text(\'Edit'**
  String get editChildTextedit;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @contentType.
  ///
  /// In en, this message translates to:
  /// **'Content Type'**
  String get contentType;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @backToProfile.
  ///
  /// In en, this message translates to:
  /// **'Back to profile'**
  String get backToProfile;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @missionType.
  ///
  /// In en, this message translates to:
  /// **'Mission Type'**
  String get missionType;

  /// No description provided for @targetValue.
  ///
  /// In en, this message translates to:
  /// **'Target Value'**
  String get targetValue;

  /// No description provided for @scope.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get scope;

  /// No description provided for @rewardPoints.
  ///
  /// In en, this message translates to:
  /// **'Reward Tokens'**
  String get rewardPoints;

  /// No description provided for @rewardDescription.
  ///
  /// In en, this message translates to:
  /// **'Reward Description'**
  String get rewardDescription;

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get addService;

  /// No description provided for @mockService.
  ///
  /// In en, this message translates to:
  /// **'Mock service'**
  String get mockService;

  /// No description provided for @partnerSelector.
  ///
  /// In en, this message translates to:
  /// **'Partner selector'**
  String get partnerSelector;

  /// No description provided for @slug.
  ///
  /// In en, this message translates to:
  /// **'Slug'**
  String get slug;

  /// No description provided for @subtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get subtitle;

  /// No description provided for @colorHex.
  ///
  /// In en, this message translates to:
  /// **'Color Hex'**
  String get colorHex;

  /// No description provided for @interestRate.
  ///
  /// In en, this message translates to:
  /// **'Interest Rate'**
  String get interestRate;

  /// No description provided for @loanMultiplier.
  ///
  /// In en, this message translates to:
  /// **'Loan Multiplier'**
  String get loanMultiplier;

  /// No description provided for @momoRecipient.
  ///
  /// In en, this message translates to:
  /// **'MoMo Recipient'**
  String get momoRecipient;

  /// No description provided for @recipientType.
  ///
  /// In en, this message translates to:
  /// **'Recipient Type'**
  String get recipientType;

  /// No description provided for @icon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// No description provided for @targetAudience.
  ///
  /// In en, this message translates to:
  /// **'Target Audience'**
  String get targetAudience;

  /// No description provided for @sortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort Order'**
  String get sortOrder;

  /// No description provided for @statusSelector.
  ///
  /// In en, this message translates to:
  /// **'Status selector'**
  String get statusSelector;

  /// No description provided for @draftChildTextdraft.
  ///
  /// In en, this message translates to:
  /// **'draft\', child: Text(\'Draft'**
  String get draftChildTextdraft;

  /// No description provided for @activeChildTextactive.
  ///
  /// In en, this message translates to:
  /// **'active\', child: Text(\'Active'**
  String get activeChildTextactive;

  /// No description provided for @inactiveChildTextinactive.
  ///
  /// In en, this message translates to:
  /// **'inactive\', child: Text(\'Inactive'**
  String get inactiveChildTextinactive;

  /// No description provided for @allGroups.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get allGroups;

  /// No description provided for @repaid.
  ///
  /// In en, this message translates to:
  /// **'Repaid'**
  String get repaid;

  /// No description provided for @markDisbursed.
  ///
  /// In en, this message translates to:
  /// **'Mark Disbursed'**
  String get markDisbursed;

  /// No description provided for @groups2.
  ///
  /// In en, this message translates to:
  /// **'groups'**
  String get groups2;

  /// No description provided for @contributions1.
  ///
  /// In en, this message translates to:
  /// **'contributions'**
  String get contributions1;

  /// No description provided for @manualReview.
  ///
  /// In en, this message translates to:
  /// **'manual review'**
  String get manualReview;

  /// No description provided for @aum.
  ///
  /// In en, this message translates to:
  /// **'AUM'**
  String get aum;

  /// No description provided for @loansOut.
  ///
  /// In en, this message translates to:
  /// **'loans out'**
  String get loansOut;

  /// No description provided for @activeLoans.
  ///
  /// In en, this message translates to:
  /// **'active loans'**
  String get activeLoans;

  /// No description provided for @activeBaskets.
  ///
  /// In en, this message translates to:
  /// **'active baskets'**
  String get activeBaskets;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @bucket.
  ///
  /// In en, this message translates to:
  /// **'Bucket'**
  String get bucket;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @searchGroups.
  ///
  /// In en, this message translates to:
  /// **'Search groups...'**
  String get searchGroups;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @members2.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members2;

  /// No description provided for @contributions2.
  ///
  /// In en, this message translates to:
  /// **'Contributions'**
  String get contributions2;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @lastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get lastActivity;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @viewLedger.
  ///
  /// In en, this message translates to:
  /// **'View ledger'**
  String get viewLedger;

  /// No description provided for @members3.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members3;

  /// No description provided for @contributions3.
  ///
  /// In en, this message translates to:
  /// **'Contributions'**
  String get contributions3;

  /// No description provided for @raised.
  ///
  /// In en, this message translates to:
  /// **'Raised'**
  String get raised;

  /// No description provided for @openLedger.
  ///
  /// In en, this message translates to:
  /// **'Open ledger'**
  String get openLedger;

  /// No description provided for @editRolloutSettings.
  ///
  /// In en, this message translates to:
  /// **'Edit rollout settings'**
  String get editRolloutSettings;

  /// No description provided for @rwandaOnly.
  ///
  /// In en, this message translates to:
  /// **'Rwanda only'**
  String get rwandaOnly;

  /// No description provided for @editMomoSubscriptionConfig.
  ///
  /// In en, this message translates to:
  /// **'Edit MoMo subscription config'**
  String get editMomoSubscriptionConfig;

  /// No description provided for @editPaymentRouteFor.
  ///
  /// In en, this message translates to:
  /// **'Edit payment route for'**
  String get editPaymentRouteFor;

  /// No description provided for @backToAdmin.
  ///
  /// In en, this message translates to:
  /// **'Back to admin'**
  String get backToAdmin;

  /// No description provided for @rayonSportsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Rayon Sports Admin'**
  String get rayonSportsAdmin;

  /// No description provided for @recentContributions1.
  ///
  /// In en, this message translates to:
  /// **'Recent contributions'**
  String get recentContributions1;

  /// No description provided for @groupSettings.
  ///
  /// In en, this message translates to:
  /// **'Group settings'**
  String get groupSettings;

  /// No description provided for @bankCustodian.
  ///
  /// In en, this message translates to:
  /// **'Bank custodian'**
  String get bankCustodian;

  /// No description provided for @momoToCreator.
  ///
  /// In en, this message translates to:
  /// **'MOMO to creator'**
  String get momoToCreator;

  /// No description provided for @bankheldAndInsured.
  ///
  /// In en, this message translates to:
  /// **'Bank-held and insured.'**
  String get bankheldAndInsured;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @merchantCode.
  ///
  /// In en, this message translates to:
  /// **'Merchant Code'**
  String get merchantCode;

  /// No description provided for @dailyValueDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily\', value: \'daily'**
  String get dailyValueDaily;

  /// No description provided for @weeklyValueWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly\', value: \'weekly'**
  String get weeklyValueWeekly;

  /// No description provided for @monthlyValueMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly\', value: \'monthly'**
  String get monthlyValueMonthly;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @peopleOutline.
  ///
  /// In en, this message translates to:
  /// **'People Outline'**
  String get peopleOutline;

  /// No description provided for @lockOutline.
  ///
  /// In en, this message translates to:
  /// **'Lock Outline'**
  String get lockOutline;

  /// No description provided for @loadGroupsFailed.
  ///
  /// In en, this message translates to:
  /// **'Load groups failed'**
  String get loadGroupsFailed;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get action;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @contributionAmountInRwandan.
  ///
  /// In en, this message translates to:
  /// **'Contribution amount in Rwandan'**
  String get contributionAmountInRwandan;

  /// No description provided for @inviteFromContacts.
  ///
  /// In en, this message translates to:
  /// **'Invite from Contacts'**
  String get inviteFromContacts;

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @coolTokens.
  ///
  /// In en, this message translates to:
  /// **'Cool Tokens'**
  String get coolTokens;

  /// No description provided for @inviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite Friends'**
  String get inviteFriends;

  /// No description provided for @momoStatements.
  ///
  /// In en, this message translates to:
  /// **'MoMo Statements'**
  String get momoStatements;

  /// No description provided for @personalInfo.
  ///
  /// In en, this message translates to:
  /// **'Personal Info'**
  String get personalInfo;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'VIEW'**
  String get view;

  /// No description provided for @failedToCompleteArchive.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete archive.'**
  String get failedToCompleteArchive;

  /// No description provided for @frontOfId.
  ///
  /// In en, this message translates to:
  /// **'Front of ID'**
  String get frontOfId;

  /// No description provided for @liveSelfie.
  ///
  /// In en, this message translates to:
  /// **'Live Selfie'**
  String get liveSelfie;

  /// No description provided for @verifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify Identity'**
  String get verifyIdentity;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @dateOfBirth.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get dateOfBirth;

  /// No description provided for @documentNumber.
  ///
  /// In en, this message translates to:
  /// **'Document number'**
  String get documentNumber;

  /// No description provided for @documentType.
  ///
  /// In en, this message translates to:
  /// **'Document type'**
  String get documentType;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @nationality.
  ///
  /// In en, this message translates to:
  /// **'Nationality'**
  String get nationality;

  /// No description provided for @ocrConfidence.
  ///
  /// In en, this message translates to:
  /// **'OCR confidence'**
  String get ocrConfidence;

  /// No description provided for @useExtractedDetails.
  ///
  /// In en, this message translates to:
  /// **'Use extracted details'**
  String get useExtractedDetails;

  /// No description provided for @scanAgain.
  ///
  /// In en, this message translates to:
  /// **'Scan again'**
  String get scanAgain;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @upload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get upload;

  /// No description provided for @nationalidLabelNationalId.
  ///
  /// In en, this message translates to:
  /// **'national_id\', label: \'National ID'**
  String get nationalidLabelNationalId;

  /// No description provided for @passportLabelPassport.
  ///
  /// In en, this message translates to:
  /// **'passport\', label: \'Passport'**
  String get passportLabelPassport;

  /// No description provided for @drivinglicenseLabelDrivingLicence.
  ///
  /// In en, this message translates to:
  /// **'driving_license\', label: \'Driving licence'**
  String get drivinglicenseLabelDrivingLicence;

  /// No description provided for @defaultKey.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultKey;

  /// No description provided for @passenger.
  ///
  /// In en, this message translates to:
  /// **'Passenger'**
  String get passenger;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @paymentAndActivityAlerts.
  ///
  /// In en, this message translates to:
  /// **'Payment and activity alerts'**
  String get paymentAndActivityAlerts;

  /// No description provided for @openSystemSettings.
  ///
  /// In en, this message translates to:
  /// **'Open system settings'**
  String get openSystemSettings;

  /// No description provided for @smsPaymentSync.
  ///
  /// In en, this message translates to:
  /// **'SMS payment sync'**
  String get smsPaymentSync;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @usedForMomoQr.
  ///
  /// In en, this message translates to:
  /// **'Used for MoMo QR'**
  String get usedForMomoQr;

  /// No description provided for @contacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get contacts;

  /// No description provided for @usedWhenInvitingGroup.
  ///
  /// In en, this message translates to:
  /// **'Used when inviting group'**
  String get usedWhenInvitingGroup;

  /// No description provided for @nfc.
  ///
  /// In en, this message translates to:
  /// **'NFC'**
  String get nfc;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// No description provided for @offInCool.
  ///
  /// In en, this message translates to:
  /// **'Off in COOL'**
  String get offInCool;

  /// No description provided for @needsAndroidAccess.
  ///
  /// In en, this message translates to:
  /// **'Needs Android access'**
  String get needsAndroidAccess;

  /// No description provided for @blockedInSystem.
  ///
  /// In en, this message translates to:
  /// **'Blocked in system'**
  String get blockedInSystem;

  /// No description provided for @deviceSettingOff.
  ///
  /// In en, this message translates to:
  /// **'Device setting off'**
  String get deviceSettingOff;

  /// No description provided for @notAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get notAvailable;

  /// No description provided for @legalNameForReports.
  ///
  /// In en, this message translates to:
  /// **'Legal name for reports'**
  String get legalNameForReports;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get lightMode;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @verification.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get verification;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get plan;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get credits;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @trips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get trips;

  /// No description provided for @addReturnTrip1.
  ///
  /// In en, this message translates to:
  /// **'Add return trip'**
  String get addReturnTrip1;

  /// No description provided for @route.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get route;

  /// No description provided for @departure.
  ///
  /// In en, this message translates to:
  /// **'Departure'**
  String get departure;

  /// No description provided for @returnKey.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnKey;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @payViaMomoUssd1.
  ///
  /// In en, this message translates to:
  /// **'Pay via MOMO USSD'**
  String get payViaMomoUssd1;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get expired;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @matched.
  ///
  /// In en, this message translates to:
  /// **'Matched'**
  String get matched;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @syncSms.
  ///
  /// In en, this message translates to:
  /// **'Sync SMS'**
  String get syncSms;

  /// No description provided for @incoming.
  ///
  /// In en, this message translates to:
  /// **'Incoming'**
  String get incoming;

  /// No description provided for @outgoing.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoing;

  /// No description provided for @entries.
  ///
  /// In en, this message translates to:
  /// **'Entries'**
  String get entries;

  /// No description provided for @postedValue.
  ///
  /// In en, this message translates to:
  /// **'Posted value'**
  String get postedValue;

  /// No description provided for @payers.
  ///
  /// In en, this message translates to:
  /// **'Payers'**
  String get payers;

  /// No description provided for @momoNumber1.
  ///
  /// In en, this message translates to:
  /// **'MoMo Number'**
  String get momoNumber1;

  /// No description provided for @momoCode.
  ///
  /// In en, this message translates to:
  /// **'MoMo Code'**
  String get momoCode;

  /// No description provided for @momoNumber2.
  ///
  /// In en, this message translates to:
  /// **'MoMo Number'**
  String get momoNumber2;

  /// No description provided for @generateQr.
  ///
  /// In en, this message translates to:
  /// **'Get QR'**
  String get generateQr;

  /// No description provided for @deepHistoricalSync.
  ///
  /// In en, this message translates to:
  /// **'Deep historical sync'**
  String get deepHistoricalSync;

  /// No description provided for @privacyFocused.
  ///
  /// In en, this message translates to:
  /// **'Privacy focused'**
  String get privacyFocused;

  /// No description provided for @alwaysInSync.
  ///
  /// In en, this message translates to:
  /// **'Always in sync'**
  String get alwaysInSync;

  /// No description provided for @maybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get maybeLater;

  /// No description provided for @allowAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow access'**
  String get allowAccess;

  /// No description provided for @proceedAnyway.
  ///
  /// In en, this message translates to:
  /// **'Proceed Anyway'**
  String get proceedAnyway;

  /// No description provided for @payByUssd.
  ///
  /// In en, this message translates to:
  /// **'Pay by USSD'**
  String get payByUssd;

  /// No description provided for @momoNumber3.
  ///
  /// In en, this message translates to:
  /// **'MoMo Number'**
  String get momoNumber3;

  /// No description provided for @momoNumber4.
  ///
  /// In en, this message translates to:
  /// **'MoMo Number'**
  String get momoNumber4;

  /// No description provided for @statements.
  ///
  /// In en, this message translates to:
  /// **'Statements'**
  String get statements;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @momoQr.
  ///
  /// In en, this message translates to:
  /// **'MOMO QR'**
  String get momoQr;

  /// No description provided for @nfcPay.
  ///
  /// In en, this message translates to:
  /// **'NFC pay'**
  String get nfcPay;

  /// No description provided for @changeStatementPeriod.
  ///
  /// In en, this message translates to:
  /// **'Change statement period'**
  String get changeStatementPeriod;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get applyFilters;

  /// No description provided for @pdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get pdf;

  /// No description provided for @excel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get excel;

  /// No description provided for @fan.
  ///
  /// In en, this message translates to:
  /// **'Fan'**
  String get fan;

  /// No description provided for @standardMembership.
  ///
  /// In en, this message translates to:
  /// **'Standard membership'**
  String get standardMembership;

  /// No description provided for @matches.
  ///
  /// In en, this message translates to:
  /// **'matches'**
  String get matches;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'products'**
  String get products;

  /// No description provided for @ticketRevenue.
  ///
  /// In en, this message translates to:
  /// **'Ticket Revenue'**
  String get ticketRevenue;

  /// No description provided for @shopRevenue.
  ///
  /// In en, this message translates to:
  /// **'Shop Revenue'**
  String get shopRevenue;

  /// No description provided for @addMatch.
  ///
  /// In en, this message translates to:
  /// **'Add Match'**
  String get addMatch;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @sendNotification.
  ///
  /// In en, this message translates to:
  /// **'Send Notification'**
  String get sendNotification;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @unlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked'**
  String get unlocked;

  /// No description provided for @rayonSports.
  ///
  /// In en, this message translates to:
  /// **'Rayon Sports'**
  String get rayonSports;

  /// No description provided for @memberRegistry.
  ///
  /// In en, this message translates to:
  /// **'Member Registry'**
  String get memberRegistry;

  /// No description provided for @supportClub.
  ///
  /// In en, this message translates to:
  /// **'Support Club'**
  String get supportClub;

  /// No description provided for @nextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next Match'**
  String get nextMatch;

  /// No description provided for @openProfile.
  ///
  /// In en, this message translates to:
  /// **'Open Profile'**
  String get openProfile;

  /// No description provided for @viewPlans.
  ///
  /// In en, this message translates to:
  /// **'View Plans'**
  String get viewPlans;

  /// No description provided for @noMatchOnSale.
  ///
  /// In en, this message translates to:
  /// **'No match on sale'**
  String get noMatchOnSale;

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @shopProducts.
  ///
  /// In en, this message translates to:
  /// **'Shop Products'**
  String get shopProducts;

  /// No description provided for @keepTheCatalogCurrent.
  ///
  /// In en, this message translates to:
  /// **'Keep the catalog current'**
  String get keepTheCatalogCurrent;

  /// No description provided for @addProduct1.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProduct1;

  /// No description provided for @active1.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get active1;

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'stock'**
  String get stock;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get low;

  /// No description provided for @noShopProductsYet.
  ///
  /// In en, this message translates to:
  /// **'No shop products yet'**
  String get noShopProductsYet;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @stock1.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock1;

  /// No description provided for @emojiIcon.
  ///
  /// In en, this message translates to:
  /// **'Emoji Icon'**
  String get emojiIcon;

  /// No description provided for @statusInactive.
  ///
  /// In en, this message translates to:
  /// **'Status inactive'**
  String get statusInactive;

  /// No description provided for @packageActive.
  ///
  /// In en, this message translates to:
  /// **'Package active'**
  String get packageActive;

  /// No description provided for @inactivePackagesRemainHidden.
  ///
  /// In en, this message translates to:
  /// **'Inactive packages remain hidden'**
  String get inactivePackagesRemainHidden;

  /// No description provided for @savePackage.
  ///
  /// In en, this message translates to:
  /// **'Save package'**
  String get savePackage;

  /// No description provided for @membershipPackages.
  ///
  /// In en, this message translates to:
  /// **'Membership Packages'**
  String get membershipPackages;

  /// No description provided for @manageSupporterfacingTierCopy.
  ///
  /// In en, this message translates to:
  /// **'Manage supporter-facing tier copy'**
  String get manageSupporterfacingTierCopy;

  /// No description provided for @plans.
  ///
  /// In en, this message translates to:
  /// **'plans'**
  String get plans;

  /// No description provided for @tier.
  ///
  /// In en, this message translates to:
  /// **'Tier'**
  String get tier;

  /// No description provided for @benefits.
  ///
  /// In en, this message translates to:
  /// **'Benefits'**
  String get benefits;

  /// No description provided for @members4.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members4;

  /// No description provided for @expired1.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get expired1;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'tokens'**
  String get points;

  /// No description provided for @searchMembers.
  ///
  /// In en, this message translates to:
  /// **'Search members'**
  String get searchMembers;

  /// No description provided for @noFanMembershipsYet.
  ///
  /// In en, this message translates to:
  /// **'No fan memberships yet'**
  String get noFanMembershipsYet;

  /// No description provided for @noMembersMatchFilter.
  ///
  /// In en, this message translates to:
  /// **'No members match filter'**
  String get noMembersMatchFilter;

  /// No description provided for @points1.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get points1;

  /// No description provided for @memberCsvCopiedTo.
  ///
  /// In en, this message translates to:
  /// **'Member CSV copied to clipboard'**
  String get memberCsvCopiedTo;

  /// No description provided for @matches1.
  ///
  /// In en, this message translates to:
  /// **'Matches'**
  String get matches1;

  /// No description provided for @scheduleFixturesAdjustPricing.
  ///
  /// In en, this message translates to:
  /// **'Schedule fixtures adjust pricing'**
  String get scheduleFixturesAdjustPricing;

  /// No description provided for @addMatch1.
  ///
  /// In en, this message translates to:
  /// **'Add match'**
  String get addMatch1;

  /// No description provided for @scheduled.
  ///
  /// In en, this message translates to:
  /// **'scheduled'**
  String get scheduled;

  /// No description provided for @onSale.
  ///
  /// In en, this message translates to:
  /// **'on sale'**
  String get onSale;

  /// No description provided for @noMatchesHaveYet.
  ///
  /// In en, this message translates to:
  /// **'No matches have yet'**
  String get noMatchesHaveYet;

  /// No description provided for @homeTeam.
  ///
  /// In en, this message translates to:
  /// **'Home Team'**
  String get homeTeam;

  /// No description provided for @awayTeam.
  ///
  /// In en, this message translates to:
  /// **'Away Team'**
  String get awayTeam;

  /// No description provided for @competition.
  ///
  /// In en, this message translates to:
  /// **'Competition'**
  String get competition;

  /// No description provided for @venue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get venue;

  /// No description provided for @generalPrice.
  ///
  /// In en, this message translates to:
  /// **'General Price'**
  String get generalPrice;

  /// No description provided for @vipPrice.
  ///
  /// In en, this message translates to:
  /// **'VIP Price'**
  String get vipPrice;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity;

  /// No description provided for @initiatives.
  ///
  /// In en, this message translates to:
  /// **'Initiatives'**
  String get initiatives;

  /// No description provided for @trackAndManageCommunity.
  ///
  /// In en, this message translates to:
  /// **'Track and manage community causes'**
  String get trackAndManageCommunity;

  /// No description provided for @addInitiative.
  ///
  /// In en, this message translates to:
  /// **'Add initiative'**
  String get addInitiative;

  /// No description provided for @causes.
  ///
  /// In en, this message translates to:
  /// **'causes'**
  String get causes;

  /// No description provided for @active2.
  ///
  /// In en, this message translates to:
  /// **'active'**
  String get active2;

  /// No description provided for @failedToLoadCauses.
  ///
  /// In en, this message translates to:
  /// **'Failed to load causes'**
  String get failedToLoadCauses;

  /// No description provided for @pullToRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull to retry'**
  String get pullToRetry;

  /// No description provided for @supporters.
  ///
  /// In en, this message translates to:
  /// **'Supporters'**
  String get supporters;

  /// No description provided for @causes1.
  ///
  /// In en, this message translates to:
  /// **'Causes'**
  String get causes1;

  /// No description provided for @loadThisCauseFailed.
  ///
  /// In en, this message translates to:
  /// **'load this cause failed'**
  String get loadThisCauseFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @initiativeNotFound.
  ///
  /// In en, this message translates to:
  /// **'Initiative not found'**
  String get initiativeNotFound;

  /// No description provided for @thisCauseMayHave.
  ///
  /// In en, this message translates to:
  /// **'This cause may have'**
  String get thisCauseMayHave;

  /// No description provided for @shareThisInitiative.
  ///
  /// In en, this message translates to:
  /// **'Share this initiative'**
  String get shareThisInitiative;

  /// No description provided for @inviteSupportersToBack.
  ///
  /// In en, this message translates to:
  /// **'Invite supporters to back'**
  String get inviteSupportersToBack;

  /// No description provided for @momoRef.
  ///
  /// In en, this message translates to:
  /// **'MoMo ref'**
  String get momoRef;

  /// No description provided for @started.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get started;

  /// No description provided for @refreshPaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh payment status'**
  String get refreshPaymentStatus;

  /// No description provided for @fanProfile.
  ///
  /// In en, this message translates to:
  /// **'Fan Profile'**
  String get fanProfile;

  /// No description provided for @showFanQr.
  ///
  /// In en, this message translates to:
  /// **'Show Fan QR'**
  String get showFanQr;

  /// No description provided for @priorityTickets.
  ///
  /// In en, this message translates to:
  /// **'Priority Tickets'**
  String get priorityTickets;

  /// No description provided for @earlyAccessToMatch.
  ///
  /// In en, this message translates to:
  /// **'Early access to match tickets'**
  String get earlyAccessToMatch;

  /// No description provided for @vipEvents.
  ///
  /// In en, this message translates to:
  /// **'VIP Events'**
  String get vipEvents;

  /// No description provided for @exclusiveFanMeetups.
  ///
  /// In en, this message translates to:
  /// **'Exclusive fan meet-ups'**
  String get exclusiveFanMeetups;

  /// No description provided for @freeKit.
  ///
  /// In en, this message translates to:
  /// **'Free Kit'**
  String get freeKit;

  /// No description provided for @freeOfficialKitPer.
  ///
  /// In en, this message translates to:
  /// **'Free official kit per season'**
  String get freeOfficialKitPer;

  /// No description provided for @shopOrders.
  ///
  /// In en, this message translates to:
  /// **'Shop Orders'**
  String get shopOrders;

  /// No description provided for @manageFulfilmentQueueAnd.
  ///
  /// In en, this message translates to:
  /// **'Manage fulfilment queue and track order status.'**
  String get manageFulfilmentQueueAnd;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'orders'**
  String get orders;

  /// No description provided for @pending1.
  ///
  /// In en, this message translates to:
  /// **'pending'**
  String get pending1;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'revenue'**
  String get revenue;

  /// No description provided for @noShopOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No shop orders yet'**
  String get noShopOrdersYet;

  /// No description provided for @noOrdersMatchThis.
  ///
  /// In en, this message translates to:
  /// **'No orders match this filter'**
  String get noOrdersMatchThis;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @momoRef1.
  ///
  /// In en, this message translates to:
  /// **'MoMo Ref'**
  String get momoRef1;

  /// No description provided for @deletePaymentRoute.
  ///
  /// In en, this message translates to:
  /// **'Delete payment route'**
  String get deletePaymentRoute;

  /// No description provided for @financeWorkspaceCouldNot.
  ///
  /// In en, this message translates to:
  /// **'Finance workspace could not'**
  String get financeWorkspaceCouldNot;

  /// No description provided for @finance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get finance;

  /// No description provided for @manageRayonPaymentRouting.
  ///
  /// In en, this message translates to:
  /// **'Manage Rayon payment routing'**
  String get manageRayonPaymentRouting;

  /// No description provided for @newRoute.
  ///
  /// In en, this message translates to:
  /// **'New route'**
  String get newRoute;

  /// No description provided for @total1.
  ///
  /// In en, this message translates to:
  /// **'total'**
  String get total1;

  /// No description provided for @valid.
  ///
  /// In en, this message translates to:
  /// **'valid'**
  String get valid;

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get used;

  /// No description provided for @noTicketsFound.
  ///
  /// In en, this message translates to:
  /// **'No tickets found'**
  String get noTicketsFound;

  /// No description provided for @noTicketsMatchThis.
  ///
  /// In en, this message translates to:
  /// **'No tickets match this filter'**
  String get noTicketsMatchThis;

  /// No description provided for @confirmEntry.
  ///
  /// In en, this message translates to:
  /// **'Confirm Entry'**
  String get confirmEntry;

  /// No description provided for @refund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get refund;

  /// No description provided for @ticketMatchFilterCurrent.
  ///
  /// In en, this message translates to:
  /// **'Ticket match filter Current'**
  String get ticketMatchFilterCurrent;

  /// No description provided for @gateCheck.
  ///
  /// In en, this message translates to:
  /// **'Gate Check'**
  String get gateCheck;

  /// No description provided for @eg50000.
  ///
  /// In en, this message translates to:
  /// **'e.g. 50,000'**
  String get eg50000;

  /// No description provided for @shareTickets.
  ///
  /// In en, this message translates to:
  /// **'Share tickets'**
  String get shareTickets;

  /// No description provided for @myTickets1.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get myTickets1;

  /// No description provided for @inviteSupportersToBuy.
  ///
  /// In en, this message translates to:
  /// **'Invite supporters to buy'**
  String get inviteSupportersToBuy;

  /// No description provided for @browseMatches.
  ///
  /// In en, this message translates to:
  /// **'Browse Matches'**
  String get browseMatches;

  /// No description provided for @paymentPending.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT PENDING'**
  String get paymentPending;

  /// No description provided for @readyForEntry.
  ///
  /// In en, this message translates to:
  /// **'READY FOR ENTRY'**
  String get readyForEntry;

  /// No description provided for @pastTickets.
  ///
  /// In en, this message translates to:
  /// **'PAST TICKETS'**
  String get pastTickets;

  /// No description provided for @fanClub.
  ///
  /// In en, this message translates to:
  /// **'Fan Club'**
  String get fanClub;

  /// No description provided for @membersPreview.
  ///
  /// In en, this message translates to:
  /// **'Members preview'**
  String get membersPreview;

  /// No description provided for @moreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get moreDetails;

  /// No description provided for @inviteSupporters.
  ///
  /// In en, this message translates to:
  /// **'Invite supporters'**
  String get inviteSupporters;

  /// No description provided for @inviteSupportersToJoin.
  ///
  /// In en, this message translates to:
  /// **'Invite supporters to join'**
  String get inviteSupportersToJoin;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @createClub.
  ///
  /// In en, this message translates to:
  /// **'Create Club'**
  String get createClub;

  /// No description provided for @searchNameOrId.
  ///
  /// In en, this message translates to:
  /// **'Search name or ID...'**
  String get searchNameOrId;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @memberDiscount.
  ///
  /// In en, this message translates to:
  /// **'Member discount'**
  String get memberDiscount;

  /// No description provided for @refreshOrderStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh order status'**
  String get refreshOrderStatus;

  /// No description provided for @backToShop.
  ///
  /// In en, this message translates to:
  /// **'Back to shop'**
  String get backToShop;

  /// No description provided for @viewProfileOrders.
  ///
  /// In en, this message translates to:
  /// **'View profile orders'**
  String get viewProfileOrders;

  /// No description provided for @orderId.
  ///
  /// In en, this message translates to:
  /// **'Order ID'**
  String get orderId;

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @checkoutCart.
  ///
  /// In en, this message translates to:
  /// **'Checkout cart'**
  String get checkoutCart;

  /// No description provided for @showAllItems.
  ///
  /// In en, this message translates to:
  /// **'Show all items'**
  String get showAllItems;

  /// No description provided for @requestAQuote.
  ///
  /// In en, this message translates to:
  /// **'Request a Quote'**
  String get requestAQuote;

  /// No description provided for @openRayonSports.
  ///
  /// In en, this message translates to:
  /// **'Open Rayon Sports'**
  String get openRayonSports;

  /// No description provided for @noFootballPartnersYet.
  ///
  /// In en, this message translates to:
  /// **'No football partners yet'**
  String get noFootballPartnersYet;

  /// No description provided for @featuredExperiences.
  ///
  /// In en, this message translates to:
  /// **'Featured experiences'**
  String get featuredExperiences;

  /// No description provided for @jerseysFanGearAnd.
  ///
  /// In en, this message translates to:
  /// **'Jerseys fan gear and'**
  String get jerseysFanGearAnd;

  /// No description provided for @noFinancePartnersYet.
  ///
  /// In en, this message translates to:
  /// **'No finance partners yet'**
  String get noFinancePartnersYet;

  /// No description provided for @openReadinessChecklist.
  ///
  /// In en, this message translates to:
  /// **'Open readiness checklist'**
  String get openReadinessChecklist;

  /// No description provided for @noServicePartnersYet.
  ///
  /// In en, this message translates to:
  /// **'No service partners yet'**
  String get noServicePartnersYet;

  /// No description provided for @loadPartnersFailed.
  ///
  /// In en, this message translates to:
  /// **'load partners failed'**
  String get loadPartnersFailed;

  /// No description provided for @rwandaAgents.
  ///
  /// In en, this message translates to:
  /// **'Rwanda Agents'**
  String get rwandaAgents;

  /// No description provided for @rwandaPlatformCoverage.
  ///
  /// In en, this message translates to:
  /// **'Rwanda Platform Coverage'**
  String get rwandaPlatformCoverage;

  /// No description provided for @zeroHallucination.
  ///
  /// In en, this message translates to:
  /// **'Zero Hallucination'**
  String get zeroHallucination;

  /// No description provided for @jurisdictionLocked.
  ///
  /// In en, this message translates to:
  /// **'Jurisdiction Locked'**
  String get jurisdictionLocked;

  /// No description provided for @qualitygatedOutputs.
  ///
  /// In en, this message translates to:
  /// **'Quality-Gated Outputs'**
  String get qualitygatedOutputs;

  /// No description provided for @rwandaProfessionalStandards.
  ///
  /// In en, this message translates to:
  /// **'Rwanda Professional Standards'**
  String get rwandaProfessionalStandards;

  /// No description provided for @openAccount.
  ///
  /// In en, this message translates to:
  /// **'Open Account'**
  String get openAccount;

  /// No description provided for @digitalOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Digital onboarding'**
  String get digitalOnboarding;

  /// No description provided for @groupSavings.
  ///
  /// In en, this message translates to:
  /// **'Group Savings'**
  String get groupSavings;

  /// No description provided for @digitalGroupWallet.
  ///
  /// In en, this message translates to:
  /// **'Digital group wallet'**
  String get digitalGroupWallet;

  /// No description provided for @getLoan.
  ///
  /// In en, this message translates to:
  /// **'Get Loan'**
  String get getLoan;

  /// No description provided for @fastCreditAccess.
  ///
  /// In en, this message translates to:
  /// **'Fast credit access'**
  String get fastCreditAccess;

  /// No description provided for @coolAppLogo.
  ///
  /// In en, this message translates to:
  /// **'Cool app logo'**
  String get coolAppLogo;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get saving;

  /// No description provided for @community.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get community;

  /// No description provided for @confirmCustomAmount.
  ///
  /// In en, this message translates to:
  /// **'Confirm custom amount'**
  String get confirmCustomAmount;

  /// No description provided for @loadingContent.
  ///
  /// In en, this message translates to:
  /// **'Loading content'**
  String get loadingContent;

  /// No description provided for @seat.
  ///
  /// In en, this message translates to:
  /// **'Seat'**
  String get seat;

  /// No description provided for @fanId.
  ///
  /// In en, this message translates to:
  /// **'Fan ID'**
  String get fanId;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @tripCard.
  ///
  /// In en, this message translates to:
  /// **'Trip card'**
  String get tripCard;

  /// No description provided for @memberId.
  ///
  /// In en, this message translates to:
  /// **'Member ID'**
  String get memberId;

  /// No description provided for @points2.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get points2;

  /// No description provided for @askAboutYourFinances.
  ///
  /// In en, this message translates to:
  /// **'Ask about your finances...'**
  String get askAboutYourFinances;

  /// No description provided for @openQuestAction.
  ///
  /// In en, this message translates to:
  /// **'Open quest action'**
  String get openQuestAction;

  /// No description provided for @retake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get retake;

  /// No description provided for @searchContacts.
  ///
  /// In en, this message translates to:
  /// **'Search contacts'**
  String get searchContacts;

  /// No description provided for @searchByNameOr.
  ///
  /// In en, this message translates to:
  /// **'Search by name or'**
  String get searchByNameOr;

  /// No description provided for @contactsAccessDenied.
  ///
  /// In en, this message translates to:
  /// **'Contacts access denied'**
  String get contactsAccessDenied;

  /// No description provided for @contactsAreOffIn.
  ///
  /// In en, this message translates to:
  /// **'Contacts are off in'**
  String get contactsAreOffIn;

  /// No description provided for @contactsAccessNeeded.
  ///
  /// In en, this message translates to:
  /// **'Contacts access needed'**
  String get contactsAccessNeeded;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @eventsValue.
  ///
  /// In en, this message translates to:
  /// **'Events\', value: \'—'**
  String get eventsValue;

  /// No description provided for @ratingValue.
  ///
  /// In en, this message translates to:
  /// **'Rating\', value: \'—'**
  String get ratingValue;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @momo1.
  ///
  /// In en, this message translates to:
  /// **'MOMO'**
  String get momo1;

  /// No description provided for @scanTicket.
  ///
  /// In en, this message translates to:
  /// **'Scan Ticket'**
  String get scanTicket;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @cameraIsOffIn.
  ///
  /// In en, this message translates to:
  /// **'Camera is off in'**
  String get cameraIsOffIn;

  /// No description provided for @cameraIsBlockedIn.
  ///
  /// In en, this message translates to:
  /// **'Camera is blocked in'**
  String get cameraIsBlockedIn;

  /// No description provided for @cameraNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Camera not available'**
  String get cameraNotAvailable;

  /// No description provided for @allowCameraAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow camera access'**
  String get allowCameraAccess;

  /// No description provided for @closeScanner.
  ///
  /// In en, this message translates to:
  /// **'Close scanner'**
  String get closeScanner;

  /// No description provided for @toggleFlashlight.
  ///
  /// In en, this message translates to:
  /// **'Toggle flashlight'**
  String get toggleFlashlight;

  /// No description provided for @scanAnother.
  ///
  /// In en, this message translates to:
  /// **'Scan Another'**
  String get scanAnother;

  /// No description provided for @shareViaContact.
  ///
  /// In en, this message translates to:
  /// **'Share via Contact'**
  String get shareViaContact;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @copyInviteLink.
  ///
  /// In en, this message translates to:
  /// **'Copy invite link'**
  String get copyInviteLink;

  /// No description provided for @localBlur.
  ///
  /// In en, this message translates to:
  /// **'LOCAL BLUR'**
  String get localBlur;

  /// No description provided for @cool.
  ///
  /// In en, this message translates to:
  /// **'Cool'**
  String get cool;

  /// No description provided for @rewardsProgram.
  ///
  /// In en, this message translates to:
  /// **'Rewards Program'**
  String get rewardsProgram;

  /// No description provided for @str14DaysStreak.
  ///
  /// In en, this message translates to:
  /// **'14 Days Streak'**
  String get str14DaysStreak;

  /// No description provided for @str50Tokens.
  ///
  /// In en, this message translates to:
  /// **'+50 Tokens'**
  String get str50Tokens;

  /// No description provided for @wealthArchiveSavedTo.
  ///
  /// In en, this message translates to:
  /// **'Wealth Archive saved to Google Drive & emailed!'**
  String get wealthArchiveSavedTo;

  /// No description provided for @rwf1.
  ///
  /// In en, this message translates to:
  /// **'Rwf'**
  String get rwf1;

  /// No description provided for @seasonsAndActivities.
  ///
  /// In en, this message translates to:
  /// **'Seasons & Activities'**
  String get seasonsAndActivities;

  /// No description provided for @activeSeasons.
  ///
  /// In en, this message translates to:
  /// **'Active Seasons'**
  String get activeSeasons;

  /// No description provided for @pastSeasons.
  ///
  /// In en, this message translates to:
  /// **'Past Seasons'**
  String get pastSeasons;

  /// No description provided for @seasonEarnTokensSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Earn tokens by completing activities during each season'**
  String get seasonEarnTokensSubtitle;

  /// No description provided for @seasonStatusLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get seasonStatusLive;

  /// No description provided for @seasonStatusEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get seasonStatusEnded;

  /// No description provided for @seasonStatusUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get seasonStatusUpcoming;

  /// No description provided for @seasonsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No seasons or activities yet'**
  String get seasonsEmptyTitle;

  /// No description provided for @earnTokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Earn Tokens'**
  String get earnTokensLabel;

  /// No description provided for @creditReadinessTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit readiness'**
  String get creditReadinessTitle;

  /// No description provided for @groupDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Group Detail'**
  String get groupDetailTitle;

  /// No description provided for @groupNotFound.
  ///
  /// In en, this message translates to:
  /// **'Group not found.'**
  String get groupNotFound;

  /// No description provided for @couldNotJoinGroup.
  ///
  /// In en, this message translates to:
  /// **'Could not join group.'**
  String get couldNotJoinGroup;

  /// No description provided for @noInviteCodeYet.
  ///
  /// In en, this message translates to:
  /// **'This group does not have a shareable invite code yet.'**
  String get noInviteCodeYet;

  /// No description provided for @noContributionsYet.
  ///
  /// In en, this message translates to:
  /// **'No contributions yet'**
  String get noContributionsYet;

  /// No description provided for @showAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get showAll;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// No description provided for @membersCount.
  ///
  /// In en, this message translates to:
  /// **'Members ({count})'**
  String membersCount(int count);

  /// No description provided for @targetAmountRwf.
  ///
  /// In en, this message translates to:
  /// **'Target: RWF {amount}'**
  String targetAmountRwf(String amount);

  /// No description provided for @joinGroupShareText.
  ///
  /// In en, this message translates to:
  /// **'Join {groupName} on Cool: {url}'**
  String joinGroupShareText(String groupName, String url);

  /// No description provided for @joinGroupShareTextEmoji.
  ///
  /// In en, this message translates to:
  /// **'Join {groupName} on Cool! 🎉\n{url}'**
  String joinGroupShareTextEmoji(String groupName, String url);

  /// No description provided for @alreadyMemberOf.
  ///
  /// In en, this message translates to:
  /// **'You are already a member of {groupName}.'**
  String alreadyMemberOf(String groupName);

  /// No description provided for @youJoinedGroup.
  ///
  /// In en, this message translates to:
  /// **'You joined {groupName}.'**
  String youJoinedGroup(String groupName);

  /// No description provided for @ledgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Ledger & Statements'**
  String get ledgerTitle;

  /// No description provided for @allContributors.
  ///
  /// In en, this message translates to:
  /// **'All contributors'**
  String get allContributors;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @chooseExportFormat.
  ///
  /// In en, this message translates to:
  /// **'Choose a format to download the group ledger.'**
  String get chooseExportFormat;

  /// No description provided for @exportLedger.
  ///
  /// In en, this message translates to:
  /// **'Export Ledger'**
  String get exportLedger;

  /// No description provided for @exportAction.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportAction;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed. Please try again.'**
  String get exportFailed;

  /// No description provided for @ledgerExported.
  ///
  /// In en, this message translates to:
  /// **'Ledger exported: {fileName}'**
  String ledgerExported(String fileName);

  /// No description provided for @noDataToExport.
  ///
  /// In en, this message translates to:
  /// **'No data to export.'**
  String get noDataToExport;

  /// No description provided for @csvLabel.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get csvLabel;

  /// No description provided for @excelLabel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get excelLabel;

  /// No description provided for @pdfLabel.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get pdfLabel;

  /// No description provided for @plainTextData.
  ///
  /// In en, this message translates to:
  /// **'Plain text data'**
  String get plainTextData;

  /// No description provided for @printReadyStatement.
  ///
  /// In en, this message translates to:
  /// **'Print-ready statement'**
  String get printReadyStatement;

  /// No description provided for @spreadsheetWithHeaders.
  ///
  /// In en, this message translates to:
  /// **'Spreadsheet with headers'**
  String get spreadsheetWithHeaders;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get newestFirst;

  /// No description provided for @noContributionsForFilter.
  ///
  /// In en, this message translates to:
  /// **'No contributions found for this filter.'**
  String get noContributionsForFilter;

  /// No description provided for @filteredContributor.
  ///
  /// In en, this message translates to:
  /// **'Filtered contributor'**
  String get filteredContributor;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @lastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth;

  /// No description provided for @lastYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get lastYear;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @year.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @kycFrontIdFirst.
  ///
  /// In en, this message translates to:
  /// **'Add front ID first'**
  String get kycFrontIdFirst;

  /// No description provided for @kycAlignBack.
  ///
  /// In en, this message translates to:
  /// **'Align back of {docType}'**
  String kycAlignBack(String docType);

  /// No description provided for @kycAlignFront.
  ///
  /// In en, this message translates to:
  /// **'Align front of {docType}'**
  String kycAlignFront(String docType);

  /// No description provided for @kycBackOfDocument.
  ///
  /// In en, this message translates to:
  /// **'Back of document'**
  String get kycBackOfDocument;

  /// No description provided for @kycBackOfId.
  ///
  /// In en, this message translates to:
  /// **'Back of ID'**
  String get kycBackOfId;

  /// No description provided for @kycChooseDocumentType.
  ///
  /// In en, this message translates to:
  /// **'Choose document type'**
  String get kycChooseDocumentType;

  /// No description provided for @kycFrontOfId.
  ///
  /// In en, this message translates to:
  /// **'Front of ID'**
  String get kycFrontOfId;

  /// No description provided for @kycAutoFilled.
  ///
  /// In en, this message translates to:
  /// **'Cool has already filled'**
  String get kycAutoFilled;

  /// No description provided for @kycExtracting.
  ///
  /// In en, this message translates to:
  /// **'Cool is extracting your'**
  String get kycExtracting;

  /// No description provided for @kycCurrentIdentity.
  ///
  /// In en, this message translates to:
  /// **'Current identity on file'**
  String get kycCurrentIdentity;

  /// No description provided for @kycDrivingLicence.
  ///
  /// In en, this message translates to:
  /// **'Driving licence'**
  String get kycDrivingLicence;

  /// No description provided for @kycExtractedReady.
  ///
  /// In en, this message translates to:
  /// **'Extracted profile ready'**
  String get kycExtractedReady;

  /// No description provided for @kycExtractionFailed.
  ///
  /// In en, this message translates to:
  /// **'Extraction failed'**
  String get kycExtractionFailed;

  /// No description provided for @kycNationalId.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get kycNationalId;

  /// No description provided for @kycPassport.
  ///
  /// In en, this message translates to:
  /// **'Passport'**
  String get kycPassport;

  /// No description provided for @kycNoImageYet.
  ///
  /// In en, this message translates to:
  /// **'No image yet'**
  String get kycNoImageYet;

  /// No description provided for @kycReadingId.
  ///
  /// In en, this message translates to:
  /// **'Reading your ID'**
  String get kycReadingId;

  /// No description provided for @kycSelfieForFaceMatch.
  ///
  /// In en, this message translates to:
  /// **'Take a selfie for face match'**
  String get kycSelfieForFaceMatch;

  /// No description provided for @kycIdentityMismatch.
  ///
  /// In en, this message translates to:
  /// **'Identity mismatch detected.'**
  String get kycIdentityMismatch;

  /// No description provided for @kycDobValue.
  ///
  /// In en, this message translates to:
  /// **'DOB {dob}'**
  String kycDobValue(String dob);

  /// No description provided for @kycIdMasked.
  ///
  /// In en, this message translates to:
  /// **'ID ••••{last4}'**
  String kycIdMasked(String last4);

  /// No description provided for @adminPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanelTitle;

  /// No description provided for @adminQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get adminQuickActions;

  /// No description provided for @adminOperations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get adminOperations;

  /// No description provided for @adminAppConfig.
  ///
  /// In en, this message translates to:
  /// **'App Config'**
  String get adminAppConfig;

  /// No description provided for @adminAppConfigDesc.
  ///
  /// In en, this message translates to:
  /// **'Key-value settings'**
  String get adminAppConfigDesc;

  /// No description provided for @adminAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit Log'**
  String get adminAuditLog;

  /// No description provided for @adminAuditLogDesc.
  ///
  /// In en, this message translates to:
  /// **'Who did what, when'**
  String get adminAuditLogDesc;

  /// No description provided for @adminMissions.
  ///
  /// In en, this message translates to:
  /// **'Missions'**
  String get adminMissions;

  /// No description provided for @adminMissionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Create & manage cooperative missions'**
  String get adminMissionsDesc;

  /// No description provided for @adminAdminRoles.
  ///
  /// In en, this message translates to:
  /// **'Admin Roles'**
  String get adminAdminRoles;

  /// No description provided for @adminAdminRolesDesc.
  ///
  /// In en, this message translates to:
  /// **'Assign & manage admin access'**
  String get adminAdminRolesDesc;

  /// No description provided for @adminPartners.
  ///
  /// In en, this message translates to:
  /// **'Partners'**
  String get adminPartners;

  /// No description provided for @adminPartnersDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage partner profiles'**
  String get adminPartnersDesc;

  /// No description provided for @adminSeasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get adminSeasons;

  /// No description provided for @adminSeasonsDesc.
  ///
  /// In en, this message translates to:
  /// **'Token-earning gamification activities'**
  String get adminSeasonsDesc;

  /// No description provided for @adminActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get adminActivities;

  /// No description provided for @adminServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get adminServices;

  /// No description provided for @adminServicesDesc.
  ///
  /// In en, this message translates to:
  /// **'Partner service offerings'**
  String get adminServicesDesc;

  /// No description provided for @adminSpecialProducts.
  ///
  /// In en, this message translates to:
  /// **'Special Products'**
  String get adminSpecialProducts;

  /// No description provided for @adminSpecialProductsDesc.
  ///
  /// In en, this message translates to:
  /// **'Home screen cards'**
  String get adminSpecialProductsDesc;

  /// No description provided for @adminAiContent.
  ///
  /// In en, this message translates to:
  /// **'AI Content'**
  String get adminAiContent;

  /// No description provided for @adminAiContentDesc.
  ///
  /// In en, this message translates to:
  /// **'AI-generated UI with approval gate'**
  String get adminAiContentDesc;

  /// No description provided for @adminSystemAnalytics.
  ///
  /// In en, this message translates to:
  /// **'System Analytics'**
  String get adminSystemAnalytics;

  /// No description provided for @adminSystemAnalyticsDesc.
  ///
  /// In en, this message translates to:
  /// **'Platform-wide metrics & trends'**
  String get adminSystemAnalyticsDesc;

  /// No description provided for @adminUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get adminUsers;

  /// No description provided for @adminUsersDesc.
  ///
  /// In en, this message translates to:
  /// **'Inspect profiles and demo batches'**
  String get adminUsersDesc;

  /// No description provided for @adminLiveOps.
  ///
  /// In en, this message translates to:
  /// **'Live-Ops'**
  String get adminLiveOps;

  /// No description provided for @adminLiveOpsDesc.
  ///
  /// In en, this message translates to:
  /// **'Live-ops campaigns & rewards'**
  String get adminLiveOpsDesc;

  /// No description provided for @adminRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get adminRelease;

  /// No description provided for @adminReleaseDesc.
  ///
  /// In en, this message translates to:
  /// **'Release health and triage'**
  String get adminReleaseDesc;

  /// No description provided for @adminSupportMode.
  ///
  /// In en, this message translates to:
  /// **'Support Mode'**
  String get adminSupportMode;

  /// No description provided for @adminSupportModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Open a bank or rayon workspace as support'**
  String get adminSupportModeDesc;

  /// No description provided for @adminSupportModeHint.
  ///
  /// In en, this message translates to:
  /// **'Navigate into a partner workspace to view and manage it as support.'**
  String get adminSupportModeHint;

  /// No description provided for @adminNoPartnersFound.
  ///
  /// In en, this message translates to:
  /// **'No partners found'**
  String get adminNoPartnersFound;

  /// No description provided for @adminFailedToLoadPartners.
  ///
  /// In en, this message translates to:
  /// **'Failed to load partners: {error}'**
  String adminFailedToLoadPartners(String error);

  /// No description provided for @rsAdminUpdateStatus.
  ///
  /// In en, this message translates to:
  /// **'Update Status'**
  String get rsAdminUpdateStatus;

  /// No description provided for @rsAdminOrderNumber.
  ///
  /// In en, this message translates to:
  /// **'Order #{orderId}'**
  String rsAdminOrderNumber(String orderId);

  /// No description provided for @rsAdminItemsCount.
  ///
  /// In en, this message translates to:
  /// **'Items ({count})'**
  String rsAdminItemsCount(int count);

  /// No description provided for @partnerNotFound.
  ///
  /// In en, this message translates to:
  /// **'Partner not found'**
  String get partnerNotFound;

  /// No description provided for @prismaLabel.
  ///
  /// In en, this message translates to:
  /// **'PRISMA'**
  String get prismaLabel;

  /// No description provided for @couldNotLoadServices.
  ///
  /// In en, this message translates to:
  /// **'Could not load services'**
  String get couldNotLoadServices;

  /// No description provided for @partnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get partnerLabel;

  /// No description provided for @spreadsheetHeaders.
  ///
  /// In en, this message translates to:
  /// **'Spreadsheet with headers'**
  String get spreadsheetHeaders;

  /// No description provided for @contributorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Contributors'**
  String get contributorsLabel;

  /// No description provided for @kycIdentityVerification.
  ///
  /// In en, this message translates to:
  /// **'Identity verification'**
  String get kycIdentityVerification;

  /// No description provided for @rsAdminNoOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get rsAdminNoOrders;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
