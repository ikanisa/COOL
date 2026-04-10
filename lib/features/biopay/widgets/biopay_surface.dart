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
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: CoolSpace.x2),
      decoration: BoxDecoration(
        color: colors.glassSurface,
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.glassSurface.withValues(alpha: 0.96),
            colors.cardSurface.withValues(alpha: 0.88),
          ],
        ),
        boxShadow: CoolShadows.glass(strength: 0.42),
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
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(CoolRadii.md),
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(CoolRadii.md),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: colors.glassSurface,
            borderRadius: BorderRadius.circular(CoolRadii.md),
            border: Border.all(
              color: colors.borderStrong,
            ),
            boxShadow: CoolShadows.glass(strength: 0.24),
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
        color: colors.glassSurface,
        borderRadius: BorderRadius.circular(CoolRadii.md),
        border: Border.all(color: colors.borderStrong),
        boxShadow: CoolShadows.glass(strength: 0.22),
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
                  color: selected ? colors.accent : Colors.transparent,
                  gradient: selected
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            colors.accentStrong.withValues(alpha: 0.94),
                            colors.accent,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(CoolRadii.xs),
                  boxShadow: selected
                      ? CoolShadows.primary(strength: 0.28)
                      : null,
                ),
                child: Text(
                  labels[index].toUpperCase(),
                  style: context.coolText.mono(
                    Theme.of(context).textTheme.labelLarge,
                    color: selected
                        ? colors.accentForeground
                        : colors.secondaryText,
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
      constraints: height == null ? null : BoxConstraints(minHeight: height!),
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.glassSurface.withValues(alpha: 0.74),
            colors.cardSurface,
          ],
        ),
        borderRadius: BorderRadius.circular(CoolRadii.lg),
        border: Border.all(color: colors.borderStrong),
        boxShadow: CoolShadows.glass(strength: 0.26),
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
