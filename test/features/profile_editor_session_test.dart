import 'dart:async';

import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/features/profile/profile_edit_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _profileA = CollectProfile(
  id: 'profile-a',
  publicId: '123456',
  whatsappPhone: '+250788123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'mtn_momo',
  momoNumber: '0788123456',
  momoPayCode: '111111',
);
const _profileB = CollectProfile(
  id: 'profile-b',
  publicId: '654321',
  whatsappPhone: '+250720123456',
  countryCode: 'RW',
  currencyCode: 'RWF',
  momoProvider: 'airtel_money',
  momoNumber: '0720123456',
  momoPayCode: '222222',
);

class _ProfileRepository extends CollectRepository {
  _ProfileRepository()
    : super.fixture(
        initialState: const CollectState(
          currentProfile: _profileA,
          collections: [],
          paymentIntents: [],
          contributions: [],
        ),
      );

  int _generation = 0;
  Completer<CollectProfile>? reply;
  final submissions = <({String? owner, int generation, String? number})>[];

  @override
  int get sessionGeneration => _generation;

  void publish(CollectProfile? profile, {bool newSession = true}) {
    if (newSession) _generation++;
    state = state.copyWith(currentProfile: profile);
  }

  @override
  Future<CollectProfile> updateCurrentProfile({
    required String countryCode,
    String? momoProvider,
    String? momoNumber,
    String? momoPayCode,
  }) {
    submissions.add((
      owner: state.currentProfile?.id,
      generation: _generation,
      number: momoNumber,
    ));
    return reply!.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<_ProfileRepository> pumpEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ProfileRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          collectRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp(
          theme: CollectTheme.dark(),
          home: const ProfileEditScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Finder input(String key) => find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(TextField),
  );

  String value(WidgetTester tester, String key) =>
      tester.widget<TextField>(input(key)).controller!.text;

  Future<void> editNumber(WidgetTester tester, String number) async {
    final field = input('profile_momo_number_input');
    await tester.ensureVisible(field);
    await tester.enterText(field, number);
    await tester.pump();
  }

  Future<void> showCode(WidgetTester tester) async {
    final tab = find.byKey(const ValueKey('profile_momo_code_tab'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
  }

  testWidgets('dirty A fields do not survive null then B', (tester) async {
    final repo = await pumpEditor(tester);
    await editNumber(tester, '0788000001');
    await showCode(tester);
    await tester.enterText(input('profile_momo_code_input'), '999999');
    await tester.pump();

    repo.publish(null);
    await tester.pump();
    expect(input('profile_momo_code_input'), findsNothing);
    expect(input('profile_momo_number_input'), findsNothing);
    repo.publish(_profileB);
    await tester.pump();
    expect(value(tester, 'profile_momo_number_input'), _profileB.momoNumber);
    await showCode(tester);
    expect(value(tester, 'profile_momo_code_input'), _profileB.momoPayCode);
    expect(repo.submissions, isEmpty);
  });

  testWidgets('A to B to A cannot restore the first A draft', (tester) async {
    final repo = await pumpEditor(tester);
    await editNumber(tester, '0788000001');
    repo.publish(_profileB);
    await tester.pump();
    expect(value(tester, 'profile_momo_number_input'), _profileB.momoNumber);
    repo.publish(_profileA);
    await tester.pump();
    expect(value(tester, 'profile_momo_number_input'), _profileA.momoNumber);
    expect(repo.submissions, isEmpty);
  });

  testWidgets('new same-user session resets the earlier session draft', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    await editNumber(tester, '0788000001');
    repo.publish(_profileA);
    await tester.pump();
    expect(value(tester, 'profile_momo_number_input'), _profileA.momoNumber);
    expect(repo.submissions, isEmpty);
  });

  testWidgets('same-session refresh and rebuild retain dirty text', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    await editNumber(tester, '0788000001');
    repo.publish(_profileA.copyWith(momoPayCode: '333333'), newSession: false);
    await tester.pump();
    expect(value(tester, 'profile_momo_number_input'), '0788000001');
    await tester.pump(const Duration(milliseconds: 100));
    expect(value(tester, 'profile_momo_number_input'), '0788000001');
    expect(repo.submissions, isEmpty);
  });

  for (final succeed in [true, false]) {
    testWidgets('late A save ${succeed ? 'success' : 'error'} cannot alter B', (
      tester,
    ) async {
      final repo = await pumpEditor(tester);
      final reply = Completer<CollectProfile>();
      repo.reply = reply;
      await editNumber(tester, '0788000001');
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(repo.submissions, hasLength(1));
      expect(repo.submissions.single.owner, _profileA.id);
      expect(repo.submissions.single.number, '0788000001');

      repo.publish(null);
      repo.publish(_profileB);
      if (succeed) {
        reply.complete(_profileA.copyWith(momoNumber: '0788000001'));
      } else {
        reply.completeError(StateError('synthetic stale error'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(value(tester, 'profile_momo_number_input'), _profileB.momoNumber);
      expect(find.text('Profile saved.'), findsNothing);
      expect(
        find.text('Your profile could not be saved. Try again.'),
        findsNothing,
      );
      expect(repo.submissions, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late first-session save cannot replace A after A to B to A', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    final reply = Completer<CollectProfile>();
    repo.reply = reply;
    await editNumber(tester, '0788000001');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(repo.submissions.single.owner, _profileA.id);

    // Complete before the next frame so the old widget may still be mounted.
    repo.publish(_profileB);
    repo.publish(_profileA);
    reply.complete(_profileA.copyWith(momoNumber: '0788000001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(value(tester, 'profile_momo_number_input'), _profileA.momoNumber);
    expect(find.text('Profile saved.'), findsNothing);
    expect(repo.submissions, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('discard decision from A cannot navigate the replacement B', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    await editNumber(tester, '0788000001');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    repo.publish(_profileB);
    await tester.pump();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(value(tester, 'profile_momo_number_input'), _profileB.momoNumber);
    expect(repo.submissions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('success notice is removed on session replacement', (
    tester,
  ) async {
    final repo = await pumpEditor(tester);
    final reply = Completer<CollectProfile>();
    repo.reply = reply;
    await editNumber(tester, '0788000001');
    await tester.tap(find.text('Save'));
    await tester.pump();
    reply.complete(_profileA.copyWith(momoNumber: '0788000001'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Profile saved.'), findsOneWidget);
    repo.publish(_profileB);
    await tester.pump();
    expect(find.text('Profile saved.'), findsNothing);
    expect(value(tester, 'profile_momo_number_input'), _profileB.momoNumber);
  });
}
