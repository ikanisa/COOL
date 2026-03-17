import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../providers/discovery_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/trip_board_provider.dart';
import '../services/mobility_whatsapp_service.dart';
import '../widgets/mobility_listing_sheet.dart';
import '../widgets/trip_board_content_widgets.dart';
import '../widgets/trip_board_header_widgets.dart';

class TripBoardScreen extends ConsumerStatefulWidget {
  const TripBoardScreen({super.key});

  @override
  ConsumerState<TripBoardScreen> createState() => _TripBoardScreenState();
}

class _TripBoardScreenState extends ConsumerState<TripBoardScreen> {
  late final MobilityLocationNotifier _locationNotifier;
  TripBoardViewMode _activeView = TripBoardViewMode.explore;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);

    Future<void>.microtask(_bootstrap);
  }

  @override
  void dispose() {
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _locationNotifier.bootstrap();
    await _locationNotifier.acquireTracking();

    await Future.wait([
      ref.read(discoveryProvider.notifier).refresh(),
      ref.read(tripBoardProvider.notifier).loadMyTrips(),
    ]);
  }

  Future<void> _refreshTrips() async {
    await _locationNotifier.refresh();
    await Future.wait([
      ref.read(discoveryProvider.notifier).refresh(),
      ref.read(tripBoardProvider.notifier).loadMyTrips(),
    ]);
  }

  Future<void> _openWhatsApp(Trip trip) async {
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showSnackBar('Contact unavailable');
      return;
    }

    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phoneNumber,
      message: MobilityWhatsAppService.buildTripInquiryMessage(
        trip: trip,
        requester: ref.read(currentUserProvider),
      ),
    );
  }

  Future<void> _showTripPreview(Trip trip) {
    return showTripListingSheet(
      context,
      trip: trip,
      buttonLabel: hasContactPhone(trip) ? 'Open WhatsApp' : 'No contact yet',
      onOpenWhatsApp: hasContactPhone(trip)
          ? () {
              unawaited(_openWhatsApp(trip));
            }
          : null,
    );
  }

  Future<void> _cancelTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('Cancel failed');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .cancelTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip canceled.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _deleteTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('Delete failed');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final palette = context.coolPalette;
        return AlertDialog(
          backgroundColor: palette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: palette.border),
          ),
          title: Text(
            'Delete Trip?',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          content: Text(
            'This will permanently delete'
            '${trip.fromLocation} to ${trip.toLocation}. '
            'This action cannot be undone.',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: palette.text2,
              height: 1.5,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.text2,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Delete',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: palette.red,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .deleteTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip deleted.');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _pauseTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('Pause failed');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .pauseTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip paused');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _repostTrip(Trip trip) async {
    final tripId = trip.id;
    if (tripId == null) {
      _showSnackBar('Repost failed');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .repostTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip reposted');
      return;
    }

    final error = ref.read(tripBoardMutationErrorProvider);
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _showTripActions(Trip trip) async {
    final isPaused = isPausedTrip(trip);
    final isActive = isActiveTrip(trip);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final palette = context.coolPalette;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trip Actions',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${trip.fromLocation} \u2192 ${trip.toLocation}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.text2,
                  ),
                ),
                const SizedBox(height: 18),
                if (isActive) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.pause_circle_outline_rounded,
                      color: palette.orange,
                    ),
                    title: Text(
                      'Pause Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    subtitle: Text(
                      'Temporarily hide from others',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: palette.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pauseTrip(trip));
                    },
                  ),
                  Divider(color: palette.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cancel_outlined, color: palette.red),
                    title: Text(
                      'Cancel Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_cancelTrip(trip));
                    },
                  ),
                  Divider(color: palette.border),
                ],
                if (isPaused) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.play_circle_outline_rounded,
                      color: palette.accent,
                    ),
                    title: Text(
                      'Repost Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    subtitle: Text(
                      'Make visible to others',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: palette.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_repostTrip(trip));
                    },
                  ),
                  Divider(color: palette.border),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: palette.red,
                  ),
                  title: Text(
                    'Delete Trip',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_deleteTrip(trip));
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    CoolToast.info(context, message);
  }

  Future<void> _openTripTypeSheet() async {
    final activeTab = ref.read(tripBoardActiveTabProvider);
    final nextTab = await showModalBottomSheet<TripBoardTab>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => TripBoardTripTypeSheet(activeTab: activeTab),
    );

    if (nextTab == null || !mounted || nextTab == activeTab) {
      return;
    }

    await ref.read(tripBoardProvider.notifier).setActiveTab(nextTab);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
        ),
      ),
      body: CoolScreenBackground(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: Text(
                'Trip Board',
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                  height: 1.1,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: palette.accent,
                backgroundColor: palette.surface,
                onRefresh: _refreshTrips,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                      sliver: SliverToBoxAdapter(
                        child: TripBoardTopCard(
                          activeView: _activeView,
                          onViewChanged: (view) {
                            setState(() => _activeView = view);
                          },
                          onPostTrip: () => context.push('/mobility/schedule'),
                          onOpenTripType: () {
                            unawaited(_openTripTypeSheet());
                          },
                        ),
                      ),
                    ),
                    if (_activeView == TripBoardViewMode.explore) ...[
                      TripBoardPublicTripsSliver(
                        onPreviewTap: (trip) {
                          unawaited(_showTripPreview(trip));
                        },
                        onWhatsAppTap: (trip) {
                          unawaited(_openWhatsApp(trip));
                        },
                      ),
                    ] else ...[
                      TripBoardMyTripsSliver(
                        onShowActions: (trip) {
                          unawaited(_showTripActions(trip));
                        },
                      ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
