// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';

import 'package:cool_app/core/models/geo_point.dart';
import 'package:cool_app/features/mobility/models/mobility_route_preview.dart';
import 'package:cool_app/features/mobility/models/trip_post_request.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/status/cool_status_awarder.dart';
import '../../../core/status/models/cool_event.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/mobility_location_provider.dart';
import '../providers/mobility_provider.dart';
import '../services/place_search_service.dart';
import '../widgets/schedule_trip_map_preview.dart';
import '../widgets/schedule_trip_place_search_sheet.dart';
import '../widgets/schedule_trip_review_card.dart';
import '../widgets/schedule_trip_route_widgets.dart';
import '../widgets/schedule_trip_shared.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_toast.dart';

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
  MobilityRoutePreview? _routePreview;
  bool _loadingRoutePreview = false;
  String? _routePreviewError;
  int _routePreviewRequestId = 0;
  ScheduleTripStep _activeStep = ScheduleTripStep.route;
  bool _showAdditionalDetails = false;

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
      if (!mounted) {
        return;
      }
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
            languageTag: Localizations.localeOf(context).toLanguageTag(),
            travelMode: _selectedTravelMode(),
          );
      if (!mounted || requestId != _routePreviewRequestId) {
        return;
      }

      setState(() {
        _routePreview = preview;
        _loadingRoutePreview = false;
        _routePreviewError = preview == null
            ? 'Route preview unavailable. Coordinates still attached.'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _routePreviewRequestId) {
        return;
      }

      setState(() {
        _loadingRoutePreview = false;
        _routePreview = null;
        _routePreviewError =
            'Route preview failed. You can still post with pinned coordinates.';
      });
    }
  }

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

  DateTime _combineDateAndTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _formatDate(DateTime date) {
    final localeName = Localizations.localeOf(context).toLanguageTag();
    return DateFormat('EEE, d MMM', localeName).format(date);
  }

  String _formatTime(TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(time);
  }

  List<_VehicleOption> _vehicleOptions(BuildContext context) {
    final l10n = context.l10n;
    return <_VehicleOption>[
      _VehicleOption(
        value: TripVehiclePreference.moto,
        label: l10n.vehicleMoto,
      ),
      _VehicleOption(value: TripVehiclePreference.cab, label: l10n.vehicleCab),
      _VehicleOption(value: TripVehiclePreference.any, label: l10n.vehicleAny),
    ];
  }

  List<_DayOption> _dayOptions(BuildContext context) {
    final l10n = context.l10n;
    return <_DayOption>[
      _DayOption(day: TripWeekday.mon, label: l10n.weekdayMonShort),
      _DayOption(day: TripWeekday.tue, label: l10n.weekdayTueShort),
      _DayOption(day: TripWeekday.wed, label: l10n.weekdayWedShort),
      _DayOption(day: TripWeekday.thu, label: l10n.weekdayThuShort),
      _DayOption(day: TripWeekday.fri, label: l10n.weekdayFriShort),
      _DayOption(day: TripWeekday.sat, label: l10n.weekdaySatShort),
      _DayOption(day: TripWeekday.sun, label: l10n.weekdaySunShort),
    ];
  }

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

  int get _activeStepIndex => ScheduleTripStep.values.indexOf(_activeStep);

  bool _shouldShowLocationAttachmentCard(MobilityLocationState locationState) {
    return switch (locationState.status) {
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

    if (message == null) {
      return true;
    }

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

  void _goToPreviousStep() {
    if (_activeStepIndex == 0) {
      return;
    }
    setState(() {
      _activeStep = ScheduleTripStep.values[_activeStepIndex - 1];
    });
  }

  void _goToNextStep() {
    if (_activeStep == ScheduleTripStep.route) {
      final isValid = _formKey.currentState?.validate() ?? false;
      if (!_validateRouteStep() || !isValid) {
        return;
      }
    }
    if (_activeStep == ScheduleTripStep.timing && !_validateTimingStep()) {
      return;
    }
    if (_activeStepIndex >= ScheduleTripStep.values.length - 1) {
      return;
    }
    setState(() {
      _activeStep = ScheduleTripStep.values[_activeStepIndex + 1];
    });
  }

  Future<void> _openPlaceSearch({required bool isOrigin}) async {
    final result = await showModalBottomSheet<PlaceSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ScheduleTripPlaceSearchSheet(
          title: isOrigin ? 'Set pickup' : 'Set destination',
          initialQuery: isOrigin
              ? _fromController.text.trim()
              : _toController.text.trim(),
          service: ref.read(placeSearchServiceProvider),
          near: ref.read(mobilityLocationProvider).position,
          languageTag: Localizations.localeOf(context).toLanguageTag(),
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

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

  Future<void> _useCurrentLocationForPickup() async {
    if (_resolvingCurrentLocation) {
      return;
    }

    final languageTag = Localizations.localeOf(context).toLanguageTag();
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
      if (!mounted) {
        return;
      }

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
      if (!mounted) {
        return;
      }
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

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final tripRole = GoRouterState.of(
      context,
    ).uri.queryParameters['role']?.trim();
    final isDriverReturnTrip = tripRole?.toLowerCase() == 'driver';
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
      // Only navigate to the trip board if the trip was confirmed by the
      // server. Offline-stored trips won't appear there yet, so navigating
      // would show an empty list — a false-success UX.
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSubmitting = ref.watch(mobilitySubmissionLoadingProvider);
    final locationState = ref.watch(mobilityLocationProvider);

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
                      ScheduleTripStepper(activeStep: _activeStep),
                      const SizedBox(height: 18),
                      if (_activeStep == ScheduleTripStep.route) ...[
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pickup and destination',
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enter both stops. Search or use your current location only if you need it.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.text2,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ScheduleTripRouteEditor(
                                fromController: _fromController,
                                toController: _toController,
                                fromHint: l10n.scheduleTripFromHint,
                                toHint: l10n.scheduleTripToHint,
                                fromResolved: _fromSelection != null,
                                toResolved: _toSelection != null,
                                isResolvingCurrentLocation:
                                    _resolvingCurrentLocation,
                                onFromSearchTap: () {
                                  _openPlaceSearch(isOrigin: true);
                                },
                                onToSearchTap: () {
                                  _openPlaceSearch(isOrigin: false);
                                },
                                onUseCurrentLocationTap:
                                    _useCurrentLocationForPickup,
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
                                fromHintText: _fromSelection != null
                                    ? 'Pickup coordinates attached.'
                                    : 'Search or use current location.',
                                toHintText: _toSelection != null
                                    ? 'Destination coordinates attached.'
                                    : 'Search for a destination.',
                              ),
                            ],
                          ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child:
                              _fromSelection == null &&
                                  _toSelection == null &&
                                  !_loadingRoutePreview &&
                                  (_routePreviewError?.trim().isEmpty ?? true)
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: ScheduleTripMapPreview(
                                    originLabel:
                                        _fromSelection?.primaryText ??
                                        _fromController.text.trim(),
                                    destinationLabel:
                                        _toSelection?.primaryText ??
                                        _toController.text.trim(),
                                    origin: _fromSelection?.position,
                                    destination: _toSelection?.position,
                                    preview: _routePreview,
                                    isLoading: _loadingRoutePreview,
                                    error: _routePreviewError,
                                  ),
                                ),
                        ),
                        if (_shouldShowLocationAttachmentCard(
                          locationState,
                        )) ...[
                          const SizedBox(height: 12),
                          ScheduleTripLocationAttachmentCard(
                            locationState: locationState,
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
                          ),
                        ],
                        const SizedBox(height: 20),
                        ScheduleTripStepActionBar(
                          primaryLabel: 'Continue',
                          onPrimary: _goToNextStep,
                        ),
                      ],
                      if (_activeStep == ScheduleTripStep.timing) ...[
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'When',
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Set departure first. Add a return or repeat only if needed.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.text2,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ScheduleTripFieldLabel(
                                label: l10n.scheduleTripDateTimeLabel,
                              ),
                              const SizedBox(height: 8),
                              ScheduleTripAdaptiveFieldPair(
                                first: ScheduleTripPickerField(
                                  prefix: l10n.scheduleTripDateFieldPrefix,
                                  value: _formatDate(_selectedDate),
                                  onTap: _pickDate,
                                ),
                                second: ScheduleTripPickerField(
                                  prefix: l10n.scheduleTripTimeFieldPrefix,
                                  value: _formatTime(_selectedTime),
                                  onTap: _pickTime,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Return or repeat',
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ScheduleTripToggleCard(
                                icon: Icons.repeat_rounded,
                                title: l10n.scheduleTripReturnTitle,
                                subtitle: l10n.scheduleTripReturnSubtitle,
                                value: _returnTrip,
                                onChanged: (value) {
                                  setState(() {
                                    _returnTrip = value;
                                    if (value) {
                                      _returnDate = _selectedDate;
                                    }
                                  });
                                },
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                child: !_returnTrip
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ScheduleTripFieldLabel(
                                              label: l10n
                                                  .scheduleTripReturnFieldsLabel,
                                            ),
                                            const SizedBox(height: 8),
                                            ScheduleTripAdaptiveFieldPair(
                                              first: ScheduleTripPickerField(
                                                prefix: l10n
                                                    .scheduleTripDateFieldPrefix,
                                                value: _formatDate(_returnDate),
                                                onTap: () =>
                                                    _pickDate(isReturn: true),
                                              ),
                                              second: ScheduleTripPickerField(
                                                prefix: l10n
                                                    .scheduleTripTimeFieldPrefix,
                                                value: _formatTime(_returnTime),
                                                onTap: () =>
                                                    _pickTime(isReturn: true),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 12),
                              ScheduleTripToggleCard(
                                icon: Icons.sync_rounded,
                                title: l10n.scheduleTripRecurringTitle,
                                subtitle: l10n.scheduleTripRecurringSubtitle,
                                value: _recurringTrip,
                                onChanged: (value) {
                                  setState(() {
                                    _recurringTrip = value;
                                    if (!value) {
                                      _recurringDays.clear();
                                    }
                                  });
                                },
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                child: !_recurringTrip
                                    ? const SizedBox.shrink()
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ScheduleTripFieldLabel(
                                              label: l10n
                                                  .scheduleTripRecurringDaysLabel,
                                            ),
                                            const SizedBox(height: 8),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                for (final option
                                                    in _dayOptions(context))
                                                  ScheduleTripDayChip(
                                                    label: option.label,
                                                    selected: _recurringDays
                                                        .contains(option.day),
                                                    onTap: () {
                                                      setState(() {
                                                        if (_recurringDays
                                                            .contains(
                                                              option.day,
                                                            )) {
                                                          _recurringDays.remove(
                                                            option.day,
                                                          );
                                                        } else {
                                                          _recurringDays.add(
                                                            option.day,
                                                          );
                                                        }
                                                      });
                                                    },
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ScheduleTripStepActionBar(
                          showBack: true,
                          onBack: _goToPreviousStep,
                          primaryLabel: 'Continue',
                          onPrimary: _goToNextStep,
                        ),
                      ],
                      if (_activeStep == ScheduleTripStep.options) ...[
                        CoolCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trip setup',
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Choose the ride, seats, and any optional note.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.text2,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 16),
                              ScheduleTripFieldLabel(
                                label: l10n.scheduleTripVehicleLabel,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final option in _vehicleOptions(context))
                                    ScheduleTripSelectionChip(
                                      label: option.label,
                                      selected:
                                          _vehiclePreference == option.value,
                                      onTap: () {
                                        setState(
                                          () =>
                                              _vehiclePreference = option.value,
                                        );
                                        unawaited(_refreshRoutePreview());
                                      },
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              ScheduleTripFieldLabel(
                                label: l10n.scheduleTripSeatsLabel,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final seat in _seatOptions)
                                    ScheduleTripSeatChip(
                                      label: seat >= 3 ? '3+' : '$seat',
                                      selected: _seats == seat,
                                      onTap: () =>
                                          setState(() => _seats = seat),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Add details',
                                      style: GoogleFonts.dmSans(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.text,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showAdditionalDetails =
                                            !_showAdditionalDetails;
                                      });
                                    },
                                    child: Text(
                                      _showAdditionalDetails ? 'Hide' : 'Show',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Price notes and expiry are optional.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.text2,
                                  height: 1.4,
                                ),
                              ),
                              AnimatedCrossFade(
                                duration: const Duration(milliseconds: 220),
                                crossFadeState: _showAdditionalDetails
                                    ? CrossFadeState.showSecond
                                    : CrossFadeState.showFirst,
                                firstChild: const SizedBox(height: 12),
                                secondChild: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface2,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: AppColors.border2,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.schedule_rounded,
                                            size: 18,
                                            color: AppColors.text2,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  l10n.scheduleTripExpiryTitle,
                                                  style: GoogleFonts.dmSans(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.text,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  l10n.scheduleTripExpirySubtitle,
                                                  style: GoogleFonts.dmSans(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w400,
                                                    color: AppColors.text2,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    ScheduleTripFieldLabel(
                                      label: 'Price note (optional)',
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: _priceNoteController,
                                      style: GoogleFonts.dmSans(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.text,
                                      ),
                                      maxLength: 60,
                                      decoration: InputDecoration(
                                        hintText: 'e.g. 500 RWF · Negotiable',
                                        hintStyle: GoogleFonts.dmSans(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
                                          color: AppColors.text3,
                                        ),
                                        counterStyle: GoogleFonts.dmSans(
                                          fontSize: 11,
                                          color: AppColors.text3,
                                        ),
                                        filled: true,
                                        fillColor: AppColors.surface3,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: const BorderSide(
                                            color: AppColors.accent,
                                            width: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        ScheduleTripStepActionBar(
                          showBack: true,
                          onBack: _goToPreviousStep,
                          primaryLabel: 'Review',
                          onPrimary: _goToNextStep,
                        ),
                      ],
                      if (_activeStep == ScheduleTripStep.review) ...[
                        ScheduleTripReviewCard(
                          routeLabel:
                              '${_fromController.text.trim()} → ${_toController.text.trim()}',
                          departureLabel:
                              '${_formatDate(_selectedDate)} · ${_formatTime(_selectedTime)}',
                          vehicleLabel: _vehicleOptions(context)
                              .firstWhere(
                                (option) => option.value == _vehiclePreference,
                              )
                              .label,
                          seatsLabel: _seats >= 3 ? '3+' : '$_seats',
                          returnLabel: _returnTrip
                              ? '${_formatDate(_returnDate)} · ${_formatTime(_returnTime)}'
                              : 'No return trip',
                          recurringLabel: _recurringTrip
                              ? _dayOptions(context)
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
                          previewLabel: _routePreview == null
                              ? 'No live route preview'
                              : '${_routePreview!.distanceLabel} · ${_routePreview!.durationLabel}',
                        ),
                        const SizedBox(height: 20),
                        ScheduleTripStepActionBar(
                          showBack: true,
                          onBack: _goToPreviousStep,
                          primaryLabel: l10n.scheduleTripPostCta,
                          onPrimary: _submit,
                          isPrimaryLoading: isSubmitting,
                        ),
                      ],
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

// ── Data helpers ─────────────────────────────────────────────────

class _VehicleOption {
  const _VehicleOption({required this.value, required this.label});

  final TripVehiclePreference value;
  final String label;
}

class _DayOption {
  const _DayOption({required this.day, required this.label});

  final TripWeekday day;
  final String label;
}

const _seatOptions = <int>[1, 2, 3];
