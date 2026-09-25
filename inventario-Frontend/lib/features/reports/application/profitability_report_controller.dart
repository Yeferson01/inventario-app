import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/operational_bootstrap_providers.dart';
import '../data/models/profitability_report_models.dart';
import '../data/models/sales_report_models.dart';
import 'profitability_report_providers.dart';
import 'profitability_report_service.dart';
import 'sales_report_controller.dart';
import 'sales_report_providers.dart';

extension ProfitabilityReportAccess on SalesReportViewRequest {
  bool get canViewProfitability =>
      hasCompleteScope &&
      canViewSalesReports &&
      effectivePermissions.contains(profitabilityCostCapability);
}

/// Keeps sensitive metrics hidden when the local authorization projection or
/// authenticated profile changes while the report route remains open.
final profitabilityPresentationAccessProvider =
    StreamProvider.autoDispose.family<bool, ProfitabilityReportViewRequest>(
  (ref, request) {
    if (!request.canViewProfitability ||
        ref.watch(currentSupabaseUserProvider)?.id !=
            request.context.profileId) {
      return Stream.value(false);
    }
    return ref
        .watch(authorizedOperationalContextLocalDaoProvider)
        .watchContextRecord(
          profileId: request.context.profileId,
          businessId: request.context.businessId,
          branchId: request.context.branchId,
        )
        .map((context) =>
            context?.isActive == true &&
            context!.effectivePermissions.contains(salesReportCapability) &&
            context.effectivePermissions.contains(profitabilityCostCapability));
  },
);

class ProfitabilityReportViewRequest {
  ProfitabilityReportViewRequest({
    required this.context,
    required this.period,
  }) : filterKey = period.filterKey;

  final SalesReportViewRequest context;
  final SalesReportPeriod period;
  final String filterKey;

  bool get canViewProfitability => context.canViewProfitability;

  SalesReportScope get scope => SalesReportScope(
        profileId: context.profileId,
        businessId: context.businessId,
        branchId: context.branchId,
        period: period,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfitabilityReportViewRequest &&
          other.context == context &&
          other.filterKey == filterKey;

  @override
  int get hashCode => Object.hash(context, filterKey);
}

enum ProfitabilityReportPhase {
  initialLoading,
  ready,
  unavailableOffline,
  unauthorized,
  error,
}

enum ProfitabilityReportNotice { offlineCache, refreshFailed }

class ProfitabilityReportScreenState {
  const ProfitabilityReportScreenState({
    required this.phase,
    this.snapshot,
    this.isRefreshing = false,
    this.notice,
  });

  final ProfitabilityReportPhase phase;
  final ProfitabilityReportSnapshot? snapshot;
  final bool isRefreshing;
  final ProfitabilityReportNotice? notice;
}

class ProfitabilityReportController
    extends Notifier<ProfitabilityReportScreenState> {
  ProfitabilityReportController(this.request);

  final ProfitabilityReportViewRequest request;
  Future<void>? _refreshInFlight;

  ProfitabilityReportService get _service =>
      ref.read(profitabilityReportServiceProvider);

  @override
  ProfitabilityReportScreenState build() {
    if (!request.canViewProfitability) {
      return const ProfitabilityReportScreenState(
        phase: ProfitabilityReportPhase.unauthorized,
      );
    }
    unawaited(Future<void>.microtask(_initialize));
    return const ProfitabilityReportScreenState(
      phase: ProfitabilityReportPhase.initialLoading,
    );
  }

  Future<void> _initialize() async {
    final cached = await _service.readCached(request.scope);
    if (!ref.mounted) return;
    if (cached.outcome == ProfitabilityCacheReadOutcome.unauthorized) {
      _unauthorized();
      return;
    }
    if (cached.snapshot != null) {
      state = ProfitabilityReportScreenState(
        phase: ProfitabilityReportPhase.ready,
        snapshot: cached.snapshot,
      );
    }
    final online = await ref.read(salesReportOnlineCheckProvider)();
    if (!ref.mounted) return;
    if (!online) {
      state = ProfitabilityReportScreenState(
        phase: cached.snapshot == null
            ? ProfitabilityReportPhase.unavailableOffline
            : ProfitabilityReportPhase.ready,
        snapshot: cached.snapshot,
        notice: cached.snapshot == null
            ? null
            : ProfitabilityReportNotice.offlineCache,
      );
      return;
    }
    await refresh();
  }

  Future<void> refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _refresh();
    _refreshInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    });
  }

  Future<void> _refresh() async {
    if (!request.canViewProfitability) {
      _unauthorized();
      return;
    }
    final online = await ref.read(salesReportOnlineCheckProvider)();
    if (!ref.mounted) return;
    if (!online) {
      state = ProfitabilityReportScreenState(
        phase: state.snapshot == null
            ? ProfitabilityReportPhase.unavailableOffline
            : ProfitabilityReportPhase.ready,
        snapshot: state.snapshot,
        notice: state.snapshot == null
            ? null
            : ProfitabilityReportNotice.offlineCache,
      );
      return;
    }
    state = ProfitabilityReportScreenState(
      phase: state.phase,
      snapshot: state.snapshot,
      isRefreshing: true,
    );
    final result = await _service.refresh(request.scope);
    if (!ref.mounted) return;
    switch (result.outcome) {
      case ProfitabilityRefreshOutcome.refreshed:
        state = ProfitabilityReportScreenState(
          phase: ProfitabilityReportPhase.ready,
          snapshot: result.snapshot,
        );
      case ProfitabilityRefreshOutcome.unauthorized:
        _unauthorized();
      case ProfitabilityRefreshOutcome.remoteFailure:
        final preserved = result.preservedCache ?? state.snapshot;
        state = ProfitabilityReportScreenState(
          phase: preserved == null
              ? ProfitabilityReportPhase.error
              : ProfitabilityReportPhase.ready,
          snapshot: preserved,
          notice: preserved == null
              ? null
              : ProfitabilityReportNotice.refreshFailed,
        );
    }
  }

  void _unauthorized() {
    if (!ref.mounted) return;
    state = const ProfitabilityReportScreenState(
      phase: ProfitabilityReportPhase.unauthorized,
    );
  }
}

final profitabilityReportControllerProvider = NotifierProvider.autoDispose
    .family<ProfitabilityReportController, ProfitabilityReportScreenState,
        ProfitabilityReportViewRequest>(ProfitabilityReportController.new);
