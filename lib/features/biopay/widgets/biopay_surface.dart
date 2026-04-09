import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// BioPay scaffold — now fully unified with Tactile Monolith dark theme.
///
/// Uses [CoolScreenBackground] + [CoolSemanticColors] instead of the
/// deleted `BiopaySurfaceColors` light palette.
class BiopayLightScaffold extends StatelessWidget {
  const BiopayLightScaffold({
    required this.child,
    this.topPadding = CoolSpace.x5,
    super.key,
  });

  final Widget child;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return CoolScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            primary: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              CoolSpace.x4,
              topPadding,
              CoolSpace.x4,
              CoolSpace.x6 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class BiopayTopBar extends StatelessWidget {
  const BiopayTopBar({this.title, this.trailing, this.onBack, super.key});

  final String? title;
  final Widget? trailing;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: BiopayBackButton(onTap: onBack),
          ),
          if (title != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 64),
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.headlineSmall,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
            ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing!),
        ],
      ),
    );
  }
}

class BiopayBackButton extends StatelessWidget {
  const BiopayBackButton({this.onTap, super.key});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Material(
      color: colors.cardSurface,
      borderRadius: BorderRadius.circular(CoolRadii.sm),
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CoolRadii.sm),
            boxShadow: CoolShadows.ambientFloat(strength: 0.3),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: colors.primaryText,
          ),
        ),
      ),
    );
  }
}

class BiopaySegmentedControl extends StatelessWidget {
  const BiopaySegmentedControl({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      height: 60,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.sm),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: CoolMotion.quick,
                curve: Curves.easeOut,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? colors.cardSurfaceStrong
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.xs),
                  boxShadow: selected
                      ? CoolShadows.ambientFloat(strength: 0.4)
                      : null,
                ),
                child: Text(
                  labels[index].toUpperCase(),
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelLarge,
                    color: selected ? colors.accent : colors.secondaryText,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.2,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class BiopaySectionCard extends StatelessWidget {
  const BiopaySectionCard({required this.child, this.height, super.key});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        boxShadow: CoolShadows.ambientFloat(strength: 0.3),
      ),
      child: child,
    );
  }
}

class BiopayPrimaryButton extends StatelessWidget {
  const BiopayPrimaryButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return SizedBox(
      width: double.infinity,
      height: 88,
      child: FilledButton(
        onPressed: isLoading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.accentForeground,
          disabledBackgroundColor: colors.accent.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CoolRadii.lg),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: context.coolText.headline(
            Theme.of(context).textTheme.headlineSmall,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colors.accentForeground),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 28),
                    const SizedBox(width: CoolSpace.x3),
                  ],
                  Flexible(child: Text(label, maxLines: 1)),
                ],
              ),
      ),
    );
  }
}

class BiopayFieldLabel extends StatelessWidget {
  const BiopayFieldLabel({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return Text(
      label.toUpperCase(),
      style: context.coolText.mono(
        Theme.of(context).textTheme.labelMedium,
        color: colors.secondaryText,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.0,
      ),
    );
  }
}
