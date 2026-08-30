import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_providers.dart';
import 'package:inventario_frontend/features/dashboard/presentation/screens/main_dashboard_screen.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_providers.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/business_context_required_gate.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/operational_branch_switcher.dart';

void main() {
  testWidgets('one branch shows its name without an unnecessary selector',
      (tester) async {
    final principal = _context();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationalBranchSwitcher(
            currentContext: principal,
            contexts: [principal],
            onSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Sucursal actual: Principal'), findsOneWidget);
    expect(
      find.byKey(const Key('change-operational-branch')),
      findsNothing,
    );
    expect(find.text(principal.branchId), findsNothing);
  });

  testWidgets('multiple branches expose only authorized names for the business',
      (tester) async {
    final principal = _context();
    final vendeMas = _context(
      branchId: 'branch-vende-mas',
      branchName: 'VendeMás',
    );
    final foreign = _context(
      businessId: 'business-2',
      branchId: 'branch-foreign',
      branchName: 'Sucursal ajena',
    );
    AuthorizedOperationalContext? selected;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OperationalBranchSwitcher(
            currentContext: principal,
            contexts: [principal, vendeMas, foreign],
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('change-operational-branch')));
    await tester.pumpAndSettle();

    expect(find.text('Cambiar sucursal'), findsWidgets);
    expect(find.text('VendeMás'), findsOneWidget);
    expect(find.text('Sucursal ajena'), findsNothing);
    expect(find.text(vendeMas.branchId), findsNothing);

    await tester.tap(find.text('VendeMás'));
    await tester.pumpAndSettle();

    expect(selected?.branchId, vendeMas.branchId);
  });

  test('branch contexts are profile and business scoped, active and unique',
      () {
    final result = scopedOperationalBranchContexts(
      contexts: [
        _context(branchId: 'branch-vende-mas', branchName: 'VendeMás'),
        _context(),
        _context(profileId: 'profile-2', branchId: 'branch-other-profile'),
        _context(businessId: 'business-2', branchId: 'branch-other-business'),
        _context(branchId: 'branch-inactive', branchStatus: 'inactive'),
        _context(branchId: 'branch-principal', branchName: 'Principal'),
      ],
      profileId: 'profile-1',
      businessId: 'business-1',
    );

    expect(
      result.map((item) => item.branchName),
      orderedEquals(['Principal', 'VendeMás']),
    );
  });

  test('selection intent rejects cross-profile and cross-business targets', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(
      productiveOperationalSelectionIntentProvider.notifier,
    );

    expect(
      notifier.requestSwitch(
        currentProfileId: 'profile-1',
        currentBusinessId: 'business-1',
        target: _context(profileId: 'profile-2'),
      ),
      isFalse,
    );
    expect(
      notifier.requestSwitch(
        currentProfileId: 'profile-1',
        currentBusinessId: 'business-1',
        target: _context(businessId: 'business-2'),
      ),
      isFalse,
    );
    expect(
      container.read(productiveOperationalSelectionIntentProvider),
      isNull,
    );

    expect(
      notifier.requestSwitch(
        currentProfileId: 'profile-1',
        currentBusinessId: 'business-1',
        target: _context(
          branchId: 'branch-vende-mas',
          branchName: 'VendeMás',
        ),
      ),
      isTrue,
    );
    expect(
      container
          .read(productiveOperationalSelectionIntentProvider)
          ?.selection
          .branchId,
      'branch-vende-mas',
    );
  });

  testWidgets(
      'branch intent re-enters the existing productive convergence flow',
      (tester) async {
    final switchCompleter = Completer<OperationalBootstrapEntryResult>();
    final requests = <ProductiveOperationalEntryRequest>[];
    final contexts = [
      _context(),
      _context(branchId: 'branch-vende-mas', branchName: 'VendeMás'),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productiveOperationalEntryProvider.overrideWith(
            (ref, request) async {
              requests.add(request);
              if (request.selection == null) {
                return _ready(contexts);
              }
              return switchCompleter.future;
            },
          ),
          authenticatedAccessResolverProvider.overrideWith(
            (ref, profileId) async => _access(contexts),
          ),
        ],
        child: MaterialApp(
          home: BusinessContextRequiredGate(
            profileId: 'profile-1',
            businessId: 'business-1',
            child: Consumer(
              builder: (context, ref, _) => FilledButton(
                key: const Key('request-vende-mas'),
                onPressed: () => ref
                    .read(
                      productiveOperationalSelectionIntentProvider.notifier,
                    )
                    .requestSwitch(
                      currentProfileId: 'profile-1',
                      currentBusinessId: 'business-1',
                      target: contexts.last,
                    ),
                child: const Text('Dashboard'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('request-vende-mas')));
    await tester.pump();

    expect(requests.last.selection?.businessId, 'business-1');
    expect(requests.last.selection?.branchId, 'branch-vende-mas');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    switchCompleter.complete(_ready(contexts));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
  });

  test('switching invalidates only context-dependent shell state', () {
    final gate = File(
      'lib/features/sync/presentation/widgets/'
      'business_context_required_gate.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/features/dashboard/presentation/screens/'
      'main_dashboard_screen.dart',
    ).readAsStringSync();

    expect(gate, contains('ref.invalidate(appRouterSyncBootstrapProvider)'));
    expect(gate, contains('ref.invalidate(appCurrentContextProvider)'));
    expect(gate, isNot(contains('appDatabaseProvider')));
    expect(gate, isNot(contains('LocalSyncOutbox')));
    expect(dashboard, isNot(contains('.rpc(')));
    expect(dashboard, isNot(contains('deleteAll')));
    expect(dashboard, contains('cashRegisterId: cashRegisterId'));
    expect(dashboard, contains("title: 'Recuperación requerida'"));
    expect(MainDashboardScreen, isNotNull);
  });
}

OperationalBootstrapEntryResult _ready(
  List<AuthorizedOperationalContext> contexts,
) {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
    contexts: contexts,
    profileId: 'profile-1',
    selectedContext: contexts.last,
    message: 'ready',
    offlineReady: true,
    canRequestAdministrativeSetup: false,
  );
}

AuthenticatedAccessResult _access(
  List<AuthorizedOperationalContext> contexts,
) {
  return AuthenticatedAccessResult(
    outcome: AuthenticatedAccessOutcome.existingContexts,
    contexts: contexts,
    pendingInvitations: const [],
    message: 'authorized',
  );
}

AuthorizedOperationalContext _context({
  String profileId = 'profile-1',
  String businessId = 'business-1',
  String businessStatus = 'active',
  String branchId = 'branch-principal',
  String branchName = 'Principal',
  String branchStatus = 'active',
}) {
  return AuthorizedOperationalContext(
    profileId: profileId,
    businessId: businessId,
    businessName: 'Cronos Business',
    businessStatus: businessStatus,
    businessUpdatedAt: DateTime.utc(2026, 8, 29),
    branchId: branchId,
    branchName: branchName,
    branchStatus: branchStatus,
    branchUpdatedAt: DateTime.utc(2026, 8, 29),
    membershipIds: const ['membership-1'],
    membershipsUpdatedAt: DateTime.utc(2026, 8, 29),
    effectiveRoles: const [],
    effectivePermissions: const ['inventory.read'],
  );
}
