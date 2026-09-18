import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/administration/data/models/business_administration_models.dart';
import 'package:inventario_frontend/features/administration/presentation/widgets/business_invitation_access_panel.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_providers.dart';
import 'package:inventario_frontend/features/dashboard/application/dashboard_module_access.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_entry_providers.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/business_context_required_gate.dart';

void main() {
  testWidgets('IA-01 fresh discovery continues directly to Dashboard',
      (tester) async {
    var accessCalls = 0;
    var selectedEntryCalls = 0;
    await tester.pumpWidget(
      _gateApp(
        loadAccess: () {
          accessCalls += 1;
          return accessCalls == 1 ? _pendingAccess() : _warehouseAccess();
        },
        runEntry: (request) async {
          if (request.selection == null) return _noContexts();
          selectedEntryCalls += 1;
          return _ready();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pumpAndSettle();

    expect(accessCalls, 2);
    expect(selectedEntryCalls, 1);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('Información pendiente'), findsNothing);
  });

  testWidgets('IA-02 context appearing on second discovery cycle auto-recovers',
      (tester) async {
    var accessCalls = 0;
    await tester.pumpWidget(
      _gateApp(
        loadAccess: () {
          accessCalls += 1;
          return accessCalls < 3 ? _pendingAccess() : _warehouseAccess();
        },
        runEntry: (request) async =>
            request.selection == null ? _noContexts() : _ready(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pumpAndSettle();

    expect(accessCalls, 3);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('Información pendiente'), findsNothing);
  });

  testWidgets('IA-03 authoritative bootstrap failure remains visible',
      (tester) async {
    var accessCalls = 0;
    var selectedEntryCalls = 0;
    await tester.pumpWidget(
      _gateApp(
        loadAccess: () {
          accessCalls += 1;
          return accessCalls == 1 ? _pendingAccess() : _warehouseAccess();
        },
        runEntry: (request) async {
          if (request.selection == null) return _noContexts();
          selectedEntryCalls += 1;
          return _failed();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(selectedEntryCalls, 1);
    expect(find.text('Información pendiente'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('IA-04 transient bootstrap receives exactly one automatic retry',
      (tester) async {
    var accessCalls = 0;
    var selectedEntryCalls = 0;
    await tester.pumpWidget(
      _gateApp(
        loadAccess: () {
          accessCalls += 1;
          return accessCalls == 1 ? _pendingAccess() : _warehouseAccess();
        },
        runEntry: (request) async {
          if (request.selection == null) return _noContexts();
          selectedEntryCalls += 1;
          return selectedEntryCalls == 1 ? _transient() : _failed();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(selectedEntryCalls, 2);
    expect(find.text('Información pendiente'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('IA-06 invitation acceptance remains single-flight',
      (tester) async {
    final completion = Completer<AcceptedBusinessMemberInvitation>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessInvitationAccessPanel(
            invitations: [_invitation()],
            onAccept: (_) {
              calls += 1;
              return completion.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, 1);
    completion.complete(_accepted());
    await tester.pumpAndSettle();
  });

  test('IA-05 warehouse authorization does not expose POS', () {
    final access = DashboardModuleAccess.fromContext(
      AppCurrentContext(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-warehouse',
        installationId: 'installation-1',
        isOnline: true,
        effectiveRoles: const ['warehouse'],
        roleName: 'warehouse',
        authorizationContextReady: true,
        permissions: AppPermissionSet.fromIterable(
          const ['inventory.read', 'inventory.purchase'],
        ),
      ),
    );

    expect(access.canReadInventory, isTrue);
    expect(access.canPurchaseInventory, isTrue);
    expect(access.canCreateSales, isFalse);
    expect(access.canUseCash, isFalse);
  });
}

Widget _gateApp({
  required AuthenticatedAccessResult Function() loadAccess,
  required Future<OperationalBootstrapEntryResult> Function(
    ProductiveOperationalEntryRequest request,
  ) runEntry,
}) {
  return ProviderScope(
    overrides: [
      authenticatedAccessResolverProvider.overrideWith(
        (ref, profileId) async => loadAccess(),
      ),
      businessInvitationAcceptorProvider.overrideWithValue(
        (_) async => _accepted(),
      ),
      productiveOperationalEntryProvider.overrideWith(
        (ref, request) => runEntry(request),
      ),
    ],
    child: const MaterialApp(
      home: BusinessContextRequiredGate(
        profileId: 'profile-warehouse',
        child: Text('DASHBOARD'),
      ),
    ),
  );
}

AuthenticatedAccessResult _pendingAccess() {
  return AuthenticatedAccessResult(
    outcome: AuthenticatedAccessOutcome.pendingInvitations,
    contexts: const [],
    pendingInvitations: const [],
    pendingBusinessInvitations: [_invitation()],
    message: 'invitation pending',
  );
}

AuthenticatedAccessResult _warehouseAccess() {
  return AuthenticatedAccessResult(
    outcome: AuthenticatedAccessOutcome.existingContexts,
    contexts: [_warehouseContext()],
    pendingInvitations: const [],
    message: 'authorized',
  );
}

BusinessMemberInvitation _invitation() {
  return BusinessMemberInvitation(
    id: 'invitation-warehouse',
    businessId: 'business-1',
    businessName: 'Negocio Uno',
    email: 'warehouse@example.test',
    roleId: 'role-warehouse',
    roleName: 'warehouse',
    branchId: 'branch-1',
    branchName: 'Principal',
    scope: BusinessMemberInvitationScope.branch,
    status: 'pending',
    deliveryStatus: BusinessMemberInvitationDeliveryState.sent,
    expiresAt: DateTime.utc(2099),
    isExpired: false,
  );
}

const AcceptedBusinessMemberInvitation _acceptedInvitation =
    AcceptedBusinessMemberInvitation(
  invitationId: 'invitation-warehouse',
  profileId: 'profile-warehouse',
  businessId: 'business-1',
  branchId: 'branch-1',
  roleId: 'role-warehouse',
  membershipId: 'membership-warehouse',
);

AcceptedBusinessMemberInvitation _accepted() => _acceptedInvitation;

AuthorizedOperationalContext _warehouseContext() {
  return AuthorizedOperationalContext(
    profileId: 'profile-warehouse',
    businessId: 'business-1',
    businessName: 'Negocio Uno',
    businessStatus: 'active',
    businessUpdatedAt: DateTime.utc(2026, 9, 17),
    branchId: 'branch-1',
    branchName: 'Principal',
    branchStatus: 'active',
    branchUpdatedAt: DateTime.utc(2026, 9, 17),
    membershipIds: const ['membership-warehouse'],
    membershipsUpdatedAt: DateTime.utc(2026, 9, 17),
    effectiveRoles: const [
      AuthorizedOperationalRole(
        roleId: 'role-warehouse',
        roleName: 'warehouse',
        isSystemRole: true,
        membershipIds: ['membership-warehouse'],
      ),
    ],
    effectivePermissions: const ['inventory.read', 'inventory.purchase'],
  );
}

OperationalBootstrapEntryResult _noContexts() {
  return const OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.noAuthorizedContexts,
    contexts: [],
    message: 'no contexts',
    offlineReady: false,
    canRequestAdministrativeSetup: false,
  );
}

OperationalBootstrapEntryResult _ready() {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted,
    contexts: [_warehouseContext()],
    profileId: 'profile-warehouse',
    selectedContext: _warehouseContext(),
    message: 'ready',
    offlineReady: true,
    canRequestAdministrativeSetup: false,
  );
}

OperationalBootstrapEntryResult _transient() {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.transientFailure,
    contexts: [_warehouseContext()],
    profileId: 'profile-warehouse',
    selectedContext: _warehouseContext(),
    message: 'temporary bootstrap race',
    offlineReady: false,
    canRequestAdministrativeSetup: false,
  );
}

OperationalBootstrapEntryResult _failed() {
  return OperationalBootstrapEntryResult(
    outcome: OperationalBootstrapEntryOutcome.failed,
    contexts: [_warehouseContext()],
    profileId: 'profile-warehouse',
    selectedContext: _warehouseContext(),
    message: 'authoritative bootstrap failure',
    offlineReady: false,
    canRequestAdministrativeSetup: false,
  );
}
