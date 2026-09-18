import '../../sync/application/app_context_models.dart';
import '../data/datasources/inventory_history_local_dao.dart';
import '../data/datasources/inventory_history_remote_datasource.dart';
import '../data/models/inventory_history_models.dart';

typedef InventoryHistoryOnlineCheck = Future<bool> Function();

class InventoryHistoryAccessException implements Exception {
  const InventoryHistoryAccessException(this.message);

  final String message;

  @override
  String toString() => 'InventoryHistoryAccessException: $message';
}

class InventoryHistoryService {
  InventoryHistoryService({
    required InventoryHistoryLocalDao localDao,
    required InventoryHistoryRemoteDatasource remoteDatasource,
    required InventoryHistoryOnlineCheck isOnline,
  })  : _localDao = localDao,
        _remoteDatasource = remoteDatasource,
        _isOnline = isOnline;

  final InventoryHistoryLocalDao _localDao;
  final InventoryHistoryRemoteDatasource _remoteDatasource;
  final InventoryHistoryOnlineCheck _isOnline;

  Future<InventoryHistoryHydrationResult> refreshLatest({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    final branchId = _validateContext(context);
    final before = await _localDao.getCoverage(
      businessId: context.businessId,
      branchId: branchId,
    );
    if (!await _isOnline()) {
      return InventoryHistoryHydrationResult(
        outcome: before.hasCachedRows
            ? InventoryHistoryHydrationOutcome.cachedOffline
            : InventoryHistoryHydrationOutcome.noCachedHistory,
        coverage: before,
      );
    }

    final page = await _remoteDatasource.loadBranchPage(
      businessId: context.businessId,
      branchId: branchId,
      limit: limit,
    );
    await _localDao.applyRefreshPage(
      businessId: context.businessId,
      branchId: branchId,
      page: page,
      canViewCosts: context.hasPermission('inventory.view_costs'),
    );
    final coverage = await _localDao.getCoverage(
      businessId: context.businessId,
      branchId: branchId,
    );
    return InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.hydrated,
      coverage: coverage,
      rowsApplied: page.rows.length,
    );
  }

  Future<InventoryHistoryHydrationResult> loadOlder({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    final branchId = _validateContext(context);
    final before = await _localDao.getCoverage(
      businessId: context.businessId,
      branchId: branchId,
    );
    if (!await _isOnline()) {
      return InventoryHistoryHydrationResult(
        outcome: before.hasCachedRows
            ? InventoryHistoryHydrationOutcome.connectionRequired
            : InventoryHistoryHydrationOutcome.noCachedHistory,
        coverage: before,
      );
    }
    if (!before.hasMoreRemote) {
      return InventoryHistoryHydrationResult(
        outcome: InventoryHistoryHydrationOutcome.noMoreRemote,
        coverage: before,
      );
    }
    final cursor = before.oldestCursor;
    if (cursor == null) {
      return refreshLatest(context: context, limit: limit);
    }

    final page = await _remoteDatasource.loadBranchPage(
      businessId: context.businessId,
      branchId: branchId,
      cursor: cursor,
      limit: limit,
    );
    await _localDao.applyOlderPage(
      businessId: context.businessId,
      branchId: branchId,
      page: page,
      canViewCosts: context.hasPermission('inventory.view_costs'),
    );
    final coverage = await _localDao.getCoverage(
      businessId: context.businessId,
      branchId: branchId,
    );
    return InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.hydrated,
      coverage: coverage,
      rowsApplied: page.rows.length,
    );
  }

  Future<List<InventoryMovementHistoryEntry>> loadCachedHistory({
    required AppCurrentContext context,
    String? productId,
    String? effectiveType,
    DateTime? from,
    DateTime? to,
    InventoryHistoryCursor? cursor,
    int limit = 50,
  }) {
    final branchId = _validateContext(context);
    return _localDao.loadHistory(
      query: InventoryHistoryLocalQuery(
        businessId: context.businessId,
        branchId: branchId,
        productId: productId,
        effectiveType: effectiveType,
        from: from,
        to: to,
        cursor: cursor,
        limit: limit,
      ),
      canViewCosts: context.hasPermission('inventory.view_costs'),
    );
  }

  Future<InventoryHistoryCoverage> getCoverage({
    required AppCurrentContext context,
  }) {
    final branchId = _validateContext(context);
    return _localDao.getCoverage(
      businessId: context.businessId,
      branchId: branchId,
    );
  }

  String _validateContext(AppCurrentContext context) {
    final branchId = context.branchId?.trim();
    if (context.profileId == null ||
        branchId == null ||
        branchId.isEmpty ||
        !context.authorizationContextReady ||
        !context.hasPermission('inventory.read')) {
      throw const InventoryHistoryAccessException(
        'An active branch context with inventory.read is required.',
      );
    }
    return branchId;
  }
}
