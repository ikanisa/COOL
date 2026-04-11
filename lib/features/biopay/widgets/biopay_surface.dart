import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Shared BioPay scaffold built on the app-wide minimalist system.
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
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
      ),
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
                padding: const EdgeInsets.symmetric(horizontal: 72),
                child: Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.coolText.headline(
                    Theme.of(context).textTheme.titleLarge,
                    color: colors.primaryText,
                    fontWeight: FontWeight.w600,
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colors.cardSurfaceStrong,
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
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
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.border),
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
                      ? colors.chipSelectedBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(CoolRadii.xs),
                ),
                child: Text(
                  labels[index],
                  style: context.coolText.mobiLabel(
                    color: selected ? colors.primaryText : colors.secondaryText,
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
      constraints: height == null ? null : BoxConstraints(minHeight: height!),
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.border),
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(CoolRadii.pill),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                colors.accentStrong.withValues(alpha: 0.96),
                colors.accent,
              ],
            ),
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            boxShadow: onTap != null
                ? CoolShadows.primary(strength: 0.55)
                : null,
          ),
          child: InkWell(
            onTap: isLoading ? null : onTap,
            borderRadius: BorderRadius.circular(CoolRadii.pill),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colors.accentForeground,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 28, color: colors.accentForeground),
                          const SizedBox(width: CoolSpace.x3),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            style: context.coolText.headline(
                              Theme.of(context).textTheme.headlineSmall,
                              color: colors.accentForeground,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
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
