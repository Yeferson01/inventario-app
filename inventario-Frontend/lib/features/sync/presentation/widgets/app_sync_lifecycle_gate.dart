import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../application/app_sync_coordinator_models.dart';
import '../../application/local_sync_outbox_providers.dart';

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

typedef AppSyncInputBuilder = Future<AppSyncCoordinatorInput?> Function(
  WidgetRef ref,
  AppSyncLifecycleTrigger trigger,
);

class AppSyncLifecycleGate extends ConsumerStatefulWidget {
  const AppSyncLifecycleGate({
    required this.child,
    required this.inputBuilder,
    this.minInterval = const Duration(minutes: 1),
    super.key,
  });

  final Widget child;
  final AppSyncInputBuilder inputBuilder;
  final Duration minInterval;

  @override
  ConsumerState<AppSyncLifecycleGate> createState() =>
      _AppSyncLifecycleGateState();
}

class _AppSyncLifecycleGateState extends ConsumerState<AppSyncLifecycleGate>
    with WidgetsBindingObserver {
  bool _isRunning = false;
  DateTime? _lastAttemptAt;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptScheduledSync(AppSyncLifecycleTrigger.appStart);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _attemptScheduledSync(AppSyncLifecycleTrigger.appResume);
    }
  }

  Future<void> _attemptScheduledSync(AppSyncLifecycleTrigger trigger) async {
    if (_isRunning) {
      return;
    }

    final now = DateTime.now().toUtc();

    if (_lastAttemptAt != null &&
        now.difference(_lastAttemptAt!) < widget.minInterval) {
      return;
    }

    _isRunning = true;
    _lastAttemptAt = now;

    try {
      final input = await widget.inputBuilder(ref, trigger);

      if (!mounted || input == null) {
        return;
      }

      final coordinator = ref.read(appSyncCoordinatorServiceProvider);

      await coordinator.runScheduledSyncIfDue(input);
    } catch (error, stackTrace) {
      AppLogger.error(
        'App sync lifecycle attempt failed: ${trigger.code}',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _isRunning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
