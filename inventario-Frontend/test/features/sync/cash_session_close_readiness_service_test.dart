import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/cash_session_close_readiness_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/cash_session_close_readiness_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  CashSessionCloseEvidence evidence({
    Map<String, dynamic>? session,
    List<Map<String, dynamic>> movements = const [],
    List<Map<String, dynamic>> mutations = const [],
    List<Map<String, dynamic>> issues = const [],
    int dirtyPosCount = 0,
  }) =>
      CashSessionCloseEvidence(
        session: session ??
            const {
              'id': 'S',
              'cash_register_id': 'R',
              'local_status': 'synced',
              'sync_status': 0,
            },
        cashMovements: movements,
        outboxMutations: mutations,
        dirtyPosCount: dirtyPosCount,
        openIssues: issues,
      );

  Future<CashSessionCloseReadinessResult> evaluate(
    CashSessionCloseEvidence current, {
    BatchDependencyReadiness dependency = BatchDependencyReadiness.ready,
  }) =>
      CashSessionCloseReadinessService(
        evidenceLoader: (
                {required profileId,
                required businessId,
                required branchId}) async =>
            current,
        dependencyReadinessLoader: (_) async => dependency,
      ).evaluate(
          profileId: 'profile', businessId: 'business', branchId: 'branch');

  test(
      'clean S is ready; unrelated business issue and resolved S2 do not block',
      () async {
    final result = await evaluate(evidence(issues: const [
      {
        'domain': 'catalog',
        'severity': 'blocking',
        'scope_resolution_status': 'unresolved'
      },
      {
        'domain': 'cash_pos',
        'entity_type': 'sales',
        'severity': 'blocking',
        'scope_resolution_status': 'resolved_session',
        'cash_session_id': 'S2'
      },
    ]));
    expect(result.readiness, CashSessionCloseReadiness.ready);
  });

  test('pending movement waits, failed movement blocks, applied clears',
      () async {
    expect(
        (await evaluate(evidence(movements: const [
          {'id': 'cm', 'local_status': 'dirty', 'sync_status': 1},
        ])))
            .readiness,
        CashSessionCloseReadiness.indeterminate);
    expect(
        (await evaluate(evidence(movements: const [
          {'id': 'cm', 'local_status': 'conflict', 'sync_status': 1},
        ])))
            .readiness,
        CashSessionCloseReadiness.blocked);
    expect(
        (await evaluate(evidence(movements: const [
          {'id': 'cm', 'local_status': 'synced', 'sync_status': 0},
        ])))
            .readiness,
        CashSessionCloseReadiness.ready);
  });

  test('transitive blocked dependency keeps S blocked', () async {
    final result = await evaluate(
        evidence(mutations: const [
          {
            'entity_table': 'cash_movements',
            'status': 'pending',
            'batch_id': 'CM'
          },
        ]),
        dependency: BatchDependencyReadiness.blocked);
    expect(result.readiness, CashSessionCloseReadiness.blocked);
  });

  test('POS issue on S blocks; unresolved same-register issue is indeterminate',
      () async {
    final blocked = await evaluate(evidence(issues: const [
      {
        'domain': 'cash_pos',
        'entity_type': 'sales',
        'severity': 'blocking',
        'scope_resolution_status': 'resolved_session',
        'cash_session_id': 'S'
      },
    ]));
    expect(blocked.readiness, CashSessionCloseReadiness.blocked);
    final unknown = await evaluate(evidence(issues: const [
      {
        'domain': 'cash_pos',
        'entity_type': 'cash_sessions',
        'severity': 'blocking',
        'scope_resolution_status': 'unresolved',
        'cash_register_id': 'R'
      },
    ]));
    expect(unknown.readiness, CashSessionCloseReadiness.indeterminate);
    final noSession = await evaluate(evidence(issues: const [
      {
        'domain': 'cash_pos',
        'entity_type': 'sales',
        'severity': 'blocking',
        'scope_resolution_status': 'resolved_no_session'
      },
    ]));
    expect(noSession.readiness, CashSessionCloseReadiness.ready);
  });

  test('provenance refresh evaluates the refreshed session state', () async {
    var current = evidence(
      session: const {
        'id': 'S',
        'cash_register_id': 'R',
        'local_status': 'dirty',
        'sync_status': 1,
      },
      issues: const [
        {
          'domain': 'cash_pos',
          'entity_type': 'sales',
          'severity': 'blocking',
          'scope_resolution_status': 'unresolved',
          'cash_register_id': 'R',
        },
      ],
    );
    final service = CashSessionCloseReadinessService(
      evidenceLoader: (
              {required profileId,
              required businessId,
              required branchId}) async =>
          current,
      dependencyReadinessLoader: (_) async => BatchDependencyReadiness.ready,
      provenanceRefresher: (
          {required profileId,
          required businessId,
          required branchId,
          required cashRegisterId,
          required appDeviceId}) async {
        expect(cashRegisterId, 'R');
        current = evidence();
      },
    );
    final result = await service.evaluate(
      profileId: 'profile',
      businessId: 'business',
      branchId: 'branch',
      appDeviceId: 'device',
    );
    expect(result.readiness, CashSessionCloseReadiness.ready);
    expect(result.sessionId, 'S');
  });
}
