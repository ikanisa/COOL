import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:cool_app/core/models/geo_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../services/mobility_whatsapp_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../../../shared/widgets/cool_screen_background.dart';
import '../models/driver_info.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../widgets/mobility_list_widgets.dart';
import '../widgets/mobility_listing_sheet.dart';

class MobilityHomeScreen extends ConsumerStatefulWidget {
  const MobilityHomeScreen({super.key});

  @override
  ConsumerState<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends ConsumerState<MobilityHomeScreen> {
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;
  late final MobilityLocationNotifier _locationNotifier;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);
    _locationSubscription = ref.listenManual<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
        if (!mounted) {
          return;
        }
        final notifier = ref.read(mobilityProvider.notifier);
        final nextPosition = next.position;
        if (next.hasLocation && nextPosition != null) {
          final driverNotifier = ref.read(driverProvider.notifier);
          final driverState = ref.read(driverProvider);
          final previousPosition = previous?.position;
          notifier.updateLocation(nextPosition);
          final shouldReload =
              previousPosition == null ||
              _distanceBetween(previousPosition, nextPosition) > 0.05 ||
              previous?.status != next.status;
          if (shouldReload) {
            if (driverState.profile?.isOnline == true) {
              unawaited(
                driverNotifier.syncOnlineLocation(
                  latitude: nextPosition.latitude,
                  longitude: nextPosition.longitude,
                ),
              );
            }
            unawaited(notifier.loadNearbyDrivers());
            unawaited(notifier.loadScheduledTrips());
          }
          return;
        }

        if (previous?.hasLocation == true && !next.hasLocation) {
          notifier.clearLocation();
        }
      },
    );

    Future.microtask(() async {
      await ref.read(driverProvider.notifier).loadDriverProfile();
      await _locationNotifier.bootstrap();
      await _locationNotifier.acquireTracking();
    });
  }

  @override
  void dispose() {
    _locationSubscription.close();
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _refreshNearbyDrivers() async {
    await _locationNotifier.refresh();

    final locationState = ref.read(mobilityLocationProvider);
    if (!locationState.hasLocation) {
      return;
    }

    final notifier = ref.read(mobilityProvider.notifier);
    await notifier.loadNearbyDrivers();
    await notifier.loadScheduledTrips();
  }

  void _showMarketplaceSnackBar(String message) {
    CoolToast.info(context, message);
  }

  Future<void> _openTripWhatsApp(Trip trip) async {
    final l10n = context.l10n;
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(l10n.mobilityNoWhatsappAvailable);
      return;
    }

    final message = MobilityWhatsAppService.buildTripInquiryMessage(
      trip: trip,
      requester: ref.read(currentUserProvider),
    );

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  Future<void> _openDriverWhatsApp(DriverInfo driver) async {
    final l10n = context.l10n;
    final phoneNumber = driver.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showMarketplaceSnackBar(l10n.mobilityNoWhatsappAvailable);
      return;
    }

    final message = MobilityWhatsAppService.buildDriverInquiryMessage(
      driver: driver,
      requester: ref.read(currentUserProvider),
    );

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: message,
    );
  }

  Future<void> _showTripPreview(Trip trip) {
    final l10n = context.l10n;
    return showTripListingSheet(
      context,
      trip: trip,
      buttonLabel: _hasTripContact(trip)
          ? l10n.contactViaWhatsapp
          : l10n.mobilityNoContactYet,
      onOpenWhatsApp: _hasTripContact(trip)
          ? () {
              unawaited(_openTripWhatsApp(trip));
            }
          : null,
    );
  }

  Future<void> _showDriverPreview(DriverInfo driver) {
    final l10n = context.l10n;
    return showDriverListingSheet(
      context,
      driver: driver,
      buttonLabel: _hasDriverContact(driver)
          ? l10n.contactViaWhatsapp
          : l10n.mobilityNoContactYet,
      onOpenWhatsApp: _hasDriverContact(driver)
          ? () {
              unawaited(_openDriverWhatsApp(driver));
            }
          : null,
    );
  }

  double _distanceBetween(GeoPoint a, GeoPoint b) {
    return a.distanceToKm(b);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final currentUser = ref.watch(currentUserProvider);
    final driverProfile = ref.watch(
      driverProvider.select((state) => state.profile),
    );
    final isDriver = (currentUser?.isDriver ?? false) || driverProfile != null;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.home),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: CoolScreenBackground(
        child: RefreshIndicator(
          color: palette.accent,
          backgroundColor: palette.surface2,
          onRefresh: _refreshNearbyDrivers,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    l10n.navMobility,
                    style: GoogleFonts.dmSans(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(18, isDriver ? 0 : 8, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: MobilityTopActionsCard(
                    isDriver: isDriver,
                    onScheduleTrip: () =>
                        context.push(AppRoutes.mobilitySchedule),
                  ),
                ),
              ),
              MobilityContentSliver(
                onDriverPreviewTap: (driver) {
                  unawaited(_showDriverPreview(driver));
                },
                onDriverWhatsAppTap: (driver) {
                  unawaited(_openDriverWhatsApp(driver));
                },
                onTripPreviewTap: (trip) {
                  unawaited(_showTripPreview(trip));
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
      ),
    );
  }
}

bool _hasTripContact(Trip trip) =>
    (trip.whatsappNumber?.trim().isNotEmpty ?? false) ||
    (trip.contactPhone?.trim().isNotEmpty ?? false);

bool _hasDriverContact(DriverInfo driver) =>
    driver.contactPhone?.trim().isNotEmpty ?? false;
