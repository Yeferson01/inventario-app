import 'package:logger/logger.dart';

class AppLogger {
  AppLogger._();

  static final Logger instance = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 100,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  static void debug(Object? message, {Object? error, StackTrace? stackTrace}) {
    instance.d(message, error: error, stackTrace: stackTrace);
  }

  static void info(Object? message, {Object? error, StackTrace? stackTrace}) {
    instance.i(message, error: error, stackTrace: stackTrace);
  }

  static void warning(Object? message,
      {Object? error, StackTrace? stackTrace}) {
    instance.w(message, error: error, stackTrace: stackTrace);
  }

  static void error(Object? message, {Object? error, StackTrace? stackTrace}) {
    instance.e(message, error: error, stackTrace: stackTrace);
  }
}
