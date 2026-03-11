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
      'Community savings, group funds & mobility — all in one simple app for Sub-Saharan Africa.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get signIn => 'Already have an account? Sign In';

  @override
  String get selectLanguage => 'Select Language';

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
  String get languageFrench => 'Français';

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
}
