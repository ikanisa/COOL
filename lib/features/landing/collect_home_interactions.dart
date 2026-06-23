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

Future<void> _openWhatsApp(String message) async {
  final url = Uri.https('wa.me', '/$_collectWhatsAppNumber', {'text': message});
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

Future<void> _openEmail() async {
  final url = Uri(
    scheme: 'mailto',
    path: _collectContactEmail,
    queryParameters: {'subject': 'Collect support'},
  );
  await launchUrl(url, mode: LaunchMode.externalApplication);
}
