import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../services/mobility_whatsapp_service.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';

import '../../../shared/widgets/cool_screen_background.dart';
import '../models/driver_info.dart';
import '../providers/discovery_provider.dart';
import '../widgets/mobility_listing_sheet.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../widgets/mobility_list_widgets.dart';

class MobilityHomeScreen extends ConsumerStatefulWidget {
  const MobilityHomeScreen({super.key});

  @override
  ConsumerState<MobilityHomeScreen> createState() => _MobilityHomeScreenState();
}

class _MobilityHomeScreenState extends ConsumerState<MobilityHomeScreen> {
  late final MobilityLocationNotifier _locationNotifier;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);

    Future.microtask(() async {
      await ref.read(driverProvider.notifier).loadDriverProfile();
      await _locationNotifier.bootstrap();
      await _locationNotifier.acquireTracking();
    });
  }

  @override
  void dispose() {
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _refreshNearby() async {
    await _locationNotifier.refresh();
    await ref.read(discoveryProvider.notifier).refresh();
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
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: CoolScreenBackground(
        child: RefreshIndicator(
          color: palette.accent,
          backgroundColor: palette.surface2,
          onRefresh: _refreshNearby,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: CoolLayout.rootPagePadding.copyWith(bottom: 0, top: 0),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    l10n.navMobility,
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  CoolLayout.horizontalPagePadding,
                  isDriver ? 0 : 8,
                  CoolLayout.horizontalPagePadding,
                  0,
                ),
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
              const SliverToBoxAdapter(
                child: SizedBox(height: CoolLayout.rootBottomClearance),
              ),
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