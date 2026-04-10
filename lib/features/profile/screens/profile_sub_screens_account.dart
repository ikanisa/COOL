part of 'profile_sub_screens.dart';

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileViewProvider);
    final colors = context.coolSemanticColors;
    final biopayAsync = ref.watch(biopayProfileProvider);

    return _ProfileSubScaffold(
      title: 'ACCOUNT',
      subtitle: 'PERSONAL INFORMATION',
      icon: Icons.person_outline_rounded,
      slivers: [
        // ── IDENTITY section ───────────────────────────────────────
        const _SectionLabel(label: 'IDENTITY'),
        const SizedBox(height: CoolSpace.x3),
        _GlassCard(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.accent, colors.info],
                      ),
                      borderRadius: BorderRadius.circular(CoolRadii.lg),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      profile.initials,
                      style: context.coolText.displayCondensed(
                        Theme.of(context).textTheme.headlineMedium,
                        fontWeight: FontWeight.w900,
                        color: colors.accentForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: CoolSpace.x4),
                  Expanded(
                    child: Text(
                      profile.name.isNotEmpty
                          ? profile.name.toUpperCase()
                          : 'ANONYMOUS USER',
                      style: context.coolText.displayCondensed(
                        Theme.of(context).textTheme.titleLarge,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: CoolSpace.x4),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.badge_outlined,
                title: 'MEMBER ID',
                value: profile.userId.isNotEmpty ? profile.userId : '------',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.phone_outlined,
                title: 'PHONE',
                value: profile.phone.isNotEmpty ? profile.phone : 'NOT SET',
              ),
              const _RowDivider(),
              _InfoRow(
                icon: Icons.flag_outlined,
                title: 'COUNTRY',
                value: profile.country.toUpperCase(),
              ),
            ],
          ),
        ),
        const SizedBox(height: CoolSpace.x6),

        // ── BIOPAY section ─────────────────────────────────────────
        const _SectionLabel(label: 'BIOPAY'),
        const SizedBox(height: CoolSpace.x3),
        biopayAsync.when(
          data: (biopay) => _GlassCard(
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.fingerprint_rounded,
                  title: 'BIOPAY ID',
                  value: biopay?.publicId.trim().isNotEmpty == true
                      ? biopay!.publicId
                      : 'NOT ENROLLED',
                  valueColor: biopay?.publicId.trim().isNotEmpty == true
                      ? null
                      : colors.secondaryText,
                ),
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.face_retouching_natural_rounded,
                  title: 'FACE ID',
                  value: (biopay?.active ?? false) ? 'READY' : 'NOT SET UP',
                  valueColor: (biopay?.active ?? false)
                      ? colors.success
                      : colors.secondaryText,
                ),
                const _RowDivider(),
                _InfoRow(
                  icon: Icons.route_rounded,
                  title: 'RECEIVE ROUTE',
                  value: biopay?.maskedRecipientValue ?? 'NOT LINKED',
                  valueColor: biopay?.maskedRecipientValue != null
                      ? null
                      : colors.secondaryText,
                ),
              ],
            ),
          ),
          loading: () => _GlassCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: CoolSpace.x5),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              ),
            ),
          ),
          error: (error, _) => _GlassCard(
            child: _InfoRow(
              icon: Icons.error_outline_rounded,
              title: 'BIOPAY',
              value: 'UNAVAILABLE',
              valueColor: colors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}
