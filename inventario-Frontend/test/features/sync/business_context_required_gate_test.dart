import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_providers.dart';
import 'package:inventario_frontend/features/sync/application/offline_operational_readiness_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_providers.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/business_context_required_gate.dart';

void main() {
  testWidgets(
      'stale authorization data is not rendered while access refreshes to ready',
      (tester) async {
    final readyCompleter = Completer<OperationalBootstrapEntryResult>();
    var executions = 0;
    final container = ProviderContainer(
      overrides: [
        productiveOperationalEntryProvider.overrideWith((ref, request) {
          executions += 1;
          if (executions == 1) {
            return const OperationalBootstrapEntryResult(
              outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
              contexts: [],
              message: 'stale pre-login authorization result',
              offlineReady: false,
              canRequestAdministrativeSetup: false,
            );
          }
          return readyCompleter.future;
        }),
        authenticatedAccessResolverProvider.overrideWith(
          (ref, profileId) async => _accessWithContext(),
        ),
      ],
    );
    addTearDown(container.dispose);
    const request = ProductiveOperationalEntryRequest(profileId: 'profile-1');

    final stale = await container
        .read(productiveOperationalEntryProvider(request).future);
    expect(
      stale.outcome,
      OperationalBootstrapEntryOutcome.authorizationRevoked,
    );

    container.invalidate(productiveOperationalEntryProvider(request));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: BusinessContextRequiredGate(
            profileId: 'profile-1',
            child: Text('PRODUCTIVE CHILD'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Autorización no disponible'), findsNothing);

    readyCompleter.complete(
      OperationalBootstrapEntryResult(
        outcome:
            OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
        contexts: [_context()],
        message: 'ready',
        offlineReady: true,
        canRequestAdministrativeSetup: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTIVE CHILD'), findsOneWidget);
    expect(find.text('Autorización no disponible'), findsNothing);
  });

  testWidgets(
      'RG-07 zero contexts and invitations renders stable no-access state',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome.noAuthorizedContexts,
          contexts: [],
          message: 'none',
          offlineReady: false,
          canRequestAdministrativeSetup: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes acceso a ningún negocio'), findsOneWidget);
    expect(
      find.text(
        'Puedes esperar a que un administrador te agregue o crear tu propio negocio.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('No tienes negocios disponibles.'), findsNothing);
  });

  testWidgets('one ready context continues to productive child',
      (tester) async {
    await tester.pumpWidget(
      _app(
        OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome
              .runtimeReadyAndBootstrapCompleted,
          contexts: [_context()],
          message: 'ready',
          offlineReady: true,
          canRequestAdministrativeSetup: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTIVE CHILD'), findsOneWidget);
    expect(find.text('Selecciona tu negocio'), findsNothing);
  });

  testWidgets('multiple contexts show server-authoritative selection',
      (tester) async {
    await tester.pumpWidget(
      _app(
        OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome.selectionRequired,
          contexts: [
            _context(),
            _context(branchId: 'branch-y', branchName: 'Sucursal Y'),
          ],
          message: 'select',
          offlineReady: false,
          canRequestAdministrativeSetup: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Selecciona tu negocio'), findsWidgets);
    expect(
      find.byKey(const Key('operational-branch-selector')),
      findsOneWidget,
    );
  });

  testWidgets('OR-07 transient failure preserves a ready cached context',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome.transientFailure,
          contexts: [],
          message: 'network unavailable',
          offlineReady: false,
          canRequestAdministrativeSetup: false,
        ),
        cachedReadiness: const OfflineOperationalReadinessResult(
          outcome: OfflineOperationalReadinessOutcome.ready,
          reason: 'offline_ready',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTIVE CHILD'), findsOneWidget);
    expect(find.text('Red no disponible'), findsNothing);
  });

  testWidgets('OR-02 incomplete cached recovery does not open the application',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome.transientFailure,
          contexts: [],
          message: 'network unavailable',
          offlineReady: false,
          canRequestAdministrativeSetup: false,
        ),
        cachedReadiness: const OfflineOperationalReadinessResult(
          outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
          reason: 'required_datasets_incomplete',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTIVE CHILD'), findsNothing);
    expect(find.text('Información pendiente'), findsOneWidget);
    expect(find.textContaining('Conéctate a Internet'), findsOneWidget);
  });

  testWidgets('UX-06 revoked access uses productive copy and hides diagnostics',
      (tester) async {
    await tester.pumpWidget(
      _app(
        const OperationalBootstrapEntryResult(
          outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
          contexts: [],
          message: 'RPC forbidden for profile 00000000-technical',
          offlineReady: false,
          canRequestAdministrativeSetup: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acceso no disponible'), findsOneWidget);
    expect(
      find.text('Tu acceso a este negocio o sucursal ya no está disponible.'),
      findsOneWidget,
    );
    expect(find.text('Volver a iniciar sesión'), findsOneWidget);
    expect(find.textContaining('RPC'), findsNothing);
    expect(find.textContaining('00000000'), findsNothing);
  });
}

Widget _app(
  OperationalBootstrapEntryResult result, {
  OfflineOperationalReadinessResult cachedReadiness =
      const OfflineOperationalReadinessResult(
    outcome: OfflineOperationalReadinessOutcome.invalidContext,
    reason: 'selected_context_missing',
  ),
}) {
  return ProviderScope(
    overrides: [
      productiveOperationalEntryProvider.overrideWith(
        (ref, request) async => result,
      ),
      productiveCachedOperationalReadinessProvider.overrideWith(
        (ref, profileId) async => cachedReadiness,
      ),
      authenticatedAccessResolverProvider.overrideWith(
        (ref, profileId) async => result.contexts.isEmpty
            ? _noAuthorizedAccess()
            : _accessWithContext(),
      ),
    ],
    child: const MaterialApp(
      home: BusinessContextRequiredGate(
        profileId: 'profile-1',
        child: Text('PRODUCTIVE CHILD'),
      ),
    ),
  );
}

AuthenticatedAccessResult _accessWithContext() {
  return AuthenticatedAccessResult(
    outcome: AuthenticatedAccessOutcome.existingContexts,
    contexts: [_context()],
    pendingInvitations: const [],
    message: 'authorized',
  );
}

const AuthenticatedAccessResult _noAuthorizedAccessResult =
    AuthenticatedAccessResult(
  outcome: AuthenticatedAccessOutcome.noAuthorizedAccess,
  contexts: [],
  pendingInvitations: [],
  message: 'no access',
);

AuthenticatedAccessResult _noAuthorizedAccess() => _noAuthorizedAccessResult;

AuthorizedOperationalContext _context({
  String branchId = 'branch-x',
  String branchName = 'Sucursal X',
}) {
  return AuthorizedOperationalContext(
    profileId: 'profile-1',
    businessId: 'business-1',
    businessName: 'Business',
    businessStatus: 'active',
    businessUpdatedAt: DateTime.utc(2026, 8, 21),
    branchId: branchId,
    branchName: branchName,
    branchStatus: 'active',
    branchUpdatedAt: DateTime.utc(2026, 8, 21),
    membershipIds: const ['membership-1'],
    membershipsUpdatedAt: DateTime.utc(2026, 8, 21),
    effectiveRoles: const [],
    effectivePermissions: const ['inventory.read'],
  );
}
