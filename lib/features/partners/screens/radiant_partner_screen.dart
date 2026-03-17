import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/icon_mapper.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/whatsapp_hint_chip.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import '../providers/partner_provider.dart';
import '../providers/partner_service_provider.dart';
import '../widgets/partner_navigation.dart';
import '../../../core/l10n/l10n.dart';

// ═════════════════════════════════════════════════════════════════════════════
// RADIANT INSURANCE — PARTNER DETAIL SCREEN (now DATA-DRIVEN)
// ═════════════════════════════════════════════════════════════════════════════

class RadiantPartnerScreen extends ConsumerWidget {
  const RadiantPartnerScreen({super.key});

  static const _slug = 'radiant';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnerAsync = ref.watch(partnerBySlugProvider(_slug));

    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: buildPartnerBackButton(
            context,
            fallbackLocation: AppRoutes.partners,
            icon: Icons.arrow_back_ios_new_rounded,
            color: AppColors.text,
          ),
          actions: buildPartnerAppBarActions(
            context,
            homeColor: AppColors.text,
          ),
          title: partnerAsync.when(
            data: (p) => Text(
              p?.name ?? 'Insurance Partner',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          centerTitle: true,
        ),
        body: partnerAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(18),
            child: CoolSkeletonList(),
          ),
          error: (e, _) => Center(
            child: Text(
              e.toString(),
              style: GoogleFonts.dmSans(color: AppColors.text2),
            ),
          ),
          data: (partner) {
            if (partner == null) {
              return Center(
                child: Text(
                  'Partner not found',
                  style: GoogleFonts.dmSans(color: AppColors.text2),
                ),
              );
            }
            return _RadiantBody(partner: partner);
          },
        ),
      ),
    );
  }
}

class _RadiantBody extends ConsumerWidget {
  const _RadiantBody({required this.partner});

  final Partner partner;

  Future<void> _openChat(BuildContext context, {String? topic}) {
    final message = switch (topic) {
      null => 'Hello, I would like a quote from ${partner.name}.',
      _ => 'Hello, I would like help with ${partner.name}: $topic.',
    };

    final phone = partner.whatsappNumber ?? '';
    if (phone.isEmpty) return Future.value();

    return WhatsAppContactService.openChat(
      context,
      phoneNumber: phone,
      message: message,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(
      currentCountryPartnerServicesProvider(partner.id),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        children: [
          // ── Hero ─────────────────────────────────────────────
          CoolCard(
            gradient: AppColors.blueGradient,
            child: Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -5,
                  child: Icon(
                    IconMapper.from(partner.emoji),
                    size: 80,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              IconMapper.from(partner.emoji),
                              size: 13,
                              color: AppColors.blue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              partner.subtitle ?? 'Insurance Partner',
                              style: GoogleFonts.dmSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        partner.name,
                        style: GoogleFonts.dmSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                      if (partner.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          partner.subtitle!,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppColors.text2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Dynamic service cards ──────────────────────────
          servicesAsync.when(
            loading: () => const CoolSkeletonList(itemCount: 3),
            error: (e, _) => CoolCard(
              child: Text(
                e.toString(),
                style: GoogleFonts.dmSans(color: AppColors.text2),
              ),
            ),
            data: (services) => Column(
              children: [
                for (final service in services) ...[
                  _InsuranceServiceCard(
                    service: service,
                    onTap: () => _openChat(context, topic: service.title),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
          CoolButton(label: context.l10n.requestAQuote, onTap: () => _openChat(context)),
        ],
      ),
    );
  }
}

class _InsuranceServiceCard extends StatelessWidget {
  const _InsuranceServiceCard({required this.service, required this.onTap});

  final PartnerService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  IconMapper.from(service.emoji),
                  size: 20,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.title,
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    if (service.subtitle != null)
                      Text(
                        service.subtitle!,
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
          if (service.details.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < service.details.length; i++) ...[
                    _InfoRow(detail: service.details[i]),
                    if (i < service.details.length - 1)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: WhatsAppHintChip(
              label: service.ctaLabel ?? 'Chat about this cover',
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.detail});

  final ServiceDetail detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(IconMapper.from(detail.icon), size: 14, color: AppColors.text2),
        const SizedBox(width: 8),
        Text(
          detail.label,
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
          ),
        ),
        const Spacer(),
        Text(
          detail.value,
          style: GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.accent,
          ),
        ),
      ],
    );
  }
}