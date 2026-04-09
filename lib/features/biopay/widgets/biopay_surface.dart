import 'package:flutter/material.dart';

import '../../../core/theme/cool_foundations.dart';

abstract final class BiopaySurfaceColors {
  static const background = Color(0xFFF8FAFD);
  static const surface = Colors.white;
  static const surfaceMuted = Color(0xFFF1F5FB);
  static const surfaceStrong = Color(0xFFE6EDF7);
  static const text = Color(0xFF0D1730);
  static const mutedText = Color(0xFF8191AE);
  static const outline = Color(0xFFDCE5F2);
  static const primary = Color(0xFF1749A5);
  static const deep = Color(0xFF0B1330);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFFFC72C);
  static const purple = Color(0xFF5B3DF5);
  static const teal = Color(0xFF089981);
  static const orange = Color(0xFFFF8A00);
  static const shadow = Color(0x180D1730);
}

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
    return Scaffold(
      backgroundColor: BiopaySurfaceColors.background,
      body: DecoratedBox(
        decoration: const BoxDecoration(color: BiopaySurfaceColors.background),
        child: SafeArea(
          child: SingleChildScrollView(
            primary: false,
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: BiopaySurfaceColors.text,
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
    return Material(
      color: BiopaySurfaceColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: BiopaySurfaceColors.outline),
            boxShadow: const [
              BoxShadow(
                color: BiopaySurfaceColors.shadow,
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: BiopaySurfaceColors.text,
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
    return Container(
      height: 60,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: BiopaySurfaceColors.surfaceStrong,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: BiopaySurfaceColors.shadow,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
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
                      ? BiopaySurfaceColors.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: BiopaySurfaceColors.shadow,
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[index].toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected
                        ? BiopaySurfaceColors.primary
                        : BiopaySurfaceColors.mutedText,
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
    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(CoolSpace.x4),
      decoration: BoxDecoration(
        color: BiopaySurfaceColors.surfaceMuted,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: BiopaySurfaceColors.shadow,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
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
    this.backgroundColor = BiopaySurfaceColors.primary,
    this.foregroundColor = Colors.white,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 88,
      child: FilledButton(
        onPressed: isLoading ? null : onTap,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
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
    return Text(
      label.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: BiopaySurfaceColors.mutedText,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.0,
      ),
    );
  }
}
