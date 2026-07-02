import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../data/datasources/cash_session_local_dao.dart';
import 'cash_session_local_service.dart';

final cashSessionLocalDaoProvider = Provider<CashSessionLocalDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return CashSessionLocalDao(db);
});

final cashSessionLocalServiceProvider =
    Provider<CashSessionLocalService>((ref) {
  return CashSessionLocalService(
    dao: ref.watch(cashSessionLocalDaoProvider),
  );
});
