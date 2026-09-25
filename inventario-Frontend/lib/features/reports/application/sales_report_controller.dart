import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/datasources/sales_report_remote_datasource.dart';
import '../data/models/sales_report_models.dart';
import 'sales_report_providers.dart';
import 'sales_report_service.dart';

enum SalesReportPreset { today, lastSevenDays, thisMonth, custom }

extension SalesReportPresetPresentation on SalesReportPreset {
  String get label => switch (this) {
        SalesReportPreset.today => 'Hoy',
        SalesReportPreset.lastSevenDays => 'Últimos 7 días',
        SalesReportPreset.thisMonth => 'Este mes',
        SalesReportPreset.custom => 'Personalizado',
      };
}

enum SalesReportScreenPhase {
  initialLoading,
  ready,
  unavailableOffline,
  unauthorized,
  error,
}

enum SalesReportScreenNotice { offlineCache, refreshFailed }

class SalesReportViewRequest {
  SalesReportViewRequest({
    required String profileId,
    required String businessId,
    required String branchId,
    required this.branchName,
    required Iterable<String> effectivePermissions,
    required this.authorizationContextReady,
    this.authorizationValidatedAt,
  })  : profileId = profileId.trim(),
        businessId = businessId.trim(),
        branchId = branchId.trim(),
        permissionFingerprint = _permissionFingerprint(effectivePermissions),
        effectivePermissions = Set.unmodifiable(
          effectivePermissions
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty),
        );

  final String profileId;
  final String businessId;
  final String branchId;
  final String branchName;
  final Set<String> effectivePermissions;
  final bool authorizationContextReady;
  final DateTime? authorizationValidatedAt;

  // Provider identity intentionally excludes connectivity. Going online or
  // offline must not destroy the selected preset or its visible cache.
  final String permissionFingerprint;

  bool get canViewSalesReports =>
      authorizationContextReady &&
      effectivePermissions.contains(salesReportCapability);

  bool get hasCompleteScope =>
      profileId.isNotEmpty && businessId.isNotEmpty && branchId.isNotEmpty;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SalesReportViewRequest &&
            other.profileId == profileId &&
            other.businessId == businessId &&
            other.branchId == branchId &&
            other.branchName == branchName &&
            other.permissionFingerprint == permissionFingerprint &&
            other.authorizationContextReady == authorizationContextReady &&
            other.authorizationValidatedAt?.toUtc() ==
                authorizationValidatedAt?.toUtc();
  }

  @override
  int get hashCode => Object.hash(
        profileId,
        businessId,
        branchId,
        branchName,
        permissionFingerprint,
        authorizationContextReady,
        authorizationValidatedAt?.toUtc(),
      );
}

class SalesReportScreenState {
  const SalesReportScreenState({
    required this.phase,
    required this.preset,
    required this.period,
    this.snapshot,
    this.isRefreshing = false,
    this.isOffline = false,
    this.notice,
  });

  factory SalesReportScreenState.initial({
    required SalesReportPreset preset,
    required SalesReportPeriod period,
  }) {
    return SalesReportScreenState(
      phase: SalesReportScreenPhase.initialLoading,
      preset: preset,
      period: period,
    );
  }

  final SalesReportScreenPhase phase;
  final SalesReportPreset preset;
  final SalesReportPeriod period;
  final SalesReportSnapshot? snapshot;
  final bool isRefreshing;
  final bool isOffline;
  final SalesReportScreenNotice? notice;

  // The UTC period is the single source of truth, including custom ranges.
  // These inclusive calendar dates are for display and picker initialization.
  DateTime get selectedStartDate => period.from.toLocal();

  DateTime get selectedEndDate {
    final exclusiveEnd = period.to.toLocal();
    return DateTime(
      exclusiveEnd.year,
      exclusiveEnd.month,
      exclusiveEnd.day - 1,
    );
  }

  SalesReportScreenState copyWith({
    SalesReportScreenPhase? phase,
    SalesReportPreset? preset,
    SalesReportPeriod? period,
    Object? snapshot = _unset,
    bool? isRefreshing,
    bool? isOffline,
    Object? notice = _unset,
  }) {
    return SalesReportScreenState(
      phase: phase ?? this.phase,
      preset: preset ?? this.preset,
      period: period ?? this.period,
      snapshot: identical(snapshot, _unset)
          ? this.snapshot
          : snapshot as SalesReportSnapshot?,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isOffline: isOffline ?? this.isOffline,
      notice: identical(notice, _unset)
          ? this.notice
          : notice as SalesReportScreenNotice?,
    );
  }
}

class SalesReportController extends Notifier<SalesReportScreenState> {
  SalesReportController(this.request);

  final SalesReportViewRequest request;

  int _selectionRevision = 0;
  Future<void>? _refreshInFlight;

  SalesReportService get _service => ref.read(salesReportServiceProvider);

  @override
  SalesReportScreenState build() {
    const preset = SalesReportPreset.today;
    final period = salesReportPeriodFor(
      preset,
      ref.read(salesReportClockProvider)(),
    );

    if (!request.hasCompleteScope || !request.canViewSalesReports) {
      return SalesReportScreenState(
        phase: SalesReportScreenPhase.unauthorized,
        preset: preset,
        period: period,
      );
    }

    unawaited(Future<void>.microtask(_initializeSelected));
    return SalesReportScreenState.initial(preset: preset, period: period);
  }

  Future<void> selectPreset(SalesReportPreset preset) async {
    if (preset == SalesReportPreset.custom) {
      throw ArgumentError('Custom periods require explicit calendar dates.');
    }
    if (state.preset == preset) return;

    final period = salesReportPeriodFor(
      preset,
      ref.read(salesReportClockProvider)(),
    );
    await _selectPeriod(preset, period);
  }

  /// Returns false without changing the period or querying on invalid input.
  Future<bool> selectCustomRange({
    required DateTime? startDate,
    required DateTime? endDate,
  }) async {
    if (startDate == null || endDate == null) return false;
    final SalesReportPeriod period;
    try {
      period = salesReportPeriodForDates(
        startDate: startDate,
        endDate: endDate,
      );
    } on ArgumentError {
      return false;
    }
    await _selectPeriod(SalesReportPreset.custom, period);
    return true;
  }

  Future<void> _selectPeriod(
    SalesReportPreset preset,
    SalesReportPeriod period,
  ) async {
    if (!request.hasCompleteScope || !request.canViewSalesReports) {
      _publishUnauthorized();
      return;
    }
    if (state.period.filterKey == period.filterKey) {
      state = state.copyWith(preset: preset);
      return;
    }
    _selectionRevision += 1;
    state = SalesReportScreenState.initial(preset: preset, period: period);
    await _initializeSelected();
  }

  Future<void> refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;

    final revision = _selectionRevision;
    final future = _refreshSelected(revision);
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _initializeSelected() async {
    final revision = _selectionRevision;
    final scope = _scopeFor(state.period);
    final cached = await _service.readCached(scope);
    if (!_isCurrent(revision)) return;

    if (cached.outcome == SalesReportCacheReadOutcome.unauthorized) {
      _publishUnauthorized();
      return;
    }

    if (cached.outcome == SalesReportCacheReadOutcome.available) {
      state = state.copyWith(
        phase: SalesReportScreenPhase.ready,
        snapshot: cached.snapshot,
        notice: null,
      );
    }

    final isOnline = await ref.read(salesReportOnlineCheckProvider)();
    if (!_isCurrent(revision)) return;

    if (!isOnline) {
      if (cached.outcome == SalesReportCacheReadOutcome.available) {
        state = state.copyWith(
          phase: SalesReportScreenPhase.ready,
          isOffline: true,
          notice: SalesReportScreenNotice.offlineCache,
        );
      } else {
        state = state.copyWith(
          phase: SalesReportScreenPhase.unavailableOffline,
          snapshot: null,
          isOffline: true,
          notice: null,
        );
      }
      return;
    }

    // A previous period may still be refreshing. Its result is revision-guarded;
    // finish that flight before requesting the newly selected period.
    final previousRefresh = _refreshInFlight;
    if (previousRefresh != null) await previousRefresh;
    if (!_isCurrent(revision)) return;
    await refresh();
  }

  Future<void> _refreshSelected(int revision) async {
    if (!request.hasCompleteScope || !request.canViewSalesReports) {
      _publishUnauthorized();
      return;
    }

    final isOnline = await ref.read(salesReportOnlineCheckProvider)();
    if (!_isCurrent(revision)) return;

    if (!isOnline) {
      if (state.snapshot != null) {
        state = state.copyWith(
          phase: SalesReportScreenPhase.ready,
          isRefreshing: false,
          isOffline: true,
          notice: SalesReportScreenNotice.offlineCache,
        );
      } else {
        state = state.copyWith(
          phase: SalesReportScreenPhase.unavailableOffline,
          isRefreshing: false,
          isOffline: true,
          notice: null,
        );
      }
      return;
    }

    state = state.copyWith(
      isRefreshing: true,
      isOffline: false,
      notice: null,
    );

    final result = await _service.refresh(_scopeFor(state.period));
    if (!_isCurrent(revision)) return;

    switch (result.outcome) {
      case SalesReportRefreshOutcome.refreshed:
        state = state.copyWith(
          phase: SalesReportScreenPhase.ready,
          snapshot: result.snapshot,
          isRefreshing: false,
          isOffline: false,
          notice: null,
        );
      case SalesReportRefreshOutcome.unauthorized:
        _publishUnauthorized();
      case SalesReportRefreshOutcome.remoteFailure:
        final preserved = result.preservedCache ?? state.snapshot;
        if (preserved != null) {
          state = state.copyWith(
            phase: SalesReportScreenPhase.ready,
            snapshot: preserved,
            isRefreshing: false,
            isOffline:
                result.failureKind == SalesReportRemoteFailureKind.network,
            notice: SalesReportScreenNotice.refreshFailed,
          );
        } else {
          state = state.copyWith(
            phase: SalesReportScreenPhase.error,
            snapshot: null,
            isRefreshing: false,
            isOffline:
                result.failureKind == SalesReportRemoteFailureKind.network,
            notice: null,
          );
        }
    }
  }

  SalesReportScope _scopeFor(SalesReportPeriod period) {
    return SalesReportScope(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      period: period,
    );
  }

  bool _isCurrent(int revision) =>
      ref.mounted && revision == _selectionRevision;

  void _publishUnauthorized() {
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: SalesReportScreenPhase.unauthorized,
      snapshot: null,
      isRefreshing: false,
      isOffline: false,
      notice: null,
    );
  }
}

SalesReportPeriod salesReportPeriodFor(
  SalesReportPreset preset,
  DateTime now,
) {
  final localNow = now.toLocal();
  final today = DateTime(localNow.year, localNow.month, localNow.day);

  final (from, to) = switch (preset) {
    SalesReportPreset.today => (
        today,
        DateTime(localNow.year, localNow.month, localNow.day + 1),
      ),
    SalesReportPreset.lastSevenDays => (
        DateTime(localNow.year, localNow.month, localNow.day - 6),
        DateTime(localNow.year, localNow.month, localNow.day + 1),
      ),
    SalesReportPreset.thisMonth => (
        DateTime(localNow.year, localNow.month),
        DateTime(localNow.year, localNow.month + 1),
      ),
    SalesReportPreset.custom =>
      throw ArgumentError('Custom periods require explicit calendar dates.'),
  };

  return SalesReportPeriod(from: from.toUtc(), to: to.toUtc());
}

SalesReportPeriod salesReportPeriodForDates({
  required DateTime startDate,
  required DateTime endDate,
}) {
  // Picker values are calendar dates, not instants. Strip the time before
  // constructing local boundaries; advance the calendar, never add 24 hours.
  final from = DateTime(startDate.year, startDate.month, startDate.day);
  final inclusiveEnd = DateTime(endDate.year, endDate.month, endDate.day);
  if (inclusiveEnd.isBefore(from)) {
    throw ArgumentError('End date must be on or after start date.');
  }
  final to = DateTime(endDate.year, endDate.month, endDate.day + 1);
  return SalesReportPeriod(from: from.toUtc(), to: to.toUtc());
}

final salesReportControllerProvider = NotifierProvider.autoDispose.family<
    SalesReportController, SalesReportScreenState, SalesReportViewRequest>(
  SalesReportController.new,
);

String _permissionFingerprint(Iterable<String> values) {
  final sorted = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return sorted.join('\u001f');
}

const Object _unset = Object();
