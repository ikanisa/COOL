import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../services/place_search_service.dart';
import '../../../core/models/geo_point.dart';

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
      separatorBuilder: (_, index) => const SizedBox(height: 10),
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
