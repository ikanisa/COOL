part of 'auth_screen_widgets.dart';

const _countryPickerMaxTextScale = 1.0;

Future<Country?> showCollectCountryPicker(BuildContext context) {
  return showModalBottomSheet<Country>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: CollectColors.transparentColor,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (context) => const AuthCountryPickerSheet(),
  );
}

class AuthCountryPickerSheet extends StatefulWidget {
  const AuthCountryPickerSheet({super.key});

  @override
  State<AuthCountryPickerSheet> createState() => _AuthCountryPickerSheetState();
}

class _AuthCountryPickerSheetState extends State<AuthCountryPickerSheet> {
  late final TextEditingController _searchController;
  late final List<Country> _countries;
  late List<Country> _filteredCountries;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _countries = List<Country>.unmodifiable(CountryService().getAll());
    _filteredCountries = _countries;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _search(String query) {
    final normalized = query.trim();
    final localizations = CountryLocalizations.of(context);
    setState(() {
      _filteredCountries = normalized.isEmpty
          ? _countries
          : _countries
                .where(
                  (country) => country.startsWith(normalized, localizations),
                )
                .toList(growable: false);
    });
  }

  String _localizedName(Country country) {
    return (country.getTranslatedName(context) ?? country.name).replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
  }

  void _select(Country country) {
    country.nameLocalized = _localizedName(country);
    Navigator.of(context).pop(country);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.authForeground;
    final media = MediaQuery.of(context);
    final favorite = _searchController.text.isEmpty
        ? _countries.where((country) => country.countryCode == 'RW').firstOrNull
        : null;

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: ColoredBox(
          color: colors.authSheetSurface,
          child: SizedBox(
            height: media.size.height * 0.74,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: _countryPickerMaxTextScale,
              child: Column(
                children: [
                  const SizedBox(height: CollectSpacing.x3),
                  Semantics(
                    label: 'Country picker',
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: foreground.withValues(alpha: 0.78),
                        borderRadius: CollectRadius.pillBorder,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CollectSpacing.x5,
                      CollectSpacing.x6,
                      CollectSpacing.x5,
                      CollectSpacing.x3,
                    ),
                    child: CollectAccessibleTextField(
                      controller: _searchController,
                      label: 'Search country',
                      onChanged: _search,
                      builder: (focusNode) => TextField(
                        key: const ValueKey('auth_country_search_input'),
                        focusNode: focusNode,
                        controller: _searchController,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                          fontWeight: CollectTypography.weightBold,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search country',
                          hintStyle: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.48),
                              ),
                          prefixIcon: Icon(
                            CollectIcons.search,
                            color: foreground.withValues(alpha: 0.72),
                          ),
                          filled: true,
                          fillColor: foreground.withValues(alpha: 0.12),
                          border: OutlineInputBorder(
                            borderRadius: CollectRadius.pillBorder,
                            borderSide: BorderSide(
                              color: foreground.withValues(alpha: 0.14),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: CollectRadius.pillBorder,
                            borderSide: BorderSide(
                              color: foreground.withValues(alpha: 0.14),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: CollectRadius.pillBorder,
                            borderSide: BorderSide(
                              color: colors.focusRing,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: _search,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('auth_country_list'),
                      padding: const EdgeInsets.only(
                        left: CollectSpacing.x4,
                        right: CollectSpacing.x4,
                        bottom: CollectSpacing.x5,
                      ),
                      children: [
                        if (favorite != null) ...[
                          _CountryPickerRow(
                            country: favorite,
                            localizedName: _localizedName(favorite),
                            onTap: () => _select(favorite),
                          ),
                          Divider(
                            color: foreground.withValues(alpha: 0.55),
                            height: 1,
                          ),
                        ],
                        for (final country in _filteredCountries)
                          _CountryPickerRow(
                            country: country,
                            localizedName: _localizedName(country),
                            onTap: () => _select(country),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryPickerRow extends StatelessWidget {
  const _CountryPickerRow({
    required this.country,
    required this.localizedName,
    required this.onTap,
  });

  final Country country;
  final String localizedName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.authForeground;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: foreground,
      fontWeight: CollectTypography.weightBold,
      letterSpacing: CollectTypography.trackingDefault,
    );
    final phoneCode = '+${country.phoneCode}';

    return Semantics(
      button: true,
      label: '$localizedName, calling code $phoneCode',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: CollectColors.transparentColor,
          child: InkWell(
            key: ValueKey(
              'auth_country_row_${country.countryCode}_${country.phoneCode}',
            ),
            borderRadius: CollectRadius.controlBorder,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CollectSpacing.x2,
                  vertical: CollectSpacing.x3,
                ),
                child: Row(
                  children: [
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1,
                      child: SizedBox(
                        width: 36,
                        child: Text(
                          country.flagEmoji,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ),
                    CollectSpacing.gapW12,
                    Text(
                      phoneCode,
                      key: ValueKey(
                        'auth_country_code_${country.countryCode}_${country.phoneCode}',
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: style?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    CollectSpacing.gapW16,
                    Expanded(
                      child: Text(
                        localizedName,
                        key: ValueKey(
                          'auth_country_name_${country.countryCode}_${country.phoneCode}',
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
