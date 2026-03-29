part of '../screens/rs_admin_engagement_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
// CREATE POLL SECTION
// ═══════════════════════════════════════════════════════════════════════

class _CreatePollSection extends ConsumerStatefulWidget {
  const _CreatePollSection({required this.matchId});

  final String matchId;

  @override
  ConsumerState<_CreatePollSection> createState() => _CreatePollSectionState();
}

class _CreatePollSectionState extends ConsumerState<_CreatePollSection> {
  PollType _pollType = PollType.custom;
  final _questionController = TextEditingController();
  final _optionsController = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _questionController.dispose();
    _optionsController.dispose();
    super.dispose();
  }

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
          Row(
            children: [
              const Text('📊', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'CREATE POLL',
                style: text.mono(
                  theme.textTheme.labelMedium,
                  fontWeight: FontWeight.w700,
                  color: colors.secondaryText,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),

          // Poll type
          DropdownButtonFormField<PollType>(
            initialValue: _pollType,
            dropdownColor: colors.cardSurface,
            items: PollType.values
                .map(
                  (t) => DropdownMenuItem(
                    value: t,
                    child: Text(
                      '${t.emoji} ${t.label}',
                      style: TextStyle(color: colors.primaryText),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _pollType = v ?? PollType.custom),
            decoration: InputDecoration(
              labelText: 'Poll Type',
              labelStyle: TextStyle(color: colors.tertiaryText),
              filled: true,
              fillColor: colors.cardSurfaceStrong,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.borderStrong),
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x3),

          // Question
          TextFormField(
            controller: _questionController,
            decoration: InputDecoration(
              labelText: 'Question',
              labelStyle: TextStyle(color: colors.tertiaryText),
              hintText: 'Who do you think will score first?',
              hintStyle: TextStyle(color: colors.tertiaryText),
              filled: true,
              fillColor: colors.cardSurfaceStrong,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.borderStrong),
              ),
            ),
            style: TextStyle(color: colors.primaryText),
          ),
          const SizedBox(height: CoolSpace.x3),

          // Options (comma separated)
          TextFormField(
            controller: _optionsController,
            decoration: InputDecoration(
              labelText: 'Options (comma-separated)',
              labelStyle: TextStyle(color: colors.tertiaryText),
              hintText: 'Option A, Option B, Option C',
              hintStyle: TextStyle(color: colors.tertiaryText),
              filled: true,
              fillColor: colors.cardSurfaceStrong,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colors.borderStrong),
              ),
            ),
            style: TextStyle(color: colors.primaryText),
            maxLines: 2,
          ),
          const SizedBox(height: CoolSpace.x4),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _creating ? null : _createPoll,
              style: FilledButton.styleFrom(
                backgroundColor: RsColors.rsRed,
                foregroundColor: RsColors.rsWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _creating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: RsColors.rsWhite,
                      ),
                    )
                  : const Icon(Icons.add_rounded),
              label: const Text('CREATE POLL'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createPoll() async {
    final question = _questionController.text.trim();
    final optionsRaw = _optionsController.text.trim();
    if (question.isEmpty || optionsRaw.isEmpty) return;

    final options = optionsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (options.length < 2) return;

    setState(() => _creating = true);
    try {
      final repo = ref.read(rayonSportsRepositoryProvider);
      await repo.createPoll(
        matchId: widget.matchId,
        pollType: _pollType,
        question: question,
        options: options,
      );
      _questionController.clear();
      _optionsController.clear();
      ref.invalidate(matchPollsProvider(widget.matchId));
    } catch (_) {
      // Error handled
    }
    if (mounted) setState(() => _creating = false);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EXISTING POLLS LIST
// ═══════════════════════════════════════════════════════════════════════

class _ExistingPollsList extends ConsumerWidget {
  const _ExistingPollsList({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final pollsAsync = ref.watch(matchPollsProvider(matchId));

    return CoolCard(
      backgroundColor: colors.cardSurface,
      borderColor: colors.borderStrong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'EXISTING POLLS',
            style: text.mono(
              theme.textTheme.labelMedium,
              fontWeight: FontWeight.w700,
              color: colors.secondaryText,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          pollsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => Text(
              'Failed to load polls',
              style: TextStyle(color: colors.secondaryText),
            ),
            data: (polls) {
              if (polls.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No polls created for this match.',
                    style: TextStyle(color: colors.tertiaryText),
                  ),
                );
              }

              return Column(
                children: polls.map((poll) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      tileColor: colors.cardSurfaceStrong,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colors.borderStrong),
                      ),
                      leading: Text(
                        poll.pollType.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                      title: Text(
                        poll.question,
                        style: text.rayon(
                          theme.textTheme.bodyMedium,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${poll.options.length} options  •  ${poll.isActive ? "Active" : "Closed"}',
                        style: text.rayon(
                          theme.textTheme.bodySmall,
                          fontWeight: FontWeight.w500,
                          color: poll.isActive
                              ? RsColors.rsGold
                              : colors.tertiaryText,
                        ),
                      ),
                      trailing: Switch(
                        value: poll.isActive,
                        activeThumbColor: RsColors.rsRed,
                        onChanged: (v) async {
                          final repo = ref.read(rayonSportsRepositoryProvider);
                          await repo.togglePollActive(poll.id, isActive: v);
                          ref.invalidate(matchPollsProvider(matchId));
                        },
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// AWARD XP SECTION
// ═══════════════════════════════════════════════════════════════════════

class _AwardXpSection extends ConsumerStatefulWidget {
  const _AwardXpSection({required this.matchId, this.match});

  final String matchId;
  final RsMatch? match;

  @override
  ConsumerState<_AwardXpSection> createState() => _AwardXpSectionState();
}

class _AwardXpSectionState extends ConsumerState<_AwardXpSection> {
  int _homeScore = 0;
  int _awayScore = 0;
  bool _awarding = false;
  int? _updatedCount;

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
          Row(
            children: [
              const Text('🎯', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'AWARD PREDICTION XP',
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
          Text(
            'Enter the final score to award XP to fans who predicted correctly.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w500,
              color: colors.tertiaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),

          // Score inputs
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '$_homeScore',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _homeScore = int.tryParse(v) ?? 0,
                  decoration: InputDecoration(
                    labelText: widget.match?.homeTeam ?? 'Home Score',
                    labelStyle: TextStyle(color: colors.tertiaryText),
                    filled: true,
                    fillColor: colors.cardSurfaceStrong,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.borderStrong),
                    ),
                  ),
                  style: TextStyle(color: colors.primaryText),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '–',
                style: text.mono(
                  const TextStyle(fontSize: 24),
                  fontWeight: FontWeight.w400,
                  color: colors.tertiaryText,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  initialValue: '$_awayScore',
                  keyboardType: TextInputType.number,
                  onChanged: (v) => _awayScore = int.tryParse(v) ?? 0,
                  decoration: InputDecoration(
                    labelText: widget.match?.awayTeam ?? 'Away Score',
                    labelStyle: TextStyle(color: colors.tertiaryText),
                    filled: true,
                    fillColor: colors.cardSurfaceStrong,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.borderStrong),
                    ),
                  ),
                  style: TextStyle(color: colors.primaryText),
                ),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x4),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _awarding ? null : _awardXp,
              style: FilledButton.styleFrom(
                backgroundColor: RsColors.rsGold,
                foregroundColor: RsColors.rsNavy,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _awarding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stars_rounded),
              label: const Text('AWARD XP'),
            ),
          ),

          if (_updatedCount != null) ...[
            const SizedBox(height: CoolSpace.x3),
            Text(
              '✅ XP awarded! $_updatedCount exact predictions found.',
              style: text.rayon(
                theme.textTheme.bodySmall,
                fontWeight: FontWeight.w600,
                color: RsColors.rsGold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _awardXp() async {
    setState(() {
      _awarding = true;
      _updatedCount = null;
    });
    try {
      final repo = ref.read(rayonSportsRepositoryProvider);
      final count = await repo.awardPredictionXp(
        matchId: widget.matchId,
        homeScore: _homeScore,
        awayScore: _awayScore,
      );
      if (mounted) setState(() => _updatedCount = count);
    } catch (_) {
      // Handled
    }
    if (mounted) setState(() => _awarding = false);
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MANAGE ROSTER SECTION
// ═══════════════════════════════════════════════════════════════════════

class _ManageRosterSection extends ConsumerStatefulWidget {
  const _ManageRosterSection({required this.matchId, this.match});

  final String matchId;
  final RsMatch? match;

  @override
  ConsumerState<_ManageRosterSection> createState() =>
      _ManageRosterSectionState();
}

class _ManageRosterSectionState extends ConsumerState<_ManageRosterSection> {
  final _playerController = TextEditingController();
  late List<String> _roster;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _roster = List<String>.from(widget.match?.roster ?? <String>[]);
  }

  @override
  void dispose() {
    _playerController.dispose();
    super.dispose();
  }

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
          Row(
            children: [
              const Text('👥', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'MATCH ROSTER (MOTM)',
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
          Text(
            'Add players for fans to choose as Man of the Match.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w500,
              color: colors.tertiaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),

          // Add player input
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _playerController,
                  decoration: InputDecoration(
                    hintText: 'Player name',
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
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  style: TextStyle(color: colors.primaryText),
                  onFieldSubmitted: (_) => _addPlayer(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: _addPlayer,
                style: IconButton.styleFrom(
                  backgroundColor: RsColors.rsRed,
                  foregroundColor: RsColors.rsWhite,
                ),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: CoolSpace.x3),

          // Roster chips
          if (_roster.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _roster.map((player) {
                return Chip(
                  label: Text(player),
                  labelStyle: text.rayon(
                    theme.textTheme.bodySmall,
                    fontWeight: FontWeight.w600,
                    color: colors.primaryText,
                  ),
                  backgroundColor: colors.cardSurfaceStrong,
                  side: BorderSide(color: colors.borderStrong),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  deleteIconColor: colors.secondaryText,
                  onDeleted: () {
                    setState(() => _roster.remove(player));
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }).toList(),
            ),

          if (_roster.isNotEmpty) ...[
            const SizedBox(height: CoolSpace.x4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveRoster,
                style: FilledButton.styleFrom(
                  backgroundColor: RsColors.rsNavyLight,
                  foregroundColor: RsColors.rsWhite,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RsColors.rsWhite,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text('SAVE ROSTER (${_roster.length} players)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addPlayer() {
    final name = _playerController.text.trim();
    if (name.isNotEmpty && !_roster.contains(name)) {
      HapticFeedback.lightImpact();
      setState(() => _roster.add(name));
      _playerController.clear();
    }
  }

  Future<void> _saveRoster() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(rayonSportsRepositoryProvider);
      // Direct update to rs_matches table
      await repo.updateMatchRoster(widget.matchId, _roster);
      ref.invalidate(rayonSportsProvider);
    } catch (_) {
      // Handled
    }
    if (mounted) setState(() => _saving = false);
  }
}
