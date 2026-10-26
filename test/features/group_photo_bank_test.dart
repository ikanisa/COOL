import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/shared/models/collect_group_cover.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_offline_cache.dart';
import 'package:collect_app/shared/widgets/collect_group_photo_picker.dart';
import 'package:collect_app/shared/widgets/collect_group_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fixtures/collect_repository_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'runtime cover metadata and order match the complete source catalog',
    () {
      final catalog =
          jsonDecode(
                File(
                  'assets/group_covers/rwanda/catalog.v1.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final assets = (catalog['assets'] as List).cast<Map<String, dynamic>>();
      final families = {
        for (final family
            in (catalog['families'] as List).cast<Map<String, dynamic>>())
          family['id']: family,
      };
      expect(
        collectGroupCovers.map((cover) => cover.id),
        assets.map((asset) => asset['id']),
      );
      for (var index = 0; index < assets.length; index++) {
        final asset = assets[index];
        final cover = collectGroupCovers[index];
        expect(
          {
            'id': cover.id,
            'version': cover.version,
            'name': cover.name,
            'family': cover.family,
            'theme': cover.theme,
            'types': cover.types,
            'terms': cover.terms,
            'context': cover.context,
            'namedGroup': cover.namedGroup,
            'generalDefault': cover.generalDefault,
            'priority': cover.priority,
            'focalX': cover.focalX,
            'focalY': cover.focalY,
          },
          {
            'id': asset['id'],
            'version': asset['version'],
            'name': asset['labels']['en'],
            'family': asset['family'],
            'theme': asset['theme'],
            'types': asset['collection_types'],
            'terms': [
              ...(asset['labels'] as Map).values,
              ...(families[asset['family']]!['labels'] as Map).values,
              ...asset['search_terms'] as List,
            ],
            'context': asset['explicit_context'],
            'namedGroup': asset['named_group'],
            'generalDefault': asset['general_default'],
            'priority': asset['editorial_priority'],
            'focalX': asset['focal_point']['x'],
            'focalY': asset['focal_point']['y'],
          },
          reason: cover.id,
        );
      }
    },
  );

  test(
    'covers are versioned and named covers require governed group identity',
    () {
      expect(collectGroupCovers.length, 42);
      expect(
        CollectGroupCover.resolve(
          'collect-cover:rw-09-wedding-committee:v2',
        )?.version,
        2,
      );
      expect(
        CollectGroupCover.resolve('collect-cover:../../secrets:v1'),
        isNull,
      );
      expect(
        CollectGroupCover.resolve('collect-cover:rw-09-wedding-committee:v999'),
        isNull,
      );
      final generic = CollectGroupCover.suggestions(browseAll: true);
      expect(
        generic.every((c) => c.namedGroup == null && c.context == null),
        isTrue,
      );
      expect(
        CollectGroupCover.suggestions(query: 'Gikundiro', browseAll: true),
        isEmpty,
      );
      expect(
        CollectGroupCover.suggestions(type: CollectionType.sport).length,
        4,
      );
      expect(
        CollectGroupCover.suggestions(type: CollectionType.church).length,
        5,
      );
      expect(
        CollectGroupCover.suggestions(
          family: 'weddings',
          query: 'ubukwe',
        ).length,
        6,
      );
      expect(
        CollectGroupCover.suggestions(
          context: 'muslim',
          browseAll: true,
        ).any((c) => c.context == 'muslim'),
        isTrue,
      );
      final record = <String, dynamic>{
        'id': 'test-public',
        'slug': 'gikundiro',
        'title': 'Gikundiro',
        'is_public': true,
        'is_platform_sponsored': true,
        'collection_type': 'sport',
        'created_at': '2026-09-06T00:00:00Z',
      };
      final named = CollectCollection.fromJson(record);
      expect(CollectGroupCover.fallbackFor(named)?.namedGroup, 'gikundiro');
      expect(
        CollectGroupCover.fallbackFor(
          CollectCollection.fromJson({
            ...record,
            'slug': 'someone-elses-group',
          }),
        )?.namedGroup,
        isNull,
      );
      expect(
        CollectGroupCover.fallbackFor(
          named.copyWith(isPlatformSponsored: false),
        )?.namedGroup,
        isNull,
      );
    },
  );

  test(
    'create, cache reload, owner edit and remove retain exact media state',
    () async {
      const ownerId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final repo = FixtureCollectRepository(
        profileOverride: const CollectProfile(
          id: ownerId,
          publicId: '123456',
          whatsappPhone: '',
          countryCode: 'RW',
          currencyCode: 'RWF',
        ),
      );
      addTearDown(repo.dispose);
      const channel = MethodChannel('collect/secure_snapshot');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      String? protectedSnapshot;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final arguments = Map<String, Object?>.from(call.arguments as Map);
        expect(arguments['owner_id'], ownerId);
        switch (call.method) {
          case 'write':
            expect(arguments.keys, unorderedEquals(['owner_id', 'value']));
            protectedSnapshot = arguments['value'] as String;
            return true;
          case 'read':
            expect(arguments.keys, ['owner_id']);
            return protectedSnapshot;
          default:
            throw StateError(
              'Unexpected protected snapshot call: ${call.method}',
            );
        }
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final cover = collectGroupCovers.first;
      final created = await repo.createCollection(
        title: 'QA savings',
        requestId: 'a1111111-1111-4111-8111-111111111111',
        description: 'Fixture',
        imageUrl: cover.reference,
      );
      const cache = CollectOfflineCache.protected();
      await cache.save(
        CollectOfflineSnapshot(
          savedAt: DateTime.now(),
          currentProfile: repo.state.currentProfile,
          collections: [created],
          paymentIntents: const [],
          contributions: const [],
        ),
      );
      final restored = await cache.read(ownerUserId: ownerId);
      expect(restored!.currentProfile?.id, ownerId);
      expect(restored.collections.single.primaryPaymentRail, 'unavailable');
      expect(restored.collections.single.imageUrl, cover.reference);
      expect(
        CollectGroupCover.resolve(restored.collections.single.imageUrl)?.asset,
        cover.asset,
      );
      final second = collectGroupCovers[8];
      await repo.updateCollectionProfile(
        collectionId: created.id,
        title: created.title,
        description: created.description,
        recurringCadence: 'monthly',
        imageUrl: second.reference,
        isPublic: false,
      );
      expect(repo.maybeCollectionById(created.id)!.imageUrl, second.reference);
      await repo.updateCollectionProfile(
        collectionId: created.id,
        title: 'Updated title without image changes',
        description: created.description,
        recurringCadence: 'monthly',
        imageUrl: null,
        isPublic: false,
      );
      expect(repo.maybeCollectionById(created.id)!.imageUrl, second.reference);
      await repo.updateCollectionProfile(
        collectionId: created.id,
        title: created.title,
        description: created.description,
        recurringCadence: 'monthly',
        imageUrl: '',
        isPublic: false,
      );
      expect(repo.maybeCollectionById(created.id)!.imageUrl, isNull);
    },
  );

  Future<void> pumpSheet(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    double keyboard = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
            disableAnimations: true,
          ),
          child: const Scaffold(
            resizeToAvoidBottomInset: false,
            body: RepaintBoundary(
              key: ValueKey('cover-capture'),
              child: CollectGroupPhotoSheet(groupType: CollectionType.wedding),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('search, select, confirm and empty recovery are deliberate', (
    tester,
  ) async {
    await pumpSheet(tester);
    final use = find.widgetWithText(FilledButton, 'Use photo');
    // The shared button may choose a platform ButtonStyleButton subclass.
    expect(find.text('Use photo'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('group-photo-search')),
      'gusaba',
    );
    await tester.pumpAndSettle();
    expect(find.text('1 photo'), findsOneWidget);
    final image = find.byKey(
      const ValueKey('group-photo-rw-10-gusaba-gukwa-gathering'),
    );
    await tester.ensureVisible(image);
    await tester.tap(image);
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Gusaba and gukwa gathering'))
          .flagsCollection
          .isSelected,
      ui.Tristate.isTrue,
    );
    semantics.dispose();
    expect(use.evaluate().isNotEmpty, isTrue);
    await tester.ensureVisible(
      find.byKey(const ValueKey('group-photo-search')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('group-photo-search')),
      'no_such_photo',
    );
    await tester.pumpAndSettle();
    expect(find.text('No matching photos'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear filters'));
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('No matching photos'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (const Size(320, 740), 2.0, 0.0),
    (const Size(390, 844), 1.0, 300.0),
    (const Size(844, 390), 1.0, 0.0),
    (const Size(844, 390), 1.0, 248.0),
    (const Size(844, 390), 2.0, 248.0),
  ]) {
    testWidgets(
      'photo sheet fits ${scenario.$1} at ${scenario.$2} with keyboard ${scenario.$3}',
      (tester) async {
        await pumpSheet(
          tester,
          size: scenario.$1,
          scale: scenario.$2,
          keyboard: scenario.$3,
        );
        expect(tester.takeException(), isNull);
        await tester.enterText(
          find.byKey(const ValueKey('group-photo-search')),
          'wedding',
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Use photo'),
          100,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('group-photo-scroll')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final confirm = tester.getRect(find.text('Use photo'));
        expect(
          confirm.bottom,
          lessThanOrEqualTo(scenario.$1.height - scenario.$3),
        );
      },
    );
  }

  testWidgets(
    'saved reference renders offline and unknown version falls back',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: CollectGroupImage(
              value: collectGroupCovers.first.reference,
              fallback: const Text('Fallback'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Fallback'), findsNothing);
      await tester.pumpWidget(
        const MaterialApp(
          home: CollectGroupImage(
            value: 'collect-cover:unknown:v99',
            fallback: Text('Fallback'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fallback'), findsOneWidget);
    },
  );

  testWidgets('capture local photo-picker framing', (tester) async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/typefaces/Inter-Variable.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await pumpSheet(tester);
    await tester.enterText(
      find.byKey(const ValueKey('group-photo-search')),
      'gusaba',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('group-photo-rw-10-gusaba-gukwa-gathering')),
    );
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('cover-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File('.cache/group-cover-integration/picker-wedding.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    });
    expect(tester.takeException(), isNull);
  });
}
