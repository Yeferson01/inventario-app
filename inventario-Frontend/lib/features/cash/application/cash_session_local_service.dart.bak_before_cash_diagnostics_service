import '../data/datasources/cash_session_local_dao.dart';
import 'cash_session_local_models.dart';

class CashSessionLocalService {
  CashSessionLocalService({
    required CashSessionLocalDao dao,
  }) : _dao = dao;

  final CashSessionLocalDao _dao;

  Future<OpenCashSessionResult> openCashSession(
    OpenCashSessionInput input,
  ) async {
    _validateInput(input);

    final cashRegister = await _getOrCreateCashRegister(input);

    final openSession = await _dao.getOpenCashSessionForRegister(
      cashRegisterId: cashRegister.id,
    );

    if (openSession != null) {
      return OpenCashSessionResult(
        cashRegister: cashRegister,
        cashSession: _sessionResult(
          openSession,
          created: false,
        ),
        reusedOpenSession: true,
      );
    }

    final createdSession = await _dao.createCashSession(
      businessId: input.businessId,
      branchId: input.branchId,
      cashRegisterId: cashRegister.id,
      profileId: input.profileId,
      openingCashAmount: input.openingCashAmount,
      appDeviceId: input.appDeviceId,
      deviceInstallationId: input.deviceInstallationId,
      metadata: {
        ...input.metadata,
        'source': 'cash_session_local_service',
      },
    );

    return OpenCashSessionResult(
      cashRegister: cashRegister,
      cashSession: _sessionResult(
        createdSession,
        created: true,
      ),
      reusedOpenSession: false,
    );
  }

  Future<LocalCashSessionResult?> getOpenCashSession({
    required String businessId,
    required String branchId,
  }) async {
    final session = await _dao.getOpenCashSessionForBranch(
      businessId: businessId,
      branchId: branchId,
    );

    if (session == null) {
      return null;
    }

    return _sessionResult(session, created: false);
  }

  Future<LocalCashRegisterResult> _getOrCreateCashRegister(
    OpenCashSessionInput input,
  ) async {
    if (input.cashRegisterId != null &&
        input.cashRegisterId!.trim().isNotEmpty) {
      final existing = await _dao.getCashRegisterById(
        id: input.cashRegisterId!.trim(),
      );

      if (existing == null) {
        throw StateError(
          'cashRegisterId informado no existe localmente: ${input.cashRegisterId}',
        );
      }

      return _registerResult(
        existing,
        created: false,
      );
    }

    final existing = await _dao.getActiveCashRegisterByCode(
      businessId: input.businessId,
      branchId: input.branchId,
      code: input.cashRegisterCode,
    );

    if (existing != null) {
      return _registerResult(
        existing,
        created: false,
      );
    }

    final created = await _dao.createCashRegister(
      businessId: input.businessId,
      branchId: input.branchId,
      name: input.cashRegisterName,
      code: input.cashRegisterCode,
      profileId: input.profileId,
      appDeviceId: input.appDeviceId,
      deviceInstallationId: input.deviceInstallationId,
      metadata: {
        ...input.metadata,
        'source': 'cash_session_local_service',
      },
    );

    return _registerResult(
      created,
      created: true,
    );
  }

  LocalCashRegisterResult _registerResult(
    Map<String, dynamic> row, {
    required bool created,
  }) {
    return LocalCashRegisterResult(
      id: _requiredString(row, 'id'),
      businessId: _requiredString(row, 'business_id'),
      branchId: _requiredString(row, 'branch_id'),
      name: _nullableString(row['name']) ?? 'Caja principal',
      code: _nullableString(row['code']) ?? 'MAIN',
      created: created,
    );
  }

  LocalCashSessionResult _sessionResult(
    Map<String, dynamic> row, {
    required bool created,
  }) {
    return LocalCashSessionResult(
      id: _requiredString(row, 'id'),
      businessId: _requiredString(row, 'business_id'),
      branchId: _requiredString(row, 'branch_id'),
      cashRegisterId: _requiredString(row, 'cash_register_id'),
      openedByProfileId: _requiredString(row, 'opened_by_profile_id'),
      openedAt: _date(row['opened_at']),
      openingCashAmount: _double(row['opening_cash_amount']),
      status: _nullableString(row['status']) ?? 'open',
      created: created,
    );
  }

  void _validateInput(OpenCashSessionInput input) {
    if (input.businessId.trim().isEmpty) {
      throw ArgumentError('businessId es requerido.');
    }

    if (input.branchId.trim().isEmpty) {
      throw ArgumentError('branchId es requerido.');
    }

    if (input.profileId.trim().isEmpty) {
      throw ArgumentError('profileId es requerido.');
    }

    if (input.cashRegisterName.trim().isEmpty) {
      throw ArgumentError('cashRegisterName es requerido.');
    }

    if (input.cashRegisterCode.trim().isEmpty) {
      throw ArgumentError('cashRegisterCode es requerido.');
    }

    if (input.openingCashAmount < 0) {
      throw ArgumentError('openingCashAmount no puede ser negativo.');
    }
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = _nullableString(source[key]);

    if (value == null) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value;
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  DateTime _date(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw ArgumentError('Fecha inválida: $value');
    }

    return parsed.toUtc();
  }

  double _double(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
