// Local native fixture; never imported by production entry points.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:collect_app/shared/repositories/collect_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_cover_review_app.dart' as review;

final _errors = <String>[];

void main() {
  if (!kDebugMode ||
      kIsWeb ||
      appFlavor != 'dev' ||
      !const bool.fromEnvironment('COLLECT_GROUP_COVER_QA')) {
    throw StateError(
      'Only the explicit native dev photo fixture is supported.',
    );
  }
  enableFlutterDriverExtension(
    enableTextEntryEmulation: false,
    handler: (_) async {
      final fields = <String>[];
      BuildContext? providerContext;
      void visit(Element element) {
        if (element.widget is ConsumerWidget ||
            element.widget is ConsumerStatefulWidget) {
          providerContext ??= element;
        }
        if (element.widget case TextField(:final controller)) {
          fields.add(controller?.text ?? '');
        }
        element.visitChildren(visit);
      }

      WidgetsBinding.instance.rootElement?.visitChildren(visit);
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final state = providerContext == null
          ? null
          : ProviderScope.containerOf(
              providerContext!,
              listen: false,
            ).read(collectRepositoryProvider);
      return jsonEncode({
        'fields': fields,
        'keyboardInset': view.viewInsets.bottom / view.devicePixelRatio,
        'width': view.physicalSize.width / view.devicePixelRatio,
        'height': view.physicalSize.height / view.devicePixelRatio,
        'errors': _errors,
        'groups': [
          for (final group in state?.collections ?? [])
            {
              'id': group.id,
              'image': group.imageUrl,
              'type': group.collectionType.storageValue,
            },
        ],
      });
    },
  );
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _errors.add(details.exceptionAsString());
    previous?.call(details);
  };
  review.main();
}
