import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:collect_app/admin/core/admin_auth_guard.dart';
import 'package:collect_app/admin/core/admin_roster_dialog.dart';
import 'package:collect_app/admin/core/admin_roster_import.dart';
import 'package:collect_app/admin/core/admin_repository_base.dart';
import 'package:collect_app/app/env/app_env.dart';
import 'package:collect_app/app/theme/collect_theme.dart';
import 'package:collect_app/core/supabase/supabase_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

// A loopback-only acceptance entrypoint. Release entrypoints never import it.
// Authentication uses production Supabase.initialize and browser Auth options;
// roster interactions use the actual gateway, draft and Admin dialog.
final _homeKey = GlobalKey<_HomeState>();
final _navigatorKey = GlobalKey<NavigatorState>();
final _status = (web.document.createElement('pre') as web.HTMLElement)
  ..id = 'roster-fixture-status';

Future<void> main() async {
  final origin = web.window.location.origin;
  if (Uri.parse(origin).host != '127.0.0.1') {
    throw StateError('loopback_fixture_required');
  }
  _status.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..zIndex = '10000'
    ..pointerEvents = 'none';
  web.document.body!.append(_status);
  _status.textContent = jsonEncode({
    'boot': 'initializing',
    'authenticated': false,
  });
  WidgetsFlutterBinding.ensureInitialized();
  final SemanticsHandle semantics = SemanticsBinding.instance.ensureSemantics();
  final env = AppEnv(
    supabaseUrl: origin,
    supabaseAnonKey: 'sb_publishable_synthetic_loopback_only',
    publicUrl: origin,
    adminAppUrl: origin,
    enableSmsReader: false,
    enableAndroidSmsAccess: false,
    enableAdminPanel: true,
    enableAdminDevTools: false,
    authCaptchaEnabled: false,
    authCaptchaProvider: '',
    authCaptchaSiteKey: '',
  );
  try {
    final client = (await createSupabaseClientFromEnvironment(
      environment: env,
    ))!;
    runApp(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          theme: CollectTheme.light(),
          home: _Home(key: _homeKey, client: client, semantics: semantics),
        ),
      ),
    );
    final refresh = web.HTMLButtonElement()
      ..id = 'refresh-synthetic-operator-authority'
      ..textContent = 'Refresh synthetic operator authority';
    refresh.style
      ..position = 'fixed'
      ..right = '0'
      ..bottom = '0'
      ..zIndex = '10000';
    refresh.onclick =
        ((web.MouseEvent _) => _homeKey.currentState?._refreshIdentity()).toJS;
    web.document.body!.append(refresh);
  } catch (_) {
    semantics.dispose();
    _status.textContent = jsonEncode({
      'boot': 'cleanup_denied',
      'authenticated': false,
    });
  }
}

class _Home extends ConsumerStatefulWidget {
  const _Home({required this.client, required this.semantics, super.key});
  final SupabaseClient client;
  final SemanticsHandle semantics;
  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  StreamSubscription<AuthState>? _auth;
  Timer? _observer;
  AdminRosterDraft? _draft;
  final List<String> _events = [];
  String _outcome = 'none';

  @override
  void initState() {
    super.initState();
    _auth = widget.client.auth.onAuthStateChange.listen(
      (event) {
        _events.add(event.event.name);
        if (mounted) setState(_paint);
      },
      onError: (_) {
        _events.add('redacted_auth_error');
        if (mounted) setState(_paint);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _paint());
    _observer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      // Observe the actual production helper's mounted dialog. This fixture
      // never supplies a substitute gateway/scope or changes its draft state.
      AdminRosterDraft? found;
      void visit(Element element) {
        if (element.widget case AdminRosterImportDialog(:final draft)) {
          found = draft;
        }
        element.visitChildElements(visit);
      }

      _navigatorKey.currentContext?.visitChildElements(visit);
      if (!identical(_draft, found)) {
        _draft?.removeListener(_paint);
        _draft = found;
        _draft?.addListener(_paint);
      }
      _paint();
    });
  }

  void _paint() {
    final draft = _draft;
    _status.textContent = jsonEncode({
      'boot': 'ready',
      'authenticated': widget.client.auth.currentSession != null,
      'session_id': adminSessionKey(
        widget.client.auth.currentSession,
      )?.sessionId,
      'identity_ready':
          ref.read(adminIdentityProvider).asData?.value != null &&
          !ref.read(adminIdentityProvider).isLoading,
      'events': _events,
      'dialog': draft != null,
      'invalidated': draft?.invalidated ?? false,
      'busy': draft?.busy ?? false,
      'preview': draft?.preview != null,
      'can_submit': draft?.preview?.canSubmit ?? false,
      'can_commit': draft?.canCommit ?? false,
      'edited': draft?.edited ?? false,
      'affirmed': draft?.affirmed ?? false,
      'fresh_affirmed': draft?.freshRecoveryAffirmed ?? false,
      'interrupted_count': draft?.interruptedImports.length ?? 0,
      'inspected': draft?.interruptedInspection != null,
      'transfer_pending': draft?.transferOutcomePending ?? false,
      'row_count': draft?.rows.length ?? 0,
      'error_code': draft?.errorCode,
      'outcome': _outcome,
    });
  }

  Future<void> _signIn(String token) async {
    try {
      await widget.client.auth.verifyOTP(
        phone: '+250788989001',
        token: token,
        type: OtpType.sms,
      );
    } catch (_) {
      _events.add('redacted_sign_in_error');
    }
    if (mounted) setState(_paint);
  }

  Future<void> _openRoster() async {
    if (_draft != null || widget.client.auth.currentSession == null) return;
    _outcome = 'pending';
    await createAdminAssistedGroup(
      context,
      ref,
      onDone: () {
        _outcome = 'acknowledged';
        _paint();
      },
    );
    _draft = null;
    if (_outcome == 'pending') _outcome = 'closed';
    if (mounted) setState(_paint);
  }

  void _refreshIdentity() => ref.invalidate(adminIdentityProvider);

  @override
  void dispose() {
    unawaited(_auth?.cancel());
    _observer?.cancel();
    _draft?.removeListener(_paint);
    widget.semantics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(adminIdentityProvider);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Synthetic local roster acceptance'),
            FilledButton(
              onPressed: () => _signIn('A'),
              child: const Text('Sign in synthetic A'),
            ),
            FilledButton(
              onPressed: () => _signIn('B'),
              child: const Text('Sign in synthetic B'),
            ),
            OutlinedButton(
              onPressed: () async {
                await widget.client.auth.refreshSession();
                _paint();
              },
              child: const Text('Refresh synthetic sign-in'),
            ),
            OutlinedButton(
              onPressed: () async {
                await widget.client.auth.signOut();
                _paint();
              },
              child: const Text('Sign out synthetic sign-in'),
            ),
            FilledButton(
              onPressed:
                  widget.client.auth.currentSession == null ||
                      identity.isLoading ||
                      identity.asData?.value == null
                  ? null
                  : _openRoster,
              child: const Text('Open production roster'),
            ),
          ],
        ),
      ),
    );
  }
}
