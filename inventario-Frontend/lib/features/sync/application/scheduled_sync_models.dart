enum ScheduledSyncTrigger {
  scheduled1100,
  scheduled2300,
  cashClose,
  manual,
}

extension ScheduledSyncTriggerCode on ScheduledSyncTrigger {
  String get code {
    switch (this) {
      case ScheduledSyncTrigger.scheduled1100:
        return 'scheduled_1100';
      case ScheduledSyncTrigger.scheduled2300:
        return 'scheduled_2300';
      case ScheduledSyncTrigger.cashClose:
        return 'cash_close';
      case ScheduledSyncTrigger.manual:
        return 'manual';
    }
  }
}

class ScheduledSyncDecision {
  const ScheduledSyncDecision({
    required this.shouldRun,
    required this.trigger,
    required this.reason,
    required this.slotKey,
  });

  final bool shouldRun;
  final ScheduledSyncTrigger trigger;
  final String reason;
  final String slotKey;

  Map<String, dynamic> toJson() {
    return {
      'should_run': shouldRun,
      'trigger': trigger.code,
      'reason': reason,
      'slot_key': slotKey,
    };
  }
}

class ScheduledSyncRunResult {
  const ScheduledSyncRunResult({
    required this.didRun,
    required this.trigger,
    required this.reason,
    required this.startedAt,
    required this.finishedAt,
    required this.catalogUploadResult,
    required this.catalogPullResult,
  });

  final bool didRun;
  final ScheduledSyncTrigger trigger;
  final String reason;
  final DateTime startedAt;
  final DateTime finishedAt;

  final Map<String, dynamic>? catalogUploadResult;
  final Map<String, dynamic>? catalogPullResult;

  Duration get duration => finishedAt.difference(startedAt);

  Map<String, dynamic> toJson() {
    return {
      'did_run': didRun,
      'trigger': trigger.code,
      'reason': reason,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': finishedAt.toUtc().toIso8601String(),
      'duration_ms': duration.inMilliseconds,
      'catalog_upload_result': catalogUploadResult,
      'catalog_pull_result': catalogPullResult,
    };
  }
}
