import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'admin_governed_settings_checkpoint.dart';
import 'admin_governed_settings_models.dart';

@JS('window.localStorage')
external _Storage get _storage;
extension type _Storage(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
}

@JS('navigator.locks')
external _Locks? get _locks;
extension type _Locks(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(
    String name,
    _LockOptions options,
    JSFunction callback,
  );
}

@JS('AbortController')
extension type _AbortController._(JSObject _) implements JSObject {
  external factory _AbortController();
  external JSObject get signal;
  external void abort();
}

extension type _LockOptions._(JSObject _) implements JSObject {
  external factory _LockOptions({String mode, JSObject signal});
}

class _SettingsStore implements AdminSettingsCheckpointStore {
  static const _lockBound = Duration(seconds: 5);
  Future<T> _exclusive<T>(String owner, T Function() work) async {
    final manager = _locks;
    if (manager == null) governedSettingsInvalid('recovery lock');
    final abort = _AbortController(), elapsed = Stopwatch()..start();
    var closed = false, ran = false;
    late T result;
    Object? failure;
    StackTrace? failureStack;
    void close() {
      closed = true;
      abort.abort();
    }

    final timer = Timer(_lockBound, close);
    try {
      await manager
          .request(
            '${_prefix(owner)}exclusive',
            _LockOptions(mode: 'exclusive', signal: abort.signal),
            ((JSAny? lock) {
              // Preserve typed Dart refusal across JS promise callbacks.
              ran = true;
              try {
                if (closed || elapsed.elapsed >= _lockBound || lock == null) {
                  governedSettingsInvalid('recovery lock');
                }
                result = work();
              } catch (error, stack) {
                failure = error;
                failureStack = stack;
              }
              return null;
            }).toJS,
          )
          .toDart
          .timeout(
            _lockBound,
            onTimeout: () {
              close();
              governedSettingsInvalid('recovery lock');
            },
          );
      if (closed || !ran) governedSettingsInvalid('recovery lock');
      if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
      return result;
    } finally {
      timer.cancel();
      close();
    }
  }

  String _prefix(String owner) =>
      'collect.admin.settings.recovery.v2.${settingsDigest(owner)}.';
  String _key(AdminSettingsBookmark original) =>
      '${_prefix(original.ownerDigest)}${original.requestId}';
  @override
  List<String> read(String ownerDigest) {
    final prefix = _prefix(ownerDigest), rows = <String>[];
    final length = _storage.length;
    if (length > 10000) governedSettingsInvalid('storage index');
    final originals = <String>{}, markers = <String>{};
    for (var i = 0; i < length; i++) {
      final key = _storage.key(i);
      if (key == null || !key.startsWith(prefix)) continue;
      final suffix = key.substring(prefix.length);
      if (suffix.endsWith('.resolution')) {
        settingsUuid(suffix.substring(0, suffix.length - 11));
        markers.add(key.substring(0, key.length - 11));
      } else {
        settingsUuid(suffix);
        originals.add(key);
      }
    }
    if (!originals.containsAll(markers)) {
      governedSettingsInvalid('orphaned resolution');
    }
    for (final key in originals) {
      final raw = _storage.getItem(key);
      if (raw == null) governedSettingsInvalid('bookmark storage');
      final original = AdminSettingsBookmark.parse(raw, ownerDigest);
      if (key != _key(original)) governedSettingsInvalid('bookmark key');
      final marker = _storage.getItem('$key.resolution');
      if (marker == null) {
        rows.add(raw);
        if (rows.length > 50) governedSettingsInvalid('pending request limit');
      } else {
        if (marker.length > 1024) governedSettingsInvalid('resolution marker');
        final m = settingsObject(jsonDecode(marker), {
          'version',
          'original_sha256',
          'status',
        });
        if (m['version'] != 2 ||
            m['version'] is! int ||
            m['original_sha256'] != original.digest ||
            !{
              'recorded',
              'not_recorded_after_deadline',
              'never_submitted',
            }.contains(m['status'])) {
          governedSettingsInvalid('resolution marker');
        }
      }
    }
    return rows;
  }

  @override
  Future<void> write(AdminSettingsBookmark original) =>
      _exclusive(original.ownerDigest, () {
        if (read(original.ownerDigest).isNotEmpty) {
          throw const AdminSettingsPendingOriginal();
        }
        final key = _key(original);
        if (_storage.getItem(key) != null) {
          governedSettingsInvalid('original already retained');
        }
        _storage.setItem(key, original.encode());
        final pending = read(original.ownerDigest);
        if (pending.length != 1 || pending.single != original.encode()) {
          governedSettingsInvalid('bookmark acknowledgement');
        }
      });
  @override
  Future<void> resolve(AdminSettingsBookmark original, String resolution) =>
      _exclusive(original.ownerDigest, () {
        if (!{
          'recorded',
          'not_recorded_after_deadline',
          'never_submitted',
        }.contains(resolution)) {
          governedSettingsInvalid('resolution');
        }
        final key = _key(original);
        if (_storage.getItem(key) != original.encode()) {
          governedSettingsInvalid('original bookmark');
        }
        final marker = jsonEncode({
          'version': 2,
          'original_sha256': original.digest,
          'status': resolution,
        });
        final previous = _storage.getItem('$key.resolution');
        if (previous != null && previous != marker) {
          governedSettingsInvalid('immutable resolution');
        }
        _storage.setItem('$key.resolution', marker);
        if (_storage.getItem('$key.resolution') != marker) {
          governedSettingsInvalid('resolution acknowledgement');
        }
      });
}

AdminSettingsCheckpointStore createSettingsCheckpointStore() =>
    _SettingsStore();
