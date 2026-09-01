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
  static const _lastStep = 4;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _receiverNumber = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _groupImageBytes;
  String? _groupImageName;
  String? _groupImageMimeType;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  CollectionType _collectionType = CollectionType.ikimina;
  String _receiverProvider = 'mtn_momo';
  bool _creating = false;
  bool _enablingSms = false;
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
    _receiverNumber.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog =
        ref.watch(collectCollectionTypeCatalogProvider).valueOrNull ??
        CollectionTypeCatalogConfig.defaults;
    final typeOption = catalog.optionFor(_collectionType);
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (profile != null && _receiverNumber.text != profile.momoNumber) {
      _receiverNumber.text = profile.momoNumber;
      _receiverProvider = profile.momoProvider.isEmpty
          ? 'mtn_momo'
          : profile.momoProvider;
    }
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
            ],
          )
        else if (_step == 2) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectListTile(
                leading: CollectIcons.momo,
                title: _receiverProvider == 'airtel_money'
                    ? 'Airtel Money receiver'
                    : 'MTN MoMo receiver',
                subtitle: _receiverNumber.text.trim(),
                trailing: const Icon(CollectIcons.chevron),
                onTap: () => context.push('/settings/profile'),
              ),
              Text(
                'The receiver is your Rwanda MoMo profile. Tap it to change provider or number before creating this group.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const InfoSecurityBanner(
                title: 'Android receipt reconciliation',
                message:
                    'Collect asks for SMS access only to capture MoMo receipts for this private group. Raw SMS stays protected and admin review is audited.',
                tone: CollectStatusTone.privacy,
              ),
              CollectButton(
                label: _enablingSms
                    ? 'Checking SMS access'
                    : 'Enable MoMo receipt SMS',
                icon: CollectIcons.sms,
                onPressed: _enablingSms ? null : _enableSmsAccess,
                variant: CollectButtonVariant.secondary,
                expand: true,
              ),
            ],
          ),
        ] else if (_step == 3) ...[
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
        ] else
          _CreateGroupReview(
            title: _title.text.trim(),
            description: _description.text.trim(),
            collectionTypeOption: typeOption,
            receiver:
                '${_receiverProvider == 'airtel_money' ? 'Airtel Money' : 'MTN MoMo'} · ${_receiverNumber.text.trim()}',
            accentColor: _selectedAccentColor,
            hasPhoto: _groupImageBytes != null,
            isPublicRequested: false,
            error: _error,
          ),
      ],
    );
  }

  bool get _canContinue => switch (_step) {
    0 => _title.text.trim().isNotEmpty,
    2 =>
      (_receiverProvider == 'mtn_momo'
              ? RegExp(r'^(?:\+?250|0)?7[89][0-9]{7}$')
              : RegExp(r'^(?:\+?250|0)?7[23][0-9]{7}$'))
          .hasMatch(_receiverNumber.text.replaceAll(RegExp(r'\s'), '')),
    _ => true,
  };

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
    if (_step == 2 && !_canContinue) {
      setState(
        () => _error = _receiverProvider == 'airtel_money'
            ? 'Use an Airtel Money number such as 073XXXXXXX.'
            : 'Use an MTN MoMo number such as 078XXXXXXX.',
      );
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
            receiverMomoNumber: _receiverNumber.text,
            receiverProvider: _receiverProvider,
            isPublic: false,
          );
      if (mounted) context.go('/groups/${collection.id}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = _safeGroupCreateError(error);
      });
    }
  }

  Future<void> _enableSmsAccess() async {
    setState(() {
      _enablingSms = true;
      _error = null;
    });
    try {
      final enabled = await ref
          .read(collectRepositoryProvider.notifier)
          .setSmsAccess(true);
      if (!enabled) {
        throw StateError(
          'Android SMS permission was not granted. Enable it to reconcile MoMo receipts.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('MoMo receipt SMS enabled.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _safeGroupCreateError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _enablingSms = false);
    }
  }

  String _safeGroupCreateError(Object error) {
    if (error is StateError) return error.message.toString();
    if (error is FormatException) return error.message.toString();
    return 'Could not create the group. Check the details and try again.';
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
