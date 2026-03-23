import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_market.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/cool_layout.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_empty_view.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/cool_bottom_sheet.dart';
import '../../../shared/widgets/cool_screen_background.dart';

EdgeInsets _quickActionsBodyPadding() => CoolSpace.pagePadding;

EdgeInsets _quickActionsListPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolLayout.rootBottomClearance,
);

EdgeInsets _quickActionsCardPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _quickActionTilePadding() => CoolSpace.sectionPadding.copyWith(
  left: CoolSpace.x4,
  right: CoolSpace.x4,
  top: CoolSpace.x2,
  bottom: CoolSpace.x2,
);

EdgeInsets _quickActionFieldPadding() => CoolSpace.sectionPadding.copyWith(
  left: 0,
  right: 0,
  top: 0,
  bottom: CoolSpace.x3,
);

EdgeInsets _quickActionsZeroPadding() =>
    CoolSpace.sectionPadding.copyWith(left: 0, right: 0, top: 0, bottom: 0);

EdgeInsets _quickActionSheetInsets(BuildContext context) {
  final space = context.coolSpace;
  return CoolSpace.pagePadding.copyWith(
    top: space.x3,
    bottom: MediaQuery.of(context).viewInsets.bottom + space.x6,
  );
}

OutlineInputBorder _quickActionInputBorder(
  CoolSemanticColors colors, {
  Color? borderColor,
  double width = 1,
}) {
  return OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.xs)),
    borderSide: BorderSide(color: borderColor ?? colors.border, width: width),
  );
}

Widget _quickActionSheetHandle(BuildContext context) {
  final colors = context.coolSemanticColors;
  return Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: colors.border,
      borderRadius: const BorderRadius.all(Radius.circular(CoolRadii.pill)),
    ),
  );
}

/// Admin screen for managing home-screen quick action cards.
class ManageQuickActionsScreen extends ConsumerStatefulWidget {
  const ManageQuickActionsScreen({super.key});

  @override
  ConsumerState<ManageQuickActionsScreen> createState() =>
      _ManageQuickActionsScreenState();
}

class _ManageQuickActionsScreenState
    extends ConsumerState<ManageQuickActionsScreen> {
  List<Map<String, dynamic>>? _localActions;

  void _onReorder(int oldIndex, int newIndex) {
    final actions = _localActions;
    if (actions == null) return;

    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = actions.removeAt(oldIndex);
      actions.insert(newIndex, item);
    });

    // Persist sort_order in the background.
    final orderedIds = actions
        .map((a) => a['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    ref.read(adminRepositoryProvider).reorderQuickActions(orderedIds);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    final actionsAsync = ref.watch(adminQuickActionsProvider);

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
          title: Text(
            'Quick Actions',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: colors.divider),
          ),
        ),
        floatingActionButton: Semantics(
          button: true,
          label: context.l10n.addQuickAction,
          hint: 'New action',
          child: FloatingActionButton(
            backgroundColor: colors.accent,
            onPressed: () => _showEditSheet(context, ref, null),
            child: Icon(Icons.add_rounded, color: colors.accentForeground),
          ),
        ),
        body: Padding(
          padding: _quickActionsBodyPadding(),
          child: CoolAsyncView<List<Map<String, dynamic>>>(
            value: actionsAsync,
            onRetry: () => ref.invalidate(adminQuickActionsProvider),
            loadingWidget: const CoolSkeletonList(itemCount: 4),
            emptyCheck: (a) => a.isEmpty,
            emptyWidget: const CoolEmptyView(
              message: 'No quick actions yet',
              icon: Icons.bolt_rounded,
            ),
            builder: (actions) {
              _localActions ??= List<Map<String, dynamic>>.from(actions);
              final displayActions = _localActions!;
              if (displayActions.isEmpty) {
                return const SizedBox.shrink();
              }
              return ReorderableListView.builder(
                itemCount: displayActions.length,
                onReorder: _onReorder,
                padding: _quickActionsListPadding(),
                itemBuilder: (context, index) {
                  final a = displayActions[index];
                  return Padding(
                    key: ValueKey(a['id']),
                    padding: _quickActionsCardPadding(),
                    child: CoolCard(
                      padding: _quickActionsZeroPadding(),
                      backgroundColor: colors.operationalSurface,
                      useGradient: false,
                      child: Semantics(
                        container: true,
                        label:
                            'Quick action ${a['title'] ?? ''}. Route ${a['route'] ?? ''}. '
                            'Market ${AppMarket.country.name}.',
                        child: ListTile(
                          contentPadding: _quickActionTilePadding(),
                          leading: Text(
                            a['emoji']?.toString() ?? '⚡',
                            style: theme.textTheme.titleMedium,
                          ),
                          title: Text(
                            a['title']?.toString() ?? '',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.primaryText,
                            ),
                          ),
                          subtitle: Text(
                            '${a['route']} · ${AppMarket.country.name}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.tertiaryText,
                            ),
                          ),
                          trailing: IconButton(
                            tooltip: 'Edit quick action ${a['title'] ?? ''}',
                            onPressed: () => _showEditSheet(context, ref, a),
                            icon: Icon(
                              Icons.edit_rounded,
                              size: 18,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic>? action,
  ) {
    showCoolBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditQuickActionSheet(action: action, ref: ref),
    ).then((_) {
      // Reset local cache so fresh data is picked up.
      setState(() => _localActions = null);
    });
  }
}

class _EditQuickActionSheet extends StatefulWidget {
  const _EditQuickActionSheet({this.action, required this.ref});
  final Map<String, dynamic>? action;
  final WidgetRef ref;
  @override
  State<_EditQuickActionSheet> createState() => _EditQuickActionSheetState();
}

class _EditQuickActionSheetState extends State<_EditQuickActionSheet> {
  late final TextEditingController _titleCtl,
      _subtitleCtl,
      _emojiCtl,
      _routeCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _titleCtl = TextEditingController(text: a?['title']?.toString() ?? '');
    _subtitleCtl = TextEditingController(
      text: a?['subtitle']?.toString() ?? '',
    );
    _emojiCtl = TextEditingController(text: a?['emoji']?.toString() ?? '');
    _routeCtl = TextEditingController(text: a?['route']?.toString() ?? '');
  }

  @override
  void dispose() {
    _titleCtl.dispose();
    _subtitleCtl.dispose();
    _emojiCtl.dispose();
    _routeCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'title': _titleCtl.text.trim(),
      'subtitle': _subtitleCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(),
      'route': _routeCtl.text.trim(),
      'country': AppMarket.countryCode,
    };
    if (widget.action != null) data['id'] = widget.action!['id'];
    try {
      await widget.ref.read(adminRepositoryProvider).upsertQuickAction(data);
      widget.ref.invalidate(adminQuickActionsProvider);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CoolToast.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.overlaySurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(CoolRadii.lg),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: _quickActionSheetInsets(context),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _quickActionSheetHandle(context),
                const SizedBox(height: CoolSpace.x4),
                Text(
                  widget.action != null
                      ? 'Edit Quick Action'
                      : 'New Quick Action',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                ),
                const SizedBox(height: CoolSpace.x4),
                _field('Title', _titleCtl),
                _field('Subtitle', _subtitleCtl),
                _field('Emoji', _emojiCtl),
                _field('Route', _routeCtl),
                _marketField(),
                const SizedBox(height: CoolSpace.x3),
                SizedBox(
                  width: double.infinity,
                  child: CoolButton(
                    label: 'Save',
                    onTap: _save,
                    isLoading: _saving,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: _quickActionFieldPadding(),
    child: Builder(
      builder: (context) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return Semantics(
          textField: true,
          label: label,
          hint: 'Enter $label',
          child: TextField(
            controller: ctl,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: theme.textTheme.bodySmall?.copyWith(
                color: colors.tertiaryText,
              ),
              filled: true,
              fillColor: colors.inputSurface,
              border: _quickActionInputBorder(colors),
              enabledBorder: _quickActionInputBorder(colors),
              focusedBorder: _quickActionInputBorder(
                colors,
                borderColor: colors.accent,
                width: 1.4,
              ),
              contentPadding: CoolSpace.sectionPadding.copyWith(
                left: CoolSpace.x3,
                right: CoolSpace.x3,
                top: CoolSpace.x3,
                bottom: CoolSpace.x3,
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _marketField() => Padding(
    padding: _quickActionFieldPadding(),
    child: Builder(
      builder: (context) {
        final colors = context.coolSemanticColors;
        final theme = Theme.of(context);
        return TextFormField(
          initialValue: AppMarket.country.name,
          enabled: false,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colors.primaryText,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            labelText: 'Market',
            labelStyle: theme.textTheme.bodySmall?.copyWith(
              color: colors.tertiaryText,
            ),
            filled: true,
            fillColor: colors.inputSurface.withValues(alpha: 0.55),
            border: _quickActionInputBorder(colors),
            disabledBorder: _quickActionInputBorder(colors),
            contentPadding: CoolSpace.sectionPadding.copyWith(
              left: CoolSpace.x3,
              right: CoolSpace.x3,
              top: CoolSpace.x3,
              bottom: CoolSpace.x3,
            ),
          ),
        );
      },
    ),
  );
}
