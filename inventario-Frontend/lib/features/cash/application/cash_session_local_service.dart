import '../data/datasources/cash_session_local_dao.dart';
import 'cash_session_local_models.dart';

class CashSessionLocalService {
  CashSessionLocalService({
    required CashSessionLocalDao dao,
  }) : _dao = dao;

  final CashSessionLocalDao _dao;

  Future<Map<String, dynamic>> getLatestCashSessionSummaryForBranch({
    required String businessId,
    required String branchId,
  }) {
    return _dao.getLatestCashSessionSummaryForBranch(
      businessId: businessId,
      branchId: branchId,
    );
  }

  Future<CloseCashSessionResult> closeCashSession(
    CloseCashSessionInput input,
  ) async {
    if (input.actualClosingAmount < 0) {
      throw ArgumentError('El monto de cierre no puede ser negativo.');
    }

    final openSession = await _dao.getOpenCashSessionForBranch(
      businessId: input.businessId,
      branchId: input.branchId,
    );

    if (openSession == null) {
      throw StateError('No hay una sesión de caja abierta para cerrar.');
    }

    final cashSessionId = (openSession['id'] ?? '').toString().trim();
    final cashRegisterId =
        (openSession['cash_register_id'] ?? '').toString().trim();

    if (cashSessionId.isEmpty) {
      throw StateError('La sesión abierta no tiene id local válido.');
    }

    if (cashRegisterId.isEmpty) {
      throw StateError('La sesión abierta no tiene cash_register_id válido.');
    }

    final expectedCashAmount = await _dao.calculateExpectedCashAmountForSession(
      cashSessionId: cashSessionId,
    );

    await _dao.closeCashSession(
      cashSessionId: cashSessionId,
      closedByProfileId: input.profileId,
      expectedCashAmount: expectedCashAmount,
      closingCashAmount: input.actualClosingAmount,
      notes: input.notes,
    );

    return CloseCashSessionResult(
      cashSessionId: cashSessionId,
      cashRegisterId: cashRegisterId,
      businessId: input.businessId,
      branchId: input.branchId,
      expectedCashAmount: expectedCashAmount,
      actualClosingAmount: input.actualClosingAmount,
      differenceAmount: input.actualClosingAmount - expectedCashAmount,
      status: 'closed',
    );
  }

  Future<Map<String, dynamic>> getPosCashReadinessSummary({
    required String businessId,
    required String branchId,
  }) {
    return _dao.getPosCashReadinessSummary(
      businessId: businessId,
      branchId: branchId,
    );
  }

  Future<List<Map<String, dynamic>>> getSalesCashAssociationPreview({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) {
    return _dao.getSalesCashAssociationPreview(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );
  }

  Future<void> assertPosUploadCashReady({
    required String businessId,
    required String branchId,
  }) async {
    final summary = await getPosCashReadinessSummary(
      businessId: businessId,
      branchId: branchId,
    );

    final blockedReason = summary['pos_upload_blocked_reason'];

    if (blockedReason != null && blockedReason.toString().trim().isNotEmpty) {
      throw StateError(blockedReason.toString());
    }
  }

  Future<OpenCashSessionResult> openCashSession(
    OpenCashSessionInput input,
  ) async {
    _validateInput(input);

    final cashRegister = await _getCanonicalCashRegister(input);

    final openSession = await _dao.getOpenCashSessionForRegister(
      businessId: input.businessId,
      branchId: input.branchId,
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

  Future<LocalCashRegisterResult> _getCanonicalCashRegister(
    OpenCashSessionInput input,
  ) async {
    final cashRegisterId = input.cashRegisterId.trim();
    final existing = await _dao.getCashRegisterById(
      id: cashRegisterId,
      businessId: input.businessId,
      branchId: input.branchId,
    );

    if (existing == null) {
      throw CashRecoveryRequiredException(
        cashRegisterId: cashRegisterId,
        businessId: input.businessId,
        branchId: input.branchId,
      );
    }

    return _registerResult(
      existing,
      created: false,
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
      openedByProfileId: _nullableString(row['opened_by_profile_id']),
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

    if (input.cashRegisterId.trim().isEmpty) {
      throw CashRecoveryRequiredException(
        cashRegisterId: input.cashRegisterId,
        businessId: input.businessId,
        branchId: input.branchId,
      );
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
