import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/components/admin_data_table.dart';
import '../shared/components/admin_empty_state.dart';
import '../shared/components/admin_filter_bar.dart';
import '../shared/components/admin_loading_state.dart';
import '../shared/components/admin_page.dart';
import 'admin_models.dart';

/// Operator table adaptation of the bundled, offline Flutter license registry.
/// The mobile legal page and the notices supplied by each dependency stay intact.
class CloudflareAdminLicensesPage extends StatefulWidget {
  const CloudflareAdminLicensesPage({super.key});

  @override
  State<CloudflareAdminLicensesPage> createState() => _LicensesState();
}

class _LicensesState extends State<CloudflareAdminLicensesPage> {
  static const _pageSize = 25;
  static const _orders = {
    'package_asc',
    'package_desc',
    'notices_asc',
    'notices_desc',
  };
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _detailFocus = FocusNode(debugLabel: 'Admin legal notices');
  late Future<Map<String, List<_BundledNotice>>> _licenses;
  String _query = '', _filter = '', _order = 'package_asc';
  String? _selected;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _licenses = _readLicenses();
  }

  Future<Map<String, List<_BundledNotice>>> _readLicenses() async {
    final packages = <String, List<_BundledNotice>>{};
    await for (final entry in LicenseRegistry.licenses) {
      final names = entry.packages.toSet().toList();
      final notice = _BundledNotice(entry, names);
      for (final name in names) {
        (packages[name] ??= []).add(notice);
      }
    }
    return packages;
  }

  void _refresh() => setState(() {
    _query = _search.text.trim().toLowerCase();
    _page = 0;
    _licenses = _readLicenses();
  });

  void _sort(String value) {
    if (!_orders.contains(value)) return;
    setState(() {
      _order = value;
      _page = 0;
    });
  }

  void _open(String package) {
    setState(() => _selected = package);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selected == package) _detailFocus.requestFocus();
    });
  }

  void _backToIndex() {
    setState(() => _selected = null);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _detailFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminPage(
    title: _selected == null ? 'Open-source licenses' : 'License notices',
    subtitle: _selected == null
        ? 'Bundled software packages and their complete offline notices.'
        : 'Complete notices and package attributions from this build.',
    scrollController: _scroll,
    leading: IconButton(
      tooltip: _selected == null
          ? 'Back to account security'
          : 'Back to license index',
      onPressed: _selected == null
          ? () => context.go('/admin/security')
          : _backToIndex,
      icon: const Icon(Icons.arrow_back),
    ),
    child: FutureBuilder<Map<String, List<_BundledNotice>>>(
      future: _licenses,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AdminLoadingState(title: 'Loading bundled licenses');
        }
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The bundled license notices could not be read.'),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry license loading'),
              ),
            ],
          );
        }
        final packages = snapshot.data!;
        final selected = _selected;
        if (selected != null) {
          return Focus(
            focusNode: _detailFocus,
            child: _LegalNoticesTable(notices: packages[selected]!),
          );
        }
        final terms = _query.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
        final names = packages.keys
            .where(
              (name) =>
                  terms.every((term) => name.toLowerCase().contains(term)) &&
                  (_filter != 'multiple' || packages[name]!.length > 1),
            )
            .toList();
        names.sort((a, b) {
          final comparison = _order.startsWith('notices_')
              ? packages[a]!.length.compareTo(packages[b]!.length)
              : a.toLowerCase().compareTo(b.toLowerCase());
          if (comparison == 0) return a.compareTo(b);
          return _order.endsWith('_asc') ? comparison : -comparison;
        });
        final offset = (_page * _pageSize).clamp(0, names.length).toInt();
        final page = names.skip(offset).take(_pageSize).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminFilterBar(
              searchController: _search,
              searchLabel: 'Search all bundled packages',
              searchHint: 'Search packages',
              status: _filter,
              statusOptions: const [
                AdminFilterOption(value: '', label: 'All packages'),
                AdminFilterOption(value: 'multiple', label: 'Multiple notices'),
              ],
              sortBy: _order,
              sortOptions: const [
                AdminFilterOption(value: 'package_asc', label: 'Package A–Z'),
                AdminFilterOption(value: 'package_desc', label: 'Package Z–A'),
                AdminFilterOption(value: 'notices_desc', label: 'Most notices'),
                AdminFilterOption(
                  value: 'notices_asc',
                  label: 'Fewest notices',
                ),
              ],
              onStatusChanged: (value) => setState(() {
                _filter = value;
                _page = 0;
              }),
              onSortChanged: _sort,
              onRefresh: _refresh,
            ),
            const SizedBox(height: 16),
            if (names.isEmpty)
              AdminEmptyState(
                title: packages.isEmpty
                    ? 'No bundled license notices'
                    : 'No matching packages',
                message: packages.isEmpty
                    ? 'The license registry returned no package entries.'
                    : 'Change the search or filter to see other packages.',
              )
            else
              AdminDataTable(
                tableLabel: 'Bundled packages',
                sortBy: _order,
                onSortChanged: _sort,
                rows: [
                  for (final name in page)
                    AdminTableRowData(
                      id: name,
                      title: name,
                      subtitle: '',
                      status: '',
                      amount: '${packages[name]!.length}',
                    ),
                ],
                columns: [
                  AdminTableColumn(
                    label: 'Package',
                    sortKey: 'package',
                    value: (row) => row.title,
                  ),
                  AdminTableColumn(
                    label: 'Notices',
                    sortKey: 'notices',
                    numeric: true,
                    value: (row) => row.amount,
                  ),
                ],
                onOpen: (row) => _open(row.id),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${names.isEmpty ? 0 : offset + 1}–${offset + page.length} of ${names.length} packages',
                ),
                IconButton.outlined(
                  tooltip: 'Previous packages',
                  onPressed: _page == 0 ? null : () => setState(() => _page--),
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton.outlined(
                  tooltip: 'Next packages',
                  onPressed: offset + page.length >= names.length
                      ? null
                      : () => setState(() => _page++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

class _BundledNotice {
  const _BundledNotice(this.entry, this.packages);
  final LicenseEntry entry;
  final List<String> packages;
}

class _LegalNoticesTable extends StatelessWidget {
  const _LegalNoticesTable({required this.notices});
  final List<_BundledNotice> notices;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: 'Complete legal notices table, ${notices.length} notices',
    child: Table(
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(3)},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          children: [
            for (final label in ['Packages', 'Legal notice'])
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 12, 16),
                child: Semantics(
                  header: true,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
          ],
        ),
        for (final (index, notice) in notices.indexed)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 16, 32),
                child: SelectableText(notice.packages.join('\n')),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Semantics(
                  container: true,
                  label: 'Notice ${index + 1}',
                  child: _NoticeText(entry: notice.entry),
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _NoticeText extends StatelessWidget {
  const _NoticeText({required this.entry});
  final LicenseEntry entry;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    if (entry is LicenseEntryWithLineBreaks) {
      // Keep exact bundled notice text, including original paragraph breaks.
      return SelectableText(entry.text);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final paragraph in entry.paragraphs)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              paragraph.indent > 0
                  ? paragraph.indent.clamp(0, 2).toDouble() * 12
                  : 0,
              0,
              0,
              16,
            ),
            child: SelectableText(
              paragraph.text,
              textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                  ? TextAlign.center
                  : TextAlign.start,
            ),
          ),
      ],
    );
  }
}
