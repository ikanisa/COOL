// ignore_for_file: unused_element, unused_element_parameter

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
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/cool_palette.dart';
import '../../../core/utils/intl_locale.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/schedule_trip_place_search_sheet.dart';
import '../widgets/schedule_trip_shared.dart';
import '../widgets/schedule_trip_step_widgets.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';

part 'schedule_trip_screen_logic.dart';
part '../widgets/schedule_trip_role_card.dart';

enum ScheduleTripPostingRole { passenger, driver }

enum _ScheduleTripToastKind { info, success, error }

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
  bool _returnTrip = false;
  bool _recurringTrip = false;
  late DateTime _returnDate;
  TimeOfDay _returnTime = const TimeOfDay(hour: 17, minute: 0);
  final Set<TripWeekday> _recurringDays = <TripWeekday>{};
  PlaceSearchResult? _fromSelection;
  PlaceSearchResult? _toSelection;
  bool _resolvingCurrentLocation = false;
  bool _resolvingTypedRoute = false;
  MobilityRoutePreview? _routePreview;
  bool _loadingRoutePreview = false;
  String? _routePreviewError;
  int _routePreviewRequestId = 0;
  ScheduleTripStep _activeStep = ScheduleTripStep.route;
  ScheduleTripPostingRole _postingRole = ScheduleTripPostingRole.passenger;
  bool _showAdditionalDetails = false;
  bool _didResolveInitialRole = false;

  String get _stepTitle {
    final isDriverPosting = _postingRole == ScheduleTripPostingRole.driver;
    return switch (_activeStep) {
      ScheduleTripStep.route =>
        isDriverPosting ? 'Set your return route' : 'Set your route',
      ScheduleTripStep.timing =>
        isDriverPosting ? 'Set departure timing' : 'Choose departure timing',
      ScheduleTripStep.options =>
        isDriverPosting ? 'Confirm driver setup' : 'Pick ride options',
      ScheduleTripStep.review =>
        isDriverPosting ? 'Review driver trip' : 'Review and post',
    };
  }

  String get _stepSubtitle {
    final isDriverPosting = _postingRole == ScheduleTripPostingRole.driver;
    return switch (_activeStep) {
      ScheduleTripStep.route =>
        isDriverPosting
            ? 'Set where you are leaving from and where riders are headed.'
            : 'Start with pickup and destination.',
      ScheduleTripStep.timing =>
        isDriverPosting
            ? 'Set departure first. Repeat only if this route happens often.'
            : 'Add return or repeat only if needed.',
      ScheduleTripStep.options =>
        isDriverPosting
            ? 'Use your driver setup defaults and only adjust what matters.'
            : 'Keep trip preferences short and practical.',
      ScheduleTripStep.review =>
        isDriverPosting
            ? 'Confirm the driver-facing trip before posting.'
            : 'Check the essentials before posting.',
    };
  }

  String get _stepContextLabel {
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    if (from.isNotEmpty && to.isNotEmpty) {
      return '$from → $to';
    }
    return _postingRole == ScheduleTripPostingRole.driver
        ? 'Posting as driver'
        : 'Posting as passenger';
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().add(const Duration(days: 1));
    _returnDate = _selectedDate;
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
    final vehicleOptions = buildVehicleOptions(context);
    final dayOptions = buildDayOptions(context);
    final selectedVehicleLabel =
        isDriverPosting && (driverVehicleType?.trim().isNotEmpty ?? false)
        ? driverVehicleType!.trim()
        : vehicleOptions
              .firstWhere((option) => option.value == _vehiclePreference)
              .label;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: Icon(Icons.arrow_back_rounded, color: palette.text),
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      l10n.scheduleTripTitle,
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 96),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _ScheduleTripProgressCard(
                        activeStep: _activeStep,
                        stepTitle: _stepTitle,
                        stepSubtitle: _stepSubtitle,
                        contextLabel: _stepContextLabel,
                        selectedRole: _postingRole,
                        canScheduleAsDriver: canScheduleAsDriver,
                        onOpenRoleSheet: () =>
                            unawaited(_openRoleSheet(canScheduleAsDriver)),
                        onOpenDriverSetup: () =>
                            context.push(AppRoutes.mobilityDriver),
                      ),
                      const SizedBox(height: 24),
                      if (_activeStep == ScheduleTripStep.route)
                        ScheduleTripRouteStep(
                            isDriverPosting: isDriverPosting,
                            fromController: _fromController,
                            toController: _toController,
                            fromSelection: _fromSelection,
                            toSelection: _toSelection,
                            isResolvingCurrentLocation:
                                _resolvingCurrentLocation,
                            routePreview: _routePreview,
                            loadingRoutePreview: _loadingRoutePreview,
                            resolvingTypedRoute: _resolvingTypedRoute,
                            routePreviewError: _routePreviewError,
                            locationState: locationState,
                            shouldShowLocationCard:
                                _shouldShowLocationAttachmentCard(
                                  locationState,
                                ),
                            onFromSearchTap: () =>
                                _openPlaceSearch(isOrigin: true),
                            onToSearchTap: () =>
                                _openPlaceSearch(isOrigin: false),
                            onUseCurrentLocationTap:
                                _useCurrentLocationForPickup,
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
                            onContinue: () => unawaited(_goToNextStep()),
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
                        if (_activeStep == ScheduleTripStep.timing)
                          ScheduleTripTimingStep(
                            isDriverPosting: isDriverPosting,
                            selectedDate: _selectedDate,
                            selectedTime: _selectedTime,
                            returnTrip: _returnTrip,
                            returnDate: _returnDate,
                            returnTime: _returnTime,
                            recurringTrip: _recurringTrip,
                            recurringDays: _recurringDays,
                            formatDate: _formatDate,
                            formatTime: _formatTime,
                            onPickDate: _pickDate,
                            onPickTime: _pickTime,
                            onPickReturnDate: () => _pickDate(isReturn: true),
                            onPickReturnTime: () => _pickTime(isReturn: true),
                            onReturnTripToggled: (value) {
                              setState(() {
                                _returnTrip = value;
                                if (value) _returnDate = _selectedDate;
                              });
                            },
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
                            onBack: _goToPreviousStep,
                            onContinue: () => unawaited(_goToNextStep()),
                          ),
                        if (_activeStep == ScheduleTripStep.options)
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
                                _showAdditionalDetails =
                                    !_showAdditionalDetails;
                              });
                            },
                            onBack: _goToPreviousStep,
                            onContinue: () => unawaited(_goToNextStep()),
                          ),
                        if (_activeStep == ScheduleTripStep.review)
                          ScheduleTripReviewStep(
                            title: isDriverPosting
                                ? 'Ready to post your driver return?'
                                : 'Review',
                            subtitle: isDriverPosting
                                ? 'Riders will see this route with your driver setup once you post it.'
                                : 'Check the main trip details before posting.',
                            postingGuideTitle:
                                l10n.scheduleTripPostingGuideTitle,
                            postingGuideSubtitle:
                                l10n.scheduleTripPostingGuideSubtitle,
                            roleFieldLabel: isDriverPosting
                                ? 'Trip type'
                                : 'Role',
                            seatsFieldLabel: isDriverPosting
                                ? 'Seats available'
                                : 'Seats',
                            detailsFieldLabel: isDriverPosting
                                ? 'Rider note'
                                : 'Details',
                            roleLabel: isDriverPosting
                                ? 'Driver return'
                                : 'Passenger',
                            visibilityValue: isDriverPosting
                                ? l10n.scheduleTripPostingDriverVisibility
                                : l10n.scheduleTripPostingPassengerVisibility,
                            precisionValue:
                                _fromSelection != null && _toSelection != null
                                ? l10n.scheduleTripPostingPrecisionExact
                                : _fromSelection != null || _toSelection != null
                                ? l10n.scheduleTripPostingPrecisionPartial
                                : l10n.scheduleTripPostingPrecisionTextOnly,
                            coordinationValue: isDriverPosting
                                ? l10n.scheduleTripPostingDriverCoordination
                                : l10n.scheduleTripPostingPassengerCoordination,
                            offlineValue:
                                l10n.scheduleTripPostingOfflineBehavior,
                            fromText: _fromController.text.trim(),
                            toText: _toController.text.trim(),
                            departureLabel:
                                '${_formatDate(_selectedDate)} · ${_formatTime(_selectedTime)}',
                            vehicleLabel: selectedVehicleLabel,
                            seatsLabel: _seats >= 3 ? '3+' : '$_seats',
                            returnLabel: _returnTrip
                                ? '${_formatDate(_returnDate)} · ${_formatTime(_returnTime)}'
                                : 'No return trip',
                            recurringLabel: _recurringTrip
                                ? dayOptions
                                      .where(
                                        (option) =>
                                            _recurringDays.contains(option.day),
                                      )
                                      .map((option) => option.label)
                                      .join(', ')
                                : 'One-time trip',
                            detailsLabel:
                                _priceNoteController.text.trim().isEmpty
                                ? (isDriverPosting
                                      ? 'No rider note'
                                      : 'No extra note')
                                : _priceNoteController.text.trim(),
                            previewLabel: _routePreview != null
                                ? '${_routePreview!.distanceLabel} · ${_routePreview!.durationLabel}'
                                : _fromSelection != null && _toSelection != null
                                ? 'Google pins attached · route preview unavailable'
                                : _fromSelection != null || _toSelection != null
                                ? 'Partial Google pinning attached'
                                : 'Text route only',
                            isSubmitting: isSubmitting,
                            submitLabel: l10n.scheduleTripPostCta,
                            onBack: _goToPreviousStep,
                            onSubmit: () => _submit(
                              canScheduleAsDriver: canScheduleAsDriver,
                            ),
                          ),
                      ],
                    ),
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
