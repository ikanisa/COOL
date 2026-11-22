import 'package:collect_app/shared/widgets/collect_form_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _submitKey = Key('form-submit');
const _editKey = Key('form-edit');

Widget _host({
  required TextEditingController controller,
  double scale = 1,
  double keyboard = 0,
  bool longBody = true,
  VoidCallback? onSubmit,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(scale),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SafeArea(
      child: CollectFormViewport(
        maxWidth: 430,
        header: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Contribute to the group'),
        ),
        bodyPadding: const EdgeInsets.all(20),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount in RWF'),
            ),
            if (longBody) ...[
              const SizedBox(height: 24),
              const Text(
                'Review the amount and the approved receiver before continuing.',
              ),
              const SizedBox(height: 160),
              const Text(
                'The receipt confirms the contribution, not opening the dialer.',
              ),
            ],
          ],
        ),
        actions: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: _submitKey,
                onPressed: onSubmit ?? () {},
                child: const Text('Continue to MoMo'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: _editKey,
                onPressed: () {},
                child: const Text('Edit contribution amount'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  final cases = <(Size, double, double)>[
    (const Size(320, 568), 1, 0),
    (const Size(320, 568), 2, 220),
    (const Size(320, 568), 3, 220),
    (const Size(568, 320), 2, 160),
    (const Size(390, 844), 2, 300),
  ];
  for (final (size, scale, keyboard) in cases) {
    testWidgets(
      'form actions are reachable: $size, scale=$scale, keyboard=$keyboard',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var submits = 0;
        await tester.pumpWidget(
          _host(
            controller: controller,
            scale: scale,
            keyboard: keyboard,
            onSubmit: () => submits++,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), '12000');
        await tester.scrollUntilVisible(
          find.byKey(_submitKey),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final submit = tester.getRect(find.byKey(_submitKey));
        expect(submit.center.dy, inInclusiveRange(0, size.height - keyboard));
        await tester.tap(find.byKey(_submitKey));
        await tester.pump();
        expect(submits, 1);
        expect(controller.text, '12000');
        await tester.scrollUntilVisible(
          find.byKey(_editKey),
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(_editKey)).center.dy,
          inInclusiveRange(0, size.height - keyboard),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'short form actions fill the bottom instead of floating after the field',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller, longBody: false));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_editKey)).bottom, closeTo(880, 1));
      expect(tester.getSize(find.byType(CustomScrollView)).width, 430);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard resize preserves editor focus and selection', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final controller = TextEditingController(text: '12000');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller: controller, longBody: false));
    await tester.tap(find.byType(TextField));
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();
    final focus = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    await tester.pumpWidget(
      _host(controller: controller, keyboard: 220, longBody: false),
    );
    await tester.pumpAndSettle();
    final after = tester
        .widget<EditableText>(find.byType(EditableText))
        .focusNode;
    expect(identical(focus, after), isTrue);
    expect(after.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(controller.text, '12000');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the form does not introduce a nested vertical list or text-scale override',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_host(controller: controller, scale: 2));
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      final context = tester.element(find.byType(TextField));
      expect(MediaQuery.textScalerOf(context).scale(16), 32);
      expect(tester.takeException(), isNull);
    },
  );
}
