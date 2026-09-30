import 'package:url_launcher/url_launcher.dart';

class RevolutLauncher {
  const RevolutLauncher();

  static final Uri _appUri = Uri.parse('revolut://');
  static final Uri _webFallback = Uri.parse('https://www.revolut.com/app/');

  /// Opens Revolut at its root. Beneficiary, amount, and reference are never
  /// injected into an undocumented URI; the member confirms them in Revolut.
  Future<bool> launch() async {
    if (await canLaunchUrl(_appUri) &&
        await launchUrl(_appUri, mode: LaunchMode.externalApplication)) {
      return true;
    }
    return launchUrl(_webFallback, mode: LaunchMode.externalApplication);
  }
}
