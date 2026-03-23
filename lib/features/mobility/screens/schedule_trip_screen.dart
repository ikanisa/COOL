import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/providers/production_redesign_provider.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/cool_foundations.dart';
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
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
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          tooltip: context.l10n.back,
          icon: Icon(Icons.arrow_back_rounded, color: colors.primaryText),
        ),
        title: Text(
          l10n.scheduleTripTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: CoolScreenBackground(
        showGlow: false,
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
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;
  final VoidCallback onOpenRoleSheet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final isDriver = selectedRole == ScheduleTripPostingRole.driver;
    final label = isDriver ? 'Posting as driver' : 'Posting as passenger';
    final status = canScheduleAsDriver
        ? (isDriver ? 'Driver ready' : 'Passenger mode')
        : 'Driver setup';

    return CoolCard(
      onTap: onOpenRoleSheet,
      semanticsLabel: '$label. Tap to switch role.',
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Row(
        children: [
          Icon(
            isDriver ? Icons.directions_car_rounded : Icons.person_rounded,
            size: 20,
            color: colors.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.swap_horiz_rounded, size: 20, color: colors.tertiaryText),
        ],
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final isDriverPosting = postingRole == ScheduleTripPostingRole.driver;

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isDriverPosting ? 'Driver trip' : 'Passenger trip',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isDriverPosting ? 'Set route and seats.' : 'Set route and timing.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
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
                    ? 'Driver ready'
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final routeLabel = fromLabel.isEmpty || toLabel.isEmpty
        ? 'Add route first.'
        : '$fromLabel → $toLabel';
    final vehicleLabel = switch (vehiclePreference) {
      TripVehiclePreference.any => 'Any',
      TripVehiclePreference.cab => 'Cab',
      TripVehiclePreference.moto => 'Moto',
      TripVehiclePreference.trike => 'Trike',
      TripVehiclePreference.truck => 'Truck',
      TripVehiclePreference.others => 'Others',
    };

    return CoolCard(
      backgroundColor: colors.routeSurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip review',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            routeLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
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
              _ScheduleSurfaceMetric(label: 'Vehicle', value: vehicleLabel),
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.chipSelectedBackground
            : colors.chipBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: highlighted ? colors.accent : colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: highlighted ? colors.accent : colors.secondaryText,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;

    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.tertiaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
