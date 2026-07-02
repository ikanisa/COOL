import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/collect_colors.dart';
import '../../app/theme/collect_motion.dart';
import '../../app/theme/collect_typography.dart';
import 'public_content.dart';

export 'public_content.dart';

part 'collect_public_page.dart';
part 'collect_public_page_hero.dart';
part 'collect_public_page_infographic.dart';
part 'collect_public_page_sections.dart';
part 'collect_public_page_summary.dart';
part 'collect_home_hero.dart';
part 'collect_home_access_trust.dart';
part 'collect_home_audience_metrics.dart';
part 'collect_home_customer_action.dart';
part 'collect_home_footer.dart';
part 'collect_home_interactions.dart';
part 'collect_home_offer_sections.dart';
part 'collect_home_product_media.dart';
part 'collect_home_phone_preview.dart';
part 'collect_home_evidence_media.dart';
part 'collect_home_sections.dart';
part 'collect_landing_primitives.dart';

const _customerCtaKey = ValueKey<String>('collect-customer-action');
const _collectUssdCode = '*182*8*1*41258*2000#';
const _collectWhatsAppNumber = '250795588248';
const _collectContactEmail = 'info@ikanisa.com';

class CollectLandingPage extends StatelessWidget {
  const CollectLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: CollectColors.brandPaper,
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _LandingHero()),
            SliverToBoxAdapter(child: _AudienceConversionSection()),
            SliverToBoxAdapter(child: _AppAccessSection()),
            SliverToBoxAdapter(child: _TrustProofSection()),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: CollectColors.brandPaper,
                child: _SplitSection(
                  title: 'The rhythm gap for daily-income earners',
                  body:
                      'Income comes daily, but money systems are built for monthly cycles. Collect fits the daily rhythm: save today, insure today, repay today and build a record over time.',
                  steps: [
                    LandingStepData(
                      icon: Icons.person_outline,
                      title: 'Daily income',
                      body: 'Small, irregular earnings.',
                      color: CollectColors.brandDustyRose,
                    ),
                    LandingStepData(
                      icon: Icons.calendar_today_outlined,
                      title: 'Monthly systems',
                      body: 'High-friction files and lump-sum expectations.',
                      color: CollectColors.publicMutedGrey,
                    ),
                    LandingStepData(
                      icon: Icons.lock_outline,
                      title: 'Access denied',
                      body: 'Savings, credit and protection stay out of reach.',
                      color: CollectColors.brandDustyRose,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: CollectColors.publicWhite,
                child: _SplitSection(
                  title: 'How ibimina become verified records',
                  body:
                      'IKANISA helps trusted groups turn saving discipline into clearer records, statements and credit-readiness signals.',
                  steps: [
                    LandingStepData(
                      icon: Icons.groups_outlined,
                      title: 'Form a group',
                      body: 'Members agree on rules and savings goals.',
                      color: CollectColors.brandPeriwinkle,
                    ),
                    LandingStepData(
                      icon: Icons.savings_outlined,
                      title: 'Save daily',
                      body: 'MoMo, app or agent-backed deposits.',
                      color: CollectColors.brandMintGreen,
                    ),
                    LandingStepData(
                      icon: Icons.receipt_long_outlined,
                      title: 'Verified ledger',
                      body:
                          'Pay-ins, fund movements and decisions in real time.',
                      color: CollectColors.brandDustyRose,
                    ),
                    LandingStepData(
                      icon: Icons.query_stats_outlined,
                      title: 'Credit signals',
                      body: 'Discipline, frequency and tenure build readiness.',
                      color: CollectColors.brandPeriwinkle,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _SectionBand(
                background: CollectColors.publicMintSurface,
                child: _SplitSection(
                  title:
                      'Diaspora savings with custody records and collateral rules',
                  body:
                      'Diaspora groups save together in the host country, maintain custody records, ring-fence agreed collateral and prepare eligible members for Rwanda investment.',
                  steps: [
                    LandingStepData(
                      icon: Icons.people_alt_outlined,
                      title: 'Diaspora group',
                      body: 'Members save together in the host country.',
                      color: CollectColors.brandMintGreen,
                    ),
                    LandingStepData(
                      icon: Icons.account_balance_outlined,
                      title: 'Custody records',
                      body: 'Savings records remain clear and traceable.',
                      color: CollectColors.inkPrimary,
                    ),
                    LandingStepData(
                      icon: Icons.verified_user_outlined,
                      title: 'Collateral lock',
                      body: 'An agreed share of the pool is ring-fenced.',
                      color: CollectColors.brandMintGreen,
                    ),
                    LandingStepData(
                      icon: Icons.location_on_outlined,
                      title: 'Invest in Rwanda',
                      body: 'Property, SMEs, startups, agriculture and assets.',
                      color: CollectColors.brandMintGreen,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _InsuranceSection()),
            SliverToBoxAdapter(child: _ProductMediaSection()),
            SliverToBoxAdapter(child: _CraasSection()),
            SliverToBoxAdapter(child: _StakeholderSection()),
            SliverToBoxAdapter(child: _CustomerActionSection()),
            SliverToBoxAdapter(child: _LandingFooter()),
          ],
        ),
      ),
    );
  }
}
