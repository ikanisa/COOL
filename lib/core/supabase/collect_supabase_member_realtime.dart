import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:realtime_client/realtime_client.dart';

import '../cloudflare/collect_cloudflare_client.dart';
import 'collect_supabase_member_socket_stub.dart'
    if (dart.library.io) 'collect_supabase_member_socket_io.dart';

const _project = 'https://rrlduytparvsjfmegalh.supabase.co';
final _uuid = RegExp(r'^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$');

/// Receives opaque native member hints only. Auth, persistence and all reads
/// remain owned by CollectCloudflareClient/the existing member repository.
class CollectSupabaseMemberRealtime {
  CollectSupabaseMemberRealtime({
    required CollectCloudflareClient client,
    required this.onReconcile,
    required this.onConnectionChanged,
    this.onForegroundChanged,
    this.transport,
    this.observeLifecycle = true,
    this.joinTimeout = const Duration(seconds: 10),
    this.heartbeatInterval = const Duration(seconds: 25),
    int Function(int)? retryAfterMs,
  }) : _client = client,
       _retryAfterMs = retryAfterMs ?? _retryDelay,
       _owner = client.auth.currentSession?.user.id,
       _subject = client.auth.currentSession?.authSubject,
       _sid = client.auth.currentSession?.claims['session_id'] as String?;

  final CollectCloudflareClient _client;
  final void Function() onReconcile;
  final void Function(bool) onConnectionChanged;
  final void Function(bool)? onForegroundChanged;
  final WebSocketTransport? transport;
  final int Function(int) _retryAfterMs;
  final bool observeLifecycle;
  final Duration joinTimeout, heartbeatInterval;
  final String? _owner, _subject, _sid;
  final Set<String> _seen = {};
  // Owned by start()/dispose(); cancellation is awaited before disposal completes.
  // ignore: cancel_subscriptions
  StreamSubscription<CollectAuthState>? _auth;
  // _fence transfers this subscription into the awaited _closing chain.
  // ignore: cancel_subscriptions
  StreamSubscription<RealtimeHeartbeatStatus>? _heartbeat;
  AppLifecycleListener? _lifecycle;
  _SilentRealtimeClient? _socket;
  CollectMemberSocketTransport? _ownedTransport;
  Timer? _retry, _join, _expiry;
  Future<void> _closing = Future.value();
  int _epoch = 0, _failures = 0;
  bool _disposed = false,
      _departed = false,
      _started = false,
      _foreground = true;
  bool _joined = false;
  String? _token;
  bool get isConnected => _joined && _current && _foreground;
  bool get isForeground => _foreground;
  bool get ownsCurrentSession => _current;

  bool get _current {
    final session = _client.auth.currentSession;
    return !_disposed &&
        !_departed &&
        session != null &&
        _owner != null &&
        session.user.id == _owner &&
        session.authSubject == _subject &&
        session.claims['session_id'] == _sid;
  }

  bool get _eligible {
    final session = _client.auth.currentSession;
    if (session == null) return false;
    return _current &&
        _foreground &&
        _client.auth.surface == 'member' &&
        _client.supabaseConfiguration?.project.origin == _project &&
        session.usesMappedAuthUser &&
        session.user.authUserId == _subject &&
        session.claims['sub'] == _subject &&
        session.claims['iss'] == '$_project/auth/v1' &&
        session.claims['aud'] == 'authenticated' &&
        session.claims['role'] == 'authenticated' &&
        _uuid.hasMatch(_subject ?? '') &&
        _uuid.hasMatch(_sid ?? '') &&
        !session.isExpired;
  }

  static int _retryDelay(int failures) {
    const delays = [1000, 2000, 4000, 8000, 16000, 30000];
    final base = delays[(failures - 1).clamp(0, delays.length - 1)];
    return min(30000, base + Random().nextInt(max(1, base ~/ 4)));
  }

  void _notify(void Function() callback) {
    try {
      callback();
    } catch (_) {
      /* Never expose callback errors. */
    }
  }

  void _connected(bool value) {
    if (_joined == value) return;
    _joined = value;
    _notify(() => onConnectionChanged(value));
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    _auth = _client.auth.onAuthStateChange.listen((_) {
      if (!_current) {
        _departed = true;
        _fence();
        return;
      }
      if (_client.auth.currentSession?.accessToken != _token) _replace();
    });
    if (observeLifecycle) {
      _lifecycle = AppLifecycleListener(onStateChange: handleLifecycle);
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null) handleLifecycle(state);
    }
    if (_foreground) _replace();
  }

  /// Also allows deterministic lifecycle fixtures without a device observer.
  void handleLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    final foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _notify(() => onForegroundChanged?.call(foreground));
    _fence();
    if (foreground && _current) {
      _notify(onReconcile);
      _replace();
    }
  }

  void _fence() {
    ++_epoch;
    _retry?.cancel();
    _retry = null;
    _join?.cancel();
    _join = null;
    _expiry?.cancel();
    _expiry = null;
    _connected(false);
    final heartbeat = _heartbeat;
    _heartbeat = null;
    final socket = _socket;
    _socket = null;
    socket?.retire(); // Synchronous before any cleanup await.
    _ownedTransport?.close();
    _ownedTransport = null;
    _closing = _closing
        .then((_) async {
          await heartbeat?.cancel();
          if (socket != null) await socket.closeOwned();
        })
        .catchError((Object _) {
          /* Fences remain closed on cleanup failure. */
        });
  }

  void _replace() {
    _fence();
    if (!_current || !_foreground) return;
    _failures = 0;
    _token = _client.auth.currentSession?.accessToken;
    _seen.clear();
    final epoch = _epoch;
    unawaited(_open(epoch));
  }

  bool _live(int epoch) =>
      _epoch == epoch &&
      _eligible &&
      _client.auth.currentSession?.accessToken == _token;

  Future<void> _open(int epoch) async {
    await _closing;
    if (!_live(epoch)) {
      if (_current &&
          _foreground &&
          _client.auth.currentSession?.isExpired == true) {
        await _refreshExpired();
      }
      return;
    }
    final token = _token!;
    final project = _client.supabaseConfiguration!;
    final owned = transport == null
        ? CollectMemberSocketTransport(connectTimeout: joinTimeout)
        : null;
    _ownedTransport = owned;
    final socket = _SilentRealtimeClient(
      project.project.replace(scheme: 'wss', path: '/realtime/v1').toString(),
      project.publishableKey,
      transport: transport ?? owned!.connect,
      timeout: joinTimeout,
      heartbeatIntervalMs: heartbeatInterval.inMilliseconds,
      onFault: () => _lost(epoch),
      decode: (raw) => _decode(raw, epoch),
    );
    _socket = socket;
    try {
      await socket.setAuth(token);
      if (!_live(epoch)) return;
      _heartbeat = socket.onHeartbeat.listen((status) {
        if (!_live(epoch)) return;
        if (status == RealtimeHeartbeatStatus.error ||
            status == RealtimeHeartbeatStatus.timeout) {
          _lost(epoch);
        }
      });
      socket.onError((_) => _lost(epoch));
      socket.onClose((_) => _lost(epoch));
      _join = Timer(joinTimeout, () => _lost(epoch));
      final expiration = _client.auth.currentSession!.claims['exp'] as int;
      _expiry = Timer(
        Duration(
          seconds: max(
            0,
            expiration - DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ),
        ),
        () {
          if (_epoch == epoch && _current) {
            _fence();
            unawaited(_refreshExpired());
          }
        },
      );
      socket
          .channel(
            'collect:member:$_subject:$_sid',
            const RealtimeChannelConfig(private: true),
          )
          .onBroadcast(
            event: 'invalidate',
            callback: (wrapper) {
              if (!_live(epoch) || !_joined) return;
              final payload = wrapper['payload'] as Map<String, dynamic>;
              final id = payload['id'] as String;
              if (!_seen.add(id)) return;
              if (_seen.length > 256) {
                _seen.clear();
                _notify(onReconcile);
                _lost(epoch);
                return;
              }
              _notify(onReconcile);
            },
          )
          .subscribe((status, _) {
            if (!_live(epoch)) return;
            if (status == RealtimeSubscribeStatus.subscribed) {
              _join?.cancel();
              _join = null;
              _failures = 0;
              _seen.clear();
              _connected(true);
              _notify(onReconcile);
            } else {
              _lost(epoch);
            }
          }, joinTimeout);
    } catch (_) {
      _lost(epoch);
    }
  }

  Map<String, dynamic> _decode(Object raw, int epoch) {
    try {
      if (raw is! String ||
          raw.length > 4096 ||
          utf8.encode(raw).length > 4096) {
        throw const FormatException();
      }
      final row = jsonDecode(raw);
      if (row is! Map<String, dynamic> ||
          row['topic'] is! String ||
          row['event'] is! String ||
          row['payload'] is! Map<String, dynamic> ||
          (row['ref'] != null && row['ref'] is! String) ||
          (row['join_ref'] != null && row['join_ref'] is! String)) {
        throw const FormatException();
      }
      if (row.keys.any(
            (key) => !const {
              'topic',
              'event',
              'payload',
              'ref',
              'join_ref',
            }.contains(key),
          ) ||
          !{
            'phoenix',
            'realtime:collect:member:$_subject:$_sid',
          }.contains(row['topic'])) {
        throw const FormatException();
      }
      final event = row['event'];
      final payload = row['payload'] as Map<String, dynamic>;
      if (event == 'phx_reply') {
        if (!const {'ok', 'error', 'timeout'}.contains(payload['status']) ||
            payload['response'] is! Map<String, dynamic>) {
          throw const FormatException();
        }
      } else if (event == 'broadcast') {
        final data = payload['payload'];
        if (row['topic'] != 'realtime:collect:member:$_subject:$_sid' ||
            payload.length != 3 ||
            payload['type'] != 'broadcast' ||
            payload['event'] != 'invalidate' ||
            data is! Map<String, dynamic> ||
            data.length != 2 ||
            data['v'] is! int ||
            data['v'] != 1 ||
            data['id'] is! String ||
            !_uuid.hasMatch(data['id'] as String)) {
          throw const FormatException();
        }
      } else if (!const {'phx_close', 'phx_error', 'system'}.contains(event)) {
        throw const FormatException();
      }
      return row;
    } catch (_) {
      scheduleMicrotask(() {
        if (_live(epoch)) {
          _notify(onReconcile);
          _lost(epoch);
        }
      });
      throw const FormatException('Member updates unavailable');
    }
  }

  void _lost(int epoch) {
    if (_epoch != epoch || _disposed) return;
    _fence();
    if (!_eligible) return;
    final nextEpoch = _epoch;
    final delay = _retryAfterMs(++_failures).clamp(1, 30000);
    // This adapter is the reconnect owner. The retired SDK cannot reconnect.
    unawaited(
      _closing.then((_) {
        if (!_live(nextEpoch)) return;
        _retry = Timer(Duration(milliseconds: delay), () {
          _retry = null;
          if (_live(nextEpoch)) unawaited(_open(nextEpoch));
        });
      }),
    );
  }

  Future<void> _refreshExpired() async {
    if (!_current || !_foreground) return;
    final token = _client.auth.currentSession!.accessToken;
    try {
      await _client.auth.refreshSession();
    } catch (_) {
      if (_current &&
          _client.auth.currentSession?.accessToken == token &&
          _client.auth.currentSession?.isExpired == true) {
        try {
          await _client.auth.clearLocalSession();
        } catch (_) {}
      }
    }
  }

  /// A current HTTP denial is resolved only by authoritative reads/new Auth.
  void authorityDenied() {
    if (!_disposed) _fence();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fence();
    _lifecycle?.dispose();
    _lifecycle = null;
    await _auth?.cancel();
    _auth = null;
    await _closing;
    _token = null;
    _seen.clear();
  }
}

/// Exact2.13.0 direct constructor logs contain only public endpoint/params.
/// All later SDK/channel logging is virtual through log(): discard it BEFORE
/// Logger receives token-bearing data (also passed in LogRecord.error).
class _SilentRealtimeClient extends RealtimeClient {
  _SilentRealtimeClient(
    super.endPoint,
    String publicKey, {
    super.transport,
    required super.timeout,
    required super.heartbeatIntervalMs,
    required this.onFault,
    required RealtimeDecode decode,
  }) : super(
         params: {'apikey': publicKey},
         version: RealtimeProtocolVersion.v1,
         decode: decode,
       );
  final void Function() onFault;
  bool _retired = false;
  void retire() {
    _retired = true;
  }

  @override
  void log([String? kind, String? message, dynamic data, dynamic level]) {}
  @override
  Future<void> connect() async {
    if (_retired) return;
    // Exact pinned2.13 lifecycle boundary: prevent departed SDK retry timers.
    try {
      // ignore: invalid_use_of_internal_member
      await super.connect();
    } catch (_) {
      if (!_retired) onFault();
    }
  }

  @override
  String? push(message) {
    if (_retired) return null;
    try {
      return super.push(message);
    } catch (_) {
      onFault();
      return null;
    }
  }

  @override
  void onConnMessage(Object rawMessage) {
    if (_retired) return;
    try {
      super.onConnMessage(rawMessage);
    } catch (_) {
      onFault();
    }
  }

  @override
  Future<void> sendHeartbeat() async {
    if (_retired) return;
    // Exact pinned2.13 timer has no catch; contain its async sink/token errors.
    try {
      // ignore: invalid_use_of_internal_member
      await super.sendHeartbeat();
    } catch (_) {
      if (!_retired) onFault();
    }
  }

  Future<void> closeOwned() async {
    try {
      await disconnect();
    } finally {
      await removeAllChannels();
      sendBuffer.clear();
      accessToken = null;
    }
  }
}
