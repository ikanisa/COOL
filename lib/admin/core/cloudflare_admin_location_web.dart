import 'package:web/web.dart' as web;

void removeCloudflareSetupTokenFromLocation() {
  web.window.history.replaceState(null, '', '/#/admin/setup');
}
