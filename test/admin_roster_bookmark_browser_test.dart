@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:collect_app/admin/core/admin_roster_checkpoint.dart';
import 'package:collect_app/admin/core/admin_roster_models.dart';

void main() {
  test(
    'actual browser sessionStorage retains only bounded schema references across adapter recreation',
    () {
      final first = browserRosterBookmarkStore()!;
      first.clear();
      final bookmark = RosterBookmark(
        ownerDigest: rosterTextDigest('synthetic actor session'),
        uploadRequestId: '99690000-0000-4000-8000-000000000001',
        sourceSha256: 'a' * 64,
      );
      first.write(jsonEncode(bookmark.toJson()));
      final second = browserRosterBookmarkStore()!;
      final restored = RosterBookmark.parse(
        second.read()!,
        bookmark.ownerDigest,
      );
      expect(restored.uploadRequestId, bookmark.uploadRequestId);
      expect(
        jsonDecode(second.read()!).keys.toSet(),
        bookmark.toJson().keys.toSet(),
      );
      second.clear();
      expect(first.read(), isNull);
    },
  );
}
