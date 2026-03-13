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
  String get welcomeSubtitle =>
      'Community savings, group funds & mobility — all in one simple app for Rwanda.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get signIn => 'Already have an account? Sign In';

  @override
  String get verifyWhatsapp => 'Verify via WhatsApp';

  @override
  String get verifyWhatsappSubtitle =>
      'We\'ll send a one-time code to your WhatsApp number.';

  @override
  String get phoneLabel => 'Phone Number';

  @override
  String get phoneHint => '+250 7XX XXX XXX';

  @override
  String get sendCode => 'Send WhatsApp Code';

  @override
  String get enterCode => 'Enter Code';

  @override
  String get enterCodeSubtitle =>
      'Enter the 6-digit code sent to your WhatsApp.';

  @override
  String get verifyButton => 'Verify & Continue';

  @override
  String get resendCode => 'Resend Code';

  @override
  String resendCodeIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get invalidCode => 'Invalid code. Please try again.';

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
  String get momoNumberHint => 'e.g. 0788 123 456';

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
  String get noActivity => 'No recent activity to show.';

  @override
  String get viewAll => 'View All';

  @override
  String get sendMoneyTitle => 'Send Money';

  @override
  String get sendMoneyHint => 'Transfer instantly to a member ID';

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
  String get noGroupsYet => 'You haven\'t joined any groups yet.';

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
  String get momoDialerError =>
      'Unable to open the USSD dialer. Please try again.';

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
  String get noTripsAvailable => 'No trips available right now.';

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
  String get scheduleTripInfoBanner =>
      'Schedule ahead to find the best matches — drivers can offer return trips at lower prices!';

  @override
  String get scheduleTripDetailsTitle => 'Trip Details';

  @override
  String get scheduleTripFromHint => '📍 From — e.g. Nyamirambo';

  @override
  String get scheduleTripToHint => '🎯 To — e.g. Kigali Downtown';

  @override
  String get scheduleTripDateTimeLabel => 'Date & Time';

  @override
  String get scheduleTripVehicleLabel => 'Vehicle Preference';

  @override
  String get scheduleTripSeatsLabel => 'Seats Needed';

  @override
  String get scheduleTripReturnTitle => 'Return Trip';

  @override
  String get scheduleTripReturnSubtitle =>
      'Drivers offer discounts on return trips';

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
  String get scheduleTripExpirySubtitle =>
      'Trips are removed 60 min after departure time if unfilled.';

  @override
  String get scheduleTripPostCta => 'Post Trip on Board';

  @override
  String get scheduleTripPostedSuccess => 'Trip posted successfully.';

  @override
  String get scheduleTripPostedPendingSync =>
      'Trip saved offline and will sync when a connection is available.';

  @override
  String get scheduleTripFromRequired => 'Enter a departure point.';

  @override
  String get scheduleTripToRequired => 'Enter a destination.';

  @override
  String get scheduleTripRouteSameError =>
      'Departure and destination must be different.';

  @override
  String get scheduleTripReturnInvalidError =>
      'Return date and time must be after departure.';

  @override
  String get scheduleTripRecurringDaysError => 'Pick at least one repeat day.';

  @override
  String get scheduleTripDateFieldPrefix => '📅';

  @override
  String get scheduleTripTimeFieldPrefix => '🕐';

  @override
  String get driverMode => 'Driver Mode';

  @override
  String get driverOnlineMessage =>
      'You are online and visible to nearby passengers.';

  @override
  String get driverOfflineMessage =>
      'You are offline. Turn on driver mode to receive trips.';

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
    return 'You have used $used trips so far and only $remaining free trips remain.';
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
  String get vehicleMoto => '🛺 Moto';

  @override
  String get vehicleCab => '🚗 Cab';

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
  String get whatsappConfirmation =>
      '📱 WhatsApp confirmation will be sent after payment';

  @override
  String get viewTicket => 'View';

  @override
  String get showAtGate => 'Show this at the gate';

  @override
  String get addToCart => 'Add to Cart';

  @override
  String get goldDiscount => '🌟 Gold Members get 10% off';

  @override
  String get noTicketsYet => 'No tickets yet';

  @override
  String get buyTicketsToUpcomingMatches => 'Buy tickets to upcoming matches';

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
  String get improveOnTime => 'Contribute on time every month';

  @override
  String get improveJoinGroups => 'Join 2+ savings groups';

  @override
  String get improveCommunityFunds => 'Contribute to 3 community funds';

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
  String get signOutConfirmMessage =>
      'Are you sure you want to sign out? You will need to verify your WhatsApp OTP again to log back in.';

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
  String get offlineNotice => 'You\'re offline. Showing cached data.';

  @override
  String goodMorningUser(String name) {
    return 'Good morning, $name 👋';
  }

  @override
  String get memberIdPrefix => 'ID: ';

  @override
  String get recent => 'Recent';

  @override
  String get seeAll => 'See all';

  @override
  String inviteToGroup(String groupName) {
    return 'Invite to $groupName';
  }

  @override
  String get scanQrOrShareLink => 'Scan QR or share the link';

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
  String get noResults => 'No results found.';

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
  String get otpUseWhatsappSubtitle =>
      'We will send a 6-digit code to your WhatsApp.';

  @override
  String get otpPhoneRequired => 'Enter your phone number';

  @override
  String get otpContinue => 'Continue';

  @override
  String get otpGenericError => 'Something went wrong. Please try again.';

  @override
  String get openLinkError => 'Could not open link';

  @override
  String get otpLegalPrefix => 'By continuing, you accept the ';

  @override
  String get otpLegalAnd => ' and ';

  @override
  String get termsLabel => 'Terms';

  @override
  String get privacyPolicyLabel => 'Privacy Policy';

  @override
  String get homeMissionsTitle => 'Missions';

  @override
  String get homeMonthlyNet => 'Monthly net';

  @override
  String get homeActionPay => 'Pay';

  @override
  String get homeActionTrips => 'Trips';

  @override
  String get homeFallbackGroupsSubtitle => 'Savings and invites';

  @override
  String get homeFallbackPaySubtitle => 'MoMo and statements';

  @override
  String get homeFallbackPartnersSubtitle => 'Banks and clubs';

  @override
  String get homeFallbackTripsSubtitle => 'Ride or drive';

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
  String get homeLoadErrorMessage => 'Pull to refresh or try again.';

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
  String get profileMoreToolsShowSubtitle =>
      'Show extra actions and secondary shortcuts.';

  @override
  String get profileMoreToolsHideSubtitle =>
      'Hide QR, driver, status, and admin shortcuts.';

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
  String get deleteAccountMessage =>
      'This permanently removes your account and data.';

  @override
  String get signOutMessage =>
      'You\'ll need to verify your number again to log back in.';

  @override
  String get completeProfileTitle => 'Complete your profile';

  @override
  String get completeProfileSubtitle => 'Finish setup to unlock all features.';

  @override
  String get profileSavingMomoInfo => 'Saving MoMo info...';

  @override
  String get profileDeletingAccount => 'Deleting your account...';

  @override
  String get profileMomoUpdated => 'MoMo info updated';

  @override
  String get profileMomoUpdateFailed => 'Failed to update MoMo info';

  @override
  String get profileSupportOpenError =>
      'Could not open WhatsApp. Please try again.';

  @override
  String get profileSupportUnavailable => 'Support is unavailable right now.';

  @override
  String get profileMomoQrTitle => 'MoMo QR';

  @override
  String profileMomoQrSubtitle(String number) {
    return 'Scan to pay $number';
  }

  @override
  String get profileEditMomoInfo => 'Edit MoMo Info';

  @override
  String get profileEditMomoSubtitle =>
      'This number will be used for Mobile Money payments';

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
  String get walletEmptyMessage => 'Wallet activity will appear here.';

  @override
  String get walletLedgerTitle => 'Wallet ledger';

  @override
  String walletLedgerSubtitle(int shown, int total) {
    return 'Showing $shown of $total wallet entries.';
  }

  @override
  String get savingsEmptyTitle => 'No savings entries yet';

  @override
  String get savingsEmptyMessage => 'Savings contributions will appear here.';

  @override
  String get savingsStatementTitle => 'Savings statement';

  @override
  String savingsStatementSubtitle(int shown, int total) {
    return 'Showing $shown of $total group contribution records.';
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
      'Try adjusting your filters or date range.';

  @override
  String get momoStatementsSavingsFilteredEmptyTitle =>
      'No matching savings entries';

  @override
  String get momoStatementsSavingsFilteredEmptyMessage =>
      'Try adjusting your filters or date range.';

  @override
  String get fansScreenUnavailableTitle => 'Fan Hub Moved';

  @override
  String get fansScreenHeadline => 'Fan Hub';

  @override
  String fansScreenBody(String clubName) {
    return 'Fan features for $clubName are now consolidated in the partner hub.';
  }

  @override
  String get fansScreenMembershipUnavailable =>
      'Membership features live inside Rayon Sports.';

  @override
  String get fansScreenClubsUnavailable =>
      'Fan clubs are now managed inside Rayon Sports.';

  @override
  String get fansScreenRayonDedicatedHub =>
      'Rayon Sports has a dedicated fan hub.';

  @override
  String get fansScreenRouteKeptReachable =>
      'This route is kept reachable for deep links.';

  @override
  String get fansScreenBackToPartners => 'Back to Partners';

  @override
  String get fansScreenOpenRayon => 'Open Rayon Sports';

  @override
  String get ticketWalletInvalidLink => 'Invalid Google Wallet link.';

  @override
  String get ticketWalletUnavailable =>
      'Google Wallet is not available on this device.';

  @override
  String get ticketWalletOpenFailed => 'Could not open Google Wallet.';

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
    return 'Check out $matchTitle on Cool!';
  }

  @override
  String get ticketStatusPendingTitle => 'Payment Pending';

  @override
  String get ticketStatusPendingSubtitle => 'Waiting for MoMo confirmation.';

  @override
  String get ticketStatusPendingNote =>
      'Your ticket is reserved. Complete the MoMo payment to activate it.';

  @override
  String get ticketStatusValidTitle => 'Valid Ticket';

  @override
  String get ticketStatusValidSubtitle => 'Show this at the gate.';

  @override
  String get ticketStatusValidNote =>
      'Present the QR code below at the stadium entrance.';

  @override
  String get ticketStatusUsedTitle => 'Ticket Used';

  @override
  String get ticketStatusUsedSubtitle => 'This ticket has been scanned.';

  @override
  String get ticketStatusUsedNote =>
      'This ticket was validated at the gate. It cannot be used again.';

  @override
  String get ticketStatusCancelledTitle => 'Ticket Cancelled';

  @override
  String get ticketStatusCancelledSubtitle => 'This ticket is no longer valid.';

  @override
  String get ticketStatusCancelledNote =>
      'Contact support if you believe this is an error.';

  @override
  String get partnersHomeTooltip => 'Partners Home';

  @override
  String get partnersServicesTab => 'Services';

  @override
  String get partnersRayonWelcomeTitle => 'Welcome to Rayon Sports!';

  @override
  String get partnersRayonWelcomeSubtitle =>
      'Your fan membership has been created. Enjoy exclusive perks, tickets, and club updates.';

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
  String get partnersNoFootballPartners =>
      'No football partners available yet.';

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
  String get partnersNoFinancePartners => 'No finance partners available yet.';

  @override
  String get partnersFinancePrepTitle => 'Financial Readiness';

  @override
  String get partnersFinancePrepSubtitle =>
      'Check your credit readiness and prepare for financial services from our partners.';

  @override
  String get partnersReadinessChecklistCta => 'Credit Readiness Checklist';

  @override
  String partnersWhatsappMessage(String partnerName) {
    return 'Hi, I\'d like to learn more about $partnerName on Cool.';
  }

  @override
  String get partnersNoServicePartners => 'No service partners available yet.';

  @override
  String get partnersInsurancePartnerBadge => 'Insurance Partner';

  @override
  String get partnersProfessionalServicesBadge => 'Professional Services';

  @override
  String get partnersServicePartnerBadge => 'Service Partner';

  @override
  String get partnersLoadErrorTitle => 'Could not load partners';

  @override
  String get partnersEmptyMessage =>
      'Partners will appear here once available.';

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
  String get momoNfcLaunchFailed => 'NFC launch failed. Please try again.';

  @override
  String get momoScreenTitle => 'Mobile Money';

  @override
  String get momoNfcLaunchingOverlay => 'Launching MoMo…';

  @override
  String get momoSendValidationError =>
      'Please enter a valid recipient and amount.';

  @override
  String momoSendLaunchFailed(String countryName) {
    return 'Could not launch MoMo payment for $countryName.';
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
    return 'Completes via USSD on your $countryName SIM.';
  }

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
    return 'Join $groupName on Cool: $inviteUrl';
  }

  @override
  String get groupsCreateNewTitle => 'Create a New Group';

  @override
  String get groupsCreateNewSubtitle => 'Saving or Community';

  @override
  String get groupsEmptyPublicTitle => 'No public groups found';

  @override
  String get groupsEmptyPublicMessage =>
      'Pull to refresh or check your groups.';

  @override
  String get groupsEmptyPrivateMessage =>
      'Create a group or browse public ones.';

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
  String get profileIdentityUpdateFailed => 'Failed to update identity details';

  @override
  String get profileAppAccess => 'App access';

  @override
  String get profileManageAction => 'Manage';

  @override
  String profileCoolStatusValue(String tier, int points) {
    return '$tier · $points pts';
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
  String get mobilityNoWhatsappAvailable =>
      'No WhatsApp contact available yet.';

  @override
  String get mobilityNoContactYet => 'No contact yet';

  @override
  String get mobilityLocationRequiredDriverMode =>
      'Location is required before turning on driver mode.';

  @override
  String momoSendMoneyOpensUssd(String countryName) {
    return 'Open $countryName MoMo USSD to send money.';
  }

  @override
  String get momoMoreToolsSubtitle =>
      'Statements, QR, and NFC tools for your route.';

  @override
  String get momoStatementsToolSubtitle => 'Review wallet and savings history.';

  @override
  String get momoNfcToolsTitle => 'NFC tools';

  @override
  String get momoNfcToolsSubtitle => 'Tap-to-pay and share route details.';

  @override
  String get basketScreenTitle => 'Basket';

  @override
  String get basketScreenHeadline => 'Basket is not live right now';

  @override
  String get basketScreenBody =>
      'This route stays available for compatibility, but basket balances and creation flows are not active in this build.';

  @override
  String get basketScreenCardBody =>
      'Basket products are paused while the team finishes the next release.';

  @override
  String get basketScreenExpectationBalances =>
      'No live basket balances are shown here.';

  @override
  String get basketScreenExpectationCreation =>
      'New basket creation is currently disabled.';

  @override
  String get basketScreenExpectationLinks =>
      'Existing deep links still land on this placeholder.';

  @override
  String get basketScreenBackHome => 'Back Home';
}
