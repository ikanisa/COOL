import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

part '../widgets/manage_services_parts.dart';

EdgeInsets _manageServicesHeaderPadding() =>
    CoolSpace.pagePadding.copyWith(top: 0, bottom: 0);

EdgeInsets _manageServicesListPadding() => CoolSpace.pagePadding.copyWith(
  top: 0,
  bottom: CoolLayout.rootBottomClearance,
);

EdgeInsets _manageServicesCardSpacing() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x2,
);

/// Admin screen for managing partner services — grouped by partner.
class ManageServicesScreen extends ConsumerWidget {
  const ManageServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final space = context.coolSpace;
    final servicesAsync = ref.watch(adminPartnerServicesProvider(null));
    final partners = ref.watch(adminPartnersProvider).valueOrNull ?? const [];

    return CoolScreenBackground(
      showGlow: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.back,
            icon: const Icon(Icons.arrow_back_rounded),
            color: colors.primaryText,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: context.l10n.addService,
          hint: 'New service',
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            onPressed: () => _showEditSheet(context, ref, null, partners),
            child: Icon(Icons.add_rounded, color: colors.accentForeground),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: _manageServicesHeaderPadding(),
              child: Text(
                'Manage Services',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: colors.primaryText,
                ),
              ),
            ),
            SizedBox(height: space.x2),
            Padding(
              padding: _manageServicesHeaderPadding(),
              child: Text(
                'Services under Partners — grouped by partner',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ),
            SizedBox(height: space.x3),
            Expanded(
              child: CoolAsyncView<List<Map<String, dynamic>>>(
                value: servicesAsync,
                onRetry: () =>
                    ref.invalidate(adminPartnerServicesProvider(null)),
                loadingWidget: const CoolSkeletonList(itemCount: 4),
                emptyCheck: (s) => s.isEmpty,
                emptyWidget: const CoolEmptyView(
                  message: 'No services yet',
                  icon: Icons.assignment_outlined,
                ),
                builder: (services) {
                  final grouped = <String, List<Map<String, dynamic>>>{};
                  for (final s in services) {
                    final partnerName =
                        (s['partners'] as Map?)?['name']?.toString() ?? 'Other';
                    grouped.putIfAbsent(partnerName, () => []).add(s);
                  }
                  final sortedKeys = grouped.keys.toList()..sort();

                  return ListView.builder(
                    padding: _manageServicesListPadding(),
                    itemCount: sortedKeys.length,
                    itemBuilder: (context, groupIndex) {
                      final partnerName = sortedKeys[groupIndex];
                      final groupServices = grouped[partnerName]!;
                      final partnerData = partners
                          .cast<Map<String, dynamic>>()
                          .firstWhere(
                            (p) => p['name']?.toString() == partnerName,
                            orElse: () => <String, dynamic>{},
                          );
                      final whatsapp =
                          partnerData['whatsapp_number']?.toString() ?? '';

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groupIndex > 0)
                            const SizedBox(height: CoolSpace.x5),
                          Row(
                            children: [
                              Text(
                                partnerData['emoji']?.toString() ?? '🤝',
                                style: theme.textTheme.bodyLarge,
                              ),
                              const SizedBox(width: CoolSpace.x2),
                              Expanded(
                                child: Text(
                                  'Services under $partnerName',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.primaryText,
                                  ),
                                ),
                              ),
                              _CountBadge(count: groupServices.length),
                            ],
                          ),
                          if (whatsapp.isNotEmpty) ...[
                            const SizedBox(height: CoolSpace.x1),
                            Row(
                              children: [
                                const SizedBox(
                                  width: CoolSpace.x6 + CoolSpace.x1,
                                ),
                                Icon(
                                  Icons.chat_rounded,
                                  size: 12,
                                  color: colors.tertiaryText,
                                ),
                                const SizedBox(width: CoolSpace.x1),
                                Flexible(
                                  child: Text(
                                    'WhatsApp: $whatsapp',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: colors.tertiaryText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: CoolSpace.x3),
                          ...groupServices.map(
                            (s) => Padding(
                              padding: _manageServicesCardSpacing(),
                              child: _ServiceCard(
                                service: s,
                                onEdit: () =>
                                    _showEditSheet(context, ref, s, partners),
                                onDelete: () => _deleteService(context, ref, s),
                                onToggleActive: () =>
                                    _toggleActive(context, ref, s),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? service,
    List<Map<String, dynamic>> partners,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          _EditServiceSheet(service: service, ref: ref, partners: partners),
    );
  }

  Future<void> _deleteService(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> service,
  ) async {
    final title = service['title']?.toString() ?? 'Service';
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text('This service will be permanently removed.'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(context.l10n.cancel),
            onPressed: () => Navigator.pop(context, false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .deletePartnerService(service['id']?.toString() ?? '');
      ref.invalidate(adminPartnerServicesProvider(null));
      if (context.mounted) CoolToast.success(context, '$title deleted');
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Error: $e');
    }
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> service,
  ) async {
    final isActive = service['is_active'] == true;
    try {
      await ref.read(adminRepositoryProvider).upsertPartnerService({
        'id': service['id'],
        'is_active': !isActive,
      });
      ref.invalidate(adminPartnerServicesProvider(null));
      if (context.mounted) {
        CoolToast.success(
          context,
          isActive ? 'Service deactivated' : 'Service activated',
        );
      }
    } catch (e) {
      if (context.mounted) CoolToast.error(context, 'Error: $e');
    }
  }
}

// ──────────────────────────────────────────────────────────────
// Count badge
// ──────────────────────────────────────────────────────────────
