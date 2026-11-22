import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Apple-platform icon font is included in the app bundle', () async {
    final font = await rootBundle.load(
      'packages/cupertino_icons/assets/CupertinoIcons.ttf',
    );
    expect(font.lengthInBytes, greaterThan(1000));
    // TrueType/OpenType font signatures, not an HTML fallback/error body.
    expect(font.getUint32(0), anyOf(0x00010000, 0x4f54544f));
  });
}
