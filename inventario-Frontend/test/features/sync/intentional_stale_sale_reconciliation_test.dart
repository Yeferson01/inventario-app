import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/intentional_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';

void main() {
  const input = IntentionalStaleSaleReconciliationInput(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-a',
    appDeviceId: 'device-a',
    saleId: 'sale-a',
    syncConflictId: 'conflict-a',
    destinationCashSessionId: 'session-b',
    reconciliationId: 'reconciliation-a',
    idempotencyKey: 'reconcile:sale-a',
    reason: 'La venta real quedó asociada a una sesión cerrada.',
    cashTreatment:
        IntentionalStaleSaleCashTreatment.alreadyIncludedInDestinationOpening,
    confirmedSaleDidOccur: true,
  );

  test('productive retry identity is stable for the same Sale', () {
    const saleId = '01a05831-1c20-72b9-a146-1b43e285b143';

    final first = buildStaleSaleReconciliationIdentity(saleId);
    final retry = buildStaleSaleReconciliationIdentity('  $saleId  ');

    expect(retry, first);
    expect(first.reconciliationId, saleId);
    expect(
      first.idempotencyKey,
      'stale-sale-reconciliation:$saleId',
    );
  });

  test('success projects canonical state without a second stock decrement',
      () async {
    var inventoryRefreshes = 0;
    var cashRefreshes = 0;
    final service = IntentionalStaleSaleReconciliationService(
      remoteExecutor: _successfulRemote,
      localPreviewLoader: _localPreview,
      localProjector: ({
        required profileId,
        required businessId,
        required branchId,
        required saleId,
        required destinationCashSessionId,
        required reconciliationId,
        required cashTreatment,
        required reason,
      }) async {
        expect(destinationCashSessionId, 'session-b');
        return const IntentionalStaleSaleLocalProjectionResult(
          saleId: 'sale-a',
          alreadyProjected: false,
          movementsAcknowledged: 1,
          mutationsSuperseded: 3,
          issuesResolved: 1,
          stockByProductBefore: {'product-a': 25},
          stockByProductAfter: {'product-a': 25},
        );
      },
      inventoryRefresher: (_, __) async => inventoryRefreshes++,
      cashRefresher: (_, __) async => cashRefreshes++,
    );

    final result = await service.reconcile(input);

    expect(result.local.stockByProductAfter, result.local.stockByProductBefore);
    expect(result.remote.cashAdjustmentAmount, -10);
    expect(inventoryRefreshes, 1);
    expect(cashRefreshes, 1);
  });

  test('remote rejection leaves local projection, stock and blocker untouched',
      () async {
    var projected = false;
    var refreshed = false;
    final service = IntentionalStaleSaleReconciliationService(
      remoteExecutor: ({
        required businessId,
        required branchId,
        required appDeviceId,
        required saleId,
        required syncConflictId,
        required destinationCashSessionId,
        required reconciliationId,
        required idempotencyKey,
        required reason,
        required cashTreatment,
      }) async {
        throw StateError('destination_cash_session_required');
      },
      localPreviewLoader: _localPreview,
      localProjector: ({
        required profileId,
        required businessId,
        required branchId,
        required saleId,
        required destinationCashSessionId,
        required reconciliationId,
        required cashTreatment,
        required reason,
      }) async {
        projected = true;
        throw StateError('must not project');
      },
      inventoryRefresher: (_, __) async => refreshed = true,
      cashRefresher: (_, __) async => refreshed = true,
    );

    await expectLater(
      service.reconcile(input),
      throwsA(
        isA<IntentionalStaleSaleReconciliationException>().having(
          (error) => error.kind,
          'kind',
          IntentionalStaleSaleReconciliationFailureKind.remoteRejected,
        ),
      ),
    );
    expect(projected, isFalse);
    expect(refreshed, isFalse);
  });
}

Future<IntentionalStaleSaleLocalPreview> _localPreview({
  required String businessId,
  required String branchId,
  required String saleId,
  required String destinationCashSessionId,
}) async {
  return IntentionalStaleSaleLocalPreview(
    saleId: saleId,
    saleTotal: 10,
    cashTotal: 10,
    originalCashSessionId: 'session-a',
    destinationCashSessionId: destinationCashSessionId,
    destinationOpeningAmount: 110,
    destinationCurrentCashPayments: 0,
    affectedStock: const [
      IntentionalStaleSaleAffectedStock(
        productId: 'product-a',
        productName: 'Product A',
        soldQuantity: 1,
        currentQuantityOnHand: 25,
      ),
    ],
  );
}

Future<IntentionalStaleSaleRemoteResult> _successfulRemote({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
  required String syncConflictId,
  required String destinationCashSessionId,
  required String reconciliationId,
  required String idempotencyKey,
  required String reason,
  required String cashTreatment,
}) async {
  return IntentionalStaleSaleRemoteResult(
    reconciliationId: reconciliationId,
    businessId: businessId,
    branchId: branchId,
    saleId: saleId,
    cashRegisterId: 'register-a',
    originalCashSessionId: 'session-a',
    destinationCashSessionId: destinationCashSessionId,
    syncConflictId: syncConflictId,
    cashTreatment: cashTreatment,
    cashReconciledTotal: 10,
    cashAdjustmentTotal: 10,
    cashAdjustmentAmount: -10,
    projectedExpectedCash: 110,
    status: 'completed',
    idempotent: false,
  );
}
