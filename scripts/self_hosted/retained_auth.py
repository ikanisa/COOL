"""Plan persistent CLI Auth settings for the existing retained Collect project.

This helper has no executor. It verifies a sealed release and emits only a
sanitized plan unless --output is supplied. A new protected output contains
section updates and a server-only application.env append candidate. It never
changes the retained workspace, existing keys, containers, volumes or providers.
The operator must review/apply the updates with the existing TOML section writer
and merge the selected server-only secrets without replacing private/application.env.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import sys
from urllib.parse import urlsplit

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from scripts.self_hosted.configure import (
    private_file, read_env, read_provider_settings, admin_email_otp_ttl,
    TURNSTILE_TEST_SITE_KEYS, TURNSTILE_TEST_SECRET_KEYS,
)
from scripts.self_hosted.release_operator import Operator
from scripts.self_hosted.prepare import auth_redirect_allowlist
from scripts.self_hosted.retained_collect import read_cli_configuration

SMTP_VARIABLE = 'COLLECT_AUTH_SMTP_PASS'
# CLI 2.122.0 packages/config/src/lib/env.ts uses the capture verbatim as
# the environment key. Quotes inside env(...) would become part of that key.
SMTP_REFERENCE = 'env(' + SMTP_VARIABLE + ')'
SMTP_FIELDS = ('SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_ADMIN_EMAIL', 'SMTP_SENDER_NAME')
TURNSTILE_VARIABLE = 'COLLECT_AUTH_TURNSTILE_SECRET'
TURNSTILE_REFERENCE = 'env(' + TURNSTILE_VARIABLE + ')'


class AuthPlanError(RuntimeError):
    """Fixed, nonsecret error codes only."""


def _sha(raw):
    return hashlib.sha256(raw).hexdigest()


def _json(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':'))


def _secret_in_environment(values, names, secret, prefixes=()):
    if not isinstance(values, dict):
        return True
    return any(str(key).upper() in names or str(key).upper().startswith(prefixes)
               or any(name in str(value) for name in names)
               or bool(secret) and secret in str(value) for key, value in values.items())


def _callback(value, origins):
    if not isinstance(value, str) or len(value) > 2048 or re.search(r'[\s\\%*\x00-\x1f]', value):
        raise AuthPlanError('retained_auth_callback_invalid')
    try:
        url = urlsplit(value)
        if (url.scheme != 'https' or url.username is not None or url.password is not None
                or url.scheme + '://' + url.netloc not in origins or url.query or url.fragment
                or not re.fullmatch(r'(?:/[A-Za-z0-9_~.-]+)*/?', url.path)
                or any(part in ('.', '..') for part in url.path.split('/'))):
            raise ValueError()
    except ValueError:
        raise AuthPlanError('retained_auth_callback_invalid') from None
    return value


class RetainedAuthPlan:
    def __init__(self, operator, config_path, callbacks=()):
        self.operator = operator
        self.config_path, raw, config = read_cli_configuration(config_path)
        self.callbacks = tuple(callbacks)
        self.config_sha256 = _sha(raw)
        self.configuration_sha256 = _sha((operator.root / 'private/configuration.json').read_bytes())
        provider_path = operator.root / 'private/provider-settings.json'
        private_file(provider_path)
        self.provider_sha256 = _sha(provider_path.read_bytes())
        settings = read_provider_settings(provider_path)
        try:
            email_otp_lifetime = admin_email_otp_ttl(settings)
        except ValueError:
            raise AuthPlanError('retained_auth_email_otp_lifetime_invalid') from None
        profile = operator.profile
        self.production_private = profile['environment'] == 'production'
        auth = config.get('auth', {})
        if auth.get('enabled') is not True or config.get('experimental', {}).get('stack', False) is not False:
            raise AuthPlanError('retained_auth_original_stack_required')
        if auth.get('hook', {}).get('send_email', {}).get('enabled') is True:
            # An enabled hook overrides SMTP. Changing its policy is a separate
            # explicit decision; silently leaving it enabled is not SMTP setup.
            raise AuthPlanError('retained_auth_send_email_hook_conflict')
        if any(not isinstance(settings.get(name), str) for name in SMTP_FIELDS):
            raise AuthPlanError('retained_auth_smtp_configuration_required')
        if settings['SMTP_HOST'] != 'smtp.mx.cloudflare.net' or settings['SMTP_PORT'] != '465' or settings['SMTP_USER'] != 'api_token':
            raise AuthPlanError('retained_auth_cloudflare_implicit_tls_required')
        password = settings['SMTP_PASS']
        if not re.fullmatch(r'[!-~]{16,1024}', password):
            raise AuthPlanError('retained_auth_protected_smtp_password_required')
        if not re.fullmatch(r'[^\s@<>]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,63}', settings['SMTP_ADMIN_EMAIL']):
            raise AuthPlanError('retained_auth_sender_required')
        if not settings['SMTP_SENDER_NAME'] or len(settings['SMTP_SENDER_NAME']) > 128 or re.search(r'[\x00-\x1f\x7f]', settings['SMTP_SENDER_NAME']):
            raise AuthPlanError('retained_auth_sender_required')
        edge_secrets = config.get('edge_runtime', {}).get('secrets', {})
        functions = read_env(operator.root / 'private/functions.env')
        if any(_secret_in_environment(values, (SMTP_VARIABLE,), password,
                                      ('SMTP_', 'GOTRUE_SMTP_', 'COLLECT_AUTH_SMTP_'))
               for values in (edge_secrets, functions)):
            raise AuthPlanError('retained_auth_smtp_server_boundary_required')
        site_key, captcha_secret = settings.get('TURNSTILE_SITE_KEY'), settings.get('TURNSTILE_SECRET_KEY')
        self.turnstile_enabled = self.production_private or bool(site_key or captcha_secret) or auth.get('captcha', {}).get('enabled') is True
        if self.turnstile_enabled:
            if (not isinstance(site_key, str) or not re.fullmatch(r'[A-Za-z0-9_-]{10,200}', site_key)
                    or not isinstance(captcha_secret, str) or not re.fullmatch(r'[A-Za-z0-9_-]{16,1024}', captcha_secret)):
                raise AuthPlanError('retained_auth_turnstile_configuration_required')
            if self.production_private and (site_key in TURNSTILE_TEST_SITE_KEYS or captcha_secret in TURNSTILE_TEST_SECRET_KEYS):
                raise AuthPlanError('retained_auth_production_turnstile_required')
        captcha_names = (TURNSTILE_VARIABLE, 'TURNSTILE_SECRET_KEY', 'GOTRUE_SECURITY_CAPTCHA_SECRET')
        if any(_secret_in_environment(values, captcha_names, captcha_secret)
               for values in (edge_secrets, functions)):
            raise AuthPlanError('retained_auth_turnstile_server_boundary_required')
        origins = {profile['public_origin'], profile['admin_origin']}
        redirects = set(auth_redirect_allowlist(profile).split(',')) | {_callback(value, origins) for value in callbacks}
        self.google_enabled = auth.get('external', {}).get('google', {}).get('enabled') is True
        if self.production_private:
            phone = auth.get('sms', {})
            unsupported = (any(settings.get(name) != 'false' for name in
                               ('AUTH_ANONYMOUS_ENABLED', 'AUTH_SMS_ENABLED', 'AUTH_WHATSAPP_ENABLED'))
                           or settings.get('GOOGLE_AUTH_ENABLED') not in ('true', 'false')
                           or settings.get('GOOGLE_AUTH_ENABLED') != settings.get('GOTRUE_EXTERNAL_GOOGLE_ENABLED')
                           or self.google_enabled != (settings.get('GOOGLE_AUTH_ENABLED') == 'true')
                           or auth.get('hook', {}).get('send_sms', {}).get('enabled') is True
                           or any(isinstance(value, dict) and value.get('enabled') is True for value in phone.values())
                           or any(name != 'google' and isinstance(value, dict) and value.get('enabled') is True
                                  for name, value in auth.get('external', {}).items()))
            if unsupported:
                raise AuthPlanError('retained_auth_private_provider_policy_required')
        if self.google_enabled:
            if profile['google_callback_origin'] != profile['admin_origin']:
                raise AuthPlanError('retained_auth_google_admin_origin_required')
        auth_url = profile['supabase_origin'] + '/auth/v1'
        self._updates = {
            'api': {'external_url': profile['supabase_origin']},
            'auth': {'external_url': auth_url, 'jwt_issuer': auth_url,
                     'site_url': profile['public_origin'], 'additional_redirect_urls': sorted(redirects)},
            'auth.email.smtp': {'enabled': True, 'host': settings['SMTP_HOST'], 'port': 465,
                                'user': settings['SMTP_USER'], 'pass': SMTP_REFERENCE,
                                'admin_email': settings['SMTP_ADMIN_EMAIL'], 'sender_name': settings['SMTP_SENDER_NAME']},
            'auth.email': {'otp_expiry': email_otp_lifetime},
            'edge_runtime': {'enabled': False},
        }
        if self.turnstile_enabled:
            self._updates['auth.captcha'] = {'enabled': True, 'provider': 'turnstile', 'secret': TURNSTILE_REFERENCE}
        if self.production_private:
            self._updates['auth'].update(enable_signup=False, enable_anonymous_sign_ins=False)
            # CLI 2.122.0 maps this flag to GOTRUE_EXTERNAL_EMAIL_ENABLED,
            # including existing-user OTP. Global enable_signup above separately
            # keeps GoTrue DisableSignup on; email login must remain enabled.
            self._updates['auth.email']['enable_signup'] = True
        if self.google_enabled:
            # A previously authored loopback redirect overrides the CLI's new
            # issuer-derived default. Change only that profile-bound URL.
            self._updates['auth.external.google'] = {'redirect_uri': auth_url + '/callback'}
        # Existing Google enablement/credentials, nonce policy, SMS hook/provider,
        # templates, confirmation policy, JWT references and signing-key path
        # are absent from this allowlist. Production public signup/anonymous
        # access are explicitly disabled; qualified existing users can sign in.
        self._application_environment = SMTP_VARIABLE + '=' + password + '\n'
        if self.turnstile_enabled:
            self._application_environment += TURNSTILE_VARIABLE + '=' + captcha_secret + '\n'
        self._revision = (operator.meta['source_sha256'], operator.meta['profile_sha256'],
                          self.configuration_sha256, self.provider_sha256, self.config_sha256)

    def __repr__(self):
        return 'RetainedAuthPlan(private_environment=redacted)'

    def describe(self):
        return {'format': 'collect.retained-auth.plan.v1', 'plan_only': True,
                'configuration_changed': False, 'runtime_changed': False,
                'profile_sha256': self.operator.meta['profile_sha256'],
                'source_sha256': self.operator.meta['source_sha256'],
                'configuration_sha256': self.configuration_sha256,
                'input_cli_configuration_sha256': self.config_sha256,
                'provider_configuration_sha256': self.provider_sha256,
                'section_update_fields': {section: sorted(fields) for section, fields in self._updates.items()},
                'smtp_environment_fields': [SMTP_VARIABLE],
                'smtp_environment_scope': 'retained_auth_only', 'replace_application_environment': False,
                'turnstile_environment_fields': [TURNSTILE_VARIABLE] if self.turnstile_enabled else [],
                'gotrue_turnstile_enabled': self.turnstile_enabled,
                'production_public_signup_disabled': self.production_private,
                'generic_cli_edge_disabled': True, 'existing_keys_replaced': False,
                'google_state_redirect_match_requires_qualification': self.google_enabled,
                'provider_credentials_verified': False, 'email_delivery_verified': False,
                'requires_operator': ['apply_selected_section_updates_preserving_all_other_configuration',
                    'merge_selected_server_only_variables_into_existing_private_application_environment',
                    'selected_profile_devctl_public_status_and_redirect_validation',
                    'qualify_native_and_admin_captcha_flow_before_commissioning',
                    'controlled_cli_restart_preserving_project_network_keys_and_volumes',
                    'reinstall_canonical_closed_edge_with_retained_operator',
                    'verify_actual_email_delivery_and_app_callback_allowlist']}

    def export(self, output):
        # This is still only preparation. Recheck the seal and original config
        # before writing candidates, and bind the plan to those exact bytes.
        current = plan(self.operator.root, self.config_path, callbacks=self.callbacks)
        if current._revision != self._revision:
            raise AuthPlanError('retained_auth_plan_changed')
        output = Path(output).absolute()
        workspace = self.config_path.parent.parent if self.config_path.parent.name == 'supabase' else self.config_path.parent
        try:
            parent = output.parent
            info = parent.stat()
            if (parent.resolve(strict=True) != parent or output.exists() or output.is_symlink()
                    or not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077
                    or output == workspace or output.is_relative_to(workspace)
                    or output == self.operator.root or output.is_relative_to(self.operator.root)):
                raise ValueError()
        except Exception:
            raise AuthPlanError('retained_auth_new_protected_output_required') from None
        payloads = {'config-updates.json': _json(self._updates) + '\n',
                    'application-env.append': self._application_environment,
                    'plan.json': _json(self.describe()) + '\n'}
        try:
            output.mkdir(mode=0o700)
            for name, content in payloads.items():
                fd = os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                with os.fdopen(fd, 'wb') as target:
                    target.write(content.encode('utf8'))
        except Exception:
            # Never echo a private payload/path/parser exception or replay a
            # partially written output as if it were an applied configuration.
            raise AuthPlanError('retained_auth_candidate_output_unconfirmed') from None
        result = self.describe()
        result['candidate_files'] = {name: {'sha256': _sha(value.encode('utf8')), 'mode': '0600'}
                                     for name, value in payloads.items()}
        return result


def plan(release, config_path, *, callbacks=()):
    return RetainedAuthPlan(Operator(release), config_path, callbacks)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', required=True, type=Path)
    parser.add_argument('--cli-config', required=True, type=Path)
    parser.add_argument('--callback', action='append', default=[], help='Exact deployed HTTPS app callback on the approved Admin/public origin')
    parser.add_argument('--output', type=Path, help='New candidate directory under an owned mode0700 parent; never the retained workspace')
    args = parser.parse_args(argv)
    try:
        selected = plan(args.release, args.cli_config, callbacks=args.callback)
        print(json.dumps(selected.export(args.output) if args.output else selected.describe(), sort_keys=True))
        return 0
    except Exception as error:
        code = str(error) if isinstance(error, AuthPlanError) else 'retained_auth_configuration_invalid'
        print(json.dumps({'code': code, 'plan_completed': False, 'configuration_changed': False,
                          'runtime_changed': False}), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
