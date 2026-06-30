import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/phone_normalizer.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _momoNumber = TextEditingController();
  final _momoPayCode = TextEditingController();
  CollectMomoReceiverMode _momoMode = CollectMomoReceiverMode.momoNumber;
  bool _synced = false;
  bool _syncingFields = false;
  bool _saving = false;
  bool _saved = false;
  String _initialMomoNumber = '';
  String _initialMomoPayCode = '';
  String? _error;

  TextEditingController get _activeMomoController {
    return _momoMode == CollectMomoReceiverMode.momoPayCode
        ? _momoPayCode
        : _momoNumber;
  }

  @override
  void initState() {
    super.initState();
    _momoNumber.addListener(_handleMomoEdited);
    _momoPayCode.addListener(_handleMomoEdited);
  }

  @override
  void dispose() {
    _momoNumber.removeListener(_handleMomoEdited);
    _momoPayCode.removeListener(_handleMomoEdited);
    _momoNumber.dispose();
    _momoPayCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(collectRepositoryProvider).currentProfile;
    if (!_synced && profile != null) {
      _syncingFields = true;
      if (profile.momoNumber?.trim().isNotEmpty == true) {
        _momoNumber.text =
            PhoneNormalizer.tryNormalizeMtnMomoLocal(profile.momoNumber!) ??
            profile.momoNumber!;
      }
      if (profile.momoPayCode?.trim().isNotEmpty == true) {
        _momoPayCode.text = profile.momoPayCode!;
        if (_momoNumber.text.trim().isEmpty) {
          _momoMode = CollectMomoReceiverMode.momoPayCode;
        }
      }
      _initialMomoNumber = _momoNumber.text.trim();
      _initialMomoPayCode = _momoPayCode.text.trim();
      _syncingFields = false;
      _synced = true;
    }
    return ScreenScaffold(
      title: 'Profile setup',
      showHeader: false,
      bottomAction: _bottomAction(context, profile),
      children: [
        const CollectPlainPageHeader(title: 'Profile setup'),
        if (profile == null)
          const MinimalStatePanel(
            icon: CollectIcons.profile,
            title: 'Sign in first.',
            message:
                'Collect creates your private 6-digit ID after WhatsApp verification.',
            tone: CollectStatusTone.warning,
          )
        else ...[
          if (_saved)
            const InfoSecurityBanner(
              title: 'Profile saved',
              message: 'Your MoMo details are saved.',
              tone: CollectStatusTone.success,
            ),
          _ProfileSetupPanel(
            errorTitle: 'Profile not saved',
            errorMessage: _error,
            children: [
              CollectMomoReceiverCard(
                mode: _momoMode,
                onChanged: (mode) => setState(() {
                  _momoMode = mode;
                  _error = null;
                }),
                numberController: _momoNumber,
                codeController: _momoPayCode,
                numberInputLabel: 'MoMo number',
                codeInputLabel: 'MoMo code',
              ),
            ],
          ),
          CollectIdDisplay(
            publicId: profile.publicId,
            onCopy: () => copyToClipboard(
              context,
              profile.publicId,
              message: 'Collect ID copied.',
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomAction(BuildContext context, CollectProfile? profile) {
    if (profile == null) {
      return BottomActionSurface(
        children: [
          CollectButton(
            label: 'Sign in',
            icon: CollectIcons.sms,
            onPressed: () => context.go('/auth'),
            expand: true,
          ),
        ],
      );
    }
    return BottomActionSurface(
      children: [
        CollectButton(
          label: _saving
              ? 'Saving'
              : _momoMode == CollectMomoReceiverMode.momoPayCode
              ? 'Save MoMo code'
              : 'Save MoMo number',
          icon: CollectIcons.check,
          onPressed: _canSaveMomo ? _saveMomoNumber : null,
          expand: true,
        ),
        CollectButton(
          label: 'Back to settings',
          icon: CollectIcons.chevron,
          onPressed: () => context.go('/settings'),
          variant: CollectButtonVariant.subtle,
          expand: true,
        ),
      ],
    );
  }

  void _handleMomoEdited() {
    if (_syncingFields || !mounted) return;
    setState(() {
      _saved = false;
      _error = null;
    });
  }

  bool get _hasMomoChanges {
    return _momoNumber.text.trim() != _initialMomoNumber ||
        _momoPayCode.text.trim() != _initialMomoPayCode;
  }

  bool get _activeMomoValueIsValid {
    final value = _activeMomoController.text.trim();
    if (value.isEmpty) return false;
    if (_momoMode == CollectMomoReceiverMode.momoPayCode) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      return digits.length >= 5 && digits.length <= 6;
    }
    return PhoneNormalizer.tryNormalizeMtnMomoLocal(value) != null;
  }

  bool get _canSaveMomo {
    return !_saving && _hasMomoChanges && _activeMomoValueIsValid;
  }

  Future<void> _saveMomoNumber() async {
    if (_activeMomoController.text.trim().isEmpty) {
      setState(
        () => _error = _momoMode == CollectMomoReceiverMode.momoPayCode
            ? 'Enter your MoMo code.'
            : 'Enter your MTN MoMo number.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repository = ref.read(collectRepositoryProvider.notifier);
      await repository.updateProfile(
        momoNumber: _momoNumber.text,
        momoPayCode: _momoPayCode.text,
      );
      if (!mounted) return;
      final pendingSlug = ref.read(pendingSharedGroupSlugProvider)?.trim();
      if (pendingSlug != null && pendingSlug.isNotEmpty) {
        final collection = await repository.joinGroupBySlug(pendingSlug);
        ref.read(pendingSharedGroupSlugProvider.notifier).state = null;
        if (!mounted) return;
        context.go('/groups/${collection.id}');
        return;
      }
      setState(() {
        _saved = true;
        _saving = false;
        _error = null;
        _initialMomoNumber = _momoNumber.text.trim();
        _initialMomoPayCode = _momoPayCode.text.trim();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _saving = false;
        });
      }
    }
  }
}

class _ProfileSetupPanel extends StatelessWidget {
  const _ProfileSetupPanel({
    required this.children,
    this.errorTitle,
    this.errorMessage,
  });

  final String? errorTitle;
  final String? errorMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap16,
          ],
          if (errorMessage != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: errorTitle ?? 'Action failed',
              message: errorMessage!,
              tone: CollectStatusTone.danger,
            ),
          ],
        ],
      ),
    );
  }
}
