import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/cool_async_view.dart';
import '../../../../shared/widgets/cool_card.dart';
import '../../../../shared/widgets/cool_empty_view.dart';
import '../../../../shared/widgets/cool_toast.dart';
import '../../../partners/providers/rayon_sports_provider.dart';
import '../models/rs_models.dart';
import '../providers/rs_admin_provider.dart';
import '../rs_membership_package.dart';
import '../widgets/rs_admin_shell.dart';

class RsAdminPackagesScreen extends ConsumerStatefulWidget {
  const RsAdminPackagesScreen({super.key});

  @override
  ConsumerState<RsAdminPackagesScreen> createState() =>
      _RsAdminPackagesScreenState();
}

class _RsAdminPackagesScreenState extends ConsumerState<RsAdminPackagesScreen> {
  bool _isSavingPackage = false;
  String? _activePackageTier;
  String? _activePackageAction;

  Future<void> _editPackage(RsMembershipPackage package) async {
    if (_isSavingPackage) {
      return;
    }

    final titleController = TextEditingController(text: package.title);
    final subtitleController = TextEditingController(text: package.subtitle);
    final descriptionController = TextEditingController(
      text: package.description,
    );
    final benefitsController = TextEditingController(
      text: package.benefits
          .map((benefit) => '${benefit.title} | ${benefit.description}')
          .join('\n'),
    );
    var isActive = package.isActive;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Edit ${package.tier.label} package',
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Supporter-facing tier copy and',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subtitleController,
                      decoration: const InputDecoration(labelText: 'Subtitle'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: benefitsController,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Benefits',
                        helperText:
                            'One line per benefit',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Package active'),
                      subtitle: const Text(
                        'Inactive packages remain hidden',
                      ),
                      value: isActive,
                      onChanged: (value) =>
                          setModalState(() => isActive = value),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          final title = titleController.text.trim();
                          final subtitle = subtitleController.text.trim();
                          final description = descriptionController.text.trim();
                          final benefits = _parseBenefits(
                            benefitsController.text,
                          );
                          if (title.isEmpty ||
                              subtitle.isEmpty ||
                              benefits.isEmpty) {
                            CoolToast.error(
                              context,
                              'Title, subtitle, and at least one benefit are required.',
                            );
                            return;
                          }

                          Navigator.of(context).pop();
                          setState(() {
                            _isSavingPackage = true;
                            _activePackageTier = package.tier.name;
                            _activePackageAction = 'save';
                          });
                          try {
                            final repository = ref.read(
                              rayonSportsRepositoryProvider,
                            );
                            await repository.upsertMembershipPackage(
                              tier: package.tier,
                              title: title,
                              subtitle: subtitle,
                              description: description,
                              benefits: benefits,
                              isActive: isActive,
                              sortOrder: package.sortOrder,
                            );
                            ref.invalidate(rsAdminMembershipPackagesProvider);
                            ref.invalidate(rayonMembershipPackagesProvider);
                            if (!mounted) {
                              return;
                            }
                            CoolToast.success(
                              this.context,
                              '${package.tier.label} package saved.',
                            );
                          } catch (_) {
                            if (!mounted) {
                              return;
                            }
                            CoolToast.error(
                              this.context,
                              'Could not save this membership package.',
                            );
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isSavingPackage = false;
                                _activePackageTier = null;
                                _activePackageAction = null;
                              });
                            }
                          }
                        },
                        child: const Text('Save package'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _togglePackage(RsMembershipPackage package) async {
    if (_isSavingPackage) {
      return;
    }

    setState(() {
      _isSavingPackage = true;
      _activePackageTier = package.tier.name;
      _activePackageAction = package.isActive ? 'deactivate' : 'activate';
    });
    try {
      final repository = ref.read(rayonSportsRepositoryProvider);
      await repository.upsertMembershipPackage(
        tier: package.tier,
        title: package.title,
        subtitle: package.subtitle,
        description: package.description,
        benefits: package.benefits,
        isActive: !package.isActive,
        sortOrder: package.sortOrder,
      );
      ref.invalidate(rsAdminMembershipPackagesProvider);
      ref.invalidate(rayonMembershipPackagesProvider);
      if (!mounted) {
        return;
      }
      CoolToast.success(
        context,
        !package.isActive
            ? '${package.tier.label} package activated.'
            : '${package.tier.label} package deactivated.',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Could not update package visibility.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPackage = false;
          _activePackageTier = null;
          _activePackageAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(rsAdminMembershipPackagesProvider);
    final membersAsync = ref.watch(rsAdminMembersProvider);
    final activeCount =
        packagesAsync.whenOrNull(
          data: (packages) =>
              packages.where((package) => package.isActive).length,
        ) ??
        0;

    return RsAdminShell(
      title: 'Membership Packages',
      subtitle:
          'Manage supporter-facing tier copy',
      metrics: [
        RsAdminMetric(
          label: 'plans',
          value:
              packagesAsync.whenOrNull(
                data: (packages) => '${packages.length}',
              ) ??
              '...',
        ),
        RsAdminMetric(label: 'active', value: '$activeCount'),
        RsAdminMetric(
          label: 'members',
          value:
              membersAsync.whenOrNull(data: (members) => '${members.length}') ??
              '...',
        ),
      ],
      child: CoolAsyncView<List<RsMembershipPackage>>(
        value: packagesAsync,
        emptyCheck: (packages) => packages.isEmpty,
        emptyWidget: const CoolEmptyView(
          message: 'No membership packages yet',
          compact: true,
        ),
        builder: (packages) => ListView(
          children: packages
              .map(
                (package) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PackageCard(
                    package: package,
                    isBusy: _activePackageTier == package.tier.name,
                    busyAction: _activePackageAction,
                    onEdit: () => _editPackage(package),
                    onToggleActive: () => _togglePackage(package),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.isBusy,
    required this.busyAction,
    required this.onEdit,
    required this.onToggleActive,
  });

  final RsMembershipPackage package;
  final bool isBusy;
  final String? busyAction;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final tier = package.tier;
    return CoolCard(
      borderColor: package.isActive
          ? tier.color.withValues(alpha: 0.32)
          : AppColors.border2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.title,
                      style: GoogleFonts.barlow(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.rsWhite,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      package.subtitle,
                      style: GoogleFonts.barlow(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              _PackageStatusPill(package: package),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoPill(label: 'Tier', value: tier.label),
              _InfoPill(label: 'Threshold', value: '${tier.minPoints}+ pts'),
              _InfoPill(
                label: 'Benefits',
                value: package.benefits.length.toString(),
              ),
            ],
          ),
          if (package.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              package.description,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text2,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...package.benefits.map(
            (benefit) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _benefitIcon(benefit.title),
                    size: 16,
                    color: package.isActive ? tier.color : AppColors.text3,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          benefit.title,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        if (benefit.description.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            benefit.description,
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.text2,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: isBusy ? null : onEdit,
                child: Text(
                  isBusy && busyAction == 'save' ? 'Saving...' : 'Edit package',
                ),
              ),
              TextButton(
                onPressed: isBusy ? null : onToggleActive,
                child: Text(
                  isBusy && busyAction != 'save'
                      ? (busyAction == 'activate'
                            ? 'Activating...'
                            : 'Deactivating...')
                      : (package.isActive ? 'Deactivate' : 'Activate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackageStatusPill extends StatelessWidget {
  const _PackageStatusPill({required this.package});

  final RsMembershipPackage package;

  @override
  Widget build(BuildContext context) {
    final color = package.isActive ? package.tier.color : AppColors.text3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        package.isActive ? 'Active' : 'Inactive',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        '$label: $value',
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
      ),
    );
  }
}

List<RsMembershipPackageBenefit> _parseBenefits(String raw) {
  return raw
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) {
        final parts = line.split('|');
        final title = parts.first.trim();
        final description = parts.length > 1
            ? parts.sublist(1).join('|').trim()
            : '';
        return RsMembershipPackageBenefit(
          title: title,
          description: description,
        );
      })
      .where((benefit) => benefit.title.isNotEmpty)
      .toList(growable: false);
}

IconData _benefitIcon(String title) {
  final normalized = title.toLowerCase();
  if (normalized.contains('ticket')) {
    return Icons.confirmation_number_rounded;
  }
  if (normalized.contains('shop') || normalized.contains('kit')) {
    return Icons.shopping_bag_rounded;
  }
  if (normalized.contains('meet') || normalized.contains('event')) {
    return Icons.handshake_rounded;
  }
  if (normalized.contains('discount')) {
    return Icons.local_offer_rounded;
  }
  if (normalized.contains('badge')) {
    return Icons.workspace_premium_rounded;
  }
  return Icons.star_rounded;
}
