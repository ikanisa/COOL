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
  final _receiver = TextEditingController();
  final _receiverPayCode = TextEditingController();
  final _imagePicker = ImagePicker();

  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageMimeType;
  bool _removeExistingImage = false;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  String _cadence = 'monthly';
  CollectionType _collectionType = CollectionType.ikimina;
  CollectMomoReceiverMode _receiverMode = CollectMomoReceiverMode.momoNumber;
  bool _isPublic = false;
  bool _recurringEnabled = true;
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _receiver.dispose();
    _receiverPayCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(collectRepositoryProvider.notifier);
    final collection = repo.maybeCollectionById(widget.collectionId);
    if (collection == null) return const MissingGroupStateScreen();
    if (collection.isArchived) {
      return ArchivedGroupStateScreen(
        collectionId: widget.collectionId,
        groupTitle: collection.title,
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
            onPressed: _saving ? null : () => _save(collection),
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
                      _imageProviderUrl(collection.imageUrl) != null)
              ? () => setState(() {
                  _imageBytes = null;
                  _imageName = null;
                  _imageMimeType = null;
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
            ),
            _GroupProfileCardTextField(
              controller: _description,
              label: 'Description',
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              autocorrect: true,
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
            Material(
              color: context.collectColors.transparent,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public group'),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
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
            CollectMomoReceiverCard(
              mode: _receiverMode,
              onChanged: (mode) => setState(() {
                _receiverMode = mode;
                _error = null;
              }),
              numberController: _receiver,
              codeController: _receiverPayCode,
              numberInputLabel: 'Receiver MoMo',
              codeInputLabel: 'MoMo code',
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
    return CollectColors.brandPrimaryOptions
        .firstWhere(
          (option) => option.hex == _accentColorHex,
          orElse: () => CollectColors.brandPrimaryOptions.first,
        )
        .color;
  }

  void _loadOnce(CollectCollection collection) {
    if (_loaded) return;
    _loaded = true;
    _name.text = collection.title;
    _description.text = collection.description;
    final receiverValue = collection.receiverMomoNumber ?? '';
    if (_isMomoPayCodeLabel(collection.receiverDisplayLabel)) {
      _receiverMode = CollectMomoReceiverMode.momoPayCode;
      _receiverPayCode.text = receiverValue;
      _receiver.clear();
    } else {
      _receiverMode = CollectMomoReceiverMode.momoNumber;
      _receiver.text = receiverValue;
      _receiverPayCode.clear();
    }
    _accentColorHex =
        collection.accentColorHex ??
        CollectColors.brandPrimaryOptions.first.hex;
    _cadence = collection.recurringCadence;
    _recurringEnabled = collection.recurringCadence.trim().isNotEmpty;
    _collectionType = collection.collectionType;
    _isPublic = collection.isPublic;
  }

  Future<void> _pickImage() async {
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
        _imageBytes = bytes;
        _imageName = image.name;
        _imageMimeType = image.mimeType ?? _mimeTypeFromName(image.name);
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
          : _selectedImageDataUri() ?? collection.imageUrl;
      final receiverIsMomoPayCode =
          _receiverMode == CollectMomoReceiverMode.momoPayCode;
      await ref
          .read(collectRepositoryProvider.notifier)
          .updateCollectionProfile(
            collectionId: collection.id,
            title: _name.text,
            description: _description.text,
            receiverMomoNumber: receiverIsMomoPayCode
                ? _receiverPayCode.text
                : _receiver.text,
            receiverLabel: receiverIsMomoPayCode
                ? 'MoMo code'
                : 'Primary MoMo receiver',
            recurringCadence: _recurringEnabled ? _cadence : 'monthly',
            collectionType: _collectionType,
            categorySubtype: _selectedTypeOption.defaultCategorySubtype,
            purposeLabel: _selectedTypeOption.defaultPurposeLabel,
            accentColorHex: _accentColorHex,
            imageUrl: imageUrl,
            isPublic: _isPublic,
            receiverIsMomoPayCode: receiverIsMomoPayCode,
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}/manage');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  String? _selectedImageDataUri() {
    final bytes = _imageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType =
        _imageMimeType ?? _mimeTypeFromName(_imageName ?? '') ?? 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  CollectionTypeCatalogItem get _selectedTypeOption {
    return (ref.read(collectCollectionTypeCatalogProvider).valueOrNull ??
            CollectionTypeCatalogConfig.defaults)
        .optionFor(_collectionType);
  }
}

bool _isMomoPayCodeLabel(String label) {
  return label.trim().toLowerCase().contains('code');
}
