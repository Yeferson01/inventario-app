import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/operational_bootstrap_test_data.dart';

void main() {
  const focusedRequest = OperationalBootstrapRemoteRequest(
    businessId: 'business-a',
    branchId: 'branch-x',
    appDeviceId: 'device-a',
    bundle: 'product_operational',
    dataset: 'products',
    limit: 1000,
  );

  test('parses first page JSON and sends the exact focused RPC contract',
      () async {
    Map<String, Object?>? captured;
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (parameters) async {
        captured = parameters;
        return bootstrapRpcResponse();
      },
    );

    final response = await datasource.pullPage(focusedRequest);

    expect(response.snapshotId, 'snapshot-1');
    expect(response.datasets['products']?.count, 1);
    expect(captured, {
      'p_business_id': 'business-a',
      'p_branch_id': 'branch-x',
      'p_app_device_id': 'device-a',
      'p_bundle': 'product_operational',
      'p_dataset': 'products',
      'p_limit_per_dataset': 1000,
      'p_page_token': null,
    });
  });

  test('passes continuation token opaquely without decoding or rebuilding it',
      () async {
    const opaqueToken = 'signed.opaque+/token==';
    Map<String, Object?>? captured;
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (parameters) async {
        captured = parameters;
        return bootstrapRpcResponse();
      },
    );

    await datasource.pullPage(
      const OperationalBootstrapRemoteRequest(
        businessId: 'business-a',
        branchId: 'branch-x',
        appDeviceId: 'device-a',
        bundle: 'product_operational',
        dataset: 'products',
        pageToken: opaqueToken,
      ),
    );

    expect(captured?['p_page_token'], same(opaqueToken));
  });

  test('supports dataset null for a full bundle', () async {
    Map<String, Object?>? captured;
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (parameters) async {
        captured = parameters;
        return bootstrapRpcResponse(
          datasetRequested: null,
          datasets: {
            'categories': bootstrapDatasetPage(dataset: 'categories'),
            'products': bootstrapDatasetPage(dataset: 'products'),
          },
        );
      },
    );

    final response = await datasource.pullPage(
      const OperationalBootstrapRemoteRequest(
        businessId: 'business-a',
        branchId: 'branch-x',
        appDeviceId: 'device-a',
        bundle: 'product_operational',
      ),
    );

    expect(captured?['p_dataset'], isNull);
    expect(response.datasets.keys, ['categories', 'products']);
  });

  test('supports focal product_stock_balances dataset', () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => bootstrapRpcResponse(
        datasetRequested: 'product_stock_balances',
        datasets: {
          'product_stock_balances': bootstrapDatasetPage(
            dataset: 'product_stock_balances',
          ),
        },
      ),
    );

    final response = await datasource.pullPage(
      const OperationalBootstrapRemoteRequest(
        businessId: 'business-a',
        branchId: 'branch-x',
        appDeviceId: 'device-a',
        bundle: 'product_operational',
        dataset: 'product_stock_balances',
      ),
    );

    expect(response.datasetRequested, 'product_stock_balances');
  });

  test('parses tombstone record state without mapping a productive entity',
      () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => bootstrapRpcResponse(
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: const [
              {
                'id': 'product-deleted',
                'deleted_at': '2026-08-15T08:00:00Z',
                '_bootstrap_record_state': 'tombstone',
              },
            ],
          ),
        },
      ),
    );

    final response = await datasource.pullPage(focusedRequest);

    expect(
      response.datasets['products']?.rows.single.state,
      OperationalBootstrapRecordState.tombstone,
    );
  });

  test('rejects malformed pagination contract', () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => bootstrapRpcResponse(
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            hasMore: true,
          ),
        },
      ),
    );

    await expectLater(
      datasource.pullPage(focusedRequest),
      throwsA(
        isA<OperationalBootstrapException>().having(
          (error) => error.kind,
          'kind',
          OperationalBootstrapFailureKind.malformedResponse,
        ),
      ),
    );
  });

  test('rejects a response outside the requested remote scope', () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => bootstrapRpcResponse(branchId: 'branch-y'),
    );

    await expectLater(
      datasource.pullPage(focusedRequest),
      throwsA(
        isA<OperationalBootstrapException>().having(
          (error) => error.kind,
          'kind',
          OperationalBootstrapFailureKind.scopeMismatch,
        ),
      ),
    );
  });

  test('classifies signed token failures as restart-required errors', () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => throw const PostgrestException(
        message: 'Invalid operational bootstrap page token',
        code: 'P0001',
      ),
    );

    await expectLater(
      datasource.pullPage(focusedRequest),
      throwsA(
        isA<OperationalBootstrapException>().having(
          (error) => error.kind,
          'kind',
          OperationalBootstrapFailureKind.invalidToken,
        ),
      ),
    );
  });

  test('classifies revoked membership as forbidden context', () async {
    final datasource = OperationalBootstrapRemoteDataSource.withInvoker(
      (_) async => throw const PostgrestException(
        message: 'No active membership grants access to this branch',
        code: 'P0001',
      ),
    );

    await expectLater(
      datasource.pullPage(focusedRequest),
      throwsA(
        isA<OperationalBootstrapException>().having(
          (error) => error.kind,
          'kind',
          OperationalBootstrapFailureKind.forbidden,
        ),
      ),
    );
  });
}
