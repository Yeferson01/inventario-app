import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/app_context_models.dart';
import '../data/models/inventory_history_models.dart';
import 'inventory_history_providers.dart';
import 'inventory_history_service.dart';

enum InventoryHistoryScreenPhase {
  initialLoading,
  ready,
  emptyOnline,
  emptyOffline,
  error,
}

enum InventoryHistoryScreenNotice {
  connectionRequired,
  refreshFailed,
  loadOlderFailed,
  noAdditionalFilteredRows,
}

enum InventoryHistoryScreenFailure {
  accessDenied,
  unexpected,
}

class InventoryHistoryViewRequest {
  InventoryHistoryViewRequest({
    required this.context,
    String? productId,
  })  : productId = _normalizeOptional(productId),
        profileIdKey = _normalizeOptional(context.profileId),
        businessIdKey = context.businessId.trim(),
        branchIdKey = _normalizeOptional(context.branchId),
        authorizationContextReadyKey = context.authorizationContextReady,
        authorizationValidatedAtKey = context.authorizationValidatedAt?.toUtc(),
        permissionFingerprint = context.permissions.sorted().join('\u001f'),
        membershipFingerprint = _sortedFingerprint(
          context.applicableMembershipIds,
        );

  final AppCurrentContext context;
  final String? productId;

  // Family identity.
  //
  // Deliberately excludes context.isOnline. Connectivity changes must not
  // create a new controller/cache identity.
  final String? profileIdKey;
  final String businessIdKey;
  final String? branchIdKey;
  final bool authorizationContextReadyKey;
  final DateTime? authorizationValidatedAtKey;
  final String permissionFingerprint;
  final String membershipFingerprint;

  bool get canReadInventory => context.hasPermission('inventory.read');

  bool get canViewCosts => context.hasPermission('inventory.view_costs');

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is InventoryHistoryViewRequest &&
            other.profileIdKey == profileIdKey &&
            other.businessIdKey == businessIdKey &&
            other.branchIdKey == branchIdKey &&
            other.authorizationContextReadyKey ==
                authorizationContextReadyKey &&
            other.authorizationValidatedAtKey == authorizationValidatedAtKey &&
            other.permissionFingerprint == permissionFingerprint &&
            other.membershipFingerprint == membershipFingerprint &&
            other.productId == productId;
  }

  @override
  int get hashCode => Object.hash(
        profileIdKey,
        businessIdKey,
        branchIdKey,
        authorizationContextReadyKey,
        authorizationValidatedAtKey,
        permissionFingerprint,
        membershipFingerprint,
        productId,
      );
}

class InventoryHistoryScreenState {
  const InventoryHistoryScreenState({
    required this.phase,
    required this.rows,
    required this.canViewCosts,
    this.coverage,
    this.effectiveType,
    this.isRefreshing = false,
    this.isLoadingOlder = false,
    this.isOffline = false,
    this.hasMoreLocal = false,
    this.notice,
    this.failure,
  });

  factory InventoryHistoryScreenState.initial({
    required bool canViewCosts,
  }) {
    return InventoryHistoryScreenState(
      phase: InventoryHistoryScreenPhase.initialLoading,
      rows: const [],
      canViewCosts: canViewCosts,
    );
  }

  final InventoryHistoryScreenPhase phase;
  final List<InventoryMovementHistoryEntry> rows;
  final InventoryHistoryCoverage? coverage;

  /// Current local presentation filter.
  ///
  /// It does not alter the branch-wide hydration cursor.
  final String? effectiveType;

  final bool canViewCosts;
  final bool isRefreshing;
  final bool isLoadingOlder;
  final bool isOffline;

  /// True when the last local page was full, meaning that another cached
  /// page may exist. False does not necessarily mean end-of-history:
  /// [coverage.hasMoreRemote] may still be true.
  final bool hasMoreLocal;

  final InventoryHistoryScreenNotice? notice;
  final InventoryHistoryScreenFailure? failure;

  bool get hasRows => rows.isNotEmpty;

  bool get hasMoreRemote => coverage?.hasMoreRemote ?? true;

  bool get canLoadOlder => !isLoadingOlder && (hasMoreLocal || hasMoreRemote);

  InventoryHistoryScreenState copyWith({
    InventoryHistoryScreenPhase? phase,
    List<InventoryMovementHistoryEntry>? rows,
    Object? coverage = _unset,
    Object? effectiveType = _unset,
    bool? isRefreshing,
    bool? isLoadingOlder,
    bool? isOffline,
    bool? hasMoreLocal,
    Object? notice = _unset,
    Object? failure = _unset,
  }) {
    return InventoryHistoryScreenState(
      phase: phase ?? this.phase,
      rows: rows ?? this.rows,
      coverage: identical(coverage, _unset)
          ? this.coverage
          : coverage as InventoryHistoryCoverage?,
      effectiveType: identical(effectiveType, _unset)
          ? this.effectiveType
          : effectiveType as String?,
      canViewCosts: canViewCosts,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isOffline: isOffline ?? this.isOffline,
      hasMoreLocal: hasMoreLocal ?? this.hasMoreLocal,
      notice: identical(notice, _unset)
          ? this.notice
          : notice as InventoryHistoryScreenNotice?,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as InventoryHistoryScreenFailure?,
    );
  }
}

class InventoryHistoryController extends Notifier<InventoryHistoryScreenState> {
  InventoryHistoryController(this.request);

  static const int _pageSize = 50;

  final InventoryHistoryViewRequest request;

  int _filterRevision = 0;

  InventoryHistoryService get _service =>
      ref.read(inventoryHistoryServiceProvider);

  @override
  InventoryHistoryScreenState build() {
    final initial = InventoryHistoryScreenState.initial(
      canViewCosts: request.canViewCosts,
    );

    unawaited(
      Future<void>.microtask(_initialize),
    );

    return initial;
  }

  Future<void> refresh() async {
    if (state.isRefreshing) {
      return;
    }

    state = state.copyWith(
      isRefreshing: true,
      notice: null,
      failure: null,
    );

    await _performRefresh();
  }

  Future<void> reloadCached() async {
    try {
      final rows = await _loadLocalPage();
      final coverage = await _service.getCoverage(
        context: request.context,
      );

      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        rows: rows,
        coverage: coverage,
        phase: _phaseFor(
          rows: rows,
          isOffline: state.isOffline,
        ),
        hasMoreLocal: rows.length == _pageSize,
        notice: null,
        failure: null,
      );
    } on InventoryHistoryAccessException {
      _publishAccessDenied();
    } catch (_) {
      if (!ref.mounted) {
        return;
      }

      if (state.rows.isEmpty) {
        state = state.copyWith(
          phase: InventoryHistoryScreenPhase.error,
          failure: InventoryHistoryScreenFailure.unexpected,
        );
      } else {
        state = state.copyWith(
          notice: InventoryHistoryScreenNotice.refreshFailed,
        );
      }
    }
  }

  Future<void> setEffectiveType(String? effectiveType) async {
    final normalized = _normalizeOptional(effectiveType)?.toLowerCase();

    if (normalized == state.effectiveType) {
      return;
    }

    final revision = ++_filterRevision;

    state = state.copyWith(
      effectiveType: normalized,
      rows: const [],
      phase: InventoryHistoryScreenPhase.initialLoading,
      hasMoreLocal: false,
      notice: null,
      failure: null,
    );

    try {
      final rows = await _loadLocalPage(
        effectiveType: normalized,
      );
      final coverage = await _service.getCoverage(
        context: request.context,
      );

      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      state = state.copyWith(
        rows: rows,
        coverage: coverage,
        phase: _phaseFor(
          rows: rows,
          isOffline: state.isOffline,
        ),
        hasMoreLocal: rows.length == _pageSize,
      );
    } on InventoryHistoryAccessException {
      if (!ref.mounted || revision != _filterRevision) {
        return;
      }
      _publishAccessDenied();
    } catch (_) {
      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      state = state.copyWith(
        phase: InventoryHistoryScreenPhase.error,
        failure: InventoryHistoryScreenFailure.unexpected,
      );
    }
  }

  Future<void> loadOlder() async {
    if (state.isLoadingOlder) {
      return;
    }

    final revision = _filterRevision;
    final effectiveType = state.effectiveType;
    final previousRows = state.rows;
    final cursor = _cursorAfter(previousRows);

    state = state.copyWith(
      isLoadingOlder: true,
      notice: null,
    );

    try {
      var coverage = state.coverage ??
          await _service.getCoverage(
            context: request.context,
          );

      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      // Prefer rows that are already cached locally before doing network I/O.
      final localPage = await _loadLocalPage(
        cursor: cursor,
        effectiveType: effectiveType,
      );

      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      if (localPage.isNotEmpty) {
        state = state.copyWith(
          rows: _appendUnique(previousRows, localPage),
          coverage: coverage,
          phase: InventoryHistoryScreenPhase.ready,
          isLoadingOlder: false,
          hasMoreLocal: localPage.length == _pageSize,
          notice: null,
        );
        return;
      }

      if (!coverage.hasMoreRemote) {
        state = state.copyWith(
          coverage: coverage,
          isLoadingOlder: false,
          hasMoreLocal: false,
          notice: null,
        );
        return;
      }

      final result = await _service.loadOlder(
        context: request.context,
        limit: _pageSize,
      );

      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      coverage = result.coverage;

      if (result.outcome ==
          InventoryHistoryHydrationOutcome.connectionRequired) {
        state = state.copyWith(
          coverage: coverage,
          isLoadingOlder: false,
          isOffline: true,
          hasMoreLocal: false,
          notice: InventoryHistoryScreenNotice.connectionRequired,
        );
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.noCachedHistory) {
        state = state.copyWith(
          coverage: coverage,
          isLoadingOlder: false,
          isOffline: true,
          hasMoreLocal: false,
          phase: previousRows.isEmpty
              ? InventoryHistoryScreenPhase.emptyOffline
              : InventoryHistoryScreenPhase.ready,
          notice: InventoryHistoryScreenNotice.connectionRequired,
        );
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.noMoreRemote) {
        state = state.copyWith(
          coverage: coverage,
          isLoadingOlder: false,
          isOffline: false,
          hasMoreLocal: false,
          notice: null,
        );
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.hydrated) {
        final hydratedLocalPage = await _loadLocalPage(
          cursor: cursor,
          effectiveType: effectiveType,
        );

        if (!ref.mounted || revision != _filterRevision) {
          return;
        }

        final appended = _appendUnique(
          previousRows,
          hydratedLocalPage,
        );

        state = state.copyWith(
          rows: appended,
          coverage: coverage,
          phase: _phaseFor(
            rows: appended,
            isOffline: false,
          ),
          isLoadingOlder: false,
          isOffline: false,
          hasMoreLocal: hydratedLocalPage.length == _pageSize,
          notice: hydratedLocalPage.isEmpty && coverage.hasMoreRemote
              ? InventoryHistoryScreenNotice.noAdditionalFilteredRows
              : null,
        );
        return;
      }

      // Defensive fallback for any outcome not expected from loadOlder().
      state = state.copyWith(
        coverage: coverage,
        isLoadingOlder: false,
      );
    } on InventoryHistoryAccessException {
      if (!ref.mounted || revision != _filterRevision) {
        return;
      }
      _publishAccessDenied();
    } catch (_) {
      if (!ref.mounted || revision != _filterRevision) {
        return;
      }

      state = state.copyWith(
        isLoadingOlder: false,
        notice: InventoryHistoryScreenNotice.loadOlderFailed,
        phase: state.rows.isEmpty
            ? InventoryHistoryScreenPhase.error
            : InventoryHistoryScreenPhase.ready,
        failure: state.rows.isEmpty
            ? InventoryHistoryScreenFailure.unexpected
            : null,
      );
    }
  }

  Future<void> _initialize() async {
    try {
      final cachedRows = await _loadLocalPage();
      final coverage = await _service.getCoverage(
        context: request.context,
      );

      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        rows: cachedRows,
        coverage: coverage,
        phase: cachedRows.isEmpty
            ? InventoryHistoryScreenPhase.initialLoading
            : InventoryHistoryScreenPhase.ready,
        isRefreshing: true,
        hasMoreLocal: cachedRows.length == _pageSize,
        notice: null,
        failure: null,
      );

      await _performRefresh();
    } on InventoryHistoryAccessException {
      _publishAccessDenied();
    } catch (_) {
      if (!ref.mounted) {
        return;
      }

      state = state.copyWith(
        phase: state.rows.isEmpty
            ? InventoryHistoryScreenPhase.error
            : InventoryHistoryScreenPhase.ready,
        isRefreshing: false,
        notice: state.rows.isEmpty
            ? null
            : InventoryHistoryScreenNotice.refreshFailed,
        failure: state.rows.isEmpty
            ? InventoryHistoryScreenFailure.unexpected
            : null,
      );
    }
  }

  Future<void> _performRefresh() async {
    try {
      final result = await _service.refreshLatest(
        context: request.context,
        limit: _pageSize,
      );

      if (!ref.mounted) {
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.hydrated) {
        // Refresh resets only the visible pagination to the newest local page.
        // The branch-wide hydration tail remains intact in Drift.
        final rows = await _loadLocalPage();

        if (!ref.mounted) {
          return;
        }

        state = state.copyWith(
          rows: rows,
          coverage: result.coverage,
          phase: _phaseFor(
            rows: rows,
            isOffline: false,
          ),
          isRefreshing: false,
          isOffline: false,
          hasMoreLocal: rows.length == _pageSize,
          notice: null,
          failure: null,
        );
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.cachedOffline) {
        state = state.copyWith(
          coverage: result.coverage,
          phase: _phaseFor(
            rows: state.rows,
            isOffline: true,
          ),
          isRefreshing: false,
          isOffline: true,
          notice: null,
          failure: null,
        );
        return;
      }

      if (result.outcome == InventoryHistoryHydrationOutcome.noCachedHistory) {
        state = state.copyWith(
          rows: const [],
          coverage: result.coverage,
          phase: InventoryHistoryScreenPhase.emptyOffline,
          isRefreshing: false,
          isOffline: true,
          hasMoreLocal: false,
          notice: null,
          failure: null,
        );
        return;
      }

      // refreshLatest() currently should not return connectionRequired or
      // noMoreRemote, but keep the presentation contract defensive.
      state = state.copyWith(
        coverage: result.coverage,
        isRefreshing: false,
      );
    } on InventoryHistoryAccessException {
      _publishAccessDenied();
    } catch (_) {
      if (!ref.mounted) {
        return;
      }

      if (state.rows.isEmpty) {
        state = state.copyWith(
          phase: InventoryHistoryScreenPhase.error,
          isRefreshing: false,
          failure: InventoryHistoryScreenFailure.unexpected,
          notice: null,
        );
      } else {
        state = state.copyWith(
          phase: InventoryHistoryScreenPhase.ready,
          isRefreshing: false,
          notice: InventoryHistoryScreenNotice.refreshFailed,
          failure: null,
        );
      }
    }
  }

  Future<List<InventoryMovementHistoryEntry>> _loadLocalPage({
    InventoryHistoryCursor? cursor,
    String? effectiveType,
  }) {
    return _service.loadCachedHistory(
      context: request.context,
      productId: request.productId,
      effectiveType: effectiveType ?? state.effectiveType,
      cursor: cursor,
      limit: _pageSize,
    );
  }

  void _publishAccessDenied() {
    if (!ref.mounted) {
      return;
    }

    state = state.copyWith(
      rows: const [],
      phase: InventoryHistoryScreenPhase.error,
      isRefreshing: false,
      isLoadingOlder: false,
      hasMoreLocal: false,
      notice: null,
      failure: InventoryHistoryScreenFailure.accessDenied,
    );
  }

  static InventoryHistoryScreenPhase _phaseFor({
    required List<InventoryMovementHistoryEntry> rows,
    required bool isOffline,
  }) {
    if (rows.isNotEmpty) {
      return InventoryHistoryScreenPhase.ready;
    }

    return isOffline
        ? InventoryHistoryScreenPhase.emptyOffline
        : InventoryHistoryScreenPhase.emptyOnline;
  }

  static InventoryHistoryCursor? _cursorAfter(
    List<InventoryMovementHistoryEntry> rows,
  ) {
    if (rows.isEmpty) {
      return null;
    }

    final last = rows.last;
    return InventoryHistoryCursor(
      occurredAt: last.occurredAt,
      id: last.id,
    );
  }

  static List<InventoryMovementHistoryEntry> _appendUnique(
    List<InventoryMovementHistoryEntry> existing,
    List<InventoryMovementHistoryEntry> incoming,
  ) {
    if (incoming.isEmpty) {
      return existing;
    }

    final ids = existing.map((row) => row.id).toSet();
    final result = <InventoryMovementHistoryEntry>[...existing];

    for (final row in incoming) {
      if (ids.add(row.id)) {
        result.add(row);
      }
    }

    return List.unmodifiable(result);
  }
}

final inventoryHistoryControllerProvider = NotifierProvider.autoDispose.family<
    InventoryHistoryController,
    InventoryHistoryScreenState,
    InventoryHistoryViewRequest>(
  InventoryHistoryController.new,
);

String? _normalizeOptional(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }
  return normalized;
}

String _sortedFingerprint(Iterable<String> values) {
  final sorted = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList()
    ..sort();

  return sorted.join('\u001f');
}

const Object _unset = Object();
