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
  /// **'Community savings, group funds & mobility — all in one simple app for Rwanda.'**
  String get welcomeSubtitle;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign In'**
  String get signIn;

  /// No description provided for @verifyWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Verify via WhatsApp'**
  String get verifyWhatsapp;

  /// No description provided for @verifyWhatsappSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send a one-time code to your WhatsApp number.'**
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
  /// **'Enter the 6-digit code sent to your WhatsApp.'**
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
  String resendCodeIn(int seconds);

  /// No description provided for @invalidCode.
  ///
  /// In en, this message translates to:
  /// **'Invalid code. Please try again.'**
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
  /// **'e.g. 0788 123 456'**
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
  /// **'No recent activity to show.'**
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
  /// **'Transfer instantly to a member ID'**
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
  String memberCount(int count);

  /// No description provided for @groupMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get groupMembers;

  /// No description provided for @recentContributions.
  ///
  /// In en, this message translates to:
  /// **'Recent Contributions'**
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
  /// **'You haven\'t joined any groups yet.'**
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
  String totalItems(int count);

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
  /// **'Unable to open the USSD dialer. Please try again.'**
  String get momoDialerError;

  /// No description provided for @mobilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Mobility'**
  String get mobilityTitle;

  /// No description provided for @nearbyDrivers.
  ///
  /// In en, this message translates to:
  /// **'Nearby Drivers'**
  String get nearbyDrivers;

  /// No description provided for @scheduledTrips.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Trips'**
  String get scheduledTrips;

  /// No description provided for @scheduleTrip.
  ///
  /// In en, this message translates to:
  /// **'Schedule a Trip'**
  String get scheduleTrip;

  /// No description provided for @postTrip.
  ///
  /// In en, this message translates to:
  /// **'Post Trip on Board'**
  String get postTrip;

  /// No description provided for @tripBoard.
  ///
  /// In en, this message translates to:
  /// **'Trip Board'**
  String get tripBoard;

  /// No description provided for @driverProfile.
  ///
  /// In en, this message translates to:
  /// **'Driver Profile'**
  String get driverProfile;

  /// No description provided for @allTrips.
  ///
  /// In en, this message translates to:
  /// **'All Trips'**
  String get allTrips;

  /// No description provided for @oneWay.
  ///
  /// In en, this message translates to:
  /// **'One Way'**
  String get oneWay;

  /// No description provided for @returnTrips.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnTrips;

  /// No description provided for @noTripsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No trips available right now.'**
  String get noTripsAvailable;

  /// No description provided for @noDriversNearby.
  ///
  /// In en, this message translates to:
  /// **'No drivers nearby.'**
  String get noDriversNearby;

  /// No description provided for @contactViaWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'Contact via WhatsApp'**
  String get contactViaWhatsapp;

  /// No description provided for @tripDetails.
  ///
  /// In en, this message translates to:
  /// **'Trip Details'**
  String get tripDetails;

  /// No description provided for @expiresIn.
  ///
  /// In en, this message translates to:
  /// **'Expires in {minutes} min'**
  String expiresIn(int minutes);

  /// No description provided for @seatsLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} seat'**
  String seatsLabel(int count);

  /// No description provided for @seatsLabelPlural.
  ///
  /// In en, this message translates to:
  /// **'{count} seats'**
  String seatsLabelPlural(int count);

  /// No description provided for @scheduleTripTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule a Trip'**
  String get scheduleTripTitle;

  /// No description provided for @scheduleTripInfoBanner.
  ///
  /// In en, this message translates to:
  /// **'Schedule ahead to find the best matches — drivers can offer return trips at lower prices!'**
  String get scheduleTripInfoBanner;

  /// No description provided for @scheduleTripDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Trip Details'**
  String get scheduleTripDetailsTitle;

  /// No description provided for @scheduleTripFromHint.
  ///
  /// In en, this message translates to:
  /// **'📍 From — e.g. Nyamirambo'**
  String get scheduleTripFromHint;

  /// No description provided for @scheduleTripToHint.
  ///
  /// In en, this message translates to:
  /// **'🎯 To — e.g. Kigali Downtown'**
  String get scheduleTripToHint;

  /// No description provided for @scheduleTripDateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get scheduleTripDateTimeLabel;

  /// No description provided for @scheduleTripVehicleLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Preference'**
  String get scheduleTripVehicleLabel;

  /// No description provided for @scheduleTripSeatsLabel.
  ///
  /// In en, this message translates to:
  /// **'Seats Needed'**
  String get scheduleTripSeatsLabel;

  /// No description provided for @scheduleTripReturnTitle.
  ///
  /// In en, this message translates to:
  /// **'Return Trip'**
  String get scheduleTripReturnTitle;

  /// No description provided for @scheduleTripReturnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Drivers offer discounts on return trips'**
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
  /// **'Trips are removed 60 min after departure time if unfilled.'**
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
  /// **'Trip saved offline and will sync when a connection is available.'**
  String get scheduleTripPostedPendingSync;

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
  /// **'Departure and destination must be different.'**
  String get scheduleTripRouteSameError;

  /// No description provided for @scheduleTripReturnInvalidError.
  ///
  /// In en, this message translates to:
  /// **'Return date and time must be after departure.'**
  String get scheduleTripReturnInvalidError;

  /// No description provided for @scheduleTripRecurringDaysError.
  ///
  /// In en, this message translates to:
  /// **'Pick at least one repeat day.'**
  String get scheduleTripRecurringDaysError;

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
  /// **'You are online and visible to nearby passengers.'**
  String get driverOnlineMessage;

  /// No description provided for @driverOfflineMessage.
  ///
  /// In en, this message translates to:
  /// **'You are offline. Turn on driver mode to receive trips.'**
  String get driverOfflineMessage;

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

  /// No description provided for @tripsDone.
  ///
  /// In en, this message translates to:
  /// **'Trips Done'**
  String get tripsDone;

  /// No description provided for @freeTrips.
  ///
  /// In en, this message translates to:
  /// **'Free Trips'**
  String get freeTrips;

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

  /// No description provided for @myVehicle.
  ///
  /// In en, this message translates to:
  /// **'My Vehicle'**
  String get myVehicle;

  /// No description provided for @editVehicle.
  ///
  /// In en, this message translates to:
  /// **'Edit Vehicle'**
  String get editVehicle;

  /// No description provided for @saveVehicleInfo.
  ///
  /// In en, this message translates to:
  /// **'Save Vehicle Info'**
  String get saveVehicleInfo;

  /// No description provided for @vehicleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Type'**
  String get vehicleTypeLabel;

  /// No description provided for @plateNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Plate Number'**
  String get plateNumberLabel;

  /// No description provided for @baseLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'Base Location'**
  String get baseLocationLabel;

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
  /// **'You have used {used} trips so far and only {remaining} free trips remain.'**
  String tripsUsedMessage(int used, int remaining);

  /// No description provided for @daysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} days remaining'**
  String daysRemaining(int count);

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
  /// **'🛺 Moto'**
  String get vehicleMoto;

  /// No description provided for @vehicleCab.
  ///
  /// In en, this message translates to:
  /// **'🚗 Cab'**
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
  String fansCount(int count);

  /// No description provided for @clubsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} clubs'**
  String clubsCount(int count);

  /// No description provided for @gamesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} games'**
  String gamesCount(int count);

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
  /// **'📱 WhatsApp confirmation will be sent after payment'**
  String get whatsappConfirmation;

  /// No description provided for @viewTicket.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewTicket;

  /// No description provided for @showAtGate.
  ///
  /// In en, this message translates to:
  /// **'Show this at the gate'**
  String get showAtGate;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @goldDiscount.
  ///
  /// In en, this message translates to:
  /// **'🌟 Gold Members get 10% off'**
  String get goldDiscount;

  /// No description provided for @noTicketsYet.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get noTicketsYet;

  /// No description provided for @buyTicketsToUpcomingMatches.
  ///
  /// In en, this message translates to:
  /// **'Buy tickets to upcoming matches'**
  String get buyTicketsToUpcomingMatches;

  /// No description provided for @cartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String cartItemCount(int count);

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
  /// **'Contribute on time every month'**
  String get improveOnTime;

  /// No description provided for @improveJoinGroups.
  ///
  /// In en, this message translates to:
  /// **'Join 2+ savings groups'**
  String get improveJoinGroups;

  /// No description provided for @improveCommunityFunds.
  ///
  /// In en, this message translates to:
  /// **'Contribute to 3 community funds'**
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
  /// **'Are you sure you want to sign out? You will need to verify your WhatsApp OTP again to log back in.'**
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
  String expiringInDays(int count);

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

  /// No description provided for @noConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection.'**
  String get noConnection;

  /// No description provided for @offlineNotice.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Showing cached data.'**
  String get offlineNotice;

  /// No description provided for @goodMorningUser.
  ///
  /// In en, this message translates to:
  /// **'Good morning, {name} 👋'**
  String goodMorningUser(String name);

  /// No description provided for @memberIdPrefix.
  ///
  /// In en, this message translates to:
  /// **'ID: '**
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
  /// **'Scan QR or share the link'**
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
  String inMinutesShort(int count);

  /// No description provided for @inHoursShort.
  ///
  /// In en, this message translates to:
  /// **'in {count}h'**
  String inHoursShort(int count);

  /// No description provided for @inDaysShort.
  ///
  /// In en, this message translates to:
  /// **'in {count}d'**
  String inDaysShort(int count);

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
  String targetAmount(String amount);

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
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
  /// **'We will send a 6-digit code to your WhatsApp.'**
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
  /// **'Something went wrong. Please try again.'**
  String get otpGenericError;

  /// No description provided for @openLinkError.
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get openLinkError;

  /// No description provided for @otpLegalPrefix.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you accept the '**
  String get otpLegalPrefix;

  /// No description provided for @otpLegalAnd.
  ///
  /// In en, this message translates to:
  /// **' and '**
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
  /// **'Pay'**
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
  /// **'MoMo and statements'**
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

  /// No description provided for @homeActiveCount.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String homeActiveCount(int count);

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
  /// **'Pull to refresh or try again.'**
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
  /// **'Show extra actions and secondary shortcuts.'**
  String get profileMoreToolsShowSubtitle;

  /// No description provided for @profileMoreToolsHideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide QR, driver, status, and admin shortcuts.'**
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
  /// **'This permanently removes your account and data.'**
  String get deleteAccountMessage;

  /// No description provided for @signOutMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ll need to verify your number again to log back in.'**
  String get signOutMessage;

  /// No description provided for @completeProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile'**
  String get completeProfileTitle;

  /// No description provided for @completeProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Finish setup to unlock all features.'**
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
  /// **'Failed to update MoMo info'**
  String get profileMomoUpdateFailed;

  /// No description provided for @profileSupportOpenError.
  ///
  /// In en, this message translates to:
  /// **'Could not open WhatsApp. Please try again.'**
  String get profileSupportOpenError;

  /// No description provided for @profileSupportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Support is unavailable right now.'**
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
  String profileMomoQrSubtitle(String number);

  /// No description provided for @profileEditMomoInfo.
  ///
  /// In en, this message translates to:
  /// **'Edit MoMo Info'**
  String get profileEditMomoInfo;

  /// No description provided for @profileEditMomoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This number will be used for Mobile Money payments'**
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
  /// **'Wallet activity will appear here.'**
  String get walletEmptyMessage;

  /// No description provided for @walletLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet ledger'**
  String get walletLedgerTitle;

  /// No description provided for @walletLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} wallet entries.'**
  String walletLedgerSubtitle(int shown, int total);

  /// No description provided for @savingsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No savings entries yet'**
  String get savingsEmptyTitle;

  /// No description provided for @savingsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Savings contributions will appear here.'**
  String get savingsEmptyMessage;

  /// No description provided for @savingsStatementTitle.
  ///
  /// In en, this message translates to:
  /// **'Savings statement'**
  String get savingsStatementTitle;

  /// No description provided for @savingsStatementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} group contribution records.'**
  String savingsStatementSubtitle(int shown, int total);

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
  /// **'Try adjusting your filters or date range.'**
  String get momoStatementsWalletFilteredEmptyMessage;

  /// No description provided for @momoStatementsSavingsFilteredEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No matching savings entries'**
  String get momoStatementsSavingsFilteredEmptyTitle;

  /// No description provided for @momoStatementsSavingsFilteredEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters or date range.'**
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
  /// **'Fan features for {clubName} are now consolidated in the partner hub.'**
  String fansScreenBody(String clubName);

  /// No description provided for @fansScreenMembershipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Membership features live inside Rayon Sports.'**
  String get fansScreenMembershipUnavailable;

  /// No description provided for @fansScreenClubsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Fan clubs are now managed inside Rayon Sports.'**
  String get fansScreenClubsUnavailable;

  /// No description provided for @fansScreenRayonDedicatedHub.
  ///
  /// In en, this message translates to:
  /// **'Rayon Sports has a dedicated fan hub.'**
  String get fansScreenRayonDedicatedHub;

  /// No description provided for @fansScreenRouteKeptReachable.
  ///
  /// In en, this message translates to:
  /// **'This route is kept reachable for deep links.'**
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
  /// **'Google Wallet is not available on this device.'**
  String get ticketWalletUnavailable;

  /// No description provided for @ticketWalletOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open Google Wallet.'**
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
  /// **'Check out {matchTitle} on Cool!'**
  String ticketShareMatchText(String matchTitle);

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
  /// **'Your ticket is reserved. Complete the MoMo payment to activate it.'**
  String get ticketStatusPendingNote;

  /// No description provided for @ticketStatusValidTitle.
  ///
  /// In en, this message translates to:
  /// **'Valid Ticket'**
  String get ticketStatusValidTitle;

  /// No description provided for @ticketStatusValidSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show this at the gate.'**
  String get ticketStatusValidSubtitle;

  /// No description provided for @ticketStatusValidNote.
  ///
  /// In en, this message translates to:
  /// **'Present the QR code below at the stadium entrance.'**
  String get ticketStatusValidNote;

  /// No description provided for @ticketStatusUsedTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Used'**
  String get ticketStatusUsedTitle;

  /// No description provided for @ticketStatusUsedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This ticket has been scanned.'**
  String get ticketStatusUsedSubtitle;

  /// No description provided for @ticketStatusUsedNote.
  ///
  /// In en, this message translates to:
  /// **'This ticket was validated at the gate. It cannot be used again.'**
  String get ticketStatusUsedNote;

  /// No description provided for @ticketStatusCancelledTitle.
  ///
  /// In en, this message translates to:
  /// **'Ticket Cancelled'**
  String get ticketStatusCancelledTitle;

  /// No description provided for @ticketStatusCancelledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This ticket is no longer valid.'**
  String get ticketStatusCancelledSubtitle;

  /// No description provided for @ticketStatusCancelledNote.
  ///
  /// In en, this message translates to:
  /// **'Contact support if you believe this is an error.'**
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
  /// **'Your fan membership has been created. Enjoy exclusive perks, tickets, and club updates.'**
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
  /// **'No football partners available yet.'**
  String get partnersNoFootballPartners;

  /// No description provided for @partnersComingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'{partnerName} is coming soon!'**
  String partnersComingSoonMessage(String partnerName);

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
  /// **'No finance partners available yet.'**
  String get partnersNoFinancePartners;

  /// No description provided for @partnersFinancePrepTitle.
  ///
  /// In en, this message translates to:
  /// **'Financial Readiness'**
  String get partnersFinancePrepTitle;

  /// No description provided for @partnersFinancePrepSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check your credit readiness and prepare for financial services from our partners.'**
  String get partnersFinancePrepSubtitle;

  /// No description provided for @partnersReadinessChecklistCta.
  ///
  /// In en, this message translates to:
  /// **'Credit Readiness Checklist'**
  String get partnersReadinessChecklistCta;

  /// No description provided for @partnersWhatsappMessage.
  ///
  /// In en, this message translates to:
  /// **'Hi, I\'d like to learn more about {partnerName} on Cool.'**
  String partnersWhatsappMessage(String partnerName);

  /// No description provided for @partnersNoServicePartners.
  ///
  /// In en, this message translates to:
  /// **'No service partners available yet.'**
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
  /// **'Could not load partners'**
  String get partnersLoadErrorTitle;

  /// No description provided for @partnersEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Partners will appear here once available.'**
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
  /// **'NFC launch failed. Please try again.'**
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
  /// **'Please enter a valid recipient and amount.'**
  String get momoSendValidationError;

  /// No description provided for @momoSendLaunchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not launch MoMo payment for {countryName}.'**
  String momoSendLaunchFailed(String countryName);

  /// No description provided for @momoFromNumber.
  ///
  /// In en, this message translates to:
  /// **'From {number}'**
  String momoFromNumber(String number);

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
  String momoAmountLabel(String currency);

  /// No description provided for @momoSendCompletesViaUssd.
  ///
  /// In en, this message translates to:
  /// **'Completes via USSD on your {countryName} SIM.'**
  String momoSendCompletesViaUssd(String countryName);

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
  String momoStatementsSavedFile(String fileName);

  /// No description provided for @momoStatementsDownloadedFile.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {fileName}'**
  String momoStatementsDownloadedFile(String fileName);

  /// No description provided for @momoStatementsDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Statement download failed.'**
  String get momoStatementsDownloadFailed;

  /// No description provided for @momoStatementsFilterSummaryPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period: {period}'**
  String momoStatementsFilterSummaryPeriod(String period);

  /// No description provided for @momoStatementsFilterSummaryParty.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String momoStatementsFilterSummaryParty(String label, String value);

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
  /// **'Join {groupName} on Cool: {inviteUrl}'**
  String groupsShareText(String groupName, String inviteUrl);

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
  /// **'Pull to refresh or check your groups.'**
  String get groupsEmptyPublicMessage;

  /// No description provided for @groupsEmptyPrivateMessage.
  ///
  /// In en, this message translates to:
  /// **'Create a group or browse public ones.'**
  String get groupsEmptyPrivateMessage;

  /// No description provided for @groupsBankCustodianMeta.
  ///
  /// In en, this message translates to:
  /// **'Bank custodian · {partnerName}'**
  String groupsBankCustodianMeta(String partnerName);

  /// No description provided for @groupsMomoRouteMeta.
  ///
  /// In en, this message translates to:
  /// **'MoMo route · {number}'**
  String groupsMomoRouteMeta(String number);

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
  /// **'Failed to update identity details'**
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
  /// **'{tier} · {points} pts'**
  String profileCoolStatusValue(String tier, int points);

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

  /// No description provided for @profileTravelRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Travel role'**
  String get profileTravelRoleLabel;

  /// No description provided for @profilePassengerRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Passenger'**
  String get profilePassengerRoleLabel;

  /// No description provided for @profileDriverRoleLabel.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get profileDriverRoleLabel;

  /// No description provided for @profileMomoCodeNotSet.
  ///
  /// In en, this message translates to:
  /// **'MoMo code not set'**
  String get profileMomoCodeNotSet;

  /// No description provided for @profileDriverSetupPending.
  ///
  /// In en, this message translates to:
  /// **'Driver setup pending'**
  String get profileDriverSetupPending;

  /// No description provided for @profileRegularDriverCadence.
  ///
  /// In en, this message translates to:
  /// **'Regular driver'**
  String get profileRegularDriverCadence;

  /// No description provided for @profileOccasionalDriverCadence.
  ///
  /// In en, this message translates to:
  /// **'Occasional driver'**
  String get profileOccasionalDriverCadence;

  /// No description provided for @profileMobilityCreditsValue.
  ///
  /// In en, this message translates to:
  /// **'{credits} credits'**
  String profileMobilityCreditsValue(int credits);

  /// No description provided for @profileMobilitySubscriptionActive.
  ///
  /// In en, this message translates to:
  /// **'Subscription active'**
  String get profileMobilitySubscriptionActive;

  /// No description provided for @profileMobilitySubscriptionUntil.
  ///
  /// In en, this message translates to:
  /// **'Subscribed until {date}'**
  String profileMobilitySubscriptionUntil(String date);

  /// No description provided for @mobilityNoWhatsappAvailable.
  ///
  /// In en, this message translates to:
  /// **'No WhatsApp contact available yet.'**
  String get mobilityNoWhatsappAvailable;

  /// No description provided for @mobilityNoContactYet.
  ///
  /// In en, this message translates to:
  /// **'No contact yet'**
  String get mobilityNoContactYet;

  /// No description provided for @mobilityLocationRequiredDriverMode.
  ///
  /// In en, this message translates to:
  /// **'Location is required before turning on driver mode.'**
  String get mobilityLocationRequiredDriverMode;

  /// No description provided for @momoSendMoneyOpensUssd.
  ///
  /// In en, this message translates to:
  /// **'Open {countryName} MoMo USSD to send money.'**
  String momoSendMoneyOpensUssd(String countryName);

  /// No description provided for @momoMoreToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Statements, QR, and NFC tools for your route.'**
  String get momoMoreToolsSubtitle;

  /// No description provided for @momoStatementsToolSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review wallet and savings history.'**
  String get momoStatementsToolSubtitle;

  /// No description provided for @momoNfcToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'NFC tools'**
  String get momoNfcToolsTitle;

  /// No description provided for @momoNfcToolsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap-to-pay and share route details.'**
  String get momoNfcToolsSubtitle;

  /// No description provided for @basketScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get basketScreenTitle;

  /// No description provided for @basketScreenHeadline.
  ///
  /// In en, this message translates to:
  /// **'Basket is not live right now'**
  String get basketScreenHeadline;

  /// No description provided for @basketScreenBody.
  ///
  /// In en, this message translates to:
  /// **'This route stays available for compatibility, but basket balances and creation flows are not active in this build.'**
  String get basketScreenBody;

  /// No description provided for @basketScreenCardBody.
  ///
  /// In en, this message translates to:
  /// **'Basket products are paused while the team finishes the next release.'**
  String get basketScreenCardBody;

  /// No description provided for @basketScreenExpectationBalances.
  ///
  /// In en, this message translates to:
  /// **'No live basket balances are shown here.'**
  String get basketScreenExpectationBalances;

  /// No description provided for @basketScreenExpectationCreation.
  ///
  /// In en, this message translates to:
  /// **'New basket creation is currently disabled.'**
  String get basketScreenExpectationCreation;

  /// No description provided for @basketScreenExpectationLinks.
  ///
  /// In en, this message translates to:
  /// **'Existing deep links still land on this placeholder.'**
  String get basketScreenExpectationLinks;

  /// No description provided for @basketScreenBackHome.
  ///
  /// In en, this message translates to:
  /// **'Back Home'**
  String get basketScreenBackHome;
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
