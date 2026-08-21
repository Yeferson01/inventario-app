import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_providers.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/business_context_required_gate.dart';

void main() {
  testWidgets(
      'zero contexts renders a typed state instead of an empty selector',
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

    expect(
        find.text('Sin contextos operacionales autorizados'), findsOneWidget);
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

  testWidgets('transient discovery failure preserves an active cached context',
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
        cachedContextAvailable: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRODUCTIVE CHILD'), findsOneWidget);
    expect(find.text('Red no disponible'), findsNothing);
  });
}

Widget _app(
  OperationalBootstrapEntryResult result, {
  bool cachedContextAvailable = false,
}) {
  return ProviderScope(
    overrides: [
      productiveOperationalEntryProvider.overrideWith(
        (ref, request) async => result,
      ),
      productiveCachedContextAvailabilityProvider.overrideWith(
        (ref, profileId) async => cachedContextAvailable,
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
