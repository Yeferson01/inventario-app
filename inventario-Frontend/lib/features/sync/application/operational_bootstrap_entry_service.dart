import 'dart:async';

import '../data/models/authorized_operational_context_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import '../data/models/operational_integration_failure.dart';
import '../data/models/runtime_resolution_models.dart';
import '../data/models/runtime_setup_models.dart';
import 'app_selected_sync_context_store.dart';
import 'operational_bootstrap_entry_models.dart';
import 'operational_bootstrap_orchestration_models.dart';

typedef EntryAuthenticatedProfileResolver = FutureOr<String?> Function();
typedef EntryDiscoveryRunner = Future<List<AuthorizedOperationalContext>>
    Function();
typedef EntryInstallationResolver = Future<String> Function();
typedef EntryDeviceRegistrationRunner = Future<RegisteredAppDeviceResult>
    Function(RegisterAppDeviceInput input);
typedef EntryRuntimeResolutionRunner = Future<ResolvedBusinessRuntime>
    Function({
  required String profileId,
  required String businessId,
  required String branchId,
});
typedef EntryBootstrapRunner = Future<OperationalBootstrapResult> Function(
  OperationalBootstrapRequest request,
);
typedef EntrySelectedContextReader = Future<AppSelectedSyncContext?> Function(
  String profileId,
);
typedef EntrySelectedContextWriter = Future<void> Function(
  AppSelectedSyncContext context,
);
typedef EntrySelectedContextClearer = Future<void> Function(String profileId);

class OperationalBootstrapEntryService {
  OperationalBootstrapEntryService({
    required EntryAuthenticatedProfileResolver authenticatedProfileId,
    required EntryDiscoveryRunner discover,
    required EntryInstallationResolver installationId,
    required EntryDeviceRegistrationRunner registerDevice,
    required EntryRuntimeResolutionRunner resolveRuntime,
    required EntryBootstrapRunner bootstrap,
    required EntrySelectedContextReader readSelectedContext,
    required EntrySelectedContextWriter writeSelectedContext,
    required EntrySelectedContextClearer clearSelectedContext,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _discover = discover,
        _installationId = installationId,
        _registerDevice = registerDevice,
        _resolveRuntime = resolveRuntime,
        _bootstrap = bootstrap,
        _readSelectedContext = readSelectedContext,
        _writeSelectedContext = writeSelectedContext,
        _clearSelectedContext = clearSelectedContext;

  final EntryAuthenticatedProfileResolver _authenticatedProfileId;
  final EntryDiscoveryRunner _discover;
  final EntryInstallationResolver _installationId;
  final EntryDeviceRegistrationRunner _registerDevice;
  final EntryRuntimeResolutionRunner _resolveRuntime;
  final EntryBootstrapRunner _bootstrap;
  final EntrySelectedContextReader _readSelectedContext;
  final EntrySelectedContextWriter _writeSelectedContext;
  final EntrySelectedContextClearer _clearSelectedContext;

  Future<OperationalBootstrapEntryResult> run(
    OperationalBootstrapEntryRequest request,
  ) async {
    String? profileId;
    List<AuthorizedOperationalContext> contexts = const [];
    String? installationId;
    AuthorizedOperationalContext? selected;
    RegisteredAppDeviceResult? device;
    ResolvedBusinessRuntime? runtime;

    try {
      profileId = await _authenticatedProfileId();
      if (profileId == null || profileId.trim().isEmpty) {
        return _result(
          outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
          contexts: contexts,
          message: 'An authenticated profile is required.',
        );
      }

      contexts = await _discover();
      if (contexts.isEmpty) {
        await _clearSelectedContext(profileId);
        return _result(
          outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
          contexts: contexts,
          profileId: profileId,
          message: 'No authorized operational context is available.',
        );
      }

      final selection = request.selection;
      if (selection != null) {
        selected = _match(
          contexts,
          selection.businessId,
          selection.branchId,
        );
        if (selected == null) {
          await _clearSelectedContext(profileId);
          return _result(
            outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
            contexts: contexts,
            profileId: profileId,
            message: 'The explicitly selected context is no longer authorized.',
          );
        }
      } else {
        final stored = await _readSelectedContext(profileId);
        if (stored != null && stored.branchId != null) {
          selected = _match(
            contexts,
            stored.businessId,
            stored.branchId!,
          );
          if (selected == null) await _clearSelectedContext(profileId);
        } else if (stored != null) {
          await _clearSelectedContext(profileId);
        }

        // A single concrete server-authoritative context is unambiguous.
        selected ??= contexts.length == 1 ? contexts.single : null;
        if (selected == null) {
          return _result(
            outcome: OperationalBootstrapEntryOutcome.selectionRequired,
            contexts: contexts,
            profileId: profileId,
            message: 'An explicit business and branch selection is required.',
          );
        }
      }

      await _writeSelectedContext(
        AppSelectedSyncContext(
          businessId: selected.businessId,
          branchId: selected.branchId,
          profileId: profileId,
        ),
      );

      installationId = await _installationId();
      if (installationId.trim().isEmpty) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.malformedResponse,
          message: 'Installation identity is missing.',
        );
      }

      device = await _registerDevice(
        RegisterAppDeviceInput(
          businessId: selected.businessId,
          branchId: selected.branchId,
          installationId: installationId,
          deviceName: request.deviceName,
          platform: request.platform,
          appVersion: request.appVersion,
          osVersion: request.osVersion,
          metadata: {
            'source': 'operational_bootstrap_entry',
            ...request.metadata,
          },
        ),
      );

      runtime = await _resolveRuntime(
        profileId: profileId,
        businessId: selected.businessId,
        branchId: selected.branchId,
      );
      if (!runtime.runtimeReady) {
        return _result(
          outcome: OperationalBootstrapEntryOutcome.runtimeSetupRequired,
          contexts: contexts,
          profileId: profileId,
          installationId: installationId,
          selectedContext: selected,
          device: device,
          runtime: runtime,
          canRequestAdministrativeSetup: selected.canRequestAdministrativeSetup,
          message: 'The selected branch requires administrative runtime setup.',
        );
      }

      final bootstrap = await _bootstrap(
        OperationalBootstrapRequest(
          profileId: profileId,
          businessId: selected.businessId,
          branchId: selected.branchId,
          installationId: installationId,
          appDeviceId: device.appDeviceId,
          runtime: OperationalBootstrapRuntimeResolution(
            businessId: runtime.businessId,
            branchId: runtime.branchId,
            installationId: installationId,
            appDeviceId: device.appDeviceId,
            runtimeReady: runtime.runtimeReady,
            cashRegisterId: runtime.cashRegisterId,
            cashSessionId: runtime.openCashSessionId,
            receiptSequenceId: runtime.receiptSequenceId,
          ),
          mode: request.mode,
          pageLimit: request.pageLimit,
        ),
      );
      return _fromBootstrap(
        bootstrap,
        contexts: contexts,
        profileId: profileId,
        installationId: installationId,
        selected: selected,
        device: device,
        runtime: runtime,
      );
    } on OperationalIntegrationException catch (error) {
      final outcome = switch (error.kind) {
        OperationalIntegrationFailureKind.deviceBlocked =>
          OperationalBootstrapEntryOutcome.deviceBlocked,
        OperationalIntegrationFailureKind.unauthorized ||
        OperationalIntegrationFailureKind.forbidden =>
          OperationalBootstrapEntryOutcome.authorizationRevoked,
        OperationalIntegrationFailureKind.networkTransient =>
          OperationalBootstrapEntryOutcome.transientFailure,
        _ => OperationalBootstrapEntryOutcome.failed,
      };
      return _result(
        outcome: outcome,
        contexts: contexts,
        profileId: profileId,
        installationId: installationId,
        selectedContext: selected,
        device: device,
        runtime: runtime,
        message: error.message,
      );
    } on OperationalBootstrapException catch (error) {
      return _result(
        outcome: error.retryable
            ? OperationalBootstrapEntryOutcome.transientFailure
            : OperationalBootstrapEntryOutcome.failed,
        contexts: contexts,
        profileId: profileId,
        installationId: installationId,
        selectedContext: selected,
        device: device,
        runtime: runtime,
        message: error.message,
      );
    } catch (_) {
      return _result(
        outcome: OperationalBootstrapEntryOutcome.failed,
        contexts: contexts,
        profileId: profileId,
        installationId: installationId,
        selectedContext: selected,
        device: device,
        runtime: runtime,
        message: 'Operational bootstrap entry failed unexpectedly.',
      );
    }
  }

  AuthorizedOperationalContext? _match(
    List<AuthorizedOperationalContext> contexts,
    String businessId,
    String branchId,
  ) {
    final business = businessId.trim();
    final branch = branchId.trim();
    if (business.isEmpty || branch.isEmpty) return null;
    for (final context in contexts) {
      if (context.businessId == business && context.branchId == branch) {
        return context;
      }
    }
    return null;
  }

  OperationalBootstrapEntryResult _fromBootstrap(
    OperationalBootstrapResult bootstrap, {
    required List<AuthorizedOperationalContext> contexts,
    required String profileId,
    required String installationId,
    required AuthorizedOperationalContext selected,
    required RegisteredAppDeviceResult device,
    required ResolvedBusinessRuntime runtime,
  }) {
    final outcome = switch (bootstrap.outcome) {
      OperationalBootstrapOutcome.ready =>
        OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
      OperationalBootstrapOutcome.recoveryBlocked =>
        OperationalBootstrapEntryOutcome.bootstrapRecoveryBlocked,
      OperationalBootstrapOutcome.authorizationRevoked =>
        OperationalBootstrapEntryOutcome.authorizationRevoked,
      OperationalBootstrapOutcome.runtimeSetupRequired =>
        OperationalBootstrapEntryOutcome.runtimeSetupRequired,
      OperationalBootstrapOutcome.networkUnavailableWithCachedContext ||
      OperationalBootstrapOutcome.transientFailure =>
        OperationalBootstrapEntryOutcome.transientFailure,
      OperationalBootstrapOutcome.failed =>
        OperationalBootstrapEntryOutcome.failed,
    };
    return _result(
      outcome: outcome,
      contexts: contexts,
      profileId: profileId,
      installationId: installationId,
      selectedContext: selected,
      device: device,
      runtime: runtime,
      bootstrapResult: bootstrap,
      offlineReady: bootstrap.offlineReady,
      canRequestAdministrativeSetup: selected.canRequestAdministrativeSetup,
      message: bootstrap.message,
    );
  }

  OperationalBootstrapEntryResult _result({
    required OperationalBootstrapEntryOutcome outcome,
    required List<AuthorizedOperationalContext> contexts,
    required String message,
    String? profileId,
    String? installationId,
    AuthorizedOperationalContext? selectedContext,
    RegisteredAppDeviceResult? device,
    ResolvedBusinessRuntime? runtime,
    OperationalBootstrapResult? bootstrapResult,
    bool offlineReady = false,
    bool canRequestAdministrativeSetup = false,
  }) {
    return OperationalBootstrapEntryResult(
      outcome: outcome,
      contexts: List.unmodifiable(contexts),
      message: message,
      offlineReady: offlineReady,
      canRequestAdministrativeSetup: canRequestAdministrativeSetup,
      profileId: profileId,
      installationId: installationId,
      selectedContext: selectedContext,
      device: device,
      runtime: runtime,
      bootstrapResult: bootstrapResult,
    );
  }
}
