import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/tab_pill.dart';
import '../models/group.dart';
import '../providers/groups_provider.dart';

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  bool _showMine = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groupsAsync = ref.watch(
      _showMine ? myGroupsProvider : publicGroupsProvider,
    );
    final textTheme = context.coolText;
    final colors = context.coolSemanticColors;
    final space = context.coolSpace;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: colors.appBackground.withValues(alpha: 0.9),
            elevation: 0,
            pinned: true,
            title: Text(
              l10n.navGroups.toUpperCase(),
              style: textTheme.displayCondensed(null, letterSpacing: 1.2),
            ),
            actions: [
              const _DataPulseBadge().animate().fadeIn(),
              SizedBox(width: space.x4),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: space.x4,
                vertical: space.x3,
              ),
              child: AnimatedSwitcher(
                duration: CoolMotion.quick,
                child: Row(
                  key: ValueKey<bool>(_showMine),
                  children: [
                    Expanded(
                      child: TabPill(
                        label: 'My Ledgers',
                        isActive: _showMine,
                        onTap: () => setState(() => _showMine = true),
                      ),
                    ),
                    SizedBox(width: space.x2),
                    Expanded(
                      child: TabPill(
                        label: 'Explore',
                        isActive: !_showMine,
                        onTap: () => setState(() => _showMine = false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No ledgers found.',
                      style: textTheme.mono(null, color: colors.secondaryText),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: space.x4),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final group = groups[index];
                      return Padding(
                        padding: EdgeInsets.only(bottom: space.x3),
                        child: _GroupLedgerCard(group: group),
                      );
                    },
                    childCount: groups.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Failed to load: $error',
                  style: TextStyle(color: colors.danger),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.paddingOf(context).bottom + 80,
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLedgerCard extends StatelessWidget {
  const _GroupLedgerCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;
    final space = context.coolSpace;
    final isPublic = group.visibility == 'public';

    return Container(
      padding: EdgeInsets.all(space.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
        boxShadow: CoolShadows.standard(Theme.of(context).brightness),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  group.name,
                  style: textTheme.display(
                    null,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:
                      isPublic
                          ? colors.info.withValues(alpha: 0.15)
                          : colors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  border: Border.all(
                    color:
                        isPublic
                            ? colors.info.withValues(alpha: 0.3)
                            : colors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isPublic ? 'PUBLIC' : 'PRIVATE',
                  style: textTheme.mobiLabel(
                    color: isPublic ? colors.info : colors.warning,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: space.x1),
          Text(
            '${group.memberCount} Members • ${group.country}',
            style: textTheme.mobiLabel(color: colors.secondaryText),
          ),
          SizedBox(height: space.x3),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: space.x3,
              vertical: space.x2,
            ),
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(CoolRadii.md),
              border: Border.all(color: colors.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BALANCE',
                      style: textTheme.mobiLabel(color: colors.tertiaryText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${group.amount} RWF',
                      style: textTheme.mono(null, color: colors.accentGold),
                    ),
                  ],
                ),
                if (group.targetAmount > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'TARGET',
                        style: textTheme.mobiLabel(color: colors.tertiaryText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.targetAmount} RWF',
                        style: textTheme.mono(
                          null,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          SizedBox(height: space.x3),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () {
                try {
                  GoRouter.of(context).push('/biopay/scan?mode=pay');
                } catch (_) {
                  Navigator.of(context).pushNamed('/biopay/scan?mode=pay');
                }
              },
              icon: Icon(Icons.face_retouching_natural_rounded, color: colors.accentForeground),
              label: Text(
                'CONTRIBUTE VIA FACE PAY',
                style: textTheme.mobiLabel(color: colors.accentForeground).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: colors.accent,
                padding: EdgeInsets.symmetric(vertical: space.x3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CoolRadii.md),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0.0);
  }
}

class _DataPulseBadge extends StatefulWidget {
  const _DataPulseBadge();

  @override
  State<_DataPulseBadge> createState() => _DataPulseBadgeState();
}

class _DataPulseBadgeState extends State<_DataPulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = context.coolText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final opacity = 0.4 + (_ctrl.value * 0.6);
              return Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.success.withValues(alpha: opacity),
                  boxShadow: [
                    BoxShadow(
                      color: colors.success.withValues(alpha: opacity * 0.5),
                      blurRadius: 4,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          Text('LIVE', style: textTheme.mobiLabel(color: colors.success)),
        ],
      ),
    );
  }
}

