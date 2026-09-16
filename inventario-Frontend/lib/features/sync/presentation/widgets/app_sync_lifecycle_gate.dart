import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../application/app_router_sync_bootstrap_provider.dart';
import '../../application/productive_scheduled_sync_service.dart';
import '../../application/scheduled_sync_policy.dart';

enum AppSyncLifecycleTrigger {
  appStart,
  appResume,
}

extension AppSyncLifecycleTriggerCode on AppSyncLifecycleTrigger {
  String get code {
    switch (this) {
      case AppSyncLifecycleTrigger.appStart:
        return 'app_start';
      case AppSyncLifecycleTrigger.appResume:
        return 'app_resume';
    }
  }
}

typedef ProductiveScheduledSyncRunner = Future<ProductiveScheduledSyncResult>
    Function({DateTime? now});
typedef ScheduledSyncClock = DateTime Function();
typedef ScheduledSyncTimerFactory = Timer Function(
  Duration duration,
  void Function() callback,
);

class AppSyncLifecycleGate extends ConsumerStatefulWidget {
  const AppSyncLifecycleGate({
    required this.child,
    required this.scopeKey,
    this.minInterval = const Duration(minutes: 1),
    this.runner,
    this.clock = DateTime.now,
    this.timerFactory = _defaultTimerFactory,
    super.key,
  });

  final Widget child;
  final String scopeKey;
  final Duration minInterval;
  final ProductiveScheduledSyncRunner? runner;
  final ScheduledSyncClock clock;
  final ScheduledSyncTimerFactory timerFactory;

  static Timer _defaultTimerFactory(
    Duration duration,
    void Function() callback,
  ) {
    return Timer(duration, callback);
  }

  @override
  ConsumerState<AppSyncLifecycleGate> createState() =>
      _AppSyncLifecycleGateState();
}

class _AppSyncLifecycleGateState extends ConsumerState<AppSyncLifecycleGate>
    with WidgetsBindingObserver {
  static const _policy = ScheduledSyncPolicy();

  bool _isRunning = false;
  DateTime? _lastAttemptAt;
  Timer? _nextSlotTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptScheduledSync(AppSyncLifecycleTrigger.appStart);
      _scheduleNextSlot();
    });
  }

  @override
  void didUpdateWidget(covariant AppSyncLifecycleGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeKey != widget.scopeKey) {
      _lastAttemptAt = null;
      _attemptScheduledSync(AppSyncLifecycleTrigger.appStart);
      _scheduleNextSlot();
    }
  }

  @override
  void dispose() {
    _nextSlotTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attemptScheduledSync(AppSyncLifecycleTrigger.appResume);
      _scheduleNextSlot();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _nextSlotTimer?.cancel();
      _nextSlotTimer = null;
    }
  }

  void _scheduleNextSlot() {
    _nextSlotTimer?.cancel();
    if (!mounted) return;

    final now = widget.clock();
    final nextSlot = _policy.nextSlotAfter(now);
    final delay = nextSlot.difference(now);
    _nextSlotTimer = widget.timerFactory(
      delay.isNegative ? Duration.zero : delay,
      () async {
        await _attemptScheduledSync(
          AppSyncLifecycleTrigger.appResume,
          bypassThrottle: true,
        );
        if (mounted) _scheduleNextSlot();
      },
    );
  }

  Future<void> _attemptScheduledSync(
    AppSyncLifecycleTrigger trigger, {
    bool bypassThrottle = false,
  }) async {
    if (_isRunning) return;

    final now = widget.clock();
    if (!bypassThrottle &&
        _lastAttemptAt != null &&
        now.difference(_lastAttemptAt!) < widget.minInterval) {
      return;
    }

    _isRunning = true;
    _lastAttemptAt = now;

    try {
      final runner = widget.runner ??
          ref.read(productiveScheduledSyncServiceProvider).runIfDue;
      await runner(now: now);
    } catch (error, stackTrace) {
      AppLogger.error(
        'App scheduled sync attempt failed: ${trigger.code}',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
