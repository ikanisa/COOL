import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_skeleton.dart';
import '../providers/admin_providers.dart';

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
    final actionsAsync = ref.watch(adminQuickActionsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text('Quick Actions', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _showEditSheet(context, ref, null),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: actionsAsync.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: CoolSkeletonList()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.text3))),
        data: (actions) {
          _localActions ??= List<Map<String, dynamic>>.from(actions);
          final displayActions = _localActions!;
          if (displayActions.isEmpty) {
            return const Center(child: Text('No quick actions', style: TextStyle(color: AppColors.text3)));
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: displayActions.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final a = displayActions[index];
              return Padding(
                key: ValueKey(a['id']),
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                  child: ListTile(
                    leading: Text(a['emoji']?.toString() ?? '⚡', style: const TextStyle(fontSize: 22)),
                    title: Text(a['title']?.toString() ?? '', style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text)),
                    subtitle: Text('${a['route']} · ${a['country'] ?? 'global'}', style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.text3)),
                    trailing: GestureDetector(
                      onTap: () => _showEditSheet(context, ref, a),
                      child: const Icon(Icons.edit_rounded, size: 18, color: AppColors.text3),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Map<String, dynamic>? action) {
    showModalBottomSheet<void>(
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
  late final TextEditingController _titleCtl, _subtitleCtl, _emojiCtl, _routeCtl, _countryCtl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.action;
    _titleCtl = TextEditingController(text: a?['title']?.toString() ?? '');
    _subtitleCtl = TextEditingController(text: a?['subtitle']?.toString() ?? '');
    _emojiCtl = TextEditingController(text: a?['emoji']?.toString() ?? '');
    _routeCtl = TextEditingController(text: a?['route']?.toString() ?? '');
    _countryCtl = TextEditingController(text: a?['country']?.toString() ?? '');
  }

  @override
  void dispose() { _titleCtl.dispose(); _subtitleCtl.dispose(); _emojiCtl.dispose(); _routeCtl.dispose(); _countryCtl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'title': _titleCtl.text.trim(), 'subtitle': _subtitleCtl.text.trim(),
      'emoji': _emojiCtl.text.trim(), 'route': _routeCtl.text.trim(),
      'country': _countryCtl.text.trim().isEmpty ? null : _countryCtl.text.trim(),
    };
    if (widget.action != null) data['id'] = widget.action!['id'];
    try {
      await widget.ref.read(adminRepositoryProvider).upsertQuickAction(data);
      widget.ref.invalidate(adminQuickActionsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: SafeArea(top: false, child: Padding(
        padding: EdgeInsets.fromLTRB(22, 12, 22, MediaQuery.of(context).viewInsets.bottom + 22),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border2, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(widget.action != null ? 'Edit Quick Action' : 'New Quick Action', style: GoogleFonts.dmSans(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.text)),
          const SizedBox(height: 16),
          _field('Title', _titleCtl), _field('Subtitle', _subtitleCtl), _field('Emoji', _emojiCtl), _field('Route', _routeCtl), _field('Country (ISO, blank=global)', _countryCtl),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Save', style: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black)),
          )),
        ])),
      )),
    );
  }

  Widget _field(String label, TextEditingController ctl) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: ctl, style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
      decoration: InputDecoration(labelText: label, labelStyle: GoogleFonts.dmSans(color: AppColors.text3), filled: true, fillColor: AppColors.surface2, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
  );
}
