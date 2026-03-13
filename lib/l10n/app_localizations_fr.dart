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

  @override
  String get retryAction => 'Réessayer';

  @override
  String get cancelAction => 'Annuler';

  @override
  String get openAction => 'Ouvrir';

  @override
  String get languageLabel => 'Langue';

  @override
  String get supportLabel => 'Assistance';

  @override
  String get notificationsLabel => 'Notifications';

  @override
  String get statementsLabel => 'Relevés';

  @override
  String get walletLabel => 'Portefeuille';

  @override
  String get savingsLabel => 'Épargne';

  @override
  String get allTimeLabel => 'Depuis le début';

  @override
  String get last30DaysLabel => '30 derniers jours';

  @override
  String get last90DaysLabel => '90 derniers jours';

  @override
  String get incomingLabel => 'Entrées';

  @override
  String get outgoingLabel => 'Sorties';

  @override
  String get counterpartyLabel => 'Contrepartie';

  @override
  String get referenceLabel => 'Référence';

  @override
  String get detailsLabel => 'Détails';

  @override
  String get otpUseWhatsappTitle => 'Utilisez votre numéro WhatsApp';

  @override
  String get otpUseWhatsappSubtitle =>
      'Nous enverrons un code à 6 chiffres sur votre WhatsApp.';

  @override
  String get otpPhoneRequired => 'Entrez votre numéro de téléphone';

  @override
  String get otpContinue => 'Continuer';

  @override
  String get otpGenericError => 'Une erreur est survenue. Veuillez réessayer.';

  @override
  String get openLinkError => 'Impossible d\'ouvrir le lien';

  @override
  String get otpLegalPrefix => 'En continuant, vous acceptez les ';

  @override
  String get otpLegalAnd => ' et la ';

  @override
  String get termsLabel => 'Conditions';

  @override
  String get privacyPolicyLabel => 'Politique de confidentialité';

  @override
  String get homeMissionsTitle => 'Missions';

  @override
  String get homeMonthlyNet => 'Net mensuel';

  @override
  String get homeActionPay => 'Payer';

  @override
  String get homeActionTrips => 'Trajets';

  @override
  String get homeFallbackGroupsSubtitle => 'Épargne et invitations';

  @override
  String get homeFallbackPaySubtitle => 'MoMo et relevés';

  @override
  String get homeFallbackPartnersSubtitle => 'Banques et clubs';

  @override
  String get homeFallbackTripsSubtitle => 'Trajet ou conduite';

  @override
  String homeActiveCount(int count) {
    return '$count actifs';
  }

  @override
  String get homeNoActivityTitle => 'Aucune activité pour le moment';

  @override
  String get homeNoActivityMessage => 'L\'activité apparaîtra ici.';

  @override
  String get homeLoadErrorTitle => 'Impossible de charger cette section';

  @override
  String get homeLoadErrorMessage => 'Tirez pour actualiser ou réessayez.';

  @override
  String get profileMobileMoney => 'Mobile Money';

  @override
  String get profileCreditScore => 'Score de crédit';

  @override
  String get profileNotLinked => 'Non lié';

  @override
  String get profileCreditReadiness => 'Préparation au crédit';

  @override
  String get profileDriverTools => 'Outils chauffeur';

  @override
  String get profileCoolStatus => 'Statut COOL';

  @override
  String get profileAdminPanel => 'Panneau admin';

  @override
  String get officialNameLabel => 'Nom officiel';

  @override
  String get identityLabel => 'Identité';

  @override
  String get moneySectionTitle => 'Argent';

  @override
  String get preferencesSectionTitle => 'Préférences';

  @override
  String get moreToolsSectionTitle => 'Plus d\'outils';

  @override
  String get profileMoreToolsShowSubtitle =>
      'Afficher les actions supplémentaires et raccourcis secondaires.';

  @override
  String get profileMoreToolsHideSubtitle =>
      'Masquer les raccourcis QR, chauffeur, statut et admin.';

  @override
  String get vehicleLabel => 'Véhicule';

  @override
  String get accountActionsTitle => 'Actions du compte';

  @override
  String get signOutAction => 'Se déconnecter';

  @override
  String get deleteAccountAction => 'Supprimer le compte';

  @override
  String get deleteAccountQuestion => 'Supprimer le compte ?';

  @override
  String get deleteAccountMessage =>
      'Cela supprime définitivement votre compte et vos données.';

  @override
  String get signOutMessage =>
      'Vous devrez vérifier votre numéro à nouveau pour vous reconnecter.';

  @override
  String get completeProfileTitle => 'Complétez votre profil';

  @override
  String get completeProfileSubtitle =>
      'Terminez la configuration pour débloquer toutes les fonctionnalités.';

  @override
  String get profileSavingMomoInfo => 'Enregistrement des infos MoMo...';

  @override
  String get profileDeletingAccount => 'Suppression de votre compte...';

  @override
  String get profileMomoUpdated => 'Infos MoMo mises à jour';

  @override
  String get profileMomoUpdateFailed =>
      'Échec de la mise à jour des infos MoMo';

  @override
  String get profileSupportOpenError =>
      'Impossible d\'ouvrir WhatsApp. Veuillez réessayer.';

  @override
  String get profileSupportUnavailable =>
      'L\'assistance est indisponible pour le moment.';

  @override
  String get profileMomoQrTitle => 'QR MoMo';

  @override
  String profileMomoQrSubtitle(String number) {
    return 'Scannez pour payer $number';
  }

  @override
  String get profileEditMomoInfo => 'Modifier les infos MoMo';

  @override
  String get profileEditMomoSubtitle =>
      'Ce numéro sera utilisé pour les paiements Mobile Money';

  @override
  String get profileMomoCodeOptional => 'CODE MOMO (OPTIONNEL)';

  @override
  String get kycNeedsUpdate => 'À mettre à jour';

  @override
  String get kycUnverified => 'Non vérifié';

  @override
  String get userFallbackName => 'Utilisateur';

  @override
  String get notSetLabel => 'Non défini';

  @override
  String get momoStatementsTitle => 'Relevés et grand livre';

  @override
  String get momoRefreshStatements => 'Actualiser les relevés';

  @override
  String get statementOverviewTitle => 'Aperçu du relevé';

  @override
  String get walletEntriesMetric => 'Entrées portefeuille';

  @override
  String get savingsEntriesMetric => 'Entrées épargne';

  @override
  String get walletEmptyTitle => 'Aucune entrée de portefeuille';

  @override
  String get walletEmptyMessage =>
      'L\'activité du portefeuille apparaîtra ici.';

  @override
  String get walletLedgerTitle => 'Grand livre portefeuille';

  @override
  String walletLedgerSubtitle(int shown, int total) {
    return '$shown sur $total écritures portefeuille.';
  }

  @override
  String get savingsEmptyTitle => 'Aucune entrée d\'épargne';

  @override
  String get savingsEmptyMessage =>
      'Les contributions d\'épargne apparaîtront ici.';

  @override
  String get savingsStatementTitle => 'Relevé d\'épargne';

  @override
  String savingsStatementSubtitle(int shown, int total) {
    return '$shown sur $total contributions de groupe affichées.';
  }

  @override
  String get coolMemberFallback => 'Membre COOL';

  @override
  String get momoStatementsPeriodDay => 'Jour';

  @override
  String get momoStatementsPeriodWeek => 'Semaine';

  @override
  String get momoStatementsPeriodMonth => 'Mois';

  @override
  String get momoStatementsPeriodCustom => 'Personnalisé';

  @override
  String get momoStatementsPeriodAll => 'Tout';

  @override
  String get momoStatementsSortNewestFirst => 'Plus récent d\'abord';

  @override
  String get momoStatementsSortOldestFirst => 'Plus ancien d\'abord';

  @override
  String get momoStatementsSortAmountHighToLow => 'Montant : élevé → bas';

  @override
  String get momoStatementsSortAmountLowToHigh => 'Montant : bas → élevé';

  @override
  String get momoStatementsSortNameAz => 'Nom : A → Z';

  @override
  String get momoStatementsSortNameZa => 'Nom : Z → A';

  @override
  String get momoStatementsWalletFilteredEmptyTitle =>
      'Aucune entrée de portefeuille correspondante';

  @override
  String get momoStatementsWalletFilteredEmptyMessage =>
      'Essayez d\'ajuster vos filtres ou la période.';

  @override
  String get momoStatementsSavingsFilteredEmptyTitle =>
      'Aucune entrée d\'épargne correspondante';

  @override
  String get momoStatementsSavingsFilteredEmptyMessage =>
      'Essayez d\'ajuster vos filtres ou la période.';

  @override
  String get fansScreenUnavailableTitle => 'Hub Fan déplacé';

  @override
  String get fansScreenHeadline => 'Hub Fan';

  @override
  String fansScreenBody(String clubName) {
    return 'Les fonctionnalités fan pour $clubName sont désormais dans le hub partenaire.';
  }

  @override
  String get fansScreenMembershipUnavailable =>
      'Les fonctionnalités d\'adhésion se trouvent dans Rayon Sports.';

  @override
  String get fansScreenClubsUnavailable =>
      'Les clubs de fans sont désormais gérés dans Rayon Sports.';

  @override
  String get fansScreenRayonDedicatedHub =>
      'Rayon Sports dispose d\'un hub dédié aux fans.';

  @override
  String get fansScreenRouteKeptReachable =>
      'Cette route est maintenue accessible pour les liens profonds.';

  @override
  String get fansScreenBackToPartners => 'Retour aux partenaires';

  @override
  String get fansScreenOpenRayon => 'Ouvrir Rayon Sports';

  @override
  String get ticketWalletInvalidLink => 'Lien Google Wallet invalide.';

  @override
  String get ticketWalletUnavailable =>
      'Google Wallet n\'est pas disponible sur cet appareil.';

  @override
  String get ticketWalletOpenFailed => 'Impossible d\'ouvrir Google Wallet.';

  @override
  String get ticketConfirmationScreenTitle => 'Billet';

  @override
  String get ticketConfirmationNotFound => 'Billet introuvable.';

  @override
  String get ticketAddToGoogleWallet => 'Ajouter à Google Wallet';

  @override
  String get ticketBackToTickets => 'Retour aux billets';

  @override
  String get ticketShareMatchTitle => 'Partager le match';

  @override
  String ticketShareMatchText(String matchTitle) {
    return 'Découvrez $matchTitle sur Cool !';
  }

  @override
  String get ticketStatusPendingTitle => 'Paiement en attente';

  @override
  String get ticketStatusPendingSubtitle => 'En attente de confirmation MoMo.';

  @override
  String get ticketStatusPendingNote =>
      'Votre billet est réservé. Finalisez le paiement MoMo pour l\'activer.';

  @override
  String get ticketStatusValidTitle => 'Billet valide';

  @override
  String get ticketStatusValidSubtitle => 'Présentez-le à l\'entrée.';

  @override
  String get ticketStatusValidNote =>
      'Présentez le code QR ci-dessous à l\'entrée du stade.';

  @override
  String get ticketStatusUsedTitle => 'Billet utilisé';

  @override
  String get ticketStatusUsedSubtitle => 'Ce billet a été scanné.';

  @override
  String get ticketStatusUsedNote =>
      'Ce billet a été validé à l\'entrée. Il ne peut plus être utilisé.';

  @override
  String get ticketStatusCancelledTitle => 'Billet annulé';

  @override
  String get ticketStatusCancelledSubtitle => 'Ce billet n\'est plus valide.';

  @override
  String get ticketStatusCancelledNote =>
      'Contactez le support si vous pensez qu\'il s\'agit d\'une erreur.';

  @override
  String get partnersHomeTooltip => 'Accueil partenaires';

  @override
  String get partnersServicesTab => 'Services';

  @override
  String get partnersRayonWelcomeTitle => 'Bienvenue chez Rayon Sports !';

  @override
  String get partnersRayonWelcomeSubtitle =>
      'Votre adhésion fan a été créée. Profitez d\'avantages exclusifs, de billets et d\'actualités du club.';

  @override
  String get partnersOpenRayonSports => 'Ouvrir Rayon Sports';

  @override
  String get partnersMembershipPerkRegistryAccess => 'Accès au registre fan';

  @override
  String get partnersMembershipPerkClubUpdates => 'Actualités du club';

  @override
  String get partnersMembershipPerkMemberQueue => 'File prioritaire membre';

  @override
  String get partnersMembershipPerkPriorityTickets =>
      'Accès prioritaire aux billets';

  @override
  String get partnersMembershipPerkShopDiscount => 'Remise boutique';

  @override
  String get partnersMembershipPerkVipQueue => 'File VIP';

  @override
  String get partnersMembershipPerkVipAccess => 'Accès VIP événements';

  @override
  String get partnersMembershipPerkExclusiveEvents => 'Événements exclusifs';

  @override
  String get partnersNoFootballPartners =>
      'Aucun partenaire football disponible.';

  @override
  String partnersComingSoonMessage(String partnerName) {
    return '$partnerName arrive bientôt !';
  }

  @override
  String get partnersRayonHubBadge => 'Hub Fan Officiel';

  @override
  String get partnersGamesMetricLabel => 'Matchs';

  @override
  String get partnersLoadingMessage => 'Chargement des partenaires…';

  @override
  String get partnersNoFinancePartners =>
      'Aucun partenaire financier disponible.';

  @override
  String get partnersFinancePrepTitle => 'Préparation financière';

  @override
  String get partnersFinancePrepSubtitle =>
      'Vérifiez votre admissibilité au crédit et préparez-vous aux services financiers de nos partenaires.';

  @override
  String get partnersReadinessChecklistCta => 'Checklist d\'admissibilité';

  @override
  String partnersWhatsappMessage(String partnerName) {
    return 'Bonjour, j\'aimerais en savoir plus sur $partnerName sur Cool.';
  }

  @override
  String get partnersNoServicePartners =>
      'Aucun partenaire de services disponible.';

  @override
  String get partnersInsurancePartnerBadge => 'Partenaire assurance';

  @override
  String get partnersProfessionalServicesBadge => 'Services professionnels';

  @override
  String get partnersServicePartnerBadge => 'Partenaire de services';

  @override
  String get partnersLoadErrorTitle => 'Impossible de charger les partenaires';

  @override
  String get partnersEmptyMessage =>
      'Les partenaires apparaîtront ici une fois disponibles.';

  @override
  String get partnersClubShopSubtitle => 'Merchandising officiel';

  @override
  String get partnersFootballTab => 'Football';

  @override
  String get partnersFinanceTab => 'Finance';

  @override
  String get partnersFeaturesTitle => 'Fonctionnalités';

  @override
  String get momoNfcInvalidRequest => 'Demande de paiement NFC invalide.';

  @override
  String get momoLaunchingUssd => 'Lancement USSD…';

  @override
  String get momoNfcLaunchFailed =>
      'Échec du lancement NFC. Veuillez réessayer.';

  @override
  String get momoScreenTitle => 'Mobile Money';

  @override
  String get momoNfcLaunchingOverlay => 'Lancement MoMo…';

  @override
  String get momoSendValidationError =>
      'Veuillez entrer un destinataire et un montant valides.';

  @override
  String momoSendLaunchFailed(String countryName) {
    return 'Impossible de lancer le paiement MoMo pour $countryName.';
  }

  @override
  String momoFromNumber(String number) {
    return 'De $number';
  }

  @override
  String get momoRoutePhoneLabel => 'Numéro de téléphone';

  @override
  String get momoRouteCodeLabel => 'Code MoMo';

  @override
  String get momoRecipientCodeLabel => 'Code MoMo du destinataire';

  @override
  String get momoRecipientPhoneLabel => 'Téléphone du destinataire';

  @override
  String momoAmountLabel(String currency) {
    return 'Montant ($currency)';
  }

  @override
  String momoSendCompletesViaUssd(String countryName) {
    return 'Se termine via USSD sur votre SIM $countryName.';
  }

  @override
  String get momoConfirmSendLabel => 'Envoyer de l\'argent';

  @override
  String get momoStatementsPayerLabel => 'Payeur';

  @override
  String get momoStatementsAllPayers => 'Tous les payeurs';

  @override
  String get momoStatementsAllGroups => 'Tous les groupes';

  @override
  String get momoStatementsSelectCustomPeriod =>
      'Choisir une période personnalisée';

  @override
  String get momoStatementsNothingToDownload =>
      'Rien à télécharger pour le moment.';

  @override
  String momoStatementsSavedFile(String fileName) {
    return 'Enregistré : $fileName';
  }

  @override
  String momoStatementsDownloadedFile(String fileName) {
    return 'Téléchargé : $fileName';
  }

  @override
  String get momoStatementsDownloadFailed =>
      'Échec du téléchargement du relevé.';

  @override
  String momoStatementsFilterSummaryPeriod(String period) {
    return 'Période : $period';
  }

  @override
  String momoStatementsFilterSummaryParty(String label, String value) {
    return '$label : $value';
  }

  @override
  String get momoStatementsFilterTitle => 'Filtres et exports';

  @override
  String get momoStatementsSortByLabel => 'Tri';

  @override
  String get resetAction => 'Réinitialiser';

  @override
  String get momoStatementsPreparingLabel => 'Export en cours…';

  @override
  String get momoStatementsPdfLabel => 'PDF';

  @override
  String get momoStatementsExcelLabel => 'Excel';

  @override
  String get groupsTabAll => 'Tous';

  @override
  String get groupsTabSaving => 'Épargne';

  @override
  String get groupsTabCommunity => 'Communautaire';

  @override
  String get groupsTabPublic => 'Public';

  @override
  String get groupsTabPrivate => 'Privé';

  @override
  String groupsShareText(String groupName, String inviteUrl) {
    return 'Rejoignez $groupName sur Cool : $inviteUrl';
  }

  @override
  String get groupsCreateNewTitle => 'Créer un nouveau groupe';

  @override
  String get groupsCreateNewSubtitle => 'Épargne ou communautaire';

  @override
  String get groupsEmptyPublicTitle => 'Aucun groupe public trouvé';

  @override
  String get groupsEmptyPublicMessage =>
      'Tirez pour actualiser ou vérifiez vos groupes.';

  @override
  String get groupsEmptyPrivateMessage =>
      'Créez un groupe ou parcourez les groupes publics.';

  @override
  String groupsBankCustodianMeta(String partnerName) {
    return 'Banque dépositaire · $partnerName';
  }

  @override
  String groupsMomoRouteMeta(String number) {
    return 'Route MoMo · $number';
  }

  @override
  String get groupsSavingGroupMeta => 'Groupe d\'épargne';

  @override
  String get groupsCommunityFundMeta => 'Fonds communautaire';

  @override
  String get groupsRaisedLabel => 'collecté';

  @override
  String get groupsShareAction => 'Partager';

  @override
  String get groupsLoadErrorTitle => 'Une erreur est survenue';

  @override
  String get profileTierBlue => 'Bleu';

  @override
  String get profileTierSilver => 'Argent';

  @override
  String get profileTierGold => 'Or';

  @override
  String get profileTierPlatinum => 'Platine';

  @override
  String get profileSavingIdentity =>
      'Enregistrement des informations d\'identité...';

  @override
  String get profileIdentityUpdated => 'Informations d\'identité mises à jour';

  @override
  String get profileIdentityUpdateFailed =>
      'Échec de la mise à jour des informations d\'identité';

  @override
  String get profileAppAccess => 'Accès de l\'application';

  @override
  String get profileManageAction => 'Gérer';

  @override
  String profileCoolStatusValue(String tier, int points) {
    return '$tier · $points pts';
  }

  @override
  String get profileUserIdLabel => 'ID utilisateur';

  @override
  String get profileWalletLabel => 'Portefeuille';

  @override
  String get profileSetupTitle => 'Configuration du profil';

  @override
  String get profilePublicProfileLabel => 'Profil public';

  @override
  String get profileOfficialIdentityLabel => 'Identité officielle';

  @override
  String get profilePassengerRoleLabel => 'Passager';

  @override
  String get profileDriverRoleLabel => 'Chauffeur';

  @override
  String get mobilityNoWhatsappAvailable =>
      'Aucun contact WhatsApp disponible pour le moment.';

  @override
  String get mobilityNoContactYet => 'Aucun contact pour le moment';

  @override
  String get mobilityLocationRequiredDriverMode =>
      'La localisation est requise avant d\'activer le mode chauffeur.';

  @override
  String momoSendMoneyOpensUssd(String countryName) {
    return 'Ouvrez le code USSD MoMo de $countryName pour envoyer de l\'argent.';
  }

  @override
  String get momoMoreToolsSubtitle =>
      'Relevés, QR et outils NFC pour votre route.';

  @override
  String get momoStatementsToolSubtitle =>
      'Consultez l\'historique du portefeuille et de l\'épargne.';

  @override
  String get momoNfcToolsTitle => 'Outils NFC';

  @override
  String get momoNfcToolsSubtitle =>
      'Paiement sans contact et partage de route.';

  @override
  String get basketScreenTitle => 'Panier';

  @override
  String get basketScreenHeadline =>
      'Le panier n\'est pas actif pour le moment';

  @override
  String get basketScreenBody =>
      'Cette route reste disponible pour la compatibilité, mais les soldes et la création de paniers ne sont pas actifs dans cette version.';

  @override
  String get basketScreenCardBody =>
      'Les produits panier sont en pause pendant la finalisation de la prochaine version.';

  @override
  String get basketScreenExpectationBalances =>
      'Aucun solde panier en direct n\'est affiché ici.';

  @override
  String get basketScreenExpectationCreation =>
      'La création de nouveaux paniers est actuellement désactivée.';

  @override
  String get basketScreenExpectationLinks =>
      'Les liens profonds existants arrivent toujours sur cet écran.';

  @override
  String get basketScreenBackHome => 'Retour à l\'accueil';
}
