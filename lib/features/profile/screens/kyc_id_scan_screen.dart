import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/kyc_id_scanner_overlay.dart';
import '../../../shared/widgets/tab_pill.dart';
import 'kyc_selfie_screen.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';

class KycIdScanScreen extends ConsumerStatefulWidget {
  const KycIdScanScreen({super.key});

  @override
  ConsumerState<KycIdScanScreen> createState() => _KycIdScanScreenState();
}

enum _KycStep { capture, processing, review }

class _KycIdScanScreenState extends ConsumerState<KycIdScanScreen> {
  final ImagePicker _picker = ImagePicker();

  _KycStep _step = _KycStep.capture;
  String _documentType = 'national_id';
  XFile? _frontImage;
  XFile? _backImage;
  XFile? _selfieImage;
  Map<String, Object?>? _extracted;
  String? _errorMessage;

  bool get _backImageRecommended => _documentType != 'passport';

  Future<void> _openScanner({required bool isFront}) async {
    final XFile? result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => KycIdScannerOverlay(
          title: isFront ? context.l10n.kycFrontOfId : context.l10n.kycBackOfId,
          instruction: isFront
              ? context.l10n.kycAlignFront(
                  _documentTypeLabel(context, _documentType),
                )
              : context.l10n.kycAlignBack(
                  _documentTypeLabel(context, _documentType),
                ),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (isFront) {
          _frontImage = result;
        } else {
          _backImage = result;
        }
        _errorMessage = null;
        _extracted = null;
      });
    }
  }

  Future<void> _takeSelfie() async {
    final XFile? result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const KycSelfieScreen()));

    if (result != null && mounted) {
      setState(() {
        _selfieImage = result;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickFromGallery({required bool isFront}) async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2200,
    );
    if (image == null || !mounted) {
      return;
    }

    setState(() {
      if (isFront) {
        _frontImage = image;
      } else {
        _backImage = image;
      }
      _errorMessage = null;
      _extracted = null;
    });
  }

  Future<void> _extractIdentity() async {
    if (_frontImage == null) {
      setState(() {
        _errorMessage = context.l10n.kycFrontIdFirst;
      });
      return;
    }
    if (_selfieImage == null) {
      setState(() {
        _errorMessage = context.l10n.kycSelfieForFaceMatch;
      });
      return;
    }

    setState(() {
      _step = _KycStep.processing;
      _errorMessage = null;
    });

    final frontBytes = await _frontImage!.readAsBytes();
    final selfieBytes = await _selfieImage!.readAsBytes();

    final result = await ref
        .read(authProvider.notifier)
        .submitKycDocument(
          documentType: _documentType,
          frontImageBase64: base64Encode(frontBytes),
          frontMimeType: _mimeTypeFor(_frontImage!),
          backImageBase64: _backImage == null
              ? null
              : base64Encode(await _backImage!.readAsBytes()),
          backMimeType: _backImage == null ? null : _mimeTypeFor(_backImage!),
        );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _step = _KycStep.capture;
        _errorMessage =
            ref.read(authProvider).error ?? context.l10n.kycExtractionFailed;
      });
      return;
    }

    // Perform Agentic Face Match
    final faceMatch = await ref
        .read(authProvider.notifier)
        .verifyFaceMatch(
          idImageBase64: base64Encode(frontBytes),
          selfieBase64: base64Encode(selfieBytes),
          idMimeType: _mimeTypeFor(_frontImage!),
          selfieMimeType: _mimeTypeFor(_selfieImage!),
        );

    if (!mounted) return;

    if (faceMatch == null || !faceMatch.isMatch) {
      setState(() {
        _step = _KycStep.capture;
        _errorMessage = faceMatch?.reason ?? context.l10n.kycIdentityMismatch;
      });
      return;
    }

    setState(() {
      _extracted = result.extracted;
      _step = _KycStep.review;
    });
  }

  void _resetCapture() {
    setState(() {
      _frontImage = null;
      _backImage = null;
      _selfieImage = null;
      _extracted = null;
      _errorMessage = null;
      _step = _KycStep.capture;
    });
  }

  String _mimeTypeFor(XFile file) {
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) {
      return 'image/png';
    }
    if (path.endsWith('.heic') || path.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        title: Text(
          context.l10n.personalInfo,
          style: theme.textTheme.titleLarge?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: CoolScreenBackground(
        showGlow: false,
        child: SafeArea(
          top: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_step) {
              _KycStep.capture => _buildCaptureView(),
              _KycStep.processing => _buildProcessingView(),
              _KycStep.review => _buildReviewView(),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCaptureView() {
    final user = ref.watch(authProvider).user;

    return SingleChildScrollView(
      key: const ValueKey('kyc-capture-view'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 140),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user != null && user.hasOfficialIdentity) ...[
            _CurrentIdentityCard(user: user),
            const SizedBox(height: 24),
          ],
          Text(
            context.l10n.kycChooseDocumentType,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final option in _documentTypeOptions)
                _DocumentTypeChip(
                  label: option.label,
                  selected: option.value == _documentType,
                  onTap: () {
                    setState(() {
                      _documentType = option.value;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 32),
          _DocumentInputCard(
            title: context.l10n.kycFrontOfId,
            image: _frontImage,
            onTakePhoto: () => _openScanner(isFront: true),
            onUpload: () => _pickFromGallery(isFront: true),
          ),
          const SizedBox(height: 16),
          _DocumentInputCard(
            title: _backImageRecommended
                ? context.l10n.kycBackOfId
                : context.l10n.kycBackOfDocument,
            image: _backImage,
            onTakePhoto: () => _openScanner(isFront: false),
            onUpload: () => _pickFromGallery(isFront: false),
          ),
          const SizedBox(height: 16),
          _DocumentInputCard(
            title: 'Live Selfie',
            image: _selfieImage,
            onTakePhoto: _takeSelfie,
            takePhotoLabel: 'Take selfie',
            onUpload: null,
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                final colors = context.coolSemanticColors;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(CoolRadii.lg),
                    border: Border.all(
                      color: colors.danger.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.danger,
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 18),
          CoolButton(
            label: context.l10n.kycIdentityVerification,
            icon: Icons.verified_user_rounded,
            onTap: _extractIdentity,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Center(
      key: const ValueKey('kyc-processing-view'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.chipSelectedBackground,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: CircularProgressIndicator(
                  color: colors.info,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              context.l10n.kycReadingId,
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.kycExtracting,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewView() {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final extracted = _extracted ?? const <String, Object?>{};
    final fullName = extracted['fullName']?.toString() ?? '';
    final dateOfBirth = extracted['dateOfBirth']?.toString();
    final nationalIdNumber = extracted['nationalIdNumber']?.toString();
    final documentType = extracted['documentType']?.toString();
    final gender = extracted['gender']?.toString();
    final nationality = extracted['nationality']?.toString();
    final confidence = extracted['confidence']?.toString();

    return SingleChildScrollView(
      key: const ValueKey('kyc-review-view'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoolCard(
            backgroundColor: colors.cardSurfaceStrong,
            borderColor: colors.borderStrong,
            useGradient: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.kycExtractedReady,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.l10n.kycAutoFilled,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ReviewField(label: 'Full name', value: fullName),
          if (dateOfBirth?.isNotEmpty == true)
            _ReviewField(label: 'Date of birth', value: dateOfBirth!),
          if (nationalIdNumber?.isNotEmpty == true)
            _ReviewField(label: 'Document number', value: nationalIdNumber!),
          if (documentType?.isNotEmpty == true)
            _ReviewField(label: 'Document type', value: documentType!),
          if (gender?.isNotEmpty == true)
            _ReviewField(label: 'Gender', value: gender!),
          if (nationality?.isNotEmpty == true)
            _ReviewField(label: 'Nationality', value: nationality!),
          if (confidence?.isNotEmpty == true)
            _ReviewField(label: 'OCR confidence', value: confidence!),
          const SizedBox(height: 18),
          CoolButton(
            label: 'Use extracted details',
            icon: Icons.check_circle_outline_rounded,
            onTap: () => context.pop(true),
          ),
          const SizedBox(height: 12),
          CoolButton(
            label: 'Scan again',
            variant: CoolButtonVariant.secondary,
            onTap: _resetCapture,
          ),
        ],
      ),
    );
  }
}

class _CurrentIdentityCard extends StatelessWidget {
  const _CurrentIdentityCard({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final trimmedNationalId = user.nationalIdNumber?.trim() ?? '';
    final details = <String>[
      if (user.kycDocumentType?.trim().isNotEmpty == true)
        _documentTypeLabel(context, user.kycDocumentType!),
      if (user.dateOfBirth?.trim().isNotEmpty == true)
        'DOB ${user.dateOfBirth!.trim()}',
      if (trimmedNationalId.isNotEmpty)
        'ID ••••${trimmedNationalId.substring(trimmedNationalId.length > 4 ? trimmedNationalId.length - 4 : 0)}',
    ];

    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.kycCurrentIdentity,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user.officialName?.trim().isNotEmpty == true
                ? user.officialName!.trim()
                : user.fullName,
            style: theme.textTheme.titleLarge?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentInputCard extends StatelessWidget {
  const _DocumentInputCard({
    required this.title,
    required this.onTakePhoto,
    required this.onUpload,
    this.image,
    this.takePhotoLabel = 'Take photo',
  });

  final String title;
  final XFile? image;
  final VoidCallback onTakePhoto;
  final VoidCallback? onUpload;
  final String takePhotoLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return CoolCard(
      backgroundColor: colors.cardSurfaceStrong,
      borderColor: colors.borderStrong,
      borderRadius: CoolRadii.xxl,
      useGradient: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontSize: 18),
          ),
          const SizedBox(height: 16),

          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1.58,
                child: Image.file(File(image!.path), fit: BoxFit.cover),
              ),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: colors.inputSurface,
                borderRadius: BorderRadius.circular(CoolRadii.xl),
                border: Border.all(color: colors.border, width: 1.2),
              ),
              child: Center(
                child: Text(
                  context.l10n.kycNoImageYet,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: takePhotoLabel,
                  variant: CoolButtonVariant.secondary,
                  icon: Icons.camera_alt_outlined,
                  onTap: onTakePhoto,
                ),
              ),
              if (onUpload != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: CoolButton(
                    label: 'Upload',
                    variant: CoolButtonVariant.secondary,
                    icon: Icons.upload_file_outlined,
                    onTap: onUpload,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong,
        borderRadius: BorderRadius.circular(CoolRadii.xl),
        border: Border.all(color: colors.border, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.tertiaryText,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTypeChip extends StatelessWidget {
  const _DocumentTypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TabPill(label: label, isActive: selected, onTap: onTap);
  }
}

class _DocumentTypeOption {
  const _DocumentTypeOption({required this.value, required this.label});

  final String value;
  final String label;
}

const _documentTypeOptions = <_DocumentTypeOption>[
  _DocumentTypeOption(value: 'national_id', label: 'National ID'),
  _DocumentTypeOption(value: 'passport', label: 'Passport'),
  _DocumentTypeOption(value: 'driving_license', label: 'Driving licence'),
];

String _documentTypeLabel(BuildContext context, String value) {
  return switch (value.trim().toLowerCase()) {
    'national_id' => context.l10n.kycNationalId,
    'passport' => context.l10n.kycPassport,
    'driving_license' => context.l10n.kycDrivingLicence,
    _ => 'your ID',
  };
}
