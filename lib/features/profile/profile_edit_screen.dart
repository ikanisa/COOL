import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/rwanda_momo_number.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';

part 'profile_edit_widgets.dart';

class ProfileEditScreen extends ConsumerWidget {
  const ProfileEditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(collectRepositoryProvider.notifier);
    final scope = ref.watch(
      collectRepositoryProvider.select(
        (state) => (
          repository,
          repository.sessionGeneration,
          state.currentProfile?.id,
        ),
      ),
    );
    // Controllers, drafts and their notifications belong to one authenticated
    // session, even when the replacement session belongs to the same user.
    return ScaffoldMessenger(
      key: ValueKey(scope),
      child: const _ProfileEditor(),
    );
  }
}

class _ProfileEditor extends ConsumerStatefulWidget {
  const _ProfileEditor();

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  final _momoNumber = TextEditingController();
  final _momoPayCode = TextEditingController();
  late final CollectRepository _scopeRepository;
  late final int _scopeGeneration;
  late final String? _scopeProfileId;
  int _saveRevision = 0;
  String? _error;
  CollectProfile? _savedProfile;
  final _scrollController = ScrollController();
  bool _dirty = false;
  bool _hydrating = false;
  bool _saving = false;
  bool _showMomoCode = false;

  @override
  void initState() {
    super.initState();
    _scopeRepository = ref.read(collectRepositoryProvider.notifier);
    _scopeGeneration = _scopeRepository.sessionGeneration;
    _scopeProfileId = ref.read(collectRepositoryProvider).currentProfile?.id;
    _momoNumber.addListener(_markDirty);
    _momoPayCode.addListener(_markDirty);
    _hydrate(ref.read(collectRepositoryProvider).currentProfile);
  }

  @override
  void dispose() {
    ++_saveRevision;
    _momoNumber.removeListener(_markDirty);
    _momoPayCode.removeListener(_markDirty);
    _momoNumber.dispose();
    _momoPayCode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final profile = _scopeIsCurrent ? state.currentProfile : null;
    ref.listen<CollectProfile?>(
      collectRepositoryProvider.select((state) => state.currentProfile),
      (_, next) {
        if (next == null || _saving || _dirty || !_scopeIsCurrent) return;
        setState(() => _hydrate(next));
      },
    );

    final selectedCountry = Country.parse('RW');

    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
      },
      child: Scaffold(
        backgroundColor: context.collectColors.canvas,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scale = MediaQuery.textScalerOf(
                    context,
                  ).scale(1).clamp(1.0, 1.5);
                  final scrollChrome = constraints.maxHeight < 320 * scale;
                  final header = _ProfileAppBar(
                    onBack: _saving ? null : _leave,
                  );
                  final action = Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CollectSpacing.x5,
                      CollectSpacing.x3,
                      CollectSpacing.x5,
                      CollectSpacing.x4,
                    ),
                    child: CollectButton(
                      key: const ValueKey('profile_save_button'),
                      label: profile == null
                          ? 'Sign in'
                          : (_saving ? 'Saving…' : 'Save'),
                      onPressed: profile == null
                          ? (state.isLoading ? null : () => context.go('/auth'))
                          : (_saving || !_dirty ? null : _save),
                      expand: true,
                    ),
                  );
                  return Column(
                    key: const ValueKey('native_profile_editor'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!scrollChrome) header,
                      Expanded(
                        // Retain the same viewport and keyed fields when the
                        // keyboard or rotation moves the chrome into the form.
                        key: const ValueKey('profile_form_viewport'),
                        child: CustomScrollView(
                          controller: _scrollController,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.manual,
                          slivers: [
                            if (scrollChrome) SliverToBoxAdapter(child: header),
                            if (profile == null)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: state.isLoading
                                      ? const CircularProgressIndicator(
                                          semanticsLabel: 'Loading profile',
                                        )
                                      : const Text(
                                          'Sign in to edit your profile',
                                        ),
                                ),
                              )
                            else
                              SliverPadding(
                                key: const ValueKey('profile_form_fields'),
                                padding: const EdgeInsets.fromLTRB(
                                  CollectSpacing.x5,
                                  CollectSpacing.x3,
                                  CollectSpacing.x5,
                                  CollectSpacing.x6,
                                ),
                                sliver: SliverList.list(
                                  children: [
                                    _ProfileIdentity(
                                      publicId: profile.publicId,
                                    ),
                                    CollectSpacing.gap24,
                                    if (_error != null) ...[
                                      Semantics(
                                        liveRegion: true,
                                        child: Text(
                                          _error!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: context
                                                    .collectColors
                                                    .dangerForeground,
                                              ),
                                        ),
                                      ),
                                      CollectSpacing.gap16,
                                    ],
                                    _ProfileDetails(
                                      country: selectedCountry,
                                      currencyCode: 'RWF',
                                      whatsappPhone: profile.whatsappPhone,
                                    ),
                                    CollectSpacing.gap12,
                                    ...[
                                      _ProfileMomoSwitcher(
                                        showCode: _showMomoCode,
                                        enabled: !_saving,
                                        onChanged: (showCode) {
                                          FocusManager.instance.primaryFocus
                                              ?.unfocus();
                                          setState(
                                            () => _showMomoCode = showCode,
                                          );
                                        },
                                      ),
                                      CollectSpacing.gap12,
                                      if (_showMomoCode) ...[
                                        _ProfileInput(
                                          key: const ValueKey(
                                            'profile_momo_code_input',
                                          ),
                                          controller: _momoPayCode,
                                          label: 'MoMo code, optional',
                                          enabled: !_saving,
                                          keyboardType: TextInputType.number,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) =>
                                              _submitIfChanged(),
                                        ),
                                        CollectSpacing.gap8,
                                        Text(
                                          'Add a merchant code alongside your MoMo number.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: context
                                                    .collectColors
                                                    .textSecondary,
                                              ),
                                        ),
                                      ] else
                                        _ProfileInput(
                                          key: const ValueKey(
                                            'profile_momo_number_input',
                                          ),
                                          controller: _momoNumber,
                                          label: 'MoMo number',
                                          enabled: !_saving,
                                          keyboardType: TextInputType.phone,
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) =>
                                              _submitIfChanged(),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            if (scrollChrome) SliverToBoxAdapter(child: action),
                          ],
                        ),
                      ),
                      if (!scrollChrome) action,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submitIfChanged() {
    if (_dirty && !_saving) _save();
  }

  Future<void> _leave() async {
    if (_saving || !_scopeIsCurrent) return;
    if (_dirty) {
      final discard = await showCollectConfirmationSheet(
        context: context,
        title: 'Discard changes?',
        message: 'Your unsaved profile changes will be lost.',
        cancelLabel: 'Keep editing',
        confirmLabel: 'Discard',
        destructive: true,
      );
      if (!mounted || !_scopeIsCurrent || discard != true) return;
    }
    if (mounted && _scopeIsCurrent) {
      setState(() => _dirty = false);
      context.go('/settings');
    }
  }

  bool get _scopeIsCurrent =>
      mounted &&
      identical(
        ref.read(collectRepositoryProvider.notifier),
        _scopeRepository,
      ) &&
      _scopeRepository.sessionGeneration == _scopeGeneration &&
      ref.read(collectRepositoryProvider).currentProfile?.id == _scopeProfileId;

  void _hydrate(CollectProfile? profile) {
    if (profile == null || profile.id != _scopeProfileId || !_scopeIsCurrent) {
      return;
    }
    _hydrating = true;
    _savedProfile = profile;
    _momoNumber.text = profile.momoNumber;
    _momoPayCode.text = profile.momoPayCode;
    _dirty = false;
    _hydrating = false;
  }

  void _markDirty() {
    final saved = _savedProfile;
    if (_hydrating || !_scopeIsCurrent || saved == null) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _dirty =
          _momoNumber.text != saved.momoNumber ||
          _momoPayCode.text != saved.momoPayCode;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _scopeProfileId == null || !_scopeIsCurrent) return;
    final revision = ++_saveRevision;
    bool current() => revision == _saveRevision && _scopeIsCurrent;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final momo = RwandaMomoNumber.parse(_momoNumber.text);
      if (!current()) return;
      final updated = await _scopeRepository.updateCurrentProfile(
        countryCode: 'RW',
        momoProvider: momo.provider,
        momoNumber: momo.localNumber,
        momoPayCode: _momoPayCode.text,
      );
      if (!mounted || !current()) return;
      if (updated.id != _scopeProfileId) {
        throw const FormatException('Updated profile identity is invalid.');
      }
      setState(() {
        _hydrate(updated);
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (error) {
      if (!current()) return;
      setState(() {
        _saving = false;
        _error = _safeProfileError(error);
      });
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    }
  }

  String _safeProfileError(Object error) {
    if (error is FormatException) return error.message.toString();
    final text = error.toString().toLowerCase();
    if (text.contains('network') ||
        text.contains('socket') ||
        text.contains('connection')) {
      return 'Check your connection and try saving again.';
    }
    return 'Your profile could not be saved. Try again.';
  }
}
