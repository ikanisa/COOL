import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/cool_palette.dart';
import '../../../shared/widgets/cool_card.dart';
import '../../../shared/widgets/cool_screen_background.dart';

/// Admin Dashboard — card grid for all admin management screens.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  static const _sections = [
    _AdminSection(
      'Users',
      Icons.person_rounded,
      '/admin/users',
      'Inspect profiles and demo batches',
    ),
    _AdminSection(
      'Partners',
      Icons.handshake_rounded,
      '/admin/partners',
      'Manage partner profiles',
    ),
    _AdminSection(
      'Services',
      Icons.assignment_rounded,
      '/admin/services',
      'Partner service offerings',
    ),
    _AdminSection(
      'Quick Actions',
      Icons.bolt_rounded,
      '/admin/quick-actions',
      'Home screen cards',
    ),
    _AdminSection(
      'Vehicle Types',
      Icons.directions_car_filled_rounded,
      '/admin/vehicle-types',
      'Mobility filter chips',
    ),
    _AdminSection(
      'App Config',
      Icons.settings_rounded,
      '/admin/app-config',
      'Key-value settings',
    ),
    _AdminSection(
      'Operations',
      Icons.monitor_heart_rounded,
      '/admin/operations',
      'Release health and triage',
    ),
    _AdminSection(
      'Rayon Sports',
      Icons.sports_soccer_rounded,
      '/admin/rayon',
      'Matches, tickets, shop, members',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.coolPalette;
    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Semantics(
          button: true,
          label: 'Back to profile',
          child: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: palette.text),
            onPressed: () => context.go('/profile'),
          ),
        ),
      ),
      body: CoolScreenBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
            children: [
              Text(
                'Admin Panel',
                style: GoogleFonts.dmSans(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: palette.text,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 24),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.2,
                ),
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  return _AdminCard(section: section);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSection {
  const _AdminSection(this.title, this.icon, this.route, this.subtitle);
  final String title;
  final IconData icon;
  final String route;
  final String subtitle;
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.section});
  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return CoolCard(
      padding: const EdgeInsets.all(16),
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      semanticsLabel: '${section.title}. ${section.subtitle}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(section.icon, size: 28, color: palette.text2),
          const SizedBox(height: 8),
          Text(
            section.title,
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            section.subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: palette.text3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
