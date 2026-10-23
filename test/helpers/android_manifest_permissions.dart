import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _toolsNamespace = 'http://schemas.android.com/tools';

/// Source permission declarations, excluding real manifest-merger removals.
/// Merged artifact/device acceptance remains a separate release check.
Set<String> requestedAndroidPermissions(String source) =>
    _permissions(source, removed: false);

Set<String> removedAndroidPermissions(String source) =>
    _permissions(source, removed: true);

Set<String> _permissions(String source, {required bool removed}) {
  final document = XmlDocument.parse(source);
  final names = <String>{};
  for (final element in document.descendants.whereType<XmlElement>()) {
    if (!const {
      'uses-permission',
      'uses-permission-sdk-23',
      'uses-permission-sdk-m',
    }.contains(element.name.local)) {
      continue;
    }
    final removal = const {
      'remove',
      'removeAll',
    }.contains(element.getAttribute('node', namespace: _toolsNamespace));
    if (removal != removed) continue;
    final name = element.getAttribute('name', namespace: _androidNamespace);
    if (name == null || name.isEmpty) {
      throw const FormatException('Manifest permission has no Android name.');
    }
    names.add(name);
  }
  return names;
}
