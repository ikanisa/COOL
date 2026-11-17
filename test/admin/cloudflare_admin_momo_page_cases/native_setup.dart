part of '../cloudflare_admin_momo_page_test.dart';

const _nativeGrant = 'ac100000-0000-4000-8000-000000000001';
const _nativeInstallation = 'ac100000-0000-4000-8000-000000000002';
const _nativeCustodian = 'ac100000-0000-4000-8000-000000000003';
const _oldNativeInstallation = 'ac100000-0000-4000-8000-000000000004';
const _oldNativeBinding = 'ac100000-0000-4000-8000-000000000005';
const _oldNativeKey = 'ac100000-0000-4000-8000-000000000006';
const _nativePermissions = [
  'payments.read',
  'sms.read',
  'receivers.read',
  'receivers.manage',
  'admin_users.manage',
];
Map<String, dynamic> _nativeDirectory({
  bool prepared = true,
  bool paired = false,
  bool receiverHistory = false,
  List<Map<String, dynamic>>? devices,
  Map<String, dynamic>? replacement,
}) => {
  'contractVersion': 1,
  'collections': [
    {
      'id': groupId,
      'title': 'Existing Collect group',
      'receiverNetwork': 'mtn_momo',
      'receiverNumber': '123456',
      'version': 4,
    },
    {
      'id': 'other-existing-group',
      'title': 'Other Collect group',
      'receiverNetwork': 'airtel_money',
      'receiverNumber': '654321',
      'version': 1,
    },
  ],
  'accounts': [],
  'scopes': prepared
      ? [
          {
            'collectionId': groupId,
            'receivingAccountId': accountId,
            'enabled': paired || receiverHistory || replacement != null,
            'version': replacement?['phase'] == 'retired' ? 3 : 2,
            'bindingId': replacement?['phase'] == 'retired'
                ? txId
                : paired || receiverHistory
                ? _oldNativeBinding
                : null,
            'bindingVersion': 1,
            'paired': paired && replacement?['phase'] != 'retired',
            'receiverKeyId':
                (paired || receiverHistory) &&
                    replacement?['phase'] != 'retired'
                ? _oldNativeKey
                : null,
            'receiverInstallationId':
                (paired || receiverHistory) &&
                    replacement?['phase'] != 'retired'
                ? _oldNativeInstallation
                : null,
            'pendingReplacement': replacement,
          },
        ]
      : [],
  'installations':
      devices ??
      [
        {
          'grantId': _nativeGrant,
          'installationId': _nativeInstallation,
          'grantVersion': 3,
          'custodianAccountId': _nativeCustodian,
          'custodianName': 'Approved current owner',
          'custodyAssigned': false,
        },
      ],
};
Map<String, dynamic> _nativeReceipt(Map<String, dynamic> c, {int? expiresAt}) =>
    {
      'contractVersion': 1,
      'requestId': c['requestId'],
      'collectionId': c['collectionId'],
      'operation': c['operation'],
      'receivingAccountId': c['receivingAccountId'],
      'scopeVersion':
          (c['expectedScopeVersion'] as int) +
          (c['operation'] == 'prepare_replacement' ? 0 : 1),
      'enabled': c['operation'] != 'prepare',
      'bindingId': txId,
      'pairingId': paymentId,
      'bindingVersion': 1,
      'installationId': c['installationId'],
      'custodianAccountId': c['custodianAccountId'],
      'grantId': c['grantId'],
      'grantVersion': c['expectedGrantVersion'],
      'subscriptionId': c['subscriptionId'],
      'deliveryExpiresAt':
          expiresAt ?? DateTime.now().millisecondsSinceEpoch + 600000,
      if (c['operation'] == 'prepare_replacement') ...{
        'handoffId': c['requestId'],
        'expectedBindingId': c['expectedBindingId'],
        'expectedBindingVersion': c['expectedBindingVersion'],
        'expectedReceiverKeyId': c['expectedReceiverKeyId'],
        'retirementRequired': true,
      },
    };
Map<String, dynamic> _pendingReplacement(
  Map<String, dynamic> receipt,
  String phase,
) => {
  'handoffId': receipt['handoffId'],
  'targetInstallationId': receipt['installationId'],
  'targetGrantId': receipt['grantId'],
  'targetGrantVersion': receipt['grantVersion'],
  'targetCustodianAccountId': receipt['custodianAccountId'],
  'expectedScopeVersion': receipt['scopeVersion'],
  'expectedBindingId': receipt['expectedBindingId'],
  'expectedBindingVersion': receipt['expectedBindingVersion'],
  'expectedReceiverKeyId': receipt['expectedReceiverKeyId'],
  'expiresAt': receipt['deliveryExpiresAt'],
  'phase': phase,
  'subscriptionId': receipt['subscriptionId'],
};
Future<void> _selectNativeGroup(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('gateway-native-group-null:2')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Existing Collect group').last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Account ownership and pairing reason'),
    'Actual existing destination and owner phone verified',
  );
}

void _registerNativeSetupCases() {
  testWidgets(
    'dynamic native setup binds actual group account approved device and SIM; code is explicit and ephemeral',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage(),
          calls = <http.Request>[];
      Map<String, dynamic>? command, issuedReceipt;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          calls.add(request);
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET')
            return jsonResponse(_nativeDirectory());
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            command = jsonDecode(request.body) as Map<String, dynamic>;
            expect(command, containsPair('collectionId', groupId));
            expect(command, containsPair('receivingAccountId', accountId));
            expect(
              command,
              containsPair('installationId', _nativeInstallation),
            );
            expect(
              command,
              containsPair('custodianAccountId', _nativeCustodian),
            );
            expect(command, containsPair('grantId', _nativeGrant));
            expect(command, containsPair('expectedGrantVersion', 3));
            expect(command, containsPair('subscriptionId', 7));
            expect(command, containsPair('expectedScopeVersion', 2));
            expect(request.headers['idempotency-key'], command!['requestId']);
            expect(
              storage.values.values.single,
              contains(command!['requestId'] as String),
            );
            issuedReceipt = _nativeReceipt(command!);
            return jsonResponse(issuedReceipt!);
          }
          if (request.url.path.endsWith('/delivery'))
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': command!['requestId'],
              'bindingId': txId,
              'installationId': _nativeInstallation,
              'subscriptionId': 7,
              'pairingCode': 'e' * 64,
              'expiresAt': issuedReceipt!['deliveryExpiresAt'],
            });
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Issue receiving phone pairing'));
      await tester.tap(find.text('Issue receiving phone pairing'));
      await tester.pumpAndSettle();
      expect(command, isNotNull);
      expect(find.text('Show pairing code'), findsOneWidget);
      expect(find.text('e' * 64), findsNothing);
      expect(calls.where((r) => r.url.path.endsWith('/delivery')), isEmpty);
      await tester.tap(find.text('Show pairing code'));
      await tester.pumpAndSettle();
      expect(find.text('e' * 64), findsOneWidget);
      expect(storage.values.values.join(), isNot(contains('e' * 64)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('e' * 64), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(
        calls.where((r) => r.url.path.endsWith('/delivery')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'unconfirmed initial prepare cancels its original UUID without creating or retargeting a scope',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage(),
          posts = <http.Request>[];
      Map<String, dynamic>? original;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET')
            return jsonResponse(_nativeDirectory(prepared: false));
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            posts.add(request);
            original = jsonDecode(request.body) as Map<String, dynamic>;
            throw http.ClientException('Synthetic unknown transport');
          }
          if (request.url.path.endsWith('/cancel')) {
            posts.add(request);
            expect(jsonDecode(request.body), {'collectionId': groupId});
            expect(request.headers['idempotency-key'], original!['requestId']);
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': original!['requestId'],
              'operation': 'cancelled',
              'applied': false,
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'Receiving account',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Collect synthetic receiver · 123456 · unverified').last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prepare native group'));
      await tester.tap(find.text('Prepare native group'));
      await tester.pumpAndSettle();
      expect(original!['expectedScopeVersion'], 0);
      expect(original!['operation'], 'prepare');
      expect(posts, hasLength(1));
      expect(find.text('Submit original setup'), findsNothing);
      expect(find.text('Check original setup'), findsOneWidget);
      await tester.tap(find.text('Cancel unapplied setup'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(storage.values, isEmpty);
      expect(find.text('Prepare native group'), findsOneWidget);
      expect(find.text('Show pairing code'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'auto-registered phone choices bind the selected custodian without aliasing a shared grant',
    (tester) async {
      const otherCustodian = 'ac100000-0000-4000-8000-000000000009';
      final choices = [
        ...(_nativeDirectory()['installations'] as List)
            .cast<Map<String, dynamic>>(),
        {
          ...((_nativeDirectory()['installations'] as List).single
              as Map<String, dynamic>),
          'custodianAccountId': otherCustodian,
          'custodianName': 'Other current custodian',
        },
      ];
      Map<String, dynamic>? command;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET')
            return jsonResponse(_nativeDirectory(devices: choices));
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            command = jsonDecode(request.body) as Map<String, dynamic>;
            expect(command!['operation'], 'activate');
            expect(command!['custodianAccountId'], otherCustodian);
            expect(command!['grantId'], _nativeGrant);
            expect(command!.length, 11);
            return jsonResponse(_nativeReceipt(command!));
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      final select = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Approved receiving phone',
      );
      await tester.ensureVisible(select);
      await tester.tap(select);
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Other current custodian · $_nativeInstallation').last,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Issue receiving phone pairing'));
      await tester.tap(find.text('Issue receiving phone pairing'));
      await tester.pumpAndSettle();
      expect(command, isNotNull);
      expect(find.text('Show pairing code'), findsOneWidget);
      expect(
        find.textContaining('managed grant in BuriMunsi access first'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'paired replacement preserves scope until explicit lost-phone finalize and recovers its original request without replay',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage(),
          posts = <Map<String, dynamic>>[],
          deliveries = <String>[];
      Map<String, dynamic>? preparedReceipt, finalReceipt;
      var retired = false;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET')
            return jsonResponse(
              _nativeDirectory(
                paired: true,
                replacement: preparedReceipt == null
                    ? null
                    : _pendingReplacement(
                        preparedReceipt!,
                        retired ? 'retired' : 'prepared',
                      ),
              ),
            );
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            posts.add(body);
            expect(request.headers['idempotency-key'], body['requestId']);
            if (body['operation'] == 'prepare_replacement') {
              expect(body.length, 14);
              expect(body['expectedScopeVersion'], 2);
              expect(body['expectedBindingId'], _oldNativeBinding);
              expect(body['expectedReceiverKeyId'], _oldNativeKey);
              preparedReceipt = _nativeReceipt(body);
              expect(preparedReceipt!['scopeVersion'], 2);
              return jsonResponse(preparedReceipt!);
            }
            expect(body['operation'], 'finalize_replacement');
            expect(body.length, 7);
            expect(body['handoffId'], preparedReceipt!['requestId']);
            expect(body['expectedScopeVersion'], 2);
            finalReceipt = {
              'contractVersion': 1,
              'requestId': body['requestId'],
              'collectionId': groupId,
              'operation': 'finalize_replacement',
              'receivingAccountId': accountId,
              'scopeVersion': 3,
              'enabled': true,
              'bindingId': txId,
              'handoffId': body['handoffId'],
              'bindingVersion': 1,
              'retirementMethod': 'owner_lost',
              'reauthenticationRequired': true,
            };
            retired = true;
            throw http.ClientException('Synthetic lost finalize ACK');
          }
          if (request.method == 'GET' &&
              request.url.path.contains('/requests/')) {
            final id = request.url.path.split('/').last;
            final receipt = id == preparedReceipt?['requestId']
                ? preparedReceipt
                : finalReceipt;
            expect(receipt, isNotNull);
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': id,
              'found': true,
              'receipt': receipt,
            });
          }
          if (request.url.path.endsWith('/delivery')) {
            final id = request.url.path.split('/').reversed.skip(1).first;
            deliveries.add(id);
            expect(id, preparedReceipt!['requestId']);
            expect(id, isNot(finalReceipt?['requestId']));
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': id,
              'bindingId': txId,
              'installationId': _nativeInstallation,
              'subscriptionId': 7,
              'pairingCode': 'f' * 64,
              'expiresAt': preparedReceipt!['deliveryExpiresAt'],
              'handoffId': id,
              'retirementRequired': !retired,
              'phase': retired ? 'retired' : 'prepared',
            });
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prepare phone replacement'));
      await tester.tap(find.text('Prepare phone replacement'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(retired, isFalse);
      final finalize = find.widgetWithText(
        OutlinedButton,
        'Finalize prepared replacement without old phone',
      );
      expect(tester.widget<OutlinedButton>(finalize).onPressed, isNull);
      await tester.ensureVisible(find.text('Show pairing code'));
      await tester.tap(find.text('Show pairing code'));
      await tester.pumpAndSettle();
      expect(find.text('f' * 64), findsOneWidget);
      expect(storage.values.values.join(), isNot(contains('f' * 64)));
      await tester.ensureVisible(
        find.text('The old receiving phone is unavailable.'),
      );
      await tester.tap(find.text('The old receiving phone is unavailable.'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(finalize);
      await tester.tap(finalize);
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(find.text('Show pairing code'), findsNothing);
      expect(find.text('Check original setup'), findsOneWidget);
      expect(find.text('Submit original setup'), findsNothing);
      await tester.tap(find.text('Check original setup'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(2));
      expect(find.text('Show pairing code'), findsOneWidget);
      await tester.tap(find.text('Show pairing code'));
      await tester.pumpAndSettle();
      expect(deliveries, hasLength(2));
      expect(deliveries.toSet(), {preparedReceipt!['requestId']});
      expect(find.text('f' * 64), findsOneWidget);
      expect(storage.values.values.join(), isNot(contains('f' * 64)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'revoked old receiver history requires replacement and explicit lost-phone finalization without pretending it is paired',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage(),
          writes = <Map<String, dynamic>>[];
      Map<String, dynamic>? preparedReceipt;
      var retired = false, deliveries = 0;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET') {
            final directory = _nativeDirectory(
              receiverHistory: true,
              replacement: preparedReceipt == null
                  ? null
                  : _pendingReplacement(
                      preparedReceipt!,
                      retired ? 'retired' : 'prepared',
                    ),
            );
            final scope = (directory['scopes'] as List).single as Map;
            expect(scope['paired'], isFalse);
            if (!retired) {
              expect(scope['receiverKeyId'], _oldNativeKey);
              expect(scope['receiverInstallationId'], _oldNativeInstallation);
              expect(scope['bindingId'], _oldNativeBinding);
              expect(scope['version'], 2);
            }
            return jsonResponse(directory);
          }
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            writes.add(body);
            expect(request.headers['idempotency-key'], body['requestId']);
            expect(body['expectedScopeVersion'], 2);
            if (body['operation'] == 'prepare_replacement') {
              expect(body.length, 14);
              expect(body['expectedBindingId'], _oldNativeBinding);
              expect(body['expectedBindingVersion'], 1);
              expect(body['expectedReceiverKeyId'], _oldNativeKey);
              expect(body['installationId'], _nativeInstallation);
              expect(body['custodianAccountId'], _nativeCustodian);
              preparedReceipt = _nativeReceipt(body);
              expect(preparedReceipt!['scopeVersion'], 2);
              return jsonResponse(preparedReceipt!);
            }
            expect(body['operation'], 'finalize_replacement');
            expect(body.length, 7);
            expect(body['handoffId'], preparedReceipt!['requestId']);
            retired = true;
            return jsonResponse({
              'contractVersion': 1,
              'requestId': body['requestId'],
              'collectionId': groupId,
              'operation': 'finalize_replacement',
              'receivingAccountId': accountId,
              'scopeVersion': 3,
              'enabled': true,
              'bindingId': txId,
              'handoffId': body['handoffId'],
              'bindingVersion': 1,
              'retirementMethod': 'owner_lost',
              'reauthenticationRequired': true,
            });
          }
          if (request.url.path.endsWith('/delivery')) deliveries++;
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      await tester.pumpAndSettle();
      expect(find.text('Issue receiving phone pairing'), findsNothing);
      expect(writes, isEmpty);
      await tester.ensureVisible(find.text('Prepare phone replacement'));
      await tester.tap(find.text('Prepare phone replacement'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(retired, isFalse);
      expect(deliveries, 0);
      await tester.ensureVisible(find.text('Finish setup'));
      await tester.tap(find.text('Finish setup'));
      await tester.pumpAndSettle();
      expect(storage.values, isEmpty);
      expect(
        find.text(
          'Replacement is prepared for the selected phone. Confirm retirement of the old receiver before pairing the replacement.',
        ),
        findsOneWidget,
      );
      expect(find.text('Issue receiving phone pairing'), findsNothing);
      final finalize = find.widgetWithText(
        OutlinedButton,
        'Finalize prepared replacement without old phone',
      );
      expect(tester.widget<OutlinedButton>(finalize).onPressed, isNull);
      expect(writes, hasLength(1));
      await tester.ensureVisible(
        find.text('The old receiving phone is unavailable.'),
      );
      await tester.tap(find.text('The old receiving phone is unavailable.'));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(finalize).onPressed, isNotNull);
      await tester.ensureVisible(finalize);
      await tester.tap(finalize);
      await tester.pumpAndSettle();
      expect(writes.map((w) => w['operation']).toList(), [
        'prepare_replacement',
        'finalize_replacement',
      ]);
      expect(retired, isTrue);
      expect(deliveries, 0);
      expect(writes.last['requestId'], isNot(writes.first['requestId']));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'wrong target receipt and delivery retain original intent without exposing a code or resending activation',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      Map<String, dynamic>? command, receipt;
      var writes = 0;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET')
            return jsonResponse(_nativeDirectory());
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            writes++;
            command = jsonDecode(request.body) as Map<String, dynamic>;
            receipt = _nativeReceipt(command!);
            return jsonResponse({
              ...receipt!,
              'custodianAccountId': 'ac100000-0000-4000-8000-000000000099',
            });
          }
          if (request.method == 'GET' &&
              request.url.path.contains('/requests/'))
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': command!['requestId'],
              'found': true,
              'receipt': receipt,
            });
          if (request.url.path.endsWith('/delivery'))
            return jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': command!['requestId'],
              'bindingId': txId,
              'installationId': 'ac100000-0000-4000-8000-000000000099',
              'subscriptionId': 7,
              'pairingCode': 'a' * 64,
              'expiresAt': receipt!['deliveryExpiresAt'],
            });
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Issue receiving phone pairing'));
      await tester.tap(find.text('Issue receiving phone pairing'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('Show pairing code'), findsNothing);
      expect(storage.values.values.single, contains(command!['requestId']));
      await tester.tap(find.text('Check original setup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show pairing code'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(find.text('a' * 64), findsNothing);
      expect(storage.values.values.join(), isNot(contains('a' * 64)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
  testWidgets(
    'background during code delivery discards its late reply until a new explicit foreground reveal',
    (tester) async {
      final storage = MemoryAdminPendingAttemptStorage();
      Map<String, dynamic>? command, receipt;
      var deliveryCalls = 0, writes = 0;
      final result = await pump(
        tester,
        nativeOwner: true,
        permissions: _nativePermissions,
        pendingStorage: storage,
        respond: (request) async {
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'GET') {
            return jsonResponse(_nativeDirectory());
          }
          if (request.url.path.endsWith('/momo/native-setup') &&
              request.method == 'POST') {
            writes++;
            command = jsonDecode(request.body) as Map<String, dynamic>;
            receipt = _nativeReceipt(command!);
            return jsonResponse(receipt!);
          }
          if (request.url.path.endsWith('/delivery')) {
            deliveryCalls++;
            final response = jsonResponse({
              'contractVersion': 1,
              'collectionId': groupId,
              'requestId': command!['requestId'],
              'bindingId': txId,
              'installationId': _nativeInstallation,
              'subscriptionId': 7,
              'pairingCode': 'b' * 64,
              'expiresAt': receipt!['deliveryExpiresAt'],
            });
            if (deliveryCalls == 1) {
              return Future<http.Response>.delayed(
                const Duration(milliseconds: 100),
                () => response,
              );
            }
            return response;
          }
          return http.Response('{}', 404);
        },
      );
      await openGatewayTools(tester);
      await _selectNativeGroup(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Receiving SIM subscription ID'),
        '7',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Issue receiving phone pairing'));
      await tester.tap(find.text('Issue receiving phone pairing'));
      await tester.pumpAndSettle();
      final retainedIntent = Map.of(storage.values);
      await tester.tap(find.text('Show pairing code'));
      await tester.pump();
      expect(deliveryCalls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pumpAndSettle();
      expect(find.text('b' * 64), findsNothing);
      expect(storage.values, retainedIntent);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(deliveryCalls, 1);
      expect(find.text('b' * 64), findsNothing);
      await tester.tap(find.text('Show pairing code'));
      await tester.pumpAndSettle();
      expect(deliveryCalls, 2);
      expect(writes, 1);
      expect(find.text('b' * 64), findsOneWidget);
      expect(storage.values, retainedIntent);
      expect(storage.values.values.join(), isNot(contains('b' * 64)));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      result.dispose();
    },
  );
}
