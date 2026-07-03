part of 'collect_landing_page.dart';

void _scrollToCustomerAction(BuildContext context) {
  final position = Scrollable.maybeOf(context)?.position;
  if (position == null) return;
  final target = position.maxScrollExtent - 220;
  final offset = target.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  if (MediaQuery.maybeOf(context)?.disableAnimations == true) {
    position.jumpTo(offset);
    return;
  }
  position.animateTo(
    offset,
    duration: CollectMotion.medium,
    curve: CollectMotion.standard,
  );
}

CollectRuntimeConfig _runtimeConfigFor(BuildContext context) {
  try {
    return ProviderScope.containerOf(
      context,
      listen: false,
    ).read(collectRuntimeConfigProvider);
  } catch (_) {
    return CollectRuntimeConfig.defaults;
  }
}

Future<void> _openWhatsApp(BuildContext context, String message) async {
  final config = _runtimeConfigFor(context);
  final url = Uri.https('wa.me', '/${config.whatsAppSupportPhone}', {
    'text': message,
  });
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<void> _openEmail(BuildContext context) async {
  final config = _runtimeConfigFor(context);
  final url = Uri(
    scheme: 'mailto',
    path: config.supportEmail,
    queryParameters: {'subject': 'Collect support'},
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
}
