import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_button.dart';

class RayonLoadingView extends StatelessWidget {
  const RayonLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 120),
      child: Center(
        child: CircularProgressIndicator(color: AppColors.rsBlueLight),
      ),
    );
  }
}

class RayonErrorView extends StatelessWidget {
  const RayonErrorView({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 8),
      child: Column(
        children: [
          Text(
            'Rayon data unavailable',
            style: GoogleFonts.barlowCondensed(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppColors.rsWhite,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 180,
            child: CoolButton(label: 'Retry', onTap: onRetry),
          ),
        ],
      ),
    );
  }
}
