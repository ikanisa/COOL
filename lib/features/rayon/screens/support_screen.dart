import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/cool_foundations.dart';
import '../../../../core/theme/rs_colors.dart';
import '../../../../shared/widgets/cool_skeleton.dart';
import '../../../../shared/widgets/rs_initiative_card.dart';

import '../models/rs_initiative_models.dart';
import '../providers/rayon_sports_provider.dart';
import '../../../../shared/widgets/core_app_scaffold.dart';

enum _SupportFilter {
  all('ALL'),
  infrastructure('INFRASTRUCTURE');

  const _SupportFilter(this.label);
  final String label;
}

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _searchController = TextEditingController();
  var _filter = _SupportFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final initiativesAsync = ref.watch(rayonInitiativesProvider);

    return CoreAppScaffold(
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUPPORT CLUB',
            style: text.rayonCondensed(
              const TextStyle(fontSize: 28),
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'ACTIVE INITIATIVES',
            style: text.mono(
              theme.textTheme.labelSmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
      fallbackLocation: AppRoutes.rayonHome,
      scrollable: false,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // ─── Search + Filters ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SearchBar(
                    controller: _searchController,
                    onChanged: (val) => setState(() {}),
                  ),
                  const SizedBox(height: CoolSpace.x4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter in _SupportFilter.values) ...[
                          _CategoryChip(
                            emoji: filter == _SupportFilter.all ? '⚡' : '⚙️',
                            label: filter.label,
                            isSelected: filter == _filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                          if (filter != _SupportFilter.values.last)
                            const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ─── "♡ ACTIVE CAUSES" section header ─────────────
                  Row(
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        size: 18,
                        color: RsColors.rsNavyLight,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'ACTIVE CAUSES',
                        style: text.mono(
                          theme.textTheme.labelMedium,
                          fontWeight: FontWeight.w700,
                          color: colors.secondaryText,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: CoolSpace.x4),
                ],
              ),
            ),
          ),

          // ─── Initiative list ──────────────────────────────────────
          ...initiativesAsync.when(
            loading: () => <Widget>[
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: CoolSkeletonList()),
              ),
            ],
            error: (error, stackTrace) => <Widget>[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(
                  child: _StateCard(
                    icon: Icons.warning_amber_rounded,
                    title: 'Failed to load causes',
                    subtitle: 'Pull to retry',
                    actionLabel: 'Retry',
                    onTap: () => ref.invalidate(rayonInitiativesProvider),
                  ),
                ),
              ),
            ],
            data: (initiatives) {
              final query = _searchController.text.toLowerCase().trim();
              var filtered = _filter == _SupportFilter.infrastructure
                  ? const <RsInitiative>[]
                  : initiatives;

              if (query.isNotEmpty) {
                filtered = filtered
                    .where(
                      (i) =>
                          i.title.toLowerCase().contains(query) ||
                          i.description.toLowerCase().contains(query),
                    )
                    .toList();
              }

              if (filtered.isEmpty) {
                return const <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(child: _EmptyInitiativesState()),
                  ),
                ];
              }

              return <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final initiative = filtered[index];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: index == filtered.length - 1 ? 0 : 18,
                        ),
                        child: RsInitiativeCard(
                          initiative: initiative,
                          onTap: () => context.push(
                            AppRoutes.contributionDetailLocation(initiative.id),
                          ),
                          onSupportTap: () => context.push(
                            AppRoutes.contributionDetailLocation(initiative.id),
                          ),
                        ),
                      );
                    }, childCount: filtered.length),
                  ),
                ),
              ];
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

// ─── Search bar ───────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: text.rayon(
          theme.textTheme.bodyMedium,
          fontWeight: FontWeight.w700,
          color: colors.primaryText,
        ),
        cursorColor: colors.accent,
        decoration: InputDecoration(
          hintText: 'SEARCH INITIATIVES...',
          hintStyle: text.rayon(
            theme.textTheme.bodyMedium,
            fontWeight: FontWeight.w600,
            color: colors.tertiaryText,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: colors.secondaryText),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
        ),
      ),
    );
  }
}

// ─── Category chip with emoji ─────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.emoji,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? RsColors.rsRed : Colors.transparent,
          borderRadius: BorderRadius.circular(CoolRadii.pill),
          border: Border.all(
            color: isSelected ? RsColors.rsRed : colors.borderStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: text.rayonCondensed(
                Theme.of(context).textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────

class _EmptyInitiativesState extends StatelessWidget {
  const _EmptyInitiativesState();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final text = context.coolText;
    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurfaceStrong.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colors.cardSurface,
              borderRadius: BorderRadius.circular(CoolRadii.lg),
              border: Border.all(color: colors.borderStrong),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.stadium_rounded,
              size: 34,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x5),
          Text(
            'No active causes right now',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CoolSpace.x2),
          Text(
            'Check back soon for new fundraising programs.',
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Error state card ─────────────────────────────────────────────────────

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: colors.warning),
          const SizedBox(height: CoolSpace.x3),
          Text(
            title,
            style: text.rayonCondensed(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x1),
          Text(
            subtitle,
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: RsColors.rsRed,
                borderRadius: BorderRadius.circular(CoolRadii.pill),
              ),
              child: Text(
                actionLabel,
                style: text.rayonCondensed(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
