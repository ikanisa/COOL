import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'collect_components.dart';

class AmountInput extends StatelessWidget {
  const AmountInput({required this.controller, super.key});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: collectInputDecoration(
        context,
        label: 'Amount',
        prefix: 'RWF ',
      ),
    );
  }
}
