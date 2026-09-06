import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/collect_group_photo_picker.dart';
import '../../shared/widgets/collect_group_image.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_empty_state.dart';

part 'group_profile_media.dart';
part 'group_profile_form_controls.dart';

class GroupProfileScreen extends ConsumerStatefulWidget {
  const GroupProfileScreen({required this.collectionId, super.key});

  final String collectionId;

  @override
  ConsumerState<GroupProfileScreen> createState() => _GroupProfileScreenState();
}

class _GroupProfileScreenState extends ConsumerState<GroupProfileScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageValue;
  bool _removeExistingImage = false;
  String _accentColorHex = CollectColors.groupAccentOptions.first.hex;
  String _cadence = 'monthly';
  CollectionType _collectionType = CollectionType.ikimina;
  bool _recurringEnabled = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
      );
    }
    final profile = state.currentProfile;
    if (profile == null || collection.creatorUserId != profile.id) {
      return ScreenScaffold(
        title: 'Group profile',
        subtitle: collection.title,
        children: [
          const MinimalStatePanel(
            icon: CollectIcons.lock,
            title: 'Owner only',
            message: 'Only the group owner can edit this profile.',
            tone: CollectStatusTone.privacy,
          ),
          CollectButton(
            label: 'Open group',
            icon: CollectIcons.collections,
            onPressed: () => context.go('/groups/${widget.collectionId}'),
            expand: true,
          ),
        ],
      );
    }
    final collectionCatalog =
        ref.watch(collectCollectionTypeCatalogProvider).valueOrNull ??
        CollectionTypeCatalogConfig.defaults;
    _loadOnce(collection);

    return ScreenScaffold(
      title: 'Group profile',
      showHeader: false,
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _saving ? 'Saving' : 'Save',
            icon: CollectIcons.check,
            onPressed:
                _saving || _name.text.trim().isEmpty || !_hasChanges(collection)
                ? null
                : () => _save(collection),
            expand: true,
          ),
        ],
      ),
      children: [
        const CollectPlainPageHeader(title: 'Group profile'),
        _GroupProfileMediaRow(
          title: _name.text.trim().isEmpty ? collection.title : _name.text,
          accentColor: _selectedColor,
          imageBytes: _imageBytes,
          imageUrl: _imageBytes == null && !_removeExistingImage
              ? collection.imageUrl
              : null,
          onPick: _pickImage,
          onRemove:
              _imageBytes != null ||
                  (!_removeExistingImage &&
                      collection.imageUrl?.trim().isNotEmpty == true)
              ? () => setState(() {
                  _imageBytes = null;
                  _imageValue = null;
                  _removeExistingImage = true;
                })
              : null,
        ),
        _GroupProfileEditSection(
          errorMessage: _error,
          children: [
            _GroupProfileCardTextField(
              controller: _name,
              label: 'Group name',
              textCapitalization: TextCapitalization.words,
              autocorrect: true,
              onChanged: (_) => setState(() {}),
            ),
            _GroupProfileCardTextField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        _GroupProfileEditSection(
          children: [
            _ProfileCollectionTypePicker(
              selected: _collectionType,
              options: collectionCatalog.types,
              onChanged: (value) => setState(() => _collectionType = value),
            ),
            InfoSecurityBanner(
              title: collection.isPublic
                  ? 'Platform-sponsored public group'
                  : 'Private group',
              message: collection.isPublic
                  ? 'Public visibility is managed by Collect administrators and is preserved when you edit this profile.'
                  : 'User-created groups stay private. Invite members with the group link or QR code.',
              tone: CollectStatusTone.privacy,
            ),
            _RecurringCadenceControl(
              enabled: _recurringEnabled,
              selected: _cadence,
              onEnabledChanged: (value) =>
                  setState(() => _recurringEnabled = value),
              onCadenceChanged: (value) => setState(() => _cadence = value),
            ),
          ],
        ),
        _GroupProfileEditSection(
          children: [
            const SectionHeader(title: 'Paying to'),
            if (collection.receiverMomoNumber != null)
              CollectListTile(
                leading: CollectIcons.momo,
                title: collection.receiverDisplayLabel,
                subtitle: collection.receiverMomoNumber,
              ),
          ],
        ),
        _GroupProfileEditSection(
          children: [
            _ProfileColorPalette(
              selectedHex: _accentColorHex,
              onChanged: (value) => setState(() => _accentColorHex = value),
            ),
          ],
        ),
      ],
    );
  }

  Color get _selectedColor {
    return CollectColors.groupAccentOptions
        .firstWhere(
          (option) =>
              option.hex ==
              CollectColors.groupColorHexForDisplay(_accentColorHex),
          orElse: () => CollectColors.groupAccentOptions.first,
        )
        .color;
  }

  bool _hasChanges(CollectCollection collection) =>
      _name.text.trim() != collection.title ||
      _description.text.trim() != collection.description ||
      _accentColorHex !=
          (collection.accentColorHex ??
              CollectColors.groupAccentOptions.first.hex) ||
      _cadence != collection.recurringCadence ||
      _recurringEnabled != collection.isRecurring ||
      _collectionType != collection.collectionType ||
      _imageBytes != null ||
      _removeExistingImage;

  void _loadOnce(CollectCollection collection) {
    if (_loaded) return;
    _loaded = true;
    _name.text = collection.title;
    _description.text = collection.description;
    _accentColorHex =
        collection.accentColorHex ?? CollectColors.groupAccentOptions.first.hex;
    _cadence = collection.recurringCadence;
    _recurringEnabled = collection.isRecurring;
    _collectionType = collection.collectionType;
  }

  Future<void> _pickImage() async {
    try {
      final image = await pickCollectGroupPhoto(
        context,
        imagePicker: _imagePicker,
        groupType: _collectionType,
        selectedReference:
            _imageValue ??
            (_removeExistingImage
                ? null
                : ref
                      .read(collectRepositoryProvider.notifier)
                      .maybeCollectionById(widget.collectionId)
                      ?.imageUrl),
      );
      if (image == null) return;
      if (!mounted) return;
      setState(() {
        _imageBytes = image.bytes;
        _imageValue = image.value;
        _removeExistingImage = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Image upload failed.');
    }
  }

  Future<void> _save(CollectCollection collection) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final imageUrl = _removeExistingImage
          ? null
          : _imageValue ?? collection.imageUrl;
      await ref
          .read(collectRepositoryProvider.notifier)
          .updateCollectionProfile(
            collectionId: collection.id,
            title: _name.text,
            description: _description.text,
            recurringCadence: _recurringEnabled ? _cadence : 'monthly',
            collectionType: _collectionType,
            categorySubtype: _selectedTypeOption.defaultCategorySubtype,
            purposeLabel: _selectedTypeOption.defaultPurposeLabel,
            accentColorHex: _accentColorHex,
            imageUrl: imageUrl,
            isPublic: collection.isPublic,
            isRecurring: _recurringEnabled,
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}/manage');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error =
            'Could not save the group profile. Check the fields and try again.';
      });
    }
  }

  CollectionTypeCatalogItem get _selectedTypeOption {
    return (ref.read(collectCollectionTypeCatalogProvider).valueOrNull ??
            CollectionTypeCatalogConfig.defaults)
        .optionFor(_collectionType);
  }
}
