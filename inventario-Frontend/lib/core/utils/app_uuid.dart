import 'package:uuid/uuid.dart';

class AppUuid {
  AppUuid._();

  static const Uuid _uuid = Uuid();

  /// ID principal para entidades offline-first.
  ///
  /// Usamos UUIDv7 porque ordena mejor por tiempo que UUIDv4
  /// y funciona muy bien para sincronización posterior.
  static String v7() {
    return _uuid.v7();
  }

  /// Fallback para casos donde no importa el orden temporal.
  static String v4() {
    return _uuid.v4();
  }

  static bool looksLikeUuid(String value) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );

    return uuidRegex.hasMatch(value.trim());
  }
}
