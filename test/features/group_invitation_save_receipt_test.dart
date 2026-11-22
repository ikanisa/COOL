// Actual fork Android MethodChannel handling is deliberately exercised here.
// ignore_for_file: implementation_imports
import 'package:collect_app/features/collections/group_invitation_transport.dart';
import 'package:file_saver/src/models/file.model.dart';
import 'package:file_saver/src/platform_handler/platform_handler_all.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('file_saver');
  final calls = <MethodCall>[];
  String? receipt;
  bool throwPlatformError = false;
  setUp(() {
    calls.clear();
    throwPlatformError = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (throwPlatformError) {
            throw PlatformException(
              code: 'save_failed',
              message: 'synthetic secret',
            );
          }
          return receipt;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  for (final value in <String?>[
    null,
    '',
    'Error While Saving Filesynthetic secret',
    'Something went wrong, please report the issue synthetic secret',
    'relative/group-qr.png',
    'Downloads',
    '/private/other-qr.png',
    '/private/\ngroup-qr.png',
  ]) {
    test(
      'actual Android save receipt rejects ${value?.length ?? 'null'}:${value?.substring(0, value.length > 8 ? 8 : value.length)}',
      () async {
        receipt = value;
        await expectLater(
          const AndroidReceiptTransport().saveQr(
            Uint8List.fromList([1, 2, 3]),
            'group-qr',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe error',
              'QR save did not confirm the requested file.',
            ),
          ),
        );
        expect(calls, hasLength(1));
        expect(calls.single.method, 'saveFile');
        final args = calls.single.arguments as Map;
        expect(args['name'], 'group-qr');
        expect(args['bytes'], [1, 2, 3]);
        expect(args['fileExtension'], '.png');
        expect(args['mimeType'], 'image/png');
      },
    );
  }
  test(
    'actual Android absolute requested PNG receipt remains accepted once',
    () async {
      receipt =
          '/storage/emulated/0/Android/data/app.cool.mobile/files/group-qr.png';
      await const AndroidReceiptTransport().saveQr(
        Uint8List.fromList([1]),
        'group-qr',
      );
      expect(calls, hasLength(1));
    },
  );
  test(
    'actual Android channel failure is propagated once without retry',
    () async {
      throwPlatformError = true;
      await expectLater(
        const AndroidReceiptTransport().saveQr(
          Uint8List.fromList([1]),
          'group-qr',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(calls, hasLength(1));
    },
  );
}

class AndroidReceiptTransport extends GroupInvitationTransport {
  const AndroidReceiptTransport();
  @override
  Future<String> saveQrFile(Uint8List bytes, String filename) =>
      PlatformHandlerAll().saveFileForAndroid(
        FileModel(
          name: filename,
          bytes: bytes,
          fileExtension: '.png',
          mimeType: 'image/png',
          includeExtension: true,
        ),
      );
  @override
  Future<Uint8List> renderQr(String link) async =>
      Uint8List.fromList([1, 2, 3]);
}
