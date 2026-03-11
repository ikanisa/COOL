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
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';

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
            ? 'Google route preview is not available yet. Your coordinates will still be attached.'
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
            'The route preview could not be loaded right now. You can still post the trip with the pinned coordinates.';
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
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: backgroundColor,
          content: Text(
            message,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      );
  }

  Future<void> _openPlaceSearch({required bool isOrigin}) async {
    final result = await showModalBottomSheet<PlaceSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _PlaceSearchSheet(
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
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);
    DateTime? returnAt;

    if (_returnTrip) {
      returnAt = _combineDateAndTime(_returnDate, _returnTime);
      if (!returnAt.isAfter(departureAt)) {
        _showSnackBar(
          message: l10n.scheduleTripReturnInvalidError,
          backgroundColor: AppColors.red,
          textColor: Colors.white,
        );
        return;
      }
    }

    if (_recurringTrip && _recurringDays.isEmpty) {
      _showSnackBar(
        message: l10n.scheduleTripRecurringDaysError,
        backgroundColor: AppColors.red,
        textColor: Colors.white,
      );
      return;
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
                      _InfoBanner(message: l10n.scheduleTripInfoBanner),
                      const SizedBox(height: 18),
                      CoolCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.scheduleTripDetailsTitle,
                              style: GoogleFonts.dmSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.text,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _RouteEditor(
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
                                  : 'Tap search or use current location to attach pickup coordinates.',
                              toHintText: _toSelection != null
                                  ? 'Destination coordinates attached.'
                                  : 'Search for a destination to attach route coordinates.',
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
                      const SizedBox(height: 12),
                      _LocationAttachmentCard(
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
                      const SizedBox(height: 18),
                      _FieldLabel(label: l10n.scheduleTripDateTimeLabel),
                      const SizedBox(height: 8),
                      _AdaptiveFieldPair(
                        first: _PickerField(
                          prefix: l10n.scheduleTripDateFieldPrefix,
                          value: _formatDate(_selectedDate),
                          onTap: _pickDate,
                        ),
                        second: _PickerField(
                          prefix: l10n.scheduleTripTimeFieldPrefix,
                          value: _formatTime(_selectedTime),
                          onTap: _pickTime,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(label: l10n.scheduleTripVehicleLabel),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final option in _vehicleOptions(context))
                            _SelectionChip(
                              label: option.label,
                              selected: _vehiclePreference == option.value,
                              onTap: () {
                                setState(
                                  () => _vehiclePreference = option.value,
                                );
                                unawaited(_refreshRoutePreview());
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(label: l10n.scheduleTripSeatsLabel),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final seat in _seatOptions)
                            _SeatChip(
                              label: seat >= 3 ? '3+' : '$seat',
                              selected: _seats == seat,
                              onTap: () => setState(() => _seats = seat),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _ToggleCard(
                        emoji: '🔁',
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                      label: l10n.scheduleTripReturnFieldsLabel,
                                    ),
                                    const SizedBox(height: 8),
                                    _AdaptiveFieldPair(
                                      first: _PickerField(
                                        prefix:
                                            l10n.scheduleTripDateFieldPrefix,
                                        value: _formatDate(_returnDate),
                                        onTap: () => _pickDate(isReturn: true),
                                      ),
                                      second: _PickerField(
                                        prefix:
                                            l10n.scheduleTripTimeFieldPrefix,
                                        value: _formatTime(_returnTime),
                                        onTap: () => _pickTime(isReturn: true),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      _ToggleCard(
                        emoji: '🔄',
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _FieldLabel(
                                      label:
                                          l10n.scheduleTripRecurringDaysLabel,
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final option in _dayOptions(
                                          context,
                                        ))
                                          _DayChip(
                                            label: option.label,
                                            selected: _recurringDays.contains(
                                              option.day,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                if (_recurringDays.contains(
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
                      const SizedBox(height: 18),
                      CoolCard(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('⏰', style: TextStyle(fontSize: 20)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 18),
                      _FieldLabel(label: 'Price Note (optional)'),
                      const SizedBox(height: 8),
                      CoolCard(
                        child: TextFormField(
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
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      CoolButton(
                        label: l10n.scheduleTripPostCta,
                        onTap: _submit,
                        isLoading: isSubmitting,
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

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accentGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.accent,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationAttachmentCard extends StatelessWidget {
  const _LocationAttachmentCard({
    required this.locationState,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final MobilityLocationState locationState;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    late final String emoji;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        emoji = '📍';
        title = 'Current location is ready';
        subtitle = locationState.isApproximate
            ? 'Use it to fill the pickup field with an approximate current area.'
            : 'Use it to fill the pickup field or bias place search around you.';
        break;
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        emoji = '📡';
        title = 'Checking current location';
        subtitle =
            'If a location fix is available, you can use it for pickup and nearby search.';
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        emoji = '📍';
        title = 'Allow location to improve nearby matching';
        subtitle =
            'You can still post with text only, but nearby riders and drivers will not match as accurately.';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        emoji = '⚙️';
        title = 'Location access is blocked';
        subtitle =
            'Open app settings to use current location for pickup or nearby search.';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        emoji = '🛰️';
        title = 'Turn on device location';
        subtitle =
            'Location services are off, so current-location pickup cannot be used.';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.error:
        emoji = '⚠️';
        title = 'Location could not be attached';
        subtitle =
            locationState.error ??
            'The trip can still be posted, but current-location pickup is unavailable.';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text2,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && action != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 160,
                    child: CoolButton(
                      label: actionLabel,
                      variant: CoolButtonVariant.secondary,
                      onTap: action,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.dmSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.text2,
      ),
    );
  }
}

class _AdaptiveFieldPair extends StatelessWidget {
  const _AdaptiveFieldPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }

        return Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _RouteEditor extends StatelessWidget {
  const _RouteEditor({
    required this.fromController,
    required this.toController,
    required this.fromHint,
    required this.toHint,
    required this.fromValidator,
    required this.toValidator,
    required this.fromHintText,
    required this.toHintText,
    this.onFromSearchTap,
    this.onToSearchTap,
    this.onUseCurrentLocationTap,
    this.isResolvingCurrentLocation = false,
    this.fromResolved = false,
    this.toResolved = false,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final String fromHint;
  final String toHint;
  final String? Function(String?) fromValidator;
  final String? Function(String?) toValidator;
  final String fromHintText;
  final String toHintText;
  final VoidCallback? onFromSearchTap;
  final VoidCallback? onToSearchTap;
  final VoidCallback? onUseCurrentLocationTap;
  final bool isResolvingCurrentLocation;
  final bool fromResolved;
  final bool toResolved;

  @override
  Widget build(BuildContext context) {
    final fields = Column(
      children: [
        _RouteField(
          controller: fromController,
          hint: fromHint,
          onSearchTap: onFromSearchTap,
          onUseCurrentLocationTap: onUseCurrentLocationTap,
          isResolvingCurrentLocation: isResolvingCurrentLocation,
          isResolved: fromResolved,
          validator: fromValidator,
        ),
        const SizedBox(height: 6),
        _RouteResolutionHint(text: fromHintText, highlighted: fromResolved),
        const SizedBox(height: 10),
        _RouteField(
          controller: toController,
          hint: toHint,
          textInputAction: TextInputAction.done,
          onSearchTap: onToSearchTap,
          isResolved: toResolved,
          validator: toValidator,
        ),
        const SizedBox(height: 6),
        _RouteResolutionHint(text: toHintText, highlighted: toResolved),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  _RouteDot(color: AppColors.accent),
                  SizedBox(width: 8),
                  _RouteDash(axis: Axis.horizontal),
                  SizedBox(width: 8),
                  _RouteDot(color: AppColors.orange),
                ],
              ),
              const SizedBox(height: 12),
              fields,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: const [
                  _RouteDot(color: AppColors.accent),
                  _RouteDash(),
                  _RouteDot(color: AppColors.orange),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: fields),
          ],
        );
      },
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _RouteDash extends StatelessWidget {
  const _RouteDash({this.axis = Axis.vertical});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (axis == Axis.horizontal) {
      return SizedBox(
        width: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List<Widget>.generate(
            5,
            (_) => Container(
              width: 4,
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.text3,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List<Widget>.generate(
          5,
          (_) => Container(
            width: 2,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.text3,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteField extends StatelessWidget {
  const _RouteField({
    required this.controller,
    required this.hint,
    required this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSearchTap,
    this.onUseCurrentLocationTap,
    this.isResolvingCurrentLocation = false,
    this.isResolved = false,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final VoidCallback? onSearchTap;
  final VoidCallback? onUseCurrentLocationTap;
  final bool isResolvingCurrentLocation;
  final bool isResolved;

  @override
  Widget build(BuildContext context) {
    final suffixIcons = <Widget>[
      if (onUseCurrentLocationTap != null)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: isResolvingCurrentLocation
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : _RouteActionIcon(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Use current location',
                  onTap: onUseCurrentLocationTap!,
                ),
        ),
      if (onSearchTap != null)
        _RouteActionIcon(
          icon: Icons.search_rounded,
          tooltip: 'Search places',
          onTap: onSearchTap!,
        ),
      if (isResolved)
        const Padding(
          padding: EdgeInsets.only(left: 6, right: 4),
          child: Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: AppColors.accent,
          ),
        ),
    ];

    return TextFormField(
      controller: controller,
      validator: validator,
      textInputAction: textInputAction,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      ),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.text3,
        ),
        filled: true,
        fillColor: AppColors.surface3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: suffixIcons.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: suffixIcons,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.red, width: 1.2),
        ),
      ),
    );
  }
}

class _RouteActionIcon extends StatelessWidget {
  const _RouteActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: AppColors.text2),
        ),
      ),
    );
  }
}

class _RouteResolutionHint extends StatelessWidget {
  const _RouteResolutionHint({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            highlighted ? Icons.check_circle_rounded : Icons.place_outlined,
            size: 14,
            color: highlighted ? AppColors.accent : AppColors.text3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: highlighted ? AppColors.accent : AppColors.text2,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({
    required this.title,
    required this.initialQuery,
    required this.service,
    required this.languageTag,
    this.near,
  });

  final String title;
  final String initialQuery;
  final PlaceSearchService service;
  final GeoPoint? near;
  final String languageTag;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  late final TextEditingController _controller;
  late final String _sessionToken;
  Timer? _searchDebounce;
  List<PlaceSearchResult> _results = const <PlaceSearchResult>[];
  bool _isSearching = false;
  bool _isResolvingSelection = false;
  bool _hasSearched = false;
  String? _error;
  String? _resolvingPlaceId;

  @override
  void initState() {
    super.initState();
    _sessionToken =
        'cool_${DateTime.now().microsecondsSinceEpoch}_${identityHashCode(this)}';
    _controller = TextEditingController(text: widget.initialQuery);
    _controller.addListener(_handleQueryChanged);
    if (widget.initialQuery.trim().length >= 3) {
      Future<void>.microtask(_search);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _controller.removeListener(_handleQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    _searchDebounce?.cancel();

    final query = _controller.text.trim();
    if (query.length < 3) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const <PlaceSearchResult>[];
        _isSearching = false;
        _error = null;
        _hasSearched = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 320), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 3) {
      setState(() {
        _hasSearched = true;
        _results = const <PlaceSearchResult>[];
        _error = 'Enter at least 3 characters to search.';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _error = null;
    });

    try {
      final results = await widget.service.searchPlaces(
        query,
        near: widget.near,
        languageTag: widget.languageTag,
        sessionToken: _sessionToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const <PlaceSearchResult>[];
        _error =
            'Place search is unavailable right now. Try again in a moment.';
      });
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _selectPrediction(PlaceSearchResult prediction) async {
    setState(() {
      _isResolvingSelection = true;
      _resolvingPlaceId = prediction.placeId;
      _error = null;
    });

    try {
      final resolved = await widget.service.resolvePlace(
        prediction,
        languageTag: widget.languageTag,
        sessionToken: _sessionToken,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(resolved);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isResolvingSelection = false;
        _resolvingPlaceId = null;
        _error =
            'That place could not be resolved precisely. Try another result or keep the text only.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (viewportHeight * 0.78).clamp(360.0, 680.0);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: sheetHeight,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Autocomplete starts after a short pause. Details are only loaded when you pick a result.',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _PlaceSearchControls(
                    controller: _controller,
                    isSearching: _isSearching,
                    onSubmitted: _search,
                    onSearchTap: _search,
                  ),
                  const SizedBox(height: 14),
                  if (_results.isNotEmpty) ...[
                    Text(
                      '${_results.length} places found',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text3,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Expanded(child: _buildResults()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching && _results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    }

    if (_error != null) {
      return _PlaceSearchEmptyState(message: _error!);
    }

    if (_results.isEmpty) {
      if (!_hasSearched) {
        return const _PlaceSearchEmptyState(
          message: 'Search for a place to attach exact route coordinates.',
        );
      }
      return const _PlaceSearchEmptyState(
        message: 'No matching places found. Try a nearby landmark or district.',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final result = _results[index];
        return Material(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _isResolvingSelection
                ? null
                : () => _selectPrediction(result),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentGlow,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.place_rounded,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.primaryText ?? result.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        if (result.secondaryText != null &&
                            result.secondaryText!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            result.secondaryText!,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: AppColors.text2,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_isResolvingSelection &&
                      _resolvingPlaceId == result.placeId)
                    const Padding(
                      padding: EdgeInsets.only(left: 12, top: 4),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlaceSearchEmptyState extends StatelessWidget {
  const _PlaceSearchEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _PlaceSearchControls extends StatelessWidget {
  const _PlaceSearchControls({
    required this.controller,
    required this.isSearching,
    required this.onSubmitted,
    required this.onSearchTap,
  });

  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSubmitted;
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSubmitted(),
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.text,
      ),
      decoration: InputDecoration(
        hintText: 'Type a landmark, neighborhood, or address',
        hintStyle: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.text3,
        ),
        filled: true,
        fillColor: AppColors.surface3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
        ),
      ),
    );

    final button = CoolButton(
      label: 'Search',
      fullWidth: false,
      isLoading: isSearching,
      onTap: onSearchTap,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            children: [
              field,
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: button),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            SizedBox(width: 110, child: button),
          ],
        );
      },
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.prefix,
    required this.value,
    required this.onTap,
  });

  final String prefix;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Text(prefix, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface3,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.text2,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              activeTrackColor: AppColors.accent,
              activeThumbColor: Colors.black,
              inactiveTrackColor: AppColors.surface2,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionChip extends StatelessWidget {
  const _SelectionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentGlow : AppColors.surface2,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accent : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeatChip extends StatelessWidget {
  const _SeatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentGlow : AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.accent : AppColors.text2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentGlow : AppColors.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 44,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accent : AppColors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

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
