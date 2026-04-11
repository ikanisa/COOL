import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/cool_foundations.dart';
import '../widgets/biopay_surface.dart';

class BiopayEnrollmentSuccessScreen extends StatelessWidget {
  const BiopayEnrollmentSuccessScreen({this.publicId, super.key});

  final String? publicId;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final id = publicId?.trim().isNotEmpty == true ? publicId!.trim() : '--';

    return BiopayLightScaffold(
      topPadding: CoolSpace.x3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BiopayTopBar(
            onBack: () {
              if (context.canPop()) {
                context.pop();
                return;
              }
              context.go(AppRoutes.biopayHome);
            },
          ),
          const SizedBox(height: 72),
          Center(
            child: Container(
              width: 164,
              height: 164,
              decoration: BoxDecoration(
                color: colors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // No-Line Rule exception: success ring is a visual indicator,
                  // not a container boundary.
                  border: Border.all(
                    color: colors.success,
                    width: 5,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.check_rounded,
                  size: 48,
                  color: colors.success,
                ),
              ),
            ),
          ),
          const SizedBox(height: CoolSpace.x7),
          Text(
            'ENROLLMENT SUCCESS',
            textAlign: TextAlign.center,
            style: context.coolText.mono(
              Theme.of(context).textTheme.labelLarge,
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.6,
            ),
          ),
          const SizedBox(height: CoolSpace.x4),
          Text(
            'Face ID Ready',
            textAlign: TextAlign.center,
            style: context.coolText.headline(
              Theme.of(context).textTheme.displaySmall,
              color: colors.primaryText,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.8,
            ),
          ),
          const SizedBox(height: CoolSpace.x3),
          Text(
            'BioPay ID: $id',
            textAlign: TextAlign.center,
            style: context.coolText.headline(
              Theme.of(context).textTheme.headlineSmall,
              color: colors.secondaryText,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 88),
          BiopayPrimaryButton(
            label: 'Done',
            onTap: () => context.go(AppRoutes.biopayHome),
          ),
          const SizedBox(height: CoolSpace.x7),
          TextButton(
            onPressed: () => context.go(AppRoutes.profileAccount),
            child: Text(
              'Go to Profile',
              style: context.coolText.headline(
                Theme.of(context).textTheme.headlineSmall,
                color: colors.secondaryText,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
