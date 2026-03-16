import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../services/place_search_service.dart';
import '../../../core/models/geo_point.dart';

Future<PlaceSearchResult?> showPlaceSearchSheet(
  BuildContext context, {
  required String title,
  required String initialQuery,
  required PlaceSearchService service,
  required String languageTag,
  GeoPoint? near,
}) {
  return showModalBottomSheet<PlaceSearchResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
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

/// Bottom sheet for searching and selecting a place.
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
        _error =
            'Search unavailable now';
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
            'Place unresolved';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (viewportHeight * 0.78).clamp(360.0, 680.0);
    final palette = context.coolPalette;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SizedBox(
        height: sheetHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                        color: palette.border2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Powered by Google Places',
                    style: Theme.of(context).textTheme.bodySmall,
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
                        color: palette.text3,
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
    final palette = context.coolPalette;
    if (_isSearching && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CupertinoActivityIndicator(color: palette.accent),
        ),
      );
    }

    if (_error != null) {
      return _PlaceSearchEmptyState(message: _error!);
    }

    if (_results.isEmpty) {
      if (!_hasSearched) {
        return const _PlaceSearchEmptyState(
          message: 'Search Google Places to',
        );
      }
      return const _PlaceSearchEmptyState(
        message: 'No matching places found',
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      padding: const EdgeInsets.only(bottom: 24),
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final result = _results[index];
        return Material(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _isResolvingSelection
                ? null
                : () => _selectPrediction(result),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.accentGlow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.place_rounded,
                      color: palette.accent,
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        if (result.secondaryText != null &&
                            result.secondaryText!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            result.secondaryText!,
                            style: Theme.of(context).textTheme.bodySmall,
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
}

class _PlaceSearchEmptyState extends StatelessWidget {
  const _PlaceSearchEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: palette.text2,
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
    final palette = context.coolPalette;
    final field = Semantics(
      textField: true,
      label: 'Trip destination search',
      hint: 'Search places',
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => onSubmitted(),
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
        decoration: InputDecoration(
          hintText: 'Search landmark or address',
          hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.text3,
              ),
          filled: true,
          fillColor: palette.surface2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: palette.border, width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: palette.border, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: palette.accent, width: 2.0),
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
              const SizedBox(height: 12),
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
