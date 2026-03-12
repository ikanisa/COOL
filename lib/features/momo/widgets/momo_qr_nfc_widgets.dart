import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/config/country_catalog.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_text_field.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../services/nfc_service.dart';

// ═════════════════════════════════════════════════════════════════════════════
// QR CODE BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoQrSheet extends StatelessWidget {
  const MomoQrSheet({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
  });

  final CoolCountry country;
  final String momoNumber;
  final String? momoCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
              const SizedBox(height: 16),
              MomoQrCodeCard(
                country: country,
                momoNumber: momoNumber,
                momoCode: momoCode,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// QR CODE CARD
// ═════════════════════════════════════════════════════════════════════════════

class MomoQrCodeCard extends StatelessWidget {
  const MomoQrCodeCard({
    required this.country,
    required this.momoNumber,
    this.momoCode,
    super.key,
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
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    size: 20,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My QR code',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Share to receive payment',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
            Text(
              momoNumber,
              style: GoogleFonts.dmMono(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            Text(
              '${country.name} · ${country.currencyCode}',
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
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
            CoolButton(
              label: 'Share QR',
              onTap: () {
                SharePlus.instance.share(
                  ShareParams(
                    text: 'Pay me via MoMo: $momoNumber',
                    subject: 'My MoMo QR Code',
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NFC BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════

class MomoNfcSheet extends StatelessWidget {
  const MomoNfcSheet({required this.currencyCode, super.key});

  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
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
              const SizedBox(height: 16),
              MomoNfcCard(currencyCode: currencyCode),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// NFC CARD (read / write)
// ═════════════════════════════════════════════════════════════════════════════

class MomoNfcCard extends StatefulWidget {
  const MomoNfcCard({this.currencyCode = 'RWF', super.key});

  final String currencyCode;

  @override
  State<MomoNfcCard> createState() => _MomoNfcCardState();
}

class _MomoNfcCardState extends State<MomoNfcCard> {
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
      CoolToast.error(context, 'NFC read failed: $e');
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
            const Icon(
              Icons.check_circle_rounded,
              size: 36,
              color: AppColors.accent,
            ),
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
              _nfcInfoRow('Phone', result.phoneNumber!),
              const SizedBox(height: 8),
              _nfcInfoRow('Amount', '${result.amount} ${widget.currencyCode}'),
            ] else if (result.rawText != null)
              _nfcInfoRow('Data', result.rawText!)
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
                  CoolToast.info(
                    context,
                    'Dial USSD to send ${result.amount} ${widget.currencyCode} to ${result.phoneNumber}',
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
                    prefixIcon: Icons.phone_rounded,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  CoolTextField(
                    label: 'Amount (${widget.currencyCode})',
                    hint: '5000',
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.payments_rounded,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 18),
                  CoolButton(
                    label: isWriting ? 'Tap NFC tag now…' : 'Write to Tag',
                    isLoading: isWriting,
                    onTap: () {
                      final phone = phoneCtrl.text.trim();
                      final amount = amountCtrl.text.trim();
                      if (phone.isEmpty || amount.isEmpty) {
                        CoolToast.error(context, 'Enter phone and amount');
                        return;
                      }
                      setSheetState(() => isWriting = true);
                      NfcService.writeTag(phoneNumber: phone, amount: amount)
                          .then((_) {
                            if (context.mounted) {
                              Navigator.pop(context);
                              CoolToast.success(context, 'Payment tag written');
                            }
                          })
                          .catchError((Object e) {
                            setSheetState(() => isWriting = false);
                            if (context.mounted) {
                              CoolToast.error(context, 'Write failed: $e');
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
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(Icons.nfc_rounded, size: 36, color: AppColors.text),
            const SizedBox(height: 12),
            Text(
              'NFC tools',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _nfcStatus == NfcStatus.available
                  ? 'Tap phones to send or receive money.'
                  : _nfcStatus == NfcStatus.disabled
                  ? 'NFC is off. Enable it in device settings.'
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
                    label: _isScanning ? 'Scanning…' : 'Read Tag',
                    isLoading: _isScanning,
                    onTap: () => _startRead(),
                  );
                  final writeButton = CoolButton(
                    label: 'Write Tag',
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
                    'Read only on iOS',
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
