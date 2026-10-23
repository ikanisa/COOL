import 'package:collect_app/shared/widgets/collect_components.dart';
import 'package:collect_app/shared/widgets/collect_form_viewport.dart' as forms;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'legacy and new viewport constructors coexist without ambiguous imports',
    () {
      const legacy = CollectFormViewport(child: SizedBox());
      const modern = forms.CollectFormViewport(
        header: SizedBox(),
        body: SizedBox(),
        actions: SizedBox(),
      );
      expect(legacy, isA<CollectFormViewport>());
      expect(modern, isA<forms.CollectFormViewport>());
      expect(legacy.runtimeType, isNot(modern.runtimeType));
    },
  );
}
