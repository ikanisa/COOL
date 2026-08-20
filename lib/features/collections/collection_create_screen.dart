import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/security/phone_normalizer.dart';
import '../../core/security/momo_receiver_normalizer.dart';
import '../../core/security/play_integrity_service.dart';
import '../../core/security/sms_access_channel.dart';
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

class _CollectionCreateScreenState extends ConsumerState<CollectionCreateScreen>
    with WidgetsBindingObserver {
  static const _lastStep = 4;

  final _title = TextEditingController();
  final _description = TextEditingController();
  final _receiverNumber = TextEditingController();
  final _receiverPayCode = TextEditingController();
  final _imagePicker = ImagePicker();
  Uint8List? _groupImageBytes;
  String? _groupImageName;
  String? _groupImageMimeType;
  String _accentColorHex = CollectColors.brandPrimaryOptions.first.hex;
  CollectMomoReceiverMode _receiverMode = CollectMomoReceiverMode.momoNumber;
  CollectionType _collectionType = CollectionType.ikimina;
  bool _syncedProfileMomo = false;
  bool _creating = false;
  bool _isPublicRequested = false;
  bool _permissionChecking = false;
  SmsAccessStatus? _smsStatus;
  String? _permissionError;
  int _step = 0;
  String? _error;

  TextEditingController get _activeReceiverController {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? _receiverPayCode
        : _receiverNumber;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _title.addListener(_refreshPreview);
    _receiverNumber.addListener(_refreshPreview);
    _receiverPayCode.addListener(_refreshPreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshSmsPermission();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshSmsPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _title.removeListener(_refreshPreview);
    _receiverNumber.removeListener(_refreshPreview);
    _receiverPayCode.removeListener(_refreshPreview);
    _title.dispose();
    _description.dispose();
    _receiverNumber.dispose();
    _receiverPayCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    final collectionCatalog =
        ref.watch(collectCollectionTypeCatalogProvider).valueOrNull ??
        CollectionTypeCatalogConfig.defaults;
    final selectedTypeOption = collectionCatalog.optionFor(_collectionType);
    if (!_syncedProfileMomo && profile != null) {
      if (profile.momoNumber?.trim().isNotEmpty == true) {
        _receiverNumber.text = profile.momoNumber!;
      } else if (profile.momoPayCode?.trim().isNotEmpty == true) {
        _receiverMode = CollectMomoReceiverMode.momoPayCode;
        _receiverPayCode.text = profile.momoPayCode!;
      }
      _syncedProfileMomo = true;
    }
    final canCreate = canCreateGroupsOnThisPlatform();
    if (!canCreate) {
      return const SizedBox.shrink();
    }
    final liveRepository = ref.read(collectRepositoryProvider.notifier).isLive;
    if (liveRepository &&
        (_permissionChecking || _smsStatus?.enabled != true)) {
      return _buildSmsPermissionGate();
    }
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
            onPressed: _creating || !_canUsePrimaryAction
                ? null
                : _primaryAction,
            variant: CollectButtonVariant.primary,
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
        if (_step == 0) ...[
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
          ),
        ] else if (_step == 1) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              _CollectionTypeGrid(
                selected: _collectionType,
                options: collectionCatalog.types,
                onChanged: (type) => setState(() {
                  _collectionType = type;
                  _error = null;
                }),
              ),
            ],
          ),
        ] else if (_step == 2) ...[
          _MobileCreatePanel(
            error: _error,
            children: [
              CollectMomoReceiverCard(
                mode: _receiverMode,
                onChanged: (mode) => setState(() {
                  _receiverMode = mode;
                  _error = null;
                }),
                numberController: _receiverNumber,
                codeController: _receiverPayCode,
                numberInputLabel: 'Receiver MoMo',
                codeInputLabel: 'MoMo code',
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
                : () {
                    setState(() {
                      _groupImageBytes = null;
                      _groupImageName = null;
                      _groupImageMimeType = null;
                    });
                  },
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
        ] else ...[
          _CreateGroupReview(
            title: _title.text.trim(),
            description: _description.text.trim(),
            collectionTypeOption: selectedTypeOption,
            receiver: _receiverPreviewLabel,
            accentColor: _selectedAccentColor,
            hasPhoto: _groupImageBytes != null,
            isPublicRequested: _isPublicRequested,
            error: _error,
          ),
        ],
      ],
    );
  }

  Color get _selectedAccentColor {
    return CollectColors.brandPrimaryOptions
        .firstWhere(
          (option) => option.hex == _accentColorHex,
          orElse: () => CollectColors.brandPrimaryOptions.first,
        )
        .color;
  }

  bool get _canUsePrimaryAction {
    if (_creating) return false;
    return switch (_step) {
      0 => _title.text.trim().isNotEmpty,
      1 => true,
      2 => _normalizedReceiverValue().isNotEmpty,
      3 => true,
      _ =>
        _title.text.trim().isNotEmpty && _normalizedReceiverValue().isNotEmpty,
    };
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
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
      if (!mounted) return;
      setState(() {
        _error = 'Photo upload failed.';
      });
    }
  }

  Future<void> _primaryAction() async {
    if (_step == 0) {
      if (_title.text.trim().isEmpty) {
        setState(() => _error = 'Name required.');
        return;
      }
      setState(() {
        _step = 1;
        _error = null;
      });
      return;
    }
    if (_step == 1) {
      setState(() {
        _step = 2;
        _error = null;
      });
      return;
    }
    if (_step == 2) {
      if (_normalizedReceiverValue().isEmpty) {
        setState(() => _error = _receiverErrorMessage);
        return;
      }
      setState(() {
        _step = 3;
        _error = null;
      });
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
    final title = _title.text.trim();
    final receiver = _normalizedReceiverValue();
    if (title.isEmpty || receiver.isEmpty) {
      setState(() {
        _error = title.isEmpty ? 'Name required.' : _receiverErrorMessage;
      });
      return;
    }
    final repository = ref.read(collectRepositoryProvider.notifier);
    if (repository.isLive) {
      SmsAccessStatus status;
      try {
        status = await repository.refreshSmsAccessStatus();
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _error =
              'MoMo SMS access could not be verified. Check your connection.';
        });
        return;
      }
      if (!mounted) return;
      setState(() => _smsStatus = status);
      if (!status.enabled) {
        setState(() {
          _error = 'Enable MoMo SMS access before creating a group.';
        });
        return;
      }
    }
    try {
      setState(() {
        _creating = true;
        _error = null;
      });
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .createCollection(
            title: title,
            description: _description.text,
            collectionType: _collectionType,
            categorySubtype: _selectedTypeOption.defaultCategorySubtype,
            purposeLabel: _selectedTypeOption.defaultPurposeLabel,
            receiverMomoNumber: receiver,
            receiverLabel: _receiverDisplayLabel,
            receiverIsMomoPayCode:
                _receiverMode == CollectMomoReceiverMode.momoPayCode,
            accentColorHex: _accentColorHex,
            imageUrl: _selectedImageDataUri(),
            isPublic: _isPublicRequested,
          );
      if (!mounted) return;
      context.go('/groups/${collection.id}');
    } on PlayIntegrityUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = 'Could not create the group. Check the details and try again.';
      });
    }
  }

  String get _receiverDisplayLabel {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo code'
        : 'Primary MoMo receiver';
  }

  CollectionTypeCatalogItem get _selectedTypeOption {
    return (ref.read(collectCollectionTypeCatalogProvider).valueOrNull ??
            CollectionTypeCatalogConfig.defaults)
        .optionFor(_collectionType);
  }

  String get _receiverErrorMessage {
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? MomoReceiverNormalizer.payCodeErrorMessage
        : 'Use an MTN MoMo number.';
  }

  String get _receiverPreviewLabel {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    return _receiverMode == CollectMomoReceiverMode.momoPayCode
        ? 'MoMo code $value'
        : value;
  }

  String _normalizedReceiverValue() {
    final value = _activeReceiverController.text.trim();
    if (value.isEmpty) return '';
    if (_receiverMode == CollectMomoReceiverMode.momoPayCode) {
      return MomoReceiverNormalizer.tryNormalizePayCode(value) ?? '';
    }
    return PhoneNormalizer.tryNormalizeMtnMomoLocal(value) ?? '';
  }

  String? _selectedImageDataUri() {
    final bytes = _groupImageBytes;
    if (bytes == null || bytes.isEmpty) return null;
    final mimeType =
        _groupImageMimeType ??
        _mimeTypeFromName(_groupImageName ?? '') ??
        'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  Future<void> _refreshSmsPermission() async {
    final repository = ref.read(collectRepositoryProvider.notifier);
    if (!repository.isLive || _permissionChecking) return;
    setState(() {
      _permissionChecking = true;
      _permissionError = null;
    });
    try {
      final status = await repository.refreshSmsAccessStatus();
      if (!mounted) return;
      setState(() {
        _smsStatus = status;
        _permissionChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _permissionChecking = false;
        _permissionError =
            'MoMo SMS access could not be verified. Check your connection and try again.';
      });
    }
  }

  Widget _buildSmsPermissionGate() {
    final status = _smsStatus;
    final unavailable =
        status != null && (!status.supported || !status.declared);
    return ScreenScaffold(
      title: 'Create group',
      showHeader: false,
      children: [
        const CollectPlainPageHeader(title: 'Create group'),
        CollectCard(
          emphasis: CollectCardEmphasis.glow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                unavailable ? CollectIcons.info : CollectIcons.lock,
                size: 34,
              ),
              CollectSpacing.gap12,
              Text(
                _permissionChecking
                    ? 'Checking MoMo SMS access'
                    : unavailable
                    ? 'Group creation is unavailable in this build'
                    : 'Enable MoMo SMS access first',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              CollectSpacing.gap8,
              Text(
                _permissionError ??
                    (unavailable
                        ? 'Receiver mode is Android-only and requires the approved production SMS capability.'
                        : 'Collect captures new MoMo receipts on this Android device. The server-side OpenAI parser posts only one complete, high-confidence receipt that exactly matches a pending payer request. Collect never reads old messages or sends SMS.'),
              ),
              CollectSpacing.gap16,
              if (!_permissionChecking && !unavailable)
                CollectButton(
                  label: 'Review MoMo SMS access',
                  icon: CollectIcons.settings,
                  onPressed: () => context.push('/settings/permissions'),
                  expand: true,
                ),
              if (!_permissionChecking) ...[
                CollectSpacing.gap12,
                CollectButton(
                  label: 'Check again',
                  icon: Icons.refresh_rounded,
                  onPressed: _refreshSmsPermission,
                  variant: CollectButtonVariant.secondary,
                  expand: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
