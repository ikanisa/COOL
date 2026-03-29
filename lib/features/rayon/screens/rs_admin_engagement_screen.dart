import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../core/theme/rs_colors.dart';
import '../../../core/theme/rs_text_styles.dart';
import '../../../shared/widgets/cool_card.dart';
import '../models/rs_models.dart';
import '../providers/rayon_sports_provider.dart';
import '../providers/rs_engagement_provider.dart';
import '../repositories/rayon_sports_repository.dart';

part '../widgets/rs_admin_engagement_parts.dart';

/// Admin Engagement screen — create/manage polls, enter match results, award XP.
class RsAdminEngagementScreen extends ConsumerStatefulWidget {
  const RsAdminEngagementScreen({super.key});

  @override
  ConsumerState<RsAdminEngagementScreen> createState() =>
      _RsAdminEngagementScreenState();
}

class _RsAdminEngagementScreenState
    extends ConsumerState<RsAdminEngagementScreen> {
  String? _selectedMatchId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    final rayonState = ref.watch(rayonSportsProvider);
    final matches = rayonState.data.valueOrNull?.matches ?? <RsMatch>[];

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const BackButton(),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ENGAGEMENT ',
              style: RsTextStyles.sectionTitle(color: RsColors.rsWhite),
            ),
            Text(
              'ADMIN',
              style: RsTextStyles.sectionTitle(color: RsColors.rsRed),
            ),
          ],
        ),
      ),
      body: matches.isEmpty
          ? Center(
              child: Text(
                'No matches available',
                style: RsTextStyles.badge(color: colors.secondaryText),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Match Selector ──
                  CoolCard(
                    backgroundColor: colors.cardSurface,
                    borderColor: colors.borderStrong,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SELECT MATCH',
                          style: text.mono(
                            theme.textTheme.labelSmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: CoolSpace.x3),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMatchId,
                          dropdownColor: colors.cardSurface,
                          hint: Text(
                            'Choose a match',
                            style: TextStyle(color: colors.tertiaryText),
                          ),
                          items: matches
                              .map(
                                (m) => DropdownMenuItem(
                                  value: m.id,
                                  child: Text(
                                    '${m.homeTeam} vs ${m.awayTeam}',
                                    style: TextStyle(color: colors.primaryText),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (id) =>
                              setState(() => _selectedMatchId = id),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: colors.cardSurfaceStrong,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: colors.borderStrong),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: colors.borderStrong),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: CoolSpace.x6),

                  // ── Sections (only visible when match is selected) ──
                  if (_selectedMatchId != null) ...[
                    _CreatePollSection(matchId: _selectedMatchId!),
                    const SizedBox(height: CoolSpace.x6),
                    _ExistingPollsList(matchId: _selectedMatchId!),
                    const SizedBox(height: CoolSpace.x6),
                    _AwardXpSection(
                      matchId: _selectedMatchId!,
                      match: matches
                          .where((m) => m.id == _selectedMatchId)
                          .firstOrNull,
                    ),
                    const SizedBox(height: CoolSpace.x6),
                    _ManageRosterSection(
                      matchId: _selectedMatchId!,
                      match: matches
                          .where((m) => m.id == _selectedMatchId)
                          .firstOrNull,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
