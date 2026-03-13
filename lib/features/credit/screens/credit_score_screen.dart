import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/cool_screen_background.dart';
import '../../../shared/widgets/cool_toast.dart';
import '../../../shared/widgets/section_title.dart';
import '../models/credit_dashboard.dart';
import '../providers/credit_provider.dart';
import '../widgets/credit_score_detail_widgets.dart';
import '../widgets/credit_score_display_widgets.dart';

class CreditScoreScreen extends ConsumerStatefulWidget {
  const CreditScoreScreen({super.key});

  @override
  ConsumerState<CreditScoreScreen> createState() => _CreditScoreScreenState();
}

class _CreditScoreScreenState extends ConsumerState<CreditScoreScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ringController;
  late final Animation<double> _ringAnimation;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _ringAnimation = CurvedAnimation(
      parent: _ringController,
      curve: Curves.easeOutCubic,
    );
    _ringController.forward();
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(creditDashboardProvider);
    final canRefresh = ref.watch(creditDashboardProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh credit report',
            onPressed: !_isRefreshing && canRefresh ? _refreshReport : null,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
        title: Text(
          'Credit',
          style: GoogleFonts.dmSans(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.text,
          ),
        ),
      ),
      body: CoolScreenBackground(
        primaryColor: AppColors.purple,
        secondaryColor: AppColors.yellow,
        child: dashboardAsync.when(
          data: (dashboard) => _CreditScoreBody(
            dashboard: dashboard,
            ringAnimation: _ringAnimation,
          ),
          loading: () => const CreditScoreLoadingState(),
          error: (error, _) => CreditScoreErrorState(error: error.toString()),
        ),
      ),
    );
  }

  Future<void> _refreshReport() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);
    try {
      await ref.read(creditRepositoryProvider).refreshMyScore();
      ref.invalidate(creditDashboardProvider);
      if (mounted) {
        CoolToast.success(context, 'Credit report refreshed.');
      }
    } catch (error) {
      if (mounted) {
        CoolToast.error(context, 'Could not refresh report: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }
}

class _CreditScoreBody extends StatelessWidget {
  const _CreditScoreBody({
    required this.dashboard,
    required this.ringAnimation,
  });

  final CreditDashboard? dashboard;
  final Animation<double> ringAnimation;

  @override
  Widget build(BuildContext context) {
    final data = dashboard;
    final hasReport = data?.hasReport == true;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          if (!hasReport)
            const CreditInfoBanner(
              icon: Icons.credit_score_outlined,
              message: 'Score available after verified activity.',
            )
          else if (data?.lastUpdated != null)
            CreditInfoBanner(
              icon: Icons.check_circle_outline_rounded,
              message:
                  'Updated ${DateFormat('d MMM yyyy').format(data!.lastUpdated!.toLocal())}.',
            ),
          const SizedBox(height: 12),
          ScoreHeroCard(dashboard: data, animation: ringAnimation),
          const SizedBox(height: 22),
          HowToImproveCard(dashboard: data),
          const SizedBox(height: 22),
          if (hasReport) ...[
            const SectionTitle(title: 'Top factors'),
            const SizedBox(height: 10),
            ScoreFactors(
              factors: (data?.factors ?? const [])
                  .take(3)
                  .toList(growable: false),
            ),
            const SizedBox(height: 22),
            const SectionTitle(title: 'Report details'),
            const SizedBox(height: 10),
            ScoreExplanationCard(dashboard: data),
            const SizedBox(height: 22),
          ],
          const SectionTitle(title: 'Readiness'),
          const SizedBox(height: 10),
          ApplicationReadinessEntryCard(dashboard: data),
          if (hasReport && (data?.history.isNotEmpty ?? false)) ...[
            const SizedBox(height: 22),
            const SectionTitle(title: 'History'),
            const SizedBox(height: 10),
            ScoreHistoryChart(history: data?.history ?? const []),
          ],
        ],
      ),
    );
  }
}
