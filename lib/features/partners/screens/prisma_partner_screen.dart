import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import '../providers/partner_provider.dart';
import '../providers/partner_service_provider.dart';

const _ikanisaSiteUrl = 'https://ikanisa.com/';
const _ikanisaRwandaWhatsApp = '+250795588248';
const _ikanisaMaltaWhatsApp = '+35699711145';
const _ikanisaEmail = 'info@ikanisa.com';

const _prismaCategoryOrder = <String>[
  'rwanda_agent',
  'malta_agent',
  'global_agent',
  'capability',
  'support',
];

const _prismaCategoryMeta = <String, _PrismaCategoryMeta>{
  'rwanda_agent': _PrismaCategoryMeta(
    title: 'Rwanda Agents',
    description:
        'Jurisdiction-locked Rwanda specialists for legal, tax, NGO, and marketplace work.',
    icon: Icons.flag_rounded,
    accent: AppColors.accent,
  ),
  'malta_agent': _PrismaCategoryMeta(
    title: 'Malta Agents',
    description:
        'Malta-focused corporate, tax, and insurance specialists aligned to MBR, CFR, and MFSA workflows.',
    icon: Icons.public_rounded,
    accent: AppColors.red,
  ),
  'global_agent': _PrismaCategoryMeta(
    title: 'Global Finance & Audit',
    description:
        'Cross-jurisdiction finance-control and assurance agents operating across Rwanda and Malta.',
    icon: Icons.language_rounded,
    accent: AppColors.blue,
  ),
  'capability': _PrismaCategoryMeta(
    title: 'Platform Coverage',
    description:
        'The broader service coverage exposed across legal, tax, accounting, audit, insurance, NGO, and marketplace workflows.',
    icon: Icons.dashboard_customize_outlined,
    accent: AppColors.orange,
  ),
  'support': _PrismaCategoryMeta(
    title: 'Onboarding & Contact',
    description: 'Direct channels for starting with the Rwanda or Malta desks.',
    icon: Icons.support_agent_rounded,
    accent: AppColors.whatsapp,
  ),
};

const _prismaValues = <({IconData icon, String title, String description})>[
  (
    icon: Icons.gpp_good_outlined,
    title: 'Zero Hallucination',
    description:
        'Corpus-backed and citation-gated outputs rather than generic assistant responses.',
  ),
  (
    icon: Icons.lock_outline_rounded,
    title: 'Jurisdiction Locked',
    description:
        'Rwanda agents do not apply Malta law, and Malta agents do not apply Rwanda law.',
  ),
  (
    icon: Icons.library_books_outlined,
    title: '28,000+ Indexed Documents',
    description:
        'Laws, guidance, professional standards, and source material are searchable and citable.',
  ),
  (
    icon: Icons.fact_check_outlined,
    title: 'Quality-Gated Outputs',
    description:
        'Outputs are reviewed for citation completeness, source tracing, and law-in-force checks.',
  ),
  (
    icon: Icons.translate_rounded,
    title: 'Multilingual',
    description:
        'English, French, Kinyarwanda, and Maltese support across the platform.',
  ),
];

String _normalizePrismaCategory(String rawCategory) {
  return switch (rawCategory.trim().toLowerCase()) {
    'rwanda_agent' => 'rwanda_agent',
    'malta_agent' => 'malta_agent',
    'global_agent' => 'global_agent',
    'capability' || 'service' => 'capability',
    'support' || 'general' => 'support',
    _ => 'capability',
  };
}

List<MapEntry<String, List<PartnerService>>> _groupPrismaServices(
  List<PartnerService> services,
) {
  final buckets = <String, List<PartnerService>>{};
  for (final service in services) {
    final category = _normalizePrismaCategory(service.category);
    buckets.putIfAbsent(category, () => <PartnerService>[]).add(service);
  }

  final grouped = <MapEntry<String, List<PartnerService>>>[];
  for (final category in _prismaCategoryOrder) {
    final bucket = buckets.remove(category);
    if (bucket != null && bucket.isNotEmpty) {
      grouped.add(MapEntry(category, bucket));
    }
  }
  for (final extra in buckets.entries) {
    if (extra.value.isNotEmpty) {
      grouped.add(extra);
    }
  }
  return grouped;
}

Future<void> _launchExternalUri(
  BuildContext context,
  Uri uri, {
  String unavailableMessage = 'This action is not available on this device.',
  String failureMessage = 'Could not open this action right now.',
}) async {
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(unavailableMessage)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failureMessage)));
    }
  }
}

Future<void> _launchPrismaAction(
  BuildContext context,
  Partner partner, {
  required String action,
  String? topic,
}) async {
  final normalizedAction = action.trim();
  if (normalizedAction.isEmpty) {
    return;
  }

  if (normalizedAction == 'whatsapp' ||
      normalizedAction.startsWith('whatsapp:')) {
    final explicitPhone = normalizedAction.startsWith('whatsapp:')
        ? normalizedAction.substring('whatsapp:'.length).trim()
        : '';
    final phone = explicitPhone.isNotEmpty
        ? explicitPhone
        : (partner.whatsappNumber?.trim().isNotEmpty ?? false)
        ? partner.whatsappNumber!.trim()
        : _ikanisaRwandaWhatsApp;
    final message = switch (topic) {
      null => 'Hello, I would like help with ${partner.name}.',
      _ => 'Hello, I would like help with ${partner.name}: $topic.',
    };
    await WhatsAppContactService.openChat(
      context,
      phoneNumber: phone,
      message: message,
    );
    return;
  }

  if (normalizedAction.startsWith('web:')) {
    final url = normalizedAction.substring('web:'.length);
    await _launchExternalUri(
      context,
      Uri.parse(url),
      unavailableMessage: 'Could not open the IKANISA website.',
      failureMessage: 'Could not launch the IKANISA website right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('mailto:')) {
    await _launchExternalUri(
      context,
      Uri.parse(normalizedAction),
      unavailableMessage: 'No mail app is available on this device.',
      failureMessage: 'Could not open the email app right now.',
    );
    return;
  }

  if (normalizedAction.startsWith('route:')) {
    final route = normalizedAction.substring('route:'.length);
    const allowedPrefixes = ['/partners', '/profile', '/settings'];
    final isAllowed = allowedPrefixes.any(
      (prefix) => route == prefix || route.startsWith('$prefix/'),
    );
    if (isAllowed && context.mounted) {
      context.go(route);
    } else {
      debugPrint('[PrismaPartner] Blocked unknown CTA route: $route');
    }
  }
}

class PrismaPartnerScreen extends ConsumerWidget {
  const PrismaPartnerScreen({super.key});

  static const _slug = 'prisma';

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
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: AppColors.text,
            onPressed: () => context.pop(),
          ),
          title: partnerAsync.when(
            data: (partner) => Text(
              partner?.name ?? 'PRISMA',
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
          error: (error, _) => _ErrorBody(message: error.toString()),
          data: (partner) {
            if (partner == null) {
              return const _ErrorBody(message: 'Partner not found');
            }
            return _PrismaBody(partner: partner);
          },
        ),
      ),
    );
  }
}

class _PrismaBody extends ConsumerWidget {
  const _PrismaBody({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servicesAsync = ref.watch(partnerServicesProvider(partner.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(partner: partner),
          const SizedBox(height: 16),
          _QuickActions(partner: partner),
          const SizedBox(height: 16),
          const _StatsCard(),
          const SizedBox(height: 16),
          const _ValuesCard(),
          const SizedBox(height: 18),
          servicesAsync.when(
            loading: () => const CoolSkeletonList(itemCount: 6),
            error: (error, _) => _ErrorCard(message: error.toString()),
            data: (services) {
              if (services.isEmpty) {
                return _EmptyServicesCard(partnerName: partner.name);
              }

              final grouped = _groupPrismaServices(services);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final group in grouped) ...[
                    _SectionHeader(category: group.key),
                    const SizedBox(height: 12),
                    for (final service in group.value) ...[
                      _ServiceCard(service: service, partner: partner),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          _SupportCard(partner: partner),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final description =
        partner.description ??
        'AI-powered professional services across legal, tax, accounting, audit, insurance, corporate, NGO, and marketplace operations in Rwanda and Malta.';

    return CoolCard(
      gradient: AppColors.accentGradient,
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Text(
              partner.emoji,
              style: TextStyle(
                fontSize: 84,
                color: Colors.white.withValues(alpha: 0.08),
              ),
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
                    color: AppColors.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    '${partner.emoji} Official IKANISA content',
                    style: GoogleFonts.dmSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  partner.name,
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  partner.subtitle ?? 'IKANISA AI professional services',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text2,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _HeroPill(
                      icon: Icons.balance_outlined,
                      label: 'Legal, Tax & Compliance',
                    ),
                    _HeroPill(
                      icon: Icons.assured_workload_outlined,
                      label: 'Audit, Insurance & Risk',
                    ),
                    _HeroPill(
                      icon: Icons.language_outlined,
                      label: 'Rwanda & Malta',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        _QuickActionTile(
          icon: Icons.public_rounded,
          title: 'Website',
          subtitle: 'Open ikanisa.com',
          onTap: () => _launchPrismaAction(
            context,
            partner,
            action: 'web:$_ikanisaSiteUrl',
          ),
        ),
        _QuickActionTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Rwanda Desk',
          subtitle: 'WhatsApp Rwanda team',
          onTap: () => _launchPrismaAction(
            context,
            partner,
            action: 'whatsapp:$_ikanisaRwandaWhatsApp',
          ),
        ),
        _QuickActionTile(
          icon: Icons.travel_explore_outlined,
          title: 'Malta Desk',
          subtitle: 'WhatsApp Malta team',
          onTap: () => _launchPrismaAction(
            context,
            partner,
            action: 'whatsapp:$_ikanisaMaltaWhatsApp',
          ),
        ),
        _QuickActionTile(
          icon: Icons.alternate_email_outlined,
          title: 'Email',
          subtitle: _ikanisaEmail,
          onTap: () => _launchPrismaAction(
            context,
            partner,
            action: 'mailto:$_ikanisaEmail',
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'IKANISA at a glance',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _StatTile(value: '9', label: 'AI Agents'),
              SizedBox(width: 10),
              _StatTile(value: '28K+', label: 'Indexed Docs'),
              SizedBox(width: 10),
              _StatTile(value: '2', label: 'Jurisdictions'),
              SizedBox(width: 10),
              _StatTile(value: '14', label: 'Sectors'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValuesCard extends StatelessWidget {
  const _ValuesCard();

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How the platform works',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'These are the core operating principles published on the official IKANISA site.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          for (final item in _prismaValues) ...[
            _ValueRow(
              icon: item.icon,
              title: item.title,
              description: item.description,
            ),
            if (item != _prismaValues.last) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final meta =
        _prismaCategoryMeta[category] ?? _prismaCategoryMeta['capability']!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: meta.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(meta.icon, size: 18, color: meta.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                meta.title,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          meta.description,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.text2,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.partner});

  final PartnerService service;
  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final normalizedCategory = _normalizePrismaCategory(service.category);
    final meta =
        _prismaCategoryMeta[normalizedCategory] ??
        _prismaCategoryMeta['capability']!;

    return CoolCard(
      gradient: normalizedCategory.endsWith('_agent')
          ? AppColors.blueGradient
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: meta.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  service.emoji,
                  style: const TextStyle(fontSize: 22),
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
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    if (service.subtitle != null &&
                        service.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        service.subtitle!,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text2,
                          height: 1.45,
                        ),
                      ),
                    ],
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
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < service.details.length; i++) ...[
                    _DetailRow(detail: service.details[i], accent: meta.accent),
                    if (i < service.details.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ],
          if (service.ctaLabel != null &&
              service.ctaAction != null &&
              service.ctaAction!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            CoolButton(
              label: service.ctaLabel!,
              onTap: () => _launchPrismaAction(
                context,
                partner,
                action: service.ctaAction!,
                topic: service.title,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      gradient: AppColors.blueGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start with the right desk',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'IKANISA publishes separate Rwanda and Malta WhatsApp channels. Use the one that matches your jurisdiction or email the team directly.',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          const _SupportLine(
            icon: Icons.flag_outlined,
            label: 'Rwanda WhatsApp',
            value: '+250 795 588 248',
          ),
          const SizedBox(height: 10),
          const _SupportLine(
            icon: Icons.travel_explore_outlined,
            label: 'Malta WhatsApp',
            value: '+356 9971 1145',
          ),
          const SizedBox(height: 10),
          const _SupportLine(
            icon: Icons.alternate_email_outlined,
            label: 'Email',
            value: _ikanisaEmail,
          ),
          const SizedBox(height: 10),
          const _SupportLine(
            icon: Icons.place_outlined,
            label: 'Coverage',
            value: 'Kigali, Rwanda · Valletta, Malta',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 180,
                child: CoolButton(
                  label: 'Open Rwanda Desk',
                  onTap: () => _launchPrismaAction(
                    context,
                    partner,
                    action: 'whatsapp:$_ikanisaRwandaWhatsApp',
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: CoolButton(
                  label: 'Open Malta Desk',
                  onTap: () => _launchPrismaAction(
                    context,
                    partner,
                    action: 'whatsapp:$_ikanisaMaltaWhatsApp',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail, required this.accent});

  final ServiceDetail detail;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(detail.icon, style: const TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail.value,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: CoolCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.accent, size: 22),
              const Spacer(),
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.text2,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
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
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.text2,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportLine extends StatelessWidget {
  const _SupportLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyServicesCard extends StatelessWidget {
  const _EmptyServicesCard({required this.partnerName});

  final String partnerName;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          const Text('📋', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'No services listed yet',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Services for $partnerName will appear here once they are configured by an admin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return CoolCard(
      child: Column(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 10),
          Text(
            'Unable to load services',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚠️', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrismaCategoryMeta {
  const _PrismaCategoryMeta({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
}
