part of 'runtime_component_contract_test.dart';

void _registerRuntimeComponentInteractions() {
  testWidgets('brand mark renders the official Collect image asset', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(tester, const CollectBrandMark());

      expect(find.bySemanticsLabel('Collect logo'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Collect'), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        CollectRuntimeAssets.officialLogo,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('brand mark supports inverse text on immersive surfaces', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const CollectBrandMark(
        framed: false,
        foregroundColor: CollectColors.publicWhite,
      ),
    );

    expect(
      tester.widget<Text>(find.text('Collect')).style?.color,
      CollectColors.publicWhite,
    );
  });

  testWidgets('brand mark preserves its wordmark at accessibility text scale', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const MediaQuery(
        data: MediaQueryData(
          size: Size(1024, 1366),
          textScaler: TextScaler.linear(2),
        ),
        child: CollectBrandMark(
          compact: true,
          framed: false,
          foregroundColor: CollectColors.publicWhite,
        ),
      ),
    );

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('Collect'),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  test('secondary color system protects readable semantic roles', () {
    final light = AppTheme.light().extension<CollectColors>()!;

    expect(light.actionColor, CollectColors.publicBlack);
    expect(light.urgentAction, light.dangerForeground);
    expect(light.onAccent, CollectColors.publicWhite);
    expect(light.selectedOnAccent, CollectColors.publicWhite);
    expect(light.surfaceReadable, CollectColors.publicWhite);
    expect(light.surfaceRaised, const Color(0xFFF0F0F2));
    expect(light.surfaceMuted, const Color(0xFFE8E8EB));
    expect(light.borderSoft, const Color(0xFFE1E1E4));
    expect(light.borderAccent, const Color(0xFFB8B8BE));
    expect(light.focusRing, CollectColors.publicBlack);
    expect(light.info, CollectColors.semanticInfoForeground);
    expect(light.success, CollectColors.semanticSuccessForeground);
    expect(light.warning, CollectColors.semanticWarningForeground);
    expect(light.danger, CollectColors.semanticDangerForeground);
    expect(light.statusForeground(CollectStatusTone.info), light.info);
    expect(light.statusForeground(CollectStatusTone.success), light.success);
    expect(light.statusForeground(CollectStatusTone.warning), light.warning);
    expect(light.statusForeground(CollectStatusTone.danger), light.danger);
    expect(light.statusBackground(CollectStatusTone.info), light.infoContainer);
    expect(
      light.statusBackground(CollectStatusTone.success),
      light.successContainer,
    );
    expect(
      light.statusBackground(CollectStatusTone.warning),
      light.warningContainer,
    );
    expect(
      light.statusBackground(CollectStatusTone.danger),
      light.dangerContainer,
    );
    expect(
      <Color>{
        light.info,
        light.success,
        light.warning,
        light.danger,
      }.intersection(CollectColors.groupAccentColors.toSet()),
      isEmpty,
    );

    for (final color in <Color>[
      light.textPrimary,
      light.textSecondary,
      light.textMuted,
      light.info,
      light.success,
      light.warning,
      light.danger,
    ]) {
      expect(_contrastRatio(color, light.surfaceReadable), greaterThan(4.5));
    }
    expect(_contrastRatio(light.onAccent, light.actionColor), greaterThan(4.5));
  });

  test('RWF amount typography uses tabular numerals', () {
    final style = CollectTypography.amountHero(CollectColors.light.textPrimary);

    expect(formatRwf(1250000), 'RWF 1,250,000');
    expect(style.fontFamily, 'Inter');
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
          detail: 'Statement reconciled',
        ),
      ),
    );

    expect(find.text('RWF 12,500,000'), findsOneWidget);
    expect(find.text('Statement reconciled'), findsOneWidget);
  });

  testWidgets('Collect ID card renders identity without hash prefix', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(width: 280, child: CollectIdCard(publicId: '038491')),
    );

    expect(find.byIcon(CollectIcons.profile), findsOneWidget);
    expect(find.text('038491'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
  });

  testWidgets('ledger row renders tabular transaction details', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        LedgerRow.confirmed(
          contribution: Contribution(
            id: 'con-1',
            collectionId: 'col-1',
            amountRwf: 15000,
            supporterLabel: 'Collect ID 038491',
            createdAt: DateTime(2026),
            transactionId: 'MOMO-001',
            currency: 'RWF',
          ),
        ),
      );

      expect(find.text('038491'), findsOneWidget);
      expect(find.text('RWF 15,000'), findsOneWidget);
      expect(find.text('Ref MOMO-001'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Transaction reference MOMO-001')),
        findsWidgets,
      );
    } finally {
      semantics.dispose();
    }
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
                message: 'Create a group for Rwanda MoMo contributions.',
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

  testWidgets('shape-specific Collect skeletons expose stable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SingleChildScrollView(
          child: Column(
            children: [
              LoadingSkeleton.heroAmount(semanticsLabel: 'Loading amount card'),
              CollectSpacing.gap12,
              LoadingSkeleton.groupCard(semanticsLabel: 'Loading group card'),
              CollectSpacing.gap12,
              LoadingSkeleton.ledgerRow(semanticsLabel: 'Loading ledger row'),
              CollectSpacing.gap12,
              LoadingSkeleton.bottomSheet(
                semanticsLabel: 'Loading action sheet',
              ),
            ],
          ),
        ),
      );

      expect(find.bySemanticsLabel('Loading amount card'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading group card'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading ledger row'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading action sheet'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Collect async state view renders loading error retry and data', (
    tester,
  ) async {
    var retryCount = 0;

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: const AsyncLoading<int>(),
        data: (context, value) => Text('$value loaded'),
        loadingTitle: 'Loading members',
        loadingMessage: 'Fetching group members.',
      ),
    );
    expect(find.text('Loading members'), findsOneWidget);

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: AsyncError<int>(StateError('private failure'), StackTrace.empty),
        data: (context, value) => Text('$value loaded'),
        errorTitle: 'Could not load members',
        errorMessage: 'Try again when the connection is stable.',
        onRetry: () => retryCount += 1,
      ),
    );
    expect(find.text('Could not load members'), findsOneWidget);
    expect(find.text('private failure'), findsNothing);
    await tester.tap(find.text('Try again'));
    expect(retryCount, 1);

    await _pumpCollect(
      tester,
      CollectAsyncStateView<int>(
        value: const AsyncData<int>(7),
        data: (context, value) => Text('$value loaded'),
      ),
    );
    expect(find.text('7 loaded'), findsOneWidget);
  });

  testWidgets('permission education sheet explains the native prompt', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const CollectPermissionEducationSheet(
        icon: CollectIcons.qr,
        title: 'Camera access',
        message: 'Use native phone settings.',
        education: 'Camera access lets Collect scan group QR codes.',
      ),
    );

    expect(find.text('Camera access'), findsOneWidget);
    expect(find.text('Before you continue'), findsNothing);
    expect(
      find.text('Camera access lets Collect scan group QR codes.'),
      findsOneWidget,
    );
  });

  testWidgets('notification denial stays in Collect and retry can recover', (
    tester,
  ) async {
    final service = _PermissionSequenceNotificationService([false, true]);
    final container = ProviderContainer(
      overrides: [
        collectNotificationServiceProvider.overrideWithValue(service),
        collectRepositoryProvider.overrideWith(
          (ref) => FixtureCollectRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                return TextButton(
                  onPressed: () => showNotificationSettingsSheet(context, ref),
                  child: const Text('Review permission'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Review permission'));
    await tester.pumpAndSettle();
    expect(find.text('Enable'), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(
      container.read(notificationPermissionStatusProvider),
      CollectDevicePermissionStatus.denied,
    );

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsNothing);
    expect(
      container.read(notificationPermissionStatusProvider),
      CollectDevicePermissionStatus.granted,
    );
    expect(service.requestCalls, 2);
    expect(service.registrationCalls, 1);
    expect(service.notificationCalls, 0);
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

  testWidgets('bento metrics can render icon-first metadata', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpCollect(
        tester,
        const SizedBox(
          width: 320,
          child: BentoMetricCell(
            label: 'Supporters',
            value: '42',
            detail: 'Visible groups',
            icon: CollectIcons.people,
            iconOnly: true,
            semanticLabel: '42 group members',
          ),
        ),
      );

      expect(find.byIcon(CollectIcons.people), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('Supporters'), findsNothing);
      expect(find.text('Visible groups'), findsNothing);
      expect(find.bySemanticsLabel('42 group members'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  test('group metadata copy blockers are enforced by source contract', () {
    final semanticIcons = File(
      'lib/app/theme/collect_semantic_icons.dart',
    ).readAsStringSync();
    final groupCards = File(
      'lib/shared/widgets/collect_group_cards.dart',
    ).readAsStringSync();
    final collectionCards =
        groupCards +
        File(
          'lib/shared/widgets/collect_group_card_media.dart',
        ).readAsStringSync() +
        File(
          'lib/shared/widgets/collect_group_card_metrics.dart',
        ).readAsStringSync();
    final collectionsScreen = File(
      'lib/features/collections/collections_screen.dart',
    ).readAsStringSync();
    final manageScreen = File(
      'lib/features/collections/collection_manage_screen.dart',
    ).readAsStringSync();
    final detailScreen = File(
      'lib/features/collections/collection_detail_screen.dart',
    ).readAsStringSync();
    final detailActions = detailScreen;
    final detailHero = detailScreen;
    final shareScreen = File(
      'lib/features/collections/share_screen.dart',
    ).readAsStringSync();
    final scaffoldChrome = File(
      'lib/shared/widgets/collect_scaffold_chrome.dart',
    ).readAsStringSync();
    final runtimeSources = [
      groupCards,
      collectionCards,
      collectionsScreen,
      manageScreen,
      detailActions,
      detailHero,
      shareScreen,
      scaffoldChrome,
    ];

    const requiredKeywords = [
      'support',
      'supporters',
      'members',
      'amount',
      'church',
      'football',
      'public',
      'private',
      'sport',
      'ikimina',
      'wedding',
      'bank',
      'beneficiary',
      'qr',
      'owner',
      'visibility',
    ];
    for (final keyword in requiredKeywords) {
      expect(semanticIcons, contains("'$keyword':"));
    }

    // The owner's photographic card comparator replaces the old one-line,
    // icon-only header; the full name and category remain visible.
    final editorialCards = File(
      'lib/shared/widgets/collect_group_card_editorial.dart',
    ).readAsStringSync();
    final editorialDetails = File(
      'lib/shared/widgets/collect_group_card_metrics.dart',
    ).readAsStringSync();
    expect(editorialCards, contains('collection.collectionType.label'));
    expect(editorialDetails, contains('collection.title'));
    expect(editorialDetails, isNot(contains('TextOverflow.ellipsis')));
    expect(groupCards, contains('Contributor count unavailable'));
    expect(groupCards, isNot(contains("'\${summary.supporterCount} members'")));
    expect(collectionsScreen, contains('_GroupsCardGrid'));
    expect(collectionsScreen, isNot(contains('class _GroupsMetricPill')));
    expect(collectionsScreen, isNot(contains('Group activity')));
    expect(collectionsScreen, isNot(contains('Supported activity')));
    expect(collectionsScreen, isNot(contains('Total collected')));
    expect(detailActions, contains("label: 'Members'"));
    expect(detailActions, contains('final contributionActionLabel = isMember'));
    expect(detailActions, contains("? 'Contribute'"));
    expect(detailActions, contains(": 'Contribute & Join'"));
    expect(detailActions, contains('label: contributionActionLabel'));
    expect(detailActions, contains("label: 'Share'"));
    expect(detailActions, isNot(contains("label: 'QR'")));
    expect(detailActions, isNot(contains("label: 'People'")));
    expect(detailActions, isNot(contains("label: 'Pay'")));
    expect(detailActions, contains('/groups/\${widget.collectionId}/members'));
    expect(detailActions, isNot(contains('class _GroupMomentumRail')));
    expect(detailHero, contains('CollectScreenHero('));
    expect(detailHero, contains('semanticLabel:'));
    expect(shareScreen, contains("'Share group'"));
    expect(shareScreen, contains("label: 'Share link'"));
    expect(shareScreen, contains("label: 'Share QR code'"));
    expect(shareScreen, contains("label: 'Save QR'"));
    expect(shareScreen, contains("label: 'Copy link'"));
    expect(shareScreen, contains('QrEyeShape.square'));
    expect(shareScreen, contains('QrDataModuleShape.square'));
    expect(shareScreen, isNot(contains('CollectColors.groupAccentColors')));
    expect(shareScreen, isNot(contains('QrEyeShape.circle')));
    expect(shareScreen, isNot(contains('QrDataModuleShape.circle')));
    expect(
      shareScreen,
      isNot(
        contains('Text(\n                                  collection.title'),
      ),
    );
    expect(scaffoldChrome, contains('maxLines: 1'));
    expect(scaffoldChrome, contains('TextOverflow.ellipsis'));
    expect(collectionsScreen, isNot(contains("'Supporters'")));
    expect(collectionsScreen, isNot(contains("'Visible groups'")));
    expect(collectionsScreen, isNot(contains("'Share-ready'")));
    expect(runtimeSources, isNotEmpty);
    expect(
      manageScreen,
      isNot(contains('Name, image, visibility, recurrence, receiver.')),
    );
    expect(manageScreen, isNot(contains('Show, share, or save the QR image.')));
    expect(manageScreen, isNot(contains('Native share invite link.')));
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
    expect(
      tester.widget<Text>(find.text('Target account')).overflow,
      TextOverflow.clip,
    );
    expect(
      tester
          .widget<Text>(
            find.text('Receiver details are checked before handoff.'),
          )
          .overflow,
      TextOverflow.clip,
    );
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

  testWidgets('mobile completion components expose reusable semantics', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const Column(
        children: [
          CollectWizardProgress(
            labels: ['Basics', 'Receiver', 'Review'],
            currentStep: 1,
          ),
          CollectPermissionRecoveryPanel(
            icon: CollectIcons.warning,
            title: 'SMS access required.',
            message: 'Enable SMS access to automate MoMo SMS capture.',
            settingsMessage: 'Open app settings if Android keeps blocking SMS.',
          ),
        ],
      ),
    );

    expect(find.text('Basics'), findsOneWidget);
    expect(find.text('Receiver'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('SMS access required.'), findsOneWidget);
    expect(
      find.text('Open app settings if Android keeps blocking SMS.'),
      findsOneWidget,
    );
  });

  testWidgets('group type choices activate through assistive semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final options = CollectionTypeCatalogConfig.defaults.types;
      CollectionType? selected;
      var activations = 0;
      await _pumpCollect(
        tester,
        CollectionTypeIconSelector(
          selected: options.first.type,
          onChanged: (value) {
            selected = value;
            activations += 1;
          },
        ),
      );
      final choice = options[1];
      final node = tester.getSemantics(
        find.bySemanticsLabel('${choice.label} collection type'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(selected, choice.type);
      expect(activations, 1);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('list tile shows bounded helper text and action affordance', (
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

  testWidgets('screen header keeps compact one-line title with back action', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      const SizedBox(
        width: 320,
        child: ScreenHeader(
          title: 'Collect verified support for QA medical support group',
          subtitle: 'SMS-first MoMo evidence and private group links.',
          actions: [
            IconButton(onPressed: null, icon: Icon(CollectIcons.share)),
            IconButton(onPressed: null, icon: Icon(CollectIcons.copy)),
          ],
        ),
      ),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(
      find.text('Collect verified support for QA medical support group'),
      findsOneWidget,
    );
    expect(find.textContaining('SMS-first MoMo'), findsOneWidget);
    expect(find.byType(CollectBrandMark), findsNothing);
    expect(find.byIcon(CollectIcons.shield), findsNothing);
    expect(find.byIcon(CollectIcons.share), findsOneWidget);
    expect(find.byIcon(CollectIcons.copy), findsOneWidget);
  });

  testWidgets('top chrome exposes avatar title and circular actions', (
    tester,
  ) async {
    await _pumpCollect(
      tester,
      CollectTopChrome(
        avatarLabel: '038491',
        hasUnread: true,
        titleLabel: 'Payment status',
        actions: [
          CollectTopChromeAction(
            icon: CollectIcons.qr,
            tooltip: 'Scan QR code',
            onPressed: () {},
          ),
          CollectTopChromeAction(
            icon: CollectIcons.settings,
            tooltip: 'Settings',
            onPressed: () {},
          ),
        ],
      ),
    );

    expect(find.bySemanticsLabel('Open profile for 038491'), findsOneWidget);
    expect(find.text('91'), findsNothing);
    expect(find.text('Payment status'), findsOneWidget);
    expect(find.byIcon(CollectIcons.search), findsNothing);
    expect(find.byIcon(CollectIcons.qr), findsOneWidget);
    expect(find.byIcon(CollectIcons.settings), findsOneWidget);
  });

  testWidgets(
    'TalkBack reaches chrome and hero actions without duplicate group labels',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCollect(
        tester,
        Column(
          children: [
            CollectScreenTopChrome(
              avatarTooltip: 'Profile',
              searchLabel: 'Search groups',
              onAvatarTap: () {},
              onSearchTap: () {},
              actions: [
                CollectChromeAction(
                  icon: CollectIcons.add,
                  tooltip: 'Create group',
                  onPressed: () {},
                ),
              ],
            ),
            CollectHeroQuickActionRow(
              actions: [
                CollectHeroQuickAction(
                  icon: CollectIcons.add,
                  label: 'Create',
                  onTap: () {},
                ),
                CollectHeroQuickAction(
                  icon: CollectIcons.qr,
                  label: 'Scan QR',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      );

      expect(find.semantics.byLabel('Screen actions'), findsNothing);
      expect(find.semantics.byLabel('Primary screen actions'), findsNothing);
      for (final label in const [
        'Profile',
        'Search groups',
        'Create group',
        'Create',
        'Scan QR',
      ]) {
        final node = find.semantics.byPredicate((node) {
          final data = node.getSemanticsData();
          return data.label == label || data.tooltip == label;
        });
        expect(node, findsOne, reason: label);
        expect(
          find.semantics.descendant(
            of: node,
            matching: find.semantics.byAction(SemanticsAction.tap),
            matchRoot: true,
          ),
          findsOneWidget,
          reason: '$label must retain its TalkBack tap action.',
        );
      }
      semantics.dispose();
    },
  );

  testWidgets('screen top chrome retains the official logo at maximum text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(3.2)),
          child: Scaffold(
            body: CollectScreenTopChrome(
              avatarLabel: '038491',
              avatarTooltip: 'Profile',
              searchLabel: 'Search activity',
              onAvatarTap: () {},
              onSearchTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final officialLogo = find.byKey(
      const Key('collect_top_chrome_official_logo'),
    );
    final avatar = find.byTooltip('Profile');
    expect(officialLogo, findsOneWidget);
    expect(avatar, findsOneWidget);
    expect(
      tester.getRect(avatar).contains(tester.getCenter(officialLogo)),
      isTrue,
    );
    expect(tester.getSize(officialLogo), const Size.square(24));
    expect(
      (tester.widget<Image>(officialLogo).image as AssetImage).assetName,
      CollectRuntimeAssets.officialLogo,
    );
    expect(tester.takeException(), isNull);
  });

  test('primary route smoke list keeps admin out of member app', () {
    expect(
      collectRoutePaths,
      containsAll(<String>['/home', '/groups/:collectionId/contribute']),
    );
    expect(
      collectRoutePaths,
      isNot(contains('/groups/:collectionId/pay/:intentId')),
    );
    expect(collectRoutePaths, isNot(contains('/admin')));
  });
}
