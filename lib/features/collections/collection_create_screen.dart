import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_creation_platform.dart';

part 'collection_create_widgets.dart';

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() =>
      _CollectionCreateScreenState();
}

class _CollectionCreateScreenState
    extends ConsumerState<CollectionCreateScreen> {
  static const _lastStep = 3;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _groupImageBytes;
  String? _groupImageName;
  String? _groupImageMimeType;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  CollectionType _collectionType = CollectionType.ikimina;
  bool _creating = false;
  bool _isPublicRequested = false;
  int _step = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _title.removeListener(_refreshPreview);
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(collectCollectionTypeCatalogProvider).valueOrNull ??
        CollectionTypeCatalogConfig.defaults;
    final typeOption = catalog.optionFor(_collectionType);
    if (!canCreateGroupsOnThisPlatform()) return const SizedBox.shrink();
    return ScreenScaffold(
      title: 'Create group',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _creating
                ? 'Creating group'
                : _step == _lastStep
                ? 'Create group'
                : 'Continue',
            icon: _step == _lastStep
                ? CollectIcons.check
                : CollectIcons.arrowForward,
            onPressed: _creating || !_canContinue ? null : _primaryAction,
            expand: true,
          ),
          if (_step > 0)
            CollectButton(
              label: 'Back',
              icon: CollectIcons.chevron,
              onPressed: _creating ? null : () => setState(() => _step -= 1),
              variant: CollectButtonVariant.secondary,
              expand: true,
            ),
        ],
      ),
      children: [
        const CollectPlainPageHeader(title: 'Create group'),
        if (_step == 0)
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectMobileInputField(
                controller: _title,
                icon: CollectIcons.collections,
                label: 'Group name',
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                autocorrect: true,
              ),
              CollectMobileInputField(
                controller: _description,
                icon: CollectIcons.info,
                label: 'Description, optional',
                maxLines: 2,
                textInputAction: TextInputAction.newline,
                textCapitalization: TextCapitalization.sentences,
                autocorrect: true,
              ),
            ],
          )
        else if (_step == 1)
          _MobileCreatePanel(
            error: _error,
            children: [
              _CollectionTypeGrid(
                selected: _collectionType,
                options: catalog.types,
                onChanged: (type) => setState(() {
                  _collectionType = type;
                  _error = null;
                }),
              ),
              const InfoSecurityBanner(
                title: 'One governed bank beneficiary',
                message:
                    'Every group uses the Collect EUR bank account. Group owners cannot replace the beneficiary or redirect member transfers.',
                tone: CollectStatusTone.privacy,
              ),
            ],
          )
        else if (_step == 2) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              _GroupColorPalette(
                selectedHex: _accentColorHex,
                onChanged: (hex) => setState(() => _accentColorHex = hex),
              ),
            ],
          ),
          _CreateGroupPhotoRow(
            title: _title.text.trim(),
            accentColor: _selectedAccentColor,
            imageBytes: _groupImageBytes,
            onPick: _pickGroupImage,
            onRemove: _groupImageBytes == null
                ? null
                : () => setState(() {
                    _groupImageBytes = null;
                    _groupImageName = null;
                    _groupImageMimeType = null;
                  }),
          ),
          CollectCard(
            emphasis: CollectCardEmphasis.flat,
            child: Material(
              color: context.collectColors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Request a public group'),
                subtitle: const Text(
                  'Private is immediate. Public groups appear in discovery only after review.',
                ),
                value: _isPublicRequested,
                onChanged: (value) => setState(() {
                  _isPublicRequested = value;
                  _error = null;
                }),
              ),
            ),
          ),
        ] else
          _CreateGroupReview(
            title: _title.text.trim(),
            description: _description.text.trim(),
            collectionTypeOption: typeOption,
            receiver: 'Collect EUR bank account · SEPA transfer',
            accentColor: _selectedAccentColor,
            hasPhoto: _groupImageBytes != null,
            isPublicRequested: _isPublicRequested,
            error: _error,
          ),
      ],
    );
  }

  bool get _canContinue => _step != 0 || _title.text.trim().isNotEmpty;

  Color get _selectedAccentColor => CollectColors.brandPrimaryOptions
      .firstWhere(
        (option) => option.hex == _accentColorHex,
        orElse: () => CollectColors.brandPrimaryOptions.first,
      )
      .color;

  CollectionTypeCatalogItem get _selectedTypeOption =>
      (ref.read(collectCollectionTypeCatalogProvider).valueOrNull ??
              CollectionTypeCatalogConfig.defaults)
          .optionFor(_collectionType);

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _primaryAction() async {
    if (_step == 0 && _title.text.trim().isEmpty) {
      setState(() => _error = 'Name required.');
      return;
    }
    if (_step < _lastStep) {
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    await _create();
  }

  Future<void> _create() async {
    try {
      setState(() {
        _creating = true;
        _error = null;
      });
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .createCollection(
            title: _title.text.trim(),
            description: _description.text,
            collectionType: _collectionType,
            categorySubtype: _selectedTypeOption.defaultCategorySubtype,
            purposeLabel: _selectedTypeOption.defaultPurposeLabel,
            accentColorHex: _accentColorHex,
            imageUrl: _selectedImageDataUri(),
            isPublic: _isPublicRequested,
          );
      if (mounted) context.go('/groups/${collection.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error is StateError || error is FormatException
            ? error.toString().replaceFirst(
                RegExp(r'^(Bad state|FormatException):\s*'),
                '',
              )
            : 'Could not create the group. Check the details and try again.';
      });
    }
  }

  Future<void> _pickGroupImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 86,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _groupImageBytes = bytes;
        _groupImageName = image.name;
        _groupImageMimeType = image.mimeType ?? _mimeTypeFromName(image.name);
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Photo upload failed.');
    }
  }

  String? _selectedImageDataUri() {
    final bytes = _groupImageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mime =
        _groupImageMimeType ??
        _mimeTypeFromName(_groupImageName ?? '') ??
        'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }
}
