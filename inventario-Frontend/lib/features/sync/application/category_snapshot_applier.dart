import '../data/datasources/product_operational_reconciliation_local_dao.dart';
import '../data/models/catalog_entity_reconciliation_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import '../data/models/product_operational_snapshot_models.dart';
import 'operational_bootstrap_page_applier.dart';
import 'product_operational_reconciliation_support.dart';

class CategorySnapshotApplier
    implements
        OperationalBootstrapPageApplier,
        OperationalBootstrapDatasetFinalizer {
  CategorySnapshotApplier({
    required ProductOperationalReconciliationLocalDao localDao,
    required ProductOperationalReconciliationSupport support,
  })  : _localDao = localDao,
        _support = support;

  final ProductOperationalReconciliationLocalDao _localDao;
  final ProductOperationalReconciliationSupport _support;

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    _support.validatePage(snapshot, page, 'categories');
    final seen = <String>[];
    for (final row in page.rows) {
      final remote = ProductOperationalCategorySnapshot.fromRow(row);
      _support.validateBusiness(snapshot.businessId, remote.businessId);
      seen.add(remote.id);
      final local = await _localDao.getCategory(remote.id);
      if (local == null) {
        if (row.state == OperationalBootstrapRecordState.present) {
          await _localDao.upsertCategory(remote);
        }
        continue;
      }
      final classification = await _support.classify(
        snapshot.businessId,
        'categories',
        local,
      );
      if (classification.canAcceptRemote) {
        await _localDao.upsertCategory(remote);
        continue;
      }
      await _recordPreservedIssue(
        profileId: profileId,
        snapshot: snapshot,
        remote: remote,
        local: local,
        classification: classification,
        tombstone: row.state == OperationalBootstrapRecordState.tombstone,
      );
    }
    return OperationalBootstrapPageApplyResult(seenEntityIds: seen);
  }

  @override
  Future<void> finalizeDataset({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    _support.validatePage(snapshot, page, 'categories');
    final seen = await _support.seenIds(
      profileId: profileId,
      snapshot: snapshot,
      dataset: page.dataset,
    );
    for (final local
        in await _localDao.categoriesForSweep(snapshot.businessId)) {
      final id = local['id'].toString();
      if (seen.contains(id)) {
        continue;
      }
      final classification = await _support.classify(
        snapshot.businessId,
        'categories',
        local,
      );
      if (_support.outsideSnapshotIdentityWindow(
        local,
        classification,
        snapshot.snapshotAt,
      )) {
        continue;
      }
      if (classification.canAcceptRemote) {
        await _localDao.softInvalidateCategory(
          id: id,
          businessId: snapshot.businessId,
          invalidatedAt: snapshot.snapshotAt,
        );
      } else {
        await _support.openIssue(
          profileId: profileId,
          snapshot: snapshot,
          entityType: 'categories',
          entityId: id,
          issueType: classification.state ==
                  CatalogEntityReconciliationState.dirtyWithoutOutbox
              ? 'dirty_without_outbox'
              : 'dirty_absent_from_remote',
          severity: classification.state ==
                  CatalogEntityReconciliationState.dirtyWithoutOutbox
              ? 'blocking'
              : 'warning',
          message:
              'Local category was preserved because it is dirty and absent from the authoritative snapshot.',
          classification: classification,
        );
      }
    }
  }

  Future<void> _recordPreservedIssue({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required ProductOperationalCategorySnapshot remote,
    required Map<String, dynamic> local,
    required CatalogEntityReconciliationClassification classification,
    required bool tombstone,
  }) async {
    final equivalent = _support.categoryEquivalent(local, remote);
    if (!tombstone &&
        equivalent &&
        classification.state !=
            CatalogEntityReconciliationState.dirtyWithoutOutbox) {
      return;
    }
    final anomalous = classification.state ==
        CatalogEntityReconciliationState.dirtyWithoutOutbox;
    await _support.openIssue(
      profileId: profileId,
      snapshot: snapshot,
      entityType: 'categories',
      entityId: remote.id,
      issueType: anomalous
          ? 'dirty_without_outbox'
          : tombstone
              ? 'dirty_vs_tombstone'
              : 'dirty_vs_remote',
      severity:
          tombstone || (anomalous && !equivalent) ? 'blocking' : 'warning',
      message: tombstone
          ? 'Dirty local category was preserved instead of applying a remote tombstone.'
          : 'Dirty local category was preserved instead of applying the remote payload.',
      classification: classification,
    );
  }
}
