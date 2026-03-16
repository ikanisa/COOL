import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
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
  Map<String, Object?>? _extracted;
  String? _errorMessage;

  bool get _backImageRecommended => _documentType != 'passport';

  Future<void> _pickImage({
    required bool isFront,
    required ImageSource source,
  }) async {
    final image = await _picker.pickImage(
      source: source,
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
      _step = _KycStep.capture;
    });
  }

  Future<void> _extractIdentity() async {
    if (_frontImage == null) {
      setState(() {
        _errorMessage = 'Add front ID first';
      });
      return;
    }

    setState(() {
      _step = _KycStep.processing;
      _errorMessage = null;
    });

    final result = await ref
        .read(authProvider.notifier)
        .submitKycDocument(
          documentType: _documentType,
          frontImageBase64: base64Encode(await _frontImage!.readAsBytes()),
          frontMimeType: _mimeTypeFor(_frontImage!),
          backImageBase64: _backImage == null
              ? null
              : base64Encode(await _backImage!.readAsBytes()),
          backMimeType: _backImage == null ? null : _mimeTypeFor(_backImage!),
        );

    if (!mounted) {
      return;
    }

    if (result == null) {
      setState(() {
        _step = _KycStep.capture;
        _errorMessage =
            ref.read(authProvider).error ??
            'Extraction failed';
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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(
          'Personal Info',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: CoolScreenBackground(
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user != null && user.hasOfficialIdentity) ...[
            _CurrentIdentityCard(user: user),
            const SizedBox(height: 16),
          ],
          Text(
            'Choose document type',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
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
          const SizedBox(height: 18),
          _DocumentInputCard(
            title: 'Front of ID',
            image: _frontImage,
            onTakePhoto: () =>
                _pickImage(isFront: true, source: ImageSource.camera),
            onUpload: () =>
                _pickImage(isFront: true, source: ImageSource.gallery),
          ),
          const SizedBox(height: 14),
          _DocumentInputCard(
            title: _backImageRecommended ? 'Back of ID' : 'Back of document',
            image: _backImage,
            onTakePhoto: () =>
                _pickImage(isFront: false, source: ImageSource.camera),
            onUpload: () =>
                _pickImage(isFront: false, source: ImageSource.gallery),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.red.withValues(alpha: 0.18),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.red,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          CoolButton(
            label: 'Submit',
            icon: Icons.auto_awesome_outlined,
            onTap: _extractIdentity,
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingView() {
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
              decoration: const BoxDecoration(
                color: AppColors.blueGlow,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: CircularProgressIndicator(
                  color: AppColors.blue,
                  strokeWidth: 3,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Reading your ID',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cool is extracting your',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewView() {
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentGlow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Extracted profile ready',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cool has already filled',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
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

class _IdentityHeroCard extends StatelessWidget {
  const _IdentityHeroCard({required this.documentType});

  final String documentType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.blueGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'No manual typing',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Scan ${_documentTypeLabel(documentType)} to fill',
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Cool extracts your full',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
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
    final trimmedNationalId = user.nationalIdNumber?.trim() ?? '';
    final details = <String>[
      if (user.kycDocumentType?.trim().isNotEmpty == true)
        _documentTypeLabel(user.kycDocumentType!),
      if (user.dateOfBirth?.trim().isNotEmpty == true)
        'DOB ${user.dateOfBirth!.trim()}',
      if (trimmedNationalId.isNotEmpty)
        'ID ••••${trimmedNationalId.substring(trimmedNationalId.length > 4 ? trimmedNationalId.length - 4 : 0)}',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current identity on file',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            user.officialName?.trim().isNotEmpty == true
                ? user.officialName!.trim()
                : user.fullName,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              details.join(' · '),
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
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
  });

  final String title;
  final XFile? image;
  final VoidCallback onTakePhoto;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),

          if (image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 1.58,
                child: Image.file(File(image!.path), fit: BoxFit.cover),
              ),
            )
          else
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  'No image yet',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text3,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: CoolButton(
                  label: 'Take photo',
                  variant: CoolButtonVariant.secondary,
                  icon: Icons.camera_alt_outlined,
                  onTap: onTakePhoto,
                ),
              ),
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.blueGlow : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.blue : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.blue : AppColors.text2,
          ),
        ),
      ),
    );
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
  _DocumentTypeOption(value: 'residence_permit', label: 'Residence permit'),
];

String _documentTypeLabel(String value) {
  return switch (value.trim().toLowerCase()) {
    'national_id' => 'National ID',
    'passport' => 'Passport',
    'driving_license' => 'Driving licence',
    'residence_permit' => 'Residence permit',
    _ => 'your ID',
  };
}
