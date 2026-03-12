import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_async_view.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../providers/admin_providers.dart';

/// Admin screen for managing supported countries (toggle active, view details).
class ManageCountriesScreen extends ConsumerWidget {
  const ManageCountriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countriesAsync = ref.watch(adminCountriesProvider);
    final issuesAsync = ref.watch(adminMomoValidationIssuesProvider);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          title: Text(
            'Countries',
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          iconTheme: const IconThemeData(color: AppColors.text),
          actions: [
            IconButton(
              tooltip: 'Refresh country validation',
              onPressed: () {
                ref.invalidate(adminCountriesProvider);
                ref.invalidate(adminMomoValidationIssuesProvider);
              },
              icon: const Icon(Icons.refresh_rounded, color: AppColors.text),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surface2,
                ),
                labelColor: AppColors.text,
                unselectedLabelColor: AppColors.text3,
                labelStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(text: 'Catalog'),
                  Tab(text: 'Issues'),
                ],
              ),
            ),
          ),
        ),
        body: TabBarView(
          children: [
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: countriesAsync,
              onRetry: () {
                ref.invalidate(adminCountriesProvider);
                ref.invalidate(adminMomoValidationIssuesProvider);
              },
              emptyCheck: (c) => c.isEmpty,
              emptyMessage: 'No countries',
              builder: (countries) {
                final activeCount = countries.where(_isCountryActive).length;
                final codeEnabledCount = countries
                    .where(_supportsMomoCode)
                    .length;
                final issuesCount = issuesAsync.maybeWhen(
                  data: (issues) => issues.length,
                  orElse: () => null,
                );

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: countries.length + 1,
                  separatorBuilder: (_, index) => index == 0
                      ? const SizedBox(height: 16)
                      : const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _CountrySummaryCard(
                        totalCountries: countries.length,
                        activeCountries: activeCount,
                        merchantCodeCountries: codeEnabledCount,
                        issueCount: issuesCount,
                      );
                    }

                    final country = countries[index - 1];
                    return _CountryCard(
                      country: country,
                      onToggleActive: (isActive) async {
                        await ref.read(adminRepositoryProvider).updateCountry(
                          country['iso_code'].toString(),
                          {'is_active': isActive},
                        );
                        ref.invalidate(adminCountriesProvider);
                        ref.invalidate(adminMomoValidationIssuesProvider);
                      },
                    );
                  },
                );
              },
            ),
            CoolAsyncView<List<Map<String, dynamic>>>(
              value: issuesAsync,
              onRetry: () => ref.invalidate(adminMomoValidationIssuesProvider),
              emptyCheck: (i) => i.isEmpty,
              emptyMessage:
                  'No validation issues detected. Existing users and groups match the current MoMo country rules.',
              builder: (issues) {
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: issues.length + 1,
                  separatorBuilder: (_, index) => index == 0
                      ? const SizedBox(height: 16)
                      : const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _IssueSummaryCard(issues: issues);
                    }
                    return _ValidationIssueCard(issue: issues[index - 1]);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CountrySummaryCard extends StatelessWidget {
  const _CountrySummaryCard({
    required this.totalCountries,
    required this.activeCountries,
    required this.merchantCodeCountries,
    required this.issueCount,
  });

  final int totalCountries;
  final int activeCountries;
  final int merchantCodeCountries;
  final int? issueCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Country Validation Catalog',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This catalog now carries country aliases, mobile-number validation, MoMo USSD route shapes, and explicit merchant-code support boundaries.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Countries', value: totalCountries.toString()),
              _MetricChip(label: 'Active', value: activeCountries.toString()),
              _MetricChip(
                label: 'Code Routes',
                value: merchantCodeCountries.toString(),
              ),
              _MetricChip(
                label: 'Issues',
                value: issueCount?.toString() ?? '…',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.country, required this.onToggleActive});

  final Map<String, dynamic> country;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final isActive = _isCountryActive(country);
    final aliases = _asStringList(country['country_aliases']);
    final providerAliases = _asStringList(country['momo_provider_aliases']);
    final lengths = _asIntList(country['mobile_possible_lengths']);
    final numberExample = _trimmed(country['mobile_example_national']);
    final e164Example = _trimmed(country['mobile_example_e164']);
    final numberUssdExample = _trimmed(country['momo_number_ussd_example']);
    final codeExample = _trimmed(country['momo_code_example']);
    final codeUssdExample = _trimmed(country['momo_code_ussd_example']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                country['flag_emoji']?.toString() ?? '🏳️',
                style: const TextStyle(fontSize: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country['country_name']?.toString() ?? '',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${country['iso_code']} · ${country['dial_code']} · ${country['currency_code']}',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text3,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                activeTrackColor: AppColors.accent,
                onChanged: onToggleActive,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                label: isActive ? 'Active' : 'Disabled',
                color: isActive ? AppColors.accent : AppColors.text3,
              ),
              _StatusChip(label: 'Phone route', color: AppColors.blue),
              _StatusChip(
                label: _supportsMomoCode(country)
                    ? 'Merchant code'
                    : 'No code route',
                color: _supportsMomoCode(country)
                    ? AppColors.orange
                    : AppColors.text3,
              ),
              if (lengths.isNotEmpty)
                _StatusChip(
                  label: '${lengths.join('/')} digits',
                  color: AppColors.yellow,
                ),
            ],
          ),
          const SizedBox(height: 12),
          _DetailLine(
            label: 'Phone examples',
            value: [
              numberExample,
              if (e164Example != null) 'E.164 $e164Example',
            ].whereType<String>().join('  •  '),
          ),
          if (numberUssdExample != null)
            _DetailLine(label: 'Phone USSD', value: numberUssdExample),
          if (codeExample != null || codeUssdExample != null)
            _DetailLine(
              label: 'Merchant code',
              value: [
                if (codeExample case final example?) 'Example $example',
                if (codeUssdExample != null) 'USSD $codeUssdExample',
              ].whereType<String>().join('  •  '),
            ),
          if (aliases.isNotEmpty)
            _DetailLine(label: 'Country aliases', value: aliases.join(', ')),
          if (providerAliases.isNotEmpty)
            _DetailLine(
              label: 'Provider aliases',
              value: providerAliases.join(', '),
            ),
          _DetailLine(
            label: 'Sources',
            value: [
              _trimmed(country['phone_validation_source']),
              _trimmed(country['momo_ussd_source']),
            ].whereType<String>().join('  •  '),
          ),
          if (_trimmed(country['validation_notes']) case final notes?)
            _DetailLine(label: 'Notes', value: notes),
        ],
      ),
    );
  }
}

class _IssueSummaryCard extends StatelessWidget {
  const _IssueSummaryCard({required this.issues});

  final List<Map<String, dynamic>> issues;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    final affectedCountries = <String>{};

    for (final issue in issues) {
      final issueCode = _trimmed(issue['issue_code']) ?? 'unknown_issue';
      counts.update(issueCode, (value) => value + 1, ifAbsent: () => 1);
      final country = _trimmed(issue['country']);
      if (country != null) {
        affectedCountries.add(country);
      }
    }

    final sortedIssueCodes = counts.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Validation Issues',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'These records already exist in the database but do not satisfy the current country-aware MoMo rules.',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppColors.text3,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(label: 'Issues', value: issues.length.toString()),
              _MetricChip(
                label: 'Countries',
                value: affectedCountries.length.toString(),
              ),
              for (final issueCode in sortedIssueCodes)
                _MetricChip(
                  label: _humanizeIssueCode(issueCode),
                  value: counts[issueCode].toString(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValidationIssueCard extends StatelessWidget {
  const _ValidationIssueCard({required this.issue});

  final Map<String, dynamic> issue;

  @override
  Widget build(BuildContext context) {
    final recordType = _trimmed(issue['record_type']) ?? 'record';
    final country = _trimmed(issue['country']) ?? 'Unknown country';
    final routeType = _trimmed(issue['route_type']);
    final momoNumber = _trimmed(issue['momo_number']);
    final momoCode = _trimmed(issue['momo_code']);
    final expectedPhone = _trimmed(issue['expected_phone_example']);
    final expectedCode = _trimmed(issue['expected_code_example']);
    final phoneUssd = _trimmed(issue['phone_ussd_example']);
    final codeUssd = _trimmed(issue['code_ussd_example']);
    final issueCode = _trimmed(issue['issue_code']) ?? 'unknown_issue';
    final issueMessage = _trimmed(issue['issue_message']) ?? 'Validation issue';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                label: _humanizeIssueCode(issueCode),
                color: AppColors.red,
              ),
              _StatusChip(label: recordType, color: AppColors.blue),
              _StatusChip(label: country, color: AppColors.yellow),
              if (routeType != null)
                _StatusChip(label: routeType, color: AppColors.orange),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            issueMessage,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 10),
          if (momoNumber != null)
            _DetailLine(label: 'Stored number', value: momoNumber),
          if (momoCode != null)
            _DetailLine(label: 'Stored code', value: momoCode),
          if (expectedPhone != null)
            _DetailLine(label: 'Expected phone', value: expectedPhone),
          if (expectedCode != null)
            _DetailLine(label: 'Expected code', value: expectedCode),
          if (phoneUssd != null)
            _DetailLine(label: 'Phone route', value: phoneUssd),
          if (codeUssd != null)
            _DetailLine(label: 'Code route', value: codeUssd),
          const SizedBox(height: 12),
          _IssueActionRow(issue: issue),
        ],
      ),
    );
  }
}

class _IssueActionRow extends ConsumerStatefulWidget {
  const _IssueActionRow({required this.issue});

  final Map<String, dynamic> issue;

  @override
  ConsumerState<_IssueActionRow> createState() => _IssueActionRowState();
}

class _IssueActionRowState extends ConsumerState<_IssueActionRow> {
  bool _isRepairing = false;

  Future<void> _repairIssue() async {
    final recordType = _trimmed(widget.issue['record_type']);
    final recordId = _trimmed(widget.issue['record_id']);
    final issueCode = _trimmed(widget.issue['issue_code']);
    if (recordType == null || recordId == null || issueCode == null) {
      return;
    }

    setState(() => _isRepairing = true);
    try {
      final result = await ref
          .read(adminRepositoryProvider)
          .repairMomoValidationIssue(
            recordType: recordType,
            recordId: recordId,
            issueCode: issueCode,
          );

      ref.invalidate(adminMomoValidationIssuesProvider);
      ref.invalidate(adminCountriesProvider);

      if (!mounted) {
        return;
      }

      final message =
          _trimmed(result['message']) ?? 'Repair attempt completed.';
      CoolToast.success(context, message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CoolToast.error(context, 'Repair failed: $error');
    } finally {
      if (mounted) {
        setState(() => _isRepairing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isRepairable(widget.issue)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _isRepairing ? null : _repairIssue,
          icon: _isRepairing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.build_circle_outlined, size: 16),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: const BorderSide(color: AppColors.accent),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          label: Text(
            'Attempt Repair',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Text(
      'Manual correction required for this issue type.',
      style: GoogleFonts.dmSans(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.text3,
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(color: AppColors.text),
          children: [
            TextSpan(
              text: '$value ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: label,
              style: const TextStyle(
                color: AppColors.text3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.text3,
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

bool _isCountryActive(Map<String, dynamic> country) =>
    country['is_active'] == true;

bool _supportsMomoCode(Map<String, dynamic> country) =>
    country['supports_momo_code'] == true;

List<String> _asStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return const <String>[];
}

List<int> _asIntList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => int.tryParse(item.toString()))
        .whereType<int>()
        .toList(growable: false);
  }
  return const <int>[];
}

String? _trimmed(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

String _humanizeIssueCode(String code) {
  final words = code
      .split('_')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .toList(growable: false);
  return words.isEmpty ? 'Issue' : words.join(' ');
}

bool _isRepairable(Map<String, dynamic> issue) {
  if (issue['repair_supported'] == false) {
    return false;
  }

  final recordType = _trimmed(issue['record_type']);
  final issueCode = _trimmed(issue['issue_code']);

  return recordType == 'group' &&
      (issueCode == 'unsupported_route_type' ||
          issueCode == 'invalid_momo_code' ||
          issueCode == 'invalid_phone_recipient');
}
