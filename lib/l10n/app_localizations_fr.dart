// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appName => 'Cool';

  @override
  String get navHome => 'Accueil';

  @override
  String get navGroups => 'Groupes';

  @override
  String get navMobility => 'Mobilité';

  @override
  String get navProfile => 'Profil';

  @override
  String get welcomeTitle => 'Bienvenue sur Cool';

  @override
  String get welcomeSubtitle =>
      'Épargne communautaire, cagnottes et mobilité — tout en une seule application simple pour l\'Afrique subsaharienne.';

  @override
  String get getStarted => 'Commencer';

  @override
  String get signIn => 'Déjà un compte ? Se connecter';

  @override
  String get selectLanguage => 'Choisir la langue';

  @override
  String get verifyWhatsapp => 'Vérifier via WhatsApp';

  @override
  String get verifyWhatsappSubtitle =>
      'Nous enverrons un code unique à votre numéro WhatsApp.';

  @override
  String get phoneLabel => 'Numéro de téléphone';

  @override
  String get phoneHint => '+250 7XX XXX XXX';

  @override
  String get sendCode => 'Envoyer le code WhatsApp';

  @override
  String get enterCode => 'Entrer le code';

  @override
  String get enterCodeSubtitle =>
      'Entrez le code à 6 chiffres envoyé sur votre WhatsApp.';

  @override
  String get verifyButton => 'Vérifier et continuer';

  @override
  String get resendCode => 'Renvoyer le code';

  @override
  String resendCodeIn(int seconds) {
    return 'Renvoyer dans ${seconds}s';
  }

  @override
  String get invalidCode => 'Code invalide. Veuillez réessayer.';

  @override
  String get codeSent => 'Code envoyé sur WhatsApp.';

  @override
  String get setupProfile => 'Configurer le profil';

  @override
  String get createAccount => 'Créer un compte';

  @override
  String get nameLabel => 'Nom complet';

  @override
  String get nameHint => 'ex. Amara Banda';

  @override
  String get countryLabel => 'Pays';

  @override
  String get momoNumberLabel => 'Numéro MOMO';

  @override
  String get momoNumberHint => 'ex. 0788 123 456';

  @override
  String get totalBalance => 'Solde total';

  @override
  String get rwf => 'RWF';

  @override
  String get quickActions => 'Actions rapides';

  @override
  String get sendMoney => 'Envoyer';

  @override
  String get requestPay => 'Demander';

  @override
  String get payViaMomo => 'Payer via MOMO';

  @override
  String get recentActivity => 'Activité récente';

  @override
  String get noActivity => 'Aucune activité récente.';

  @override
  String get viewAll => 'Tout voir';

  @override
  String get sendMoneyTitle => 'Envoyer de l\'argent';

  @override
  String get sendMoneyHint => 'Transfert instantané vers un identifiant membre';

  @override
  String get sendAction => 'Envoyer';

  @override
  String get recipientLabel => 'ID du destinataire';

  @override
  String get recipientHint => 'Entrez l\'identifiant membre';

  @override
  String get amountLabel => 'Montant (RWF)';

  @override
  String get amountHint => 'ex. 5 000';

  @override
  String get confirmSend => 'Confirmer et envoyer';

  @override
  String get sendSuccess => 'Transfert initié via MOMO.';

  @override
  String get myGroups => 'Mes groupes';

  @override
  String get newGroup => 'Nouveau groupe';

  @override
  String get createGroup => 'Créer un groupe';

  @override
  String get joinGroup => 'Rejoindre';

  @override
  String get leaveGroup => 'Quitter';

  @override
  String get groupSaving => 'Épargne de groupe';

  @override
  String get communityFund => 'Cagnotte communautaire';

  @override
  String get public => 'Public';

  @override
  String get private => 'Privé';

  @override
  String get publicGroup => 'Public';

  @override
  String get privateGroup => 'Privé';

  @override
  String get contribute => 'Contribuer';

  @override
  String get contribution => 'Contribution';

  @override
  String get contributionAmount => 'Montant de contribution';

  @override
  String get cycleDays => 'Cycle (jours)';

  @override
  String memberCount(int count) {
    return '$count membres';
  }

  @override
  String get groupMembers => 'Membres';

  @override
  String get recentContributions => 'Contributions récentes';

  @override
  String get shareInvite => 'Partager / QR';

  @override
  String get groupCreated => 'Groupe créé avec succès.';

  @override
  String get groupNameLabel => 'Nom du groupe';

  @override
  String get groupNameHint => 'ex. Épargnants de Nyamirambo';

  @override
  String get groupDescriptionLabel => 'Description';

  @override
  String get discoverGroups => 'Découvrir des groupes';

  @override
  String get noGroupsYet => 'Vous n\'avez rejoint aucun groupe.';

  @override
  String get noPublicGroups => 'Aucun groupe public disponible.';

  @override
  String get pending => 'En attente';

  @override
  String get confirmed => 'Confirmé';

  @override
  String get failed => 'Échoué';

  @override
  String get basket => 'Panier';

  @override
  String get emptyBasket => 'Votre panier est vide.';

  @override
  String get checkout => 'Commander';

  @override
  String totalItems(int count) {
    return '$count articles';
  }

  @override
  String get momoTitle => 'MOMO Pay';

  @override
  String get payViaUssd => 'Payer via MOMO USSD';

  @override
  String get momoDialerError =>
      'Impossible d\'ouvrir le USSD. Veuillez réessayer.';

  @override
  String get mobilityTitle => 'Mobilité';

  @override
  String get nearbyDrivers => 'Chauffeurs à proximité';

  @override
  String get scheduledTrips => 'Trajets programmés';

  @override
  String get scheduleTrip => 'Planifier un trajet';

  @override
  String get postTrip => 'Publier le trajet';

  @override
  String get tripBoard => 'Tableau des trajets';

  @override
  String get driverProfile => 'Profil chauffeur';

  @override
  String get allTrips => 'Tous';

  @override
  String get oneWay => 'Aller simple';

  @override
  String get returnTrips => 'Retour';

  @override
  String get noTripsAvailable => 'Aucun trajet disponible pour le moment.';

  @override
  String get noDriversNearby => 'Aucun chauffeur à proximité.';

  @override
  String get contactViaWhatsapp => 'Contacter via WhatsApp';

  @override
  String get tripDetails => 'Détails du trajet';

  @override
  String expiresIn(int minutes) {
    return 'Expire dans $minutes min';
  }

  @override
  String seatsLabel(int count) {
    return '$count place';
  }

  @override
  String seatsLabelPlural(int count) {
    return '$count places';
  }

  @override
  String get scheduleTripTitle => 'Planifier un trajet';

  @override
  String get scheduleTripInfoBanner =>
      'Planifiez à l\'avance pour trouver les meilleurs matchs — les chauffeurs peuvent proposer des retours à prix réduit !';

  @override
  String get scheduleTripDetailsTitle => 'Détails du trajet';

  @override
  String get scheduleTripFromHint => '📍 Départ — ex. Nyamirambo';

  @override
  String get scheduleTripToHint => '🎯 Arrivée — ex. Centre-ville de Kigali';

  @override
  String get scheduleTripDateTimeLabel => 'Date et heure';

  @override
  String get scheduleTripVehicleLabel => 'Préférence véhicule';

  @override
  String get scheduleTripSeatsLabel => 'Places demandées';

  @override
  String get scheduleTripReturnTitle => 'Trajet retour';

  @override
  String get scheduleTripReturnSubtitle =>
      'Les chauffeurs offrent souvent une réduction pour le retour';

  @override
  String get scheduleTripReturnFieldsLabel => 'Date et heure du retour';

  @override
  String get scheduleTripRecurringTitle => 'Trajet récurrent';

  @override
  String get scheduleTripRecurringSubtitle =>
      'Répétition quotidienne / hebdomadaire';

  @override
  String get scheduleTripRecurringDaysLabel => 'Jours de répétition';

  @override
  String get scheduleTripExpiryTitle => 'Le trajet expire automatiquement';

  @override
  String get scheduleTripExpirySubtitle =>
      'Les trajets sont retirés 60 min après l\'heure de départ s\'ils ne sont pas complets.';

  @override
  String get scheduleTripPostCta => 'Publier le trajet';

  @override
  String get scheduleTripPostedSuccess => 'Trajet publié avec succès.';

  @override
  String get scheduleTripPostedPendingSync =>
      'Trajet enregistré hors ligne et synchronisé dès qu\'une connexion revient.';

  @override
  String get scheduleTripFromRequired => 'Entrez un point de départ.';

  @override
  String get scheduleTripToRequired => 'Entrez une destination.';

  @override
  String get scheduleTripRouteSameError =>
      'Le départ et la destination doivent être différents.';

  @override
  String get scheduleTripReturnInvalidError =>
      'La date et l\'heure du retour doivent être après le départ.';

  @override
  String get scheduleTripRecurringDaysError =>
      'Choisissez au moins un jour de répétition.';

  @override
  String get scheduleTripDateFieldPrefix => '📅';

  @override
  String get scheduleTripTimeFieldPrefix => '🕐';

  @override
  String get driverMode => 'Mode chauffeur';

  @override
  String get driverOnlineMessage =>
      'Vous êtes en ligne et visible par les passagers à proximité.';

  @override
  String get driverOfflineMessage =>
      'Vous êtes hors ligne. Activez le mode chauffeur pour recevoir des trajets.';

  @override
  String get online => 'En ligne';

  @override
  String get offline => 'Hors ligne';

  @override
  String get tripsDone => 'Trajets effectués';

  @override
  String get freeTrips => 'Trajets gratuits';

  @override
  String get statusHealthy => 'Bon état';

  @override
  String get statusWarning => 'Attention';

  @override
  String get myVehicle => 'Mon véhicule';

  @override
  String get editVehicle => 'Modifier le véhicule';

  @override
  String get saveVehicleInfo => 'Enregistrer les infos véhicule';

  @override
  String get vehicleTypeLabel => 'Type de véhicule';

  @override
  String get plateNumberLabel => 'Numéro de plaque';

  @override
  String get baseLocationLabel => 'Point de départ habituel';

  @override
  String get statusLabel => 'Statut';

  @override
  String get verified => 'Vérifié';

  @override
  String get pendingReview => 'En cours de vérification';

  @override
  String get maintenance => 'En maintenance';

  @override
  String get subscribe => 'Payer via MOMO USSD';

  @override
  String get unlockUnlimitedTrips => 'Débloquer les trajets illimités';

  @override
  String tripsUsedMessage(int used, int remaining) {
    return 'Vous avez utilisé $used trajets et il ne reste que $remaining trajets gratuits.';
  }

  @override
  String daysRemaining(int count) {
    return '$count jours restants';
  }

  @override
  String get addReturnTrip => 'Ajouter un trajet retour';

  @override
  String get myScheduledTrips => 'Mes trajets programmés';

  @override
  String get noScheduledTrips => 'Aucun trajet programmé.';

  @override
  String get perMonth => '/mois';

  @override
  String get vehicleMoto => '🛺 Moto';

  @override
  String get vehicleCab => '🚗 Taxi';

  @override
  String get vehicleAny => 'Peu importe';

  @override
  String get weekdayMonShort => 'Lun';

  @override
  String get weekdayTueShort => 'Mar';

  @override
  String get weekdayWedShort => 'Mer';

  @override
  String get weekdayThuShort => 'Jeu';

  @override
  String get weekdayFriShort => 'Ven';

  @override
  String get weekdaySatShort => 'Sam';

  @override
  String get weekdaySunShort => 'Dim';

  @override
  String get partnersTitle => 'Partenaires';

  @override
  String get partners => 'Partenaires';

  @override
  String get football => 'Football';

  @override
  String get banks => 'Banques';

  @override
  String get organizations => 'Organisations';

  @override
  String get ticketsAndShop => 'Billets et boutique';

  @override
  String get upcomingMatches => 'Matchs à venir';

  @override
  String get fanRegistry => 'Registre des fans';

  @override
  String get fanClubs => 'Clubs de fans';

  @override
  String get ticketing => 'Billetterie';

  @override
  String get clubShop => 'Boutique du club';

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
    return '$count matchs';
  }

  @override
  String get fansTitle => 'Fans';

  @override
  String get membership => 'Adhésion';

  @override
  String get achievements => 'Réalisations';

  @override
  String get fanDirectory => 'Répertoire des fans';

  @override
  String get joinClub => 'Rejoindre';

  @override
  String get joinedClub => 'Membre';

  @override
  String get leaveClub => 'Quitter';

  @override
  String get goldMember => 'MEMBRE OR';

  @override
  String get silverMember => 'MEMBRE ARGENT';

  @override
  String get bronzeMember => 'MEMBRE BRONZE';

  @override
  String get earnedBadge => 'Obtenu';

  @override
  String get lockedBadge => 'Verrouillé';

  @override
  String get ticketingTitle => 'Billetterie';

  @override
  String get tickets => 'Billets';

  @override
  String get myTickets => 'Mes billets';

  @override
  String get purchasedTickets => 'Billets achetés';

  @override
  String get buyTicket => 'Acheter';

  @override
  String get purchaseTicket => 'Acheter un billet';

  @override
  String get quantity => 'Quantité';

  @override
  String get seatCategory => 'Catégorie de place';

  @override
  String get general => 'Général';

  @override
  String get vip => 'VIP';

  @override
  String get generalSeat => 'Tribune';

  @override
  String get vipSeat => 'VIP';

  @override
  String get total => 'Total';

  @override
  String get payViaMomoUssd => 'Payer via MOMO';

  @override
  String get whatsappConfirmation =>
      '📱 Une confirmation WhatsApp sera envoyée après le paiement';

  @override
  String get viewTicket => 'Voir';

  @override
  String get showAtGate => 'Montrez ceci à l\'entrée';

  @override
  String get addToCart => 'Ajouter au panier';

  @override
  String get goldDiscount => '🌟 Les membres Or bénéficient de –10 %';

  @override
  String get noTicketsYet => 'Pas encore de billets';

  @override
  String get buyTicketsToUpcomingMatches =>
      'Achetez des billets pour les prochains matchs';

  @override
  String cartItemCount(int count) {
    return '$count articles';
  }

  @override
  String get creditScore => 'Score de crédit';

  @override
  String get coolCreditScore => 'SCORE DE CRÉDIT COOL';

  @override
  String get excellentGrade => 'Excellent';

  @override
  String get goodStanding => 'Bonne position';

  @override
  String get fairGrade => 'Moyen';

  @override
  String get needsImprovement => 'À améliorer';

  @override
  String get scoreFactors => 'Facteurs du score';

  @override
  String get savingConsistency => 'Régularité d\'épargne';

  @override
  String get groupParticipation => 'Participation aux groupes';

  @override
  String get paymentHistory => 'Historique des paiements';

  @override
  String get communityActivity => 'Activité communautaire';

  @override
  String get howToImprove => '💡 Comment améliorer';

  @override
  String get improveOnTime => 'Contribuer à temps chaque mois';

  @override
  String get improveJoinGroups => 'Rejoindre 2+ groupes d\'épargne';

  @override
  String get improveCommunityFunds => 'Contribuer à 3 cagnottes communautaires';

  @override
  String get improveConsecutiveMonths => '6 mois consécutifs d\'épargne';

  @override
  String get scoreHistory => 'Historique du score';

  @override
  String get profile => 'Profil';

  @override
  String get account => 'Compte';

  @override
  String get phone => 'Téléphone';

  @override
  String get momoNumber => 'Numéro MOMO';

  @override
  String get momoLinked => 'Lié ✅';

  @override
  String get momoNotLinked => 'Non lié';

  @override
  String get language => 'Langue';

  @override
  String get notifications => 'Notifications';

  @override
  String get security => 'Sécurité';

  @override
  String get pinBiometric => 'PIN / Biométrique';

  @override
  String get enabled => 'Activé';

  @override
  String get whatsappOtp => 'OTP WhatsApp';

  @override
  String get active => 'Actif';

  @override
  String get more => 'Plus';

  @override
  String get helpAndSupport => 'Aide et support';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutConfirmTitle => 'Se déconnecter';

  @override
  String get signOutConfirmMessage =>
      'Êtes-vous sûr de vouloir vous déconnecter ? Vous devrez revérifier votre OTP WhatsApp pour vous reconnecter.';

  @override
  String get cancel => 'Annuler';

  @override
  String get vehicle => 'Véhicule';

  @override
  String get subscription => 'Abonnement';

  @override
  String expiringInDays(int count) {
    return 'Expire dans $count jours';
  }

  @override
  String get languageEnglish => 'English';

  @override
  String get languageFrench => 'Français';

  @override
  String get loading => 'Chargement…';

  @override
  String get retry => 'Réessayer';

  @override
  String get error => 'Une erreur est survenue.';

  @override
  String get noConnection => 'Pas de connexion internet.';

  @override
  String get offlineNotice =>
      'Vous êtes hors ligne. Données en cache affichées.';

  @override
  String goodMorningUser(String name) {
    return 'Bonjour, $name 👋';
  }

  @override
  String get memberIdPrefix => 'ID : ';

  @override
  String get recent => 'Récent';

  @override
  String get seeAll => 'Voir tout';

  @override
  String inviteToGroup(String groupName) {
    return 'Invitation à $groupName';
  }

  @override
  String get scanQrOrShareLink => 'Scannez le QR ou partagez le lien';

  @override
  String get shareViaWhatsapp => 'Partager via WhatsApp';

  @override
  String get linkCopied => 'Lien copié !';

  @override
  String get copy => 'Copier';

  @override
  String get whatsapp => 'WhatsApp';

  @override
  String get topUp => 'Recharger';

  @override
  String get savingsRank => 'Classement épargne';

  @override
  String get officialPartner => 'Partenaire officiel';

  @override
  String get bankingPartner => 'Partenaire bancaire';

  @override
  String get activeGroups => 'Groupes actifs';

  @override
  String get rwfHeld => 'RWF détenus';

  @override
  String get members => 'membres';

  @override
  String get moreOrganizationsComingSoon =>
      'Plus d\'organisations arrivent bientôt';

  @override
  String get admin => 'Admin';

  @override
  String get returnLabel => 'Retour';

  @override
  String get daily => 'Quotidien';

  @override
  String get expiresSoon => 'Expire bientôt';

  @override
  String get departed => 'parti';

  @override
  String inMinutesShort(int count) {
    return 'dans $count min';
  }

  @override
  String inHoursShort(int count) {
    return 'dans $count h';
  }

  @override
  String inDaysShort(int count) {
    return 'dans $count j';
  }

  @override
  String get save => 'Enregistrer';

  @override
  String get edit => 'Modifier';

  @override
  String get delete => 'Supprimer';

  @override
  String get confirm => 'Confirmer';

  @override
  String get ok => 'OK';

  @override
  String get close => 'Fermer';

  @override
  String targetAmount(String amount) {
    return 'Objectif : $amount RWF';
  }

  @override
  String get search => 'Rechercher';

  @override
  String get noResults => 'Aucun résultat.';

  @override
  String get seeMore => 'Voir plus';

  @override
  String get copied => 'Copié dans le presse-papiers.';
}
