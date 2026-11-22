import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/contribution_record_copy.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/utils/support_contact.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'security_hub_header.dart';
import 'settings_subpage_widgets.dart';

class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenScaffold(
      title: 'Security',
      showHeader: false,
      compact: true,
      topChrome: SecurityHubHeader(onBack: () => goBackOrHome(context)),
      children: [
        const InfoSecurityBanner(
          title: 'Approve payments in MoMo',
          message:
              'Never share your MoMo PIN. Enter it only in your provider’s payment prompt.',
          tone: CollectStatusTone.warning,
        ),
        SettingsOptionPanel(
          children: [
            SettingsLinkRow(
              icon: CollectIcons.lock,
              title: 'Session and profile',
              subtitle: 'Review account details, Collect ID, and sign out.',
              onTap: () => context.go('/settings/account'),
            ),
            SettingsLinkRow(
              icon: Icons.smartphone_rounded,
              title: ContributionRecordCopy.totalTitle,
              subtitle: ContributionRecordCopy.recordHint,
              onTap: () => context.go('/activity'),
            ),
            SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Payment privacy',
              subtitle:
                  'Personal payment details and receipt evidence stay private.',
              onTap: () => context.go('/settings/legal/privacy'),
            ),
            SettingsLinkRow(
              icon: CollectIcons.error,
              title: 'Delete data',
              subtitle: 'Create an auditable account deletion request.',
              onTap: () => context.go('/settings/account/delete'),
            ),
          ],
        ),
      ],
    );
  }
}

class HelpSettingsScreen extends ConsumerWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runtimeConfig = ref.watch(collectRuntimeConfigProvider);
    return ScreenScaffold(
      title: 'Help',
      showHeader: false,
      compact: true,
      topChrome: const SettingsSubpageHeader(title: 'Help'),
      children: [
        const SectionHeader(title: 'Common problems'),
        SettingsOptionPanel(
          children: [
            SettingsLinkRow(
              icon: CollectIcons.lock,
              title: 'Sign-in or code problem',
              subtitle: 'Get help when a code is late, expired, or rejected.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            SettingsLinkRow(
              icon: CollectIcons.pending,
              title: 'Contribution issue',
              subtitle:
                  'Ask about a pending, missing, duplicate, or wrong contribution.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            SettingsLinkRow(
              icon: CollectIcons.qr,
              title: 'QR, sharing, or joining',
              subtitle: 'Get help finding, joining, scanning, or sharing.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            SettingsLinkRow(
              icon: CollectIcons.people,
              title: 'Membership or owner issue',
              subtitle: 'Get help with group access, roles, or ownership.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Privacy or deletion request',
              subtitle: 'Review privacy or create an auditable request.',
              onTap: () => context.go('/settings/account/delete'),
            ),
          ],
        ),
        const SectionHeader(title: 'Contact and policies'),
        SettingsOptionPanel(
          children: [
            SettingsLinkRow(
              icon: CollectIcons.support,
              title: 'WhatsApp support',
              subtitle: 'Contact IKANISA through the configured support line.',
              onTap: () => openCollectWhatsAppSupport(
                phone: runtimeConfig.whatsAppSupportPhone,
              ),
            ),
            SettingsLinkRow(
              icon: CollectIcons.privacy,
              title: 'Privacy policy',
              subtitle: 'Understand how Collect handles customer data.',
              onTap: () => context.go('/settings/legal/privacy'),
            ),
            SettingsLinkRow(
              icon: CollectIcons.info,
              title: 'Terms',
              subtitle: 'Review the rules for using Collect.',
              onTap: () => context.go('/settings/legal/terms'),
            ),
          ],
        ),
      ],
    );
  }
}
