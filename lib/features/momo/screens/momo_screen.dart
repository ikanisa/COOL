import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/providers/supported_countries_provider.dart';
import '../../../core/services/momo_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../auth/providers/auth_provider.dart';
import '../services/nfc_service.dart';

/// Mobile Money hub — USSD gateway, QR code, and NFC transfers.
class MomoScreen extends ConsumerWidget {
  const MomoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final countries =
        ref.watch(supportedCountriesProvider).valueOrNull ??
        CoolCountryCatalog.all;
    final country = CoolCountryCatalog.resolve(
      country: user?.country,
      phone: user?.phone,
      providerId: user?.momoProvider,
      source: countries,
    );
    final momoNumber = user?.momoNumber.isNotEmpty == true
        ? user!.momoNumber
        : user?.phone.isNotEmpty == true
        ? user!.phone
        : country.buildE164Phone('91234567');
    final momoCode = user?.momoCode;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        automaticallyImplyLeading: context.canPop(),
        title: Text(
          'Mobile Money',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 8),
                  _StatementAccessCard(
                    onOpenStatements: () => context.push('/profile/momo-sms'),
                  ),
                  const SizedBox(height: 16),
                  _UssdCard(
                    country: country,
                    momoCode: momoCode,
                    onSendTap: () => _showSendMoneySheet(
                      context,
                      country: country,
                      momoNumber: momoNumber,
                      momoCode: momoCode,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _QrCodeCard(
                    country: country,
                    momoNumber: momoNumber,
                    momoCode: momoCode,
                  ),
                  const SizedBox(height: 16),
                  _NfcCard(currencyCode: country.currencyCode),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSendMoneySheet(
    BuildContext context, {
    required CoolCountry country,
    required String momoNumber,
    String? momoCode,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SendMoneySheet(
        country: country,
        momoNumber: momoNumber,
        momoCode: momoCode,
      ),
    );
  }
}

class _StatementAccessCard extends StatelessWidget {
  const _StatementAccessCard({required this.onOpenStatements});

  final VoidCallback onOpenStatements;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.blueGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border2),
              ),
              alignment: Alignment.center,
              child: const Text('🧾', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Statements & Ledger',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Browse wallet entries, savings contributions, filters, and export-ready statement data.',
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 132,
              child: CoolButton(
                label: 'Open',
                variant: CoolButtonVariant.secondary,
                onTap: onOpenStatements,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// USSD CARD
// ═════════════════════════════════════════════════════════════════════════

class _UssdCard extends StatelessWidget {
  const _UssdCard({
    required this.country,
    required this.onSendTap,
    this.momoCode,
  });

  final CoolCountry country;
  final VoidCallback onSendTap;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Text('📲', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 12),
            Text(
              'USSD Mobile Money',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send & receive via USSD SMS gateway.\nWorks on any phone, no internet needed.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${country.displayName} · ${country.currencyCode}',
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    country.momoUssdTemplate
                        .replaceAll('{recipient}', '91234567')
                        .replaceAll('{amount}', '5000'),
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text2,
                    ),
                  ),
                  if (country.supportsMomoCode) ...[
                    const SizedBox(height: 6),
                    Text(
                      country.momoCodeUssdTemplate!
                          .replaceAll('{recipient}', momoCode ?? '123456')
                          .replaceAll('{amount}', '5000'),
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final shouldStack = constraints.maxWidth < 360;
                final requestPayButton = CoolButton(
                  label: 'Request Pay',
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Request Pay — Coming Soon'),
                      ),
                    );
                  },
                );

                if (shouldStack) {
                  return Column(
                    children: [
                      CoolButton(label: 'Send MOMO', onTap: onSendTap),
                      const SizedBox(height: 12),
                      requestPayButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(
                      child: CoolButton(label: 'Send MOMO', onTap: onSendTap),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: requestPayButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// MY QR CODE CARD
// ═════════════════════════════════════════════════════════════════════════

class _QrCodeCard extends StatelessWidget {
  const _QrCodeCard({
    required this.country,
    required this.momoNumber,
    this.momoCode,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('📱', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My MOMO QR Code',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Scan to pay · Works offline',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${country.currencyCode} · ${country.dialCode}',
                        style: GoogleFonts.dmSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // QR code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: momoNumber.replaceAll(' ', ''),
                version: QrVersions.auto,
                size: 160,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.circle,
                  color: Colors.white,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Phone number
            Text(
              momoNumber,
              style: GoogleFonts.dmMono(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            if (momoCode != null && momoCode!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'MoMo Code: ${momoCode!.trim()}',
                style: GoogleFonts.dmMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                ),
              ),
            ],
            const SizedBox(height: 18),

            LayoutBuilder(
              builder: (context, constraints) {
                final shouldStack = constraints.maxWidth < 360;
                final shareButton = CoolButton(
                  label: 'Share QR',
                  onTap: () {
                    SharePlus.instance.share(
                      ShareParams(
                        text: 'Pay me via MoMo: $momoNumber',
                        subject: 'My MoMo QR Code',
                      ),
                    );
                  },
                );
                final saveButton = CoolButton(
                  label: 'Save Image',
                  variant: CoolButtonVariant.secondary,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Save to Gallery — Coming Soon'),
                      ),
                    );
                  },
                );

                if (shouldStack) {
                  return Column(
                    children: [
                      shareButton,
                      const SizedBox(height: 12),
                      saveButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: shareButton),
                    const SizedBox(width: 12),
                    Expanded(child: saveButton),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// NFC CARD
// ═════════════════════════════════════════════════════════════════════════

class _NfcCard extends StatefulWidget {
  const _NfcCard({this.currencyCode = 'RWF'});

  final String currencyCode;

  @override
  State<_NfcCard> createState() => _NfcCardState();
}

class _NfcCardState extends State<_NfcCard> {
  NfcStatus _nfcStatus = NfcStatus.notSupported;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _checkNfc();
  }

  Future<void> _checkNfc() async {
    final status = await NfcService.checkAvailability();
    if (mounted) setState(() => _nfcStatus = status);
  }

  Future<void> _startRead() async {
    setState(() => _isScanning = true);
    try {
      final result = await NfcService.readTag();
      if (!mounted) return;
      setState(() => _isScanning = false);
      _showReadResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('NFC read failed: $e')));
    }
  }

  void _showReadResult(NfcReadResult result) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('✅', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 12),
            Text(
              result.hasPaymentData ? 'Payment Tag Found' : 'Tag Read',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 12),
            if (result.hasPaymentData) ...[
              _nfcInfoRow('📱 Phone', result.phoneNumber!),
              const SizedBox(height: 8),
              _nfcInfoRow(
                '💰 Amount',
                '${result.amount} ${widget.currencyCode}',
              ),
            ] else if (result.rawText != null)
              _nfcInfoRow('📄 Data', result.rawText!)
            else
              Text(
                'No readable data on this tag',
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text2),
              ),
            const SizedBox(height: 18),
            if (result.hasPaymentData)
              CoolButton(
                label: 'Pay via USSD',
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Dial USSD to send ${result.amount} ${widget.currencyCode} to ${result.phoneNumber}',
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _nfcInfoRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text2,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteSheet() {
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        var isWriting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(
                22,
                16,
                22,
                22 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Write Payment Tag',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  CoolTextField(
                    label: 'Phone Number',
                    hint: '+250 791 234 567',
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    prefixEmoji: '📱',
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CoolTextField(
                    label: 'Amount (${widget.currencyCode})',
                    hint: '5000',
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    prefixEmoji: '💰',
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 18),
                  CoolButton(
                    label: isWriting ? 'Tap NFC tag now…' : '📤 Write to Tag',
                    isLoading: isWriting,
                    onTap: () {
                      final phone = phoneCtrl.text.trim();
                      final amount = amountCtrl.text.trim();
                      if (phone.isEmpty || amount.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Enter phone and amount'),
                          ),
                        );
                        return;
                      }
                      setSheetState(() => isWriting = true);
                      NfcService.writeTag(phoneNumber: phone, amount: amount)
                          .then((_) {
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '✅ Payment tag written successfully',
                                  ),
                                ),
                              );
                            }
                          })
                          .catchError((Object e) {
                            setSheetState(() => isWriting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Write failed: $e')),
                              );
                            }
                          });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final showWrite = !kIsWeb && Platform.isAndroid;

    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Text('🤝', style: TextStyle(fontSize: 38)),
            const SizedBox(height: 12),
            Text(
              'NFC Phone-to-Phone',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _nfcStatus == NfcStatus.available
                  ? 'Tap phones to send money or read a\npayment tag from another Cool user.'
                  : _nfcStatus == NfcStatus.disabled
                  ? 'NFC is disabled. Enable it in your\ndevice settings to use this feature.'
                  : 'NFC is not available on this device.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.text2,
                height: 1.5,
              ),
            ),
            if (_nfcStatus == NfcStatus.available) ...[
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final shouldStack = constraints.maxWidth < 360 && showWrite;
                  final readButton = CoolButton(
                    label: _isScanning ? '📡 Scanning…' : '📥 Read Tag',
                    isLoading: _isScanning,
                    onTap: () => _startRead(),
                  );
                  final writeButton = CoolButton(
                    label: '📤 Write Tag',
                    variant: CoolButtonVariant.secondary,
                    onTap: _showWriteSheet,
                  );

                  if (shouldStack) {
                    return Column(
                      children: [
                        readButton,
                        const SizedBox(height: 12),
                        writeButton,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: readButton),
                      if (showWrite) ...[
                        const SizedBox(width: 12),
                        Expanded(child: writeButton),
                      ],
                    ],
                  );
                },
              ),
              if (!showWrite)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Read only on iOS · Android supports write too',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text3,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// SEND MONEY BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════

class _SendMoneySheet extends StatefulWidget {
  const _SendMoneySheet({
    required this.country,
    required this.momoNumber,
    this.momoCode,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  State<_SendMoneySheet> createState() => _SendMoneySheetState();
}

class _SendMoneySheetState extends State<_SendMoneySheet> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late MomoRecipientType _recipientType;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _recipientType = MomoRecipientType.phoneNumber;
  }

  Future<void> _confirmSend() async {
    if (_isSubmitting) {
      return;
    }

    final recipient = _recipientController.text.trim();
    final amount = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );

    if (recipient.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Enter a valid recipient and amount.',
            style: GoogleFonts.dmSans(color: AppColors.text),
          ),
          backgroundColor: AppColors.surface2,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await MomoService.instance.initiatePayment(
        recipientMomo: recipient,
        amount: amount,
        reference: 'SEND-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: _recipientType,
        countryCode: widget.country.isoCode,
      );

      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open the ${widget.country.name} USSD flow.',
            style: GoogleFonts.dmSans(color: AppColors.text),
          ),
          backgroundColor: AppColors.surface2,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            22 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Send Money',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Text('🌍', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.country.displayName} · ${widget.country.currencyCode} · ${widget.country.dialCode}\nFrom: ${widget.momoNumber}',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (widget.country.supportsMomoCode) ...[
                Row(
                  children: [
                    Expanded(
                      child: _RouteTypeChip(
                        label: 'MoMo Number',
                        isActive:
                            _recipientType == MomoRecipientType.phoneNumber,
                        onTap: () {
                          setState(
                            () =>
                                _recipientType = MomoRecipientType.phoneNumber,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RouteTypeChip(
                        label: 'MoMo Code',
                        isActive: _recipientType == MomoRecipientType.code,
                        onTap: () {
                          setState(
                            () => _recipientType = MomoRecipientType.code,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // Recipient
              CoolTextField(
                label: _recipientType == MomoRecipientType.code
                    ? 'Merchant MoMo Code'
                    : 'Recipient Phone or User ID',
                hint: _recipientType == MomoRecipientType.code
                    ? (widget.momoCode?.trim().isNotEmpty == true
                          ? widget.momoCode!.trim()
                          : '123456')
                    : '${widget.country.dialCode} 91234567 or #392847',
                controller: _recipientController,
                keyboardType: _recipientType == MomoRecipientType.code
                    ? TextInputType.number
                    : TextInputType.phone,
                prefixEmoji: _recipientType == MomoRecipientType.code
                    ? '🏷️'
                    : '👤',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),

              // Amount
              CoolTextField(
                label: 'Amount (${widget.country.currencyCode})',
                hint: '5,000',
                controller: _amountController,
                keyboardType: TextInputType.number,
                prefixEmoji: '💰',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),

              // Note
              CoolTextField(
                label: 'Note (optional)',
                hint: 'What\'s this for?',
                controller: _noteController,
                prefixEmoji: '📝',
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),

              // USSD info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Text('📞', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You\'ll be redirected to ${widget.country.name} MOMO USSD to confirm the transaction.',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.accent,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Confirm button
              CoolButton(
                label: 'Confirm Send',
                isLoading: _isSubmitting,
                onTap: _confirmSend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteTypeChip extends StatelessWidget {
  const _RouteTypeChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accentGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? AppColors.accent : AppColors.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isActive ? AppColors.accent : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
