import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_button.dart';
import '../../../shared/widgets/cool_card.dart';
import '../providers/mobility_location_provider.dart';
import '../../../core/l10n/l10n.dart';

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
    final palette = context.coolPalette;
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
                  _RouteDot(color: palette.accent),
                  const SizedBox(width: 8),
                  const _RouteDash(axis: Axis.horizontal),
                  const SizedBox(width: 8),
                  _RouteDot(color: palette.orange),
                ],
              ),
              const SizedBox(height: 12),
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
                  _RouteDot(color: palette.accent),
                  const _RouteDash(),
                  _RouteDot(color: palette.orange),
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

// ── Internal helpers ──────────────────────────────────────────────

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
    final palette = context.coolPalette;
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
                color: palette.text3,
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
              color: palette.text3,
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
    final palette = context.coolPalette;
    final suffixIcons = <Widget>[
      if (onUseCurrentLocationTap != null)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: isResolvingCurrentLocation
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CupertinoActivityIndicator(radius: 9),
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
          padding: const EdgeInsets.only(left: 6, right: 4),
          child: Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: palette.accent,
          ),
        ),
    ];

    return TextFormField(
      controller: controller,
      validator: validator,
      textInputAction: textInputAction,
      style: GoogleFonts.dmSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: palette.text,
      ),
      cursorColor: palette.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: palette.text3,
        ),
        filled: true,
        fillColor: palette.surface3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        suffixIcon: suffixIcons.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: suffixIcons,
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.red, width: 1.2),
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
    final palette = context.coolPalette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: palette.text2),
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
    final palette = context.coolPalette;
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            highlighted ? Icons.check_circle_rounded : Icons.place_outlined,
            size: 14,
            color: highlighted ? palette.accent : palette.text3,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: highlighted ? palette.accent : palette.text2,
                height: 1.35,
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
    final palette = context.coolPalette;
    late final IconData icon;
    late final String title;
    late final String subtitle;
    String? actionLabel;
    VoidCallback? action;

    switch (locationState.status) {
      case MobilityLocationStatus.ready:
      case MobilityLocationStatus.approximateReady:
        icon = Icons.pin_drop_rounded;
        title = 'Current location is ready';
        subtitle = locationState.isApproximate
            ? 'Fill pickup field'
            : 'Bias place search';
        break;
      case MobilityLocationStatus.checking:
      case MobilityLocationStatus.requesting:
      case MobilityLocationStatus.idle:
        icon = Icons.satellite_alt_rounded;
        title = 'Checking current location';
        subtitle =
            'Location fix available';
        break;
      case MobilityLocationStatus.accessDisabled:
        icon = Icons.admin_panel_settings_outlined;
        title = 'Location is off in COOL';
        subtitle =
            'Enable in Profile';
        actionLabel = 'Enable Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.needsPermission:
      case MobilityLocationStatus.denied:
        icon = Icons.pin_drop_rounded;
        title = 'Allow location';
        subtitle =
            'Text-only mode available';
        actionLabel = 'Allow Location';
        action = onEnableLocation;
        break;
      case MobilityLocationStatus.deniedForever:
        icon = Icons.settings_rounded;
        title = 'Location access is blocked';
        subtitle =
            'Open settings to allow';
        actionLabel = 'Open Settings';
        action = onOpenAppSettings;
        break;
      case MobilityLocationStatus.serviceDisabled:
        icon = Icons.satellite_alt_rounded;
        title = 'Turn on device location';
        subtitle =
            'Location services off';
        actionLabel = 'Turn On Location';
        action = onOpenLocationSettings;
        break;
      case MobilityLocationStatus.error:
        icon = Icons.warning_amber_rounded;
        title = 'Location could not be attached';
        subtitle =
            locationState.error ??
            'Pickup location unavailable';
        actionLabel = 'Try Again';
        action = onEnableLocation;
        break;
    }

    return CoolCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: palette.text2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: palette.text2,
                    height: 1.4,
                  ),
                ),
                if (actionLabel != null && action != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 160,
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