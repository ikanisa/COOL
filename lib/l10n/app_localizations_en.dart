// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Cool';

  @override
  String get navHome => 'Home';

  @override
  String get navGroups => 'Groups';

  @override
  String get navMobility => 'Mobility';

  @override
  String get navProfile => 'Profile';

  @override
  String get welcomeTitle => 'Welcome to Cool';

  @override
  String get welcomeSubtitle => 'Community savings group funds';

  @override
  String get getStarted => 'Get Started';

  @override
  String get signIn => 'Already have an account?';

  @override
  String get verifyWhatsapp => 'Verify via WhatsApp';

  @override
  String get verifyWhatsappSubtitle => 'We\'ll send a one-time';

  @override
  String get phoneLabel => 'Phone Number';

  @override
  String get phoneHint => '+250 7XX XXX XXX';

  @override
  String get sendCode => 'Send WhatsApp Code';

  @override
  String get enterCode => 'Enter Code';

  @override
  String get enterCodeSubtitle => 'Enter the 6-digit code';

  @override
  String get verifyButton => 'Verify & Continue';

  @override
  String get resendCode => 'Resend Code';

  @override
  String resendCodeIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get invalidCode => 'Invalid code Please try';

  @override
  String get codeSent => 'Code sent to WhatsApp.';

  @override
  String get setupProfile => 'Setup Profile';

  @override
  String get createAccount => 'Create Account';

  @override
  String get nameLabel => 'Full Name';

  @override
  String get nameHint => 'e.g. Amara Banda';

  @override
  String get countryLabel => 'Country';

  @override
  String get momoNumberLabel => 'MOMO Number';

  @override
  String get momoNumberHint => 'e g 0788 123';

  @override
  String get totalBalance => 'Total Balance';

  @override
  String get rwf => 'RWF';

  @override
  String get quickActions => 'Quick Actions';

  @override
  String get sendMoney => 'Send Money';

  @override
  String get requestPay => 'Request Pay';

  @override
  String get payViaMomo => 'Pay via MOMO';

  @override
  String get recentActivity => 'Recent Activity';

  @override
  String get noActivity => 'No recent activity to';

  @override
  String get viewAll => 'View All';

  @override
  String get sendMoneyTitle => 'Send Money';

  @override
  String get sendMoneyHint => 'Transfer instantly to a';

  @override
  String get sendAction => 'Send';

  @override
  String get recipientLabel => 'Recipient ID';

  @override
  String get recipientHint => 'Enter member ID';

  @override
  String get amountLabel => 'Amount (RWF)';

  @override
  String get amountHint => 'e.g. 5,000';

  @override
  String get confirmSend => 'Confirm & Send';

  @override
  String get sendSuccess => 'Transfer initiated via MOMO.';

  @override
  String get myGroups => 'My Groups';

  @override
  String get newGroup => 'New Group';

  @override
  String get createGroup => 'Create Group';

  @override
  String get joinGroup => 'Join Group';

  @override
  String get leaveGroup => 'Leave Group';

  @override
  String get groupSaving => 'Group Saving';

  @override
  String get communityFund => 'Community Fund';

  @override
  String get public => 'Public';

  @override
  String get private => 'Private';

  @override
  String get publicGroup => 'Public';

  @override
  String get privateGroup => 'Private';

  @override
  String get contribute => 'Contribute';

  @override
  String get contribution => 'Contribution';

  @override
  String get contributionAmount => 'Contribution Amount';

  @override
  String get cycleDays => 'Cycle (days)';

  @override
  String memberCount(int count) {
    return '$count members';
  }

  @override
  String get groupMembers => 'Members';

  @override
  String get recentContributions => 'Recent Contributions';

  @override
  String get shareInvite => 'Share / QR';

  @override
  String get groupCreated => 'Group created successfully.';

  @override
  String get groupNameLabel => 'Group Name';

  @override
  String get groupNameHint => 'e.g. Nyamirambo Savers';

  @override
  String get groupDescriptionLabel => 'Description';

  @override
  String get discoverGroups => 'Discover Groups';

  @override
  String get noGroupsYet => 'You haven\'t joined any';

  @override
  String get noPublicGroups => 'No public groups available.';

  @override
  String get pending => 'Pending';

  @override
  String get confirmed => 'Confirmed';

  @override
  String get failed => 'Failed';

  @override
  String get basket => 'Basket';

  @override
  String get emptyBasket => 'Your basket is empty.';

  @override
  String get checkout => 'Checkout';

  @override
  String totalItems(int count) {
    return '$count items';
  }

  @override
  String get momoTitle => 'MOMO Pay';

  @override
  String get payViaUssd => 'Pay via MOMO USSD';

  @override
  String get momoDialerError => 'open the USSD failed';

  @override
  String get mobilityTitle => 'Mobility';

  @override
  String get nearbyDrivers => 'Nearby Drivers';

  @override
  String get scheduledTrips => 'Scheduled Trips';

  @override
  String get scheduleTrip => 'Schedule a Trip';

  @override
  String get postTrip => 'Post Trip on Board';

  @override
  String get tripBoard => 'Trip Board';

  @override
  String get driverProfile => 'Driver Profile';

  @override
  String get allTrips => 'All Trips';

  @override
  String get oneWay => 'One Way';

  @override
  String get returnTrips => 'Return';

  @override
  String get noTripsAvailable => 'No trips available right';

  @override
  String get noDriversNearby => 'No drivers nearby.';

  @override
  String get contactViaWhatsapp => 'Contact via WhatsApp';

  @override
  String get tripDetails => 'Trip Details';

  @override
  String expiresIn(int minutes) {
    return 'Expires in $minutes min';
  }

  @override
  String seatsLabel(int count) {
    return '$count seat';
  }

  @override
  String seatsLabelPlural(int count) {
    return '$count seats';
  }

  @override
  String get scheduleTripTitle => 'Schedule a Trip';

  @override
  String get scheduleTripInfoBanner => 'Schedule ahead to find!';

  @override
  String get scheduleTripDetailsTitle => 'Trip Details';

  @override
  String get scheduleTripFromHint => '📍 From — e.g. Nyamirambo';

  @override
  String get scheduleTripToHint => 'To e g Kigali';

  @override
  String get scheduleTripDateTimeLabel => 'Date & Time';

  @override
  String get scheduleTripVehicleLabel => 'Vehicle Preference';

  @override
  String get scheduleTripSeatsLabel => 'Seats Needed';

  @override
  String get scheduleTripReturnTitle => 'Return Trip';

  @override
  String get scheduleTripReturnSubtitle => 'Drivers offer discounts on';

  @override
  String get scheduleTripReturnFieldsLabel => 'Return Date & Time';

  @override
  String get scheduleTripRecurringTitle => 'Recurring Trip';

  @override
  String get scheduleTripRecurringSubtitle => 'Daily / Weekly repeat';

  @override
  String get scheduleTripRecurringDaysLabel => 'Repeat Days';

  @override
  String get scheduleTripExpiryTitle => 'Trip expires automatically';

  @override
  String get scheduleTripExpirySubtitle => 'Trips are removed 60';

  @override
  String get scheduleTripPostCta => 'Post Trip on Board';

  @override
  String get scheduleTripPostedSuccess => 'Trip posted successfully.';

  @override
  String get scheduleTripPostedPendingSync => 'Trip saved offline and';

  @override
  String get scheduleTripPostingGuideTitle => 'Posting behavior';

  @override
  String get scheduleTripPostingGuideSubtitle => 'Make sure the trip';

  @override
  String get scheduleTripPostingVisibilityLabel => 'Visible to others';

  @override
  String get scheduleTripPostingPrecisionLabel => 'Pickup precision';

  @override
  String get scheduleTripPostingCoordinationLabel => 'After posting';

  @override
  String get scheduleTripPostingOfflineLabel => 'Offline fallback';

  @override
  String get scheduleTripPostingPassengerVisibility => 'Drivers see your route';

  @override
  String get scheduleTripPostingDriverVisibility => 'Riders see your route';

  @override
  String get scheduleTripPostingPrecisionExact =>
      'Exact pickup and destination';

  @override
  String get scheduleTripPostingPrecisionPartial => 'One place pin is';

  @override
  String get scheduleTripPostingPrecisionTextOnly => 'Text route only Confirm';

  @override
  String get scheduleTripPostingPassengerCoordination =>
      'Drivers contact you after';

  @override
  String get scheduleTripPostingDriverCoordination =>
      'Riders contact you after';

  @override
  String get scheduleTripPostingOfflineBehavior => 'If the network drops';

  @override
  String get scheduleTripFromRequired => 'Enter a departure point.';

  @override
  String get scheduleTripToRequired => 'Enter a destination.';

  @override
  String get scheduleTripRouteSameError => 'Departure and destination must';

  @override
  String get scheduleTripReturnInvalidError => 'Return date and time';

  @override
  String get scheduleTripRecurringDaysError => 'Pick at least one';

  @override
  String get scheduleTripDateFieldPrefix => '📅';

  @override
  String get scheduleTripTimeFieldPrefix => '🕐';

  @override
  String get driverMode => 'Driver Mode';

  @override
  String get driverOnlineMessage => 'Online now';

  @override
  String get driverOfflineMessage => 'Offline now';

  @override
  String get online => 'Online';

  @override
  String get offline => 'Offline';

  @override
  String get tripsDone => 'Trips Done';

  @override
  String get freeTrips => 'Free Trips';

  @override
  String get statusHealthy => 'Healthy';

  @override
  String get statusWarning => 'Warning';

  @override
  String get myVehicle => 'My Vehicle';

  @override
  String get editVehicle => 'Edit Vehicle';

  @override
  String get saveVehicleInfo => 'Save Vehicle Info';

  @override
  String get vehicleTypeLabel => 'Vehicle Type';

  @override
  String get plateNumberLabel => 'Plate Number';

  @override
  String get baseLocationLabel => 'Base Location';

  @override
  String get statusLabel => 'Status';

  @override
  String get verified => 'Verified';

  @override
  String get pendingReview => 'Pending Review';

  @override
  String get maintenance => 'Maintenance';

  @override
  String get subscribe => 'Pay via MOMO USSD';

  @override
  String get unlockUnlimitedTrips => 'Unlock Unlimited Trips';

  @override
  String tripsUsedMessage(int used, int remaining) {
    return 'You have used $used';
  }

  @override
  String daysRemaining(int count) {
    return '$count days remaining';
  }

  @override
  String get addReturnTrip => 'Add Return Trip';

  @override
  String get myScheduledTrips => 'My Scheduled Trips';

  @override
  String get noScheduledTrips => 'No scheduled trips yet.';

  @override
  String get perMonth => '/month';

  @override
  String get vehicleMoto => 'Moto';

  @override
  String get vehicleCab => 'Cab';

  @override
  String get vehicleAny => 'Any';

  @override
  String get weekdayMonShort => 'Mon';

  @override
  String get weekdayTueShort => 'Tue';

  @override
  String get weekdayWedShort => 'Wed';

  @override
  String get weekdayThuShort => 'Thu';

  @override
  String get weekdayFriShort => 'Fri';

  @override
  String get weekdaySatShort => 'Sat';

  @override
  String get weekdaySunShort => 'Sun';

  @override
  String get partnersTitle => 'Partners';

  @override
  String get partners => 'Partners';

  @override
  String get football => 'Football';

  @override
  String get banks => 'Banks';

  @override
  String get organizations => 'Orgs';

  @override
  String get ticketsAndShop => 'Tickets & Shop';

  @override
  String get upcomingMatches => 'Upcoming Matches';

  @override
  String get fanRegistry => 'Fan Registry';

  @override
  String get fanClubs => 'Fan Clubs';

  @override
  String get ticketing => 'Ticketing';

  @override
  String get clubShop => 'Club Shop';

  @override
  String fansCount(int count) {
    return '$count fans';
  }

  @override
  String clubsCount(int count) {
    return '$count clubs';
  }

  @override
  String gamesCount(int count) {
    return '$count games';
  }

  @override
  String get fansTitle => 'Fans';

  @override
  String get membership => 'Membership';

  @override
  String get achievements => 'Achievements';

  @override
  String get fanDirectory => 'Fan Directory';

  @override
  String get joinClub => 'Join';

  @override
  String get joinedClub => 'Joined';

  @override
  String get leaveClub => 'Leave';

  @override
  String get goldMember => 'GOLD MEMBER';

  @override
  String get silverMember => 'SILVER MEMBER';

  @override
  String get bronzeMember => 'BRONZE MEMBER';

  @override
  String get earnedBadge => 'Earned';

  @override
  String get lockedBadge => 'Locked';

  @override
  String get ticketingTitle => 'Ticketing';

  @override
  String get tickets => 'Tickets';

  @override
  String get myTickets => 'My Tickets';

  @override
  String get purchasedTickets => 'Purchased Tickets';

  @override
  String get buyTicket => 'Buy';

  @override
  String get purchaseTicket => 'Purchase Ticket';

  @override
  String get quantity => 'Quantity';

  @override
  String get seatCategory => 'Seat Category';

  @override
  String get general => 'General';

  @override
  String get vip => 'VIP';

  @override
  String get generalSeat => 'General';

  @override
  String get vipSeat => 'VIP';

  @override
  String get total => 'Total';

  @override
  String get payViaMomoUssd => 'Pay via MOMO';

  @override
  String get whatsappConfirmation => 'WhatsApp confirmation will be';

  @override
  String get viewTicket => 'View';

  @override
  String get showAtGate => 'Show this at the';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get goldDiscount => 'Gold Members get 10';

  @override
  String get noTicketsYet => 'No tickets yet';

  @override
  String get buyTicketsToUpcomingMatches => 'Buy tickets to upcoming';

  @override
  String cartItemCount(int count) {
    return '$count items';
  }

  @override
  String get creditScore => 'Credit Score';

  @override
  String get coolCreditScore => 'COOL CREDIT SCORE';

  @override
  String get excellentGrade => 'Excellent';

  @override
  String get goodStanding => 'Good Standing';

  @override
  String get fairGrade => 'Fair';

  @override
  String get needsImprovement => 'Needs Improvement';

  @override
  String get scoreFactors => 'Score Factors';

  @override
  String get savingConsistency => 'Saving Consistency';

  @override
  String get groupParticipation => 'Group Participation';

  @override
  String get paymentHistory => 'Payment History';

  @override
  String get communityActivity => 'Community Activity';

  @override
  String get howToImprove => '💡 How to Improve';

  @override
  String get improveOnTime => 'Contribute on time every';

  @override
  String get improveJoinGroups => 'Join 2+ savings groups';

  @override
  String get improveCommunityFunds => 'Contribute to 3 community';

  @override
  String get improveConsecutiveMonths => '6 consecutive months saving';

  @override
  String get scoreHistory => 'Score History';

  @override
  String get profile => 'Profile';

  @override
  String get account => 'Account';

  @override
  String get phone => 'Phone';

  @override
  String get momoNumber => 'MOMO Number';

  @override
  String get momoLinked => 'Linked ✅';

  @override
  String get momoNotLinked => 'Not linked';

  @override
  String get language => 'Language';

  @override
  String get notifications => 'Notifications';

  @override
  String get security => 'Security';

  @override
  String get pinBiometric => 'PIN / Biometric';

  @override
  String get enabled => 'Enabled';

  @override
  String get whatsappOtp => 'WhatsApp OTP';

  @override
  String get active => 'Active';

  @override
  String get more => 'More';

  @override
  String get helpAndSupport => 'Help & Support';

  @override
  String get signOut => 'Sign Out';

  @override
  String get signOutConfirmTitle => 'Sign Out';

  @override
  String get signOutConfirmMessage => 'Sign out now?';

  @override
  String get cancel => 'Cancel';

  @override
  String get vehicle => 'Vehicle';

  @override
  String get subscription => 'Subscription';

  @override
  String expiringInDays(int count) {
    return 'Expiring in $count days';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get loading => 'Loading…';

  @override
  String get retry => 'Retry';

  @override
  String get error => 'Something went wrong.';

  @override
  String get noConnection => 'No internet connection.';

  @override
  String get offlineNotice => 'You\'re offline Showing cached';

  @override
  String goodMorningUser(String name) {
    return 'Good morning, $name 👋';
  }

  @override
  String get memberIdPrefix => 'ID:';

  @override
  String get recent => 'Recent';

  @override
  String get seeAll => 'See all';

  @override
  String inviteToGroup(String groupName) {
    return 'Invite to $groupName';
  }

  @override
  String get scanQrOrShareLink => 'Scan QR or share';

  @override
  String get shareViaWhatsapp => 'Share via WhatsApp';

  @override
  String get linkCopied => 'Link copied!';

  @override
  String get copy => 'Copy';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get topUp => 'Top Up';

  @override
  String get savingsRank => 'Savings Rank';

  @override
  String get officialPartner => 'Official Partner';

  @override
  String get bankingPartner => 'Banking Partner';

  @override
  String get activeGroups => 'Active Groups';

  @override
  String get rwfHeld => 'RWF Held';

  @override
  String get members => 'members';

  @override
  String get moreOrganizationsComingSoon => 'More organizations coming soon';

  @override
  String get admin => 'Admin';

  @override
  String get returnLabel => 'Return';

  @override
  String get daily => 'Daily';

  @override
  String get expiresSoon => 'Expires soon';

  @override
  String get departed => 'departed';

  @override
  String inMinutesShort(int count) {
    return 'in ${count}min';
  }

  @override
  String inHoursShort(int count) {
    return 'in ${count}h';
  }

  @override
  String inDaysShort(int count) {
    return 'in ${count}d';
  }

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Close';

  @override
  String targetAmount(String amount) {
    return 'Target: $amount RWF';
  }

  @override
  String get search => 'Search';

  @override
  String get noResults => 'No results found';

  @override
  String get seeMore => 'See More';

  @override
  String get copied => 'Copied to clipboard.';

  @override
  String get retryAction => 'Retry';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get openAction => 'Open';

  @override
  String get languageLabel => 'Language';

  @override
  String get supportLabel => 'Support';

  @override
  String get appearanceLabel => 'Appearance';

  @override
  String get appearanceSheetSubtitle => 'Choose how Cool looks';

  @override
  String get appearanceSystemLabel => 'System';

  @override
  String get appearanceSystemDescription => 'Follow your phone\'s light';

  @override
  String get appearanceLightLabel => 'Light';

  @override
  String get appearanceLightDescription => 'Always use the light';

  @override
  String get appearanceDarkLabel => 'Dark';

  @override
  String get appearanceDarkDescription => 'Always use the dark';

  @override
  String get notificationsLabel => 'Notifications';

  @override
  String get statementsLabel => 'Statements';

  @override
  String get walletLabel => 'Wallet';

  @override
  String get savingsLabel => 'Savings';

  @override
  String get allTimeLabel => 'All time';

  @override
  String get last30DaysLabel => 'Last 30 days';

  @override
  String get last90DaysLabel => 'Last 90 days';

  @override
  String get incomingLabel => 'Incoming';

  @override
  String get outgoingLabel => 'Outgoing';

  @override
  String get counterpartyLabel => 'Counterparty';

  @override
  String get referenceLabel => 'Reference';

  @override
  String get detailsLabel => 'Details';

  @override
  String get otpUseWhatsappTitle => 'Use your WhatsApp number';

  @override
  String get otpUseWhatsappSubtitle => 'We will send a';

  @override
  String get otpPhoneRequired => 'Enter your phone number';

  @override
  String get otpContinue => 'Continue';

  @override
  String get otpGenericError => 'Something went wrong Please';

  @override
  String get openLinkError => 'Open link failed';

  @override
  String get otpLegalPrefix => 'By continuing you accept';

  @override
  String get otpLegalAnd => 'and';

  @override
  String get termsLabel => 'Terms';

  @override
  String get privacyPolicyLabel => 'Privacy Policy';

  @override
  String get homeMissionsTitle => 'Missions';

  @override
  String get homeMonthlyNet => 'Monthly net';

  @override
  String get homeActionPay => 'MoMo';

  @override
  String get homeActionTrips => 'Trips';

  @override
  String get homeFallbackGroupsSubtitle => 'Savings and invites';

  @override
  String get homeFallbackPaySubtitle => 'Receive, send, and statements';

  @override
  String get homeFallbackPartnersSubtitle => 'Banks and clubs';

  @override
  String get homeFallbackTripsSubtitle => 'Ride or drive';

  @override
  String get homePriorityLabel => 'Today';

  @override
  String get homePriorityGroupsTitle => 'Start with a group';

  @override
  String get homePriorityGroupsSubtitle => 'Create or join a';

  @override
  String get homePriorityMomoTitle => 'Open Mobile Money';

  @override
  String get homePriorityMomoSubtitle => 'Send request or receive';

  @override
  String get homePriorityStatementsTitle => 'Review statements';

  @override
  String get homePriorityStatementsSubtitle => 'Your monthly trend is';

  @override
  String get homePriorityMomentumTitle => 'Keep contributions moving';

  @override
  String get homePriorityMomentumSubtitle => 'You have active group';

  @override
  String homeActiveCount(int count) {
    return '$count active';
  }

  @override
  String get homeNoActivityTitle => 'No activity yet';

  @override
  String get homeNoActivityMessage => 'Activity will appear here.';

  @override
  String get homeLoadErrorTitle => 'Couldn\'t load this section';

  @override
  String get homeLoadErrorMessage => 'Pull to refresh';

  @override
  String get profileMobileMoney => 'Mobile Money';

  @override
  String get profileCreditScore => 'Credit score';

  @override
  String get profileNotLinked => 'Not linked';

  @override
  String get profileCreditReadiness => 'Credit readiness';

  @override
  String get profileDriverTools => 'Driver tools';

  @override
  String get profileCoolStatus => 'COOL status';

  @override
  String get profileAdminPanel => 'Admin panel';

  @override
  String get officialNameLabel => 'Official name';

  @override
  String get identityLabel => 'Identity';

  @override
  String get moneySectionTitle => 'Money';

  @override
  String get preferencesSectionTitle => 'Preferences';

  @override
  String get moreToolsSectionTitle => 'More tools';

  @override
  String get profileMoreToolsShowSubtitle => 'Show extra actions and';

  @override
  String get profileMoreToolsHideSubtitle => 'Hide QR driver and';

  @override
  String get vehicleLabel => 'Vehicle';

  @override
  String get accountActionsTitle => 'Account actions';

  @override
  String get signOutAction => 'Sign out';

  @override
  String get deleteAccountAction => 'Delete account';

  @override
  String get deleteAccountQuestion => 'Delete account?';

  @override
  String get deleteAccountMessage => 'This permanently removes your';

  @override
  String get signOutMessage => 'You\'ll need to verify';

  @override
  String get completeProfileTitle => 'Complete your profile';

  @override
  String get completeProfileSubtitle => 'Finish setup to unlock';

  @override
  String get profileSavingMomoInfo => 'Saving MoMo info...';

  @override
  String get profileDeletingAccount => 'Deleting your account...';

  @override
  String get profileMomoUpdated => 'MoMo info updated';

  @override
  String get profileMomoUpdateFailed => 'Failed to update MoMo';

  @override
  String get profileSupportOpenError => 'Open WhatsApp Please failed';

  @override
  String get profileSupportUnavailable => 'Support is unavailable right';

  @override
  String get profileMomoQrTitle => 'MoMo QR';

  @override
  String profileMomoQrSubtitle(String number) {
    return 'Scan to pay $number';
  }

  @override
  String get profileEditMomoInfo => 'Edit MoMo Info';

  @override
  String get profileEditMomoSubtitle => 'This number will be';

  @override
  String get profileMomoCodeOptional => 'MOMO CODE (OPTIONAL)';

  @override
  String get kycNeedsUpdate => 'Needs update';

  @override
  String get kycUnverified => 'Unverified';

  @override
  String get userFallbackName => 'User';

  @override
  String get notSetLabel => 'Not set';

  @override
  String get momoStatementsTitle => 'Statements & Ledger';

  @override
  String get momoRefreshStatements => 'Refresh statements';

  @override
  String get statementOverviewTitle => 'Statement overview';

  @override
  String get walletEntriesMetric => 'Wallet entries';

  @override
  String get savingsEntriesMetric => 'Savings entries';

  @override
  String get walletEmptyTitle => 'No wallet entries yet';

  @override
  String get walletEmptyMessage => 'Wallet activity will appear';

  @override
  String get walletLedgerTitle => 'Wallet ledger';

  @override
  String walletLedgerSubtitle(int shown, int total) {
    return '$shown/$total shown';
  }

  @override
  String get savingsEmptyTitle => 'No savings entries yet';

  @override
  String get savingsEmptyMessage => 'Savings contributions will appear';

  @override
  String get savingsStatementTitle => 'Savings statement';

  @override
  String savingsStatementSubtitle(int shown, int total) {
    return '$shown/$total shown';
  }

  @override
  String get coolMemberFallback => 'COOL member';

  @override
  String get momoStatementsPeriodDay => 'Day';

  @override
  String get momoStatementsPeriodWeek => 'Week';

  @override
  String get momoStatementsPeriodMonth => 'Month';

  @override
  String get momoStatementsPeriodCustom => 'Custom';

  @override
  String get momoStatementsPeriodAll => 'All';

  @override
  String get momoStatementsSortNewestFirst => 'Newest first';

  @override
  String get momoStatementsSortOldestFirst => 'Oldest first';

  @override
  String get momoStatementsSortAmountHighToLow => 'Amount: high → low';

  @override
  String get momoStatementsSortAmountLowToHigh => 'Amount: low → high';

  @override
  String get momoStatementsSortNameAz => 'Name: A → Z';

  @override
  String get momoStatementsSortNameZa => 'Name: Z → A';

  @override
  String get momoStatementsWalletFilteredEmptyTitle =>
      'No matching wallet entries';

  @override
  String get momoStatementsWalletFilteredEmptyMessage =>
      'Try adjusting your filters';

  @override
  String get momoStatementsSavingsFilteredEmptyTitle =>
      'No matching savings entries';

  @override
  String get momoStatementsSavingsFilteredEmptyMessage =>
      'Try adjusting your filters';

  @override
  String get fansScreenUnavailableTitle => 'Fan Hub Moved';

  @override
  String get fansScreenHeadline => 'Fan Hub';

  @override
  String fansScreenBody(String clubName) {
    return 'Fan features for $clubName';
  }

  @override
  String get fansScreenMembershipUnavailable =>
      'Membership features live inside';

  @override
  String get fansScreenClubsUnavailable => 'Fan clubs are now';

  @override
  String get fansScreenRayonDedicatedHub => 'Rayon Sports has a';

  @override
  String get fansScreenRouteKeptReachable => 'Legacy route';

  @override
  String get fansScreenBackToPartners => 'Back to Partners';

  @override
  String get fansScreenOpenRayon => 'Open Rayon Sports';

  @override
  String get ticketWalletInvalidLink => 'Invalid Google Wallet link.';

  @override
  String get ticketWalletUnavailable => 'Google Wallet is not';

  @override
  String get ticketWalletOpenFailed => 'Open Google Wallet failed';

  @override
  String get ticketConfirmationScreenTitle => 'Ticket';

  @override
  String get ticketConfirmationNotFound => 'Ticket not found.';

  @override
  String get ticketAddToGoogleWallet => 'Add to Google Wallet';

  @override
  String get ticketBackToTickets => 'Back to Tickets';

  @override
  String get ticketShareMatchTitle => 'Share Match';

  @override
  String ticketShareMatchText(String matchTitle) {
    return 'Check out $matchTitle on!';
  }

  @override
  String get ticketStatusPendingTitle => 'Payment Pending';

  @override
  String get ticketStatusPendingSubtitle => 'Waiting for MoMo confirmation.';

  @override
  String get ticketStatusPendingNote => 'Ticket reserved';

  @override
  String get ticketStatusValidTitle => 'Valid Ticket';

  @override
  String get ticketStatusValidSubtitle => 'Show this at the';

  @override
  String get ticketStatusValidNote => 'Present the QR code';

  @override
  String get ticketStatusUsedTitle => 'Ticket Used';

  @override
  String get ticketStatusUsedSubtitle => 'Ticket already scanned';

  @override
  String get ticketStatusUsedNote => 'Ticket already used';

  @override
  String get ticketStatusCancelledTitle => 'Ticket Cancelled';

  @override
  String get ticketStatusCancelledSubtitle => 'Ticket invalid';

  @override
  String get ticketStatusCancelledNote => 'Contact support';

  @override
  String get partnersHomeTooltip => 'Partners Home';

  @override
  String get partnersServicesTab => 'Services';

  @override
  String get partnersRayonWelcomeTitle => 'Welcome to Rayon Sports!';

  @override
  String get partnersRayonWelcomeSubtitle => 'Your fan membership has';

  @override
  String get partnersOpenRayonSports => 'Open Rayon Sports';

  @override
  String get partnersMembershipPerkRegistryAccess => 'Fan registry access';

  @override
  String get partnersMembershipPerkClubUpdates => 'Club updates';

  @override
  String get partnersMembershipPerkMemberQueue => 'Member queue priority';

  @override
  String get partnersMembershipPerkPriorityTickets => 'Priority ticket access';

  @override
  String get partnersMembershipPerkShopDiscount => 'Shop discount';

  @override
  String get partnersMembershipPerkVipQueue => 'VIP queue access';

  @override
  String get partnersMembershipPerkVipAccess => 'VIP event access';

  @override
  String get partnersMembershipPerkExclusiveEvents => 'Exclusive events';

  @override
  String get partnersNoFootballPartners => 'No football partners yet';

  @override
  String partnersComingSoonMessage(String partnerName) {
    return '$partnerName is coming soon!';
  }

  @override
  String get partnersRayonHubBadge => 'Official Fan Hub';

  @override
  String get partnersGamesMetricLabel => 'Games';

  @override
  String get partnersLoadingMessage => 'Loading partners…';

  @override
  String get partnersNoFinancePartners => 'No finance partners yet';

  @override
  String get partnersFinancePrepTitle => 'Financial Readiness';

  @override
  String get partnersFinancePrepSubtitle => 'Check your credit readiness';

  @override
  String get partnersReadinessChecklistCta => 'Credit Readiness Checklist';

  @override
  String partnersWhatsappMessage(String partnerName) {
    return 'Hi I\'d like to';
  }

  @override
  String get partnersNoServicePartners => 'No service partners yet';

  @override
  String get partnersInsurancePartnerBadge => 'Insurance Partner';

  @override
  String get partnersProfessionalServicesBadge => 'Professional Services';

  @override
  String get partnersServicePartnerBadge => 'Service Partner';

  @override
  String get partnersLoadErrorTitle => 'Load partners failed';

  @override
  String get partnersEmptyMessage => 'Partners will appear here';

  @override
  String get partnersClubShopSubtitle => 'Official merchandise';

  @override
  String get partnersFootballTab => 'Football';

  @override
  String get partnersFinanceTab => 'Finance';

  @override
  String get partnersFeaturesTitle => 'Features';

  @override
  String get momoNfcInvalidRequest => 'Invalid NFC payment request.';

  @override
  String get momoLaunchingUssd => 'Launching USSD…';

  @override
  String get momoNfcLaunchFailed => 'NFC launch failed Please';

  @override
  String get momoScreenTitle => 'Mobile Money';

  @override
  String get momoNfcLaunchingOverlay => 'Launching MoMo…';

  @override
  String get momoSendValidationError => 'Please enter a valid';

  @override
  String momoSendLaunchFailed(String countryName) {
    return 'Launch MoMo payment failed';
  }

  @override
  String momoFromNumber(String number) {
    return 'From $number';
  }

  @override
  String get momoRoutePhoneLabel => 'Phone Number';

  @override
  String get momoRouteCodeLabel => 'MoMo Code';

  @override
  String get momoRecipientCodeLabel => 'Recipient MoMo Code';

  @override
  String get momoRecipientPhoneLabel => 'Recipient Phone';

  @override
  String momoAmountLabel(String currency) {
    return 'Amount ($currency)';
  }

  @override
  String momoSendCompletesViaUssd(String countryName) {
    return 'Completes via USSD on';
  }

  @override
  String get momoContinueToUssd => 'Continue to USSD';

  @override
  String get momoTrustCardTitle => 'Before you pay';

  @override
  String get momoTrustCardSubtitle => 'COOL opens the network';

  @override
  String get momoTrustFeesTitle => 'Fees show before confirmation';

  @override
  String get momoTrustFeesSubtitle => 'The USSD prompt displays';

  @override
  String get momoTrustApprovalTitle => 'You approve on your';

  @override
  String get momoTrustApprovalSubtitle => 'COOL never completes the';

  @override
  String get momoTrustReceiptTitle => 'Receipts land in statements';

  @override
  String get momoTrustReceiptSubtitle => 'Matching Mobile Money SMS';

  @override
  String get momoReviewTitle => 'Review before USSD';

  @override
  String get momoReviewRecipientLabel => 'Recipient';

  @override
  String get momoReviewAmountLabel => 'Amount';

  @override
  String get momoReviewRouteLabel => 'Route';

  @override
  String get momoReviewFromLabel => 'From';

  @override
  String get momoReviewMissingRecipient => 'Add a recipient';

  @override
  String get momoReviewMissingAmount => 'Add amount';

  @override
  String get momoWhatHappensNextTitle => 'What happens next';

  @override
  String momoWhatHappensNextOpen(String countryName) {
    return 'COOL opens the $countryName';
  }

  @override
  String get momoWhatHappensNextConfirm => 'You confirm the amount';

  @override
  String get momoWhatHappensNextReceipt => 'A matching SMS confirmation';

  @override
  String get momoConfirmSendLabel => 'Send Money';

  @override
  String get momoStatementsPayerLabel => 'Payer';

  @override
  String get momoStatementsAllPayers => 'All payers';

  @override
  String get momoStatementsAllGroups => 'All groups';

  @override
  String get momoStatementsSelectCustomPeriod => 'Select custom period';

  @override
  String get momoStatementsNothingToDownload => 'Nothing to download yet.';

  @override
  String momoStatementsSavedFile(String fileName) {
    return 'Saved $fileName';
  }

  @override
  String momoStatementsDownloadedFile(String fileName) {
    return 'Downloaded $fileName';
  }

  @override
  String get momoStatementsDownloadFailed => 'Statement download failed.';

  @override
  String momoStatementsFilterSummaryPeriod(String period) {
    return 'Period: $period';
  }

  @override
  String momoStatementsFilterSummaryParty(String label, String value) {
    return '$label: $value';
  }

  @override
  String get momoStatementsFilterTitle => 'Filters & exports';

  @override
  String get momoStatementsSortByLabel => 'Sort';

  @override
  String get resetAction => 'Reset';

  @override
  String get momoStatementsPreparingLabel => 'Exporting…';

  @override
  String get momoStatementsPdfLabel => 'PDF';

  @override
  String get momoStatementsExcelLabel => 'Excel';

  @override
  String get groupsTabAll => 'All';

  @override
  String get groupsTabSaving => 'Saving';

  @override
  String get groupsTabCommunity => 'Community';

  @override
  String get groupsTabPublic => 'Public';

  @override
  String get groupsTabPrivate => 'Private';

  @override
  String groupsShareText(String groupName, String inviteUrl) {
    return 'Join $groupName on Cool';
  }

  @override
  String get groupsCreateNewTitle => 'Create a New Group';

  @override
  String get groupsCreateNewSubtitle => 'Saving or Community';

  @override
  String get groupsEmptyPublicTitle => 'No public groups found';

  @override
  String get groupsEmptyPublicMessage => 'Pull to refresh';

  @override
  String get groupsEmptyPrivateMessage => 'Create a group or';

  @override
  String groupsBankCustodianMeta(String partnerName) {
    return 'Bank custodian · $partnerName';
  }

  @override
  String groupsMomoRouteMeta(String number) {
    return 'MoMo route · $number';
  }

  @override
  String get groupsSavingGroupMeta => 'Saving group';

  @override
  String get groupsCommunityFundMeta => 'Community fund';

  @override
  String get groupsRaisedLabel => 'raised';

  @override
  String get groupsShareAction => 'Share';

  @override
  String get groupsLoadErrorTitle => 'Something went wrong';

  @override
  String get profileTierBlue => 'Blue';

  @override
  String get profileTierSilver => 'Silver';

  @override
  String get profileTierGold => 'Gold';

  @override
  String get profileTierPlatinum => 'Platinum';

  @override
  String get profileSavingIdentity => 'Saving identity details...';

  @override
  String get profileIdentityUpdated => 'Identity details updated';

  @override
  String get profileIdentityUpdateFailed => 'Failed to update identity';

  @override
  String get profileAppAccess => 'App access';

  @override
  String get profileManageAction => 'Manage';

  @override
  String profileCoolStatusValue(String tier, int points) {
    return '$tier · $points Tokens';
  }

  @override
  String get profileUserIdLabel => 'User ID';

  @override
  String get profileWalletLabel => 'Wallet';

  @override
  String get profileSetupTitle => 'Profile setup';

  @override
  String get profilePublicProfileLabel => 'Public profile';

  @override
  String get profileOfficialIdentityLabel => 'Official identity';

  @override
  String get profileTravelRoleLabel => 'Travel role';

  @override
  String get profilePassengerRoleLabel => 'Passenger';

  @override
  String get profileDriverRoleLabel => 'Driver';

  @override
  String get profileMomoCodeNotSet => 'MoMo code not set';

  @override
  String get profileDriverSetupPending => 'Driver setup pending';

  @override
  String get profileRegularDriverCadence => 'Regular driver';

  @override
  String get profileOccasionalDriverCadence => 'Occasional driver';

  @override
  String profileMobilityCreditsValue(int credits) {
    return '$credits credits';
  }

  @override
  String get profileMobilitySubscriptionActive => 'Subscription active';

  @override
  String profileMobilitySubscriptionUntil(String date) {
    return 'Subscribed until $date';
  }

  @override
  String get mobilityNoWhatsappAvailable => 'No WhatsApp contact yet';

  @override
  String get mobilityNoContactYet => 'No contact yet';

  @override
  String get mobilityLocationRequiredDriverMode =>
      'Location is required before';

  @override
  String momoSendMoneyOpensUssd(String countryName) {
    return 'Open $countryName MoMo USSD';
  }

  @override
  String get momoMoreToolsSubtitle => 'Statements QR and NFC';

  @override
  String get momoStatementsToolSubtitle => 'Review wallet and savings';

  @override
  String get momoNfcToolsTitle => 'NFC tools';

  @override
  String get momoNfcToolsSubtitle => 'Tap-to-pay and share route';

  @override
  String get basketScreenTitle => 'Basket';

  @override
  String get basketScreenHeadline => 'Basket is not live';

  @override
  String get basketScreenBody => 'Legacy route';

  @override
  String get basketScreenCardBody => 'Basket products are paused';

  @override
  String get basketScreenExpectationBalances => 'No live basket balances';

  @override
  String get basketScreenExpectationCreation => 'New basket creation is';

  @override
  String get basketScreenExpectationLinks => 'Existing deep links still';

  @override
  String get basketScreenBackHome => 'Back Home';
}
