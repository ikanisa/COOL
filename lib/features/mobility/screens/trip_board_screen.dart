import 'dart:async';

import 'package:cool_app/features/mobility/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../auth/providers/auth_provider.dart';
import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_toast.dart';
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
  late final ProviderSubscription<MobilityLocationState> _locationSubscription;
  late final MobilityLocationNotifier _locationNotifier;
  TripBoardViewMode _activeView = TripBoardViewMode.explore;

  @override
  void initState() {
    super.initState();
    _locationNotifier = ref.read(mobilityLocationProvider.notifier);
    _locationSubscription = ref.listenManual<MobilityLocationState>(
      mobilityLocationProvider,
      (previous, next) {
        final notifier = ref.read(tripBoardProvider.notifier);
        notifier.updateLocation(next.position);

        final hadLocation = previous?.hasLocation ?? false;
        if (!hadLocation && next.hasLocation) {
          unawaited(notifier.loadPublicTrips());
        } else if (hadLocation && !next.hasLocation) {
          notifier.clearPublicTrips();
        }
      },
    );

    Future<void>.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _locationSubscription.close();
    unawaited(_locationNotifier.releaseTracking());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _locationNotifier.bootstrap();
    await _locationNotifier.acquireTracking();

    ref
        .read(tripBoardProvider.notifier)
        .updateLocation(ref.read(mobilityLocationProvider).position);

    await ref.read(tripBoardProvider.notifier).refresh();
  }

  Future<void> _refreshTrips() async {
    await _locationNotifier.refresh();
    ref
        .read(tripBoardProvider.notifier)
        .updateLocation(ref.read(mobilityLocationProvider).position);
    await ref.read(tripBoardProvider.notifier).refresh();
  }

  Future<void> _openWhatsApp(Trip trip) async {
    final phoneNumber =
        trip.whatsappNumber?.trim() ?? trip.contactPhone?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      _showSnackBar('Contact details are not available for this trip yet.');
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
      buttonLabel:
          hasContactPhone(trip) ? 'Open WhatsApp' : 'No contact yet',
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
      _showSnackBar('This trip cannot be canceled right now.');
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
      _showSnackBar('This trip cannot be deleted right now.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Delete Trip?',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.text,
          ),
        ),
        content: Text(
          'This will permanently delete the trip from '
          '${trip.fromLocation} to ${trip.toLocation}. '
          'This action cannot be undone.',
          style: GoogleFonts.dmSans(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.text2,
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
                color: AppColors.text2,
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
                color: AppColors.red,
              ),
            ),
          ),
        ],
      ),
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
      _showSnackBar('This trip cannot be paused right now.');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .pauseTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip paused. It will no longer appear to others.');
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
      _showSnackBar('This trip cannot be reposted right now.');
      return;
    }

    final succeeded = await ref
        .read(tripBoardProvider.notifier)
        .repostTrip(tripId);

    if (!mounted) return;

    if (succeeded) {
      _showSnackBar('Trip reposted and visible again.');
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
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${trip.fromLocation} \u2192 ${trip.toLocation}',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 18),
                if (isActive) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.pause_circle_outline_rounded,
                      color: AppColors.orange,
                    ),
                    title: Text(
                      'Pause Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    subtitle: Text(
                      'Temporarily hide from others',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_pauseTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.cancel_outlined,
                      color: AppColors.red,
                    ),
                    title: Text(
                      'Cancel Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_cancelTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                ],
                if (isPaused) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.play_circle_outline_rounded,
                      color: AppColors.accent,
                    ),
                    title: Text(
                      'Repost Trip',
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    subtitle: Text(
                      'Make visible to others again',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.text3,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_repostTrip(trip));
                    },
                  ),
                  const Divider(color: AppColors.border),
                ],
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.red,
                  ),
                  title: Text(
                    'Delete Trip',
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          'Trip board',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        onRefresh: _refreshTrips,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              sliver: SliverToBoxAdapter(
                child: TripBoardModeSwitcher(
                  activeView: _activeView,
                  onChanged: (view) {
                    setState(() => _activeView = view);
                  },
                ),
              ),
            ),
            if (_activeView == TripBoardViewMode.explore) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: TripBoardExploreHeaderCard(
                    onPostTrip: () => context.push('/mobility/schedule'),
                  ),
                ),
              ),
              TripBoardPublicTripsSliver(
                onPreviewTap: (trip) {
                  unawaited(_showTripPreview(trip));
                },
                onWhatsAppTap: (trip) {
                  unawaited(_openWhatsApp(trip));
                },
              ),
            ] else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                sliver: SliverToBoxAdapter(
                  child: TripBoardMyTripsHeaderCard(
                    onPostTrip: () => context.push('/mobility/schedule'),
                  ),
                ),
              ),
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
    );
  }
}
