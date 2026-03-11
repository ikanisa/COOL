import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';

/// Admin Dashboard — card grid for all admin management screens.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  static const _sections = [
    _AdminSection(
      'Users',
      '👤',
      '/admin/users',
      'Inspect profiles and demo batches',
    ),
    _AdminSection(
      'Partners',
      '🤝',
      '/admin/partners',
      'Manage partner profiles',
    ),
    _AdminSection(
      'Services',
      '📋',
      '/admin/services',
      'Partner service offerings',
    ),
    _AdminSection(
      'Quick Actions',
      '⚡',
      '/admin/quick-actions',
      'Home screen cards',
    ),
    _AdminSection(
      'Vehicle Types',
      '🚘',
      '/admin/vehicle-types',
      'Mobility filter chips',
    ),
    _AdminSection(
      'Countries',
      '🌍',
      '/admin/countries',
      'Supported country catalog',
    ),
    _AdminSection(
      'App Config',
      '⚙️',
      '/admin/app-config',
      'Key-value settings',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.text),
          onPressed: () => context.go('/profile'),
        ),
        title: Text(
          'Admin Panel',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.builder(
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
        ),
      ),
    );
  }
}

class _AdminSection {
  const _AdminSection(this.title, this.emoji, this.route, this.subtitle);
  final String title;
  final String emoji;
  final String route;
  final String subtitle;
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({required this.section});
  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        context.push(section.route);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(section.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              section.title,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              section.subtitle,
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: AppColors.text3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
