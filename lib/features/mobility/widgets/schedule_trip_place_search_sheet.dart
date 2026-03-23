import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/geo_point.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_button.dart';
import '../services/place_search_service.dart';

Future<PlaceSearchResult?> showPlaceSearchSheet(
  BuildContext context, {
  required String title,
  required String initialQuery,
  required PlaceSearchService service,
  required String languageTag,
  GeoPoint? near,
}) {
  return showCoolBottomSheet<PlaceSearchResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return ScheduleTripPlaceSearchSheet(
        title: title,
        initialQuery: initialQuery,
        service: service,
        near: near,
        languageTag: languageTag,
      );
    },
  );
}

class ScheduleTripPlaceSearchSheet extends StatefulWidget {
  const ScheduleTripPlaceSearchSheet({
    required this.title,
    required this.initialQuery,
    required this.service,
    required this.languageTag,
    this.near,
    super.key,
  });

  final String title;
  final String initialQuery;
  final PlaceSearchService service;
  final GeoPoint? near;
  final String languageTag;

  @override
  State<ScheduleTripPlaceSearchSheet> createState() =>
      _ScheduleTripPlaceSearchSheetState();
}

class _ScheduleTripPlaceSearchSheetState
    extends State<ScheduleTripPlaceSearchSheet> {
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
    _sessionToken = const Uuid().v4();
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
        _error = 'Min 3 characters';
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
        _error = 'Search unavailable now';
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
        _error = 'Place unresolved';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (viewportHeight * 0.78).clamp(360.0, 680.0);

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.overlaySurface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CoolRadii.xxl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.borderStrong,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x5),
                  Text(
                    widget.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: colors.primaryText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Powered by Google Places',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.secondaryText,
                      fontWeight: FontWeight.w600,
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
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.tertiaryText,
                        fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    if (_isSearching && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CupertinoActivityIndicator(color: colors.accent),
        ),
      );
    }

    if (_error != null) {
      return _PlaceSearchEmptyState(message: _error!);
    }

    if (_results.isEmpty) {
      if (!_hasSearched) {
        return const _PlaceSearchEmptyState(message: 'Search to start');
      }
      return const _PlaceSearchEmptyState(message: 'No places found');
    }

    return ListView.separated(
      itemCount: _results.length,
      padding: const EdgeInsets.only(bottom: 24),
      separatorBuilder: (_, index) => const SizedBox(height: CoolSpace.x3),
      itemBuilder: (context, index) {
        final result = _results[index];
        return Material(
          color: colors.routeSurface,
          borderRadius: BorderRadius.circular(CoolRadii.xl),
          child: InkWell(
            borderRadius: BorderRadius.circular(CoolRadii.xl),
            onTap: _isResolvingSelection
                ? null
                : () => _selectPrediction(result),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(CoolRadii.xl),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.chipSelectedBackground,
                      borderRadius: BorderRadius.circular(CoolRadii.md),
                    ),
                    child: Icon(
                      Icons.place_rounded,
                      color: colors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.primaryText ?? result.label,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.primaryText,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (result.secondaryText != null &&
                            result.secondaryText!.isNotEmpty) ...[
                          const SizedBox(height: CoolSpace.x1),
                          Text(
                            result.secondaryText!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (result.distanceMeters != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.chipBackground,
                        borderRadius: BorderRadius.circular(CoolRadii.sm),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        _formatDistance(result.distanceMeters!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.secondaryText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  if (_isResolvingSelection &&
                      _resolvingPlaceId == result.placeId)
                    const Padding(
                      padding: EdgeInsets.only(left: 12, top: 4),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CupertinoActivityIndicator(radius: 9),
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

  String _formatDistance(int meters) {
    if (meters >= 1000) {
      final km = meters / 1000;
      return km >= 10 ? '${km.round()} km' : '${km.toStringAsFixed(1)} km';
    }
    return '$meters m';
  }
}

class _PlaceSearchEmptyState extends StatelessWidget {
  const _PlaceSearchEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.secondaryText,
            fontWeight: FontWeight.w600,
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
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final field = Semantics(
      textField: true,
      label: 'Trip destination search',
      hint: 'Search places',
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmitted(),
        style: theme.textTheme.bodyLarge?.copyWith(
          color: colors.primaryText,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          hintText: 'Search landmark or address',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: colors.tertiaryText,
            fontWeight: FontWeight.w600,
          ),
          filled: true,
          fillColor: colors.inputSurface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            borderSide: BorderSide(color: colors.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            borderSide: BorderSide(color: colors.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            borderSide: BorderSide(color: colors.accent, width: 2),
          ),
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
              const SizedBox(height: CoolSpace.x3),
              SizedBox(width: double.infinity, height: 60, child: button),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            SizedBox(width: 120, height: 60, child: button),
          ],
        );
      },
    );
  }
}
