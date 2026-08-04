part of 'auth_screen_widgets.dart';

class AuthOtpEntry extends StatefulWidget {
  const AuthOtpEntry({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  static const digitCount = 6;

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<AuthOtpEntry> createState() => AuthOtpEntryState();
}

class AuthOtpEntryState extends State<AuthOtpEntry> {
  static const _digitCount = AuthOtpEntry.digitCount;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;
  var _syncing = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_digitCount, (_) => TextEditingController());
    _nodes = List.generate(_digitCount, (_) => FocusNode());
    widget.controller.addListener(_syncFromExternal);
    _syncFromExternal();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromExternal);
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFromExternal() {
    if (_syncing) return;
    final digits = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    for (var index = 0; index < _digitCount; index += 1) {
      final value = index < digits.length ? digits[index] : '';
      if (_controllers[index].text != value) {
        _controllers[index].text = value;
      }
    }
  }

  void _publish() {
    final value = _controllers.map((controller) => controller.text).join();
    _syncing = true;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _syncing = false;
    widget.onChanged();
  }

  void _handleDigit(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (var offset = 0; offset < digits.length; offset += 1) {
        final target = index + offset;
        if (target >= _digitCount) break;
        _controllers[target].text = digits[offset];
      }
      final nextIndex = (index + digits.length)
          .clamp(0, _digitCount - 1)
          .toInt();
      _nodes[nextIndex].requestFocus();
      _publish();
      return;
    }
    final digit = digits;
    if (_controllers[index].text != digit) {
      _controllers[index].text = digit;
    }
    if (digit.isNotEmpty && index < _digitCount - 1) {
      _nodes[index + 1].requestFocus();
    }
    _publish();
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        _controllers[index].text.isNotEmpty ||
        index == 0) {
      return KeyEventResult.ignored;
    }
    _controllers[index - 1].clear();
    _nodes[index - 1].requestFocus();
    _publish();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = context.collectColors.onImagePrimary;
    return AutofillGroup(
      child: Semantics(
        textField: true,
        label: 'Verification code',
        child: Row(
          children: [
            for (var index = 0; index < _digitCount; index += 1) ...[
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) => _handleKey(index, event),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: SizedBox(
                      height: 64,
                      child: TextField(
                        key: ValueKey('auth_otp_digit_$index'),
                        controller: _controllers[index],
                        focusNode: _nodes[index],
                        keyboardType: TextInputType.number,
                        autofocus: index == 0,
                        autofillHints: index == 0
                            ? const [AutofillHints.oneTimeCode]
                            : null,
                        enableSuggestions: false,
                        autocorrect: false,
                        obscureText: true,
                        obscuringCharacter: '•',
                        textInputAction: index == _digitCount - 1
                            ? TextInputAction.done
                            : TextInputAction.next,
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: foreground,
                          fontWeight: CollectTypography.weightBold,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          counterText: '',
                          border: InputBorder.none,
                        ),
                        onChanged: (value) => _handleDigit(index, value),
                      ),
                    ),
                  ),
                ),
              ),
              if (index == 2)
                SizedBox(
                  width: 20,
                  child: Text(
                    '–',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: foreground.withValues(alpha: 0.72),
                    ),
                  ),
                )
              else if (index != _digitCount - 1)
                const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }
}
