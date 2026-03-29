import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/tab_pill.dart';
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navGroups)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                TabPill(
                  label: l10n.navGroups,
                  isActive: _showMine,
                  onTap: () => setState(() => _showMine = true),
                ),
                TabPill(
                  label: 'Explore',
                  isActive: !_showMine,
                  onTap: () => setState(() => _showMine = false),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: groupsAsync.when(
                data: (groups) => ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return Card(
                      child: ListTile(
                        title: Text(group.name),
                        subtitle: Text(
                          '${group.memberCount} members · ${group.country}',
                        ),
                      ),
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Failed to load: $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
