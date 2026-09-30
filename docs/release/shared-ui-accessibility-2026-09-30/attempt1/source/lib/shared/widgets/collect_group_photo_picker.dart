import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/collect_group_cover.dart';
import '../models/collect_models.dart';
import 'collect_components.dart';

class CollectPickedGroupPhoto {
  const CollectPickedGroupPhoto({required this.bytes, required this.value});
  final Uint8List bytes;
  final String value;
}

Future<CollectPickedGroupPhoto?> pickCollectGroupPhoto(
  BuildContext context, {
  required ImagePicker imagePicker,
  CollectionType? groupType,
  String? selectedReference,
}) async {
  final selection = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: CollectMotion.animationStyle(context),
    builder: (context) => CollectGroupPhotoSheet(
      groupType: groupType,
      selectedReference: selectedReference,
    ),
  );
  if (selection == null || !context.mounted) return null;
  if (selection == 'device-gallery') {
    final file = await imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      imageQuality: 86,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 5 MB.');
    }
    final extension = file.name.toLowerCase();
    final mime =
        file.mimeType ??
        (extension.endsWith('.png')
            ? 'image/png'
            : extension.endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg');
    return CollectPickedGroupPhoto(
      bytes: bytes,
      value: 'data:$mime;base64,${base64Encode(bytes)}',
    );
  }
  final cover = CollectGroupCover.resolve(selection);
  if (cover == null || cover.namedGroup != null) {
    throw const FormatException('Choose another photo from the library.');
  }
  final data = await rootBundle.load(cover.asset);
  return CollectPickedGroupPhoto(
    bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    value: cover.reference,
  );
}

class CollectGroupPhotoSheet extends StatefulWidget {
  const CollectGroupPhotoSheet({
    super.key,
    this.groupType,
    this.selectedReference,
  });
  final CollectionType? groupType;
  final String? selectedReference;
  @override
  State<CollectGroupPhotoSheet> createState() => _CollectGroupPhotoSheetState();
}

class _CollectGroupPhotoSheetState extends State<CollectGroupPhotoSheet> {
  final _search = TextEditingController();
  String? _family, _context, _selected;
  bool _browseAll = false;

  @override
  void initState() {
    super.initState();
    final cover = CollectGroupCover.resolve(widget.selectedReference);
    if (cover != null && cover.namedGroup == null) _selected = cover.reference;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final choices = CollectGroupCover.suggestions(
      type: widget.groupType,
      family: _family,
      context: _context,
      query: _search.text,
      browseAll: _browseAll,
    );
    final selected = CollectGroupCover.resolve(_selected);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Group photo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close photo collection',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: CollectButton(
        label: 'Use photo',
        icon: CollectIcons.check,
        expand: true,
        onPressed: selected == null
            ? null
            : () => Navigator.of(context).pop(selected.reference),
      ),
    );
    return FractionallySizedBox(
      heightFactor: 0.94,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, viewport) {
              final scrollChrome = viewport.maxHeight < 320;
              return Column(
                children: [
                  if (!scrollChrome) header,
                  Expanded(
                    key: const ValueKey('photo-grid-body'),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth >= 600
                            ? 3
                            : constraints.maxWidth >= 360 &&
                                  MediaQuery.textScalerOf(context).scale(1) <
                                      1.5
                            ? 2
                            : 1;
                        return CustomScrollView(
                          key: const ValueKey('group-photo-scroll'),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          slivers: [
                            if (scrollChrome) SliverToBoxAdapter(child: header),
                            SliverPadding(
                              key: const ValueKey('photo-filters'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              sliver: SliverToBoxAdapter(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    CollectButton(
                                      label: 'Choose your own photo',
                                      icon: CollectIcons.photo,
                                      variant: CollectButtonVariant.secondary,
                                      expand: true,
                                      onPressed: () => Navigator.of(
                                        context,
                                      ).pop('device-gallery'),
                                    ),
                                    CollectSpacing.gap16,
                                    TextField(
                                      key: const ValueKey('group-photo-search'),
                                      controller: _search,
                                      decoration:
                                          _photoInput(
                                            context,
                                            'Search photos',
                                          ).copyWith(
                                            floatingLabelBehavior:
                                                FloatingLabelBehavior.never,
                                            hintText:
                                                'Try ubukwe, school, savings',
                                            prefixIcon: const Icon(
                                              Icons.search_rounded,
                                            ),
                                          ),
                                      onChanged: (_) => setState(() {}),
                                      textInputAction: TextInputAction.search,
                                    ),
                                    CollectSpacing.gap12,
                                    Wrap(
                                      spacing: CollectSpacing.x2,
                                      runSpacing: CollectSpacing.x2,
                                      children: [
                                        ChoiceChip(
                                          label: const Text('Suggested'),
                                          selected: !_browseAll,
                                          onSelected: (_) => setState(() {
                                            _browseAll = false;
                                            _family = null;
                                            _context = null;
                                          }),
                                        ),
                                        ChoiceChip(
                                          label: const Text('All photos'),
                                          selected: _browseAll,
                                          onSelected: (_) =>
                                              setState(() => _browseAll = true),
                                        ),
                                      ],
                                    ),
                                    CollectSpacing.gap12,
                                    DropdownButtonFormField<String>(
                                      key: ValueKey('photo-family-$_family'),
                                      initialValue: _family ?? '',
                                      isExpanded: true,
                                      decoration: _photoInput(context, 'Theme'),
                                      itemHeight: null,
                                      items: [
                                        const DropdownMenuItem(
                                          value: '',
                                          child: Text('All themes'),
                                        ),
                                        for (final entry
                                            in collectCoverFamilies.entries)
                                          DropdownMenuItem(
                                            value: entry.key,
                                            child: Text(entry.value),
                                          ),
                                      ],
                                      onChanged: (value) => setState(() {
                                        _family = value == '' ? null : value;
                                        _browseAll = true;
                                        _context = null;
                                      }),
                                    ),
                                    if (_browseAll ||
                                        widget.groupType ==
                                            CollectionType.church) ...[
                                      CollectSpacing.gap12,
                                      DropdownButtonFormField<String>(
                                        key: ValueKey(
                                          'photo-context-$_context',
                                        ),
                                        initialValue: _context ?? '',
                                        isExpanded: true,
                                        decoration: _photoInput(
                                          context,
                                          'Occasion',
                                        ),
                                        itemHeight: null,
                                        items: [
                                          const DropdownMenuItem(
                                            value: '',
                                            child: Text('General'),
                                          ),
                                          for (final entry
                                              in collectCoverContexts.entries)
                                            DropdownMenuItem(
                                              value: entry.key,
                                              child: Text(entry.value),
                                            ),
                                        ],
                                        onChanged: (value) => setState(() {
                                          _context = value == '' ? null : value;
                                          _browseAll = true;
                                        }),
                                      ),
                                    ],
                                    CollectSpacing.gap16,
                                    Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        '${choices.length} ${choices.length == 1 ? 'photo' : 'photos'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                    ),
                                    CollectSpacing.gap12,
                                  ],
                                ),
                              ),
                            ),
                            if (choices.isEmpty)
                              SliverPadding(
                                padding: const EdgeInsets.all(24),
                                sliver: SliverToBoxAdapter(
                                  child: Column(
                                    children: [
                                      Text(
                                        'No matching photos',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      CollectSpacing.gap12,
                                      CollectButton(
                                        label: 'Clear filters',
                                        variant: CollectButtonVariant.secondary,
                                        onPressed: () => setState(() {
                                          _search.clear();
                                          _family = null;
                                          _context = null;
                                          _browseAll = true;
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  24,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: (choices.length / columns).ceil(),
                                  itemBuilder: (context, row) => Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (
                                          var column = 0;
                                          column < columns;
                                          column++
                                        ) ...[
                                          if (column > 0) CollectSpacing.gapW12,
                                          Expanded(
                                            child:
                                                row * columns + column >=
                                                    choices.length
                                                ? const SizedBox.shrink()
                                                : _PhotoOption(
                                                    cover:
                                                        choices[row * columns +
                                                            column],
                                                    selected:
                                                        _selected ==
                                                        choices[row * columns +
                                                                column]
                                                            .reference,
                                                    onSelect: () => setState(
                                                      () => _selected =
                                                          choices[row *
                                                                      columns +
                                                                  column]
                                                              .reference,
                                                    ),
                                                  ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (scrollChrome) SliverToBoxAdapter(child: footer),
                          ],
                        );
                      },
                    ),
                  ),
                  if (!scrollChrome) footer,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PhotoOption extends StatelessWidget {
  const _PhotoOption({
    required this.cover,
    required this.selected,
    required this.onSelect,
  });
  final CollectGroupCover cover;
  final bool selected;
  final VoidCallback onSelect;
  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      selected: selected,
      label: cover.name,
      onTap: onSelect,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceMuted,
        borderRadius: CollectRadius.cardBorder,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('group-photo-${cover.id}'),
          onTap: onSelect,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? colors.textPrimary : colors.panelBorder,
                width: selected ? 2 : 1,
              ),
              borderRadius: CollectRadius.cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: CollectGroupCardTokens.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        cover.asset,
                        fit: BoxFit.cover,
                        alignment: Alignment(
                          cover.focalX * 2 - 1,
                          cover.focalY * 2 - 1,
                        ),
                        cacheWidth: 768,
                        errorBuilder: (_, error, stack) => Icon(
                          CollectIcons.photo,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: colors.textPrimary,
                            foregroundColor: colors.surfaceMuted,
                            child: const Icon(Icons.check_rounded),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    cover.name,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration _photoInput(BuildContext context, String label) {
  final colors = context.collectColors;
  final border = OutlineInputBorder(
    borderRadius: CollectRadius.cardBorder,
    borderSide: BorderSide(color: colors.panelBorder),
  );
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: colors.controlSurface,
    contentPadding: const EdgeInsets.all(CollectSpacing.x4),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: colors.textPrimary, width: 2),
    ),
  );
}
