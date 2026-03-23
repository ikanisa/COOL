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
  String resendCodeIn(Object seconds) {
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
  String memberCount(Object count) {
    return '$count members';
  }

  @override
  String get groupMembers => 'Members';

  @override
  String get recentContributions => 'Recent contributions';

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
  String totalItems(Object count) {
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
  String expiresIn(Object minutes) {
    return 'Expires in $minutes min';
  }

  @override
  String seatsLabel(Object count) {
    return '$count seat';
  }

  @override
  String seatsLabelPlural(Object count) {
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
  String get scheduleTripDepartureInPastError =>
      'Departure time is in the past.';

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
  String tripsUsedMessage(Object used) {
    return 'You have used $used';
  }

  @override
  String daysRemaining(Object count) {
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
  String fansCount(Object count) {
    return '$count fans';
  }

  @override
  String clubsCount(Object count) {
    return '$count clubs';
  }

  @override
  String gamesCount(Object count) {
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
  String cartItemCount(Object count) {
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
  String expiringInDays(Object count) {
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
  String genericErrorText(String error) {
    return 'Error: $error';
  }

  @override
  String get noConnection => 'No internet connection.';

  @override
  String get offlineNotice => 'You\'re offline Showing cached';

  @override
  String goodMorningUser(Object name) {
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
  String inMinutesShort(Object count) {
    return 'in ${count}min';
  }

  @override
  String inHoursShort(Object count) {
    return 'in ${count}h';
  }

  @override
  String inDaysShort(Object count) {
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
  String targetAmount(Object amount) {
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
  String homeActiveCount(Object count) {
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
  String profileMomoQrSubtitle(Object number) {
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
  String walletLedgerSubtitle(Object shown, Object total) {
    return '$shown/$total shown';
  }

  @override
  String get savingsEmptyTitle => 'No savings entries yet';

  @override
  String get savingsEmptyMessage => 'Savings contributions will appear';

  @override
  String get savingsStatementTitle => 'Savings statement';

  @override
  String savingsStatementSubtitle(Object shown, Object total) {
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
  String fansScreenBody(Object clubName) {
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
  String ticketShareMatchText(Object matchTitle) {
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
  String partnersComingSoonMessage(Object partnerName) {
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
  String get partnersWhatsappMessage => 'Hi I\'d like to';

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
  String get momoSendLaunchFailed => 'Launch MoMo payment failed';

  @override
  String momoFromNumber(Object number) {
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
  String momoAmountLabel(Object currency) {
    return 'Amount ($currency)';
  }

  @override
  String get momoSendCompletesViaUssd => 'Completes via USSD on';

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
  String momoWhatHappensNextOpen(Object countryName) {
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
  String momoStatementsSavedFile(Object fileName) {
    return 'Saved $fileName';
  }

  @override
  String momoStatementsDownloadedFile(Object fileName) {
    return 'Downloaded $fileName';
  }

  @override
  String get momoStatementsDownloadFailed => 'Statement download failed.';

  @override
  String momoStatementsFilterSummaryPeriod(Object period) {
    return 'Period: $period';
  }

  @override
  String momoStatementsFilterSummaryParty(Object label, Object value) {
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
  String groupsShareText(Object groupName) {
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
  String groupsBankCustodianMeta(Object partnerName) {
    return 'Bank custodian · $partnerName';
  }

  @override
  String groupsMomoRouteMeta(Object number) {
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
  String profileCoolStatusValue(Object points, Object tier) {
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
  String profileMobilityCreditsValue(Object credits) {
    return '$credits credits';
  }

  @override
  String get profileMobilitySubscriptionActive => 'Subscription active';

  @override
  String profileMobilitySubscriptionUntil(Object date) {
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
  String momoSendMoneyOpensUssd(Object countryName) {
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

  @override
  String get activeMissions => 'Active Missions';

  @override
  String get comingSoon => 'Coming Soon';

  @override
  String get scanThisQrCode => 'Scan this QR code to join Cool';

  @override
  String get back => 'Back';

  @override
  String get shareLink => 'Share link';

  @override
  String get qrCode => 'QR Code';

  @override
  String get sendInvite => 'Send Invite';

  @override
  String get friendJoins => 'Friend Joins';

  @override
  String get earnTokens => 'Earn Tokens';

  @override
  String get waysToEarn => 'Ways to Earn';

  @override
  String get rewardsMarketplace => 'Rewards Marketplace';

  @override
  String get topEarners => 'Top Earners';

  @override
  String get currentStreak => 'Current Streak';

  @override
  String get bestStreak => 'Best Streak';

  @override
  String get grace => 'Grace';

  @override
  String get yourGroupIsClose => 'Your group is close!';

  @override
  String get attendAMatch => 'Attend a match';

  @override
  String get earn10TokensFor => 'Earn 10 Tokens for attending';

  @override
  String get oneMoreTrip => 'One more trip!';

  @override
  String get postYourRoute => 'Post your route';

  @override
  String get helpOthersFindA => 'Help others find a ride';

  @override
  String get confirmTransaction => 'Confirm transaction';

  @override
  String get joinASavingsGroup => 'Join a savings group';

  @override
  String get earn10TokensPer => 'Earn 10 Tokens per contribution';

  @override
  String get becomeARayonFan => 'Become a Rayon fan';

  @override
  String get joinTheClubAnd => 'Join the club and earn rewards';

  @override
  String get streakAtRisk => 'Streak at risk!';

  @override
  String get doAnActionToday => 'Do an action today';

  @override
  String get yourFriend => 'Your friend ';

  @override
  String get invitedYouToJoin => ' invited you to join Cool.';

  @override
  String get momoPay => 'MoMo Pay';

  @override
  String get payAtShopsAnd => 'Pay at shops and partners';

  @override
  String get amount => 'Amount';

  @override
  String get rate => 'Rate';

  @override
  String get loan => 'Loan';

  @override
  String get saved => 'Saved';

  @override
  String get groups => 'Groups';

  @override
  String get explore => 'Explore';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String get fans => 'Fans';

  @override
  String get join => 'Join';

  @override
  String get buyTickets => 'Buy Tickets';

  @override
  String get shop => 'Shop';

  @override
  String get walletCashflow => 'Wallet Cashflow';

  @override
  String get savingsDiscipline => 'Savings Discipline';

  @override
  String get groupReliability => 'Group Reliability';

  @override
  String get profileStrength => 'Profile Strength';

  @override
  String get officialNameOnFile => 'Official name on file';

  @override
  String get officialPhoneConfirmed => 'Official phone confirmed';

  @override
  String get kycReviewStarted => 'KYC review started';

  @override
  String get kycFullyVerified => 'KYC fully verified';

  @override
  String get creditReportGenerated => 'Credit report generated';

  @override
  String get walletHistoryDepth => 'Wallet history depth';

  @override
  String get activeMonths => 'Active months';

  @override
  String get savingsAndGroupEvidence => 'Savings and group evidence';

  @override
  String get bankAccountOpening => 'Bank Account Opening';

  @override
  String get loanApplication => 'Loan Application';

  @override
  String get refresh => 'Refresh';

  @override
  String get bankReportGeneratedIn => 'Bank Report generated in Google Docs!';

  @override
  String get open => 'OPEN';

  @override
  String get failedToGenerateBank => 'Failed to generate bank report.';

  @override
  String get generateGoogleDoc => 'Generate Google Doc';

  @override
  String get incomeStability => 'Income Stability';

  @override
  String get strengths => 'STRENGTHS';

  @override
  String get risks => 'RISKS';

  @override
  String get connectYourMomoTo => 'Connect your MoMo to see AI insights.';

  @override
  String get recentApplications => 'Recent applications';

  @override
  String get eligiblePartners => 'Eligible partners';

  @override
  String get kyc => 'KYC';

  @override
  String get score => 'Score';

  @override
  String get checks => 'Checks';

  @override
  String get viewAllPartners => 'View all partners';

  @override
  String get readiness => 'Readiness';

  @override
  String get created => 'Created';

  @override
  String get applicationPath => 'Application path';

  @override
  String get loanApplication1 => 'Loan application';

  @override
  String get accountOpening => 'Account opening';

  @override
  String get requestedProduct => 'Requested product';

  @override
  String get internalNote => 'Internal note';

  @override
  String get saveDraft => 'Save Draft';

  @override
  String get openReadiness => 'Open readiness';

  @override
  String get window => 'Window';

  @override
  String get engine => 'Engine';

  @override
  String get walletIn => 'Wallet In';

  @override
  String get walletOut => 'Wallet Out';

  @override
  String get savings => 'Savings';

  @override
  String get averageSave => 'Average Save';

  @override
  String get walletHistoryIsStill => 'Wallet history is still';

  @override
  String get incomingCashflowNeedsMore => 'Incoming cashflow needs more';

  @override
  String get savingsPatternIsNot => 'Savings pattern is not';

  @override
  String get noConfirmedGroupFound => 'No confirmed group found';

  @override
  String get groupContributionActivityIs => 'Group contribution activity is';

  @override
  String get profileVerificationIsHolding => 'Profile verification is holding';

  @override
  String get verifiedBehaviourLooksHealthy =>
      'Verified behaviour looks healthy';

  @override
  String get mobileMoneyNumber => 'Mobile Money Number';

  @override
  String get resendVerificationCode => 'Resend verification code';

  @override
  String get verify => 'Verify';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get mobileMoney => 'Mobile Money';

  @override
  String get credit => 'Credit';

  @override
  String get mobility => 'Mobility';

  @override
  String get rejectAllocation => 'Reject allocation';

  @override
  String get thisWillRemoveThe => 'This removes the pending allocation.';

  @override
  String get reject => 'Reject';

  @override
  String get clear => 'Clear';

  @override
  String get str07xxxxxxxx => '07XXXXXXXX';

  @override
  String get allocateToMember => 'Allocate to member';

  @override
  String get groups1 => 'GROUPS';

  @override
  String get members1 => 'MEMBERS';

  @override
  String get contributions => 'CONTRIBUTIONS';

  @override
  String get ledgers => 'LEDGERS';

  @override
  String get allocations => 'ALLOCATIONS';

  @override
  String get loans => 'LOANS';

  @override
  String get baskets => 'BASKETS';

  @override
  String get bankAdmin => 'Bank Admin';

  @override
  String get addVehicleType => 'Add vehicle type';

  @override
  String get adminWorkspaces => 'Admin Workspaces';

  @override
  String get platform => 'Platform';

  @override
  String get globalAppOperationsContent => 'Global app operations content';

  @override
  String get platformAdmin => 'Platform Admin';

  @override
  String get usersPartnersServicesApp => 'Users partners services app';

  @override
  String get partnerWorkspaces => 'Partner Workspaces';

  @override
  String get partnerscopedAdminSurfacesFor =>
      'Partner-scoped admin surfaces for';

  @override
  String get bankCustodianWorkspaces => 'Bank Custodian Workspaces';

  @override
  String get groupSavingsOversightLedgers => 'Group savings oversight ledgers';

  @override
  String get openTheBankCustodian => 'Open the bank custodian';

  @override
  String get addPartner => 'Add partner';

  @override
  String get inactive => 'Inactive';

  @override
  String get mock => 'Mock';

  @override
  String get website => 'Website';

  @override
  String get releaseDashboard => 'Release Dashboard';

  @override
  String get triageQueue => 'Triage Queue';

  @override
  String get recentSignals => 'Recent Signals';

  @override
  String get service => 'Service';

  @override
  String get reference => 'Reference';

  @override
  String get table => 'Table';

  @override
  String get record => 'Record';

  @override
  String get component => 'Component';

  @override
  String get function => 'Function';

  @override
  String get code => 'Code';

  @override
  String get addConfigEntry => 'Add config entry';

  @override
  String get rolloutGovernance => 'Rollout Governance';

  @override
  String get mobilitySubscriptionRecipient => 'Mobility Subscription Recipient';

  @override
  String get addRecipient => 'Add Recipient';

  @override
  String get partnerPaymentRoutes => 'Partner Payment Routes';

  @override
  String get additionalConfig => 'Additional Config';

  @override
  String get admins => 'Admins';

  @override
  String get drivers => 'Drivers';

  @override
  String get momo => 'MoMo';

  @override
  String get driver => 'Driver';

  @override
  String get deleteBatch => 'Delete Batch';

  @override
  String get bank => 'Bank';

  @override
  String get rayon => 'Rayon';

  @override
  String get revoke => 'Revoke';

  @override
  String get pasteUserUuid => 'Paste user UUID';

  @override
  String get paste => 'Paste';

  @override
  String get addQuickAction => 'Add quick action';

  @override
  String get partnerAdmin => 'Partner Admin';

  @override
  String get openRayonSportsAdmin => 'Open Rayon Sports Admin';

  @override
  String get title => 'Title';

  @override
  String get emoji => 'Emoji';

  @override
  String get theme => 'Theme';

  @override
  String get starts => 'Starts';

  @override
  String get ends => 'Ends';

  @override
  String get rewardsDescription => 'Rewards Description';

  @override
  String get all => 'All';

  @override
  String get deleteContent => 'Delete content?';

  @override
  String get editChildTextedit => 'edit\', child: Text(\'Edit';

  @override
  String get approve => 'Approve';

  @override
  String get contentType => 'Content Type';

  @override
  String get status => 'Status';

  @override
  String get country => 'Country';

  @override
  String get backToProfile => 'Back to profile';

  @override
  String get description => 'Description';

  @override
  String get missionType => 'Mission Type';

  @override
  String get targetValue => 'Target Value';

  @override
  String get scope => 'Scope';

  @override
  String get rewardPoints => 'Reward Tokens';

  @override
  String get rewardDescription => 'Reward Description';

  @override
  String get addService => 'Add service';

  @override
  String get mockService => 'Mock service';

  @override
  String get partnerSelector => 'Partner selector';

  @override
  String get slug => 'Slug';

  @override
  String get subtitle => 'Subtitle';

  @override
  String get colorHex => 'Color Hex';

  @override
  String get interestRate => 'Interest Rate';

  @override
  String get loanMultiplier => 'Loan Multiplier';

  @override
  String get momoRecipient => 'MoMo Recipient';

  @override
  String get recipientType => 'Recipient Type';

  @override
  String get icon => 'Icon';

  @override
  String get targetAudience => 'Target Audience';

  @override
  String get sortOrder => 'Sort Order';

  @override
  String get statusSelector => 'Status selector';

  @override
  String get draftChildTextdraft => 'draft\', child: Text(\'Draft';

  @override
  String get activeChildTextactive => 'active\', child: Text(\'Active';

  @override
  String get inactiveChildTextinactive => 'inactive\', child: Text(\'Inactive';

  @override
  String get allGroups => 'All groups';

  @override
  String get repaid => 'Repaid';

  @override
  String get markDisbursed => 'Mark Disbursed';

  @override
  String get groups2 => 'groups';

  @override
  String get contributions1 => 'contributions';

  @override
  String get manualReview => 'manual review';

  @override
  String get aum => 'AUM';

  @override
  String get loansOut => 'loans out';

  @override
  String get activeLoans => 'active loans';

  @override
  String get activeBaskets => 'active baskets';

  @override
  String get category => 'Category';

  @override
  String get bucket => 'Bucket';

  @override
  String get target => 'Target';

  @override
  String get searchGroups => 'Search groups...';

  @override
  String get balance => 'Balance';

  @override
  String get members2 => 'Members';

  @override
  String get contributions2 => 'Contributions';

  @override
  String get monthly => 'Monthly';

  @override
  String get lastActivity => 'Last activity';

  @override
  String get viewDetails => 'View details';

  @override
  String get viewLedger => 'View ledger';

  @override
  String get members3 => 'Members';

  @override
  String get contributions3 => 'Contributions';

  @override
  String get raised => 'Raised';

  @override
  String get openLedger => 'Open ledger';

  @override
  String get editRolloutSettings => 'Edit rollout settings';

  @override
  String get rwandaOnly => 'Rwanda only';

  @override
  String get editMomoSubscriptionConfig => 'Edit MoMo subscription config';

  @override
  String get editPaymentRouteFor => 'Edit payment route for';

  @override
  String get backToAdmin => 'Back to admin';

  @override
  String get rayonSportsAdmin => 'Rayon Sports Admin';

  @override
  String get recentContributions1 => 'Recent contributions';

  @override
  String get groupSettings => 'Group settings';

  @override
  String get bankCustodian => 'Bank custodian';

  @override
  String get momoToCreator => 'MOMO to creator';

  @override
  String get bankheldAndInsured => 'Bank-held and insured.';

  @override
  String get groupName => 'Group Name';

  @override
  String get phoneNumber => 'Phone Number';

  @override
  String get merchantCode => 'Merchant Code';

  @override
  String get dailyValueDaily => 'Daily\', value: \'daily';

  @override
  String get weeklyValueWeekly => 'Weekly\', value: \'weekly';

  @override
  String get monthlyValueMonthly => 'Monthly\', value: \'monthly';

  @override
  String get discover => 'Discover';

  @override
  String get peopleOutline => 'People Outline';

  @override
  String get lockOutline => 'Lock Outline';

  @override
  String get loadGroupsFailed => 'Load groups failed';

  @override
  String get action => 'Action';

  @override
  String get saveChanges => 'Save changes';

  @override
  String get add => 'Add';

  @override
  String get contributionAmountInRwandan => 'Contribution amount in Rwandan';

  @override
  String get inviteFromContacts => 'Invite from Contacts';

  @override
  String get wallet => 'Wallet';

  @override
  String get coolTokens => 'Cool Tokens';

  @override
  String get inviteFriends => 'Invite Friends';

  @override
  String get momoStatements => 'MoMo Statements';

  @override
  String get personalInfo => 'Personal Info';

  @override
  String get settings => 'Settings';

  @override
  String get view => 'VIEW';

  @override
  String get failedToCompleteArchive => 'Failed to complete archive.';

  @override
  String get frontOfId => 'Front of ID';

  @override
  String get liveSelfie => 'Live Selfie';

  @override
  String get verifyIdentity => 'Verify Identity';

  @override
  String get fullName => 'Full name';

  @override
  String get dateOfBirth => 'Date of birth';

  @override
  String get documentNumber => 'Document number';

  @override
  String get documentType => 'Document type';

  @override
  String get gender => 'Gender';

  @override
  String get nationality => 'Nationality';

  @override
  String get ocrConfidence => 'OCR confidence';

  @override
  String get useExtractedDetails => 'Use extracted details';

  @override
  String get scanAgain => 'Scan again';

  @override
  String get takePhoto => 'Take photo';

  @override
  String get upload => 'Upload';

  @override
  String get nationalidLabelNationalId => 'national_id\', label: \'National ID';

  @override
  String get passportLabelPassport => 'passport\', label: \'Passport';

  @override
  String get drivinglicenseLabelDrivingLicence =>
      'driving_license\', label: \'Driving licence';

  @override
  String get defaultKey => 'Default';

  @override
  String get passenger => 'Passenger';

  @override
  String get optional => 'Optional';

  @override
  String get paymentAndActivityAlerts => 'Payment and activity alerts';

  @override
  String get openSystemSettings => 'Open system settings';

  @override
  String get smsPaymentSync => 'SMS payment sync';

  @override
  String get location => 'Location';

  @override
  String get neededForNearbyMobility => 'Needed for nearby mobility';

  @override
  String get camera => 'Camera';

  @override
  String get usedForMomoQr => 'Used for MoMo QR';

  @override
  String get contacts => 'Contacts';

  @override
  String get usedWhenInvitingGroup => 'Used when inviting group';

  @override
  String get nfc => 'NFC';

  @override
  String get ready => 'Ready';

  @override
  String get offInCool => 'Off in COOL';

  @override
  String get needsAndroidAccess => 'Needs Android access';

  @override
  String get blockedInSystem => 'Blocked in system';

  @override
  String get deviceSettingOff => 'Device setting off';

  @override
  String get notAvailable => 'Not available';

  @override
  String get legalNameForReports => 'Legal name for reports';

  @override
  String get systemDefault => 'System default';

  @override
  String get lightMode => 'Light mode';

  @override
  String get darkMode => 'Dark mode';

  @override
  String get vehicleDetails => 'Vehicle details';

  @override
  String get subscriptionAccess => 'Subscription access';

  @override
  String get renewalNote => 'Renewal note';

  @override
  String get selectedPlan => 'Selected plan';

  @override
  String get editVehicleInfo => 'Edit vehicle info';

  @override
  String get vehicleType => 'Vehicle type';

  @override
  String get plateNumber => 'Plate number';

  @override
  String get baseLocation => 'Base location';

  @override
  String get verification => 'Verification';

  @override
  String get plan => 'Plan';

  @override
  String get credits => 'Credits';

  @override
  String get thisMonth => 'This month';

  @override
  String get retryLoadingDriverProfile => 'Retry loading driver profile';

  @override
  String get trips => 'Trips';

  @override
  String get addReturnTrip1 => 'Add return trip';

  @override
  String get route => 'Route';

  @override
  String get departure => 'Departure';

  @override
  String get returnKey => 'Return';

  @override
  String get repeat => 'Repeat';

  @override
  String get preview => 'Preview';

  @override
  String get trike => 'Trike';

  @override
  String get truck => 'Truck';

  @override
  String get others => 'Others';

  @override
  String get payViaMomoUssd1 => 'Pay via MOMO USSD';

  @override
  String get tripsPosted => 'Trips Posted';

  @override
  String get mobilityCredits => 'Mobility Credits';

  @override
  String get openSubscriptionOptions => 'Open subscription options';

  @override
  String get allValueAll => 'All\', value: \'All';

  @override
  String get motoValueMoto => 'Moto\', value: \'Moto';

  @override
  String get cabValueCab => 'Cab\', value: \'Cab';

  @override
  String get truckValueTruck => 'Truck\', value: \'Truck';

  @override
  String get trikeValueTrike => 'Trike\', value: \'Trike';

  @override
  String get othersValueOthers => 'Others\', value: \'Others';

  @override
  String get nearby => 'Nearby';

  @override
  String get schedule => 'Schedule';

  @override
  String get returnTrip => 'Return trip';

  @override
  String get recurring => 'Recurring';

  @override
  String get postedBy => 'Posted by';

  @override
  String get routeCoordinates => 'Route coordinates';

  @override
  String get chatFlowValueAgree => 'Chat flow\', value: \'Agree via WhatsApp.';

  @override
  String get priceNote => 'Price note';

  @override
  String get confirmedViaWhatsapp => 'Confirmed via WhatsApp';

  @override
  String get shareThisTrip => 'Share this trip';

  @override
  String get whatsappUnavailable => 'WhatsApp unavailable.';

  @override
  String get hasReturnTrip => 'Has return trip';

  @override
  String get regularDriver => 'Regular driver';

  @override
  String get currentRoute => 'Current route';

  @override
  String get area => 'Area';

  @override
  String get vehicleStatus => 'Vehicle status';

  @override
  String get lastActive => 'Last active';

  @override
  String get chatFlowValueAgree1 => 'Chat flow\', value: \'Agree via WhatsApp';

  @override
  String get agreedViaWhatsapp => 'Agreed via WhatsApp';

  @override
  String get tripDestinationSearch => 'Trip destination search';

  @override
  String get searchLandmarkOrAddress => 'Search landmark or address';

  @override
  String get defaultMode => 'Default mode';

  @override
  String get postTrip1 => 'Post trip';

  @override
  String get tripType => 'Trip type';

  @override
  String get exploreTrips => 'Explore trips';

  @override
  String get findARideNearby => 'Find a ride nearby.';

  @override
  String get manageYourTrips => 'Manage your trips';

  @override
  String get manageYourPostedTrips => 'Manage your posted trips.';

  @override
  String get filterByTripType => 'Filter by trip type.';

  @override
  String get passengerTrips => 'Passenger trips';

  @override
  String get ridesNearYou => 'Rides near you.';

  @override
  String get driverReturns => 'Driver returns';

  @override
  String get driversWithAvailableSeats => 'Drivers with available seats.';

  @override
  String get pickup => 'Pickup';

  @override
  String get dropoff => 'Dropoff';

  @override
  String get useCurrentLocation => 'Use current location';

  @override
  String get searchPlaces => 'Search places';

  @override
  String get loadingNearbyTrips => 'Loading nearby trips';

  @override
  String get loadNearbyTripsFailed => 'Load nearby trips failed';

  @override
  String get loadingYourTrips => 'Loading your trips';

  @override
  String get loadYourTripsFailed => 'Load your trips failed';

  @override
  String get noTripsPostedYet => 'No trips posted yet';

  @override
  String get postATripTo => 'Post a trip to get started';

  @override
  String get noDriverReturnsAvailable => 'No driver returns available';

  @override
  String get tryAnotherVehicleType => 'Try another vehicle type';

  @override
  String get tripActions => 'Trip actions';

  @override
  String get expired => 'Expired';

  @override
  String get cancelled => 'Cancelled';

  @override
  String get paused => 'Paused';

  @override
  String get matched => 'Matched';

  @override
  String get vehicleType1 => 'Vehicle Type';

  @override
  String get plateNumber1 => 'Plate Number';

  @override
  String get baseLocation1 => 'Base Location';

  @override
  String get setBaseLocation => 'Set base location';

  @override
  String get vehicleType2 => 'Vehicle Type';

  @override
  String get plateNumber2 => 'Plate Number';

  @override
  String get baseLocation2 => 'Base Location';

  @override
  String get searchGooglePlaces => 'Search Google Places';

  @override
  String get home => 'Home';

  @override
  String get syncSms => 'Sync SMS';

  @override
  String get incoming => 'Incoming';

  @override
  String get outgoing => 'Outgoing';

  @override
  String get entries => 'Entries';

  @override
  String get postedValue => 'Posted value';

  @override
  String get payers => 'Payers';

  @override
  String get momoNumber1 => 'MoMo Number';

  @override
  String get momoCode => 'MoMo Code';

  @override
  String get momoNumber2 => 'MoMo Number';

  @override
  String get generateQr => 'Get QR';

  @override
  String get deepHistoricalSync => 'Deep historical sync';

  @override
  String get privacyFocused => 'Privacy focused';

  @override
  String get alwaysInSync => 'Always in sync';

  @override
  String get maybeLater => 'Maybe later';

  @override
  String get allowAccess => 'Allow access';

  @override
  String get proceedAnyway => 'Proceed Anyway';

  @override
  String get payByUssd => 'Pay by USSD';

  @override
  String get momoNumber3 => 'MoMo Number';

  @override
  String get momoNumber4 => 'MoMo Number';

  @override
  String get statements => 'Statements';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get momoQr => 'MOMO QR';

  @override
  String get nfcPay => 'NFC pay';

  @override
  String get changeStatementPeriod => 'Change statement period';

  @override
  String get reset => 'Reset';

  @override
  String get applyFilters => 'Apply filters';

  @override
  String get pdf => 'PDF';

  @override
  String get excel => 'Excel';

  @override
  String get fan => 'Fan';

  @override
  String get standardMembership => 'Standard membership';

  @override
  String get matches => 'matches';

  @override
  String get products => 'products';

  @override
  String get ticketRevenue => 'Ticket Revenue';

  @override
  String get shopRevenue => 'Shop Revenue';

  @override
  String get addMatch => 'Add Match';

  @override
  String get addProduct => 'Add Product';

  @override
  String get sendNotification => 'Send Notification';

  @override
  String get current => 'Current';

  @override
  String get unlocked => 'Unlocked';

  @override
  String get rayonSports => 'Rayon Sports';

  @override
  String get memberRegistry => 'Member Registry';

  @override
  String get supportClub => 'Support Club';

  @override
  String get nextMatch => 'Next Match';

  @override
  String get openProfile => 'Open Profile';

  @override
  String get viewPlans => 'View Plans';

  @override
  String get noMatchOnSale => 'No match on sale';

  @override
  String get analytics => 'Analytics';

  @override
  String get shopProducts => 'Shop Products';

  @override
  String get keepTheCatalogCurrent => 'Keep the catalog current';

  @override
  String get addProduct1 => 'Add product';

  @override
  String get active1 => 'active';

  @override
  String get stock => 'stock';

  @override
  String get low => 'low';

  @override
  String get noShopProductsYet => 'No shop products yet';

  @override
  String get name => 'Name';

  @override
  String get stock1 => 'Stock';

  @override
  String get emojiIcon => 'Emoji Icon';

  @override
  String get statusInactive => 'Status inactive';

  @override
  String get packageActive => 'Package active';

  @override
  String get inactivePackagesRemainHidden => 'Inactive packages remain hidden';

  @override
  String get savePackage => 'Save package';

  @override
  String get membershipPackages => 'Membership Packages';

  @override
  String get manageSupporterfacingTierCopy =>
      'Manage supporter-facing tier copy';

  @override
  String get plans => 'plans';

  @override
  String get tier => 'Tier';

  @override
  String get benefits => 'Benefits';

  @override
  String get members4 => 'Members';

  @override
  String get expired1 => 'expired';

  @override
  String get points => 'tokens';

  @override
  String get searchMembers => 'Search members';

  @override
  String get noFanMembershipsYet => 'No fan memberships yet';

  @override
  String get noMembersMatchFilter => 'No members match filter';

  @override
  String get points1 => 'Tokens';

  @override
  String get memberCsvCopiedTo => 'Member CSV copied to clipboard';

  @override
  String get matches1 => 'Matches';

  @override
  String get scheduleFixturesAdjustPricing =>
      'Schedule fixtures adjust pricing';

  @override
  String get addMatch1 => 'Add match';

  @override
  String get scheduled => 'scheduled';

  @override
  String get onSale => 'on sale';

  @override
  String get noMatchesHaveYet => 'No matches have yet';

  @override
  String get homeTeam => 'Home Team';

  @override
  String get awayTeam => 'Away Team';

  @override
  String get competition => 'Competition';

  @override
  String get venue => 'Venue';

  @override
  String get generalPrice => 'General Price';

  @override
  String get vipPrice => 'VIP Price';

  @override
  String get capacity => 'Capacity';

  @override
  String get initiatives => 'Initiatives';

  @override
  String get trackAndManageCommunity => 'Track and manage community causes';

  @override
  String get addInitiative => 'Add initiative';

  @override
  String get causes => 'causes';

  @override
  String get active2 => 'active';

  @override
  String get failedToLoadCauses => 'Failed to load causes';

  @override
  String get pullToRetry => 'Pull to retry';

  @override
  String get supporters => 'Supporters';

  @override
  String get causes1 => 'Causes';

  @override
  String get loadThisCauseFailed => 'load this cause failed';

  @override
  String get tryAgain => 'Try again';

  @override
  String get initiativeNotFound => 'Initiative not found';

  @override
  String get thisCauseMayHave => 'This cause may have';

  @override
  String get shareThisInitiative => 'Share this initiative';

  @override
  String get inviteSupportersToBack => 'Invite supporters to back';

  @override
  String get momoRef => 'MoMo ref';

  @override
  String get started => 'Started';

  @override
  String get refreshPaymentStatus => 'Refresh payment status';

  @override
  String get fanProfile => 'Fan Profile';

  @override
  String get showFanQr => 'Show Fan QR';

  @override
  String get priorityTickets => 'Priority Tickets';

  @override
  String get earlyAccessToMatch => 'Early access to match tickets';

  @override
  String get vipEvents => 'VIP Events';

  @override
  String get exclusiveFanMeetups => 'Exclusive fan meet-ups';

  @override
  String get freeKit => 'Free Kit';

  @override
  String get freeOfficialKitPer => 'Free official kit per season';

  @override
  String get shopOrders => 'Shop Orders';

  @override
  String get manageFulfilmentQueueAnd =>
      'Manage fulfilment queue and track order status.';

  @override
  String get orders => 'orders';

  @override
  String get pending1 => 'pending';

  @override
  String get revenue => 'revenue';

  @override
  String get noShopOrdersYet => 'No shop orders yet';

  @override
  String get noOrdersMatchThis => 'No orders match this filter';

  @override
  String get date => 'Date';

  @override
  String get address => 'Address';

  @override
  String get momoRef1 => 'MoMo Ref';

  @override
  String get deletePaymentRoute => 'Delete payment route';

  @override
  String get financeWorkspaceCouldNot => 'Finance workspace could not';

  @override
  String get finance => 'Finance';

  @override
  String get manageRayonPaymentRouting => 'Manage Rayon payment routing';

  @override
  String get newRoute => 'New route';

  @override
  String get total1 => 'total';

  @override
  String get valid => 'valid';

  @override
  String get used => 'used';

  @override
  String get noTicketsFound => 'No tickets found';

  @override
  String get noTicketsMatchThis => 'No tickets match this filter';

  @override
  String get confirmEntry => 'Confirm Entry';

  @override
  String get refund => 'Refund';

  @override
  String get ticketMatchFilterCurrent => 'Ticket match filter Current';

  @override
  String get gateCheck => 'Gate Check';

  @override
  String get eg50000 => 'e.g. 50,000';

  @override
  String get shareTickets => 'Share tickets';

  @override
  String get myTickets1 => 'My tickets';

  @override
  String get inviteSupportersToBuy => 'Invite supporters to buy';

  @override
  String get browseMatches => 'Browse Matches';

  @override
  String get paymentPending => 'PAYMENT PENDING';

  @override
  String get readyForEntry => 'READY FOR ENTRY';

  @override
  String get pastTickets => 'PAST TICKETS';

  @override
  String get fanClub => 'Fan Club';

  @override
  String get membersPreview => 'Members preview';

  @override
  String get moreDetails => 'More details';

  @override
  String get inviteSupporters => 'Invite supporters';

  @override
  String get inviteSupportersToJoin => 'Invite supporters to join';

  @override
  String get rating => 'Rating';

  @override
  String get createClub => 'Create Club';

  @override
  String get searchNameOrId => 'Search name or ID...';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get memberDiscount => 'Member discount';

  @override
  String get refreshOrderStatus => 'Refresh order status';

  @override
  String get backToShop => 'Back to shop';

  @override
  String get viewProfileOrders => 'View profile orders';

  @override
  String get orderId => 'Order ID';

  @override
  String get delivery => 'Delivery';

  @override
  String get checkoutCart => 'Checkout cart';

  @override
  String get showAllItems => 'Show all items';

  @override
  String get requestAQuote => 'Request a Quote';

  @override
  String get openRayonSports => 'Open Rayon Sports';

  @override
  String get noFootballPartnersYet => 'No football partners yet';

  @override
  String get featuredExperiences => 'Featured experiences';

  @override
  String get jerseysFanGearAnd => 'Jerseys fan gear and';

  @override
  String get noFinancePartnersYet => 'No finance partners yet';

  @override
  String get openReadinessChecklist => 'Open readiness checklist';

  @override
  String get noServicePartnersYet => 'No service partners yet';

  @override
  String get loadPartnersFailed => 'load partners failed';

  @override
  String get rwandaAgents => 'Rwanda Agents';

  @override
  String get rwandaPlatformCoverage => 'Rwanda Platform Coverage';

  @override
  String get zeroHallucination => 'Zero Hallucination';

  @override
  String get jurisdictionLocked => 'Jurisdiction Locked';

  @override
  String get qualitygatedOutputs => 'Quality-Gated Outputs';

  @override
  String get rwandaProfessionalStandards => 'Rwanda Professional Standards';

  @override
  String get openAccount => 'Open Account';

  @override
  String get digitalOnboarding => 'Digital onboarding';

  @override
  String get groupSavings => 'Group Savings';

  @override
  String get digitalGroupWallet => 'Digital group wallet';

  @override
  String get getLoan => 'Get Loan';

  @override
  String get fastCreditAccess => 'Fast credit access';

  @override
  String get coolAppLogo => 'Cool app logo';

  @override
  String get saving => 'Saving';

  @override
  String get community => 'Community';

  @override
  String get confirmCustomAmount => 'Confirm custom amount';

  @override
  String get loadingContent => 'Loading content';

  @override
  String get seat => 'Seat';

  @override
  String get fanId => 'Fan ID';

  @override
  String get price => 'Price';

  @override
  String get tripCard => 'Trip card';

  @override
  String get memberId => 'Member ID';

  @override
  String get points2 => 'Tokens';

  @override
  String get askAboutYourFinances => 'Ask about your finances...';

  @override
  String get openQuestAction => 'Open quest action';

  @override
  String get retake => 'Retake';

  @override
  String get searchContacts => 'Search contacts';

  @override
  String get searchByNameOr => 'Search by name or';

  @override
  String get contactsAccessDenied => 'Contacts access denied';

  @override
  String get contactsAreOffIn => 'Contacts are off in';

  @override
  String get contactsAccessNeeded => 'Contacts access needed';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get eventsValue => 'Events\', value: \'—';

  @override
  String get ratingValue => 'Rating\', value: \'—';

  @override
  String get send => 'Send';

  @override
  String get momo1 => 'MOMO';

  @override
  String get scanTicket => 'Scan Ticket';

  @override
  String get goBack => 'Go Back';

  @override
  String get cameraIsOffIn => 'Camera is off in';

  @override
  String get cameraIsBlockedIn => 'Camera is blocked in';

  @override
  String get cameraNotAvailable => 'Camera not available';

  @override
  String get allowCameraAccess => 'Allow camera access';

  @override
  String get closeScanner => 'Close scanner';

  @override
  String get toggleFlashlight => 'Toggle flashlight';

  @override
  String get scanAnother => 'Scan Another';

  @override
  String get shareViaContact => 'Share via Contact';

  @override
  String get share => 'Share';

  @override
  String get copyInviteLink => 'Copy invite link';

  @override
  String get localBlur => 'LOCAL BLUR';

  @override
  String get cool => 'Cool';

  @override
  String get rewardsProgram => 'Rewards Program';

  @override
  String get str14DaysStreak => '14 Days Streak';

  @override
  String get str50Tokens => '+50 Tokens';

  @override
  String get wealthArchiveSavedTo =>
      'Wealth Archive saved to Google Drive & emailed!';

  @override
  String get rwf1 => 'Rwf';

  @override
  String get seasonsAndActivities => 'Seasons & Activities';

  @override
  String get activeSeasons => 'Active Seasons';

  @override
  String get pastSeasons => 'Past Seasons';

  @override
  String get seasonEarnTokensSubtitle =>
      'Earn tokens by completing activities during each season';

  @override
  String get seasonStatusLive => 'Live';

  @override
  String get seasonStatusEnded => 'Ended';

  @override
  String get seasonStatusUpcoming => 'Upcoming';

  @override
  String get seasonsEmptyTitle => 'No seasons or activities yet';

  @override
  String get earnTokensLabel => 'Earn Tokens';

  @override
  String get creditReadinessTitle => 'Credit readiness';

  @override
  String get groupDetailTitle => 'Group Detail';

  @override
  String get groupNotFound => 'Group not found.';

  @override
  String get couldNotJoinGroup => 'Could not join group.';

  @override
  String get noInviteCodeYet =>
      'This group does not have a shareable invite code yet.';

  @override
  String get noContributionsYet => 'No contributions yet';

  @override
  String get showAll => 'Show all';

  @override
  String get showLess => 'Show less';

  @override
  String membersCount(int count) {
    return 'Members ($count)';
  }

  @override
  String targetAmountRwf(String amount) {
    return 'Target: RWF $amount';
  }

  @override
  String joinGroupShareText(String groupName, String url) {
    return 'Join $groupName on Cool: $url';
  }

  @override
  String joinGroupShareTextEmoji(String groupName, String url) {
    return 'Join $groupName on Cool! 🎉\n$url';
  }

  @override
  String alreadyMemberOf(String groupName) {
    return 'You are already a member of $groupName.';
  }

  @override
  String youJoinedGroup(String groupName) {
    return 'You joined $groupName.';
  }

  @override
  String get ledgerTitle => 'Ledger & Statements';

  @override
  String get allContributors => 'All contributors';

  @override
  String get allTime => 'All time';

  @override
  String get chooseExportFormat =>
      'Choose a format to download the group ledger.';

  @override
  String get exportLedger => 'Export Ledger';

  @override
  String get exportAction => 'Export';

  @override
  String get exportFailed => 'Export failed. Please try again.';

  @override
  String ledgerExported(String fileName) {
    return 'Ledger exported: $fileName';
  }

  @override
  String get noDataToExport => 'No data to export.';

  @override
  String get csvLabel => 'CSV';

  @override
  String get excelLabel => 'Excel';

  @override
  String get pdfLabel => 'PDF';

  @override
  String get plainTextData => 'Plain text data';

  @override
  String get printReadyStatement => 'Print-ready statement';

  @override
  String get spreadsheetWithHeaders => 'Spreadsheet with headers';

  @override
  String get newestFirst => 'Newest first';

  @override
  String get noContributionsForFilter =>
      'No contributions found for this filter.';

  @override
  String get filteredContributor => 'Filtered contributor';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get lastMonth => 'Last month';

  @override
  String get lastYear => 'Last year';

  @override
  String get week => 'Week';

  @override
  String get month => 'Month';

  @override
  String get year => 'Year';

  @override
  String get group => 'Group';

  @override
  String get unknown => 'Unknown';

  @override
  String get kycFrontIdFirst => 'Add front ID first';

  @override
  String kycAlignBack(String docType) {
    return 'Align back of $docType';
  }

  @override
  String kycAlignFront(String docType) {
    return 'Align front of $docType';
  }

  @override
  String get kycBackOfDocument => 'Back of document';

  @override
  String get kycBackOfId => 'Back of ID';

  @override
  String get kycChooseDocumentType => 'Choose document type';

  @override
  String get kycFrontOfId => 'Front of ID';

  @override
  String get kycAutoFilled => 'Cool has already filled';

  @override
  String get kycExtracting => 'Cool is extracting your';

  @override
  String get kycCurrentIdentity => 'Current identity on file';

  @override
  String get kycDrivingLicence => 'Driving licence';

  @override
  String get kycExtractedReady => 'Extracted profile ready';

  @override
  String get kycExtractionFailed => 'Extraction failed';

  @override
  String get kycNationalId => 'National ID';

  @override
  String get kycPassport => 'Passport';

  @override
  String get kycNoImageYet => 'No image yet';

  @override
  String get kycReadingId => 'Reading your ID';

  @override
  String get kycSelfieForFaceMatch => 'Take a selfie for face match';

  @override
  String get kycIdentityMismatch => 'Identity mismatch detected.';

  @override
  String kycDobValue(String dob) {
    return 'DOB $dob';
  }

  @override
  String kycIdMasked(String last4) {
    return 'ID ••••$last4';
  }

  @override
  String get adminPanelTitle => 'Admin Panel';

  @override
  String get adminQuickActions => 'Quick Actions';

  @override
  String get adminOperations => 'Operations';

  @override
  String get adminAppConfig => 'App Config';

  @override
  String get adminAppConfigDesc => 'Key-value settings';

  @override
  String get adminAuditLog => 'Audit Log';

  @override
  String get adminAuditLogDesc => 'Who did what, when';

  @override
  String get adminMissions => 'Missions';

  @override
  String get adminMissionsDesc => 'Create & manage cooperative missions';

  @override
  String get adminAdminRoles => 'Admin Roles';

  @override
  String get adminAdminRolesDesc => 'Assign & manage admin access';

  @override
  String get adminPartners => 'Partners';

  @override
  String get adminPartnersDesc => 'Manage partner profiles';

  @override
  String get adminVehicleTypes => 'Vehicle Types';

  @override
  String get adminVehicleTypesDesc => 'Mobility filter chips';

  @override
  String get adminSeasons => 'Seasons';

  @override
  String get adminSeasonsDesc => 'Token-earning gamification activities';

  @override
  String get adminActivities => 'Activities';

  @override
  String get adminServices => 'Services';

  @override
  String get adminServicesDesc => 'Partner service offerings';

  @override
  String get adminSpecialProducts => 'Special Products';

  @override
  String get adminSpecialProductsDesc => 'Home screen cards';

  @override
  String get adminAiContent => 'AI Content';

  @override
  String get adminAiContentDesc => 'AI-generated UI with approval gate';

  @override
  String get adminSystemAnalytics => 'System Analytics';

  @override
  String get adminSystemAnalyticsDesc => 'Platform-wide metrics & trends';

  @override
  String get adminUsers => 'Users';

  @override
  String get adminUsersDesc => 'Inspect profiles and demo batches';

  @override
  String get adminLiveOps => 'Live-Ops';

  @override
  String get adminLiveOpsDesc => 'Live-ops campaigns & rewards';

  @override
  String get adminRelease => 'Release';

  @override
  String get adminReleaseDesc => 'Release health and triage';

  @override
  String get adminSupportMode => 'Support Mode';

  @override
  String get adminSupportModeDesc =>
      'Open a bank or rayon workspace as support';

  @override
  String get adminSupportModeHint =>
      'Navigate into a partner workspace to view and manage it as support.';

  @override
  String get adminNoPartnersFound => 'No partners found';

  @override
  String adminFailedToLoadPartners(String error) {
    return 'Failed to load partners: $error';
  }

  @override
  String get rsAdminUpdateStatus => 'Update Status';

  @override
  String rsAdminOrderNumber(String orderId) {
    return 'Order #$orderId';
  }

  @override
  String rsAdminItemsCount(int count) {
    return 'Items ($count)';
  }

  @override
  String get partnerNotFound => 'Partner not found';

  @override
  String get prismaLabel => 'PRISMA';

  @override
  String get couldNotLoadServices => 'Could not load services';

  @override
  String get partnerLabel => 'Partner';

  @override
  String get spreadsheetHeaders => 'Spreadsheet with headers';

  @override
  String get contributorsLabel => 'Contributors';

  @override
  String get kycIdentityVerification => 'Identity verification';

  @override
  String get rsAdminNoOrders => 'No orders yet';
}
