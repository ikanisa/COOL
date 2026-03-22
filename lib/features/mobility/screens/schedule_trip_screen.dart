import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/production_redesign_provider.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/intl_locale.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/providers/engagement_providers.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/schedule_trip_place_search_sheet.dart';
import '../widgets/schedule_trip_step_widgets.dart';

import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';

part 'schedule_trip_screen_logic.dart';
part '../widgets/schedule_trip_role_card.dart';

enum ScheduleTripPostingRole { passenger, driver }

class ScheduleTripScreen extends ConsumerStatefulWidget {
  const ScheduleTripScreen({super.key, this.initialRole});

  final ScheduleTripPostingRole? initialRole;

  @override
  ConsumerState<ScheduleTripScreen> createState() => _ScheduleTripScreenState();
}

class _ScheduleTripScreenState extends ConsumerState<ScheduleTripScreen>
    with CoolStatusAwarder {
  // ignore: use_setters_to_change_properties
  /// Proxy for [setState] so the extension in the logic part file can trigger rebuilds.
  void _updateState(VoidCallback fn) => setState(fn);

  final _formKey = GlobalKey<FormState>();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();
  final _priceNoteController = TextEditingController();

  late DateTime _selectedDate;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 7, minute: 0);
  TripVehiclePreference _vehiclePreference = TripVehiclePreference.any;
  int _seats = 1;
  bool _recurringTrip = false;
  final Set<TripWeekday> _recurringDays = <TripWeekday>{};
  PlaceSearchResult? _fromSelection;
  PlaceSearchResult? _toSelection;
  bool _resolvingCurrentLocation = false;
  bool _resolvingTypedRoute = false;
  MobilityRoutePreview? _routePreview;
  bool _loadingRoutePreview = false;
  String? _routePreviewError;
  int _routePreviewRequestId = 0;

  ScheduleTripPostingRole _postingRole = ScheduleTripPostingRole.passenger;
  bool _showAdditionalDetails = false;
  bool _didResolveInitialRole = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _fromController.addListener(_syncResolvedLocations);
    _toController.addListener(_syncResolvedLocations);
    Future<void>.microtask(() async {
      await ref.read(mobilityLocationProvider.notifier).bootstrap();
    });
  }

  @override
  void dispose() {
    _fromController.removeListener(_syncResolvedLocations);
    _toController.removeListener(_syncResolvedLocations);
    _fromController.dispose();
    _toController.dispose();
    _priceNoteController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didResolveInitialRole) {
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    final driverProfile = ref.read(driverProvider).profile;
    final resolvedRole = widget.initialRole ?? _initialPostingRoleFromRoute();
    _postingRole = resolvedRole;
    _applyPostingRoleDefaults(
      role: resolvedRole,
      vehicleType: driverProfile?.vehicleType ?? currentUser?.vehicleType,
    );
    _didResolveInitialRole = true;
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.coolPalette;
    final useProductionRedesign = ref.watch(
      productionRedesignEnabledProvider(
        const ProductionRedesignScope(
          route: ProductionRedesignRoutes.mobilitySchedule,
        ),
      ),
    );
    final isSubmitting = ref.watch(mobilitySubmissionLoadingProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final currentUser = ref.watch(currentUserProvider);
    final driverProfile = ref.watch(
      driverProvider.select((state) => state.profile),
    );
    final driverVehicleType =
        driverProfile?.vehicleType ?? currentUser?.vehicleType;
    final hasDriverRole =
        (currentUser?.isDriver ?? false) || driverProfile != null;
    final canScheduleAsDriver = _canScheduleAsDriver(
      hasDriverRole: hasDriverRole,
      vehicleType: driverVehicleType,
    );
    final isDriverPosting = _postingRole == ScheduleTripPostingRole.driver;

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
        title: Text(
          l10n.scheduleTripTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: palette.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      if (useProductionRedesign) ...[
                        _ScheduleTripCommandCard(
                          postingRole: _postingRole,
                          routePreview: _routePreview,
                          driverVehicleType: driverVehicleType,
                          canScheduleAsDriver: canScheduleAsDriver,
                        ),
                        const SizedBox(height: 20),
                      ],
                      // ── Role selector ──────────────────────────
                      _ScheduleTripRoleRow(
                        selectedRole: _postingRole,
                        canScheduleAsDriver: canScheduleAsDriver,
                        onOpenRoleSheet: () =>
                            unawaited(_openRoleSheet(canScheduleAsDriver)),
                        onOpenDriverSetup: () =>
                            context.push(AppRoutes.mobilityDriver),
                      ),
                      const SizedBox(height: 20),

                      // ── Route ──────────────────────────────────
                      ScheduleTripRouteStep(
                        isDriverPosting: isDriverPosting,
                        fromController: _fromController,
                        toController: _toController,
                        fromSelection: _fromSelection,
                        toSelection: _toSelection,
                        isResolvingCurrentLocation: _resolvingCurrentLocation,
                        routePreview: _routePreview,
                        loadingRoutePreview: _loadingRoutePreview,
                        resolvingTypedRoute: _resolvingTypedRoute,
                        routePreviewError: _routePreviewError,
                        locationState: locationState,
                        shouldShowLocationCard:
                            _shouldShowLocationAttachmentCard(locationState),
                        onFromSearchTap: () => _openPlaceSearch(isOrigin: true),
                        onToSearchTap: () => _openPlaceSearch(isOrigin: false),
                        onUseCurrentLocationTap: _useCurrentLocationForPickup,
                        onEnableLocation: () {
                          ref
                              .read(mobilityLocationProvider.notifier)
                              .requestForegroundAccess();
                        },
                        onOpenAppSettings: () {
                          ref
                              .read(mobilityLocationProvider.notifier)
                              .openAppSettings();
                        },
                        onOpenLocationSettings: () {
                          ref
                              .read(mobilityLocationProvider.notifier)
                              .openLocationSettings();
                        },
                        fromValidator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return l10n.scheduleTripFromRequired;
                          }
                          if ((value ?? '').trim() ==
                              _toController.text.trim()) {
                            return l10n.scheduleTripRouteSameError;
                          }
                          return null;
                        },
                        toValidator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return l10n.scheduleTripToRequired;
                          }
                          if ((value ?? '').trim() ==
                              _fromController.text.trim()) {
                            return l10n.scheduleTripRouteSameError;
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // ── Timing ─────────────────────────────────
                      ScheduleTripTimingStep(
                        isDriverPosting: isDriverPosting,
                        selectedDate: _selectedDate,
                        selectedTime: _selectedTime,
                        recurringTrip: _recurringTrip,
                        recurringDays: _recurringDays,
                        formatDate: _formatDate,
                        formatTime: _formatTime,
                        onPickDate: _pickDate,
                        onPickTime: _pickTime,
                        onRecurringTripToggled: (value) {
                          setState(() {
                            _recurringTrip = value;
                            if (!value) _recurringDays.clear();
                          });
                        },
                        onRecurringDayToggled: (day) {
                          setState(() {
                            if (_recurringDays.contains(day)) {
                              _recurringDays.remove(day);
                            } else {
                              _recurringDays.add(day);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 20),

                      // ── Options ────────────────────────────────
                      ScheduleTripOptionsStep(
                        isDriverPosting: isDriverPosting,
                        driverVehicleLabel: driverVehicleType,
                        vehiclePreference: _vehiclePreference,
                        seats: _seats,
                        showAdditionalDetails: _showAdditionalDetails,
                        priceNoteController: _priceNoteController,
                        onVehicleChanged: (value) {
                          setState(() => _vehiclePreference = value);
                          unawaited(_refreshRoutePreview());
                        },
                        onSeatChanged: (value) =>
                            setState(() => _seats = value),
                        onToggleDetails: () {
                          setState(() {
                            _showAdditionalDetails = !_showAdditionalDetails;
                          });
                        },
                      ),
                      const SizedBox(height: 32),

                      if (useProductionRedesign) ...[
                        _ScheduleTripSubmissionCard(
                          postingRole: _postingRole,
                          fromLabel: _fromController.text.trim(),
                          toLabel: _toController.text.trim(),
                          departureLabel:
                              '${_formatDate(_selectedDate)} · ${_formatTime(_selectedTime)}',
                          seats: _seats,
                          vehiclePreference: _vehiclePreference,
                          routePreview: _routePreview,
                          recurringTrip: _recurringTrip,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── CTA ────────────────────────────────────
                      CoolButton(
                        label: l10n.scheduleTripPostCta,
                        isLoading: isSubmitting || _resolvingTypedRoute,
                        onTap: () async {
                          await _resolveTypedRouteSelections();
                          if (!mounted) return;
                          await _submit(
                            canScheduleAsDriver: canScheduleAsDriver,
                          );
                        },
                      ),
                      const SizedBox(height: 80),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Role selector row (replaces _ScheduleTripProgressCard)
// ═════════════════════════════════════════════════════════════════════════

class _ScheduleTripRoleRow extends StatelessWidget {
  const _ScheduleTripRoleRow({
    required this.selectedRole,
    required this.canScheduleAsDriver,
    required this.onOpenRoleSheet,
    required this.onOpenDriverSetup,
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;
  final VoidCallback onOpenRoleSheet;
  final VoidCallback onOpenDriverSetup;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isDriver = selectedRole == ScheduleTripPostingRole.driver;
    final label = isDriver ? 'Posting as driver' : 'Posting as passenger';

    return Semantics(
      button: true,
      label: '$label — tap to switch role',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onOpenRoleSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: palette.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(
                isDriver ? Icons.directions_car_rounded : Icons.person_rounded,
                size: 20,
                color: palette.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
              Icon(Icons.swap_horiz_rounded, size: 20, color: palette.text3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleTripCommandCard extends StatelessWidget {
  const _ScheduleTripCommandCard({
    required this.postingRole,
    required this.routePreview,
    required this.driverVehicleType,
    required this.canScheduleAsDriver,
  });

  final ScheduleTripPostingRole postingRole;
  final MobilityRoutePreview? routePreview;
  final String? driverVehicleType;
  final bool canScheduleAsDriver;

  @override
  Widget build(BuildContext context) {
    final isDriverPosting = postingRole == ScheduleTripPostingRole.driver;

    return CoolCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF101A17), Color(0xFF132822), Color(0xFF1F473A)],
      ),
      borderColor: Colors.white.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDriverPosting ? 'Dispatch Preparation' : 'Trip Dispatch',
            style: GoogleFonts.dmSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDriverPosting
                ? 'Set route, timing, and return capacity with clear board-ready details.'
                : 'Build a clean route request with timing, vehicle preference, and immediate board visibility.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScheduleSignalPill(
                icon: isDriverPosting
                    ? Icons.directions_car_filled_rounded
                    : Icons.person_rounded,
                label: isDriverPosting ? 'Driver post' : 'Passenger request',
                highlighted: true,
              ),
              _ScheduleSignalPill(
                icon: canScheduleAsDriver
                    ? Icons.verified_outlined
                    : Icons.info_outline_rounded,
                label: canScheduleAsDriver
                    ? 'Driver role available'
                    : 'Passenger mode only',
              ),
              if ((driverVehicleType?.trim().isNotEmpty ?? false))
                _ScheduleSignalPill(
                  icon: Icons.local_shipping_outlined,
                  label: driverVehicleType!.trim(),
                ),
              if (routePreview != null) ...[
                _ScheduleSignalPill(
                  icon: Icons.alt_route_rounded,
                  label: routePreview!.distanceLabel,
                ),
                _ScheduleSignalPill(
                  icon: Icons.schedule_rounded,
                  label: routePreview!.durationLabel,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleTripSubmissionCard extends StatelessWidget {
  const _ScheduleTripSubmissionCard({
    required this.postingRole,
    required this.fromLabel,
    required this.toLabel,
    required this.departureLabel,
    required this.seats,
    required this.vehiclePreference,
    required this.routePreview,
    required this.recurringTrip,
  });

  final ScheduleTripPostingRole postingRole;
  final String fromLabel;
  final String toLabel;
  final String departureLabel;
  final int seats;
  final TripVehiclePreference vehiclePreference;
  final MobilityRoutePreview? routePreview;
  final bool recurringTrip;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final routeLabel = fromLabel.isEmpty || toLabel.isEmpty
        ? 'Route details appear after origin and destination are entered.'
        : '$fromLabel → $toLabel';

    return CoolCard(
      borderColor: palette.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Board Submission Review',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            routeLabel,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: palette.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScheduleSurfaceMetric(
                label: 'Role',
                value: postingRole == ScheduleTripPostingRole.driver
                    ? 'Driver'
                    : 'Passenger',
              ),
              _ScheduleSurfaceMetric(label: 'Departure', value: departureLabel),
              _ScheduleSurfaceMetric(label: 'Seats', value: '$seats'),
              _ScheduleSurfaceMetric(
                label: 'Vehicle',
                value: vehiclePreference.name.toUpperCase(),
              ),
              _ScheduleSurfaceMetric(
                label: 'Repeat',
                value: recurringTrip ? 'Recurring' : 'One time',
              ),
              if (routePreview != null)
                _ScheduleSurfaceMetric(
                  label: 'Route',
                  value:
                      '${routePreview!.distanceLabel} · ${routePreview!.durationLabel}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleSignalPill extends StatelessWidget {
  const _ScheduleSignalPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleSurfaceMetric extends StatelessWidget {
  const _ScheduleSurfaceMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;

    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: palette.text3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}
