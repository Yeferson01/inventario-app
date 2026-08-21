import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/app_business_context_selector.dart';

void main() {
  testWidgets('one business with two branches requires an explicit branch',
      (tester) async {
    AuthorizedOperationalContext? selected;
    await tester.pumpWidget(
      _app(
        contexts: [
          _context(branchId: 'branch-x', branchName: 'Sucursal X'),
          _context(branchId: 'branch-y', branchName: 'Sucursal Y'),
        ],
        onSelected: (value) => selected = value,
      ),
    );

    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-operational-context')),
    );
    expect(find.text('Business A'), findsOneWidget);
    expect(confirm.onPressed, isNull);

    await tester.tap(find.byKey(const Key('operational-branch-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sucursal Y').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-operational-context')));

    expect(selected?.businessId, 'business-a');
    expect(selected?.branchId, 'branch-y');
  });

  testWidgets('branches remain isolated under their authorized business',
      (tester) async {
    AuthorizedOperationalContext? selected;
    await tester.pumpWidget(
      _app(
        contexts: [
          _context(branchId: 'branch-x', branchName: 'Sucursal X'),
          _context(
            businessId: 'business-b',
            businessName: 'Business B',
            branchId: 'branch-z',
            branchName: 'Sucursal Z',
          ),
        ],
        onSelected: (value) => selected = value,
      ),
    );

    expect(
      find.byKey(const Key('operational-branch-selector')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('operational-business-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Business A').last);
    await tester.pumpAndSettle();

    expect(find.text('Sucursal X'), findsOneWidget);
    expect(find.text('Sucursal Z'), findsNothing);

    await tester.tap(find.byKey(const Key('confirm-operational-context')));
    expect(selected?.businessId, 'business-a');
    expect(selected?.branchId, 'branch-x');
  });
}

Widget _app({
  required List<AuthorizedOperationalContext> contexts,
  required ValueChanged<AuthorizedOperationalContext> onSelected,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AppBusinessContextSelector(
        contexts: contexts,
        onSelected: onSelected,
      ),
    ),
  );
}

AuthorizedOperationalContext _context({
  String businessId = 'business-a',
  String businessName = 'Business A',
  required String branchId,
  required String branchName,
}) {
  return AuthorizedOperationalContext(
    profileId: 'profile-1',
    businessId: businessId,
    businessName: businessName,
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
