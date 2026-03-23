import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/whatsapp_contact_service.dart';
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
const _prismaRwandaAccent = Color(0xFF2F7252);
const _prismaCapabilityAccent = Color(0xFFA86F26);
const _prismaSupportAccent = Color(0xFF2E8A57);

const prismaCategoryOrder = <String>['rwanda_agent', 'capability', 'support'];

final prismaCategoryMeta = <String, CategoryMeta>{
  'rwanda_agent': const CategoryMeta(
    title: 'Rwanda Agents',
    description: 'Rwanda-only specialists for legal',
    icon: Icons.flag_rounded,
    accent: _prismaRwandaAccent,
  ),
  'capability': const CategoryMeta(
    title: 'Rwanda Platform Coverage',
    description: 'Rwanda-local service coverage across',
    icon: Icons.dashboard_customize_outlined,
    accent: _prismaCapabilityAccent,
  ),
  'support': const CategoryMeta(
    title: 'Onboarding & Contact',
    description: 'Direct channels for starting',
    icon: Icons.support_agent_rounded,
    accent: _prismaSupportAccent,
  ),
};

const prismaValues = <({IconData icon, String title, String description})>[
  (
    icon: Icons.gpp_good_outlined,
    title: 'Zero Hallucination',
    description: 'Corpus-backed and citation-gated outputs',
  ),
  (
    icon: Icons.lock_outline_rounded,
    title: 'Jurisdiction Locked',
    description: 'Jurisdiction-locked to Rwandan law',
  ),
  (
    icon: Icons.library_books_outlined,
    title: '28,000+ Indexed Documents',
    description: 'Laws guidance professional standards',
  ),
  (
    icon: Icons.fact_check_outlined,
    title: 'Quality-Gated Outputs',
    description: 'Outputs are reviewed for',
  ),
  (
    icon: Icons.account_balance_outlined,
    title: 'Rwanda Professional Standards',
    description: 'Aligned with ICPAR RRA',
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
        CoolToast.error(context, 'Website unavailable');
      }
    } catch (_) {
      if (context.mounted) {
        CoolToast.error(context, 'Website unavailable');
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
        CoolToast.error(context, 'No mail app');
      }
    } catch (_) {
      if (context.mounted) {
        CoolToast.error(context, 'Mail app failed');
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
