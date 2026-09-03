import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/cash_repair_context_service.dart';
import 'package:inventario_frontend/features/sync/data/models/cash_pos_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_resolution_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('A closes stale S3 before opening one S4 and retry keeps it unique',
      () async {
    String? remoteOpenSessionId;
    var localOpenSessionIds = <String>['session-s1'];
    var reconciliations = 0;
    final service = _service(
      resolveRuntime: ({
        required profileId,
        required businessId,
        required branchId,
      }) async =>
          _runtime(openCashSessionId: remoteOpenSessionId),
      recoverCash: (_) async =>
          _recovery(openCashSessionId: remoteOpenSessionId),
      loadOpenSessions: () async =>
          localOpenSessionIds.map((id) => <String, dynamic>{'id': id}).toList(),
      reconcileOriginalSession: ({required remoteOpenCashSessionId}) async {
        expect(remoteOpenCashSessionId, isNull);
        reconciliations++;
        localOpenSessionIds = [];
        return true;
      },
      blockers: [_staleSaleBlocker()],
    );

    final beforeOpen = await service.refresh(_request());
    expect(beforeOpen.openCashSessionId, isNull);
    expect(localOpenSessionIds, isEmpty);

    remoteOpenSessionId = 'session-s4';
    localOpenSessionIds.add('session-s4');
    final afterOpen = await service.refresh(_request());
    final retry = await service.refresh(_request());

    expect(afterOpen.openCashSessionId, 'session-s4');
    expect(retry.openCashSessionId, 'session-s4');
    expect(localOpenSessionIds, ['session-s4']);
    expect(reconciliations, 1);
  });

  test('B materializes and reuses remote S4 after converging stale S3',
      () async {
    AppRuntimeContext? written;
    var recovered = 0;
    var reconciled = false;
    final service = _service(
      runtime: _runtime(openCashSessionId: 'session-s4'),
      recoverCash: (_) async {
        recovered++;
        return _recovery(
          openCashSessionId: reconciled ? 'session-s4' : null,
        );
      },
      loadBlockingIssues: () async => [
        _staleSaleBlocker(),
        if (!reconciled) _openSessionConflict(),
      ],
      loadOpenSessions: () async => [
        {'id': reconciled ? 'session-s4' : 'session-s1'},
      ],
      reconcileOriginalSession: ({required remoteOpenCashSessionId}) async {
        expect(remoteOpenCashSessionId, 'session-s4');
        reconciled = true;
        return true;
      },
      writeRuntimeContext: (context) async => written = context,
    );

    final result = await service.refresh(_request());

    expect(recovered, 2);
    expect(reconciled, isTrue);
    expect(result.openCashSessionId, 'session-s4');
    expect(written?.cashSessionId, 'session-s4');
    expect(written?.cashRegisterId, 'register-a');
  });

  test('C remote S3 still open fails closed without parallel session',
      () async {
    var reconciled = false;
    final service = _service(
      runtime: _runtime(openCashSessionId: 'session-s1'),
      recoverCash: (_) async => _recovery(openCashSessionId: 'session-s1'),
      loadOpenSessions: () async => [
        {'id': 'session-s1'},
      ],
      reconcileOriginalSession: ({required remoteOpenCashSessionId}) async {
        reconciled = true;
        return true;
      },
    );

    await expectLater(
      service.refresh(_request()),
      throwsA(
        isA<CashRepairContextException>().having(
          (error) => error.message,
          'message',
          contains('continúa abierta'),
        ),
      ),
    );
    expect(reconciled, isFalse);
  });
}

CashRepairContextService _service({
  ResolvedBusinessRuntime? runtime,
  CashRepairRuntimeResolver? resolveRuntime,
  Future<CashPosRecoveryResult> Function(CashPosRecoveryRequest)? recoverCash,
  List<Map<String, dynamic>> blockers = const [],
  Future<List<Map<String, dynamic>>> Function()? loadBlockingIssues,
  Future<List<Map<String, dynamic>>> Function()? loadOpenSessions,
  Future<void> Function(AppRuntimeContext)? writeRuntimeContext,
  Future<bool> Function({required String? remoteOpenCashSessionId})?
      reconcileOriginalSession,
}) {
  return CashRepairContextService(
    authenticatedProfileId: () => 'profile-a',
    resolveRuntime: resolveRuntime ??
        ({
          required profileId,
          required businessId,
          required branchId,
        }) async =>
            runtime ?? _runtime(),
    recoverCash: recoverCash ?? (_) async => _recovery(),
    loadOpenBlockingIssues: ({
      required profileId,
      required businessId,
      required branchId,
    }) async {
      if (loadBlockingIssues == null) return blockers;
      return loadBlockingIssues();
    },
    loadOpenSessions: ({
      required businessId,
      required branchId,
      required cashRegisterId,
    }) async {
      if (loadOpenSessions == null) return const <Map<String, dynamic>>[];
      return loadOpenSessions();
    },
    writeRuntimeContext: writeRuntimeContext ?? (_) async {},
    reconcileOriginalSession: ({
      required profileId,
      required businessId,
      required branchId,
      required cashRegisterId,
      required originalCashSessionId,
      required String? remoteOpenCashSessionId,
      required saleId,
    }) async {
      if (reconcileOriginalSession == null) return false;
      return reconcileOriginalSession(
        remoteOpenCashSessionId: remoteOpenCashSessionId,
      );
    },
  );
}

CashRepairContextRequest _request({
  Set<String> effectivePermissions = const {'cash.open'},
}) {
  return CashRepairContextRequest(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-a',
    installationId: 'installation-a',
    appDeviceId: 'device-a',
    cashRegisterId: 'register-a',
    originalCashSessionId: 'session-s1',
    saleId: 'sale-a',
    effectivePermissions: effectivePermissions,
  );
}

ResolvedBusinessRuntime _runtime({String? openCashSessionId}) {
  return ResolvedBusinessRuntime(
    profileId: 'profile-a',
    businessId: 'business-a',
    businessName: 'Business A',
    branchId: 'branch-a',
    branchName: 'Principal',
    cashRegisterId: 'register-a',
    cashRegisterName: 'Caja A',
    receiptSequenceId: 'sequence-a',
    receiptSequenceName: 'Sequence A',
    receiptPrefix: 'A',
    openCashSession: openCashSessionId == null
        ? null
        : ResolvedOpenCashSession(
            cashSessionId: openCashSessionId,
            cashRegisterId: 'register-a',
            status: 'open',
            openedBy: 'profile-a',
            openedAt: DateTime.utc(2026, 9, 2),
          ),
    runtimeReady: true,
    resolvedAt: DateTime.utc(2026, 9, 2),
  );
}

CashPosRecoveryResult _recovery({String? openCashSessionId = 'session-s2'}) {
  return CashPosRecoveryResult(
    snapshotId: 'snapshot-a',
    cashContextReady: false,
    canonicalCashRegisterId: 'register-a',
    openCashSessionId: openCashSessionId,
    recoveredSalesCount: 0,
    blockingIssues: 1,
    completed: true,
  );
}

Map<String, dynamic> _staleSaleBlocker() => {
      'domain': 'cash_pos',
      'entity_type': 'sales',
      'entity_id': 'sale-a',
      'issue_type': 'sale_cash_session_rejected',
      'severity': 'blocking',
      'status': 'open',
    };

Map<String, dynamic> _openSessionConflict() => {
      'domain': 'cash_pos',
      'entity_type': 'cash_sessions',
      'entity_id': 'session-s1',
      'issue_type': 'cash_open_session_conflict',
      'severity': 'blocking',
      'status': 'open',
    };
