part of 'schedule_trip_screen.dart';

extension on _ScheduleTripScreenState {
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
      _updateState(() {});
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
      _updateState(() {
        _routePreview = null;
        _routePreviewError = null;
        _loadingRoutePreview = false;
      });
      return;
    }

    _updateState(() {
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

      _updateState(() {
        _routePreview = preview;
        _loadingRoutePreview = false;
        _routePreviewError = preview == null
            ? 'Route data unavailable'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _routePreviewRequestId) return;

      _updateState(() {
        _loadingRoutePreview = false;
        _routePreview = null;
        _routePreviewError =
            'Route preview failed';
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
        final palette = context.coolPalette;
        final theme = Theme.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: theme.colorScheme.copyWith(
              brightness: theme.brightness,
              primary: palette.accent,
              onPrimary: theme.colorScheme.onPrimary,
              surface: palette.surface,
              onSurface: palette.text,
            ),
            dialogTheme: DialogThemeData(backgroundColor: palette.surface),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    _updateState(() {
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
        final palette = context.coolPalette;
        final theme = Theme.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: theme.colorScheme.copyWith(
              brightness: theme.brightness,
              primary: palette.accent,
              onPrimary: theme.colorScheme.onPrimary,
              surface: palette.surface,
              onSurface: palette.text,
            ),
            dialogTheme: DialogThemeData(backgroundColor: palette.surface),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    _updateState(() {
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
    required _ScheduleTripToastKind kind,
  }) {
    switch (kind) {
      case _ScheduleTripToastKind.info:
        CoolToast.info(context, message);
      case _ScheduleTripToastKind.success:
        CoolToast.success(context, message);
      case _ScheduleTripToastKind.error:
        CoolToast.error(context, message);
    }
  }

  // ── Location helpers ────────────────────────────────────────────



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

    _showSnackBar(message: message, kind: _ScheduleTripToastKind.error);
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
          kind: _ScheduleTripToastKind.error,
        );
        return false;
      }
    }

    if (_recurringTrip && _recurringDays.isEmpty) {
      _showSnackBar(
        message: l10n.scheduleTripRecurringDaysError,
        kind: _ScheduleTripToastKind.error,
      );
      return false;
    }

    return true;
  }

  // Step navigation removed — single-screen layout.
  // _activeStep kept for legacy compatibility (e.g. role card references).

  Future<void> _openRoleSheet(bool canScheduleAsDriver) async {
    final nextRole = await showModalBottomSheet<ScheduleTripPostingRole>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScheduleTripRoleSheet(
        selectedRole: _postingRole,
        canScheduleAsDriver: canScheduleAsDriver,
      ),
    );

    if (!mounted || nextRole == null || nextRole == _postingRole) {
      return;
    }

    final currentUser = ref.read(currentUserProvider);
    final driverProfile = ref.read(driverProvider).profile;
    _updateState(() {
      _postingRole = nextRole;
      _applyPostingRoleDefaults(
        role: nextRole,
        vehicleType: driverProfile?.vehicleType ?? currentUser?.vehicleType,
      );
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

    _updateState(() {
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

    _updateState(() => _resolvingTypedRoute = true);
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
          _updateState(() {
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
          _updateState(() {
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
        _updateState(() => _resolvingTypedRoute = false);
      }
    }

    if (failedFields.isNotEmpty && mounted) {
      _showSnackBar(
        message:
            'Could not pin exactly',
        kind: _ScheduleTripToastKind.info,
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
            'Location unavailable',
        kind: _ScheduleTripToastKind.error,
      );
      return;
    }

    _updateState(() => _resolvingCurrentLocation = true);
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

      _updateState(() {
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
      _updateState(() {
        _fromSelection = fallback;
        _fromController.text = fallback.label;
      });
      unawaited(_refreshRoutePreview());
      _showSnackBar(
        message:
            'Pickup coordinates were attached',
        kind: _ScheduleTripToastKind.info,
      );
    } finally {
      if (mounted) {
        _updateState(() => _resolvingCurrentLocation = false);
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

  void _applyPostingRoleDefaults({
    required ScheduleTripPostingRole role,
    required String? vehicleType,
  }) {
    if (role != ScheduleTripPostingRole.driver) {
      return;
    }

    final normalized = vehicleType?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      return;
    }

    _vehiclePreference = normalized.contains('moto')
        ? TripVehiclePreference.moto
        : TripVehiclePreference.cab;
    _seats = normalized.contains('moto') ? 1 : 3;
  }

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> _submit({required bool canScheduleAsDriver}) async {
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final isDriverReturnTrip = _postingRole == ScheduleTripPostingRole.driver;
    if (isDriverReturnTrip && !canScheduleAsDriver) {
      _showSnackBar(
        message: 'Finish driver setup before',
        kind: _ScheduleTripToastKind.error,
      );
      return;
    }
    final tripRole = isDriverReturnTrip ? 'DRIVER' : 'PASSENGER';
    if (!_validateRouteStep()) {
      return;
    }
    if (!_validateTimingStep()) {
      return;
    }
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);
    final returnAt = _returnTrip
        ? _combineDateAndTime(_returnDate, _returnTime)
        : null;

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
        kind: _ScheduleTripToastKind.success,
      );
      if (!result.storedOffline) {
        context.go('/mobility/trips');
      }
      return;
    }

    final error = ref.read(mobilitySubmissionErrorProvider);
    if (error != null) {
      _showSnackBar(message: error, kind: _ScheduleTripToastKind.error);
    }
  }
}
