import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_sync_service.dart';
import 'package:inventario_frontend/features/catalog/data/datasources/catalog_local_dao.dart';
import 'package:inventario_frontend/features/catalog/data/datasources/catalog_remote_datasource.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_local_models.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_remote_models.dart';
import 'package:inventario_frontend/features/catalog/data/repositories/catalog_local_repository.dart';

void main() {
  group('CatalogSyncService window resume', () {
    test('resumes after a 10k page budget without advancing the cursor',
        () async {
      final store = _MemoryCatalogSyncStore();
      final remote = _PagedCatalogRemote(totalRows: 10005);
      final service = CatalogSyncService(
        remoteDataSource: remote,
        localRepository: store,
      );

      final firstRun = await service.pullCatalogDelta(
        businessId: 'business-1',
        pageLimit: 500,
        maxPages: 20,
      );

      expect(firstRun.status, CatalogSyncRunStatus.incomplete);
      expect(firstRun.pagesPulled, 20);
      expect(firstRun.recordsReceived, 10000);
      expect(firstRun.committedCursorAdvanced, isFalse);
      expect(firstRun.nextPageTokenPresent, isTrue);
      expect(store.state['last_since_updated_at'], isNull);

      final restartedService = CatalogSyncService(
        remoteDataSource: remote,
        localRepository: store,
      );
      final secondRun = await restartedService.pullCatalogDelta(
        businessId: 'business-1',
        pageLimit: 500,
        maxPages: 20,
      );

      expect(secondRun.status, CatalogSyncRunStatus.complete);
      expect(secondRun.resumed, isTrue);
      expect(secondRun.pagesPulled, 1);
      expect(secondRun.recordsReceived, 5);
      expect(secondRun.committedCursorAdvanced, isTrue);
      expect(secondRun.nextPageTokenPresent, isFalse);
      expect(store.ids, hasLength(10005));
      expect(remote.requests, hasLength(21));
      expect(
          remote.requests.every((request) => request.includeDeleted), isTrue);
      expect(
        remote.requests.every((request) => request.sinceUpdatedAt == null),
        isTrue,
      );
    });
  });

  group('CatalogLocalDao convergence', () {
    late AppDatabase database;
    late CatalogLocalDao dao;

    setUp(() {
      database = AppDatabase.executor(NativeDatabase.memory());
      dao = CatalogLocalDao(database);
    });

    tearDown(() => database.close());

    test('applies newer tombstones and ignores old or local-dirty rows',
        () async {
      final first = await dao.applyCatalogDeltaRecords([
        _masterRecord(id: 'master-1', version: 3),
      ]);
      final staleTombstone = await dao.applyCatalogDeltaRecords([
        _masterRecord(
          id: 'master-1',
          version: 2,
          deletedAt: '2026-08-25T10:00:00Z',
        ),
      ]);

      expect(first.masterProductsUpserted, 1);
      expect(staleTombstone.staleRecordsIgnored, 1);
      expect((await _master(database, 'master-1'))['deleted_at'], isNull);

      final newerTombstone = await dao.applyCatalogDeltaRecords([
        _masterRecord(
          id: 'master-1',
          version: 4,
          deletedAt: '2026-08-25T11:00:00Z',
        ),
      ]);

      expect(newerTombstone.tombstonesApplied, 1);
      expect((await _master(database, 'master-1'))['deleted_at'], isNotNull);

      await database.customStatement(
        "update local_master_products_catalog set local_status = 'dirty' "
        "where id = 'master-1'",
      );
      final dirty = await dao.applyCatalogDeltaRecords([
        _masterRecord(id: 'master-1', version: 5),
      ]);

      expect(dirty.dirtyRecordsSkipped, 1);
      final preserved = await _master(database, 'master-1');
      expect(preserved['version'], 4);
      expect(preserved['deleted_at'], isNotNull);
    });

    test('rolls back page rows and checkpoint together', () async {
      await expectLater(
        dao.applyCatalogDeltaPage(
          businessId: 'business-1',
          records: [
            _masterRecord(id: 'master-valid', version: 1),
            {
              'entity_type': 'master_product',
              'payload': {'version': 1},
            },
          ],
          committedSince: null,
          windowUpperBound: DateTime.parse('2026-08-25T12:00:00Z'),
          catalogVersion: 1,
          pageToken: const {'token_version': 1, 'token': 'signed'},
          completed: false,
          isSyncing: false,
        ),
        throwsArgumentError,
      );

      final productCount = await database
          .customSelect(
            'select count(*) as count from local_master_products_catalog',
          )
          .getSingle();
      final stateCount = await database
          .customSelect(
            'select count(*) as count from local_catalog_sync_state',
          )
          .getSingle();

      expect(productCount.read<int>('count'), 0);
      expect(stateCount.read<int>('count'), 0);
    });
  });
}

Map<String, dynamic> _masterRecord({
  required String id,
  required int version,
  String? deletedAt,
}) {
  return {
    'entity_type': 'master_product',
    'payload': {
      'id': id,
      'name': 'Product $id',
      'product_name': 'Product $id',
      'version': version,
      'catalog_version': version,
      'sync_status': 'synced',
      'updated_at': '2026-08-25T09:00:00Z',
      'deleted_at': deletedAt,
    },
  };
}

Future<Map<String, dynamic>> _master(AppDatabase database, String id) async {
  final row = await database.customSelect(
    'select * from local_master_products_catalog where id = ?',
    variables: [Variable<String>(id)],
  ).getSingle();
  return Map<String, dynamic>.from(row.data);
}

class _PagedCatalogRemote implements CatalogRemoteDataSource {
  _PagedCatalogRemote({required this.totalRows});

  final int totalRows;
  final List<CatalogPullRequest> requests = [];
  final DateTime windowUpperBound = DateTime.parse('2026-08-25T12:00:00Z');

  @override
  Future<CatalogPullResponse> pullProductCatalogDelta(
    CatalogPullRequest request,
  ) async {
    requests.add(request);
    final offset = request.pageToken == null
        ? 0
        : int.parse(request.pageToken!['token'] as String);
    final end = (offset + request.limit).clamp(0, totalRows);
    final records = <Map<String, dynamic>>[
      for (var index = offset; index < end; index++)
        _masterRecord(id: 'master-$index', version: 1),
    ];
    final hasMore = end < totalRows;
    final nextToken =
        hasMore ? <String, dynamic>{'token_version': 1, 'token': '$end'} : null;
    final since =
        request.sinceUpdatedAt ?? DateTime.parse('1970-01-01T00:00:00Z');

    return CatalogPullResponse(
      records: records,
      serverTime: windowUpperBound,
      sinceUpdatedAt: since,
      catalogVersion: 1,
      nextPageToken: nextToken,
      hasMore: hasMore,
      complete: !hasMore,
      raw: const {},
    );
  }
}

class _MemoryCatalogSyncStore implements CatalogSyncLocalStore {
  final Map<String, dynamic> state = {};
  final Set<String> ids = {};

  @override
  Future<CatalogDeltaApplyResult> applyCatalogDeltaPage({
    required String businessId,
    required List<Map<String, dynamic>> records,
    required DateTime? committedSince,
    required DateTime windowUpperBound,
    required int? catalogVersion,
    required Map<String, dynamic>? pageToken,
    required bool completed,
    required bool isSyncing,
  }) async {
    for (final record in records) {
      final payload = Map<String, dynamic>.from(record['payload'] as Map);
      ids.add(payload['id'] as String);
    }
    state['last_server_time'] = windowUpperBound.toIso8601String();
    state['last_since_updated_at'] =
        completed ? windowUpperBound.toIso8601String() : committedSince;
    state['last_page_token'] = pageToken == null ? null : jsonEncode(pageToken);
    state['last_catalog_version'] = catalogVersion;
    state['is_syncing'] = isSyncing;

    return CatalogDeltaApplyResult(
      masterProductsUpserted: records.length,
      productBarcodesUpserted: 0,
      ignoredRecords: 0,
    );
  }

  @override
  Future<Map<String, dynamic>?> getCatalogSyncState(String businessId) async =>
      state.isEmpty ? null : state;

  @override
  Future<void> markCatalogSyncFailed({
    required String businessId,
    required Object error,
  }) async {
    state['is_syncing'] = false;
    state['last_error'] = error.toString();
  }

  @override
  Future<void> markCatalogSyncStarted(String businessId) async {
    state['is_syncing'] = true;
  }

  @override
  Future<void> resetCatalogSyncResume({
    required String businessId,
    required bool clearCommittedCursor,
  }) async {
    state['last_page_token'] = null;
    state['last_server_time'] = null;
    if (clearCommittedCursor) {
      state['last_since_updated_at'] = null;
    }
  }
}
