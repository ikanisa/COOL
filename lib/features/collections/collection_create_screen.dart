import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/collect_models.dart';
import '../../shared/repositories/collect_repository.dart';
import '../../shared/widgets/amount_input.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';

class CollectionCreateScreen extends ConsumerStatefulWidget {
  const CollectionCreateScreen({super.key});

  @override
  ConsumerState<CollectionCreateScreen> createState() =>
      _CollectionCreateScreenState();
}

class _CollectionCreateScreenState
    extends ConsumerState<CollectionCreateScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _target = TextEditingController();
  final _receiver = TextEditingController(text: '+250788123456');
  final _cover = TextEditingController();
  String _category = collectCategories.first;
  bool _recurring = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _target.dispose();
    _receiver.dispose();
    _cover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Create collection',
      subtitle: 'Set the goal, receiver, and privacy defaults before sharing.',
      children: [
        const InfoSecurityBanner(
          title: 'Private until approved',
          message:
              'Collections start private. Public directory listing requires platform approval and never exposes receiver MOMO publicly.',
          tone: CollectStatusTone.privacy,
        ),
        CollectCard(
          child: Column(
            children: [
              TextField(
                controller: _title,
                decoration: collectInputDecoration(context, label: 'Title'),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _description,
                maxLines: 4,
                decoration: collectInputDecoration(
                  context,
                  label: 'Story or description',
                ),
              ),
              CollectSpacing.gap12,
              DropdownButtonFormField<String>(
                initialValue: _category,
                items: [
                  for (final category in collectCategories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
                decoration: collectInputDecoration(context, label: 'Category'),
              ),
              CollectSpacing.gap12,
              AmountInput(controller: _target),
              CollectSpacing.gap12,
              TextField(
                controller: _receiver,
                keyboardType: TextInputType.phone,
                decoration: collectInputDecoration(
                  context,
                  label: 'Receiver MOMO number',
                  helper:
                      'Used only in contribution instructions and matching.',
                ),
              ),
              CollectSpacing.gap12,
              TextField(
                controller: _cover,
                keyboardType: TextInputType.url,
                decoration: collectInputDecoration(
                  context,
                  label: 'Cover image URL, optional',
                  helper:
                      'Public covers are shown only after directory approval.',
                ),
              ),
              CollectSpacing.gap12,
              SwitchListTile.adaptive(
                value: _recurring,
                onChanged: (value) => setState(() => _recurring = value),
                title: const Text('Recurring collection'),
                subtitle: const Text(
                  'Monthly periods and member obligations can be tracked.',
                ),
              ),
              CollectSpacing.gap16,
              CollectButton(
                label: 'Create private collection',
                icon: CollectIcons.check,
                onPressed: _create,
                expand: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _create() async {
    final collection = await ref
        .read(collectRepositoryProvider.notifier)
        .createCollection(
          title: _title.text.isEmpty ? 'Untitled collection' : _title.text,
          description: _description.text,
          category: _category,
          targetAmountRwf: int.tryParse(_target.text),
          receiverMomoNumber: _receiver.text,
          coverImageUrl: _cover.text,
          isRecurring: _recurring,
        );
    if (!mounted) return;
    context.go('/collections/${collection.id}');
  }
}
