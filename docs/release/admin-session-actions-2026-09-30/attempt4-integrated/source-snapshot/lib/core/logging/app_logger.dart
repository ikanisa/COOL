import 'package:logger/logger.dart';

class AppLogger {
  const AppLogger._();

  static final Logger instance = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 3,
      lineLength: 80,
      noBoxingByDefault: true,
    ),
  );
}
