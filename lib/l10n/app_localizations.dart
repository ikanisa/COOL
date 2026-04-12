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

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navProfile;

  /// No description provided for @navBiopay.
  ///
  /// In en, this message translates to:
  /// **'BioPay'**
  String get navBiopay;

  /// No description provided for @homeCommunitiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Communities'**
  String get homeCommunitiesTitle;

  /// No description provided for @homeCommunitiesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Communities failed to load.'**
  String get homeCommunitiesLoadFailed;

  /// No description provided for @homeNoCommunitiesYet.
  ///
  /// In en, this message translates to:
  /// **'No communities yet'**
  String get homeNoCommunitiesYet;

  /// No description provided for @homeCommunitiesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your groups will appear here.'**
  String get homeCommunitiesEmptySubtitle;

  /// No description provided for @homeCommunityFallbackName.
  ///
  /// In en, this message translates to:
  /// **'Community'**
  String get homeCommunityFallbackName;

  /// No description provided for @homeSavingsBalanceUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVINGS BALANCE'**
  String get homeSavingsBalanceUpper;

  /// No description provided for @homeQuickScanUpper.
  ///
  /// In en, this message translates to:
  /// **'SCAN'**
  String get homeQuickScanUpper;

  /// No description provided for @homeQuickBiopayLabel.
  ///
  /// In en, this message translates to:
  /// **'BioPay'**
  String get homeQuickBiopayLabel;

  /// No description provided for @homeOperationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get homeOperationsTitle;

  /// No description provided for @homeOperationsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Operations failed to load.'**
  String get homeOperationsLoadFailed;

  /// No description provided for @homeNoOperationsYet.
  ///
  /// In en, this message translates to:
  /// **'No operations yet'**
  String get homeNoOperationsYet;

  /// No description provided for @homeOperationsEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Incoming and outgoing transactions will appear here.'**
  String get homeOperationsEmptySubtitle;

  /// No description provided for @homeTransactionFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get homeTransactionFallbackTitle;

  /// No description provided for @homeOperationMetaToday.
  ///
  /// In en, this message translates to:
  /// **'TODAY, {time} • {type}'**
  String homeOperationMetaToday(String time, String type);

  /// No description provided for @homeOperationMetaYesterday.
  ///
  /// In en, this message translates to:
  /// **'YESTERDAY, {time} • {type}'**
  String homeOperationMetaYesterday(String time, String type);

  /// No description provided for @homeOperationMetaDate.
  ///
  /// In en, this message translates to:
  /// **'{date}, {time} • {type}'**
  String homeOperationMetaDate(String date, String time, String type);

  /// No description provided for @homeNoChangeThisMonthUpper.
  ///
  /// In en, this message translates to:
  /// **'NO CHANGE THIS MONTH'**
  String get homeNoChangeThisMonthUpper;

  /// No description provided for @homeThisMonthAmount.
  ///
  /// In en, this message translates to:
  /// **'THIS MONTH {amount} RWF'**
  String homeThisMonthAmount(String amount);

  /// No description provided for @homeMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 MEMBER} other{{count} MEMBERS}}'**
  String homeMemberCount(int count);

  /// No description provided for @homeOperationTransferUpper.
  ///
  /// In en, this message translates to:
  /// **'TRANSFER'**
  String get homeOperationTransferUpper;

  /// No description provided for @homeOperationReceivedUpper.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED'**
  String get homeOperationReceivedUpper;

  /// No description provided for @homeOperationSavingUpper.
  ///
  /// In en, this message translates to:
  /// **'SAVING'**
  String get homeOperationSavingUpper;

  /// No description provided for @homeOperationInterestUpper.
  ///
  /// In en, this message translates to:
  /// **'INTEREST'**
  String get homeOperationInterestUpper;

  /// No description provided for @homeOperationPayoutUpper.
  ///
  /// In en, this message translates to:
  /// **'PAYOUT'**
  String get homeOperationPayoutUpper;

  /// No description provided for @homeOperationActivityUpper.
  ///
  /// In en, this message translates to:
  /// **'ACTIVITY'**
  String get homeOperationActivityUpper;

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

  /// No description provided for @momoNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'MOMO Number'**
  String get momoNumberLabel;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @joinGroup.
  ///
  /// In en, this message translates to:
  /// **'Join Group'**
  String get joinGroup;

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

  /// No description provided for @memberCount.
  ///
  /// In en, this message translates to:
  /// **'{count} members'**
  String memberCount(Object count);

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

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @totalItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String totalItems(Object count);

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

  /// No description provided for @maintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get maintenance;

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

  /// No description provided for @membership.
  ///
  /// In en, this message translates to:
  /// **'Membership'**
  String get membership;

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

  /// No description provided for @cartItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String cartItemCount(Object count);

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

  /// No description provided for @weekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weekly;

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

  /// No description provided for @profileNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get profileNotLinked;

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

  /// No description provided for @partnersPartnerWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Partner Sports!'**
  String get partnersPartnerWelcomeTitle;

  /// No description provided for @partnersPartnerWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your fan membership has'**
  String get partnersPartnerWelcomeSubtitle;

  /// No description provided for @partnersOpenPartnerSports.
  ///
  /// In en, this message translates to:
  /// **'Open Partner Sports'**
  String get partnersOpenPartnerSports;

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

  /// No description provided for @partnersComingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'{partnerName} is coming soon!'**
  String partnersComingSoonMessage(Object partnerName);

  /// No description provided for @partnersPartnerHubBadge.
  ///
  /// In en, this message translates to:
  /// **'Official Fan Hub'**
  String get partnersPartnerHubBadge;

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

  /// No description provided for @profileSettingsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Settings unavailable'**
  String get profileSettingsUnavailable;

  /// No description provided for @profileAppAccessToggleFeatureAccess.
  ///
  /// In en, this message translates to:
  /// **'Toggle feature access'**
  String get profileAppAccessToggleFeatureAccess;

  /// No description provided for @profileOpenLabel.
  ///
  /// In en, this message translates to:
  /// **'Open {label}'**
  String profileOpenLabel(String label);

  /// No description provided for @profileSectionExpanded.
  ///
  /// In en, this message translates to:
  /// **'Expanded'**
  String get profileSectionExpanded;

  /// No description provided for @profileSectionCollapsed.
  ///
  /// In en, this message translates to:
  /// **'Collapsed'**
  String get profileSectionCollapsed;

  /// No description provided for @profileCollapseSection.
  ///
  /// In en, this message translates to:
  /// **'Collapse section'**
  String get profileCollapseSection;

  /// No description provided for @profileExpandSection.
  ///
  /// In en, this message translates to:
  /// **'Expand section'**
  String get profileExpandSection;

  /// No description provided for @profileMomoNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'MoMo number required'**
  String get profileMomoNumberRequired;

  /// No description provided for @profileMomoNumberIsRequired.
  ///
  /// In en, this message translates to:
  /// **'MoMo number is required'**
  String get profileMomoNumberIsRequired;

  /// No description provided for @profileMomoCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'MoMo code required'**
  String get profileMomoCodeRequired;

  /// No description provided for @profileEnterMomoNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter MoMo number'**
  String get profileEnterMomoNumber;

  /// No description provided for @profileEnterMerchantCode.
  ///
  /// In en, this message translates to:
  /// **'Enter merchant code'**
  String get profileEnterMerchantCode;

  /// No description provided for @profileDefaultReceiveRoute.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT RECEIVE ROUTE'**
  String get profileDefaultReceiveRoute;

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

  /// No description provided for @momoPay.
  ///
  /// In en, this message translates to:
  /// **'MoMo Pay'**
  String get momoPay;

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

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

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

  /// No description provided for @statusBadgeSemantics.
  ///
  /// In en, this message translates to:
  /// **'Status: {label}'**
  String statusBadgeSemantics(String label);

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

  /// No description provided for @allocateToMemberUpper.
  ///
  /// In en, this message translates to:
  /// **'ALLOCATE TO MEMBER'**
  String get allocateToMemberUpper;

  /// No description provided for @transactionAllocated.
  ///
  /// In en, this message translates to:
  /// **'Transaction allocated'**
  String get transactionAllocated;

  /// No description provided for @allocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Allocation failed'**
  String get allocationFailed;

  /// No description provided for @transactionUnallocated.
  ///
  /// In en, this message translates to:
  /// **'Transaction unallocated'**
  String get transactionUnallocated;

  /// No description provided for @unallocationFailed.
  ///
  /// In en, this message translates to:
  /// **'Unallocation failed'**
  String get unallocationFailed;

  /// No description provided for @transactionAllocationUpper.
  ///
  /// In en, this message translates to:
  /// **'TRANSACTION ALLOCATION'**
  String get transactionAllocationUpper;

  /// No description provided for @manageGroupMemberAssignment.
  ///
  /// In en, this message translates to:
  /// **'Manage group member assignment'**
  String get manageGroupMemberAssignment;

  /// No description provided for @notYetAllocated.
  ///
  /// In en, this message translates to:
  /// **'Not yet allocated'**
  String get notYetAllocated;

  /// No description provided for @unallocateUpper.
  ///
  /// In en, this message translates to:
  /// **'UNALLOCATE'**
  String get unallocateUpper;

  /// No description provided for @orReallocateToAnotherMember.
  ///
  /// In en, this message translates to:
  /// **'OR REALLOCATE TO ANOTHER MEMBER'**
  String get orReallocateToAnotherMember;

  /// No description provided for @noGroupMembersFound.
  ///
  /// In en, this message translates to:
  /// **'No group members found.'**
  String get noGroupMembersFound;

  /// No description provided for @selectMember.
  ///
  /// In en, this message translates to:
  /// **'Select member:'**
  String get selectMember;

  /// No description provided for @currentUpper.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get currentUpper;

  /// No description provided for @confirmReallocationUpper.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM REALLOCATION'**
  String get confirmReallocationUpper;

  /// No description provided for @confirmAllocationUpper.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM ALLOCATION'**
  String get confirmAllocationUpper;

  /// No description provided for @shareQrButton.
  ///
  /// In en, this message translates to:
  /// **'QR / Share'**
  String get shareQrButton;

  /// No description provided for @selectAContactToShareWith.
  ///
  /// In en, this message translates to:
  /// **'Select a contact to share with'**
  String get selectAContactToShareWith;

  /// No description provided for @postedUpper.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED'**
  String get postedUpper;

  /// No description provided for @confirmedUpper.
  ///
  /// In en, this message translates to:
  /// **'RECEIVED'**
  String get confirmedUpper;

  /// No description provided for @draftUpper.
  ///
  /// In en, this message translates to:
  /// **'DRAFT'**
  String get draftUpper;

  /// No description provided for @reviewUpper.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get reviewUpper;

  /// No description provided for @manualUpper.
  ///
  /// In en, this message translates to:
  /// **'MANUAL'**
  String get manualUpper;

  /// No description provided for @suggestedUpper.
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED'**
  String get suggestedUpper;

  /// No description provided for @rejectedUpper.
  ///
  /// In en, this message translates to:
  /// **'DECLINED'**
  String get rejectedUpper;

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

  /// No description provided for @number.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get number;

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

  /// No description provided for @momo.
  ///
  /// In en, this message translates to:
  /// **'MoMo'**
  String get momo;

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

  /// No description provided for @partner.
  ///
  /// In en, this message translates to:
  /// **'Partner'**
  String get partner;

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

  /// No description provided for @openPartnerSportsAdmin.
  ///
  /// In en, this message translates to:
  /// **'Open Partner Sports Admin'**
  String get openPartnerSportsAdmin;

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

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

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

  /// No description provided for @profileSmsSyncOptIn.
  ///
  /// In en, this message translates to:
  /// **'SMS sync opt-in'**
  String get profileSmsSyncOptIn;

  /// No description provided for @profileSmsSyncOptInMessage.
  ///
  /// In en, this message translates to:
  /// **'Android only. COOL checks approved M-Money sender IDs, imports matching confirmations, and ignores other SMS.'**
  String get profileSmsSyncOptInMessage;

  /// No description provided for @profileSmsPaymentSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'SMS Payment Sync'**
  String get profileSmsPaymentSyncTitle;

  /// No description provided for @profileSmsPaymentSyncSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Optional on Android. Watches approved M-Money sender IDs, imports matching confirmations, and auto-verifies supported payment flows.'**
  String get profileSmsPaymentSyncSubtitle;

  /// No description provided for @profileAccessFeature12MonthImport.
  ///
  /// In en, this message translates to:
  /// **'12-month import'**
  String get profileAccessFeature12MonthImport;

  /// No description provided for @profileAccessFeatureMomoVerification.
  ///
  /// In en, this message translates to:
  /// **'MoMo verification'**
  String get profileAccessFeatureMomoVerification;

  /// No description provided for @profileLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used for nearby services and place-aware flows'**
  String get profileLocationSubtitle;

  /// No description provided for @profileAccessFeatureNearbyServices.
  ///
  /// In en, this message translates to:
  /// **'Nearby services'**
  String get profileAccessFeatureNearbyServices;

  /// No description provided for @profileAccessFeaturePartnerDiscovery.
  ///
  /// In en, this message translates to:
  /// **'Partner discovery'**
  String get profileAccessFeaturePartnerDiscovery;

  /// No description provided for @profileAccessFeatureMapContext.
  ///
  /// In en, this message translates to:
  /// **'Map context'**
  String get profileAccessFeatureMapContext;

  /// No description provided for @profileCameraSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used for MoMo QR'**
  String get profileCameraSubtitle;

  /// No description provided for @profileAccessFeatureMomoQrScan.
  ///
  /// In en, this message translates to:
  /// **'MoMo QR scan'**
  String get profileAccessFeatureMomoQrScan;

  /// No description provided for @profileContactsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Used when inviting group'**
  String get profileContactsSubtitle;

  /// No description provided for @profileAccessFeatureGroupInvites.
  ///
  /// In en, this message translates to:
  /// **'Group invites'**
  String get profileAccessFeatureGroupInvites;

  /// No description provided for @profileAccessFeatureShareViaContacts.
  ///
  /// In en, this message translates to:
  /// **'Share via contacts'**
  String get profileAccessFeatureShareViaContacts;

  /// No description provided for @profileNotificationsNeedsSystemAccess.
  ///
  /// In en, this message translates to:
  /// **'Needs system access'**
  String get profileNotificationsNeedsSystemAccess;

  /// No description provided for @profileAccessFeatureMomoUpdates.
  ///
  /// In en, this message translates to:
  /// **'MoMo updates'**
  String get profileAccessFeatureMomoUpdates;

  /// No description provided for @profileAccessFeatureGroupsActivity.
  ///
  /// In en, this message translates to:
  /// **'Groups activity'**
  String get profileAccessFeatureGroupsActivity;

  /// No description provided for @profileAccessFeatureServiceUpdates.
  ///
  /// In en, this message translates to:
  /// **'Service updates'**
  String get profileAccessFeatureServiceUpdates;

  /// No description provided for @profileAccessFeaturePartnerAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'Partner announcements'**
  String get profileAccessFeaturePartnerAnnouncements;

  /// No description provided for @profileOpenLocationSettings.
  ///
  /// In en, this message translates to:
  /// **'Open location settings'**
  String get profileOpenLocationSettings;

  /// No description provided for @profileNfcSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Controls NFC receive/read flows'**
  String get profileNfcSubtitle;

  /// No description provided for @profileAccessFeatureMomoReceiveTap.
  ///
  /// In en, this message translates to:
  /// **'MoMo receive tap'**
  String get profileAccessFeatureMomoReceiveTap;

  /// No description provided for @profileAccessFeatureNfcPaymentTags.
  ///
  /// In en, this message translates to:
  /// **'NFC payment tags'**
  String get profileAccessFeatureNfcPaymentTags;

  /// No description provided for @profileOpenNfcSettings.
  ///
  /// In en, this message translates to:
  /// **'Open NFC settings'**
  String get profileOpenNfcSettings;

  /// No description provided for @profilePhotosMediaTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos & Media'**
  String get profilePhotosMediaTitle;

  /// No description provided for @profilePhotosMediaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose profile photos and upload documents from gallery.'**
  String get profilePhotosMediaSubtitle;

  /// No description provided for @profileAccessFeatureProfilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profileAccessFeatureProfilePhoto;

  /// No description provided for @profileAccessFeatureDocumentUpload.
  ///
  /// In en, this message translates to:
  /// **'Document upload'**
  String get profileAccessFeatureDocumentUpload;

  /// No description provided for @profileServiceOff.
  ///
  /// In en, this message translates to:
  /// **'Service off'**
  String get profileServiceOff;

  /// No description provided for @profileAppAccessReadyCount.
  ///
  /// In en, this message translates to:
  /// **'{readyCount}/{totalCount} ready'**
  String profileAppAccessReadyCount(int readyCount, int totalCount);

  /// No description provided for @profileAppAccessAllControls.
  ///
  /// In en, this message translates to:
  /// **'All access controls'**
  String get profileAppAccessAllControls;

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

  /// No description provided for @standardMembership.
  ///
  /// In en, this message translates to:
  /// **'Standard membership'**
  String get standardMembership;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'products'**
  String get products;

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

  /// No description provided for @partnerSports.
  ///
  /// In en, this message translates to:
  /// **'Partner Sports'**
  String get partnerSports;

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

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

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

  /// No description provided for @searchMembers.
  ///
  /// In en, this message translates to:
  /// **'Search members'**
  String get searchMembers;

  /// No description provided for @points1.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get points1;

  /// No description provided for @memberCsvCopiedTo.
  ///
  /// In en, this message translates to:
  /// **'Member CSV copied to clipboard'**
  String get memberCsvCopiedTo;

  /// No description provided for @scheduleFixturesAdjustPricing.
  ///
  /// In en, this message translates to:
  /// **'Schedule fixtures adjust pricing'**
  String get scheduleFixturesAdjustPricing;

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

  /// No description provided for @vipEvents.
  ///
  /// In en, this message translates to:
  /// **'VIP Events'**
  String get vipEvents;

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

  /// No description provided for @managePartnerPaymentRouting.
  ///
  /// In en, this message translates to:
  /// **'Manage Partner payment routing'**
  String get managePartnerPaymentRouting;

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

  /// No description provided for @inviteSupportersToBuy.
  ///
  /// In en, this message translates to:
  /// **'Invite supporters to buy'**
  String get inviteSupportersToBuy;

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

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @memberId.
  ///
  /// In en, this message translates to:
  /// **'Member ID'**
  String get memberId;

  /// No description provided for @points2.
  ///
  /// In en, this message translates to:
  /// **'Points'**
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

  /// No description provided for @contactPickerInviteFromContacts.
  ///
  /// In en, this message translates to:
  /// **'Invite from Contacts'**
  String get contactPickerInviteFromContacts;

  /// No description provided for @contactPickerSearchNameOrPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Search name or phone'**
  String get contactPickerSearchNameOrPhoneHint;

  /// No description provided for @contactPickerSearchByNameOrPhone.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone'**
  String get contactPickerSearchByNameOrPhone;

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

  /// No description provided for @contactPickerCouldNotLoadContacts.
  ///
  /// In en, this message translates to:
  /// **'Could not load contacts.'**
  String get contactPickerCouldNotLoadContacts;

  /// No description provided for @contactPickerCouldNotOpenContactsSettings.
  ///
  /// In en, this message translates to:
  /// **'Could not open contacts settings.'**
  String get contactPickerCouldNotOpenContactsSettings;

  /// No description provided for @contactPickerDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve permanently denied contacts'**
  String get contactPickerDeniedMessage;

  /// No description provided for @contactPickerAccessCurrentlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Contacts access is currently'**
  String get contactPickerAccessCurrentlyMessage;

  /// No description provided for @contactPickerEnableContacts.
  ///
  /// In en, this message translates to:
  /// **'Enable Contacts'**
  String get contactPickerEnableContacts;

  /// No description provided for @contactPickerNeedsAccessMessage.
  ///
  /// In en, this message translates to:
  /// **'Cool needs access to'**
  String get contactPickerNeedsAccessMessage;

  /// No description provided for @contactPickerNoContactsMatch.
  ///
  /// In en, this message translates to:
  /// **'No contacts match \"{query}\"'**
  String contactPickerNoContactsMatch(String query);

  /// No description provided for @contactPickerNoContactsWithPhones.
  ///
  /// In en, this message translates to:
  /// **'No contacts with phone numbers found.'**
  String get contactPickerNoContactsWithPhones;

  /// No description provided for @contactPickerDoneCount.
  ///
  /// In en, this message translates to:
  /// **'Done ({count})'**
  String contactPickerDoneCount(int count);

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
  /// **'+50 Points'**
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
  /// **'Rewards & Activities'**
  String get seasonsAndActivities;

  /// No description provided for @activeSeasons.
  ///
  /// In en, this message translates to:
  /// **'Active Reward Seasons'**
  String get activeSeasons;

  /// No description provided for @pastSeasons.
  ///
  /// In en, this message translates to:
  /// **'Past Reward Seasons'**
  String get pastSeasons;

  /// No description provided for @seasonEarnTokensSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Earn points by completing activities during each reward season'**
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
  /// **'Reward-earning seasonal activities'**
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
  /// **'Open a platform or bank workspace as support'**
  String get adminSupportModeDesc;

  /// No description provided for @adminSupportModeHint.
  ///
  /// In en, this message translates to:
  /// **'Navigate into a bank workspace or platform control surface to manage it as support.'**
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

  /// No description provided for @rsAdminNoOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get rsAdminNoOrders;

  /// No description provided for @profileWhatsAppLaunchError.
  ///
  /// In en, this message translates to:
  /// **'Could not open WhatsApp'**
  String get profileWhatsAppLaunchError;

  /// No description provided for @profileFaceIdComingSoon.
  ///
  /// In en, this message translates to:
  /// **'COMING SOON'**
  String get profileFaceIdComingSoon;

  /// No description provided for @profileFaceIdRegistered.
  ///
  /// In en, this message translates to:
  /// **'REGISTERED - {value}'**
  String profileFaceIdRegistered(String value);

  /// No description provided for @profileFaceIdScanToPay.
  ///
  /// In en, this message translates to:
  /// **'SCAN YOUR FACE TO PAY'**
  String get profileFaceIdScanToPay;

  /// No description provided for @profileFaceIdCheckingStatus.
  ///
  /// In en, this message translates to:
  /// **'CHECKING FACE ID STATUS'**
  String get profileFaceIdCheckingStatus;

  /// No description provided for @profileIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'IDENTITY'**
  String get profileIdentityTitle;

  /// No description provided for @profileAppSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'APP SETTINGS'**
  String get profileAppSettingsSection;

  /// No description provided for @profileAccountDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT DETAILS'**
  String get profileAccountDetailsTitle;

  /// No description provided for @profilePersonalInformationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'PERSONAL INFORMATION'**
  String get profilePersonalInformationSubtitle;

  /// No description provided for @profileWalletMomoTitle.
  ///
  /// In en, this message translates to:
  /// **'WALLET & MOMO'**
  String get profileWalletMomoTitle;

  /// No description provided for @profileSetupDefaultMomoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SET UP YOUR DEFAULT MOMO'**
  String get profileSetupDefaultMomoSubtitle;

  /// No description provided for @profileTransactionHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'TRANSACTION HISTORY'**
  String get profileTransactionHistoryTitle;

  /// No description provided for @profileStatementsLedgerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'M-MONEY STATEMENTS & LEDGER'**
  String get profileStatementsLedgerSubtitle;

  /// No description provided for @profileFaceIdRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'FACE ID REGISTER'**
  String get profileFaceIdRegisterTitle;

  /// No description provided for @profileSupportSection.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT'**
  String get profileSupportSection;

  /// No description provided for @profileAdminWorkspaceTitle.
  ///
  /// In en, this message translates to:
  /// **'ADMIN WORKSPACE'**
  String get profileAdminWorkspaceTitle;

  /// No description provided for @profileSystemManagementSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM MANAGEMENT'**
  String get profileSystemManagementSubtitle;

  /// No description provided for @profileHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'HELP'**
  String get profileHelpTitle;

  /// No description provided for @profileChatOnWhatsAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'CHAT ON WHATSAPP'**
  String get profileChatOnWhatsAppSubtitle;

  /// No description provided for @profileLogoutTitle.
  ///
  /// In en, this message translates to:
  /// **'LOGOUT'**
  String get profileLogoutTitle;

  /// No description provided for @otpEnterAllDigits.
  ///
  /// In en, this message translates to:
  /// **'Enter all 6 digits'**
  String get otpEnterAllDigits;

  /// No description provided for @otpSessionOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Phone was verified, but the app could not open your session.'**
  String get otpSessionOpenFailed;

  /// No description provided for @otpPhoneVerified.
  ///
  /// In en, this message translates to:
  /// **'Phone verified!'**
  String get otpPhoneVerified;

  /// No description provided for @otpEnterWhatsappNumberTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter WhatsApp\nNumber'**
  String get otpEnterWhatsappNumberTitle;

  /// No description provided for @otpEnterWhatsappNumberSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter WhatsApp number to receive OTP'**
  String get otpEnterWhatsappNumberSubtitle;

  /// No description provided for @otpPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'788 123 456'**
  String get otpPhoneHint;

  /// No description provided for @otpSendCodeUpper.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get otpSendCodeUpper;

  /// No description provided for @otpVerifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get otpVerifyTitle;

  /// No description provided for @otpVerifySubtitlePrefix.
  ///
  /// In en, this message translates to:
  /// **'We sent a 6-digit OTP to your WhatsApp at '**
  String get otpVerifySubtitlePrefix;

  /// No description provided for @otpVerifyButtonUpper.
  ///
  /// In en, this message translates to:
  /// **'VERIFY'**
  String get otpVerifyButtonUpper;

  /// No description provided for @biopayHomeHeadline.
  ///
  /// In en, this message translates to:
  /// **'Pay & Get Paid\nInstantly'**
  String get biopayHomeHeadline;

  /// No description provided for @biopayFaceScanLabel.
  ///
  /// In en, this message translates to:
  /// **'Face Scan'**
  String get biopayFaceScanLabel;

  /// No description provided for @biopayNfcTapLabel.
  ///
  /// In en, this message translates to:
  /// **'NFC Tap'**
  String get biopayNfcTapLabel;

  /// No description provided for @biopayTabNumber.
  ///
  /// In en, this message translates to:
  /// **'Number'**
  String get biopayTabNumber;

  /// No description provided for @biopayTabCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get biopayTabCode;

  /// No description provided for @biopayMomoNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'MoMo Number'**
  String get biopayMomoNumberLabel;

  /// No description provided for @biopayAmountOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (Optional)'**
  String get biopayAmountOptionalLabel;

  /// No description provided for @biopayZeroAmountHint.
  ///
  /// In en, this message translates to:
  /// **'0'**
  String get biopayZeroAmountHint;

  /// No description provided for @biopayEnterMerchantCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a merchant code'**
  String get biopayEnterMerchantCode;

  /// No description provided for @biopayEnterMomoNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a MoMo number'**
  String get biopayEnterMomoNumber;

  /// No description provided for @biopayProfileUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile unavailable'**
  String get biopayProfileUnavailableTitle;

  /// No description provided for @biopayProfileUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'BioPay could not load your linked details right now.'**
  String get biopayProfileUnavailableMessage;

  /// No description provided for @biopayTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get biopayTryAgain;

  /// No description provided for @biopayCompleteEnrollmentMessage.
  ///
  /// In en, this message translates to:
  /// **'Complete Face ID enrollment from Settings to pay with BioPay.'**
  String get biopayCompleteEnrollmentMessage;

  /// No description provided for @biopayNotLinked.
  ///
  /// In en, this message translates to:
  /// **'Not Linked'**
  String get biopayNotLinked;

  /// No description provided for @biopayNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Not Added'**
  String get biopayNotAdded;

  /// No description provided for @biopayIdLabel.
  ///
  /// In en, this message translates to:
  /// **'BioPay ID'**
  String get biopayIdLabel;

  /// No description provided for @biopayFaceIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Face ID'**
  String get biopayFaceIdLabel;

  /// No description provided for @biopayFaceIdNotSetUp.
  ///
  /// In en, this message translates to:
  /// **'Not set up'**
  String get biopayFaceIdNotSetUp;

  /// No description provided for @biopayFaceIdSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Face ID Setup'**
  String get biopayFaceIdSetupTitle;

  /// No description provided for @biopayRegisterHeadline.
  ///
  /// In en, this message translates to:
  /// **'Link your face\nto your MoMo.'**
  String get biopayRegisterHeadline;

  /// No description provided for @biopayFaceIdAlreadyLinkedNotice.
  ///
  /// In en, this message translates to:
  /// **'Face ID already linked. A new scan will replace it.'**
  String get biopayFaceIdAlreadyLinkedNotice;

  /// No description provided for @biopayUpdateEnrollment.
  ///
  /// In en, this message translates to:
  /// **'Update Enrollment'**
  String get biopayUpdateEnrollment;

  /// No description provided for @biopayStartEnrollment.
  ///
  /// In en, this message translates to:
  /// **'Start Enrollment'**
  String get biopayStartEnrollment;

  /// No description provided for @biopaySecureSessionError.
  ///
  /// In en, this message translates to:
  /// **'BioPay could not open a secure session.'**
  String get biopaySecureSessionError;

  /// No description provided for @biopayUserDisplayName.
  ///
  /// In en, this message translates to:
  /// **'BioPay User'**
  String get biopayUserDisplayName;

  /// No description provided for @biopayGetQrCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Get QR Code'**
  String get biopayGetQrCodeTitle;

  /// No description provided for @biopayGenerateQrCode.
  ///
  /// In en, this message translates to:
  /// **'Generate QR Code'**
  String get biopayGenerateQrCode;

  /// No description provided for @biopayQrReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'BioPay QR Ready'**
  String get biopayQrReadyTitle;

  /// No description provided for @doneUpper.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get doneUpper;

  /// No description provided for @biopayNfcPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'NFC Payment'**
  String get biopayNfcPaymentTitle;

  /// No description provided for @biopayNfcOffInApp.
  ///
  /// In en, this message translates to:
  /// **'NFC is off in the app. Tap activate and BioPay will request access.'**
  String get biopayNfcOffInApp;

  /// No description provided for @biopayTurnOnNfcInSettings.
  ///
  /// In en, this message translates to:
  /// **'Turn on NFC in system settings to continue.'**
  String get biopayTurnOnNfcInSettings;

  /// No description provided for @biopayNfcUnavailableOnDevice.
  ///
  /// In en, this message translates to:
  /// **'NFC is not available on this device.'**
  String get biopayNfcUnavailableOnDevice;

  /// No description provided for @biopayNfcReadyForNextTap.
  ///
  /// In en, this message translates to:
  /// **'NFC is active and ready for the next tap.'**
  String get biopayNfcReadyForNextTap;

  /// No description provided for @biopayNfcNotAvailableButton.
  ///
  /// In en, this message translates to:
  /// **'NFC Not Available'**
  String get biopayNfcNotAvailableButton;

  /// No description provided for @biopayActivateNfc.
  ///
  /// In en, this message translates to:
  /// **'Activate NFC'**
  String get biopayActivateNfc;

  /// No description provided for @biopayStopNfc.
  ///
  /// In en, this message translates to:
  /// **'Stop NFC'**
  String get biopayStopNfc;

  /// No description provided for @biopayNfcStopped.
  ///
  /// In en, this message translates to:
  /// **'BioPay NFC stopped.'**
  String get biopayNfcStopped;

  /// No description provided for @biopayNfcActivationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'NFC activation is not available here.'**
  String get biopayNfcActivationUnavailable;

  /// No description provided for @groupCreateProfileMissing.
  ///
  /// In en, this message translates to:
  /// **'Verification completed but profile missing.'**
  String get groupCreateProfileMissing;

  /// No description provided for @groupNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a group name.'**
  String get groupNameRequired;

  /// No description provided for @groupNameTooShort.
  ///
  /// In en, this message translates to:
  /// **'At least 3 characters.'**
  String get groupNameTooShort;

  /// No description provided for @groupNameMinimumThreeCharacters.
  ///
  /// In en, this message translates to:
  /// **'Use at least 3 characters.'**
  String get groupNameMinimumThreeCharacters;

  /// No description provided for @groupDescriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get groupDescriptionOptionalLabel;

  /// No description provided for @groupDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'What is this group for?'**
  String get groupDescriptionHint;

  /// No description provided for @groupTypeSection.
  ///
  /// In en, this message translates to:
  /// **'TYPE'**
  String get groupTypeSection;

  /// No description provided for @groupFrequencySection.
  ///
  /// In en, this message translates to:
  /// **'FREQUENCY'**
  String get groupFrequencySection;

  /// No description provided for @groupDailyLower.
  ///
  /// In en, this message translates to:
  /// **'daily'**
  String get groupDailyLower;

  /// No description provided for @groupWeeklyLower.
  ///
  /// In en, this message translates to:
  /// **'weekly'**
  String get groupWeeklyLower;

  /// No description provided for @groupMonthlyLower.
  ///
  /// In en, this message translates to:
  /// **'monthly'**
  String get groupMonthlyLower;

  /// No description provided for @oneOff.
  ///
  /// In en, this message translates to:
  /// **'One-Off'**
  String get oneOff;

  /// No description provided for @groupTargetLabel.
  ///
  /// In en, this message translates to:
  /// **'Target ({currency})'**
  String groupTargetLabel(String currency);

  /// No description provided for @groupSettingsTargetAmountOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Target Amount — {currency} (optional)'**
  String groupSettingsTargetAmountOptionalLabel(String currency);

  /// No description provided for @groupContributionLabel.
  ///
  /// In en, this message translates to:
  /// **'Contribution ({currency})'**
  String groupContributionLabel(String currency);

  /// No description provided for @groupSettingsContributionAmountOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Contribution Amount — {currency} (optional)'**
  String groupSettingsContributionAmountOptionalLabel(String currency);

  /// No description provided for @groupTargetHint.
  ///
  /// In en, this message translates to:
  /// **'500,000'**
  String get groupTargetHint;

  /// No description provided for @groupSettingsTargetAmountHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 500,000'**
  String get groupSettingsTargetAmountHint;

  /// No description provided for @groupContributionHint.
  ///
  /// In en, this message translates to:
  /// **'10,000'**
  String get groupContributionHint;

  /// No description provided for @groupSettingsContributionAmountHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 10,000'**
  String get groupSettingsContributionAmountHint;

  /// No description provided for @groupCreateGroupUpper.
  ///
  /// In en, this message translates to:
  /// **'CREATE GROUP'**
  String get groupCreateGroupUpper;

  /// No description provided for @groupsPaymentRoutePendingInfo.
  ///
  /// In en, this message translates to:
  /// **'This group has no payment route configured yet.'**
  String get groupsPaymentRoutePendingInfo;

  /// No description provided for @groupsLaunchMomoUssdError.
  ///
  /// In en, this message translates to:
  /// **'Could not launch MoMo payment. Try dialing *182*8*1# manually to send your contribution.'**
  String get groupsLaunchMomoUssdError;

  /// No description provided for @groupsCreateUpper.
  ///
  /// In en, this message translates to:
  /// **'CREATE'**
  String get groupsCreateUpper;

  /// No description provided for @groupsMyLedgers.
  ///
  /// In en, this message translates to:
  /// **'My Ledgers'**
  String get groupsMyLedgers;

  /// No description provided for @groupsExplore.
  ///
  /// In en, this message translates to:
  /// **'Explore'**
  String get groupsExplore;

  /// No description provided for @groupsInviteNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite not found'**
  String get groupsInviteNotFoundTitle;

  /// No description provided for @groupsInviteNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This invite code is not active.'**
  String get groupsInviteNotFoundMessage;

  /// No description provided for @groupsAlreadyMember.
  ///
  /// In en, this message translates to:
  /// **'Already a member.'**
  String get groupsAlreadyMember;

  /// No description provided for @groupsDismissUpper.
  ///
  /// In en, this message translates to:
  /// **'DISMISS'**
  String get groupsDismissUpper;

  /// No description provided for @groupsOpenUpper.
  ///
  /// In en, this message translates to:
  /// **'OPEN'**
  String get groupsOpenUpper;

  /// No description provided for @groupsJoinNowUpper.
  ///
  /// In en, this message translates to:
  /// **'JOIN NOW'**
  String get groupsJoinNowUpper;

  /// No description provided for @groupsInviteErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite error'**
  String get groupsInviteErrorTitle;

  /// No description provided for @groupsNoGroupsYetTitle.
  ///
  /// In en, this message translates to:
  /// **'No groups yet'**
  String get groupsNoGroupsYetTitle;

  /// No description provided for @groupsNoGroupsYetMessage.
  ///
  /// In en, this message translates to:
  /// **'Create your first group or join a public one.'**
  String get groupsNoGroupsYetMessage;

  /// No description provided for @groupsTapToRetry.
  ///
  /// In en, this message translates to:
  /// **'TAP TO RETRY'**
  String get groupsTapToRetry;

  /// No description provided for @groupsJoinUpper.
  ///
  /// In en, this message translates to:
  /// **'JOIN'**
  String get groupsJoinUpper;

  /// No description provided for @groupsLiveUpper.
  ///
  /// In en, this message translates to:
  /// **'LIVE'**
  String get groupsLiveUpper;

  /// No description provided for @groupsViewAllStatementsUpper.
  ///
  /// In en, this message translates to:
  /// **'VIEW ALL STATEMENTS'**
  String get groupsViewAllStatementsUpper;

  /// No description provided for @groupsContributeWithMomoUpper.
  ///
  /// In en, this message translates to:
  /// **'CONTRIBUTE WITH MOMO'**
  String get groupsContributeWithMomoUpper;

  /// No description provided for @groupsContributionRoutePendingUpper.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT SETUP IN PROGRESS'**
  String get groupsContributionRoutePendingUpper;

  /// No description provided for @groupsRoutePendingHint.
  ///
  /// In en, this message translates to:
  /// **'The admin is setting up this group\'s MoMo route. Contribute after confirmation.'**
  String get groupsRoutePendingHint;

  /// No description provided for @groupsJoinGroupUpper.
  ///
  /// In en, this message translates to:
  /// **'JOIN GROUP'**
  String get groupsJoinGroupUpper;

  /// No description provided for @groupsInviteOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'This group is invite-only.'**
  String get groupsInviteOnlyMessage;

  /// No description provided for @groupsInviteShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Share the invite link with your members.'**
  String get groupsInviteShareSubtitle;

  /// No description provided for @groupsNoPostedContributionsYet.
  ///
  /// In en, this message translates to:
  /// **'No posted contributions yet.'**
  String get groupsNoPostedContributionsYet;

  /// No description provided for @groupsNoMembersYet.
  ///
  /// In en, this message translates to:
  /// **'No members yet.'**
  String get groupsNoMembersYet;

  /// No description provided for @groupsAnonymousMember.
  ///
  /// In en, this message translates to:
  /// **'Anonymous member'**
  String get groupsAnonymousMember;

  /// No description provided for @groupsCouldNotLoadMembers.
  ///
  /// In en, this message translates to:
  /// **'Could not load members right now.'**
  String get groupsCouldNotLoadMembers;

  /// No description provided for @groupsCouldNotLoadLedger.
  ///
  /// In en, this message translates to:
  /// **'Could not load the ledger.'**
  String get groupsCouldNotLoadLedger;

  /// No description provided for @groupPaymentLedgerTitle.
  ///
  /// In en, this message translates to:
  /// **'Group Payment Ledger'**
  String get groupPaymentLedgerTitle;

  /// No description provided for @groupPaymentLedgerFileStem.
  ///
  /// In en, this message translates to:
  /// **'cool_group_payment_ledger'**
  String get groupPaymentLedgerFileStem;

  /// No description provided for @groupStatementsCoolUser.
  ///
  /// In en, this message translates to:
  /// **'COOL User'**
  String get groupStatementsCoolUser;

  /// No description provided for @groupStatementsAllPostedEntriesInView.
  ///
  /// In en, this message translates to:
  /// **'All posted entries in view'**
  String get groupStatementsAllPostedEntriesInView;

  /// No description provided for @groupStatementsTitleUpper.
  ///
  /// In en, this message translates to:
  /// **'STATEMENTS'**
  String get groupStatementsTitleUpper;

  /// No description provided for @groupStatementsGroupLedgerUpper.
  ///
  /// In en, this message translates to:
  /// **'GROUP LEDGER'**
  String get groupStatementsGroupLedgerUpper;

  /// No description provided for @groupStatementsLoadingUpper.
  ///
  /// In en, this message translates to:
  /// **'LOADING'**
  String get groupStatementsLoadingUpper;

  /// No description provided for @groupStatementsLedgerExported.
  ///
  /// In en, this message translates to:
  /// **'Ledger exported'**
  String get groupStatementsLedgerExported;

  /// No description provided for @groupStatementsNoTransactionsYetUpper.
  ///
  /// In en, this message translates to:
  /// **'NO TRANSACTIONS YET'**
  String get groupStatementsNoTransactionsYetUpper;

  /// No description provided for @groupStatementsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Contributions will appear here as members make payments to this group.'**
  String get groupStatementsEmptyMessage;

  /// No description provided for @qrShareSheetSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR or share the link'**
  String get qrShareSheetSubtitle;

  /// No description provided for @whatsappNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp is not available'**
  String get whatsappNotAvailable;

  /// No description provided for @scanMomoQr.
  ///
  /// In en, this message translates to:
  /// **'Scan MoMo QR'**
  String get scanMomoQr;

  /// No description provided for @cameraIsOff.
  ///
  /// In en, this message translates to:
  /// **'Camera is off'**
  String get cameraIsOff;

  /// No description provided for @enableCameraAccessToScan.
  ///
  /// In en, this message translates to:
  /// **'Enable camera access to scan.'**
  String get enableCameraAccessToScan;

  /// No description provided for @enableCamera.
  ///
  /// In en, this message translates to:
  /// **'Enable Camera'**
  String get enableCamera;

  /// No description provided for @cameraIsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Camera is blocked'**
  String get cameraIsBlocked;

  /// No description provided for @openSystemSettingsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Open system settings.'**
  String get openSystemSettingsPeriod;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable'**
  String get cameraUnavailable;

  /// No description provided for @deviceCannotScan.
  ///
  /// In en, this message translates to:
  /// **'This device cannot scan.'**
  String get deviceCannotScan;

  /// No description provided for @cameraAccessRequired.
  ///
  /// In en, this message translates to:
  /// **'Camera access is required.'**
  String get cameraAccessRequired;

  /// No description provided for @allowCamera.
  ///
  /// In en, this message translates to:
  /// **'Allow Camera'**
  String get allowCamera;

  /// No description provided for @bootstrapCoolTitle.
  ///
  /// In en, this message translates to:
  /// **'COOL'**
  String get bootstrapCoolTitle;

  /// No description provided for @bootstrapStartupBlocked.
  ///
  /// In en, this message translates to:
  /// **'Startup blocked'**
  String get bootstrapStartupBlocked;

  /// No description provided for @bootstrapRetryStartup.
  ///
  /// In en, this message translates to:
  /// **'Retry startup'**
  String get bootstrapRetryStartup;

  /// No description provided for @bootstrapBackendConfigurationRequired.
  ///
  /// In en, this message translates to:
  /// **'Backend configuration required'**
  String get bootstrapBackendConfigurationRequired;

  /// No description provided for @bootstrapLocalRunsNeedEnv.
  ///
  /// In en, this message translates to:
  /// **'Local runs usually need --dart-define-from-file=.env.json'**
  String get bootstrapLocalRunsNeedEnv;

  /// No description provided for @bootstrapStartingApp.
  ///
  /// In en, this message translates to:
  /// **'Starting app'**
  String get bootstrapStartingApp;

  /// No description provided for @bootstrapInitializingFirebase.
  ///
  /// In en, this message translates to:
  /// **'Initializing Firebase'**
  String get bootstrapInitializingFirebase;

  /// No description provided for @bootstrapRecordingRuntimeBackendContract.
  ///
  /// In en, this message translates to:
  /// **'Recording runtime backend contract'**
  String get bootstrapRecordingRuntimeBackendContract;

  /// No description provided for @bootstrapActivatingDeviceAttestation.
  ///
  /// In en, this message translates to:
  /// **'Activating device attestation'**
  String get bootstrapActivatingDeviceAttestation;

  /// No description provided for @bootstrapStartingColdStartTrace.
  ///
  /// In en, this message translates to:
  /// **'Starting cold-start trace'**
  String get bootstrapStartingColdStartTrace;

  /// No description provided for @bootstrapApplyingDeviceOrientation.
  ///
  /// In en, this message translates to:
  /// **'Applying device orientation'**
  String get bootstrapApplyingDeviceOrientation;

  /// No description provided for @bootstrapConnectingBackend.
  ///
  /// In en, this message translates to:
  /// **'Connecting backend'**
  String get bootstrapConnectingBackend;

  /// No description provided for @bootstrapPreparingLocalStorage.
  ///
  /// In en, this message translates to:
  /// **'Preparing local storage'**
  String get bootstrapPreparingLocalStorage;

  /// No description provided for @bootstrapLoadingThemePreference.
  ///
  /// In en, this message translates to:
  /// **'Loading theme preference'**
  String get bootstrapLoadingThemePreference;

  /// No description provided for @bootstrapPreparingYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Preparing your account'**
  String get bootstrapPreparingYourAccount;

  /// No description provided for @bootstrapNeverReachedFirstFrame.
  ///
  /// In en, this message translates to:
  /// **'The app never reached the first frame.'**
  String get bootstrapNeverReachedFirstFrame;

  /// No description provided for @bootstrapSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get bootstrapSomethingWentWrong;

  /// No description provided for @bootstrapPleaseRestartApp.
  ///
  /// In en, this message translates to:
  /// **'Please restart the app.'**
  String get bootstrapPleaseRestartApp;

  /// No description provided for @bootstrapFailedWhile.
  ///
  /// In en, this message translates to:
  /// **'Startup failed while {step}. Restart the app and try again.'**
  String bootstrapFailedWhile(String step);

  /// No description provided for @bootstrapTimedOut.
  ///
  /// In en, this message translates to:
  /// **'{label} timed out after {seconds}s. The app never reached the first frame.'**
  String bootstrapTimedOut(String label, int seconds);

  /// No description provided for @bootstrapStepFailed.
  ///
  /// In en, this message translates to:
  /// **'{label} failed: {error}'**
  String bootstrapStepFailed(String label, String error);

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @pwaInstallCool.
  ///
  /// In en, this message translates to:
  /// **'Install COOL'**
  String get pwaInstallCool;

  /// No description provided for @pwaAddToHomeScreen.
  ///
  /// In en, this message translates to:
  /// **'Add COOL to Home Screen'**
  String get pwaAddToHomeScreen;

  /// No description provided for @pwaInstallStandaloneMessage.
  ///
  /// In en, this message translates to:
  /// **'Install the app for faster admin access and standalone launch.'**
  String get pwaInstallStandaloneMessage;

  /// No description provided for @pwaSafariInstallMessage.
  ///
  /// In en, this message translates to:
  /// **'Use Safari share actions to install the admin PWA on iPhone or iPad.'**
  String get pwaSafariInstallMessage;

  /// No description provided for @pwaHowToInstall.
  ///
  /// In en, this message translates to:
  /// **'How to install'**
  String get pwaHowToInstall;

  /// No description provided for @pwaUpdateReady.
  ///
  /// In en, this message translates to:
  /// **'Update ready'**
  String get pwaUpdateReady;

  /// No description provided for @pwaUpdateReadyMessage.
  ///
  /// In en, this message translates to:
  /// **'Refresh to load the latest admin workspace and app assets.'**
  String get pwaUpdateReadyMessage;

  /// No description provided for @iosInstallSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get the full app experience with quick access from your home screen.'**
  String get iosInstallSubtitle;

  /// No description provided for @iosInstallStep1.
  ///
  /// In en, this message translates to:
  /// **'Tap the Share button in Safari'**
  String get iosInstallStep1;

  /// No description provided for @iosInstallStep2.
  ///
  /// In en, this message translates to:
  /// **'Scroll down and tap \"Add to Home Screen\"'**
  String get iosInstallStep2;

  /// No description provided for @iosInstallStep3.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Add\" to confirm'**
  String get iosInstallStep3;

  /// No description provided for @iosInstallGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get iosInstallGotIt;

  /// No description provided for @coolStateLoadingTitle.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get coolStateLoadingTitle;

  /// No description provided for @coolStateLoadingMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait while this section loads.'**
  String get coolStateLoadingMessage;

  /// No description provided for @coolErrorUnexpected.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred'**
  String get coolErrorUnexpected;

  /// No description provided for @groupSettingsMomoCollectionCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'COLLECTION CODE'**
  String get groupSettingsMomoCollectionCodeLabel;

  /// No description provided for @groupSettingsMomoSetByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Set by admin for all savings groups.'**
  String get groupSettingsMomoSetByAdmin;

  /// No description provided for @groupValidationMomoRouteRequired.
  ///
  /// In en, this message translates to:
  /// **'Add a valid MoMo route before creating this group.'**
  String get groupValidationMomoRouteRequired;

  /// No description provided for @groupValidationTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a group type.'**
  String get groupValidationTypeRequired;

  /// No description provided for @groupValidationFrequencyRequired.
  ///
  /// In en, this message translates to:
  /// **'Select a savings frequency.'**
  String get groupValidationFrequencyRequired;

  /// No description provided for @groupValidationAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get groupValidationAmountInvalid;

  /// No description provided for @groupValidationAmountPositive.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than zero.'**
  String get groupValidationAmountPositive;

  /// No description provided for @deleteAccountSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your account has been deleted.'**
  String get deleteAccountSuccess;

  /// No description provided for @walletScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'WALLET'**
  String get walletScreenTitle;

  /// No description provided for @walletScreenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'M-MONEY HISTORY'**
  String get walletScreenSubtitle;

  /// No description provided for @walletStatementExported.
  ///
  /// In en, this message translates to:
  /// **'Statement exported'**
  String get walletStatementExported;

  /// No description provided for @walletStatementTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet Statement'**
  String get walletStatementTitle;

  /// No description provided for @walletDefaultUserName.
  ///
  /// In en, this message translates to:
  /// **'COOL User'**
  String get walletDefaultUserName;

  /// No description provided for @walletAllTransactionsFilter.
  ///
  /// In en, this message translates to:
  /// **'All wallet transactions'**
  String get walletAllTransactionsFilter;

  /// No description provided for @walletNewestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get walletNewestFirst;

  /// No description provided for @walletAllInView.
  ///
  /// In en, this message translates to:
  /// **'All transactions in view'**
  String get walletAllInView;

  /// No description provided for @walletNoTransactionsYetTitle.
  ///
  /// In en, this message translates to:
  /// **'NO TRANSACTIONS YET'**
  String get walletNoTransactionsYetTitle;

  /// No description provided for @walletNoTransactionsYetMessage.
  ///
  /// In en, this message translates to:
  /// **'Your M-Money transactions will appear here once SMS sync is enabled and payments are processed.'**
  String get walletNoTransactionsYetMessage;

  /// No description provided for @walletRefPrefix.
  ///
  /// In en, this message translates to:
  /// **'Ref: {reference}'**
  String walletRefPrefix(String reference);

  /// No description provided for @walletExportTruncated.
  ///
  /// In en, this message translates to:
  /// **'Export limited to {count} entries. Narrow the date range for complete data.'**
  String walletExportTruncated(int count);

  /// No description provided for @biopayScanPreparingCamera.
  ///
  /// In en, this message translates to:
  /// **'Preparing secure camera...'**
  String get biopayScanPreparingCamera;

  /// No description provided for @biopayScanLoadingServices.
  ///
  /// In en, this message translates to:
  /// **'Loading BioPay camera access and on-device services.'**
  String get biopayScanLoadingServices;

  /// No description provided for @biopayScanAlignFace.
  ///
  /// In en, this message translates to:
  /// **'Align your face inside the oval'**
  String get biopayScanAlignFace;

  /// No description provided for @biopayScanPointAtPayee.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the payee\'s face'**
  String get biopayScanPointAtPayee;

  /// No description provided for @biopayScanEnrollHelper.
  ///
  /// In en, this message translates to:
  /// **'BioPay is analyzing live frames in memory only. Hold still when the oval turns green.'**
  String get biopayScanEnrollHelper;

  /// No description provided for @biopayScanPayHelper.
  ///
  /// In en, this message translates to:
  /// **'BioPay is analyzing live frames in memory only. Keep one face centered for a fast match.'**
  String get biopayScanPayHelper;

  /// No description provided for @biopayScanCameraLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing camera…'**
  String get biopayScanCameraLoading;

  /// No description provided for @biopayUnavailable.
  ///
  /// In en, this message translates to:
  /// **'BioPay unavailable'**
  String get biopayUnavailable;

  /// No description provided for @biopayEnableCamera.
  ///
  /// In en, this message translates to:
  /// **'Enable Camera'**
  String get biopayEnableCamera;

  /// No description provided for @biopayManageAccess.
  ///
  /// In en, this message translates to:
  /// **'Manage Access'**
  String get biopayManageAccess;

  /// No description provided for @walletLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load wallet transactions.'**
  String get walletLoadFailed;

  /// No description provided for @walletRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap to retry'**
  String get walletRetry;

  /// No description provided for @walletLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more transactions'**
  String get walletLoadMore;

  /// No description provided for @homeSavingsBalanceNewUserHint.
  ///
  /// In en, this message translates to:
  /// **'Your balance updates as you join groups and contribute.'**
  String get homeSavingsBalanceNewUserHint;

  /// No description provided for @biopayTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'BioPay is temporarily unavailable. Please try again later.'**
  String get biopayTemporarilyUnavailable;

  /// No description provided for @homeGettingStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get homeGettingStartedTitle;

  /// No description provided for @homeGettingStartedLinkMomo.
  ///
  /// In en, this message translates to:
  /// **'Link your MoMo number'**
  String get homeGettingStartedLinkMomo;

  /// No description provided for @homeGettingStartedLinkMomoSub.
  ///
  /// In en, this message translates to:
  /// **'Required for payments and groups'**
  String get homeGettingStartedLinkMomoSub;

  /// No description provided for @homeGettingStartedCreateGroup.
  ///
  /// In en, this message translates to:
  /// **'Create a savings group'**
  String get homeGettingStartedCreateGroup;

  /// No description provided for @homeGettingStartedCreateGroupSub.
  ///
  /// In en, this message translates to:
  /// **'Start saving with your community'**
  String get homeGettingStartedCreateGroupSub;

  /// No description provided for @homeGettingStartedExploreGroups.
  ///
  /// In en, this message translates to:
  /// **'Explore public groups'**
  String get homeGettingStartedExploreGroups;

  /// No description provided for @homeGettingStartedExploreGroupsSub.
  ///
  /// In en, this message translates to:
  /// **'Join an existing group'**
  String get homeGettingStartedExploreGroupsSub;

  /// No description provided for @groupCreateMomoRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'MoMo number required'**
  String get groupCreateMomoRequiredTitle;

  /// No description provided for @groupCreateMomoRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Link a Mobile Money number before creating a group. Contributions are routed through your MoMo.'**
  String get groupCreateMomoRequiredMessage;

  /// No description provided for @groupCreateMomoRequiredAction.
  ///
  /// In en, this message translates to:
  /// **'SET UP MOMO'**
  String get groupCreateMomoRequiredAction;

  /// No description provided for @profileCompletionPrompt.
  ///
  /// In en, this message translates to:
  /// **'Complete your profile to unlock all features.'**
  String get profileCompletionPrompt;

  /// No description provided for @profileCompletionAction.
  ///
  /// In en, this message translates to:
  /// **'Complete profile'**
  String get profileCompletionAction;

  /// No description provided for @adminEyebrowPlatformControl.
  ///
  /// In en, this message translates to:
  /// **'PLATFORM CONTROL'**
  String get adminEyebrowPlatformControl;

  /// No description provided for @adminSubtitleOperationalModules.
  ///
  /// In en, this message translates to:
  /// **'Operational modules, oversight surfaces, and release controls.'**
  String get adminSubtitleOperationalModules;

  /// No description provided for @adminMetricModules.
  ///
  /// In en, this message translates to:
  /// **'Modules'**
  String get adminMetricModules;

  /// No description provided for @adminMetricModulesHint.
  ///
  /// In en, this message translates to:
  /// **'Platform surfaces'**
  String get adminMetricModulesHint;

  /// No description provided for @adminMetricPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get adminMetricPriority;

  /// No description provided for @adminMetricPriorityHint.
  ///
  /// In en, this message translates to:
  /// **'Daily-use modules'**
  String get adminMetricPriorityHint;

  /// No description provided for @adminMetricOversight.
  ///
  /// In en, this message translates to:
  /// **'Oversight'**
  String get adminMetricOversight;

  /// No description provided for @adminMetricOversightHint.
  ///
  /// In en, this message translates to:
  /// **'Monitoring surfaces'**
  String get adminMetricOversightHint;

  /// No description provided for @adminMetricConfig.
  ///
  /// In en, this message translates to:
  /// **'Config'**
  String get adminMetricConfig;

  /// No description provided for @adminMetricConfigHint.
  ///
  /// In en, this message translates to:
  /// **'System controls'**
  String get adminMetricConfigHint;

  /// No description provided for @adminSectionPriority.
  ///
  /// In en, this message translates to:
  /// **'Priority'**
  String get adminSectionPriority;

  /// No description provided for @adminSectionPrioritySub.
  ///
  /// In en, this message translates to:
  /// **'Users, operations, and access changes first.'**
  String get adminSectionPrioritySub;

  /// No description provided for @adminSectionOversight.
  ///
  /// In en, this message translates to:
  /// **'Oversight'**
  String get adminSectionOversight;

  /// No description provided for @adminSectionOversightSub.
  ///
  /// In en, this message translates to:
  /// **'Platform metrics, history, and operational context.'**
  String get adminSectionOversightSub;

  /// No description provided for @adminSectionConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get adminSectionConfiguration;

  /// No description provided for @adminSectionConfigurationSub.
  ///
  /// In en, this message translates to:
  /// **'Core settings and structural management surfaces.'**
  String get adminSectionConfigurationSub;

  /// No description provided for @groupDescriptionHeader.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get groupDescriptionHeader;

  /// No description provided for @iosPaymentNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic verification unavailable'**
  String get iosPaymentNoticeTitle;

  /// No description provided for @iosPaymentNoticeMessage.
  ///
  /// In en, this message translates to:
  /// **'On iPhone, payments launch normally, but auto-verification is unavailable. Your group admin confirms payment afterward.'**
  String get iosPaymentNoticeMessage;

  /// No description provided for @homeHowItWorksTitle.
  ///
  /// In en, this message translates to:
  /// **'How COOL works'**
  String get homeHowItWorksTitle;

  /// No description provided for @homeHowItWorksStep1.
  ///
  /// In en, this message translates to:
  /// **'Link your MoMo number in Settings'**
  String get homeHowItWorksStep1;

  /// No description provided for @homeHowItWorksStep2.
  ///
  /// In en, this message translates to:
  /// **'Create or join a savings group'**
  String get homeHowItWorksStep2;

  /// No description provided for @homeHowItWorksStep3.
  ///
  /// In en, this message translates to:
  /// **'Contribute via MoMo — tracked automatically'**
  String get homeHowItWorksStep3;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline. Some features may be unavailable.'**
  String get offlineBanner;

  /// No description provided for @featureTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Temporarily Unavailable'**
  String get featureTemporarilyUnavailable;

  /// No description provided for @featureComingSoonMessage.
  ///
  /// In en, this message translates to:
  /// **'{featureName} is coming soon. Stay tuned for updates.'**
  String featureComingSoonMessage(Object featureName);

  /// No description provided for @groupSettingsLoadError.
  ///
  /// In en, this message translates to:
  /// **'We could not load this group right now. Check your connection and try again.'**
  String get groupSettingsLoadError;

  /// No description provided for @groupSettingsGroupUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This group is no longer available.'**
  String get groupSettingsGroupUnavailable;

  /// No description provided for @groupSettingsAccessCheckError.
  ///
  /// In en, this message translates to:
  /// **'We could not verify your access to this group. Try again in a moment.'**
  String get groupSettingsAccessCheckError;

  /// No description provided for @groupSettingsNoPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to change these settings.'**
  String get groupSettingsNoPermission;

  /// No description provided for @groupSettingsAmountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get groupSettingsAmountInvalid;

  /// No description provided for @groupSettingsAmountNegative.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot be negative.'**
  String get groupSettingsAmountNegative;

  /// No description provided for @validationMomoNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'MoMo number is required.'**
  String get validationMomoNumberRequired;

  /// No description provided for @validationMomoNumberInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid {countryName} mobile money number.'**
  String validationMomoNumberInvalid(String countryName);

  /// No description provided for @validationMomoNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Mobile money is not configured for {countryName}.'**
  String validationMomoNotConfigured(String countryName);

  /// No description provided for @validationMomoCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'MoMo code is required.'**
  String get validationMomoCodeRequired;

  /// No description provided for @validationMomoCodeDigits.
  ///
  /// In en, this message translates to:
  /// **'MoMo code must be 4–9 digits.'**
  String get validationMomoCodeDigits;

  /// No description provided for @validationMomoCodeOnlyNumbers.
  ///
  /// In en, this message translates to:
  /// **'MoMo code must contain only numbers.'**
  String get validationMomoCodeOnlyNumbers;

  /// No description provided for @validationMomoCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid MoMo code.'**
  String get validationMomoCodeInvalid;

  /// No description provided for @validationMomoCodeNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Merchant-code payments are not configured for {countryName}.'**
  String validationMomoCodeNotConfigured(String countryName);

  /// No description provided for @validationPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get validationPhoneInvalid;

  /// No description provided for @validationEnterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number.'**
  String get validationEnterPhoneNumber;

  /// No description provided for @validationRwandanMobilePrefix.
  ///
  /// In en, this message translates to:
  /// **'Rwandan mobile numbers start with 07.'**
  String get validationRwandanMobilePrefix;

  /// No description provided for @validationUseE164Format.
  ///
  /// In en, this message translates to:
  /// **'Use + for full E.164 WhatsApp numbers.'**
  String get validationUseE164Format;

  /// No description provided for @adminSavingsGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Savings Group'**
  String get adminSavingsGroupTitle;

  /// No description provided for @adminSavingsGroupNotFound.
  ///
  /// In en, this message translates to:
  /// **'Savings group not found.'**
  String get adminSavingsGroupNotFound;

  /// No description provided for @adminSavingsCloseGroup.
  ///
  /// In en, this message translates to:
  /// **'Close Group'**
  String get adminSavingsCloseGroup;

  /// No description provided for @adminSavingsClosedStatus.
  ///
  /// In en, this message translates to:
  /// **'CLOSED'**
  String get adminSavingsClosedStatus;

  /// No description provided for @adminSavingsActiveStatus.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get adminSavingsActiveStatus;

  /// No description provided for @adminSavingsAddingMember.
  ///
  /// In en, this message translates to:
  /// **'Adding…'**
  String get adminSavingsAddingMember;

  /// No description provided for @adminSavingsAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get adminSavingsAddMember;

  /// No description provided for @adminSavingsAllocating.
  ///
  /// In en, this message translates to:
  /// **'Allocating…'**
  String get adminSavingsAllocating;

  /// No description provided for @adminSavingsAllocate.
  ///
  /// In en, this message translates to:
  /// **'Allocate'**
  String get adminSavingsAllocate;

  /// No description provided for @adminSavingsSelectMember.
  ///
  /// In en, this message translates to:
  /// **'Select member'**
  String get adminSavingsSelectMember;

  /// No description provided for @adminSavingsNoMembersYet.
  ///
  /// In en, this message translates to:
  /// **'No members yet.'**
  String get adminSavingsNoMembersYet;

  /// No description provided for @adminSavingsNoMembers.
  ///
  /// In en, this message translates to:
  /// **'No members.'**
  String get adminSavingsNoMembers;

  /// No description provided for @adminSavingsPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required.'**
  String get adminSavingsPhoneRequired;

  /// No description provided for @adminSavingsRemoveMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get adminSavingsRemoveMemberTitle;

  /// No description provided for @adminSavingsRemoveMemberMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this savings group?'**
  String adminSavingsRemoveMemberMessage(String name);

  /// No description provided for @adminSavingsMemberAdded.
  ///
  /// In en, this message translates to:
  /// **'Member added.'**
  String get adminSavingsMemberAdded;

  /// No description provided for @adminSavingsMemberRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed.'**
  String adminSavingsMemberRemoved(String name);

  /// No description provided for @adminSavingsCloseGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Close savings group'**
  String get adminSavingsCloseGroupTitle;

  /// No description provided for @adminSavingsCloseGroupMessage.
  ///
  /// In en, this message translates to:
  /// **'Members will no longer be able to contribute.'**
  String get adminSavingsCloseGroupMessage;

  /// No description provided for @adminSavingsGroupClosed.
  ///
  /// In en, this message translates to:
  /// **'Group closed.'**
  String get adminSavingsGroupClosed;

  /// No description provided for @adminSavingsContributionRecorded.
  ///
  /// In en, this message translates to:
  /// **'Contribution of {amount} RWF recorded.'**
  String adminSavingsContributionRecorded(String amount);

  /// No description provided for @adminSavingsErrorText.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String adminSavingsErrorText(String error);

  /// No description provided for @adminSavingsMembersTab.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get adminSavingsMembersTab;

  /// No description provided for @adminSavingsAllocationsTab.
  ///
  /// In en, this message translates to:
  /// **'Allocations'**
  String get adminSavingsAllocationsTab;

  /// No description provided for @adminSavingsRemoveMemberTooltip.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get adminSavingsRemoveMemberTooltip;

  /// No description provided for @adminSavingsEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get adminSavingsEnterValidAmount;
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
