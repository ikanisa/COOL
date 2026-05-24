import 'package:intl/intl.dart';

final _rwfFormat = NumberFormat.currency(
  locale: 'en_RW',
  symbol: 'RWF ',
  decimalDigits: 0,
);

String formatRwf(int amountRwf) => _rwfFormat.format(amountRwf);
