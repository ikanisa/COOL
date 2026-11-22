import '../data/exact_json_values.dart';

/// Parse the exact whole-RWF text shown to the member before submission.
int? parseRwfSubmissionAmount(String text, {required bool isComposing}) {
  final match = RegExp(
    r'^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)$',
  ).firstMatch(text);
  if (isComposing || match == null || match.end != text.length) {
    return null;
  }
  try {
    return exactJsonInteger(
      text.replaceAll(',', ''),
      field: 'contribution.amount',
      minimum: 1,
      allowDigitString: true,
    );
  } on FormatException {
    return null;
  }
}
