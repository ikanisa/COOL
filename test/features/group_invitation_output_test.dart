import 'dart:async';
import 'dart:ui' as ui;

import 'package:collect_app/app/theme/app_theme.dart';
import 'package:collect_app/features/collections/group_invitation_transport.dart';
import 'package:collect_app/features/collections/share_screen.dart';
import 'package:collect_app/shared/models/collect_models.dart';
import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fixtures/collect_repository_fixture.dart';
import 'group_invitation_save_receipt_test.dart' show AndroidReceiptTransport;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final action in ['Save QR', 'Share QR code']) {
    for (final change in [
      'account',
      'A-B-A',
      'membership',
      'archive',
      'covered',
      'covered-returned',
      'disposed',
    ]) {
      testWidgets('$action cancels delayed export after $change', (
        tester,
      ) async {
        final h = await _mount(tester);
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pump();
        expect(h.transport.renderCalls, 1);
        switch (change) {
          case 'account':
            h.repo.changeAccount();
          case 'A-B-A':
            h.repo.changeAccount();
            h.repo.restoreAccount();
          case 'membership':
            h.repo.changeGroup(member: false);
          case 'archive':
            h.repo.changeGroup(archived: true);
          case 'covered':
          case 'covered-returned':
            h.navigator.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Other route')),
              ),
            );
            await tester.pumpAndSettle();
            if (change == 'covered-returned') {
              h.navigator.currentState!.pop();
              await tester.pumpAndSettle();
            }
          case 'disposed':
            await tester.pumpWidget(const SizedBox());
        }
        h.transport.renderReply.complete(Uint8List.fromList([1, 2, 3]));
        await tester.pumpAndSettle();
        expect(h.transport.saves, 0);
        expect(h.transport.qrShares, 0);
        expect(h.transport.copies, 0);
        expect(find.text('QR saved.'), findsNothing);
        expect(find.text('Group link copied.'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final action in ['Save QR', 'Share QR code']) {
    testWidgets('$action still exports the current invitation once', (
      tester,
    ) async {
      final h = await _mount(tester);
      await tester.ensureVisible(find.text(action));
      await tester.tap(find.text(action));
      await tester.pump();
      h.transport.renderReply.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pumpAndSettle();
      expect(h.transport.saves, action == 'Save QR' ? 1 : 0);
      expect(h.transport.qrShares, action == 'Share QR code' ? 1 : 0);
      expect(h.transport.copies, 0);
      expect(h.transport.renderedLink, endsWith('/c/qa-private-group'));
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in ['Share QR code', 'Share link']) {
    testWidgets(
      '$action never copies stale link after platform share failure',
      (tester) async {
        final h = await _mount(tester);
        h.transport.shareReply = Completer<void>();
        if (action == 'Share QR code') {
          h.transport.renderReply.complete(Uint8List.fromList([1]));
        }
        await tester.ensureVisible(find.text(action));
        await tester.tap(find.text(action));
        await tester.pump();
        expect(h.transport.qrShares + h.transport.linkShares, 1);
        h.repo.changeAccount();
        h.transport.shareReply!.completeError(
          StateError('synthetic platform failure'),
        );
        await tester.pumpAndSettle();
        expect(h.transport.copies, 0);
        expect(find.text('Group link copied.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('current failed share retains explicit clipboard fallback', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.transport.shareReply = Completer<void>();
    await tester.ensureVisible(find.text('Share link'));
    await tester.tap(find.text('Share link'));
    await tester.pump();
    h.transport.shareReply!.completeError(
      StateError('synthetic platform failure'),
    );
    await tester.pumpAndSettle();
    expect(h.transport.copies, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed fresh authority read clears visible QR and cannot export', (
    tester,
  ) async {
    final h = await _mount(tester);
    h.repo.failRead = true;
    await tester.ensureVisible(find.text('Save QR'));
    await tester.tap(find.text('Save QR'));
    await tester.pumpAndSettle();
    expect(h.transport.renderCalls, 0);
    expect(h.transport.saves, 0);
    expect(find.text('Share QR code'), findsNothing);
    expect(
      find.text(
        'The current invitation could not be verified. Refresh before sharing.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic secret'), findsNothing);
    h.repo.failRead = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Share QR code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('real QR renderer produces a full1080px PNG', (tester) async {
    await tester.runAsync(() async {
      final bytes = await const GroupInvitationTransport().renderQr(
        'https://collect.ikanisa.com/c/synthetic',
      );
      expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1080);
      expect(frame.image.height, 1080);
      frame.image.dispose();
      codec.dispose();
    });
  });
  for (final success in [false, true]) {
    testWidgets('Save QR displays only confirmed Android receipt: $success', (
      tester,
    ) async {
      var calls = 0;
      const channel = MethodChannel('file_saver');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls++;
        return success
            ? '/private/${(call.arguments as Map)['name']}.png'
            : 'Error While Saving Filesynthetic private path';
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _mount(tester, boundary: const AndroidReceiptTransport());
      await tester.ensureVisible(find.text('Save QR'));
      await tester.tap(find.text('Save QR'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('QR saved.'), success ? findsOneWidget : findsNothing);
      expect(
        find.text('Could not save QR. Refresh and try again.'),
        success ? findsNothing : findsOneWidget,
      );
      expect(find.textContaining('synthetic private'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('late Android save failure after account change stays hidden', (
    tester,
  ) async {
    var calls = 0;
    final reply = Completer<String>();
    const channel = MethodChannel('file_saver');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls++;
      return reply.future;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final h = await _mount(tester, boundary: const AndroidReceiptTransport());
    await tester.ensureVisible(find.text('Save QR'));
    await tester.tap(find.text('Save QR'));
    await tester.pump();
    expect(calls, 1);
    h.repo.changeAccount();
    reply.complete('Error While Saving Filesynthetic private path');
    await tester.pumpAndSettle();
    expect(find.text('QR saved.'), findsNothing);
    expect(
      find.text('Could not save QR. Refresh and try again.'),
      findsNothing,
    );
    expect(find.textContaining('synthetic private'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _Harness {
  _Harness(this.repo, this.transport, this.navigator);
  final _Repository repo;
  final _Transport transport;
  final GlobalKey<NavigatorState> navigator;
}

Future<_Harness> _mount(
  WidgetTester tester, {
  GroupInvitationTransport? boundary,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = _Repository(), transport = _Transport();
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        collectRepositoryProvider.overrideWith((ref) => repo),
        groupInvitationTransportProvider.overrideWithValue(
          boundary ?? transport,
        ),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        theme: AppTheme.dark(),
        home: const ShareScreen(collectionId: 'qa-private-group'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Share link'), findsOneWidget);
  return _Harness(repo, transport, navigator);
}

class _Repository extends FixtureCollectRepository {
  bool failRead = false;
  @override
  Future<String> getGroupShareCode(String id) => failRead
      ? Future.error(StateError('synthetic secret authority denial'))
      : super.getGroupShareCode(id);
  late final original = state;
  void changeAccount() {
    final current = original;
    state = current.copyWith(
      currentProfile: const CollectProfile(
        id: 'other',
        publicId: '234567',
        whatsappPhone: '+250788111222',
      ),
    );
  }

  void restoreAccount() {
    state = original;
  }

  void changeGroup({bool? member, bool archived = false}) {
    state = state.copyWith(
      collections: [
        for (final g in state.collections)
          if (g.id == 'qa-private-group')
            g.copyWith(
              isCurrentUserMember: member,
              moderationStatus: archived ? 'archived' : g.moderationStatus,
            )
          else
            g,
      ],
    );
  }
}

class _Transport extends GroupInvitationTransport {
  final renderReply = Completer<Uint8List>();
  Completer<void>? shareReply;
  int renderCalls = 0, saves = 0, qrShares = 0, linkShares = 0, copies = 0;
  String? renderedLink;
  @override
  Future<Uint8List> renderQr(String link) {
    renderCalls++;
    renderedLink = link;
    return renderReply.future;
  }

  @override
  Future<void> saveQr(Uint8List bytes, String filename) async {
    saves++;
  }

  @override
  Future<void> shareQr(
    Uint8List bytes,
    String filename,
    String text,
    Rect origin,
  ) {
    qrShares++;
    return shareReply?.future ?? Future.value();
  }

  @override
  Future<void> shareLink(String title, String text, Rect origin) {
    linkShares++;
    return shareReply?.future ?? Future.value();
  }

  @override
  Future<void> copyLink(String link) async {
    copies++;
  }
}
