import 'package:collect_app/app/router.dart';
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/core/utils/money_format.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark Collect color tokens resolve', () {
    final light = AppTheme.light().extension<CollectColors>();
    final dark = AppTheme.dark().extension<CollectColors>();

    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.surface.computeLuminance(), greaterThan(0.2));
    expect(dark!.surface.computeLuminance(), lessThan(0.2));
  });

  test('RWF amount typography uses tabular numerals', () {
    final style = CollectTypography.amountHero(CollectColors.light.textPrimary);

    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('button, card, and status chip expose labels', (tester) async {
    await _pumpCollect(
      tester,
      CollectCard(
        child: Column(
          children: [
            CollectButton(label: 'Continue safely', onPressed: () {}),
            const CollectStatusChip(
              label: 'Needs review',
              tone: CollectStatusTone.warning,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Continue safely'), findsOneWidget);
    expect(find.text('Needs review'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(CollectStatusChip)),
      matchesSemantics(label: 'Status: Needs review'),
    );
  });

  testWidgets('payment status card carries SMS trust-boundary copy', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const PaymentIntentStatusCard(
        amountRwf: 5000,
        receiverLabel: 'St Michel treasury',
        receiverMomoNumber: '+250788123456',
        status: 'pending',
      ),
    );

    expect(find.text('RWF 5,000'), findsOneWidget);
    expect(find.text('St Michel treasury'), findsOneWidget);
    expect(find.text('Payment intent'), findsNothing);
    expect(find.text('Intent'), findsNothing);
    expect(find.text('SMS verification'), findsOneWidget);
    expect(find.text('Recorded'), findsNothing);
    expect(find.textContaining('receiver-side MoMo SMS'), findsOneWidget);
    expect(find.textContaining('Do not paste SMS'), findsOneWidget);
    expect(find.textContaining('Code'), findsNothing);
  });

  testWidgets('amount hero scales large RWF values in narrow cards', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 220,
        child: AmountHero(
          amount: 12500000,
          label: 'Confirmed total',
          detail: 'SMS verified',
        ),
      ),
    );

    expect(find.text('RWF 12,500,000'), findsOneWidget);
    expect(find.text('SMS verified'), findsOneWidget);
  });

  testWidgets('payment pipeline exposes semantic progress state', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const PaymentPipelineIndicator(status: 'pending'),
      );

      expect(
        find.bySemanticsLabel('Payment progress: Pending'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Start step complete'), findsOneWidget);
      expect(find.bySemanticsLabel('Check step current'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('QR card sizes link surface for narrow mobile widths', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 280,
        child: QRCard(
          link:
              'https://collect.example/c/st-michel-medical-support-private-link',
          caption: 'Share this private group link.',
        ),
      ),
    );

    expect(find.text('Share this private group link.'), findsOneWidget);
    expect(find.textContaining('collect.example'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('receiver consent card shows SMS access privacy copy', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      ReceiverConsentCard(
        flagsEnabled: true,
        consented: false,
        isSyncing: false,
        onConsentChanged: (_) {},
        onSync: () {},
      ),
    );

    expect(find.text('Consent'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Sync'), findsOneWidget);
    expect(find.textContaining('Raw SMS is never public'), findsOneWidget);
    expect(find.textContaining('MoMo confirmation matching'), findsOneWidget);
  });

  testWidgets('ledger row renders tabular transaction details', (tester) async {
    await _pumpCollect(
      tester,
      LedgerRow.confirmed(
        contribution: Contribution(
          id: 'con-1',
          collectionId: 'col-1',
          amountRwf: 15000,
          supporterLabel: 'Collect ID 038491',
          createdAt: DateTime(2026),
          transactionId: 'MTN-001',
        ),
      ),
    );

    expect(find.text('#038491'), findsOneWidget);
    expect(find.text('RWF 15,000'), findsOneWidget);
    expect(find.text('MTN-001'), findsOneWidget);
  });

  testWidgets('empty, error, and loading states render', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const Column(
          children: [
            Expanded(
              child: CollectEmptyState(
                icon: CollectIcons.collections,
                title: 'No groups yet',
                message: 'Create an SMS-first MoMo group.',
              ),
            ),
            Expanded(
              child: CollectErrorState(
                title: 'Could not load',
                message: 'Try again when the connection is stable.',
              ),
            ),
            LoadingSkeleton(lines: 2, semanticsLabel: 'Loading dashboard'),
          ],
        ),
      );

      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Could not load'), findsOneWidget);
      expect(find.byType(LoadingSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('Loading dashboard'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('loading state panel exposes visible and semantic context', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SizedBox(
          width: 360,
          child: LoadingStatePanel(
            title: 'Loading members',
            message: 'Fetching group members and Collect ID roles.',
            icon: CollectIcons.people,
            lines: 2,
          ),
        ),
      );

      expect(find.text('Loading members'), findsOneWidget);
      expect(
        find.text('Fetching group members and Collect ID roles.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Loading: Loading members')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('bento metrics adapt for text scaling without losing content', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(340, 720),
          textScaler: TextScaler.linear(1.3),
        ),
        child: SizedBox(
          width: 340,
          child: CollectBentoGrid(
            primary: BentoMetricCell(
              label: 'Total confirmed support',
              value: 'RWF 1,250,000',
              detail: 'Confirmed by SMS',
              emphasis: true,
            ),
            top: BentoMetricCell(
              label: 'Groups',
              value: '12',
              detail: 'Active',
            ),
            bottom: BentoMetricCell(
              label: 'Payments',
              value: '3',
              detail: 'Need SMS',
            ),
          ),
        ),
      ),
    );

    expect(find.text('Total confirmed support'), findsOneWidget);
    expect(find.text('RWF 1,250,000'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
  });

  testWidgets('quick action rail exposes stable premium action semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        QuickActionRail(
          children: [
            QuickActionButton(
              icon: CollectIcons.add,
              label: 'Create',
              detail: 'Android owner',
              onTap: () {},
            ),
            QuickActionButton(
              icon: CollectIcons.collections,
              label: 'Groups',
              detail: '12 active',
              onTap: () {},
            ),
          ],
        ),
      );

      expect(find.bySemanticsLabel('Quick actions'), findsOneWidget);
      expect(find.bySemanticsLabel('Create, Android owner'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('segmented filter exposes premium horizontal controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var selected = 'All';
    try {
      await _pumpCollect(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            return PremiumSegmentedFilter<String>(
              values: const ['All', 'Confirmed', 'Pending', 'Needs review'],
              selected: selected,
              labelFor: (value) => value,
              onChanged: (value) => setState(() => selected = value),
            );
          },
        ),
      );

      expect(find.bySemanticsLabel('Filter options'), findsOneWidget);
      await tester.tap(find.text('Pending'));
      await tester.pump();
      expect(selected, 'Pending');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('premium scaffold pins bottom action surface', (tester) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        height: 520,
        child: PremiumScaffold(
          title: 'Contribute',
          bottomAction: BottomActionSurface(
            children: [CollectButton(label: 'Review contribution')],
          ),
          children: [
            AmountHero(
              amount: 5000,
              label: 'Amount',
              detail: 'SMS verified after MoMo confirmation.',
            ),
            InfoSecurityBanner(
              title: 'Target account',
              message: 'Receiver details are checked before handoff.',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Review contribution'), findsOneWidget);
    expect(find.text('Target account'), findsOneWidget);
  });

  testWidgets('form section card standardizes fields errors and actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      FormSectionCard(
        title: 'Group profile',
        message: 'Members see the group name and public link.',
        errorTitle: 'Create failed',
        errorMessage: 'Name required.',
        actions: [CollectButton(label: 'Create group', onPressed: () {})],
        children: const [
          TextField(decoration: InputDecoration(labelText: 'Group name')),
        ],
      ),
    );

    expect(find.text('Group profile'), findsOneWidget);
    expect(
      find.text('Members see the group name and public link.'),
      findsOneWidget,
    );
    expect(find.text('Group name'), findsOneWidget);
    expect(find.text('Create failed'), findsOneWidget);
    expect(find.text('Name required.'), findsOneWidget);
    expect(find.text('Create group'), findsOneWidget);
  });

  testWidgets('list tile separates static information from actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      Column(
        children: [
          const CollectListTile(
            leading: CollectIcons.info,
            title: 'SMS matching',
            subtitle:
                'Receiver-side MoMo confirmations update the ledger without exposing raw SMS bodies publicly.',
          ),
          CollectListTile(
            leading: CollectIcons.profile,
            title: 'Profile',
            subtitle: 'Open setup.',
            onTap: () {},
          ),
        ],
      ),
    );

    expect(find.byIcon(CollectIcons.chevron), findsOneWidget);
    expect(find.text('SMS matching'), findsOneWidget);
    expect(
      find.textContaining('without exposing raw SMS bodies'),
      findsOneWidget,
    );
  });

  testWidgets('screen header preserves long titles and wraps tight actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 320,
        child: ScreenHeader(
          title: 'Collect verified support for St Michel medical group',
          subtitle: 'SMS-first MoMo evidence and private group links.',
          actions: [
            IconButton(onPressed: null, icon: Icon(CollectIcons.share)),
            IconButton(onPressed: null, icon: Icon(CollectIcons.copy)),
          ],
        ),
      ),
    );

    expect(
      find.text('Collect verified support for St Michel medical group'),
      findsOneWidget,
    );
    expect(find.textContaining('SMS-first MoMo'), findsOneWidget);
    expect(find.byIcon(CollectIcons.share), findsOneWidget);
    expect(find.byIcon(CollectIcons.copy), findsOneWidget);
  });

  test('primary route smoke list keeps admin out of member app', () {
    expect(
      collectRoutePaths,
      containsAll(<String>[
        '/home',
        '/groups/:collectionId/contribute',
        '/groups/:collectionId/pay/:intentId',
        '/dev/design-system',
      ]),
    );
    expect(collectRoutePaths, isNot(contains('/admin')));
  });
}

Future<void> _pumpCollect(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}
