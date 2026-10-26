part of 'admin_receipt_principal_integration_test.dart';

void _registerPrincipalWorkflowCases() {
  group('Current-owner principal Admin workflow', () {
    late _Sdk sdk;
    late _Repository repository;
    late _Store store;
    late ProviderContainer container;
    final authority = StateProvider<Future<AdminIdentity?>>(
      (_) async => _owner,
    );
    late StateProvider<DateTime> clock;
    setUp(() async {
      sdk = _Sdk();
      await sdk.start();
      store = _Store();
      repository = _Repository(store);
      clock = StateProvider((_) => _now);
      container = ProviderContainer(
        overrides: [
          collectBackendClientProvider.overrideWithValue(sdk.client),
          adminRepositoryProvider.overrideWithValue(repository),
          adminRealtimeSubscriptionProvider.overrideWith((ref) {}),
          adminIdentityProvider.overrideWith((ref) => ref.watch(authority)),
          adminReceiptPrincipalCheckpointStoreProvider.overrideWithValue(store),
          adminClockProvider.overrideWith((ref) {
            final value = ref.watch(clock);
            return () => value;
          }),
        ],
      );
      await container.read(adminIdentityProvider.future);
    });
    tearDown(() async {
      container.dispose();
      await sdk.client.dispose();
    });
    Future<void> mount(
      WidgetTester tester, {
      double width = 700,
      double scale = 1,
    }) async {
      await tester.runAsync(() async {
        container.read(adminAuthSessionScopeProvider);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.binding.setSurfaceSize(Size(width, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: CollectTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1400),
                  textScaler: TextScaler.linear(scale),
                ),
                child: const SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: AdminReceiptPrincipalCard(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
    }

    Future<void> open(WidgetTester tester) =>
        _tap(tester, 'Review signing identity');
    Future<void> enroll(WidgetTester tester) async {
      await _tap(tester, 'Enroll signing identity');
      await tester.enterText(
        _field('Public signing-key metadata'),
        jsonEncode(_metadata()),
      );
      await _tap(tester, 'Record pending identity');
    }

    Future<void> revoke(WidgetTester tester, String reason) async {
      await _tap(tester, 'Revoke signing identity');
      await tester.enterText(_field('Reason'), reason);
      await _tap(tester, 'Record identity revocation');
    }

    void verifyMetadataOnly() {
      final original = store.originals.values.single,
          decoded = jsonDecode(original) as Map<String, dynamic>;
      expect((decoded['binding'] as Map).keys.toSet(), {
        'action',
        'request_id',
        'principal_id',
        'key_sha256',
        'identity_expires_at',
        'created_at',
        'request_expires_at',
        'reason_sha256',
      });
      expect(original, isNot(contains(_metadata()['public_key_spki_base64'])));
      expect(original, isNot(contains('PRIVATE_CANARY')));
    }

    for (final absent in [
      'platform_owner',
      'admin_users.manage',
      'notifications.manage',
      'system_health.read',
    ]) {
      testWidgets('missing $absent prevents all principal reads and actions', (
        tester,
      ) async {
        container.read(authority.notifier).state = Future.value(
          AdminIdentity(
            userId: auth.actor,
            displayName: 'Synthetic denied owner',
            roles: absent == 'platform_owner' ? ['admin'] : _owner.roles,
            permissions: _owner.permissions.where((p) => p != absent).toList(),
          ),
        );
        await mount(tester);
        expect(find.textContaining('A current platform owner'), findsOneWidget);
        expect(find.text('Enroll signing identity'), findsNothing);
        expect(repository.queries, isEmpty);
        expect(repository.identityQueries, isEmpty);
        expect(repository.actions, isEmpty);
        expect(repository.lookups, isEmpty);
        expect(store.originals, isEmpty);
      });
    }
    testWidgets('another-user identity cannot reveal the owner directory', (
      tester,
    ) async {
      container.read(authority.notifier).state = Future.value(
        AdminIdentity(
          userId: auth.target,
          displayName: 'Different synthetic owner',
          roles: _owner.roles,
          permissions: _owner.permissions,
        ),
      );
      await mount(tester);
      expect(repository.queries, isEmpty);
      expect(find.text('Signing principal ID'), findsNothing);
    });
    testWidgets(
      'directory paging carries the paired cursor and returns safely',
      (tester) async {
        repository.useObservedRowsAs25Pages();
        await mount(tester);
        expect(find.text('Review signing identity'), findsNWidgets(25));
        final cursor = AdminReceiptPrincipalCursor.parse(
          repository.pages.first['next_cursor'],
        );
        await _tap(tester, 'Next identity page');
        expect(
          repository.queries.last,
          AdminReceiptPrincipalDirectoryQuery(before: cursor),
        );
        expect(find.text('Review signing identity'), findsNWidgets(4));
        await _tap(tester, 'Previous identity page');
        expect(repository.queries.last.before, isNull);
        expect(find.text('Review signing identity'), findsNWidgets(25));
        expect(repository.actions, isEmpty);
      },
    );
    testWidgets('expired directory hides IDs and disables enrollment', (
      tester,
    ) async {
      await mount(tester);
      final id = repository.observation['identity']['principal_id'] as String;
      expect(find.text(id), findsOneWidget);
      container.read(clock.notifier).state = _at(
        repository.pages.single,
        'sample_valid_until',
      );
      await _settle(tester);
      expect(
        find.textContaining('Identity directory evidence expired'),
        findsOneWidget,
      );
      expect(find.text(id), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.queries, hasLength(1));
      expect(repository.actions, isEmpty);
    });
    testWidgets('private directory evidence fails closed without raw output', (
      tester,
    ) async {
      repository.pages.single['authorization'] = 'PRIVATE_CANARY';
      await mount(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(find.text('Signing principal ID'), findsNothing);
      expect(repository.actions, isEmpty);
    });
    testWidgets('loading and redacted failure allow an explicit fresh retry', (
      tester,
    ) async {
      repository.directoryGate = Completer<void>();
      await mount(tester);
      expect(find.text('Loading receipt signing identities…'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Refresh signing identities'),
            )
            .onPressed,
        isNull,
      );
      repository.directoryError = StateError('PRIVATE_CANARY');
      repository.directoryGate!.complete();
      await _settle(tester);
      expect(find.textContaining('could not be verified'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      repository.directoryGate = null;
      repository.directoryError = null;
      await _tap(tester, 'Refresh signing identities');
      expect(find.text('Identity state: Pending'), findsOneWidget);
      expect(repository.queries, hasLength(2));
      expect(repository.actions, isEmpty);
    });
    for (final state in ['revoked', 'expired-active', 'expired-pending']) {
      testWidgets(
        '$state keeps identity state distinct from permitted actions',
        (tester) async {
          final raw = state == 'expired-pending'
              ? _observation(
                  (_observedPages().last['rows'] as List).single
                      as Map<String, dynamic>,
                  _now,
                )
              : _observed('identity-$state');
          repository.useObservation(raw);
          await mount(tester);
          await open(tester);
          final id = raw['identity']['principal_id'] as String;
          expect(repository.identityQueries, [id]);
          expect(find.text('Activate signing identity'), findsNothing);
          expect(
            find.text('Revoke signing identity'),
            state == 'revoked' ? findsNothing : findsOneWidget,
          );
          expect(
            find.text('Identity expiry has elapsed'),
            state == 'revoked' ? findsNothing : findsNWidgets(2),
          );
          expect(repository.actions, isEmpty);
          await _tap(tester, 'Close signing identity');
          expect(find.text('Receipt signing identity'), findsNothing);
        },
      );
    }
    testWidgets(
      'public enrollment saves and verifies metadata before one send',
      (tester) async {
        await mount(tester);
        await _tap(tester, 'Enroll signing identity');
        await tester.enterText(
          _field('Public signing-key metadata'),
          '{"private_key":"PRIVATE_CANARY"}',
        );
        await _tap(tester, 'Record pending identity');
        expect(
          find.textContaining('Use valid public signing-key metadata'),
          findsOneWidget,
        );
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
        await tester.enterText(
          _field('Public signing-key metadata'),
          jsonEncode(_metadata()),
        );
        await _tap(tester, 'Record pending identity');
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.enroll);
        expect(
          intent.requestExpiresAt.difference(intent.createdAt),
          const Duration(seconds: 90),
        );
        verifyMetadataOnly();
        expect(
          store.events.indexOf('published'),
          lessThan(store.events.indexOf('send')),
        );
        expect(
          store.events.sublist(
            store.events.indexOf('published') + 1,
            store.events.indexOf('send'),
          ),
          contains('read'),
        );
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Enrollment recorded: Pending'), findsOneWidget);
        expect(find.textContaining('original action receipt'), findsOneWidget);
        expect(find.text('Original identity request ID'), findsNothing);
        await _until(
          tester,
          () => repository.queries.length >= 2,
          'Durable enrollment must automatically refresh its directory.',
        );
        expect(repository.queries.length, greaterThanOrEqualTo(2));
      },
    );
    testWidgets('unavailable recovery storage prevents enrollment and sends', (
      tester,
    ) async {
      store.readError = StateError('PRIVATE_CANARY');
      await mount(tester);
      expect(find.text('Check identity recovery storage'), findsOneWidget);
      expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.actions, isEmpty);
      store.readError = null;
      await _tap(tester, 'Check identity recovery storage');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Enroll signing identity'),
            )
            .onPressed,
        isNotNull,
      );
    });
    testWidgets(
      'expired detail removes its fingerprint and mutation controls',
      (tester) async {
        await mount(tester);
        await open(tester);
        final key = repository.observation['identity']['key_sha256'] as String;
        expect(find.text(key), findsOneWidget);
        container.read(clock.notifier).state = _at(
          repository.observation,
          'sample_valid_until',
        );
        await _settle(tester);
        expect(
          find.textContaining('Signing identity evidence expired'),
          findsOneWidget,
        );
        expect(find.text(key), findsNothing);
        expect(find.text('Activate signing identity'), findsNothing);
        expect(find.text('Revoke signing identity'), findsNothing);
        expect(repository.identityQueries, hasLength(1));
        expect(repository.actions, isEmpty);
      },
    );
    testWidgets(
      'pending enrollment leaves investigation and urgent revoke usable',
      (tester) async {
        final enrolled = _observedIntent('enroll'),
            original = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              enrolled,
            );
        store.originals[original.requestId] = original.encode();
        await mount(tester);
        await open(tester);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Activate signing identity'),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Revoke signing identity'),
              )
              .onPressed,
          isNotNull,
        );
        await revoke(
          tester,
          'Revoke organization key during enrollment uncertainty',
        );
        expect(repository.actions, hasLength(1));
        final revocation = repository.actions.single;
        expect(revocation.action, AdminReceiptPrincipalAction.revoke);
        expect(store.originals, hasLength(2));
        expect(store.resolutions[revocation.requestId], 'recorded');
        expect(store.resolutions[original.requestId], isNull);
        await _tap(tester, 'Close signing identity');
        expect(
          find.text('Enrollment outcome needs reconciliation'),
          findsOneWidget,
        );
        expect(find.text('Revocation recorded: Revoked'), findsOneWidget);
        expect(repository.actions, hasLength(1));
      },
    );
    testWidgets(
      'activation proof refusal retains original and only manual lookup',
      (tester) async {
        repository.actionError = const CollectApiException(
          message: 'PRIVATE_CANARY proof missing',
          code: '42501',
        );
        await mount(tester);
        await open(tester);
        await _tap(tester, 'Activate signing identity');
        expect(repository.identityQueries, hasLength(3));
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.activate);
        verifyMetadataOnly();
        expect(store.resolutions, isEmpty);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        expect(find.textContaining('outcome is unknown'), findsWidgets);
        await _tap(tester, 'Close signing identity');
        await _tap(tester, 'Refresh signing identities');
        expect(repository.actions, hasLength(1));
        expect(
          find.text('Activation outcome needs reconciliation'),
          findsOneWidget,
        );
        await _tap(tester, 'Check original identity request');
        expect(repository.lookups.single.requestId, intent.requestId);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Activation recorded: Active'), findsOneWidget);
        expect(find.text('Identity state: Pending'), findsOneWidget);
        expect(repository.actions, hasLength(1));
      },
    );
    for (final changed in ['revoked', 'key', 'expiry']) {
      testWidgets(
        '$changed fresh preflight prevents stale activation submission',
        (tester) async {
          repository.readIdentity = (_, count) {
            if (count == 1) {
              return repository.observation;
            }
            final raw = _copy(repository.observation),
                row = raw['identity'] as Map<String, dynamic>;
            if (changed == 'revoked') {
              row['state'] = 'revoked';
              row['revoked_at'] = operationsUtc(_now);
            }
            if (changed == 'key') {
              row['key_sha256'] = 'a' * 64;
            }
            if (changed == 'expiry') {
              row['expires_at'] = operationsUtc(
                _at(row, 'expires_at').add(const Duration(microseconds: 1)),
              );
            }
            return raw;
          };
          await mount(tester);
          await open(tester);
          await _tap(tester, 'Activate signing identity');
          expect(repository.actions, isEmpty);
          expect(store.originals, isEmpty);
          expect(find.textContaining('No request was sent'), findsWidgets);
        },
      );
    }
    testWidgets(
      'unknown revocation keeps reason hash and manually recovers once',
      (tester) async {
        repository.actionError = TimeoutException('PRIVATE_CANARY transport');
        await mount(tester);
        await open(tester);
        await revoke(
          tester,
          'PRIVATE_CANARY revoke organizational signing key',
        );
        expect(repository.actions, hasLength(1));
        final intent = repository.actions.single;
        expect(intent.action, AdminReceiptPrincipalAction.revoke);
        verifyMetadataOnly();
        final original = AdminReceiptPrincipalCheckpoint.parse(
          store.originals.values.single,
          adminReceiptPrincipalOwnerDigest(auth.actor),
        );
        expect(original.binding.reasonSha256, intent.reasonSha256);
        expect(store.resolutions, isEmpty);
        await _tap(tester, 'Close signing identity');
        expect(
          find.text('Revocation outcome needs reconciliation'),
          findsOneWidget,
        );
        repository.lookupError = StateError('PRIVATE_CANARY lookup');
        await _tap(tester, 'Check original identity request');
        expect(store.resolutions, isEmpty);
        expect(find.textContaining('PRIVATE_CANARY'), findsNothing);
        repository.lookupError = null;
        await _tap(tester, 'Check original identity request');
        expect(repository.lookups.map((p) => p.requestId), [
          intent.requestId,
          intent.requestId,
        ]);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Revocation recorded: Revoked'), findsOneWidget);
        expect(store.originals, hasLength(1));
        expect(repository.actions, hasLength(1));
      },
    );
    testWidgets(
      'restored original permits lookup and never reconstructs a send',
      (tester) async {
        final intent = _observedIntent('enroll'),
            checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              intent,
            );
        store.originals[checkpoint.requestId] = checkpoint.encode();
        await mount(tester);
        expect(find.text(intent.requestId), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Enroll signing identity'),
              )
              .onPressed,
          isNull,
        );
        await _tap(tester, 'Check original identity request');
        expect(repository.actions, isEmpty);
        expect(repository.lookups.single.requestId, intent.requestId);
        expect(store.resolutions[intent.requestId], 'recorded');
        expect(find.text('Enrollment recorded: Pending'), findsOneWidget);
        expect(store.originals[checkpoint.requestId], checkpoint.encode());
      },
    );
    testWidgets(
      'absence clears only with fresh proof after retained deadline',
      (tester) async {
        final intent = _observedIntent('activate'),
            checkpoint = AdminReceiptPrincipalCheckpoint.fromIntent(
              adminReceiptPrincipalOwnerDigest(auth.actor),
              intent,
            );
        store.originals[checkpoint.requestId] = checkpoint.encode();
        repository.readLookup = (binding) =>
            _lookup(binding, repository.now, status: 'not_recorded');
        await mount(tester);
        await _tap(tester, 'Check original identity request');
        expect(store.resolutions, isEmpty);
        expect(
          find.text('Activation outcome needs reconciliation'),
          findsOneWidget,
        );
        repository.now = intent.requestExpiresAt;
        container.read(clock.notifier).state = repository.now;
        await _settle(tester);
        await _tap(tester, 'Check original identity request');
        expect(
          store.resolutions[intent.requestId],
          'not_recorded_after_deadline',
        );
        expect(find.textContaining('No request was replayed'), findsOneWidget);
        expect(repository.actions, isEmpty);
        expect(store.originals[checkpoint.requestId], checkpoint.encode());
      },
    );
    testWidgets(
      'same-user A-B-A replacement closes enrollment and suppresses draft',
      (tester) async {
        await mount(tester);
        await _tap(tester, 'Enroll signing identity');
        await tester.enterText(
          _field('Public signing-key metadata'),
          jsonEncode(_metadata()),
        );
        await tester.runAsync(
          () => auth.session(sdk.client, 'principal-modal-b'),
        );
        await _settle(tester);
        await tester.runAsync(
          () => auth.session(sdk.client, 'principal-integration-a', nonce: 1),
        );
        await _settle(tester);
        expect(find.text('Enroll receipt signing identity'), findsNothing);
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
      },
    );
    testWidgets(
      'role departure closes current detail before role restoration',
      (tester) async {
        await mount(tester);
        await open(tester);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        expect(find.text('Receipt signing identity'), findsNothing);
        expect(find.text('Activate signing identity'), findsNothing);
        expect(repository.actions, isEmpty);
        expect(repository.identityQueries, hasLength(1));
      },
    );
    testWidgets('late identity read cannot resurrect a departed A-B-A modal', (
      tester,
    ) async {
      repository.identityGate = Completer<void>();
      await mount(tester);
      await open(tester);
      expect(find.text('Loading current signing identity…'), findsOneWidget);
      await tester.runAsync(() => auth.session(sdk.client, 'principal-read-b'));
      await _settle(tester);
      await tester.runAsync(
        () => auth.session(sdk.client, 'principal-integration-a', nonce: 2),
      );
      await _settle(tester);
      repository.identityGate!.complete();
      await _settle(tester);
      expect(find.text('Receipt signing identity'), findsNothing);
      expect(find.text('Public key fingerprint'), findsNothing);
      expect(find.text('Activate signing identity'), findsNothing);
      expect(repository.identityQueries, hasLength(1));
      expect(repository.actions, isEmpty);
      expect(store.originals, isEmpty);
    });
    testWidgets(
      'authority loss during async publication commits no original or send',
      (tester) async {
        store.publicationGate = Completer<void>();
        await mount(tester);
        await enroll(tester);
        expect(store.events, contains('publication-entered'));
        expect(repository.actions, isEmpty);
        container.read(authority.notifier).state = Future.value(null);
        await _settle(tester);
        container.read(authority.notifier).state = Future.value(_owner);
        await _settle(tester);
        store.publicationGate!.complete();
        await _settle(tester);
        expect(repository.actions, isEmpty);
        expect(store.originals, isEmpty);
        expect(find.text('Enrollment recorded: Pending'), findsNothing);
      },
    );
    testWidgets(
      '320px twice-text detail keeps named semantic controls usable',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, width: 320, scale: 2);
          await open(tester);
          expect(tester.takeException(), isNull);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics && widget.properties.header == true,
            ),
            findsWidgets,
          );
          await _tap(tester, 'Refresh signing identity');
          expect(repository.identityQueries, hasLength(2));
          await _tap(tester, 'Close signing identity');
          expect(find.text('Receipt signing identity'), findsNothing);
          expect(tester.takeException(), isNull);
          expect(repository.actions, isEmpty);
        } finally {
          semantics.dispose();
        }
      },
    );
  });
}
