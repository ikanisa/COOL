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
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/intl_locale.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/driver_provider.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/schedule_trip_place_search_sheet.dart';
import '../widgets/schedule_trip_shared.dart';
import '../widgets/schedule_trip_step_widgets.dart';
import '../../../shared/widgets/cool_toast.dart';

part 'schedule_trip_screen_logic.dart';
part '../widgets/schedule_trip_role_card.dart';

enum ScheduleTripPostingRole { passenger, driver }

class ScheduleTripScreen extends ConsumerStatefulWidget {
  const ScheduleTripScreen({super.key});

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

    _postingRole = _initialPostingRoleFromRoute();
    _didResolveInitialRole = true;
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSubmitting = ref.watch(mobilitySubmissionLoadingProvider);
    final locationState = ref.watch(mobilityLocationProvider);
    final currentUser = ref.watch(currentUserProvider);
    final driverProfile = ref.watch(
      driverProvider.select((state) => state.profile),
    );
    final hasDriverRole =
        (currentUser?.isDriver ?? false) || driverProfile != null;
    final canScheduleAsDriver = _canScheduleAsDriver(
      hasDriverRole: hasDriverRole,
      vehicleType: driverProfile?.vehicleType ?? currentUser?.vehicleType,
    );
    final isDriverPosting = _postingRole == ScheduleTripPostingRole.driver;
    final vehicleOptions = buildVehicleOptions(context);
    final dayOptions = buildDayOptions(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          l10n.scheduleTripTitle,
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ScheduleTripRoleCard(
                        selectedRole: _postingRole,
                        canScheduleAsDriver: canScheduleAsDriver,
                        onSelectRole: (role) {
                          setState(() => _postingRole = role);
                        },
                        onOpenDriverSetup: () =>
                            context.push(AppRoutes.mobilityDriver),
                      ),
                      const SizedBox(height: 18),
                      ScheduleTripStepper(activeStep: _activeStep),
                      const SizedBox(height: 18),
                      if (_activeStep == ScheduleTripStep.route)
                        ScheduleTripRouteStep(
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
                          onFromSearchTap: () =>
                              _openPlaceSearch(isOrigin: true),
                          onToSearchTap: () =>
                              _openPlaceSearch(isOrigin: false),
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
                          onBack: _goToPreviousStep,
                          onContinue: () => unawaited(_goToNextStep()),
                        ),
                      if (_activeStep == ScheduleTripStep.review)
                        ScheduleTripReviewStep(
                          roleLabel: isDriverPosting ? 'Driver' : 'Passenger',
                          fromText: _fromController.text.trim(),
                          toText: _toController.text.trim(),
                          departureLabel:
                              '${_formatDate(_selectedDate)} · ${_formatTime(_selectedTime)}',
                          vehicleLabel: vehicleOptions
                              .firstWhere(
                                (option) => option.value == _vehiclePreference,
                              )
                              .label,
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
                          detailsLabel: _priceNoteController.text.trim().isEmpty
                              ? 'No extra note'
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
                          onSubmit: () =>
                              _submit(canScheduleAsDriver: canScheduleAsDriver),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
