import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/cool_foundations.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/mobility_location_provider.dart';

/// Combined pickup / destination text-field editor with route dots.
class ScheduleTripRouteEditor extends StatelessWidget {
  const ScheduleTripRouteEditor({
    required this.fromController,
    required this.toController,
    required this.fromHint,
    required this.toHint,
    required this.fromValidator,
    required this.toValidator,
    required this.fromHintText,
    required this.toHintText,
    this.onFromSearchTap,
    this.onToSearchTap,
    this.onUseCurrentLocationTap,
    this.isResolvingCurrentLocation = false,
    this.fromResolved = false,
    this.toResolved = false,
    super.key,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final String fromHint;
  final String toHint;
  final String? Function(String?) fromValidator;
  final String? Function(String?) toValidator;
  final String fromHintText;
  final String toHintText;
  final VoidCallback? onFromSearchTap;
  final VoidCallback? onToSearchTap;
  final VoidCallback? onUseCurrentLocationTap;
  final bool isResolvingCurrentLocation;
  final bool fromResolved;
  final bool toResolved;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final fields = Column(
      children: [
        _RouteField(
          controller: fromController,
          hint: fromHint,
          onSearchTap: onFromSearchTap,
          onUseCurrentLocationTap: onUseCurrentLocationTap,
          isResolvingCurrentLocation: isResolvingCurrentLocation,
          isResolved: fromResolved,
          validator: fromValidator,
        ),
        const SizedBox(height: 6),
        _RouteResolutionHint(text: fromHintText, highlighted: fromResolved),
        const SizedBox(height: 10),
        _RouteField(
          controller: toController,
          hint: toHint,
          textInputAction: TextInputAction.done,
          onSearchTap: onToSearchTap,
          isResolved: toResolved,
          validator: toValidator,
        ),
        const SizedBox(height: 6),
        _RouteResolutionHint(text: toHintText, highlighted: toResolved),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RouteDot(color: colors.accent),
                  const SizedBox(width: 8),
                  const _RouteDash(axis: Axis.horizontal),
                  const SizedBox(width: 8),
                  _RouteDot(color: colors.warning),
                ],
              ),
              const SizedBox(height: CoolSpace.x3),
              fields,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Column(
                children: [
                  _RouteDot(color: colors.accent),
                  const _RouteDash(),
                  _RouteDot(color: colors.warning),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: fields),
          ],
        );
      },
    );
  }
}

class _RouteDot extends StatelessWidget {
  const _RouteDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _RouteDash extends StatelessWidget {
  const _RouteDash({this.axis = Axis.vertical});

  final Axis axis;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    if (axis == Axis.horizontal) {
      return SizedBox(
        width: 44,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List<Widget>.generate(
            5,
            (_) => Container(
              width: 4,
              height: 2,
              decoration: BoxDecoration(
                color: colors.tertiaryText,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List<Widget>.generate(
          5,
          (_) => Container(
            width: 2,
            height: 4,
            decoration: BoxDecoration(
              color: colors.tertiaryText,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteField extends StatelessWidget {
  const _RouteField({
    required this.controller,
    required this.hint,
    required this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSearchTap,
    this.onUseCurrentLocationTap,
    this.isResolvingCurrentLocation = false,
    this.isResolved = false,
  });

  final TextEditingController controller;
  final String hint;
  final String? Function(String?) validator;
  final TextInputAction textInputAction;
  final VoidCallback? onSearchTap;
  final VoidCallback? onUseCurrentLocationTap;
  final bool isResolvingCurrentLocation;
  final bool isResolved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    final suffixIcons = <Widget>[
      if (onUseCurrentLocationTap != null)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: isResolvingCurrentLocation
              ? const SizedBox(
                  width: CoolTapTargets.minimum,
                  height: CoolTapTargets.minimum,
                  child: Center(child: CupertinoActivityIndicator(radius: 9)),
                )
              : _RouteActionIcon(
                  icon: Icons.my_location_rounded,
                  tooltip: context.l10n.useCurrentLocation,
                  onTap: onUseCurrentLocationTap!,
                ),
        ),
      if (onSearchTap != null)
        _RouteActionIcon(
          icon: Icons.search_rounded,
          tooltip: context.l10n.searchPlaces,
          onTap: onSearchTap!,
        ),
      if (isResolved)
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 2),
          child: Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: colors.accent,
          ),
        ),
    ];

    return TextFormField(
      controller: controller,
      validator: validator,
      textInputAction: textInputAction,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: colors.primaryText,
        fontWeight: FontWeight.w700,
      ),
      cursorColor: colors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: colors.tertiaryText,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: colors.inputSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: suffixIcons.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: suffixIcons,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          borderSide: BorderSide(color: colors.accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          borderSide: BorderSide(color: colors.danger, width: 1.2),
        ),
      ),
    );
  }
}

class _RouteActionIcon extends StatelessWidget {
  const _RouteActionIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 20, color: colors.secondaryText),
      constraints: const BoxConstraints.tightFor(
        width: CoolTapTargets.minimum,
        height: CoolTapTargets.minimum,
      ),
      style: IconButton.styleFrom(
        backgroundColor: colors.chipBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CoolRadii.md),
          side: BorderSide(color: colors.border),
        ),
      ),
    );
  }
}

class _RouteResolutionHint extends StatelessWidget {
  const _RouteResolutionHint({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            highlighted ? Icons.check_circle_rounded : Icons.place_outlined,
            size: 14,
            color: highlighted ? colors.accent : colors.tertiaryText,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: highlighted ? colors.primaryText : colors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Location attachment status card shown below the route editor.
class ScheduleTripLocationAttachmentCard extends StatelessWidget {
  const ScheduleTripLocationAttachmentCard({
    required this.locationState,
    required this.onEnableLocation,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    super.key,
  });

  final MobilityLocationState locationState;
  final VoidCallback onEnableLocation;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.coolSemanticColors;
    late final IconData icon;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        icon = Icons.pin_drop_rounded;
        title = 'Location ready';
        subtitle = locationState.isApproximate
            ? 'Fill pickup field.'
            : 'Biasing place search.';
        break;
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        icon = Icons.satellite_alt_rounded;
        title = 'Checking location';
        subtitle = 'Trip posting still works.';
        break;
      case MobilityLocationStatus.accessDisabled:
        icon = Icons.admin_panel_settings_outlined;
        title = 'Location off';
        subtitle = 'Turn it on in Profile.';
        actionLabel = 'Enable Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        icon = Icons.pin_drop_rounded;
        title = 'Allow location';
        subtitle = 'Text-only entry works.';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location blocked';
        subtitle = 'Open settings to allow.';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.satellite_alt_rounded;
        title = 'Turn on location';
        subtitle = 'Device services are off.';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.error:
        icon = Icons.warning_amber_rounded;
        title = 'Location unavailable';
        subtitle = locationState.error ?? 'Use text route entry.';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return CoolCard(
      backgroundColor: colors.proximitySurface,
      borderColor: colors.borderStrong,
      useGradient: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colors.secondaryText),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colors.primaryText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.secondaryText,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && action != null) ...[
                  const SizedBox(height: CoolSpace.x3),
                  SizedBox(
                    width: 168,
                    child: CoolButton(
                      label: actionLabel,
                      variant: CoolButtonVariant.secondary,
                      onTap: action,
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
