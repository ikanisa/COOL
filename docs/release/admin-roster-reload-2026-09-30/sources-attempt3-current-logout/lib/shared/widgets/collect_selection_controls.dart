part of 'collect_components.dart';

class PremiumSegmentedFilter<T> extends StatelessWidget {
  const PremiumSegmentedFilter({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return Semantics(
      container: true,
      label: 'Filter options',
      child: Scrollbar(
        thumbVisibility: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return colors.actionColor.withValues(alpha: 0.12);
                  }
                  return colors.surfaceRaised;
                }),
              ),
              segments: [
                for (final value in values)
                  ButtonSegment<T>(
                    value: value,
                    label: Text(
                      labelFor(value),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              selected: {selected},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ),
        ),
      ),
    );
  }
}

void copyToClipboard(BuildContext context, String text, {String? message}) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message ?? 'Copied securely.')));
}
