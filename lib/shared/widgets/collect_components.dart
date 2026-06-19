import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

export '../../app/theme/collect_colors.dart';
export '../../app/theme/collect_icons.dart';
export '../../app/theme/collect_radius.dart';
export '../../app/theme/collect_spacing.dart';
export '../../app/theme/collect_typography.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_component_tokens.dart';
import '../../app/theme/collect_icons.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_radius.dart';
import '../../app/theme/collect_shadows.dart';
import '../../app/theme/collect_spacing.dart';
import '../../app/theme/collect_typography.dart';
import '../../core/security/phone_normalizer.dart';
import '../../core/utils/date_format.dart';
import '../../core/utils/money_format.dart';
import '../models/collect_models.dart';

class CollectButton extends StatelessWidget {
  const CollectButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = CollectButtonVariant.primary,
    this.expand = false,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final CollectButtonVariant variant;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final style = switch (variant) {
      CollectButtonVariant.primary => CollectComponentTokens.filledButton(
        context,
      ),
      CollectButtonVariant.secondary => CollectComponentTokens.outlinedButton(
        context,
      ),
      CollectButtonVariant.subtle => TextButton.styleFrom(
        minimumSize: const Size(CollectSpacing.target, CollectSpacing.target),
        foregroundColor: colors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: CollectRadius.mdBorder),
      ),
      CollectButtonVariant.danger => CollectComponentTokens.filledButton(
        context,
      ).copyWith(backgroundColor: WidgetStatePropertyAll(colors.danger)),
    };
    final child = icon == null
        ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon),
              CollectSpacing.gapW8,
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final button = switch (variant) {
      CollectButtonVariant.primary || CollectButtonVariant.danger =>
        FilledButton(onPressed: onPressed, style: style, child: child),
      CollectButtonVariant.secondary => OutlinedButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
      CollectButtonVariant.subtle => TextButton(
        onPressed: onPressed,
        style: style,
        child: child,
      ),
    };
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

enum CollectButtonVariant { primary, secondary, subtle, danger }

class CollectCard extends StatelessWidget {
  const CollectCard({
    required this.child,
    this.onTap,
    this.padding = CollectSpacing.cardPadding,
    this.emphasis = CollectCardEmphasis.normal,
    this.backgroundGradient,
    this.accentColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final CollectCardEmphasis emphasis;
  final Gradient? backgroundGradient;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = switch (emphasis) {
      CollectCardEmphasis.hero ||
      CollectCardEmphasis.glow => CollectRadius.cardLargeBorder,
      CollectCardEmphasis.compact => CollectRadius.mdBorder,
      _ => CollectRadius.cardBorder,
    };
    final background = switch (emphasis) {
      CollectCardEmphasis.flat =>
        isDark ? CollectColors.referenceContentDark : colors.surface,
      CollectCardEmphasis.outline =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      CollectCardEmphasis.tonal => Color.alphaBlend(
        (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.18 : 0.08,
        ),
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      ),
      CollectCardEmphasis.glow =>
        isDark ? CollectColors.referenceAssetNavy : colors.surfaceRaised,
      CollectCardEmphasis.compact =>
        isDark
            ? CollectColors.referencePaymentsPurpleDeep
            : colors.surfaceRaised,
      _ => isDark ? CollectColors.referencePaymentsPurple : colors.surfaceMuted,
    };
    final backgroundOpacity = switch (emphasis) {
      CollectCardEmphasis.hero => isDark ? 0.90 : 0.82,
      CollectCardEmphasis.glow => isDark ? 0.88 : 0.80,
      CollectCardEmphasis.tonal => isDark ? 0.86 : 0.78,
      CollectCardEmphasis.compact => isDark ? 0.84 : 0.76,
      CollectCardEmphasis.flat => isDark ? 0.82 : 0.70,
      CollectCardEmphasis.outline => isDark ? 0.82 : 0.74,
      CollectCardEmphasis.normal => isDark ? 0.84 : 0.78,
    };
    final border = switch (emphasis) {
      CollectCardEmphasis.flat => null,
      CollectCardEmphasis.glow => Border.all(
        color: (accentColor ?? colors.actionColor).withValues(
          alpha: isDark ? 0.34 : 0.24,
        ),
      ),
      CollectCardEmphasis.outline => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.14)
            : colors.border,
      ),
      CollectCardEmphasis.compact => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border.withValues(alpha: 0.72),
      ),
      _ => Border.all(
        color: isDark
            ? colors.onImagePrimary.withValues(alpha: 0.12)
            : colors.border,
      ),
    };
    final shadows = switch (emphasis) {
      CollectCardEmphasis.flat ||
      CollectCardEmphasis.outline ||
      CollectCardEmphasis.compact => const <BoxShadow>[],
      CollectCardEmphasis.glow => [
        BoxShadow(
          color: (accentColor ?? colors.actionColor).withValues(
            alpha: isDark ? 0.20 : 0.13,
          ),
          blurRadius: isDark ? 34 : 28,
          offset: const Offset(0, 18),
        ),
      ],
      _ => CollectShadows.card(),
    };
    final container = AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.fast),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: backgroundGradient == null
            ? background.withValues(alpha: backgroundOpacity)
            : null,
        gradient: backgroundGradient,
        borderRadius: radius,
        border: border,
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
    final decorated = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: container,
      ),
    );
    return Material(
      color: colors.transparent,
      borderRadius: radius,
      child: onTap == null
          ? decorated
          : InkWell(borderRadius: radius, onTap: onTap, child: decorated),
    );
  }
}

enum CollectCardEmphasis { flat, normal, hero, tonal, glow, outline, compact }

class CollectVisualFeatureCard extends StatelessWidget {
  const CollectVisualFeatureCard({
    required this.asset,
    required this.title,
    required this.message,
    required this.icon,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String asset;
  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.textPrimary;
    final panelGradient = isDark
        ? LinearGradient(
            colors: [
              CollectColors.referencePaymentsPurpleDeep,
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.16),
                CollectColors.referencePaymentsPurple,
              ),
              CollectColors.referenceAssetNavy,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : LinearGradient(
            colors: [
              Color.alphaBlend(
                colors.statusForeground(tone).withValues(alpha: 0.14),
                colors.glassPanel,
              ),
              Color.alphaBlend(
                colors.mintPaint.withValues(alpha: 0.08),
                colors.glassPanel,
              ),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );
    Widget featureImage = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    if (isDark) {
      featureImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          CollectColors.referencePaymentsPurpleDeep.withValues(alpha: 0.46),
          BlendMode.multiply,
        ),
        child: featureImage,
      );
    }
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: panelGradient,
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 132),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FractionallySizedBox(
                    widthFactor: 0.48,
                    heightFactor: 1,
                    child: featureImage,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (isDark
                                ? CollectColors.referencePaymentsPurpleDeep
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.98 : 0.98),
                        (isDark
                                ? CollectColors.referencePaymentsPurple
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.88 : 0.88),
                        (isDark
                                ? CollectColors.referenceAssetNavy
                                : colors.glassPanel)
                            .withValues(alpha: isDark ? 0.30 : 0.18),
                      ],
                      stops: const [0, 0.58, 1],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: CollectSpacing.cardPaddingComfortable,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 230),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ToneIcon(icon: icon, tone: tone),
                      CollectSpacing.gap16,
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                      CollectSpacing.gap8,
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground.withValues(alpha: 0.76),
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MoneyCard extends StatelessWidget {
  const MoneyCard({
    required this.label,
    required this.amount,
    this.detail,
    this.icon = CollectIcons.money,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String label;
  final int amount;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          CollectSpacing.gap12,
          Text(
            formatRwf(amount),
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          if (detail != null) ...[
            CollectSpacing.gap4,
            Text(
              detail!,
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class AmountHero extends StatelessWidget {
  const AmountHero({
    required this.amount,
    required this.label,
    this.detail,
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.trim().isNotEmpty) ...[
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          CollectSpacing.gap8,
        ],
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRwf(amount),
            maxLines: 1,
            style: CollectTypography.amountHero(colors.textPrimary),
          ),
        ),
        if (detail != null) ...[
          CollectSpacing.gap8,
          Text(
            detail!,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class CollectIdDisplay extends StatelessWidget {
  const CollectIdDisplay({
    required this.publicId,
    this.label = 'Collect ID',
    this.onCopy,
    super.key,
  });

  final String publicId;
  final String label;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: CollectTypography.eyebrowLabel(colors.textMuted),
                ),
                CollectSpacing.gap8,
                SelectableText(
                  value,
                  style: CollectTypography.collectIdDisplay(colors.textPrimary),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Copy Collect ID',
            onPressed: onCopy,
            icon: const Icon(CollectIcons.copy),
          ),
        ],
      ),
    );
  }
}

class OtpCodeField extends StatelessWidget {
  const OtpCodeField({required this.controller, this.length = 6, super.key});

  final TextEditingController controller;
  final int length;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(length),
      ],
      style: CollectTypography.collectIdDisplay(colors.textPrimary),
      decoration: collectInputDecoration(
        context,
        label: 'Verification code',
        helper: 'Enter the $length-digit WhatsApp code.',
      ).copyWith(counterText: ''),
    );
  }
}

class CollectTextInput extends StatelessWidget {
  const CollectTextInput({
    required this.controller,
    required this.label,
    this.helper,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType:
          keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
      textInputAction:
          textInputAction ??
          (maxLines > 1 ? TextInputAction.newline : TextInputAction.next),
      autofillHints: autofillHints,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      autocorrect: autocorrect,
      decoration: collectInputDecoration(context, label: label, helper: helper),
    );
  }
}

class SearchWithClearField extends StatelessWidget {
  const SearchWithClearField({
    required this.controller,
    required this.label,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(color: colors.glassBorder),
        boxShadow: [
          BoxShadow(
            color: colors.periwinklePaint.withValues(alpha: 0.18),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: 1,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: label,
          prefixIcon: Icon(CollectIcons.search, color: colors.textSecondary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x4,
            vertical: CollectSpacing.x4,
          ),
        ),
      ),
    );
  }
}

class CollectTopChromeAction {
  const CollectTopChromeAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hasBadge = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool hasBadge;
}

class CollectTopChrome extends StatelessWidget {
  const CollectTopChrome({
    this.avatarLabel,
    this.onAvatarTap,
    this.hasUnread = false,
    this.searchLabel = 'Search',
    this.searchController,
    this.onSearchChanged,
    this.onSearchTap,
    this.actions = const [],
    this.showSearch = true,
    super.key,
  });

  final String? avatarLabel;
  final VoidCallback? onAvatarTap;
  final bool hasUnread;
  final String searchLabel;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchTap;
  final List<CollectTopChromeAction> actions;
  final bool showSearch;

  @override
  Widget build(BuildContext context) {
    final visibleActions = actions.take(2).toList();
    return Semantics(
      container: true,
      label: 'Primary screen actions',
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            _TopChromeAvatar(
              label: avatarLabel,
              hasUnread: hasUnread,
              onTap: onAvatarTap,
            ),
            if (showSearch) ...[
              CollectSpacing.gapW12,
              Expanded(
                child: searchController == null
                    ? _TopChromeSearchButton(
                        label: searchLabel,
                        onTap: onSearchTap,
                      )
                    : _TopChromeSearchField(
                        controller: searchController!,
                        label: searchLabel,
                        onChanged: onSearchChanged,
                      ),
              ),
            ] else
              const Spacer(),
            if (visibleActions.isNotEmpty) CollectSpacing.gapW12,
            for (var index = 0; index < visibleActions.length; index += 1) ...[
              if (index > 0) CollectSpacing.gapW8,
              _TopChromeActionButton(action: visibleActions[index]),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopChromeAvatar extends StatelessWidget {
  const _TopChromeAvatar({
    required this.label,
    required this.hasUnread,
    this.onTap,
  });

  final String? label;
  final bool hasUnread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    final effectiveOnTap = onTap ?? () => context.go('/settings/profile');
    return Tooltip(
      message: 'Open profile',
      child: Semantics(
        button: true,
        label: label == null ? 'Open profile' : 'Open profile for $label',
        hint: 'Opens the profile page',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CollectColors.referencePaymentsPurple.withValues(
                      alpha: 0.96,
                    ),
                    CollectColors.inkPrimary.withValues(alpha: 0.96),
                  ],
                ),
                border: Border.all(
                  color: foreground.withValues(alpha: 0.22),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: CollectColors.inkPrimary.withValues(alpha: 0.24),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                color: colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: effectiveOnTap,
                  child: SizedBox.square(
                    dimension: 52,
                    child: Center(
                      child: _CollectProfileGlyph(
                        backgroundColor: foreground.withValues(alpha: 0.14),
                        color: foreground,
                        size: 40,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasUnread)
              Positioned(
                right: 2,
                top: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.brandAction,
                    shape: BoxShape.circle,
                    border: Border.all(color: foreground, width: 2),
                  ),
                  child: const SizedBox.square(dimension: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopChromeSearchButton extends StatelessWidget {
  const _TopChromeSearchButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Tooltip(
      message: label,
      child: Material(
        color: CollectColors.inkPrimary.withValues(alpha: 0.92),
        borderRadius: CollectRadius.pillBorder,
        child: InkWell(
          borderRadius: CollectRadius.pillBorder,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: CollectRadius.pillBorder,
              border: Border.all(color: foreground.withValues(alpha: 0.24)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
              ),
              child: Row(
                children: [
                  Icon(CollectIcons.search, color: foreground),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopChromeSearchField extends StatelessWidget {
  const _TopChromeSearchField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: CollectColors.inkPrimary.withValues(alpha: 0.92),
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(color: foreground.withValues(alpha: 0.24)),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        minLines: 1,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: foreground.withValues(alpha: 0.76),
            fontWeight: FontWeight.w800,
          ),
          prefixIcon: Icon(CollectIcons.search, color: foreground),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: Icon(Icons.close_rounded, color: foreground),
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: CollectSpacing.x3,
            vertical: CollectSpacing.x3,
          ),
        ),
      ),
    );
  }
}

class _TopChromeActionButton extends StatelessWidget {
  const _TopChromeActionButton({required this.action});

  final CollectTopChromeAction action;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Tooltip(
      message: action.tooltip,
      child: Semantics(
        button: true,
        label: action.tooltip,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: CollectColors.inkPrimary.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: action.onPressed,
                child: SizedBox.square(
                  dimension: 52,
                  child: Icon(action.icon, color: foreground, size: 26),
                ),
              ),
            ),
            if (action.hasBadge)
              Positioned(
                right: 4,
                top: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.brandAction,
                    shape: BoxShape.circle,
                    border: Border.all(color: foreground, width: 2),
                  ),
                  child: const SizedBox.square(dimension: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class FinancialListRow extends StatelessWidget {
  const FinancialListRow({
    required this.title,
    required this.meta,
    this.amountRwf,
    this.subtitle,
    this.transactionId,
    this.leading,
    this.tone = CollectStatusTone.success,
    this.onTap,
    super.key,
  });

  final String title;
  final int? amountRwf;
  final String meta;
  final String? subtitle;
  final String? transactionId;
  final IconData? leading;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.controlBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x4),
          child: Row(
            children: [
              _ToneIcon(icon: leading ?? CollectIcons.money, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    if (subtitle != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: CollectTypography.transactionMeta(
                        colors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      SelectableText(
                        transactionId!,
                        style: CollectTypography.transactionMeta(
                          colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (amountRwf != null) ...[
                CollectSpacing.gapW12,
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatRwf(amountRwf!),
                    style: CollectTypography.amountCompact(colors.textPrimary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AmountEntryPanel extends StatelessWidget {
  const AmountEntryPanel({
    required this.controller,
    required this.amount,
    required this.quickAmounts,
    required this.onQuickAmount,
    this.label,
    this.detail,
    this.error,
    super.key,
  });

  final TextEditingController controller;
  final int amount;
  final List<int> quickAmounts;
  final ValueChanged<int> onQuickAmount;
  final String? label;
  final String? detail;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final amountStyle = CollectTypography.amountDisplay(
      colors.textPrimary,
    ).copyWith(fontSize: 44, height: 1.05);
    final prefixStyle = amountStyle.copyWith(color: colors.textSecondary);
    return CollectCard(
      emphasis: CollectCardEmphasis.compact,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (label?.trim().isNotEmpty == true ? label! : 'Amount'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.glassControl,
                  borderRadius: CollectRadius.pillBorder,
                  border: Border.all(color: colors.glassBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x3,
                    vertical: CollectSpacing.x1,
                  ),
                  child: Text(
                    'RWF',
                    style: CollectTypography.eyebrowLabel(colors.textMuted),
                  ),
                ),
              ),
            ],
          ),
          CollectSpacing.gap16,
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.glassControl,
              borderRadius: CollectRadius.panelBorder,
              border: Border.all(color: colors.glassBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
                vertical: CollectSpacing.x3,
              ),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: amountStyle,
                maxLines: 1,
                decoration: InputDecoration(
                  hintText: '0',
                  prefixText: 'RWF ',
                  prefixStyle: prefixStyle,
                  hintStyle: amountStyle.copyWith(color: colors.textMuted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
          if (detail != null) ...[
            CollectSpacing.gap8,
            Text(detail!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          CollectSpacing.gap16,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              for (final option in quickAmounts)
                ChoiceChip(
                  label: Text(_compactAmount(option)),
                  selected: amount == option,
                  selectedColor: CollectColors.brandPeriwinkle,
                  backgroundColor: colors.glassControl,
                  showCheckmark: false,
                  side: BorderSide(
                    color: amount == option
                        ? colors.borderAccent
                        : colors.borderSoft,
                    width: amount == option ? 1.5 : 1,
                  ),
                  labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: amount == option
                        ? colors.selectedOnAccent
                        : colors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                  onSelected: (_) => onQuickAmount(option),
                ),
            ],
          ),
          if (error != null) ...[
            CollectSpacing.gap12,
            Text(
              error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class BottomActionSurface extends StatelessWidget {
  const BottomActionSurface({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassPanel,
        borderRadius: CollectRadius.cardBorder,
        border: Border.all(color: colors.glassBorder),
        boxShadow: CollectShadows.card(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              children[index],
              if (index != children.length - 1) CollectSpacing.gap12,
            ],
          ],
        ),
      ),
    );
  }
}

enum CollectMomoReceiverMode { momoNumber, momoPayCode }

class CollectMomoReceiverModeToggle extends StatelessWidget {
  const CollectMomoReceiverModeToggle({
    required this.mode,
    required this.onChanged,
    super.key,
  });

  final CollectMomoReceiverMode mode;
  final ValueChanged<CollectMomoReceiverMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x1),
        child: Row(
          children: [
            Expanded(
              child: _CollectMomoReceiverModeButton(
                label: 'MoMo Number',
                icon: CollectIcons.momo,
                selected: mode == CollectMomoReceiverMode.momoNumber,
                onTap: () => onChanged(CollectMomoReceiverMode.momoNumber),
              ),
            ),
            CollectSpacing.gapW8,
            Expanded(
              child: _CollectMomoReceiverModeButton(
                label: 'MoMo Pay',
                icon: CollectIcons.qr,
                selected: mode == CollectMomoReceiverMode.momoPayCode,
                onTap: () => onChanged(CollectMomoReceiverMode.momoPayCode),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectMomoReceiverModeButton extends StatelessWidget {
  const _CollectMomoReceiverModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = selected ? colors.onAccent : colors.textSecondary;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: CollectRadius.controlBorder,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 46,
            decoration: BoxDecoration(
              color: selected ? colors.actionColor : colors.transparent,
              borderRadius: CollectRadius.controlBorder,
              border: Border.all(
                color: selected ? colors.actionColor : colors.glassBorder,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: CollectSpacing.x2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 19),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectMobileInputField extends StatelessWidget {
  const CollectMobileInputField({
    required this.controller,
    required this.icon,
    required this.label,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autocorrect = false,
    super.key,
  });

  final TextEditingController controller;
  final IconData icon;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autocorrect;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassControl,
        borderRadius: CollectRadius.controlBorder,
        border: Border.all(color: colors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x3,
          vertical: CollectSpacing.x1,
        ),
        child: Row(
          crossAxisAlignment: maxLines > 1
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(
                top: maxLines > 1 ? CollectSpacing.x2 : 0,
              ),
              child: Icon(icon, color: colors.textSecondary, size: 22),
            ),
            CollectSpacing.gapW12,
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                textInputAction:
                    textInputAction ??
                    (maxLines > 1
                        ? TextInputAction.newline
                        : TextInputAction.next),
                autofillHints: autofillHints,
                maxLines: maxLines,
                textCapitalization: textCapitalization,
                autocorrect: autocorrect,
                decoration: InputDecoration(
                  labelText: label,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MinimalStatePanel extends StatelessWidget {
  const MinimalStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = CollectStatusTone.info,
    this.primaryAction,
    this.secondaryAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final CollectStatusTone tone;
  final Widget? primaryAction;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final asset = _minimalStateAsset(icon, tone);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? colors.onImagePrimary : colors.surfaceReadable;
    final scrimBase = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : colors.textPrimary;
    Widget stateImage = Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => DecoratedBox(
        decoration: BoxDecoration(gradient: colors.screenGradient),
      ),
    );
    if (isDark) {
      stateImage = ColorFiltered(
        colorFilter: ColorFilter.mode(
          scrimBase.withValues(alpha: 0.44),
          BlendMode.multiply,
        ),
        child: stateImage,
      );
    }
    return CollectCard(
      emphasis: CollectCardEmphasis.glow,
      accentColor: colors.statusForeground(tone),
      padding: EdgeInsets.zero,
      backgroundGradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(
            colors.statusForeground(tone).withValues(alpha: 0.28),
            scrimBase,
          ),
          Color.alphaBlend(
            colors.periwinklePaint.withValues(alpha: 0.24),
            CollectColors.referencePaymentsPurple,
          ),
          CollectColors.referenceAssetNavy,
        ],
      ),
      child: Semantics(
        container: true,
        label: message.trim().isEmpty ? title : '$title, $message',
        child: ClipRRect(
          borderRadius: CollectRadius.cardLargeBorder,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 156),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.48,
                      heightFactor: 1,
                      child: stateImage,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          scrimBase.withValues(alpha: isDark ? 0.98 : 0.98),
                          scrimBase.withValues(alpha: isDark ? 0.84 : 0.82),
                          scrimBase.withValues(alpha: isDark ? 0.26 : 0.20),
                        ],
                        stops: const [0, 0.56, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: CollectSpacing.cardPaddingComfortable,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ToneIcon(icon: icon, tone: tone, large: true),
                        CollectSpacing.gap16,
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w900,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (message.trim().isNotEmpty) ...[
                          CollectSpacing.gap8,
                          Text(
                            message,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: foreground.withValues(alpha: 0.76),
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (primaryAction != null ||
                            secondaryAction != null) ...[
                          CollectSpacing.gap20,
                          ?primaryAction,
                          if (secondaryAction != null) ...[
                            CollectSpacing.gap12,
                            secondaryAction!,
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _minimalStateAsset(IconData icon, CollectStatusTone tone) {
  if (icon == CollectIcons.qr ||
      icon == CollectIcons.public ||
      icon == CollectIcons.share ||
      icon == CollectIcons.search) {
    return 'assets/brand/generated/collect_visual_qr_share.png';
  }
  if (icon == CollectIcons.sms ||
      icon == CollectIcons.momo ||
      icon == CollectIcons.money ||
      icon == CollectIcons.shield ||
      tone == CollectStatusTone.warning ||
      tone == CollectStatusTone.danger) {
    return 'assets/brand/generated/collect_visual_momo_signal.png';
  }
  return 'assets/brand/generated/collect_visual_group_momentum.png';
}

class EmptySearchState extends StatelessWidget {
  const EmptySearchState({
    required this.title,
    required this.message,
    this.onClear,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return MinimalStatePanel(
      icon: CollectIcons.search,
      title: title,
      message: message,
      tone: CollectStatusTone.neutral,
      primaryAction: onClear == null
          ? null
          : CollectButton(
              label: 'Clear search',
              icon: CollectIcons.sync,
              onPressed: onClear,
              expand: true,
            ),
    );
  }
}

class CollectWizardProgress extends StatelessWidget {
  const CollectWizardProgress({
    required this.labels,
    required this.currentStep,
    super.key,
  });

  final List<String> labels;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final safeStep = currentStep.clamp(0, labels.length - 1).toInt();
    return Semantics(
      container: true,
      label: 'Step ${safeStep + 1} of ${labels.length}: ${labels[safeStep]}',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        child: Wrap(
          spacing: CollectSpacing.x2,
          runSpacing: CollectSpacing.x2,
          children: [
            for (var index = 0; index < labels.length; index += 1)
              CollectStatusChip(
                label: labels[index],
                icon: index < currentStep
                    ? CollectIcons.check
                    : index == currentStep
                    ? CollectIcons.pending
                    : CollectIcons.info,
                tone: index < currentStep
                    ? CollectStatusTone.success
                    : index == currentStep
                    ? CollectStatusTone.info
                    : CollectStatusTone.neutral,
              ),
          ],
        ),
      ),
    );
  }
}

class FormSectionCard extends StatelessWidget {
  const FormSectionCard({
    required this.children,
    this.title,
    this.message,
    this.errorTitle,
    this.errorMessage,
    this.actions = const [],
    super.key,
  });

  final String? title;
  final String? message;
  final String? errorTitle;
  final String? errorMessage;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              CollectSpacing.gap4,
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (children.isNotEmpty) CollectSpacing.gap16,
          ],
          for (var index = 0; index < children.length; index += 1) ...[
            children[index],
            if (index != children.length - 1) CollectSpacing.gap12,
          ],
          if (errorMessage != null) ...[
            CollectSpacing.gap12,
            InfoSecurityBanner(
              title: errorTitle ?? 'Action failed',
              message: errorMessage!,
              tone: CollectStatusTone.danger,
            ),
          ],
          if (actions.isNotEmpty) ...[
            CollectSpacing.gap16,
            for (var index = 0; index < actions.length; index += 1) ...[
              actions[index],
              if (index != actions.length - 1) CollectSpacing.gap12,
            ],
          ],
        ],
      ),
    );
  }
}

class CollectConfirmationDialog extends StatelessWidget {
  const CollectConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmIcon,
    this.danger = false,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final IconData confirmIcon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        CollectButton(
          label: 'Cancel',
          icon: CollectIcons.chevron,
          onPressed: () => Navigator.of(context).pop(false),
          variant: CollectButtonVariant.secondary,
        ),
        CollectButton(
          label: confirmLabel,
          icon: confirmIcon,
          onPressed: () => Navigator.of(context).pop(true),
          variant: danger
              ? CollectButtonVariant.danger
              : CollectButtonVariant.primary,
        ),
      ],
    );
  }
}

class CollectPermissionRecoveryPanel extends StatelessWidget {
  const CollectPermissionRecoveryPanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.settingsMessage,
    this.tone = CollectStatusTone.warning,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String settingsMessage;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MinimalStatePanel(
          icon: icon,
          title: title,
          message: message,
          tone: tone,
        ),
        InfoSecurityBanner(
          title: 'Settings recovery',
          message: settingsMessage,
          tone: CollectStatusTone.info,
        ),
      ],
    );
  }
}

class NotificationUpdateRow extends StatelessWidget {
  const NotificationUpdateRow({
    required this.title,
    required this.message,
    required this.meta,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String title;
  final String message;
  final String meta;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToneIcon(icon: _statusIcon(tone, null), tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  meta,
                  style: CollectTypography.transactionMeta(colors.textMuted),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentReviewSummary extends StatelessWidget {
  const PaymentReviewSummary({
    required this.amountRwf,
    required this.groupTitle,
    required this.receiverLabel,
    required this.receiverMomoNumber,
    this.onEdit,
    super.key,
  });

  final int amountRwf;
  final String groupTitle;
  final String receiverLabel;
  final String receiverMomoNumber;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review contribution',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (onEdit != null)
                CollectButton(
                  label: 'Edit',
                  icon: CollectIcons.tune,
                  onPressed: onEdit,
                  variant: CollectButtonVariant.subtle,
                ),
            ],
          ),
          CollectSpacing.gap16,
          Text(
            formatRwf(amountRwf),
            style: CollectTypography.amountDisplay(colors.textPrimary),
          ),
          CollectSpacing.gap20,
          _ReviewLine(label: 'Group', value: groupTitle),
          _ReviewLine(
            label: 'MoMo',
            value: maskMomoNumberForDisplay(receiverMomoNumber),
          ),
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label.toUpperCase(),
              style: CollectTypography.eyebrowLabel(colors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class CollectStatusChip extends StatelessWidget {
  const CollectStatusChip({
    required this.label,
    this.tone = CollectStatusTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final CollectStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.statusForeground(tone);
    return Semantics(
      label: 'Status: $label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.statusBackground(tone),
            borderRadius: CollectRadius.pillBorder,
            border: Border.all(color: foreground.withValues(alpha: 0.22)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CollectSpacing.x3,
              vertical: CollectSpacing.x2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_statusIcon(tone, icon), size: 15, color: foreground),
                CollectSpacing.gapW8,
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CollectProgressBar extends StatelessWidget {
  const CollectProgressBar({required this.value, this.label, super.key});

  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: CollectRadius.pillBorder,
          child: LinearProgressIndicator(
            minHeight: CollectSpacing.x2,
            value: clamped,
          ),
        ),
        if (label != null) ...[
          CollectSpacing.gap8,
          Text(
            label!,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class CollectAvatar extends StatelessWidget {
  const CollectAvatar({
    required this.label,
    this.imageUrl,
    this.size = 40,
    super.key,
  });

  final String label;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: colors.statusBackground(CollectStatusTone.privacy),
      foregroundColor: colors.periwinklePaint,
      backgroundImage: hasImage ? NetworkImage(imageUrl!) : null,
      child: hasImage
          ? null
          : _CollectProfileGlyph(
              backgroundColor: colors.periwinklePaint.withValues(alpha: 0.14),
              color: colors.periwinklePaint,
              size: (size * 0.74).clamp(24, 44).toDouble(),
            ),
    );
  }
}

class _CollectProfileGlyph extends StatelessWidget {
  const _CollectProfileGlyph({
    required this.backgroundColor,
    required this.color,
    required this.size,
  });

  final Color backgroundColor;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final headSize = size * 0.30;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: SizedBox.square(dimension: size),
          ),
          Positioned(
            top: size * 0.18,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: SizedBox.square(dimension: headSize),
            ),
          ),
          Positioned(
            bottom: size * 0.16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(size * 0.26),
                  topRight: Radius.circular(size * 0.26),
                  bottomLeft: Radius.circular(size * 0.12),
                  bottomRight: Radius.circular(size * 0.12),
                ),
              ),
              child: SizedBox(width: size * 0.58, height: size * 0.26),
            ),
          ),
        ],
      ),
    );
  }
}

class CollectAvatarStack extends StatelessWidget {
  const CollectAvatarStack({required this.labels, super.key});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final visible = labels.take(3).toList();
    return SizedBox(
      width: 24.0 + (visible.length * 24.0),
      height: 40,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * 22.0,
              child: CollectAvatar(label: visible[index], size: 36),
            ),
        ],
      ),
    );
  }
}

class CollectListTile extends StatelessWidget {
  const CollectListTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    super.key,
  });

  final String title;
  final String? subtitle;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final visibleSubtitle = _compactDataSubtitle(subtitle);
    return InkWell(
      borderRadius: CollectRadius.mdBorder,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
        child: Row(
          children: [
            if (leading != null) ...[
              _ToneIcon(icon: leading!, tone: CollectStatusTone.info),
              CollectSpacing.gapW12,
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (visibleSubtitle != null) ...[
                    CollectSpacing.gap4,
                    Text(
                      visibleSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null || onTap != null) ...[
              CollectSpacing.gapW12,
              trailing ?? Icon(CollectIcons.chevron, color: colors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

String? _compactDataSubtitle(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;
  if (text.length > 28) return null;
  if (text.startsWith('#') ||
      text.startsWith('+') ||
      text.startsWith('RWF') ||
      text.contains('MoMo')) {
    return text;
  }
  return null;
}

class ActivityRow extends StatelessWidget {
  const ActivityRow({
    required this.title,
    required this.amount,
    required this.meta,
    this.tone = CollectStatusTone.success,
    this.transactionId,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final CollectStatusTone tone;
  final String? transactionId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        children: [
          _ToneIcon(icon: CollectIcons.money, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IdentityTitle(title: title),
                CollectSpacing.gap4,
                Text(
                  meta,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (transactionId != null) ...[
                  CollectSpacing.gap4,
                  Text(
                    transactionId!,
                    style: CollectTypography.mono(colors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          Text(
            formatRwf(amount),
            style: CollectTypography.amountCompact(colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    const foreground = CollectColors.brandPaper;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: foreground,
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x2,
                vertical: CollectSpacing.x1,
              ),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            child: Text(
              actionLabel!,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

class CollectEmptyState extends StatelessWidget {
  const CollectEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CollectGradientBackground(
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: CollectSpacing.screenPadding,
            child: CollectCard(
              emphasis: CollectCardEmphasis.flat,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToneIcon(
                    icon: icon,
                    tone: CollectStatusTone.info,
                    large: true,
                  ),
                  CollectSpacing.gap16,
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  CollectSpacing.gap8,
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (action != null) ...[CollectSpacing.gap20, action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollectErrorState extends StatelessWidget {
  const CollectErrorState({
    required this.title,
    required this.message,
    this.onRetry,
    super.key,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return CollectEmptyState(
      icon: CollectIcons.error,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : CollectButton(label: 'Try again', onPressed: onRetry),
    );
  }
}

class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({
    this.lines = 3,
    this.semanticsLabel = 'Loading content',
    this.showCard = true,
    super.key,
  });

  final int lines;
  final String semanticsLabel;
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final skeleton = Semantics(
      container: true,
      liveRegion: true,
      label: semanticsLabel,
      child: Column(
        children: [
          for (var index = 0; index < lines; index++) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.42),
                borderRadius: CollectRadius.pillBorder,
              ),
              child: SizedBox(
                height: index == 0 ? 22 : 14,
                width: double.infinity,
              ),
            ),
            if (index != lines - 1) CollectSpacing.gap12,
          ],
        ],
      ),
    );
    if (!showCard) return skeleton;
    return CollectCard(child: skeleton);
  }
}

class LoadingStatePanel extends StatelessWidget {
  const LoadingStatePanel({
    required this.title,
    required this.message,
    this.icon = CollectIcons.sync,
    this.lines = 3,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final int lines;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Loading: $title',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      CollectSpacing.gap4,
                      Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            CollectSpacing.gap16,
            LoadingSkeleton(
              lines: lines,
              semanticsLabel: 'Loading placeholder for $title',
              showCard: false,
            ),
          ],
        ),
      ),
    );
  }
}

class CollectBottomSheet extends StatelessWidget {
  const CollectBottomSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CollectRadius.bottomSheet),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassPanel,
            border: Border.all(color: colors.glassBorder),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(CollectRadius.bottomSheet),
            ),
            boxShadow: CollectShadows.card(),
          ),
          child: Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: child,
          ),
        ),
      ),
    );
  }
}

class CollectSearchField extends StatelessWidget {
  const CollectSearchField({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: CollectComponentTokens.inputDecoration(
        context: context,
        label: label,
      ).copyWith(prefixIcon: const Icon(CollectIcons.search)),
    );
  }
}

class InfoSecurityBanner extends StatelessWidget {
  const InfoSecurityBanner({
    required this.message,
    this.title = 'Safety note',
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final String title;
  final String message;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final visibleMessage = message.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      padding: const EdgeInsets.symmetric(
        horizontal: CollectSpacing.x3,
        vertical: CollectSpacing.x2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToneIcon(icon: _statusIcon(tone, null), tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                if (visibleMessage.isNotEmpty) ...[
                  CollectSpacing.gap4,
                  Text(
                    visibleMessage,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
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

class PaymentIntentStatusCard extends StatelessWidget {
  const PaymentIntentStatusCard({
    required this.amountRwf,
    required this.receiverLabel,
    required this.receiverMomoNumber,
    required this.status,
    super.key,
  });

  final int amountRwf;
  final String receiverLabel;
  final String receiverMomoNumber;
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountHero(amount: amountRwf, label: 'Payment amount'),
          CollectSpacing.gap20,
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: paymentStatusLabel(status),
                tone: paymentStatusTone(status),
              ),
            ],
          ),
          CollectSpacing.gap20,
          Text(receiverLabel, style: Theme.of(context).textTheme.labelLarge),
          CollectSpacing.gap4,
          SelectableText(
            maskMomoNumberForDisplay(receiverMomoNumber),
            style: CollectTypography.amountLarge(colors.textPrimary),
          ),
          CollectSpacing.gap16,
          const InfoSecurityBanner(
            title: 'SMS verification',
            message: 'Ledger updates after SMS.',
            tone: CollectStatusTone.privacy,
          ),
        ],
      ),
    );
  }
}

class CollectDynamicIsland extends StatelessWidget {
  const CollectDynamicIsland({
    required this.activeIntent,
    required this.minimized,
    required this.onMinimize,
    required this.onClose,
    super.key,
  });

  final PaymentIntentModel activeIntent;
  final bool minimized;
  final VoidCallback onMinimize;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final intent = activeIntent;
    if (minimized) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: 'Expand payment status',
          child: Semantics(
            button: true,
            label: 'Expand payment status',
            child: Material(
              color: colors.periwinklePaint.withValues(alpha: 0.94),
              borderRadius: CollectRadius.pillBorder,
              child: InkWell(
                onTap: onMinimize,
                borderRadius: CollectRadius.pillBorder,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x4,
                    vertical: CollectSpacing.x3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CollectIcons.momo, color: colors.onAccent, size: 18),
                      CollectSpacing.gapW8,
                      Text(
                        formatRwf(intent.expectedAmountRwf),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: colors.onAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final foreground = colors.onAccent;
    final background = colors.periwinklePaint.withValues(alpha: 0.94);
    final border = colors.onAccent.withValues(alpha: 0.12);

    return Semantics(
      label: 'Live payment status',
      child: ClipRRect(
        borderRadius: CollectRadius.pillBorder,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: CollectRadius.pillBorder,
              border: Border.all(color: border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CollectSpacing.x4,
                vertical: CollectSpacing.x3,
              ),
              child: Row(
                children: [
                  Icon(CollectIcons.momo, color: foreground, size: 18),
                  CollectSpacing.gapW12,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Payment active',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        CollectSpacing.gap4,
                        Text(
                          formatRwf(intent.expectedAmountRwf),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onAccent.withValues(alpha: 0.72),
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  CollectSpacing.gapW12,
                  CollectStatusChip(
                    label: paymentStatusLabel(intent.status),
                    tone: paymentStatusTone(intent.status),
                    icon: CollectIcons.pending,
                  ),
                  CollectSpacing.gapW8,
                  IconButton(
                    tooltip: 'Minimize payment status',
                    onPressed: onMinimize,
                    icon: const Icon(Icons.remove_rounded),
                    color: foreground,
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    tooltip: 'Close payment status',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded),
                    color: foreground,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CollectBentoGrid extends StatelessWidget {
  const CollectBentoGrid({
    required this.primary,
    required this.top,
    required this.bottom,
    super.key,
  });

  final Widget primary;
  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final compact = constraints.maxWidth < 340 || textScale > 1.15;
        if (compact) {
          return Column(
            children: [
              primary,
              CollectSpacing.gap12,
              top,
              CollectSpacing.gap12,
              bottom,
            ],
          );
        }
        return SizedBox(
          height: 236,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 6, child: primary),
              CollectSpacing.gapW12,
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    Expanded(child: top),
                    CollectSpacing.gap12,
                    Expanded(child: bottom),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BentoMetricCell extends StatelessWidget {
  const BentoMetricCell({
    required this.label,
    required this.value,
    this.detail,
    this.icon = CollectIcons.dashboard,
    this.tone = CollectStatusTone.info,
    this.emphasis = false,
    super.key,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final CollectStatusTone tone;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      emphasis: emphasis ? CollectCardEmphasis.hero : CollectCardEmphasis.flat,
      padding: EdgeInsets.all(emphasis ? CollectSpacing.x4 : CollectSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              emphasis
                  ? _ToneIcon(icon: icon, tone: tone)
                  : _BentoToneIcon(icon: icon, tone: tone),
              CollectSpacing.gapW8,
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: emphasis
                      ? CollectTypography.amountLarge(colors.textPrimary)
                      : Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                ),
              ),
              if (detail != null) ...[
                CollectSpacing.gap4,
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _BentoToneIcon extends StatelessWidget {
  const _BentoToneIcon({required this.icon, required this.tone});

  final IconData icon;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.statusBackground(tone),
        borderRadius: CollectRadius.pillBorder,
      ),
      child: SizedBox.square(
        dimension: 30,
        child: Icon(icon, color: colors.statusForeground(tone), size: 17),
      ),
    );
  }
}

class PaymentPipelineIndicator extends StatelessWidget {
  const PaymentPipelineIndicator({required this.status, super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final activeStep = _pipelineStep(status);
    const stages = [
      (label: 'Start', icon: CollectIcons.pending),
      (label: 'Check', icon: CollectIcons.sms),
      (label: 'Done', icon: CollectIcons.ledger),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Payment progress: ${paymentStatusLabel(status)}',
      child: CollectCard(
        emphasis: CollectCardEmphasis.flat,
        padding: const EdgeInsets.all(CollectSpacing.x4),
        child: Row(
          children: [
            for (var index = 0; index < stages.length; index++) ...[
              Expanded(
                child: _PipelineStage(
                  label: stages[index].label,
                  icon: stages[index].icon,
                  complete: activeStep > index,
                  current: activeStep == index,
                ),
              ),
              if (index != stages.length - 1)
                Expanded(child: _PipelineLine(active: activeStep > index + 1)),
            ],
          ],
        ),
      ),
    );
  }
}

class PaymentVerifiedRing extends StatelessWidget {
  const PaymentVerifiedRing({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      padding: CollectSpacing.cardPaddingComfortable,
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colors.success, width: 6),
              color: colors.statusBackground(CollectStatusTone.success),
            ),
            child: Icon(CollectIcons.check, color: colors.success, size: 42),
          ),
          CollectSpacing.gap20,
          Text(
            'Payment recorded',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          CollectSpacing.gap8,
          Text(
            'Ledger updated.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class CollectIdCard extends StatelessWidget {
  const CollectIdCard({required this.publicId, super.key});

  final String publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final value = publicId.trim().isEmpty ? '------' : publicId.trim();
    return CollectCard(
      emphasis: CollectCardEmphasis.hero,
      padding: CollectSpacing.cardPaddingComfortable,
      child: Row(
        children: [
          _GroupIconBadge(
            icon: CollectIcons.profile,
            accent: colors.actionColor,
            size: 52,
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: CollectTypography.amountHero(colors.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LedgerRow extends StatelessWidget {
  LedgerRow.confirmed({required Contribution contribution, super.key})
    : title = compactCollectIdLabel(contribution.supporterLabel),
      amountRwf = contribution.amountRwf,
      meta = formatCollectDateTime(contribution.createdAt),
      transactionId = contribution.transactionId,
      tone = CollectStatusTone.success,
      action = null;

  LedgerRow.review({
    required ParsedPaymentEvent event,
    required this.action,
    super.key,
  }) : title = 'Needs review',
       amountRwf = event.amountRwf,
       meta =
           'Confidence ${(event.confidence * 100).round()}% · ${event.senderLabel}',
       transactionId = event.transactionId,
       tone = CollectStatusTone.warning;

  final String title;
  final int amountRwf;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Column(
        children: [
          ActivityFeedItem(
            title: title,
            amount: amountRwf,
            meta: meta,
            transactionId: transactionId,
            tone: tone,
          ),
          if (action != null) ...[CollectSpacing.gap12, action!],
        ],
      ),
    );
  }
}

class ReceiverConsentCard extends StatelessWidget {
  const ReceiverConsentCard({
    required this.flagsEnabled,
    required this.consented,
    required this.isSyncing,
    required this.onConsentChanged,
    required this.onSync,
    super.key,
  });

  final bool flagsEnabled;
  final bool consented;
  final bool isSyncing;
  final ValueChanged<bool>? onConsentChanged;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: CollectSpacing.x2,
            runSpacing: CollectSpacing.x2,
            children: [
              CollectStatusChip(
                label: flagsEnabled ? 'Enabled' : 'Off',
                tone: flagsEnabled
                    ? CollectStatusTone.success
                    : CollectStatusTone.neutral,
              ),
              CollectStatusChip(
                label: consented ? 'Active' : 'Required',
                tone: consented
                    ? CollectStatusTone.success
                    : CollectStatusTone.warning,
              ),
            ],
          ),
          CollectSpacing.gap16,
          const InfoSecurityBanner(
            title: 'Consent',
            message:
                'Owner approval required. Private confirmation messages are used only for payment matching.',
            tone: CollectStatusTone.privacy,
          ),
          CollectSpacing.gap16,
          Material(
            color: colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: consented,
              onChanged: flagsEnabled ? onConsentChanged : null,
              title: const Text('Enable SMS app access'),
              subtitle: const Text(
                'Approved Android build and consent required.',
              ),
            ),
          ),
          CollectSpacing.gap12,
          CollectButton(
            label: isSyncing ? 'Syncing...' : 'Sync',
            icon: CollectIcons.sync,
            onPressed: flagsEnabled && consented && !isSyncing ? onSync : null,
            variant: CollectButtonVariant.secondary,
            expand: true,
          ),
        ],
      ),
    );
  }
}

class AdminReviewCard extends StatelessWidget {
  const AdminReviewCard({
    required this.title,
    required this.status,
    required this.detail,
    this.amountRwf,
    this.confidence,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final String title;
  final String status;
  final String detail;
  final int? amountRwf;
  final double? confidence;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return CollectCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CollectStatusChip(
                label: status.replaceAll('_', ' '),
                tone: statusToneFromText(status),
              ),
            ],
          ),
          CollectSpacing.gap8,
          Text(
            detail,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (amountRwf != null || confidence != null) ...[
            CollectSpacing.gap12,
            Wrap(
              spacing: CollectSpacing.x2,
              runSpacing: CollectSpacing.x2,
              children: [
                if (amountRwf != null)
                  Text(
                    formatRwf(amountRwf!),
                    style: CollectTypography.amountCompact(colors.textPrimary),
                  ),
                if (confidence != null)
                  CollectStatusChip(
                    label: 'Confidence ${(confidence! * 100).round()}%',
                    tone: confidence! >= 0.85
                        ? CollectStatusTone.success
                        : CollectStatusTone.warning,
                  ),
              ],
            ),
          ],
          if (primaryLabel != null || secondaryLabel != null) ...[
            CollectSpacing.gap16,
            Wrap(
              spacing: CollectSpacing.x2,
              runSpacing: CollectSpacing.x2,
              children: [
                if (primaryLabel != null)
                  CollectButton(label: primaryLabel!, onPressed: onPrimary),
                if (secondaryLabel != null)
                  CollectButton(
                    label: secondaryLabel!,
                    onPressed: onSecondary,
                    variant: CollectButtonVariant.secondary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class MoneyHeroCard extends StatelessWidget {
  const MoneyHeroCard({
    required this.amount,
    required this.label,
    this.detail,
    this.primaryAction,
    this.secondaryAction,
    this.chips = const [],
    super.key,
  });

  final int amount;
  final String label;
  final String? detail;
  final Widget? primaryAction;
  final Widget? secondaryAction;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final heroColor = colors.periwinklePaint;
    return AnimatedContainer(
      duration: CollectMotion.duration(context, CollectMotion.medium),
      curve: CollectMotion.standard,
      decoration: BoxDecoration(
        color: heroColor,
        borderRadius: CollectRadius.cardLargeBorder,
        boxShadow: CollectShadows.card(),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: CollectRadius.cardLargeBorder,
                border: Border.all(
                  color: colors.onImagePrimary.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          Padding(
            padding: CollectSpacing.cardPaddingComfortable,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label.trim().isNotEmpty) ...[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.78),
                    ),
                  ),
                  CollectSpacing.gap8,
                ],
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatRwf(amount),
                    style: CollectTypography.amountHero(colors.onImagePrimary),
                  ),
                ),
                if (detail != null) ...[
                  CollectSpacing.gap8,
                  Text(
                    detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onImagePrimary.withValues(alpha: 0.76),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (chips.isNotEmpty) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: chips,
                  ),
                ],
                if (primaryAction != null || secondaryAction != null) ...[
                  CollectSpacing.gap20,
                  Wrap(
                    spacing: CollectSpacing.x2,
                    runSpacing: CollectSpacing.x2,
                    children: [
                      // ignore: use_null_aware_elements
                      if (primaryAction != null) primaryAction!,
                      // ignore: use_null_aware_elements
                      if (secondaryAction != null) secondaryAction!,
                    ],
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

class QuickActionButton extends StatelessWidget {
  const QuickActionButton({
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
    this.tone = CollectStatusTone.info,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback? onTap;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      button: true,
      container: true,
      explicitChildNodes: true,
      label: detail == null ? label : '$label, $detail',
      child: Material(
        color: colors.glassControl,
        borderRadius: CollectRadius.cardBorder,
        child: InkWell(
          borderRadius: CollectRadius.cardBorder,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128, minWidth: 124),
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ToneIcon(icon: icon, tone: tone),
                  CollectSpacing.gap12,
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class QuickActionRail extends StatelessWidget {
  const QuickActionRail({
    required this.children,
    this.semanticLabel = 'Quick actions',
    super.key,
  });

  final List<Widget> children;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: semanticLabel,
      child: SizedBox(
        height: 152,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.zero,
          itemCount: children.length,
          separatorBuilder: (_, _) => CollectSpacing.gapW12,
          itemBuilder: (context, index) =>
              SizedBox(width: 142, child: children[index]),
        ),
      ),
    );
  }
}

class InsightCard extends StatelessWidget {
  const InsightCard({
    required this.title,
    required this.message,
    this.icon = CollectIcons.tips,
    this.tone = CollectStatusTone.info,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final IconData icon;
  final CollectStatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return CollectCard(
      emphasis: CollectCardEmphasis.flat,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToneIcon(icon: icon, tone: tone),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (actionLabel != null) ...[
                  CollectSpacing.gap8,
                  CollectButton(
                    label: actionLabel!,
                    icon: CollectIcons.arrowForward,
                    onPressed: onAction,
                    variant: CollectButtonVariant.subtle,
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

class SecurityNotice extends StatelessWidget {
  const SecurityNotice({
    required this.message,
    this.title = 'Trust boundary',
    this.tone = CollectStatusTone.privacy,
    super.key,
  });

  final String title;
  final String message;
  final CollectStatusTone tone;

  @override
  Widget build(BuildContext context) {
    return InfoSecurityBanner(title: title, message: message, tone: tone);
  }
}

class EmptyIllustrationState extends StatelessWidget {
  const EmptyIllustrationState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$title. $message',
      child: CollectCard(
        emphasis: CollectCardEmphasis.compact,
        padding: const EdgeInsets.symmetric(
          horizontal: CollectSpacing.x4,
          vertical: CollectSpacing.x3,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ToneIcon(icon: icon, tone: CollectStatusTone.info),
                CollectSpacing.gapW12,
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (action != null) ...[
              CollectSpacing.gap12,
              SizedBox(width: double.infinity, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

class PremiumSegmentedFilter<T> extends StatelessWidget {
  const PremiumSegmentedFilter({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: 'Filter options',
      child: Scrollbar(
        thumbVisibility: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.actionColor.withValues(alpha: 0.12);
                  }
                  return colors.surfaceRaised;
                }),
              ),
              segments: [
                for (final value in values)
                  ButtonSegment<T>(
                    value: value,
                    label: Text(
                      labelFor(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {selected},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityFeedItem extends StatelessWidget {
  const ActivityFeedItem({
    required this.title,
    required this.amount,
    required this.meta,
    this.transactionId,
    this.tone = CollectStatusTone.info,
    this.onTap,
    super.key,
  });

  final String title;
  final int amount;
  final String meta;
  final String? transactionId;
  final CollectStatusTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amountColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    return Material(
      color: colors.transparent,
      child: InkWell(
        borderRadius: CollectRadius.mdBorder,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: CollectSpacing.x3),
          child: Row(
            children: [
              _ToneIcon(icon: CollectIcons.profile, tone: tone),
              CollectSpacing.gapW12,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityTitle(title: title),
                    CollectSpacing.gap4,
                    Text(
                      meta,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (transactionId != null) ...[
                      CollectSpacing.gap4,
                      Text(
                        transactionId!,
                        style: CollectTypography.mono(colors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  formatRwf(amount),
                  style: CollectTypography.amountCompact(amountColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String compactCollectIdLabel(String label) {
  return label
      .replaceFirst(RegExp(r'^Collect ID\s+'), '')
      .replaceFirst(RegExp(r'^#'), '');
}

class _IdentityTitle extends StatelessWidget {
  const _IdentityTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cleaned = compactCollectIdLabel(title);
    final isIdentity =
        cleaned != title.replaceFirst(RegExp(r'^#'), '') ||
        RegExp(r'^\d{4,}$').hasMatch(cleaned);
    if (!isIdentity) {
      return Text(
        title,
        style: Theme.of(context).textTheme.titleSmall,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Row(
      children: [
        Icon(
          CollectIcons.profile,
          size: 18,
          color: context.collectColors.textSecondary,
        ),
        CollectSpacing.gapW8,
        Expanded(
          child: Text(
            cleaned,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

String _compactAmount(int amount) {
  if (amount >= 1000000 && amount % 1000000 == 0) {
    return '${amount ~/ 1000000}M';
  }
  if (amount >= 1000 && amount % 1000 == 0) {
    return '${amount ~/ 1000}k';
  }
  return formatRwf(amount);
}

class GroupCard extends StatelessWidget {
  const GroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
    this.variant = GroupCardVariant.owned,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;
  final GroupCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      GroupCardVariant.publicDiscovery => _PublicDiscoveryGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.compact => _CompactGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.visual => _VisualGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
      GroupCardVariant.owned => _OwnedGroupCard(
        collection: collection,
        summary: summary,
        onTap: onTap,
        primaryAction: primaryAction,
      ),
    };
  }
}

enum GroupCardVariant { owned, publicDiscovery, compact, visual }

class _OwnedGroupCard extends StatelessWidget {
  const _OwnedGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    return CollectCard(
      onTap: onTap,
      padding: CollectSpacing.cardPaddingComfortable,
      emphasis: CollectCardEmphasis.tonal,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collection.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              CollectSpacing.gapW12,
              _PrivacyGlyph(accent: accent),
            ],
          ),
          CollectSpacing.gap16,
          Row(
            children: [
              Expanded(
                child: _GroupIconMetric(
                  icon: CollectIcons.money,
                  value: formatRwf(summary.amountRaisedRwf),
                  semanticLabel:
                      'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                  accent: accent,
                ),
              ),
              Expanded(
                child: _GroupIconMetric(
                  icon: CollectIcons.people,
                  value: '${summary.supporterCount}',
                  semanticLabel: '${summary.supporterCount} group members',
                  accent: colors.success,
                ),
              ),
              if (primaryAction != null)
                Expanded(child: Center(child: primaryAction!)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PublicDiscoveryGroupCard extends StatelessWidget {
  const _PublicDiscoveryGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    const coverHeight = 124.0;
    return CollectCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.glow,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GroupCoverMedia(collection: collection),
                      _GroupCoverScrim(accent: accent),
                      Positioned(
                        top: CollectSpacing.x3,
                        right: CollectSpacing.x3,
                        child: _PublicGlyph(accent: accent),
                      ),
                      Positioned(
                        left: CollectSpacing.x3,
                        right: CollectSpacing.x3,
                        bottom: CollectSpacing.x3,
                        child: _GroupCoverTitleOverlay(
                          collection: collection,
                          accent: accent,
                          compact: true,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DecoratedBox(
                    decoration: _groupFooterDecoration(context),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        CollectSpacing.x3,
                        CollectSpacing.x1,
                        CollectSpacing.x3,
                        CollectSpacing.x2,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _GroupIconMetric(
                              icon: CollectIcons.money,
                              value: formatRwf(summary.amountRaisedRwf),
                              semanticLabel:
                                  'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                              accent: accent,
                            ),
                          ),
                          Expanded(
                            child: _GroupIconMetric(
                              icon: CollectIcons.people,
                              value: '${summary.supporterCount}',
                              semanticLabel:
                                  '${summary.supporterCount} group members',
                              accent: colors.success,
                            ),
                          ),
                          if (primaryAction != null)
                            SizedBox(
                              width: 48,
                              child: Center(child: primaryAction!),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactGroupCard extends StatelessWidget {
  const _CompactGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final accent = _groupAccent(context, collection);
    return CollectCard(
      onTap: onTap,
      emphasis: CollectCardEmphasis.compact,
      padding: const EdgeInsets.all(CollectSpacing.x3),
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  collection.title,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CollectSpacing.gap4,
                Text(
                  '${formatRwf(summary.amountRaisedRwf)} · ${summary.supporterCount} members',
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (primaryAction != null) ...[CollectSpacing.gapW12, primaryAction!],
        ],
      ),
    );
  }
}

class _VisualGroupCard extends StatelessWidget {
  const _VisualGroupCard({
    required this.collection,
    required this.summary,
    this.onTap,
    this.primaryAction,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final accent = _groupAccent(context, collection);
    const coverHeight = 136.0;
    return CollectCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      emphasis: CollectCardEmphasis.glow,
      accentColor: accent,
      backgroundGradient: _groupCardGradient(context, accent),
      child: ClipRRect(
        borderRadius: CollectRadius.cardLargeBorder,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: coverHeight,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _GroupCoverMedia(collection: collection),
                      _GroupCoverScrim(accent: accent),
                      Positioned(
                        left: CollectSpacing.x4,
                        right: CollectSpacing.x4,
                        bottom: CollectSpacing.x4,
                        child: _GroupCoverTitleOverlay(
                          collection: collection,
                          accent: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: _groupFooterDecoration(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CollectSpacing.x4,
                      CollectSpacing.x2,
                      CollectSpacing.x4,
                      CollectSpacing.x4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _GroupIconMetric(
                            icon: CollectIcons.money,
                            value: formatRwf(summary.amountRaisedRwf),
                            semanticLabel:
                                'Total collected ${formatRwf(summary.amountRaisedRwf)}',
                            accent: accent,
                          ),
                        ),
                        Expanded(
                          child: _GroupIconMetric(
                            icon: CollectIcons.people,
                            value: '${summary.supporterCount}',
                            semanticLabel:
                                '${summary.supporterCount} group members',
                            accent: colors.success,
                          ),
                        ),
                        if (primaryAction != null)
                          Expanded(child: Center(child: primaryAction!)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

LinearGradient _groupCardGradient(BuildContext context, Color accent) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    final lead = Color.alphaBlend(
      accent.withValues(alpha: 0.18),
      CollectColors.referencePaymentsPurpleDeep,
    );
    final middle = Color.alphaBlend(
      colors.periwinklePaint.withValues(alpha: 0.10),
      CollectColors.referencePaymentsPurple,
    );
    final tail = Color.alphaBlend(
      colors.rosePaint.withValues(alpha: 0.08),
      CollectColors.referenceContentDark,
    );
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lead, middle, tail],
      stops: const [0, 0.54, 1],
    );
  }
  final lead = Color.alphaBlend(
    accent.withValues(alpha: 0.24),
    colors.surfaceRaised,
  );
  final middle = Color.alphaBlend(
    colors.periwinklePaint.withValues(alpha: 0.12),
    colors.surfaceRaised,
  );
  final tail = Color.alphaBlend(
    colors.rosePaint.withValues(alpha: 0.16),
    colors.surfaceRaised,
  );
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [lead, middle, tail],
    stops: const [0, 0.55, 1],
  );
}

BoxDecoration _groupFooterDecoration(BuildContext context) {
  final colors = context.collectColors;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) {
    return BoxDecoration(
      color: CollectColors.referenceAssetNavy.withValues(alpha: 0.88),
      border: Border(
        top: BorderSide(color: colors.onImagePrimary.withValues(alpha: 0.20)),
      ),
    );
  }
  return BoxDecoration(
    color: colors.surfaceReadable.withValues(alpha: 0.88),
    border: Border(
      top: BorderSide(color: colors.textPrimary.withValues(alpha: 0.10)),
    ),
  );
}

class _GroupIconMetric extends StatelessWidget {
  const _GroupIconMetric({
    required this.icon,
    required this.value,
    required this.semanticLabel,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String semanticLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metricColor = isDark ? colors.onImagePrimary : colors.textPrimary;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final compactLargeText = textScale > 1.3;
    final textStyle = compactLargeText
        ? Theme.of(context).textTheme.labelMedium?.copyWith(
            color: metricColor,
            fontWeight: FontWeight.w900,
          )
        : Theme.of(context).textTheme.titleSmall?.copyWith(
            color: metricColor,
            fontWeight: FontWeight.w900,
          );
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: compactLargeText ? 18 : 22),
            SizedBox(height: compactLargeText ? 2 : CollectSpacing.x1),
            Text(
              value,
              style: textStyle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCoverMedia extends StatelessWidget {
  const _GroupCoverMedia({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final imageUrl = collection.imageUrl?.trim();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final dataImageBytes = _decodeDataImage(imageUrl);
      if (dataImageBytes != null) {
        return _GroupCoverImageTone(
          child: Image.memory(
            dataImageBytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: _fadeInImageFrame,
            errorBuilder: (context, error, stackTrace) =>
                _GeneratedGroupCover(collection: collection),
          ),
        );
      }
      return _GroupCoverImageTone(
        child: Image.network(
          imageUrl,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: _fadeInImageFrame,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _GeneratedGroupCover(collection: collection);
          },
          errorBuilder: (context, error, stackTrace) =>
              _GeneratedGroupCover(collection: collection),
        ),
      );
    }
    return _GeneratedGroupCover(collection: collection);
  }
}

class _GroupCoverImageTone extends StatelessWidget {
  const _GroupCoverImageTone({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        CollectColors.referencePaymentsPurpleDeep.withValues(alpha: 0.28),
        BlendMode.multiply,
      ),
      child: child,
    );
  }
}

class _GroupCoverScrim extends StatelessWidget {
  const _GroupCoverScrim({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deep = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : CollectColors.inkPrimary;
    final topAlpha = isDark ? 0.18 : 0.22;
    final midAlpha = isDark ? 0.38 : 0.42;
    final bottomAlpha = isDark ? 0.78 : 0.82;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            deep.withValues(alpha: topAlpha),
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.08 : 0.06),
              deep.withValues(alpha: midAlpha),
            ),
            deep.withValues(alpha: bottomAlpha),
          ],
          stops: const [0, 0.52, 1],
        ),
      ),
    );
  }
}

Widget _fadeInImageFrame(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0 : 1,
    duration: CollectMotion.duration(context, CollectMotion.medium),
    curve: CollectMotion.standard,
    child: child,
  );
}

Uint8List? _decodeDataImage(String value) {
  if (!value.startsWith('data:image/')) return null;
  final comma = value.indexOf(',');
  if (comma == -1 || comma == value.length - 1) return null;
  try {
    return base64Decode(value.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

class _GroupCoverTitleOverlay extends StatelessWidget {
  const _GroupCoverTitleOverlay({
    required this.collection,
    required this.accent,
    this.compact = false,
  });

  final CollectCollection collection;
  final Color accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final foreground = colors.onImagePrimary;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? CollectSpacing.x1 : 0,
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: FractionallySizedBox(
          widthFactor: compact ? 0.92 : 0.86,
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? CollectSpacing.x2 : CollectSpacing.x3,
              vertical: compact ? 5 : 7,
            ),
            child: Text(
              collection.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: compact ? 15 : 18,
                height: 1.0,
                letterSpacing: 0,
                shadows: [
                  Shadow(
                    color: CollectColors.referencePaymentsPurpleDeep.withValues(
                      alpha: 0.88,
                    ),
                    offset: const Offset(0, 1),
                    blurRadius: 8,
                  ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

class _GeneratedGroupCover extends StatelessWidget {
  const _GeneratedGroupCover({required this.collection});

  final CollectCollection collection;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverScrim = isDark
        ? CollectColors.referencePaymentsPurpleDeep
        : CollectColors.inkPrimary;
    final topAlpha = isDark ? 0.16 : 0.16;
    final bottomAlpha = isDark ? 0.62 : 0.70;
    final chipFill = isDark
        ? CollectColors.referenceContentDark.withValues(alpha: 0.88)
        : colors.surfaceReadable.withValues(alpha: 0.92);
    final chipBorder = isDark
        ? colors.onImagePrimary.withValues(alpha: 0.18)
        : colors.textPrimary.withValues(alpha: 0.12);
    final chipText = isDark ? colors.onImagePrimary : colors.textPrimary;
    final asset = _generatedGroupAsset(collection);
    return Stack(
      fit: StackFit.expand,
      children: [
        _GroupCoverImageTone(
          child: Image.asset(
            asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: _fadeInImageFrame,
            errorBuilder: (context, error, stackTrace) => DecoratedBox(
              decoration: BoxDecoration(gradient: colors.screenGradient),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                coverScrim.withValues(alpha: topAlpha),
                coverScrim.withValues(alpha: bottomAlpha),
              ],
            ),
          ),
        ),
        Positioned(
          left: CollectSpacing.x3,
          top: CollectSpacing.x3,
          child: Tooltip(
            message: collection.isPublic ? 'Public group' : 'Private group',
            child: Semantics(
              label: collection.isPublic ? 'Public group' : 'Private group',
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: chipFill,
                  shape: BoxShape.circle,
                  border: Border.all(color: chipBorder),
                ),
                child: SizedBox.square(
                  dimension: 34,
                  child: Icon(
                    collection.isPublic
                        ? CollectIcons.public
                        : CollectIcons.privacy,
                    size: 18,
                    color: collection.isPublic ? colors.success : chipText,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _generatedGroupAsset(CollectCollection collection) {
  final key = '${collection.id} ${collection.slug} ${collection.title}'
      .toLowerCase();
  if (key.contains('qr') ||
      key.contains('share') ||
      key.contains('invite') ||
      key.contains('link')) {
    return 'assets/brand/generated/collect_visual_qr_share.png';
  }
  if (key.contains('pay') ||
      key.contains('momo') ||
      key.contains('treasury') ||
      key.contains('fund')) {
    return 'assets/brand/generated/collect_visual_momo_signal.png';
  }
  return 'assets/brand/generated/collect_visual_group_momentum.png';
}

class _GroupIconBadge extends StatelessWidget {
  const _GroupIconBadge({
    required this.icon,
    required this.accent,
    required this.size,
  });

  final IconData icon;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: accent, size: size * 0.52),
      ),
    );
  }
}

class _PrivacyGlyph extends StatelessWidget {
  const _PrivacyGlyph({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Receiver details stay private',
      child: Semantics(
        label: 'Receiver details stay private',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(CollectIcons.shield, color: accent, size: 19),
          ),
        ),
      ),
    );
  }
}

class _PublicGlyph extends StatelessWidget {
  const _PublicGlyph({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Public group',
      child: Semantics(
        label: 'Public group',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(CollectIcons.public, color: accent, size: 19),
          ),
        ),
      ),
    );
  }
}

class CollectBrandMark extends StatelessWidget {
  const CollectBrandMark({
    this.compact = false,
    this.framed = true,
    this.width,
    this.height,
    this.showWordmark = true,
    super.key,
  });

  static const assetPath =
      'assets/brand/generated/collect_wordmark_transparent.png';
  static const appIconAssetPath = 'assets/brand/collect_app_icon_static.png';

  final bool compact;
  final bool framed;
  final double? width;
  final double? height;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final markWidth = width ?? (compact ? 108.0 : 132.0);
    final markHeight = height ?? (compact ? 32.0 : 38.0);
    final wordmark = Image.asset(
      assetPath,
      width: markWidth,
      height: markHeight,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
    );
    return Semantics(
      label: 'Collect logo',
      image: true,
      child: ExcludeSemantics(
        child: framed
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.glassControl,
                  borderRadius: BorderRadius.circular(markHeight * 0.5),
                  border: Border.all(color: colors.glassBorder),
                  boxShadow: CollectShadows.soft(),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(markHeight * 0.46),
                  child: wordmark,
                ),
              )
            : SizedBox(
                width: markWidth,
                height: markHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  child: wordmark,
                ),
              ),
      ),
    );
  }
}

Color _groupAccent(BuildContext context, CollectCollection collection) {
  final colors = context.collectColors;
  final selectedColor = _colorFromHex(collection.accentColorHex);
  if (selectedColor != null) return selectedColor;
  final palette = [
    colors.brandPrimary,
    colors.brandSecondary,
    colors.brandAction,
    colors.brandSuccess,
  ];
  final key = '${collection.id}${collection.title}';
  final index =
      key.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % palette.length;
  return palette[index];
}

Color? _colorFromHex(String? hex) {
  final clean = hex?.trim().replaceFirst('#', '');
  if (clean == null || clean.length != 6) return null;
  final value = int.tryParse(clean, radix: 16);
  if (value == null) return null;
  return Color(int.parse('ff$clean', radix: 16));
}

class CollectionSummaryCard extends StatelessWidget {
  const CollectionSummaryCard({
    required this.collection,
    required this.summary,
    this.onTap,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GroupCard(collection: collection, summary: summary, onTap: onTap);
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = context.collectColors.onImagePrimary;
    final actionButtons = <Widget>[
      for (final action in actions)
        DecoratedBox(
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.10),
            shape: BoxShape.circle,
            border: Border.all(color: foreground.withValues(alpha: 0.16)),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  fixedSize: const Size(42, 42),
                  minimumSize: const Size(42, 42),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: foreground,
                ),
              ),
              child: SizedBox.square(
                dimension: 42,
                child: Center(child: action),
              ),
            ),
          ),
        ),
    ];
    return Semantics(
      container: true,
      header: true,
      label: title,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: () => goBackOrHome(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: foreground,
            style: IconButton.styleFrom(
              fixedSize: const Size(44, 44),
              minimumSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              backgroundColor: foreground.withValues(alpha: 0.10),
              side: BorderSide(color: foreground.withValues(alpha: 0.16)),
            ),
          ),
          CollectSpacing.gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.headlineSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  CollectSpacing.gap4,
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: foreground.withValues(alpha: 0.70),
                      height: 1,
                      letterSpacing: 0,
                    ),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          for (final action in actionButtons) ...[CollectSpacing.gapW8, action],
        ],
      ),
    );
  }
}

class CollectPlainPageHeader extends StatelessWidget {
  const CollectPlainPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ScreenHeader(title: title, subtitle: subtitle, actions: actions);
  }
}

class CollectGradientBackground extends StatelessWidget {
  const CollectGradientBackground({
    required this.child,
    this.routePath,
    super.key,
  });

  final Widget child;
  final String? routePath;

  @override
  Widget build(BuildContext context) {
    String? path = routePath;
    path ??= CollectBackgroundRouteScope.maybeOf(context);
    if (path == null) {
      try {
        path = GoRouterState.of(context).uri.path;
      } catch (_) {
        path = null;
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: context.collectColors.screenGradientForPath(path),
      ),
      child: child,
    );
  }
}

class CollectBackgroundRouteScope extends InheritedWidget {
  const CollectBackgroundRouteScope({
    required this.routePath,
    required super.child,
    super.key,
  });

  final String routePath;

  static String? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CollectBackgroundRouteScope>()
        ?.routePath;
  }

  @override
  bool updateShouldNotify(CollectBackgroundRouteScope oldWidget) {
    return oldWidget.routePath != routePath;
  }
}

class PremiumScaffold extends StatelessWidget {
  const PremiumScaffold({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CollectGradientBackground(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: CollectSpacing.screenPadding.copyWith(
                  bottom: bottomAction == null
                      ? CollectSpacing.screenCompact + 112
                      : CollectSpacing.x3,
                ),
                children: [
                  if (persistentPill != null) ...[
                    persistentPill!,
                    compact ? CollectSpacing.gap12 : CollectSpacing.gap20,
                  ],
                  if (showHeader)
                    ScreenHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                  if (banner != null) ...[CollectSpacing.gap20, banner!],
                  compact ? CollectSpacing.gap12 : CollectSpacing.gap24,
                  ..._withGaps(
                    children,
                    gap: compact ? CollectSpacing.gap12 : CollectSpacing.gap16,
                  ),
                ],
              ),
            ),
            if (bottomAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CollectSpacing.x4,
                  CollectSpacing.x2,
                  CollectSpacing.x4,
                  CollectSpacing.x4,
                ),
                child: bottomAction!,
              ),
          ],
        ),
      ),
    );
  }

  static List<Widget> _withGaps(List<Widget> children, {required Widget gap}) {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      spaced.add(children[index]);
      if (index != children.length - 1) spaced.add(gap);
    }
    return spaced;
  }
}

class ScreenScaffoldLayout extends StatelessWidget {
  const ScreenScaffoldLayout({
    required this.title,
    required this.children,
    this.subtitle,
    this.actions = const [],
    this.banner,
    this.persistentPill,
    this.bottomAction,
    this.showHeader = true,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? banner;
  final Widget? persistentPill;
  final Widget? bottomAction;
  final List<Widget> children;
  final bool showHeader;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return PremiumScaffold(
      title: title,
      subtitle: subtitle,
      actions: actions,
      banner: banner,
      persistentPill: persistentPill,
      bottomAction: bottomAction,
      showHeader: showHeader,
      compact: compact,
      children: children,
    );
  }
}

CollectStatusTone paymentStatusTone(String status) {
  return switch (status) {
    'matched' || 'confirmed' || 'paid' => CollectStatusTone.success,
    'needs_review' || 'review' => CollectStatusTone.warning,
    'expired' || 'failed' => CollectStatusTone.danger,
    'pending' => CollectStatusTone.info,
    _ => CollectStatusTone.neutral,
  };
}

int _pipelineStep(String status) {
  return switch (status) {
    'matched' || 'confirmed' || 'paid' => 3,
    'needs_review' || 'review' => 2,
    'expired' || 'failed' => 1,
    _ => 1,
  };
}

class _PipelineStage extends StatelessWidget {
  const _PipelineStage({
    required this.label,
    required this.icon,
    required this.complete,
    required this.current,
  });

  final String label;
  final IconData icon;
  final bool complete;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final tone = complete
        ? CollectStatusTone.success
        : current
        ? CollectStatusTone.info
        : CollectStatusTone.neutral;
    final foreground = colors.statusForeground(tone);
    final stateLabel = complete
        ? 'complete'
        : current
        ? 'current'
        : 'pending';
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$label step $stateLabel',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.statusBackground(tone),
              border: Border.all(color: foreground.withValues(alpha: 0.26)),
            ),
            child: SizedBox.square(
              dimension: 38,
              child: Icon(
                complete ? CollectIcons.check : icon,
                color: foreground,
              ),
            ),
          ),
          CollectSpacing.gap8,
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PipelineLine extends StatelessWidget {
  const _PipelineLine({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          color: active
              ? colors.success
              : colors.border.withValues(alpha: 0.72),
          borderRadius: CollectRadius.pillBorder,
        ),
      ),
    );
  }
}

String paymentStatusLabel(String status) {
  return switch (status) {
    'matched' => 'Matched',
    'confirmed' || 'paid' => 'Confirmed',
    'needs_review' || 'review' => 'Needs review',
    'expired' => 'Expired',
    'pending' => 'Pending',
    _ => status.replaceAll('_', ' '),
  };
}

CollectStatusTone statusToneFromText(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('approved') ||
      normalized.contains('allocated') ||
      normalized.contains('matched') ||
      normalized.contains('confirmed')) {
    return CollectStatusTone.success;
  }
  if (normalized.contains('pending') ||
      normalized.contains('review') ||
      normalized.contains('requested')) {
    return CollectStatusTone.warning;
  }
  if (normalized.contains('reject') ||
      normalized.contains('danger') ||
      normalized.contains('expired')) {
    return CollectStatusTone.danger;
  }
  if (normalized.contains('private')) {
    return CollectStatusTone.privacy;
  }
  return CollectStatusTone.neutral;
}

String maskMomoNumberForDisplay(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'Not configured') return trimmed;
  final localMomo = PhoneNormalizer.tryNormalizeMtnMomoLocal(trimmed);
  if (localMomo != null) {
    return '${localMomo.substring(0, 3)}***${localMomo.substring(6)}';
  }
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return 'MoMo linked';
  final suffix = digits.substring(digits.length - 4);
  return '***$suffix';
}

InputDecoration collectInputDecoration(
  BuildContext context, {
  required String label,
  String? helper,
  String? prefix,
}) {
  return CollectComponentTokens.inputDecoration(
    context: context,
    label: label,
    helper: helper,
    prefix: prefix,
  );
}

void copyToClipboard(BuildContext context, String text, {String? message}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message ?? 'Copied securely.')));
}

void goBackOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

IconData _statusIcon(CollectStatusTone tone, IconData? override) {
  if (override != null) return override;
  return switch (tone) {
    CollectStatusTone.success => CollectIcons.check,
    CollectStatusTone.warning => CollectIcons.warning,
    CollectStatusTone.danger => CollectIcons.error,
    CollectStatusTone.info => CollectIcons.info,
    CollectStatusTone.privacy => CollectIcons.lock,
    CollectStatusTone.neutral => CollectIcons.info,
  };
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.icon, required this.tone, this.large = false});

  final IconData icon;
  final CollectStatusTone tone;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = colors.statusForeground(tone);
    final background = isDark
        ? Color.alphaBlend(
            foreground.withValues(alpha: 0.16),
            colors.surfaceRaised,
          )
        : colors.statusBackground(tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: CollectRadius.pillBorder,
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? 0.20 : 0),
        ),
      ),
      child: SizedBox.square(
        dimension: large ? 56 : 40,
        child: Icon(icon, color: foreground, size: large ? 28 : 20),
      ),
    );
  }
}
