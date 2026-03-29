import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_providers.dart';
import '../repositories/admin_content_repository.dart';

class ManagePartnersScreen extends ConsumerStatefulWidget {
  const ManagePartnersScreen({super.key});

  @override
  ConsumerState<ManagePartnersScreen> createState() =>
      _ManagePartnersScreenState();
}

class _ManagePartnersScreenState extends ConsumerState<ManagePartnersScreen> {
  Future<void> _openCreatePartnerSheet() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _CreatePartnerDialog(
        repository: ref.read(adminContentRepositoryProvider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final partnersAsync = ref.watch(adminPartnersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Partners')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreatePartnerSheet,
        child: const Icon(Icons.add_rounded),
      ),
      body: partnersAsync.when(
        data: (partners) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: partners.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final partner = partners[index];
            final slug = partner['slug']?.toString() ?? '';
            final category = partner['category']?.toString() ?? 'other';
            return ListTile(
              title: Text('$slug · $category'),
              subtitle: Text(partner['name']?.toString() ?? ''),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Failed to load: $error')),
      ),
    );
  }
}

class _CreatePartnerDialog extends StatefulWidget {
  const _CreatePartnerDialog({required this.repository});

  final AdminContentRepository repository;

  @override
  State<_CreatePartnerDialog> createState() => _CreatePartnerDialogState();
}

class _CreatePartnerDialogState extends State<_CreatePartnerDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _slugController;
  late final TextEditingController _emojiController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _whatsappController;
  var _category = 'bank';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _slugController = TextEditingController();
    _emojiController = TextEditingController();
    _subtitleController = TextEditingController();
    _whatsappController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _slugController.dispose();
    _emojiController.dispose();
    _subtitleController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.repository.upsertPartner(<String, dynamic>{
      'name': _nameController.text.trim(),
      'slug': _slugController.text.trim(),
      'category': _category,
      'emoji': _emojiController.text.trim(),
      'subtitle': _subtitleController.text.trim(),
      'whatsapp_number': _whatsappController.text.trim(),
      'country': 'RW',
    });
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Partner'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            TextField(
              controller: _slugController,
              decoration: const InputDecoration(labelText: 'Slug *'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: const [
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'football', child: Text('Football')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() => _category = value);
              },
            ),
            TextField(
              controller: _emojiController,
              decoration: const InputDecoration(labelText: 'Emoji'),
            ),
            TextField(
              controller: _subtitleController,
              decoration: const InputDecoration(labelText: 'Subtitle'),
            ),
            TextField(
              controller: _whatsappController,
              decoration: const InputDecoration(labelText: 'WhatsApp Number'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
