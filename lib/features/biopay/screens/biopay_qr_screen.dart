import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_market.dart';
import '../../../core/config/country_catalog.dart';
import '../../../core/models/momo_qr_payload.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/biopay_profile.dart';
import '../providers/biopay_providers.dart';
import '../widgets/biopay_surface.dart';

class BiopayQrScreen extends ConsumerStatefulWidget {
  const BiopayQrScreen({super.key});

  @override
  ConsumerState<BiopayQrScreen> createState() => _BiopayQrScreenState();
}

class _BiopayQrScreenState extends ConsumerState<BiopayQrScreen> {
  late final TextEditingController _numberController;
  late final TextEditingController _codeController;
  late final TextEditingController _amountController;
  MomoRecipientType _selectedType = MomoRecipientType.phoneNumber;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController();
    _codeController = TextEditingController();
    _amountController = TextEditingController(text: '12,356');
  }

  @override
  void dispose() {
    _numberController.dispose();
    _codeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;
    final profile = ref.watch(biopayProfileProvider).valueOrNull;
    final country = _resolveCountry(user, profile);
    final supportsCode = country.supportsMomoCode;

    _seedControllers(user: user, profile: profile, country: country);

    return BiopayLightScaffold(
      topPadding: CoolSpace.x2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BiopayTopBar(
            title: 'Get QR Code',
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
              labels: const ['Number', 'Code'],
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
          _InputCard(
            label: _selectedType == MomoRecipientType.code
                ? 'Merchant Code'
                : 'MoMo Number',
            child: TextField(
              controller: _selectedType == MomoRecipientType.code
                  ? _codeController
                  : _numberController,
              keyboardType: TextInputType.number,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: BiopaySurfaceColors.text,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.4,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '',
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          const BiopayFieldLabel(label: 'Amount (Optional)'),
          const SizedBox(height: CoolSpace.x3),
          BiopaySectionCard(
            height: 178,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${country.currencyCode} ',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: BiopaySurfaceColors.surfaceStrong,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.0,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: BiopaySurfaceColors.text,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.4,
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '0',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: CoolSpace.x7),
          BiopayPrimaryButton(
            label: 'Generate QR Code',
            icon: Icons.qr_code_2_rounded,
            backgroundColor: BiopaySurfaceColors.deep,
            onTap: () => _showQrPreview(context, country),
          ),
        ],
      ),
    );
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

  void _showQrPreview(BuildContext context, CoolCountry country) {
    final rawRecipient = _selectedType == MomoRecipientType.code
        ? _codeController.text.trim()
        : _numberController.text.trim();
    if (rawRecipient.isEmpty) {
      CoolToast.error(
        context,
        _selectedType == MomoRecipientType.code
            ? 'Enter a merchant code'
            : 'Enter a MoMo number',
      );
      return;
    }

    final normalizedRecipient = _selectedType == MomoRecipientType.code
        ? country.normalizeMerchantCode(rawRecipient)
        : country.buildE164Phone(rawRecipient);
    final amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );

    final payload = amount != null && amount > 0
        ? MomoQrPayload.paymentRequest(
            recipientValue: normalizedRecipient,
            recipientType: _selectedType,
            amount: amount,
            countryCode: country.isoCode,
          )
        : MomoQrPayload.profile(
            recipientValue: normalizedRecipient,
            recipientType: _selectedType,
            countryCode: country.isoCode,
          );

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(CoolSpace.x4),
          padding: const EdgeInsets.all(CoolSpace.x5),
          decoration: BoxDecoration(
            color: BiopaySurfaceColors.surface,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BioPay QR Ready',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: BiopaySurfaceColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Container(
                padding: const EdgeInsets.all(CoolSpace.x4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: QrImageView(
                  data: payload.toQrData(country),
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: CoolSpace.x4),
              Text(
                _selectedType == MomoRecipientType.code
                    ? _codeController.text.trim()
                    : _numberController.text.trim(),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: BiopaySurfaceColors.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (amount != null && amount > 0) ...[
                const SizedBox(height: CoolSpace.x2),
                Text(
                  '${country.currencyCode} ${_formatAmount(amount)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: BiopaySurfaceColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatAmount(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final reversedIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reversedIndex > 1 && reversedIndex % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BiopaySectionCard(
      height: 126,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BiopayFieldLabel(label: label),
          const Spacer(),
          child,
        ],
      ),
    );
  }
}
