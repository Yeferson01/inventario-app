import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/cash_flow_report_models.dart';
import '../data/models/sales_report_models.dart';
import 'cash_flow_report_providers.dart';
import 'cash_flow_report_service.dart';
import 'sales_report_controller.dart';
import 'sales_report_providers.dart';

enum CashFlowPreset { today, thisWeek, thisMonth, thisYear, custom }

extension CashFlowPresetLabel on CashFlowPreset {
  String get label => switch (this) {
        CashFlowPreset.today => 'Hoy',
        CashFlowPreset.thisWeek => 'Esta semana',
        CashFlowPreset.thisMonth => 'Este mes',
        CashFlowPreset.thisYear => 'Este año',
        CashFlowPreset.custom => 'Personalizado',
      };
}

enum CashFlowPhase { loading, ready, unavailableOffline, unauthorized, error }

enum CashFlowNotice { offlineCache, refreshFailed }

class CashFlowScreenState {
  const CashFlowScreenState(
      {required this.phase,
      required this.preset,
      required this.period,
      this.snapshot,
      this.isRefreshing = false,
      this.notice});
  final CashFlowPhase phase;
  final CashFlowPreset preset;
  final SalesReportPeriod period;
  final CashFlowReportSnapshot? snapshot;
  final bool isRefreshing;
  final CashFlowNotice? notice;

  DateTime get startDate => period.from.toLocal();
  DateTime get endDate {
    final end = period.to.toLocal();
    return DateTime(end.year, end.month, end.day - 1);
  }

  CashFlowScreenState copyWith(
          {CashFlowPhase? phase,
          CashFlowPreset? preset,
          SalesReportPeriod? period,
          Object? snapshot = _unset,
          bool? isRefreshing,
          Object? notice = _unset}) =>
      CashFlowScreenState(
        phase: phase ?? this.phase,
        preset: preset ?? this.preset,
        period: period ?? this.period,
        snapshot: identical(snapshot, _unset)
            ? this.snapshot
            : snapshot as CashFlowReportSnapshot?,
        isRefreshing: isRefreshing ?? this.isRefreshing,
        notice:
            identical(notice, _unset) ? this.notice : notice as CashFlowNotice?,
      );
}

class CashFlowReportController extends Notifier<CashFlowScreenState> {
  CashFlowReportController(this.request);
  final SalesReportViewRequest request;
  int _revision = 0;
  Future<void>? _flight;
  CashFlowReportService get _service => ref.read(cashFlowReportServiceProvider);

  @override
  CashFlowScreenState build() {
    final period = cashFlowPeriodFor(
        CashFlowPreset.today, ref.read(salesReportClockProvider)());
    if (!request.hasCompleteScope ||
        !request.authorizationContextReady ||
        !request.effectivePermissions.contains(cashFlowReportCapability)) {
      return CashFlowScreenState(
          phase: CashFlowPhase.unauthorized,
          preset: CashFlowPreset.today,
          period: period);
    }
    unawaited(Future<void>.microtask(_initialize));
    return CashFlowScreenState(
        phase: CashFlowPhase.loading,
        preset: CashFlowPreset.today,
        period: period);
  }

  Future<void> selectPreset(CashFlowPreset preset) async {
    if (preset == CashFlowPreset.custom) {
      throw ArgumentError('Custom period needs dates');
    }
    if (state.preset == preset) return;
    await _select(preset,
        cashFlowPeriodFor(preset, ref.read(salesReportClockProvider)()));
  }

  Future<bool> selectCustomRange(DateTime? start, DateTime? end) async {
    if (start == null || end == null) return false;
    final SalesReportPeriod period;
    try {
      period = salesReportPeriodForDates(startDate: start, endDate: end);
    } on ArgumentError {
      return false;
    }
    await _select(CashFlowPreset.custom, period);
    return true;
  }

  Future<void> _select(CashFlowPreset preset, SalesReportPeriod period) async {
    if (state.period.filterKey == period.filterKey) {
      state = state.copyWith(preset: preset);
      return;
    }
    _revision++;
    state = CashFlowScreenState(
        phase: CashFlowPhase.loading, preset: preset, period: period);
    await _initialize();
  }

  SalesReportScope get _scope => SalesReportScope(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      period: state.period);

  Future<void> _initialize() async {
    final revision = _revision;
    final cached = await _service.readCached(_scope);
    if (!ref.mounted || revision != _revision) return;
    if (cached.outcome == CashFlowCacheOutcome.unauthorized) {
      state = state.copyWith(phase: CashFlowPhase.unauthorized, snapshot: null);
      return;
    }
    if (cached.snapshot != null) {
      state =
          state.copyWith(phase: CashFlowPhase.ready, snapshot: cached.snapshot);
    }
    final online = await ref.read(salesReportOnlineCheckProvider)();
    if (!ref.mounted || revision != _revision) return;
    if (!online) {
      state = state.copyWith(
          phase: cached.snapshot == null
              ? CashFlowPhase.unavailableOffline
              : CashFlowPhase.ready,
          notice: cached.snapshot == null ? null : CashFlowNotice.offlineCache);
      return;
    }
    final previous = _flight;
    if (previous != null) await previous;
    if (!ref.mounted || revision != _revision) return;
    await refresh();
  }

  Future<void> refresh() {
    if (_flight != null) return _flight!;
    final revision = _revision;
    final future = _refresh(revision);
    _flight = future;
    return future.whenComplete(() {
      if (identical(_flight, future)) _flight = null;
    });
  }

  Future<void> _refresh(int revision) async {
    final online = await ref.read(salesReportOnlineCheckProvider)();
    if (!ref.mounted || revision != _revision) return;
    if (!online) {
      state = state.copyWith(
          phase: state.snapshot == null
              ? CashFlowPhase.unavailableOffline
              : CashFlowPhase.ready,
          notice: state.snapshot == null ? null : CashFlowNotice.offlineCache);
      return;
    }
    state = state.copyWith(isRefreshing: true, notice: null);
    final result = await _service.refresh(_scope);
    if (!ref.mounted || revision != _revision) return;
    switch (result.outcome) {
      case CashFlowRefreshOutcome.refreshed:
        state = state.copyWith(
            phase: CashFlowPhase.ready,
            snapshot: result.snapshot,
            isRefreshing: false,
            notice: null);
      case CashFlowRefreshOutcome.unauthorized:
        state = state.copyWith(
            phase: CashFlowPhase.unauthorized,
            snapshot: null,
            isRefreshing: false,
            notice: null);
      case CashFlowRefreshOutcome.remoteFailure:
        final preserved = result.snapshot ?? state.snapshot;
        state = state.copyWith(
            phase:
                preserved == null ? CashFlowPhase.error : CashFlowPhase.ready,
            snapshot: preserved,
            isRefreshing: false,
            notice: preserved == null ? null : CashFlowNotice.refreshFailed);
    }
  }
}

SalesReportPeriod cashFlowPeriodFor(CashFlowPreset preset, DateTime now) {
  final day = now.toLocal();
  final today = DateTime(day.year, day.month, day.day);
  final (from, to) = switch (preset) {
    CashFlowPreset.today => (today, DateTime(day.year, day.month, day.day + 1)),
    CashFlowPreset.thisWeek => (
        DateTime(day.year, day.month, day.day - (day.weekday - 1)),
        DateTime(day.year, day.month, day.day - (day.weekday - 1) + 7)
      ),
    CashFlowPreset.thisMonth => (
        DateTime(day.year, day.month),
        DateTime(day.year, day.month + 1)
      ),
    CashFlowPreset.thisYear => (DateTime(day.year), DateTime(day.year + 1)),
    CashFlowPreset.custom => throw ArgumentError('Custom period needs dates'),
  };
  return SalesReportPeriod(from: from.toUtc(), to: to.toUtc());
}

final cashFlowReportControllerProvider = NotifierProvider.autoDispose.family<
    CashFlowReportController,
    CashFlowScreenState,
    SalesReportViewRequest>(CashFlowReportController.new);

const Object _unset = Object();
