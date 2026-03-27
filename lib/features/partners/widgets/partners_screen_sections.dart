part of '../screens/partners_screen.dart';

// ─── Partner list (flat, no tabs) ─────────────────────────────────────────

class _PartnerList extends ConsumerWidget {
  const _PartnerList({
    required this.searchQuery,
    required this.onOpenRayonSports,
  });

  final String searchQuery;
  final VoidCallback onOpenRayonSports;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partnersAsync = ref.watch(partnersProvider);

    return partnersAsync.when(
      loading: () => const CoolSkeletonList(itemCount: 4),
      error: (error, _) => _ErrorState(
        error: error.toString(),
        onRetry: () => ref.invalidate(partnersProvider),
      ),
      data: (allPartners) {
        // Exclude Rayon Sports (it has its own hub) — keep only non-football
        // partners in the flat list.
        final nonRayonPartners = allPartners
            .where((p) => p.slug != 'rayon-sports')
            .toList();

        final partners = searchQuery.isEmpty
            ? nonRayonPartners
            : nonRayonPartners
                .where((p) => p.name
                    .toLowerCase()
                    .contains(searchQuery.toLowerCase()))
                .toList();

        if (partners.isEmpty) {
          return const _EmptyState(label: 'No partners found');
        }

        return Column(
          children: [
            for (var index = 0; index < partners.length; index++) ...[
              if (index > 0) const SizedBox(height: 12),
              _PartnerRow(
                partner: partners[index],
                onTap: () => _handlePartnerTap(context, partners[index]),
              ),
            ],
            const SizedBox(height: 24),
            const _BecomePartnerCard(),
          ],
        );
      },
    );
  }

  void _handlePartnerTap(BuildContext context, Partner partner) {
    // Partners with a WhatsApp number → open external link
    // Others → show a toast
    if (partner.whatsappNumber != null && partner.whatsappNumber!.isNotEmpty) {
      CoolToast.info(context, '${partner.name} — contact via WhatsApp');
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.coolSemanticColors.appBackground,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(32),
          child: CoolEmptyView(
            message: '${partner.name} profile currently unavailable',
            icon: Icons.business_rounded,
          ),
        ),
      );
    }
  }
}

// ─── Partner row card ─────────────────────────────────────────────────────
//
// Screenshot layout:
// ┌──────────────────────────────────────────────┐
// │  [thumbnail]  [✓]  NAME          [>] or [↗]  │
// │                    CATEGORY                   │
// │                    Description…               │
// └──────────────────────────────────────────────┘

class _PartnerRow extends StatelessWidget {
  const _PartnerRow({required this.partner, required this.onTap});

  final Partner partner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);
    final hasExternalLink = partner.whatsappNumber != null &&
        partner.whatsappNumber!.isNotEmpty;

    return Semantics(
      button: true,
      label: 'Open ${partner.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(CoolRadii.lg),
            border: Border.all(color: colors.borderStrong),
          ),
          child: Row(
            children: [
              // ─── Thumbnail ──────────────────────────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _PartnerThumbnail(partner: partner),
                  // Verified badge (blue checkmark)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: RsColors.rsBlue,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.cardSurfaceStrong,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // ─── Name + Category + Description ──────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.rayonCondensed(
                        theme.textTheme.titleMedium,
                        fontWeight: FontWeight.w900,
                        color: colors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _categoryLabel(partner).toUpperCase(),
                      style: text.mono(
                        theme.textTheme.labelSmall,
                        fontWeight: FontWeight.w700,
                        color: RsColors.rsBlueLight,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (partner.subtitle != null &&
                        partner.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        partner.subtitle!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.rayon(
                          theme.textTheme.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: colors.tertiaryText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // ─── Arrow/external link icon ───────────────────
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.cardSurface,
                  borderRadius: BorderRadius.circular(CoolRadii.sm),
                  border: Border.all(color: colors.borderStrong),
                ),
                child: Icon(
                  hasExternalLink
                      ? Icons.open_in_new_rounded
                      : Icons.chevron_right_rounded,
                  size: 20,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _categoryLabel(Partner partner) {
    return switch (partner.category) {
      PartnerCategory.football => 'Football club',
      PartnerCategory.bank => 'Banking partner',
      PartnerCategory.organization => _orgSubCategory(partner),
    };
  }

  static String _orgSubCategory(Partner partner) {
    if (partner.slug == 'radiant') return 'Insurance';
    if (partner.slug == 'prisma') return 'Digital agency';
    if (partner.slug == 'rssb') return 'Social security';
    if (partner.slug == 'rra') return 'Tax authority';
    return 'Service partner';
  }
}

// ─── Partner thumbnail ──────────────────────────────────────────────────

class _PartnerThumbnail extends StatelessWidget {
  const _PartnerThumbnail({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;

    // Generate deterministic color from partner slug
    final hash = partner.slug.hashCode.abs();
    final hue = (hash % 360).toDouble();
    final bgColor = HSLColor.fromAHSL(1.0, hue, 0.15, 0.2).toColor();

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
      ),
      child: partner.logoUrl != null && partner.logoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(CoolRadii.md - 1),
              child: Image.network(
                partner.logoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _fallbackIcon(colors),
              ),
            )
          : _fallbackIcon(colors),
    );
  }

  Widget _fallbackIcon(CoolSemanticColors colors) {
    return Center(
      child: Text(
        partner.emoji,
        style: const TextStyle(fontSize: 24),
      ),
    );
  }
}

// ─── Become a Partner CTA ─────────────────────────────────────────────────

class _BecomePartnerCard extends StatelessWidget {
  const _BecomePartnerCard();

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF06152D), Color(0xFF0B2351), Color(0xFF143B72)],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: RsColors.rsBlue.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon box
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: RsColors.rsBlue,
              borderRadius: BorderRadius.circular(CoolRadii.md),
            ),
            child: const Icon(
              Icons.business_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),

          Text(
            'BECOME A PARTNER',
            style: text.rayonCondensed(
              theme.textTheme.headlineSmall,
              fontWeight: FontWeight.w900,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'JOIN THE OFFICIAL NETWORK AND OFFER SERVICES TO RAYON SPORTS FANS.',
            style: text.rayon(
              theme.textTheme.bodySmall,
              fontWeight: FontWeight.w600,
              color: colors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          GestureDetector(
            onTap: () async {
              final uri = Uri.parse('https://rayonsports.rw/partners/apply');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: RsColors.rsBlue,
                borderRadius: BorderRadius.circular(CoolRadii.pill),
              ),
              child: Text(
                'APPLY NOW',
                style: text.rayonCondensed(
                  theme.textTheme.labelLarge,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



// ─── Error state ───────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 32, color: colors.warning),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'Failed to load partners',
            style: text.rayonCondensed(
              theme.textTheme.titleMedium,
              fontWeight: FontWeight.w800,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          CoolButton(label: 'Retry', onTap: onRetry),
        ],
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(CoolSpace.x6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
      ),
      child: Center(
        child: Text(
          label,
          style: text.rayon(
            theme.textTheme.bodyMedium,
            fontWeight: FontWeight.w600,
            color: colors.secondaryText,
          ),
        ),
      ),
    );
  }
}
