part of 'momo_nfc_widgets.dart';

extension _MomoNfcCardActions on _MomoNfcCardState {
  Future<void> _launchPaymentFromTag(NfcReadResult result) async {
    final amount = int.tryParse(
      (result.amount ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final recipient = result.recipientValue?.trim();
    if (recipient == null ||
        recipient.isEmpty ||
        amount == null ||
        amount <= 0) {
      CoolToast.error(context, 'NFC payload incomplete');
      return;
    }

    try {
      await widget.momoService.initiatePayment(
        recipientMomo: recipient,
        amount: amount,
        reference: 'NFC-${DateTime.now().millisecondsSinceEpoch}',
        recipientType: result.recipientType,
        countryCode: result.countryCode ?? widget.country.isoCode,
      );
      if (!mounted) {
        return;
      }
      CoolToast.success(context, 'USSD payment launched');
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'USSD launch failed');
    }
  }

  void _showReadResult(NfcReadResult result) {
    final recipientLabel = result.recipientType == MomoRecipientType.code
        ? 'MoMo Code'
        : 'MoMo Number';
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.coolSemanticColors;
        final space = context.coolSpace;
        final theme = Theme.of(context);
        return Container(
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(CoolRadii.xl),
              topRight: Radius.circular(CoolRadii.xl),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
            CoolSpace.x5 + CoolSpace.x1 / 2,
            CoolSpace.x4,
            CoolSpace.x5 + CoolSpace.x1 / 2,
            CoolSpace.x7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.borderStrong,
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.xs),
                  ),
                ),
              ),
              SizedBox(height: space.x5),
              Icon(Icons.check_circle_rounded, size: 36, color: colors.accent),
              SizedBox(height: space.x3),
              Text(
                result.hasPaymentData ? 'Payment tag' : 'Tag read',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: CoolSpace.x3),
              if (result.hasPaymentData) ...[
                _nfcInfoRow(recipientLabel, result.recipientValue!),
                SizedBox(height: space.x2),
                _nfcInfoRow(
                  'Amount',
                  '${result.amount} ${widget.country.currencyCode}',
                ),
              ] else if (result.rawText != null)
                _nfcInfoRow('Data', result.rawText!)
              else
                Text(
                  'No data found',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.secondaryText,
                  ),
                ),
              SizedBox(height: space.x4 + space.x1 / 2),
              if (result.hasPaymentData)
                CoolButton(
                  label: 'Pay by USSD',
                  onTap: () async {
                    Navigator.pop(context);
                    await _launchPaymentFromTag(result);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _nfcInfoRow(String label, String value) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x3),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.sm)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showWriteSheet() {
    final amountCtrl = TextEditingController(
      text: _nfcAmountController.text.trim(),
    );
    final recipientValue = _nfcActiveRecipientValue;
    final recipientType = _nfcRecipientType;

    if (recipientValue.isEmpty) {
      CoolToast.error(context, 'Add MoMo number first');
      return;
    }

    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        var isWriting = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = context.coolSemanticColors;
            final space = context.coolSpace;
            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: colors.elevatedBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(CoolRadii.xl),
                  topRight: Radius.circular(CoolRadii.xl),
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                space.x5 + space.x1 / 2,
                space.x4,
                space.x5 + space.x1 / 2,
                space.x5 +
                    space.x1 / 2 +
                    MediaQuery.of(context).viewInsets.bottom,
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
                        color: colors.borderStrong,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(CoolRadii.xs),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: space.x5),
                  Text(
                    _supportsPhoneTap ? 'Tap receive' : 'Write tag',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.primaryText,
                    ),
                  ),
                  SizedBox(height: space.x3),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(CoolSpace.x3),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(CoolRadii.sm),
                      ),
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recipientType == MomoRecipientType.code
                              ? 'Receiving to MoMo Code'
                              : 'Receiving to MoMo Number',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.secondaryText,
                          ),
                        ),
                        SizedBox(height: space.x1 + space.x1 / 2),
                        Text(
                          recipientType == MomoRecipientType.code
                              ? recipientValue
                              : PhoneValidator.formatMomoDisplay(
                                  recipientValue,
                                  widget.country,
                                ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: space.x3),
                  CoolTextField(
                    label: 'Amount (${widget.country.currencyCode})',
                    hint: '5000',
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    prefixIcon: Icons.payments_rounded,
                    textInputAction: TextInputAction.done,
                  ),
                  SizedBox(height: space.x4 + space.x1 / 2),
                  CoolButton(
                    label: isWriting
                        ? (_supportsPhoneTap ? 'Starting tap' : 'Writing tag')
                        : (_supportsPhoneTap ? 'Start tap' : 'Write tag'),
                    isLoading: isWriting,
                    onTap: () {
                      final amount = amountCtrl.text.trim();
                      if (recipientValue.isEmpty || amount.isEmpty) {
                        CoolToast.error(context, 'Add amount and MoMo');
                        return;
                      }
                      setSheetState(() => isWriting = true);
                      final payload = NfcPaymentPayload(
                        recipientValue: recipientValue,
                        amount: amount,
                        recipientType: recipientType,
                        countryCode: widget.country.isoCode,
                      );
                      final future = _supportsPhoneTap
                          ? _nfcHceService.startPaymentRequest(
                              uri:
                                  payload.toUssdUri() ??
                                  payload.toDeepLinkUri(),
                            )
                          : NfcService.writeTag(
                              recipientValue: recipientValue,
                              amount: amount,
                              recipientType: recipientType,
                              countryCode: widget.country.isoCode,
                            );
                      future
                          .then((_) async {
                            if (!mounted || !context.mounted) {
                              return;
                            }
                            Navigator.pop(context);
                            await _refreshNfcAccess();
                            if (!mounted) {
                              return;
                            }
                            CoolToast.success(
                              this.context,
                              _supportsPhoneTap ? 'Tap ready' : 'Tag ready',
                            );
                          })
                          .catchError((Object _) {
                            setSheetState(() => isWriting = false);
                            if (mounted) {
                              CoolToast.error(this.context, 'Write failed');
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
}
