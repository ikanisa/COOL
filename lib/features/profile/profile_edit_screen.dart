import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/payments/rwanda_momo_number.dart';
import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/collect_components.dart';
import '../auth/widgets/auth_screen_widgets.dart';

part 'profile_edit_widgets.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _momoNumber = TextEditingController();
  final _revolutAccount = TextEditingController();
  Country? _selectedCountry;
  String? _hydratedProfileId;
  String? _error;
  CollectProfile? _savedProfile;
  final _scrollController = ScrollController();
  bool _dirty = false;
  bool _hydrating = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _momoNumber.addListener(_markDirty);
    _revolutAccount.addListener(_markDirty);
    _hydrate(ref.read(collectRepositoryProvider).currentProfile);
  }

  @override
  void dispose() {
    _momoNumber.removeListener(_markDirty);
    _revolutAccount.removeListener(_markDirty);
    _momoNumber.dispose();
    _revolutAccount.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(collectRepositoryProvider);
    final profile = state.currentProfile;
    ref.listen<CollectProfile?>(
      collectRepositoryProvider.select((state) => state.currentProfile),
      (_, next) {
        if (next == null || _saving || _dirty) return;
        setState(() => _hydrate(next));
      },
    );

    final selectedCountry =
        _selectedCountry ??
        Country.tryParse(profile?.countryCode ?? '') ??
        Country.parse('RW');
    final isRwanda = selectedCountry.countryCode == 'RW';
    final currencyCode = CollectProfileCountryRules.currencyForCountry(
      selectedCountry.countryCode,
    );

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
              child: Column(
                key: const ValueKey('native_profile_editor'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ProfileAppBar(onBack: _saving ? null : _leave),
                  Expanded(
                    child: profile == null
                        ? Center(
                            child: state.isLoading
                                ? const CircularProgressIndicator(
                                    semanticsLabel: 'Loading profile',
                                  )
                                : const Text('Sign in to edit your profile'),
                          )
                        : ListView(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(
                              CollectSpacing.x5,
                              CollectSpacing.x3,
                              CollectSpacing.x5,
                              CollectSpacing.x6,
                            ),
                            children: [
                              _ProfileIdentity(publicId: profile.publicId),
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
                                currencyCode: currencyCode,
                                whatsappPhone: profile.whatsappPhone,
                                onCountryTap: _saving
                                    ? null
                                    : _showCountryPicker,
                              ),
                              CollectSpacing.gap12,
                              if (isRwanda) ...[
                                _ProfileInput(
                                  key: const ValueKey(
                                    'profile_momo_number_input',
                                  ),
                                  controller: _momoNumber,
                                  label: 'MoMo number',
                                  enabled: !_saving,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitIfChanged(),
                                ),
                              ] else ...[
                                _ProfileInput(
                                  key: const ValueKey(
                                    'profile_revolut_account_input',
                                  ),
                                  controller: _revolutAccount,
                                  label: 'Account number',
                                  enabled: !_saving,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submitIfChanged(),
                                ),
                              ],
                            ],
                          ),
                  ),
                  Padding(
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
                  ),
                ],
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
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        animationStyle: CollectMotion.animationStyle(context),
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    if (mounted) {
      setState(() => _dirty = false);
      context.go('/settings');
    }
  }

  void _hydrate(CollectProfile? profile) {
    if (profile == null || profile.id == _hydratedProfileId) return;
    _hydrating = true;
    _savedProfile = profile;
    _hydratedProfileId = profile.id;
    _momoNumber.text = profile.momoNumber;
    _revolutAccount.text = profile.revolutAccount;
    _selectedCountry =
        Country.tryParse(profile.countryCode) ??
        Country.parse(
          CollectProfileCountryRules.inferCountryCodeFromPhone(
            profile.whatsappPhone,
          ),
        );
    _dirty = false;
    _hydrating = false;
  }

  void _markDirty() {
    final saved = _savedProfile;
    if (_hydrating || !mounted || saved == null) return;
    setState(() {
      final countryCode = _selectedCountry?.countryCode;
      _dirty =
          countryCode != saved.countryCode ||
          (countryCode == 'RW'
              ? _momoNumber.text != saved.momoNumber
              : _revolutAccount.text != saved.revolutAccount);
      _error = null;
    });
  }

  Future<void> _showCountryPicker() async {
    final country = await showCollectCountryPicker(context);
    if (!mounted || country == null) return;
    _selectedCountry = country;
    _markDirty();
  }

  Future<void> _save() async {
    final selectedCountry = _selectedCountry;
    if (_saving || selectedCountry == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final momo = selectedCountry.countryCode == 'RW'
          ? RwandaMomoNumber.parse(_momoNumber.text)
          : null;
      final updated = await ref
          .read(collectRepositoryProvider.notifier)
          .updateCurrentProfile(
            countryCode: selectedCountry.countryCode,
            momoProvider: momo?.provider,
            momoNumber: momo?.localNumber,
            revolutAccount: _revolutAccount.text,
          );
      if (!mounted) return;
      _hydratedProfileId = null;
      setState(() {
        _hydrate(updated);
        _saving = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile saved.')));
    } catch (error) {
      if (!mounted) return;
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
