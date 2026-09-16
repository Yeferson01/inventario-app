import 'scheduled_sync_models.dart';

class ScheduledSyncScope {
  const ScheduledSyncScope({
    required this.profileId,
    required this.businessId,
    required this.branchId,
  });

  final String profileId;
  final String businessId;
  final String branchId;
}

class ScheduledSyncPolicy {
  const ScheduledSyncPolicy();

  static const int morningHour = 11;
  static const int nightHour = 23;

  ScheduledSyncDecision evaluateScoped({
    required DateTime now,
    required ScheduledSyncScope scope,
    required Set<String> attemptedSlotKeys,
  }) {
    final localNow = now.toLocal();
    final slot = latestEligibleSlot(localNow);
    final trigger = slot.hour == morningHour
        ? ScheduledSyncTrigger.scheduled1100
        : ScheduledSyncTrigger.scheduled2300;
    final slotKey = scopedSlotKey(scope: scope, slot: slot);

    if (attemptedSlotKeys.contains(slotKey)) {
      return ScheduledSyncDecision(
        shouldRun: false,
        trigger: trigger,
        reason: 'La oportunidad programada ya fue intentada para este scope.',
        slotKey: slotKey,
      );
    }

    return ScheduledSyncDecision(
      shouldRun: true,
      trigger: trigger,
      reason: localNow.isAfter(slot)
          ? 'Oportunidad programada pendiente; se ejecutará catch-up.'
          : 'Oportunidad programada disponible.',
      slotKey: slotKey,
    );
  }

  DateTime latestEligibleSlot(DateTime now) {
    final localNow = now.toLocal();
    final night = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      nightHour,
    );
    if (!localNow.isBefore(night)) return night;

    final morning = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      morningHour,
    );
    if (!localNow.isBefore(morning)) return morning;

    final yesterday = localNow.subtract(const Duration(days: 1));
    return DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
      nightHour,
    );
  }

  DateTime nextSlotAfter(DateTime now) {
    final localNow = now.toLocal();
    final morning = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      morningHour,
    );
    if (localNow.isBefore(morning)) return morning;

    final night = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      nightHour,
    );
    if (localNow.isBefore(night)) return night;

    final tomorrow = localNow.add(const Duration(days: 1));
    return DateTime(
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      morningHour,
    );
  }

  String scopedSlotKey({
    required ScheduledSyncScope scope,
    required DateTime slot,
  }) {
    return '${scope.profileId}|${scope.businessId}|${scope.branchId}|'
        '${_dateKey(slot)}|${slot.hour.toString().padLeft(2, '0')}';
  }

  ScheduledSyncDecision evaluate({
    required DateTime now,
    required Set<String> completedSlotKeys,
    ScheduledSyncTrigger? forcedTrigger,
  }) {
    final localNow = now.toLocal();

    if (forcedTrigger == ScheduledSyncTrigger.cashClose) {
      return ScheduledSyncDecision(
        shouldRun: true,
        trigger: ScheduledSyncTrigger.cashClose,
        reason: 'Sync forzado por cierre de caja.',
        slotKey: _cashCloseSlotKey(localNow),
      );
    }

    if (forcedTrigger == ScheduledSyncTrigger.manual) {
      return ScheduledSyncDecision(
        shouldRun: true,
        trigger: ScheduledSyncTrigger.manual,
        reason: 'Sync manual solicitado.',
        slotKey: _manualSlotKey(localNow),
      );
    }

    final scheduledTrigger = _scheduledTriggerFor(localNow);

    if (scheduledTrigger == null) {
      return ScheduledSyncDecision(
        shouldRun: false,
        trigger: ScheduledSyncTrigger.manual,
        reason: 'No estamos en una ventana programada de sync.',
        slotKey: _noneSlotKey(localNow),
      );
    }

    final slotKey = _scheduledSlotKey(localNow, scheduledTrigger);

    if (completedSlotKeys.contains(slotKey)) {
      return ScheduledSyncDecision(
        shouldRun: false,
        trigger: scheduledTrigger,
        reason: 'La ventana programada ya fue ejecutada.',
        slotKey: slotKey,
      );
    }

    return ScheduledSyncDecision(
      shouldRun: true,
      trigger: scheduledTrigger,
      reason: 'Ventana programada disponible.',
      slotKey: slotKey,
    );
  }

  ScheduledSyncTrigger? _scheduledTriggerFor(DateTime localNow) {
    if (localNow.hour == morningHour) {
      return ScheduledSyncTrigger.scheduled1100;
    }

    if (localNow.hour == nightHour) {
      return ScheduledSyncTrigger.scheduled2300;
    }

    return null;
  }

  String _scheduledSlotKey(DateTime localNow, ScheduledSyncTrigger trigger) {
    return '${_dateKey(localNow)}:${trigger.code}';
  }

  String _cashCloseSlotKey(DateTime localNow) {
    return '${_dateKey(localNow)}:cash_close:${localNow.microsecondsSinceEpoch}';
  }

  String _manualSlotKey(DateTime localNow) {
    return '${_dateKey(localNow)}:manual:${localNow.microsecondsSinceEpoch}';
  }

  String _noneSlotKey(DateTime localNow) {
    return '${_dateKey(localNow)}:none';
  }

  String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }
}
