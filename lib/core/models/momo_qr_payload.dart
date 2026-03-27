import '../config/country_catalog.dart';

const _coolMomoHost = 'momo';
const _coolDeepLinkHost = String.fromEnvironment(
  'COOL_DEEP_LINK_HOST',
  defaultValue: 'cool.app',
);
const _legacyCoolDeepLinkHosts = <String>{
  'cool.app',
  'www.cool.app',
  'cool.ikanisa.com',
  'www.cool.ikanisa.com',
};

enum MomoQrAction { profile, pay }

class MomoQrPayload {
  const MomoQrPayload({
    required this.recipientValue,
    required this.recipientType,
    required this.action,
    this.countryCode,
    this.amount,
    this.reference,
  });

  factory MomoQrPayload.profile({
    required String recipientValue,
    required MomoRecipientType recipientType,
    String? countryCode,
    String? reference,
  }) {
    return MomoQrPayload(
      recipientValue: recipientValue.trim(),
      recipientType: recipientType,
      action: MomoQrAction.profile,
      countryCode: _normalizeCountryCodeOrNull(countryCode),
      reference: reference?.trim().isEmpty ?? true ? null : reference?.trim(),
    );
  }

  factory MomoQrPayload.paymentRequest({
    required String recipientValue,
    required MomoRecipientType recipientType,
    required int amount,
    String? countryCode,
    String? reference,
  }) {
    return MomoQrPayload(
      recipientValue: recipientValue.trim(),
      recipientType: recipientType,
      action: MomoQrAction.pay,
      countryCode: _normalizeCountryCodeOrNull(countryCode),
      amount: amount > 0 ? amount : null,
      reference: reference?.trim().isEmpty ?? true ? null : reference?.trim(),
    );
  }

  final String recipientValue;
  final MomoRecipientType recipientType;
  final MomoQrAction action;
  final String? countryCode;
  final int? amount;
  final String? reference;

  bool get hasAmount => amount != null && amount! > 0;
  bool get canLaunchImmediately =>
      action == MomoQrAction.pay && hasAmount && countryCode != null;

  Uri toAppLinkUri() {
    return Uri.https(_coolDeepLinkHost, '/momo', <String, String>{
      'action': switch (action) {
        MomoQrAction.profile => 'qr_profile',
        MomoQrAction.pay => 'qr_pay',
      },
      'recipient': recipientValue,
      'recipient_type': recipientType.name,
      // ignore: use_null_aware_elements
      if (countryCode != null) 'country': countryCode!,
      if (hasAmount) 'amount': amount!.toString(),
      // ignore: use_null_aware_elements
      if (reference != null) 'reference': reference!,
    });
  }

  Uri toCustomSchemeUri() {
    return Uri(
      scheme: 'cool',
      host: _coolMomoHost,
      queryParameters: <String, String>{
        'action': switch (action) {
          MomoQrAction.profile => 'qr_profile',
          MomoQrAction.pay => 'qr_pay',
        },
        'recipient': recipientValue,
        'recipient_type': recipientType.name,
        // ignore: use_null_aware_elements
        if (countryCode != null) 'country': countryCode!,
        if (hasAmount) 'amount': amount!.toString(),
        // ignore: use_null_aware_elements
        if (reference != null) 'reference': reference!,
      },
    );
  }

  Uri toDialerUri(CoolCountry country) {
    final ussdCode = country.buildUssdCode(
      recipientMomo: recipientValue,
      amount: amount,
      recipientType: recipientType,
    );
    // Android requires # to be %23 in tel: URIs; raw # is parsed as fragment.
    final encoded = ussdCode.replaceAll('#', '%23');
    return Uri.parse('tel:$encoded');
  }

  String toQrData(CoolCountry country, {bool preferDirectDial = true}) {
    if (preferDirectDial && canLaunchImmediately) {
      return toDialerUri(country).toString();
    }
    return toAppLinkUri().toString();
  }

  static MomoQrPayload? tryParse(String rawText) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parsedUri = Uri.tryParse(trimmed);
    if (parsedUri != null) {
      final uriPayload = tryParseUri(parsedUri);
      if (uriPayload != null) {
        return uriPayload;
      }
    }

    if (trimmed.startsWith('momo://')) {
      final recipientValue = trimmed.replaceFirst('momo://', '').trim();
      if (recipientValue.isEmpty) {
        return null;
      }
      return MomoQrPayload.profile(
        recipientValue: recipientValue,
        recipientType: MomoRecipientType.phoneNumber,
      );
    }

    if (_plainPhonePattern.hasMatch(trimmed)) {
      return MomoQrPayload.profile(
        recipientValue: trimmed,
        recipientType: MomoRecipientType.phoneNumber,
      );
    }

    return null;
  }

  static MomoQrPayload? tryParseUri(Uri uri) {
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final host = uri.host.toLowerCase();
    final defaultHost = _coolDeepLinkHost.toLowerCase();
    final isCoolAppLink =
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        (host == defaultHost ||
            host == 'www.$defaultHost' ||
            _legacyCoolDeepLinkHosts.contains(host)) &&
        segments.isNotEmpty &&
        segments.first.toLowerCase() == _coolMomoHost;
    final isCustomScheme =
        uri.scheme == 'cool' &&
        ((uri.host.isNotEmpty && host == _coolMomoHost) ||
            (segments.isNotEmpty &&
                segments.first.toLowerCase() == _coolMomoHost));

    if (!isCoolAppLink && !isCustomScheme) {
      return null;
    }

    final actionValue = uri.queryParameters['action']?.trim().toLowerCase();
    final action = switch (actionValue) {
      'qr_profile' => MomoQrAction.profile,
      'qr_pay' => MomoQrAction.pay,
      _ => null,
    };
    if (action == null) {
      return null;
    }

    final recipientValue = uri.queryParameters['recipient']?.trim() ?? '';
    if (recipientValue.isEmpty) {
      return null;
    }

    final recipientType = switch (uri.queryParameters['recipient_type']
        ?.trim()
        .toLowerCase()) {
      'code' => MomoRecipientType.code,
      _ => MomoRecipientType.phoneNumber,
    };
    final amount = int.tryParse(
      (uri.queryParameters['amount'] ?? '').replaceAll(RegExp(r'[^0-9]'), ''),
    );

    return MomoQrPayload(
      recipientValue: recipientValue,
      recipientType: recipientType,
      action: action,
      countryCode: _normalizeCountryCodeOrNull(uri.queryParameters['country']),
      amount: amount != null && amount > 0 ? amount : null,
      reference: uri.queryParameters['reference']?.trim().isEmpty ?? true
          ? null
          : uri.queryParameters['reference']?.trim(),
    );
  }

  static final RegExp _plainPhonePattern = RegExp(r'^\+?[0-9]{7,15}$');

  static String? _normalizeCountryCodeOrNull(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return CoolCountryCatalog.normalizeCountryCode(value);
  }
}
