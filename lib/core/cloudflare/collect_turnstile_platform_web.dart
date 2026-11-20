import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'collect_cloudflare_types.dart';
import 'collect_turnstile_contract.dart';

({String attempt, Completer<Object?> result, web.HTMLDialogElement dialog})?
_active;

bool challengeHasForeground() =>
    web.document.visibilityState == 'visible' && web.document.hasFocus();

bool challengeOwnsInactiveFocus(String attemptId) {
  final active = _active;
  return active?.attempt == attemptId &&
      active!.dialog.open &&
      challengeHasForeground() &&
      active.dialog.contains(web.document.activeElement);
}

Future<Object?> acquireChallenge(String attemptId, {Uri? endpoint}) async {
  if (_active != null || web.document.body == null) {
    throw const CollectAuthException(
      'Security verification is unavailable.',
      code: 'captcha_unavailable',
    );
  }
  final url = collectChallengeUri(
    attemptId,
    web.window.location.origin,
    endpoint: endpoint,
  );
  final result = Completer<Object?>();
  final previousFocus = web.document.activeElement;
  final dialog = web.document.createElement('dialog') as web.HTMLDialogElement;
  _active = (attempt: attemptId, result: result, dialog: dialog);
  dialog.setAttribute('aria-label', 'Verify your sign-in');
  dialog.style.cssText =
      'padding:16px;border:0;border-radius:24px;'
      'width:min(420px,calc(100vw - 32px));max-height:calc(100dvh - 32px);'
      'box-sizing:border-box;background:#202024;color:#fff;'
      'font-family:Inter,system-ui,sans-serif;';
  final frame = web.document.createElement('iframe') as web.HTMLIFrameElement;
  frame
    ..title = 'Collect security verification'
    ..src = url.toString()
    ..referrerPolicy = 'no-referrer';
  frame.setAttribute('sandbox', 'allow-scripts allow-same-origin');
  frame.style.cssText =
      'display:block;border:0;width:100%;height:360px;'
      'max-height:calc(100dvh - 112px);border-radius:16px;background:transparent;';
  final cancel = web.document.createElement('button') as web.HTMLButtonElement;
  cancel
    ..type = 'button'
    ..textContent = 'Cancel';
  cancel.style.cssText =
      'margin-top:16px;width:100%;min-height:48px;'
      'border:1px solid #807f85;border-radius:24px;background:#202024;'
      'color:#fff;font:inherit;font-size:16px;font-weight:500;cursor:pointer;';
  dialog.appendChild(frame);
  dialog.appendChild(cancel);

  void fail() {
    if (!result.isCompleted) {
      result.completeError(
        const CollectAuthException(
          'Security verification was cancelled.',
          code: 'captcha_cancelled',
        ),
      );
    }
  }

  final messageListener = ((web.Event event) {
    final message = event as web.MessageEvent;
    if (message.origin != url.origin ||
        message.source != frame.contentWindow ||
        _active?.attempt != attemptId ||
        result.isCompleted) {
      return;
    }
    try {
      final data = message.data.dartify();
      // Parse before resolving; malformed or expired provider messages fail.
      collectChallengeToken(data, attemptId);
      result.complete(data);
    } catch (_) {
      result.completeError(
        const CollectAuthException(
          'Security verification could not finish.',
          code: 'captcha_unavailable',
        ),
      );
    }
  }).toJS;
  final cancelListener = ((web.Event event) {
    event.preventDefault();
    fail();
  }).toJS;
  // Focusing this dialog/its iframe can make Flutter inactive while this
  // document still owns focus. A real window/tab exit cancels the challenge,
  // including an exit that leaves Flutter in an already-inactive state.
  final foregroundListener = ((web.Event _) {
    if (!challengeHasForeground()) fail();
  }).toJS;
  web.window.addEventListener('message', messageListener);
  web.window.addEventListener('blur', foregroundListener);
  web.document.addEventListener('visibilitychange', foregroundListener);
  cancel.addEventListener('click', cancelListener);
  dialog.addEventListener('cancel', cancelListener);
  try {
    web.document.body!.appendChild(dialog);
    dialog.showModal();
    cancel.focus();
    return await result.future;
  } finally {
    if (_active?.attempt == attemptId) _active = null;
    web.window.removeEventListener('message', messageListener);
    web.window.removeEventListener('blur', foregroundListener);
    web.document.removeEventListener('visibilitychange', foregroundListener);
    cancel.removeEventListener('click', cancelListener);
    dialog.removeEventListener('cancel', cancelListener);
    if (dialog.open) dialog.close();
    dialog.remove();
    if (previousFocus != null && previousFocus.isA<web.HTMLElement>()) {
      (previousFocus as web.HTMLElement).focus();
    }
  }
}

Future<void> cancelChallenge(String attemptId) async {
  final active = _active;
  if (active?.attempt == attemptId && !active!.result.isCompleted) {
    active.result.completeError(
      const CollectAuthException(
        'Security verification was cancelled.',
        code: 'captcha_cancelled',
      ),
    );
  }
}
