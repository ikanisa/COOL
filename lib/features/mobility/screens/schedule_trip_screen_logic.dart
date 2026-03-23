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
      TripVehiclePreference.trike ||
      TripVehiclePreference.truck ||
      TripVehiclePreference.others ||
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
        _routePreviewError = preview == null ? 'Route data unavailable' : null;
      });

      // P2.13: Track route preview loaded
      if (preview != null) {
        ref
            .read(engagementTrackerProvider)
            .trackRoutePreviewLoaded(
              origin: _fromController.text,
              destination: _toController.text,
              distanceKm: preview.distanceKm,
              durationMinutes: preview.duration.inMinutes,
            );
      }
    } catch (_) {
      if (!mounted || requestId != _routePreviewRequestId) return;

      _updateState(() {
        _loadingRoutePreview = false;
        _routePreview = null;
        _routePreviewError = 'Route preview failed';
      });
    }
  }

  // ── Pickers ─────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 120)),
      builder: (context, child) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: theme.colorScheme.copyWith(
              brightness: theme.brightness,
              primary: colors.accent,
              onPrimary: theme.colorScheme.onPrimary,
              surface: colors.overlaySurface,
              onSurface: colors.primaryText,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: colors.overlaySurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    _updateState(() {
      _selectedDate = picked;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: theme.colorScheme.copyWith(
              brightness: theme.brightness,
              primary: colors.accent,
              onPrimary: theme.colorScheme.onPrimary,
              surface: colors.overlaySurface,
              onSurface: colors.primaryText,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: colors.overlaySurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    _updateState(() {
      _selectedTime = picked;
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

  void _showSnackBar({required String message, String kind = 'info'}) {
    switch (kind) {
      case 'success':
        CoolToast.success(context, message);
      case 'error':
        CoolToast.error(context, message);
      default:
        CoolToast.info(context, message);
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

    _showSnackBar(message: message, kind: 'error');
    return false;
  }

  bool _validateTimingStep() {
    final l10n = context.l10n;
    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);

    // F-01: Reject past departure times (non-recurring trips only).
    if (!_recurringTrip && departureAt.isBefore(DateTime.now())) {
      _showSnackBar(
        message: l10n.scheduleTripDepartureInPastError,
        kind: 'error',
      );
      return false;
    }

    if (_recurringTrip && _recurringDays.isEmpty) {
      _showSnackBar(
        message: l10n.scheduleTripRecurringDaysError,
        kind: 'error',
      );
      return false;
    }

    return true;
  }

  // Step navigation removed — single-screen layout.
  // _activeStep kept for legacy compatibility (e.g. role card references).

  Future<void> _openRoleSheet(bool canScheduleAsDriver) async {
    final nextRole = await showCoolBottomSheet<ScheduleTripPostingRole>(
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
    // P2.13: Track place autocomplete requested
    ref
        .read(engagementTrackerProvider)
        .trackPlaceAutocompleteRequested(
          query: isOrigin
              ? _fromController.text.trim()
              : _toController.text.trim(),
          source: isOrigin ? 'origin' : 'destination',
        );

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

    // P2.13: Track place selected
    ref
        .read(engagementTrackerProvider)
        .trackPlaceSelected(
          placeLabel: result.label,
          hasCoordinates: result.hasCoordinates,
          source: isOrigin ? 'origin_search' : 'destination_search',
        );

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
      _showSnackBar(message: 'Could not pin exactly', kind: 'info');
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
        message: locationState.error ?? 'Location unavailable',
        kind: 'error',
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
      _showSnackBar(message: 'Pickup coordinates were attached', kind: 'info');
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
    // F-04: Prevent double-submit from rapid taps.
    if (_isSubmitting) return;
    _isSubmitting = true;

    try {
      await _submitInner(canScheduleAsDriver: canScheduleAsDriver);
    } finally {
      _isSubmitting = false;
    }
  }

  Future<void> _submitInner({required bool canScheduleAsDriver}) async {
    FocusScope.of(context).unfocus();

    final l10n = context.l10n;
    final isDriverPosting = _postingRole == ScheduleTripPostingRole.driver;
    if (isDriverPosting && !canScheduleAsDriver) {
      _showSnackBar(message: 'Finish driver setup before', kind: 'error');
      return;
    }
    final tripRole = isDriverPosting ? 'DRIVER' : 'PASSENGER';

    // P2.13: Track trip post started
    ref
        .read(engagementTrackerProvider)
        .trackTripPostStarted(
          role: tripRole,
          vehicleType: _vehiclePreference.name,
        );
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

    // F-17: Confirmation dialog before final submission.
    final departureAt = _combineDateAndTime(_selectedDate, _selectedTime);
    final confirmed = await _showPostConfirmation(departureAt: departureAt);
    if (!confirmed || !mounted) return;

    // Auto-populate contact info from user profile
    final authState = ref.read(authProvider);
    final userPhone = authState.user?.phone;
    final userName = authState.user?.fullName;

    final result = await ref
        .read(mobilityProvider.notifier)
        .createTrip(
          TripPostRequest(
            fromLocation: _fromController.text.trim(),
            toLocation: _toController.text.trim(),
            departureAt: departureAt,
            returnAt: null,
            vehiclePreference: _vehiclePreference,
            seatsNeeded: _seats,
            recurringDays: _recurringTrip
                ? _recurringDays.toList(growable: false)
                : const [],
            role: tripRole,
            isDriverReturnTrip: isDriverPosting,
            latitude: _fromSelection?.latitude,
            longitude: _fromSelection?.longitude,
            destinationLatitude: _toSelection?.latitude,
            destinationLongitude: _toSelection?.longitude,
            contactPhone: userPhone,
            contactName: userName,
            distanceKm: _routePreview?.distanceKm,
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
        kind: 'success',
      );
      if (!result.storedOffline) {
        context.go('/mobility/trips');
      }
      return;
    }

    final error = ref.read(mobilitySubmissionErrorProvider);
    if (error != null) {
      _showSnackBar(message: error, kind: 'error');
    }
  }

  // ── F-17: Confirmation dialog ─────────────────────────────────────

  Future<bool> _showPostConfirmation({required DateTime departureAt}) async {
    final l10n = context.l10n;
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    final isRecurring = _recurringTrip && _recurringDays.isNotEmpty;
    final isDriver = _postingRole == ScheduleTripPostingRole.driver;

    final dateStr =
        '${departureAt.day}/${departureAt.month}/${departureAt.year}';
    final timeStr = TimeOfDay.fromDateTime(departureAt).format(context);

    final result = await showCoolBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colors = ctx.coolSemanticColors;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm Trip',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _ConfirmRow(icon: Icons.trip_origin_rounded, label: from),
            const SizedBox(height: 8),
            _ConfirmRow(icon: Icons.location_on_rounded, label: to),
            const SizedBox(height: 8),
            _ConfirmRow(
              icon: Icons.schedule_rounded,
              label: '$dateStr at $timeStr${isRecurring ? ' (recurring)' : ''}',
            ),
            const SizedBox(height: 8),
            _ConfirmRow(
              icon: isDriver
                  ? Icons.directions_car_rounded
                  : Icons.airline_seat_recline_normal_rounded,
              label: isDriver
                  ? 'Posting as driver'
                  : '${_vehiclePreference.name} · $_seats seat${_seats > 1 ? 's' : ''}',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: CoolButton(
                    label: l10n.cancel,
                    variant: CoolButtonVariant.secondary,
                    onTap: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CoolButton(
                    label: l10n.scheduleTripPostCta,
                    onTap: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result ?? false;
  }
}

// ── Confirm row helper ──────────────────────────────────────────────

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Row(
      children: [
        Icon(icon, size: 18, color: colors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.secondaryText,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
