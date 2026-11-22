import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/collect_localizations.dart';
import '../shared/widgets/collect_components.dart';
import 'lifecycle/member_sms_receipt_host.dart';
import 'lifecycle/notification_intent_host.dart';
import 'lifecycle/notification_registration_host.dart';
import 'lifecycle/pending_group_intent_host.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/collect_theme_controller.dart';

export 'lifecycle/pending_group_intent_host.dart'
    show collectIncomingAppLinksProvider;

class CollectApp extends ConsumerWidget {
  const CollectApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(collectThemeModeProvider);

    return PendingGroupIntentHost(
      child: NotificationIntentHost(
        child: MemberSmsReceiptHost(
          child: NotificationRegistrationHost(
            child: MaterialApp.router(
              title: 'Collect',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              highContrastTheme: AppTheme.highContrastLight(),
              highContrastDarkTheme: AppTheme.highContrastDark(),
              themeMode: themeMode,
              supportedLocales: CollectLocalizations.supportedLocales,
              localizationsDelegates: const [
                CollectLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              locale: const Locale('en'),
              routerConfig: router,
              builder: (context, child) {
                final dark = Theme.of(context).brightness == Brightness.dark;
                final icons = dark ? Brightness.light : Brightness.dark;
                return AnnotatedRegion<SystemUiOverlayStyle>(
                  value: SystemUiOverlayStyle(
                    statusBarColor: CollectColors.transparentColor,
                    statusBarIconBrightness: icons,
                    statusBarBrightness: dark
                        ? Brightness.dark
                        : Brightness.light,
                    systemNavigationBarColor: context.collectColors.canvas,
                    systemNavigationBarIconBrightness: icons,
                    systemNavigationBarDividerColor:
                        CollectColors.transparentColor,
                  ),
                  child: child ?? const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
