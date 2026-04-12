import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/providers/app_access_provider.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/services/app_access_service.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/utils/money_formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../../momo/services/nfc_hce_service.dart';
import '../../momo/services/nfc_service.dart';
import '../models/biopay_profile.dart';
import '../providers/biopay_providers.dart';
import '../widgets/biopay_surface.dart';

class BiopayNfcScreen extends ConsumerStatefulWidget {
  const BiopayNfcScreen({super.key});

  @override
  ConsumerState<BiopayNfcScreen> createState() => _BiopayNfcScreenState();
}

class _BiopayNfcScreenState extends ConsumerState<BiopayNfcScreen>
    with WidgetsBindingObserver {
  late final AppAccessService _appAccessService = ref.read(
    appAccessServiceProvider,
  );
  final _nfcHceService = NfcHceService.instance;
  late final TextEditingController _numberController;
  late final TextEditingController _codeController;
  late final TextEditingController _amountController;

  AppAccessSnapshot? _nfcAccess;
  bool _refreshOnResume = false;
  bool _isActivating = false;
  bool _supportsPhoneTap = false;
  bool _isReceiveModeActive = false;
  MomoRecipientType _selectedType = MomoRecipientType.phoneNumber;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _numberController = TextEditingController();
    _codeController = TextEditingController();
    _amountController = TextEditingController(text: '0');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNfcAccess();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _numberController.dispose();
    _codeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_refreshOnResume) {
      return;
    }
    _refreshOnResume = false;
    _refreshNfcAccess();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.coolSemanticColors;
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final profile = ref.watch(biopayProfileProvider).valueOrNull;
    final country = _resolveCountry(user, profile);
    final supportsCode = country.supportsMomoCode;

    _seedControllers(user: user, profile: profile, country: country);
    final nfcNotAvailable = _nfcAccess?.kind == AppAccessStateKind.notAvailable;

    return BiopayLightScaffold(
      topPadding: CoolSpace.x2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BiopayTopBar(
            title: l10n.biopayNfcPaymentTitle,
            onBack: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(AppRoutes.biopayHome);
            },
          ),
          const SizedBox(height: CoolSpace.x6),
          if (supportsCode) ...[
            BiopaySegmentedControl(
              labels: [l10n.biopayTabNumber, l10n.biopayTabCode],
              selectedIndex: _selectedType == MomoRecipientType.phoneNumber
                  ? 0
                  : 1,
              onSelected: (index) {
                setState(() {
                  _selectedType = index == 0
                      ? MomoRecipientType.phoneNumber
                      : MomoRecipientType.code;
                });
              },
            ),
            const SizedBox(height: CoolSpace.x4),
          ],
          _NfcInputCard(
            semanticLabel: _selectedType == MomoRecipientType.code
                ? l10n.merchantCode
                : l10n.biopayMomoNumberLabel,
            child: TextField(
              controller: _selectedType == MomoRecipientType.code
                  ? _codeController
                  : _numberController,
              keyboardType: TextInputType.number,
              style: context.coolText.headline(
                Theme.of(context).textTheme.displaySmall,
                color: colors.primaryText,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.4,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                isDense: true,
                filled: false,
                fillColor: Colors.transparent,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                hintText: '',
                hintStyle: context.coolText.mobiLabel(
                  color: colors.tertiaryText,
                ),
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          BiopayFieldLabel(label: l10n.biopayAmountOptionalLabel),
          const SizedBox(height: CoolSpace.x3),
          BiopaySectionCard(
            height: 178,
            child: Row(
              children: [
                Text(
                  '${country.currencyCode} ',
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.headlineMedium,
                    color: colors.tertiaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.0,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [GroupedThousandsInputFormatter()],
                    style: context.coolText.headline(
                      Theme.of(context).textTheme.displaySmall,
                      color: colors.primaryText,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.4,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      isDense: true,
                      filled: false,
                      fillColor: Colors.transparent,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      hintText: l10n.biopayZeroAmountHint,
                      hintStyle: context.coolText.mobiLabel(
                        color: colors.tertiaryText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_nfcAccess != null && !_nfcAccess!.isReady) ...[
            const SizedBox(height: CoolSpace.x4),
            _NfcStatusBanner(
              text: _nfcAccess!.kind == AppAccessStateKind.disabledInApp
                  ? l10n.biopayNfcOffInApp
                  : _nfcAccess!.kind == AppAccessStateKind.serviceDisabled
                  ? l10n.biopayTurnOnNfcInSettings
                  : l10n.biopayNfcUnavailableOnDevice,
              color: _nfcAccess!.kind == AppAccessStateKind.notAvailable
                  ? colors.danger
                  : colors.warning,
            ),
          ] else if (_isReceiveModeActive) ...[
            const SizedBox(height: CoolSpace.x4),
            _NfcStatusBanner(
              text: l10n.biopayNfcReadyForNextTap,
              color: colors.success,
            ),
          ],
          const SizedBox(height: CoolSpace.x7),
          BiopayPrimaryButton(
            label: nfcNotAvailable
                ? l10n.biopayNfcNotAvailableButton
                : l10n.biopayActivateNfc,
            icon: CoolIcons.nfc,
            isLoading: _isActivating,
            onTap: nfcNotAvailable ? null : () => _activateNfc(country),
          ),
          if (_isReceiveModeActive) ...[
            const SizedBox(height: CoolSpace.x4),
            TextButton(
              onPressed: _isActivating ? null : _deactivateNfc,
              child: Text(
                l10n.biopayStopNfc,
                style: context.coolText.headline(
                  Theme.of(context).textTheme.titleLarge,
                  color: colors.secondaryText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshNfcAccess() async {
    final snapshot = await _appAccessService.getSnapshot(
      AppAccessPermission.nfc,
    );
    final supportsPhoneTap = await _nfcHceService.isSupported();
    final isReceiveModeActive = supportsPhoneTap
        ? await _nfcHceService.isPaymentRequestActive()
        : false;
    if (!mounted) {
      return;
    }
    setState(() {
      _nfcAccess = snapshot;
      _supportsPhoneTap = supportsPhoneTap;
      _isReceiveModeActive = isReceiveModeActive;
    });
  }

  void _seedControllers({
    required UserProfile? user,
    required BiopayProfile? profile,
    required CoolCountry country,
  }) {
    if (_numberController.text.trim().isEmpty) {
      final raw = profile?.routeType == MomoRecipientType.phoneNumber
          ? profile?.recipientValue
          : user?.momoNumber;
      if ((raw ?? '').trim().isNotEmpty) {
        try {
          _numberController.text = country.normalizeNationalPhone(raw!);
        } catch (_) {
          _numberController.text = raw!;
        }
      }
    }
    if (_codeController.text.trim().isEmpty) {
      final raw = profile?.routeType == MomoRecipientType.code
          ? profile?.recipientValue
          : user?.momoCode;
      if ((raw ?? '').trim().isNotEmpty) {
        _codeController.text = raw!;
        _selectedType = MomoRecipientType.code;
      }
    }
  }

  CoolCountry _resolveCountry(UserProfile? user, BiopayProfile? profile) {
    final countryCode =
        profile?.countryCode.trim() ??
        user?.country.trim() ??
        AppMarket.country.isoCode;
    return CoolCountryCatalog.byIsoCode(countryCode) ?? AppMarket.country;
  }

  Future<void> _activateNfc(CoolCountry country) async {
    if (_isActivating) {
      return;
    }

    final rawRecipient = _selectedType == MomoRecipientType.code
        ? _codeController.text.trim()
        : _numberController.text.trim();
    if (rawRecipient.isEmpty) {
      CoolToast.error(
        context,
        _selectedType == MomoRecipientType.code
            ? context.l10n.biopayEnterMerchantCode
            : context.l10n.biopayEnterMomoNumber,
      );
      return;
    }

    setState(() => _isActivating = true);
    try {
      var snapshot = _nfcAccess;
      if (snapshot == null || !snapshot.isReady) {
        snapshot = await _appAccessService.enableAndRequest(
          AppAccessPermission.nfc,
        );
        if (!mounted) {
          return;
        }
        setState(() => _nfcAccess = snapshot);
      }

      if (snapshot.isReady != true) {
        if (snapshot.kind == AppAccessStateKind.serviceDisabled) {
          _refreshOnResume = true;
          await _appAccessService.openSystemSettings(AppAccessPermission.nfc);
        }
        return;
      }

      final normalizedRecipient = _selectedType == MomoRecipientType.code
          ? country.normalizeMerchantCode(rawRecipient)
          : country.normalizeNationalPhone(rawRecipient);
      final amount = _amountController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final payload = NfcPaymentPayload(
        recipientValue: normalizedRecipient,
        amount: amount.isEmpty ? '0' : amount,
        recipientType: _selectedType,
        countryCode: country.isoCode,
      );

      if (_supportsPhoneTap) {
        await _nfcHceService.startPaymentRequest(
          uri: payload.toUssdUri() ?? payload.toDeepLinkUri(),
        );
      } else if (!kIsWeb && Platform.isAndroid) {
        await NfcService.writeTag(
          recipientValue: normalizedRecipient,
          amount: payload.amount,
          recipientType: _selectedType,
          countryCode: country.isoCode,
        );
      } else {
        throw UnsupportedError(context.l10n.biopayNfcActivationUnavailable);
      }

      if (!mounted) {
        return;
      }
      await _refreshNfcAccess();
      if (!mounted) {
        return;
      }
      // Navigate to the "Tap to Pay" waiting screen.
      context.push(AppRoutes.biopayNfcTap);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, describeUserFacingError(error));
    } finally {
      if (mounted) {
        setState(() => _isActivating = false);
      }
    }
  }

  Future<void> _deactivateNfc() async {
    setState(() => _isActivating = true);
    try {
      await _nfcHceService.stopPaymentRequest();
      if (!mounted) {
        return;
      }
      await _refreshNfcAccess();
      if (!mounted) {
        return;
      }
      CoolToast.success(context, context.l10n.biopayNfcStopped);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, describeUserFacingError(error));
    } finally {
      if (mounted) {
        setState(() => _isActivating = false);
      }
    }
  }
}

class _NfcInputCard extends StatelessWidget {
  const _NfcInputCard({required this.semanticLabel, required this.child});

  final String semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BiopaySectionCard(
      height: 126,
      child: Semantics(
        label: semanticLabel,
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }
}

class _NfcStatusBanner extends StatelessWidget {
  const _NfcStatusBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: CoolSpace.x4,
        vertical: CoolSpace.x3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
      ),
      child: Text(
        text,
        style: context.coolText.mono(
          Theme.of(context).textTheme.bodyMedium,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
