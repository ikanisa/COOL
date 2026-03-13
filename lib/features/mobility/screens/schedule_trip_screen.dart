// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/router/app_router.dart';
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

enum ScheduleTripPostingRole { passenger, driver }

class ScheduleTripScreen extends ConsumerStatefulWidget {
  const ScheduleTripScreen({super.key});

  @override
  ConsumerState<ScheduleTripScreen> createState() => _ScheduleTripScreenState();
}

class _ScheduleTripScreenState extends ConsumerState<ScheduleTripScreen>
    with CoolStatusAwarder {
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

  // ── Sync & route preview ────────────────────────────────────────

  void _syncResolvedLocations() {
    final fromText = _fromController.text.trim();
    final toText = _toController.text.trim();
    var changed = false;

    if (_fromSelection != null && _fromSelection!.label != fromText) {
      _fromSelection = null;
      changed = true;
    }

    if (_toSelection != null && _toSelection!.label != toText) {
      _toSelection = null;
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
      unawaited(_refreshRoutePreview());
    }
  }

  MobilityRouteTravelMode _selectedTravelMode() {
    return switch (_vehiclePreference) {
      TripVehiclePreference.moto => MobilityRouteTravelMode.twoWheeler,
      TripVehiclePreference.cab ||
      TripVehiclePreference.any => MobilityRouteTravelMode.drive,
    };
  }

  Future<void> _refreshRoutePreview() async {
    final origin = _fromSelection?.position;
    final destination = _toSelection?.position;
    final requestId = ++_routePreviewRequestId;

    if (origin == null || destination == null) {
      if (!mounted) return;
      setState(() {
        _routePreview = null;
        _routePreviewError = null;
        _loadingRoutePreview = false;
      });
      return;
    }

    setState(() {
      _loadingRoutePreview = true;
      _routePreviewError = null;
    });

    try {
      final preview = await ref
          .read(placeSearchServiceProvider)
          .computeRoutePreview(
            origin: origin,
            destination: destination,
            languageTag: resolveIntlLocale(context),
            travelMode: _selectedTravelMode(),
          );
      if (!mounted || requestId != _routePreviewRequestId) return;

      setState(() {
        _routePreview = preview;
        _loadingRoutePreview = false;
        _routePreviewError = preview == null
            ? 'Route preview unavailable. Coordinates still attached.'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _routePreviewRequestId) return;

      setState(() {
        _loadingRoutePreview = false;
        _routePreview = null;
        _routePreviewError =
            'Route preview failed. You can still post with pinned coordinates.';
      });
    }
  }

  // ── Pickers ─────────────────────────────────────────────────────

  Future<void> _pickDate({bool isReturn = false}) async {
    final initialDate = isReturn ? _returnDate : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 120)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: Colors.black,
              surface: AppColors.surface,
              onSurface: AppColors.text,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isReturn) {
        _returnDate = picked;
      } else {
        _selectedDate = picked;
        if (_returnDate.isBefore(_selectedDate)) {
          _returnDate = _selectedDate;
        }
      }
    });
  }

  Future<void> _pickTime({bool isReturn = false}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isReturn ? _returnTime : _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accent,
              onPrimary: Colors.black,
              surface: AppColors.surface,
              onSurface: AppColors.text,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: AppColors.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isReturn) {
        _returnTime = picked;
      } else {
        _selectedTime = picked;
      }
    });
  }

  // ── Formatting helpers ──────────────────────────────────────────

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDate(DateTime date) {
    return safeDateFormat(
      'EEE, d MMM',
      locale: Localizations.maybeLocaleOf(context),
    ).format(date);
  }

  String _formatTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  // ── Toast helper ────────────────────────────────────────────────

  void _showSnackBar({
    required String message,
    required Color backgroundColor,
    required Color textColor,
  }) {
    if (backgroundColor == AppColors.red) {
      CoolToast.error(context, message);
    } else if (backgroundColor == AppColors.accent) {
      CoolToast.success(context, message);
    } else {
      CoolToast.info(context, message);
    }
  }

  // ── Location helpers ────────────────────────────────────────────

  int get _activeStepIndex => ScheduleTripStep.values.indexOf(_activeStep);

  bool _shouldShowLocationAttachmentCard(MobilityLocationState locationState) {
    return switch (locationState.status) {
      MobilityLocationStatus.accessDisabled ||
      MobilityLocationStatus.needsPermission ||
      MobilityLocationStatus.denied ||
      MobilityLocationStatus.deniedForever ||
      MobilityLocationStatus.serviceDisabled ||
      MobilityLocationStatus.error => true,
      MobilityLocationStatus.idle ||
      MobilityLocationStatus.checking ||
      MobilityLocationStatus.requesting ||
      MobilityLocationStatus.ready ||
      MobilityLocationStatus.approximateReady => false,
    };
  }

  // ── Validation ──────────────────────────────────────────────────

  bool _validateRouteStep() {
    final l10n = context.l10n;
    final from = _fromController.text.trim();
    final to = _toController.text.trim();

    String? message;
    if (from.isEmpty) {
      message = l10n.scheduleTripFromRequired;
    } else if (to.isEmpty) {
      message = l10n.scheduleTripToRequired;
    } else if (from == to) {
      message = l10n.scheduleTripRouteSameError;
    }

    if (message == null) return true;

    _showSnackBar(
      message: message,
      backgroundColor: AppColors.red,
      textColor: Colors.white,
    );
    return false;
  }

  bool _validateTimingStep() {
    final l10n = context.l10n;
    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);

    if (_returnTrip) {
      final returnAt = _combineDateAndTime(_returnDate, _returnTime);
      if (!returnAt.isAfter(departureAt)) {
        _showSnackBar(
          message: l10n.scheduleTripReturnInvalidError,
          backgroundColor: AppColors.red,
          textColor: Colors.white,
        );
        return false;
      }
    }

    if (_recurringTrip && _recurringDays.isEmpty) {
      _showSnackBar(
        message: l10n.scheduleTripRecurringDaysError,
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      );
      return false;
    }

    return true;
  }

  // ── Step navigation ─────────────────────────────────────────────

  void _goToPreviousStep() {
    if (_activeStepIndex == 0) return;
    setState(() {
      _activeStep = ScheduleTripStep.values[_activeStepIndex - 1];
    });
  }

  Future<void> _goToNextStep() async {
    if (_activeStep == ScheduleTripStep.route) {
      final isValid = _formKey.currentState?.validate() ?? false;
      if (!_validateRouteStep() || !isValid) return;
      await _resolveTypedRouteSelections();
    }
    if (_activeStep == ScheduleTripStep.timing && !_validateTimingStep()) {
      return;
    }
    if (_activeStepIndex >= ScheduleTripStep.values.length - 1) return;
    setState(() {
      _activeStep = ScheduleTripStep.values[_activeStepIndex + 1];
    });
  }

  // ── Place search & location ─────────────────────────────────────

  Future<void> _openPlaceSearch({required bool isOrigin}) async {
    final result = await showPlaceSearchSheet(
      context,
      title: isOrigin ? 'Set pickup' : 'Set destination',
      initialQuery: isOrigin
          ? _fromController.text.trim()
          : _toController.text.trim(),
      service: ref.read(placeSearchServiceProvider),
      near: ref.read(mobilityLocationProvider).position,
      languageTag: resolveIntlLocale(context),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (isOrigin) {
        _fromSelection = result;
        _fromController.text = result.label;
      } else {
        _toSelection = result;
        _toController.text = result.label;
      }
    });
    unawaited(_refreshRoutePreview());
  }

  Future<void> _resolveTypedRouteSelections() async {
    if (_resolvingTypedRoute) {
      return;
    }

    final pendingOrigins =
        _fromSelection == null && _fromController.text.trim().isNotEmpty;
    final pendingDestination =
        _toSelection == null && _toController.text.trim().isNotEmpty;
    if (!pendingOrigins && !pendingDestination) {
      return;
    }

    setState(() => _resolvingTypedRoute = true);
    final failedFields = <String>[];

    try {
      if (pendingOrigins) {
        final resolved = await ref
            .read(placeSearchServiceProvider)
            .geocodeQuery(
              _fromController.text.trim(),
              near: ref.read(mobilityLocationProvider).position,
              languageTag: resolveIntlLocale(context),
            );
        if (!mounted) {
          return;
        }
        if (resolved != null) {
          setState(() {
            _fromSelection = resolved;
            _fromController.text = resolved.label;
          });
        } else {
          failedFields.add('pickup');
        }
      }

      if (pendingDestination) {
        final resolved = await ref
            .read(placeSearchServiceProvider)
            .geocodeQuery(
              _toController.text.trim(),
              near: ref.read(mobilityLocationProvider).position,
              languageTag: resolveIntlLocale(context),
            );
        if (!mounted) {
          return;
        }
        if (resolved != null) {
          setState(() {
            _toSelection = resolved;
            _toController.text = resolved.label;
          });
        } else {
          failedFields.add('destination');
        }
      }

      unawaited(_refreshRoutePreview());
    } finally {
      if (mounted) {
        setState(() => _resolvingTypedRoute = false);
      }
    }

    if (failedFields.isNotEmpty && mounted) {
      _showSnackBar(
        message:
            'Google could not pin ${failedFields.join(' and ')} exactly. You can continue with text only, or use search to choose a place.',
        backgroundColor: AppColors.orange,
        textColor: Colors.black,
      );
    }
  }

  Future<void> _useCurrentLocationForPickup() async {
    if (_resolvingCurrentLocation) return;

    final languageTag = resolveIntlLocale(context);
    final locationNotifier = ref.read(mobilityLocationProvider.notifier);
    var locationState = ref.read(mobilityLocationProvider);
    if (!locationState.hasLocation) {
      await locationNotifier.requestForegroundAccess();
      locationState = ref.read(mobilityLocationProvider);
    }

    final position = locationState.position;
    if (position == null) {
      _showSnackBar(
        message:
            locationState.error ??
            'Current location is unavailable. Search for a place instead.',
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      );
      return;
    }

    setState(() => _resolvingCurrentLocation = true);
    try {
      final result = await ref
          .read(placeSearchServiceProvider)
          .reverseGeocode(
            latitude: position.latitude,
            longitude: position.longitude,
            languageTag: languageTag,
          );
      if (!mounted) return;

      final resolved =
          result ??
          PlaceSearchResult(
            label: _fallbackCoordinateLabel(position),
            position: position,
            primaryText: 'Current location',
          );

      setState(() {
        _fromSelection = resolved;
        _fromController.text = resolved.label;
      });
      unawaited(_refreshRoutePreview());
    } catch (_) {
      if (!mounted) return;
      final fallback = PlaceSearchResult(
        label: _fallbackCoordinateLabel(position),
        position: position,
        primaryText: 'Current location',
      );
      setState(() {
        _fromSelection = fallback;
        _fromController.text = fallback.label;
      });
      unawaited(_refreshRoutePreview());
      _showSnackBar(
        message:
            'Pickup coordinates were attached, but the address could not be resolved.',
        backgroundColor: AppColors.orange,
        textColor: Colors.black,
      );
    } finally {
      if (mounted) {
        setState(() => _resolvingCurrentLocation = false);
      }
    }
  }

  String _fallbackCoordinateLabel(GeoPoint position) {
    final lat = position.latitude.toStringAsFixed(5);
    final lng = position.longitude.toStringAsFixed(5);
    return 'Current location ($lat, $lng)';
  }

  ScheduleTripPostingRole _initialPostingRoleFromRoute() {
    try {
      final role = GoRouterState.of(
        context,
      ).uri.queryParameters['role']?.trim().toLowerCase();
      if (role == 'driver') {
        return ScheduleTripPostingRole.driver;
      }
    } catch (_) {
      // The screen is also mounted directly in widget tests.
    }
    return ScheduleTripPostingRole.passenger;
  }

  bool _canScheduleAsDriver({
    required bool hasDriverRole,
    required String? vehicleType,
  }) {
    return hasDriverRole || (vehicleType?.trim().isNotEmpty ?? false);
  }

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> _submit({required bool canScheduleAsDriver}) async {
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final isDriverReturnTrip = _postingRole == ScheduleTripPostingRole.driver;
    if (isDriverReturnTrip && !canScheduleAsDriver) {
      _showSnackBar(
        message: 'Finish driver setup before posting as a driver.',
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      );
      return;
    }
    final tripRole = isDriverReturnTrip ? 'DRIVER' : 'PASSENGER';
    if (!_validateRouteStep()) {
      setState(() => _activeStep = ScheduleTripStep.route);
      return;
    }
    if (!_validateTimingStep()) {
      setState(() => _activeStep = ScheduleTripStep.timing);
      return;
    }
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _activeStep = ScheduleTripStep.route);
      return;
    }

    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);
    DateTime? returnAt;

    if (_returnTrip) {
      returnAt = _combineDateAndTime(_returnDate, _returnTime);
    }

    final result = await ref
        .read(mobilityProvider.notifier)
        .createTrip(
          TripPostRequest(
            fromLocation: _fromController.text.trim(),
            toLocation: _toController.text.trim(),
            departureAt: departureAt,
            returnAt: returnAt,
            vehiclePreference: _vehiclePreference,
            seatsNeeded: _seats,
            recurringDays: _recurringTrip
                ? _recurringDays.toList(growable: false)
                : const [],
            role: tripRole,
            isDriverReturnTrip: isDriverReturnTrip,
            latitude: _fromSelection?.latitude,
            longitude: _fromSelection?.longitude,
            destinationLatitude: _toSelection?.latitude,
            destinationLongitude: _toSelection?.longitude,
            priceNote: _priceNoteController.text.trim().isEmpty
                ? null
                : _priceNoteController.text.trim(),
          ),
        );

    if (!mounted) return;

    if (result != null) {
      awardCoolPoints(
        ref,
        eventType: CoolEventType.tripPosted,
        sourceId: result.id,
        metadata: {
          'from': _fromController.text.trim(),
          'to': _toController.text.trim(),
        },
      );
      _showSnackBar(
        message: result.storedOffline
            ? l10n.scheduleTripPostedPendingSync
            : l10n.scheduleTripPostedSuccess,
        backgroundColor: AppColors.accent,
        textColor: Colors.black,
      );
      if (!result.storedOffline) {
        context.go('/mobility/trips');
      }
      return;
    }

    final error = ref.read(mobilitySubmissionErrorProvider);
    if (error != null) {
      _showSnackBar(
        message: error,
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      );
    }
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

class _ScheduleTripRoleCard extends StatelessWidget {
  const _ScheduleTripRoleCard({
    required this.selectedRole,
    required this.canScheduleAsDriver,
    required this.onSelectRole,
    required this.onOpenDriverSetup,
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;
  final ValueChanged<ScheduleTripPostingRole> onSelectRole;
  final VoidCallback onOpenDriverSetup;

  @override
  Widget build(BuildContext context) {
    final isDriverSelected = selectedRole == ScheduleTripPostingRole.driver;
    final summary = switch ((isDriverSelected, canScheduleAsDriver)) {
      (false, _) =>
        'Passenger is your default role. You can switch per trip whenever needed.',
      (true, true) =>
        'Driver trips are posted as return trips while you still keep passenger access.',
      (true, false) => 'Finish driver setup before posting a trip as a driver.',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule as',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ScheduleTripSelectionChip(
                label: 'Passenger',
                selected: selectedRole == ScheduleTripPostingRole.passenger,
                onTap: () => onSelectRole(ScheduleTripPostingRole.passenger),
              ),
              ScheduleTripSelectionChip(
                label: 'Driver',
                selected: isDriverSelected,
                onTap: () => onSelectRole(ScheduleTripPostingRole.driver),
              ),
            ],
          ),
          if (isDriverSelected && !canScheduleAsDriver) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onOpenDriverSetup,
              icon: const Icon(Icons.directions_car_outlined, size: 18),
              label: const Text('Become a driver'),
            ),
          ],
        ],
      ),
    );
  }
}
