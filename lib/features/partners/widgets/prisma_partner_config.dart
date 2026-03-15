import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/whatsapp_contact_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../models/partner.dart';
import '../models/partner_service.dart';
import 'partner_shared_widgets.dart';

// ═════════════════════════════════════════════════════════════════════════════
// CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════

const ikanisaSiteUrl = 'https://ikanisa.com/';
const ikanisaRwandaWhatsApp = '+250795588248';
const ikanisaEmail = 'info@ikanisa.com';

const prismaCategoryOrder = <String>['rwanda_agent', 'capability', 'support'];

const prismaCategoryMeta = <String, CategoryMeta>{
  'rwanda_agent': CategoryMeta(
    title: 'Rwanda Agents',
    description:
        'Rwanda-only specialists for legal, tax, finance, audit, NGO, and marketplace work.',
    icon: Icons.flag_rounded,
    accent: AppColors.accent,
  ),
  'capability': CategoryMeta(
    title: 'Rwanda Platform Coverage',
    description:
        'Rwanda-local service coverage across legal, tax, accounting, audit, insurance, NGO, and marketplace workflows.',
    icon: Icons.dashboard_customize_outlined,
    accent: AppColors.orange,
  ),
  'support': CategoryMeta(
    title: 'Onboarding & Contact',
    description: 'Direct channels for starting with the Rwanda desk.',
    icon: Icons.support_agent_rounded,
    accent: AppColors.whatsapp,
  ),
};

const prismaValues = <({IconData icon, String title, String description})>[
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
        'Jurisdiction-locked to Rwandan law and regulatory frameworks.',
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
    icon: Icons.account_balance_outlined,
    title: 'Rwanda Professional Standards',
    description:
        'Aligned with ICPAR, RRA, RDB, and Rwanda Bar Association frameworks.',
  ),
];

// ═════════════════════════════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═════════════════════════════════════════════════════════════════════════════

String normalizePrismaCategory(String rawCategory) {
  final normalized = rawCategory.trim().toLowerCase();
  if (normalized == 'rwanda_agent') {
    return 'rwanda_agent';
  }
  if (normalized == 'support' || normalized == 'general') {
    return 'support';
  }
  if (normalized == 'capability' ||
      normalized == 'service' ||
      normalized.endsWith('_agent')) {
    return 'capability';
  }
  return 'capability';
}

List<MapEntry<String, List<PartnerService>>> groupPrismaServices(
  List<PartnerService> services,
) {
  final buckets = <String, List<PartnerService>>{};
  for (final service in services) {
    final category = normalizePrismaCategory(service.category);
    buckets.putIfAbsent(category, () => <PartnerService>[]).add(service);
  }

  final grouped = <MapEntry<String, List<PartnerService>>>[];
  for (final category in prismaCategoryOrder) {
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

Future<void> launchPrismaAction(
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
        : ikanisaRwandaWhatsApp;
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
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        CoolToast.error(context, 'Could not open the IKANISA website.');
      }
    } catch (_) {
      if (context.mounted) {
        CoolToast.error(
          context,
          'Could not launch the IKANISA website right now.',
        );
      }
    }
    return;
  }

  if (normalizedAction.startsWith('mailto:')) {
    try {
      final launched = await launchUrl(
        Uri.parse(normalizedAction),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        CoolToast.error(context, 'No mail app is available on this device.');
      }
    } catch (_) {
      if (context.mounted) {
        CoolToast.error(context, 'Could not open the email app right now.');
      }
    }
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
