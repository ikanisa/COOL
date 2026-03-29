part of '../screens/match_engagement_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
// POLLS TAB
// ═══════════════════════════════════════════════════════════════════════

class _PollsTab extends ConsumerWidget {
  const _PollsTab({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final pollsAsync = ref.watch(matchPollsProvider(matchId));

    return pollsAsync.when(
      loading: () => const RayonInlineLoadingView(compact: false),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: colors.secondaryText,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load polls',
              style: RsTextStyles.badge(color: colors.secondaryText),
            ),
          ],
        ),
      ),
      data: (polls) {
        if (polls.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📊', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  'No polls for this match yet',
                  style: RsTextStyles.sectionTitle(color: colors.primaryText),
                ),
                const SizedBox(height: 8),
                Text(
                  'Check back closer to kick-off!',
                  style: RsTextStyles.badge(color: colors.secondaryText),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          itemCount: polls.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) => _PollCard(poll: polls[index]),
        );
      },
    );
  }
}

// ─── Poll Card ────────────────────────────────────────────────────────

class _PollCard extends ConsumerStatefulWidget {
  const _PollCard({required this.poll});

  final RsMatchPoll poll;

  @override
  ConsumerState<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends ConsumerState<_PollCard> {
  bool _submitting = false;
  String? _selectedOption;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final poll = widget.poll;

    final myVoteAsync = ref.watch(myPollVoteProvider(poll.id));
    final resultsAsync = ref.watch(pollResultsProvider(poll.id));

    final hasVoted = myVoteAsync.valueOrNull != null;
    final existingVote = myVoteAsync.valueOrNull?.selectedOption;

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poll type badge
          Row(
            children: [
              Text(poll.pollType.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: RsColors.rsRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  poll.pollType.label.toUpperCase(),
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsRed,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              if (poll.isClosed)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.cardSurfaceStrong,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'CLOSED',
                    style: text.mono(
                      theme.textTheme.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: colors.tertiaryText,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Question
          Text(
            poll.question,
            style: text.rayon(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),

          // Options
          for (final option in poll.options)
            _buildOption(
              context,
              option: option,
              isSelected: existingVote == option || _selectedOption == option,
              hasVoted: hasVoted,
              isClosed: poll.isClosed,
              result: resultsAsync.valueOrNull
                  ?.where((r) => r.option == option)
                  .firstOrNull,
            ),

          // Submit button (if not voted and not closed)
          if (!hasVoted && !poll.isClosed && _selectedOption != null) ...[
            const SizedBox(height: CoolSpace.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : () => _submitVote(ref, poll.id),
                style: FilledButton.styleFrom(
                  backgroundColor: RsColors.rsRed,
                  foregroundColor: RsColors.rsWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RsColors.rsWhite,
                        ),
                      )
                    : Text(
                        'SUBMIT VOTE  (+25 XP)',
                        style: text.mono(
                          const TextStyle(fontSize: 14),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String option,
    required bool isSelected,
    required bool hasVoted,
    required bool isClosed,
    RsPollResult? result,
  }) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final showBar = hasVoted || isClosed;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: (hasVoted || isClosed || _submitting)
            ? null
            : () {
                HapticFeedback.lightImpact();
                setState(() => _selectedOption = option);
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? RsColors.rsRed.withValues(alpha: 0.12)
                : colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? RsColors.rsRed : colors.borderStrong,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Radio indicator
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? RsColors.rsRed : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? RsColors.rsRed : colors.secondaryText,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option,
                      style: text.rayon(
                        theme.textTheme.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: colors.primaryText,
                      ),
                    ),
                    if (showBar && result != null) ...[
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: result.percentage / 100,
                          minHeight: 6,
                          backgroundColor: colors.cardSurface,
                          color: isSelected
                              ? RsColors.rsRed
                              : RsColors.rsNavyLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showBar && result != null) ...[
                const SizedBox(width: 12),
                Text(
                  '${result.percentage.toStringAsFixed(0)}%',
                  style: text.mono(
                    theme.textTheme.labelMedium,
                    fontWeight: FontWeight.w700,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitVote(WidgetRef ref, String pollId) async {
    if (_selectedOption == null) return;
    setState(() => _submitting = true);
    try {
      final repo = ref.read(rayonSportsRepositoryProvider);
      await repo.submitPollVote(pollId, _selectedOption!);
      ref.invalidate(myPollVoteProvider(pollId));
      ref.invalidate(pollResultsProvider(pollId));
    } catch (_) {
      // Silently handle — the UI will show the error state
    }
    if (mounted) setState(() => _submitting = false);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PREDICT TAB
// ═══════════════════════════════════════════════════════════════════════

class _PredictTab extends ConsumerStatefulWidget {
  const _PredictTab({required this.matchId, this.match});

  final String matchId;
  final RsMatch? match;

  @override
  ConsumerState<_PredictTab> createState() => _PredictTabState();
}

class _PredictTabState extends ConsumerState<_PredictTab> {
  int _homeScore = 1;
  int _awayScore = 0;
  String? _motm;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final match = widget.match;

    final predictionAsync = ref.watch(myPredictionProvider(widget.matchId));

    return predictionAsync.when(
      loading: () => const RayonInlineLoadingView(compact: false),
      error: (error, stackTrace) => Center(
        child: Text(
          'Failed to load prediction',
          style: RsTextStyles.badge(color: colors.secondaryText),
        ),
      ),
      data: (existing) {
        if (existing != null) {
          return _ExistingPredictionCard(prediction: existing, match: match);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──
              CoolCard(
                backgroundColor: colors.cardSurface,
                borderColor: colors.borderStrong,
                child: Column(
                  children: [
                    const Text('⚽', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(
                      'PREDICT THE SCORE',
                      style: text.mono(
                        theme.textTheme.titleMedium,
                        fontWeight: FontWeight.w800,
                        color: colors.primaryText,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Exact score = 500 XP  •  Correct result = 200 XP',
                      style: text.rayon(
                        theme.textTheme.bodySmall,
                        fontWeight: FontWeight.w500,
                        color: colors.secondaryText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x6),

              // ── Score Picker ──
              CoolCard(
                backgroundColor: colors.cardSurface,
                borderColor: colors.borderStrong,
                child: Row(
                  children: [
                    // Home team
                    Expanded(
                      child: _ScoreColumn(
                        teamName: match?.homeTeam ?? 'Home',
                        score: _homeScore,
                        onChanged: (v) => setState(() => _homeScore = v),
                      ),
                    ),
                    // VS separator
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: RsColors.rsNavy,
                        shape: BoxShape.circle,
                        border: Border.all(color: RsColors.rsRed, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'VS',
                        style: text.mono(
                          const TextStyle(fontSize: 16),
                          fontWeight: FontWeight.w900,
                          color: RsColors.rsWhite,
                        ),
                      ),
                    ),
                    // Away team
                    Expanded(
                      child: _ScoreColumn(
                        teamName: match?.awayTeam ?? 'Away',
                        score: _awayScore,
                        onChanged: (v) => setState(() => _awayScore = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: CoolSpace.x6),

              // ── MOTM Picker (from admin roster) ──
              if (match != null && match.roster.isNotEmpty) ...[
                CoolCard(
                  backgroundColor: colors.cardSurface,
                  borderColor: colors.borderStrong,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🌟', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(
                            'MAN OF THE MATCH',
                            style: text.mono(
                              theme.textTheme.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: match.roster.map((player) {
                          final isSelected = _motm == player;
                          return FilterChip(
                            label: Text(player),
                            selected: isSelected,
                            onSelected: (_) {
                              HapticFeedback.lightImpact();
                              setState(
                                () => _motm = isSelected ? null : player,
                              );
                            },
                            selectedColor: RsColors.rsRed.withValues(
                              alpha: 0.2,
                            ),
                            checkmarkColor: RsColors.rsRed,
                            side: BorderSide(
                              color: isSelected
                                  ? RsColors.rsRed
                                  : colors.borderStrong,
                            ),
                            labelStyle: text.rayon(
                              theme.textTheme.bodySmall,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? RsColors.rsRed
                                  : colors.primaryText,
                            ),
                            backgroundColor: colors.cardSurfaceStrong,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
              ],

              // ── MOTM free-text fallback ──
              if (match == null || match.roster.isEmpty) ...[
                CoolCard(
                  backgroundColor: colors.cardSurface,
                  borderColor: colors.borderStrong,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('🌟', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Text(
                            'MAN OF THE MATCH',
                            style: text.mono(
                              theme.textTheme.labelMedium,
                              fontWeight: FontWeight.w700,
                              color: colors.secondaryText,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: CoolSpace.x3),
                      TextFormField(
                        onChanged: (v) => setState(
                          () => _motm = v.trim().isEmpty ? null : v.trim(),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Player name (optional)',
                          hintStyle: TextStyle(color: colors.tertiaryText),
                          filled: true,
                          fillColor: colors.cardSurfaceStrong,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.borderStrong),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: colors.borderStrong),
                          ),
                        ),
                        style: TextStyle(color: colors.primaryText),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
              ],

              // ── Submit ──
              FilledButton(
                onPressed: _submitting ? null : _submitPrediction,
                style: FilledButton.styleFrom(
                  backgroundColor: RsColors.rsRed,
                  foregroundColor: RsColors.rsWhite,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RsColors.rsWhite,
                        ),
                      )
                    : Text(
                        'LOCK IN PREDICTION',
                        style: text.mono(
                          const TextStyle(fontSize: 16),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submitPrediction() async {
    setState(() => _submitting = true);
    try {
      final repo = ref.read(rayonSportsRepositoryProvider);
      await repo.submitPrediction(
        matchId: widget.matchId,
        homeScore: _homeScore,
        awayScore: _awayScore,
        motm: _motm,
      );
      ref.invalidate(myPredictionProvider(widget.matchId));
    } catch (_) {
      // Error handled by UI state
    }
    if (mounted) setState(() => _submitting = false);
  }
}

// ─── Score Column ─────────────────────────────────────────────────────

class _ScoreColumn extends StatelessWidget {
  const _ScoreColumn({
    required this.teamName,
    required this.score,
    required this.onChanged,
  });

  final String teamName;
  final int score;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Column(
      children: [
        Text(
          teamName,
          style: text.rayon(
            theme.textTheme.bodySmall,
            fontWeight: FontWeight.w700,
            color: colors.secondaryText,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ScoreButton(
              icon: Icons.remove,
              onTap: score > 0
                  ? () {
                      HapticFeedback.lightImpact();
                      onChanged(score - 1);
                    }
                  : null,
            ),
            Container(
              width: 56,
              alignment: Alignment.center,
              child: Text(
                '$score',
                style: text.mono(
                  const TextStyle(fontSize: 36),
                  fontWeight: FontWeight.w900,
                  color: colors.primaryText,
                ),
              ),
            ),
            _ScoreButton(
              icon: Icons.add,
              onTap: score < 15
                  ? () {
                      HapticFeedback.lightImpact();
                      onChanged(score + 1);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.cardSurfaceStrong,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderStrong),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: onTap != null ? colors.primaryText : colors.tertiaryText,
        ),
      ),
    );
  }
}

// ─── Existing Prediction Card ─────────────────────────────────────────

class _ExistingPredictionCard extends StatelessWidget {
  const _ExistingPredictionCard({required this.prediction, this.match});

  final RsMatchPrediction prediction;
  final RsMatch? match;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        children: [
          CoolCard(
            backgroundColor: colors.cardSurface,
            borderColor: colors.borderStrong,
            child: Column(
              children: [
                const Text('🔒', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 8),
                Text(
                  'PREDICTION LOCKED',
                  style: text.mono(
                    theme.textTheme.titleMedium,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryText,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: CoolSpace.x6),
                // Score display
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Column(
                      children: [
                        Text(
                          match?.homeTeam ?? 'Home',
                          style: text.rayon(
                            theme.textTheme.bodySmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                          ),
                        ),
                        Text(
                          '${prediction.predictedHomeScore}',
                          style: text.mono(
                            const TextStyle(fontSize: 48),
                            fontWeight: FontWeight.w900,
                            color: colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '–',
                        style: text.mono(
                          const TextStyle(fontSize: 48),
                          fontWeight: FontWeight.w300,
                          color: colors.tertiaryText,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        Text(
                          match?.awayTeam ?? 'Away',
                          style: text.rayon(
                            theme.textTheme.bodySmall,
                            fontWeight: FontWeight.w700,
                            color: colors.secondaryText,
                          ),
                        ),
                        Text(
                          '${prediction.predictedAwayScore}',
                          style: text.mono(
                            const TextStyle(fontSize: 48),
                            fontWeight: FontWeight.w900,
                            color: colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (prediction.predictedMotm != null) ...[
                  const SizedBox(height: CoolSpace.x4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('🌟', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        'MOTM: ${prediction.predictedMotm}',
                        style: text.rayon(
                          theme.textTheme.bodyMedium,
                          fontWeight: FontWeight.w600,
                          color: RsColors.rsGold,
                        ),
                      ),
                    ],
                  ),
                ],
                if (prediction.xpAwarded > 0) ...[
                  const SizedBox(height: CoolSpace.x4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (prediction.isCorrect == true
                                  ? RsColors.rsGold
                                  : RsColors.rsNavyLight)
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          prediction.isCorrect == true ? '🎯' : '⚡',
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+${prediction.xpAwarded} XP',
                          style: text.mono(
                            theme.textTheme.titleMedium,
                            fontWeight: FontWeight.w800,
                            color: prediction.isCorrect == true
                                ? RsColors.rsGold
                                : colors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// RECAP TAB
// ═══════════════════════════════════════════════════════════════════════

class _RecapTab extends ConsumerWidget {
  const _RecapTab({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final commentaryAsync = ref.watch(matchCommentaryProvider(matchId));

    return commentaryAsync.when(
      loading: () => const RayonInlineLoadingView(compact: false),
      error: (error, stackTrace) => Center(
        child: Text(
          'Failed to load commentary',
          style: RsTextStyles.badge(color: colors.secondaryText),
        ),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('📝', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  'No commentary yet',
                  style: RsTextStyles.sectionTitle(color: colors.primaryText),
                ),
                const SizedBox(height: 8),
                Text(
                  'AI recap will appear after the match',
                  style: RsTextStyles.badge(color: colors.secondaryText),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          itemCount: entries.length,
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemBuilder: (context, index) =>
              _CommentaryCard(entry: entries[index]),
        );
      },
    );
  }
}

// ─── Commentary Card ──────────────────────────────────────────────────

class _CommentaryCard extends StatelessWidget {
  const _CommentaryCard({required this.entry});

  final RsMatchCommentary entry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Type badge
          Row(
            children: [
              Text(
                entry.commentaryType.emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: RsColors.rsNavyLight.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.commentaryType.label.toUpperCase(),
                  style: text.mono(
                    theme.textTheme.labelSmall,
                    fontWeight: FontWeight.w700,
                    color: RsColors.rsNavyLight,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '🤖 AI',
                style: text.mono(
                  theme.textTheme.labelSmall,
                  fontWeight: FontWeight.w600,
                  color: colors.tertiaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Title
          Text(
            entry.title,
            style: text.rayon(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),

          // Body
          Text(
            entry.body,
            style: text.rayon(
              theme.textTheme.bodyMedium,
              fontWeight: FontWeight.w500,
              color: colors.secondaryText,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
