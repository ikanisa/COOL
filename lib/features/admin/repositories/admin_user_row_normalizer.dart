import '../../../core/config/app_market.dart';

Map<String, dynamic> normalizeAdminUserRowForAppMarket(
  Map<String, dynamic> row,
) {
  final normalized = Map<String, dynamic>.from(row);
  normalized['country'] = AppMarket.countryCode;
  normalized['language_code'] = AppMarket.languageCode;
  normalized['momo_provider'] = _trimmed(row['momo_provider'])?.toLowerCase();
  normalized['full_name'] = _trimmed(row['full_name']);
  normalized['phone'] = _trimmed(row['phone']);
  normalized['public_user_id'] = _trimmed(row['public_user_id']);
  normalized['vehicle_type'] = _trimmed(row['vehicle_type']);
  normalized['mock_batch'] = _trimmed(row['mock_batch']);
  return normalized;
}

String? _trimmed(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}
