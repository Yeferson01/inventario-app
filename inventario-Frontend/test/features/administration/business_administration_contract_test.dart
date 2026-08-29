import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/supabase/supabase_client_provider.dart';
import 'package:inventario_frontend/features/administration/application/business_administration_providers.dart';
import 'package:inventario_frontend/features/administration/application/business_administration_service.dart';
import 'package:inventario_frontend/features/administration/application/business_administration_submission_controllers.dart';
import 'package:inventario_frontend/features/administration/data/datasources/business_administration_remote_datasource.dart';
import 'package:inventario_frontend/features/administration/data/models/business_administration_models.dart';
import 'package:inventario_frontend/features/administration/presentation/screens/administration_home_screen.dart';
import 'package:inventario_frontend/features/administration/presentation/screens/business_branches_screen.dart';
import 'package:inventario_frontend/features/dashboard/application/dashboard_module_access.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('administration datasource uses only approved RPC and Edge contracts',
      () async {
    final calls = <String>[];
    final datasource = BusinessAdministrationRemoteDatasource.withInvokers(
      rpc: (name, params) async {
        calls.add(name);
        return switch (name) {
          'list_business_branches' => {
              'branches': [_branchJson()]
            },
          'list_business_member_invitation_options' => _optionsJson(),
          'list_business_member_invitations' => {
              'profile_id': 'profile-a',
              'business_id': 'business-a',
              'can_invite_business_wide': false,
              'invitations': [_invitationJson()],
            },
          'accept_business_member_invitation' => {
              'invitation_id': 'invitation-a',
              'profile_id': 'profile-a',
              'business_id': 'business-a',
              'branch_id': 'branch-a',
              'role_id': 'role-cashier',
              'membership_id': 'membership-a',
            },
          'revoke_business_member_invitation' =>
            _invitationJson(status: 'revoked'),
          _ => throw StateError(name),
        };
      },
      edge: (body) async {
        calls.add('business-member-invitations');
        return _issueJson();
      },
    );

    final branches = await datasource.listBranches('business-a');
    final options = await datasource.listInvitationOptions('business-a');
    final listed = await datasource.listBusinessInvitations('business-a');
    final issued = await datasource.issueInvitation(
      const IssueBusinessMemberInvitationRequest(
        businessId: 'business-a',
        email: 'employee@example.com',
        roleId: 'role-cashier',
        branchId: 'branch-a',
      ),
      idempotencyKey: 'key-a',
    );
    final accepted = await datasource.acceptInvitation('invitation-a');
    final revoked = await datasource.revokeInvitation('invitation-a');
    final failedDelivery = IssueBusinessMemberInvitationResult.fromJson(
      _issueJson(deliveryStatus: 'failed'),
    );
    final unknownDelivery = IssueBusinessMemberInvitationResult.fromJson(
      _issueJson(deliveryStatus: 'unknown'),
    );
    final source = await File(
      'lib/features/administration/data/datasources/business_administration_remote_datasource.dart',
    ).readAsString();

    expect(branches.single.id, 'branch-a');
    expect(options.roles.single.name, 'cashier');
    expect(options.canInviteBusinessWide, isFalse);
    expect(options.branches.single.id, 'branch-a');
    expect(listed.invitations.single.branchId, 'branch-a');
    expect(issued.userMessage, 'Invitación enviada.');
    expect(
      failedDelivery.userMessage,
      'La invitación fue creada, pero el correo no pudo enviarse.',
    );
    expect(
      unknownDelivery.userMessage,
      'La invitación quedó disponible para el usuario.',
    );
    expect(accepted.membershipId, 'membership-a');
    expect(revoked.status, 'revoked');
    expect(calls, [
      'list_business_branches',
      'list_business_member_invitation_options',
      'list_business_member_invitations',
      'business-member-invitations',
      'accept_business_member_invitation',
      'revoke_business_member_invitation',
    ]);
    expect(RegExp(r'''\.from\s*\(\s*['"]''').hasMatch(source), isFalse);

    final expiredDatasource =
        BusinessAdministrationRemoteDatasource.withInvokers(
      rpc: (_, __) async => throw const PostgrestException(
        message: 'Business member invitation has expired',
        code: '42501',
      ),
      edge: (_) async => throw UnimplementedError(),
    );
    await expectLater(
      expiredDatasource.acceptInvitation('expired-invitation'),
      throwsA(
        isA<BusinessAdministrationException>().having(
          (error) => error.kind,
          'kind',
          BusinessAdministrationFailureKind.unavailable,
        ),
      ),
    );
  });

  test('logical retries reuse keys and concurrent submits are single-flight',
      () async {
    final keys = <String>[];
    final firstAttempt = Completer<Object?>();
    var calls = 0;
    final datasource = BusinessAdministrationRemoteDatasource.withInvokers(
      rpc: (name, params) async {
        calls += 1;
        keys.add(params['p_idempotency_key'] as String);
        if (calls == 1) return firstAttempt.future;
        return {
          'branch_id': 'branch-new',
          'business_id': 'business-a',
          'name': 'Norte',
          'runtime_ready': true,
          'idempotency_key': 'stable-key',
        };
      },
      edge: (_) async => throw UnimplementedError(),
    );
    final controller = BranchCreationController(
      BusinessAdministrationService(datasource),
      keyFactory: () => 'stable-key',
    );
    const request = CreateBusinessBranchRequest(
      businessId: 'business-a',
      name: 'Norte',
    );

    final first = controller.submit(request);
    final second = controller.submit(request);
    expect(identical(first, second), isTrue);
    expect(keys, ['stable-key']);
    firstAttempt.completeError(TimeoutException('transient'));
    await expectLater(first, throwsA(isA<BusinessAdministrationException>()));

    final retried = await controller.submit(request);
    expect(retried.branchId, 'branch-new');
    expect(keys, ['stable-key', 'stable-key']);

    final invitationKeys = <String>[];
    final invitationAttempt = Completer<Object?>();
    var edgeCalls = 0;
    final invitationDatasource =
        BusinessAdministrationRemoteDatasource.withInvokers(
      rpc: (_, __) async => throw UnimplementedError(),
      edge: (body) async {
        edgeCalls += 1;
        invitationKeys.add(body['idempotency_key'] as String);
        if (edgeCalls == 1) return invitationAttempt.future;
        return _issueJson();
      },
    );
    final invitationController = BusinessInvitationIssueController(
      BusinessAdministrationService(invitationDatasource),
      keyFactory: () => 'invitation-key',
    );
    const invitationRequest = IssueBusinessMemberInvitationRequest(
      businessId: 'business-a',
      email: 'employee@example.com',
      roleId: 'role-cashier',
      branchId: 'branch-a',
    );
    final issueFirst = invitationController.submit(invitationRequest);
    final issueDuplicate = invitationController.submit(invitationRequest);
    expect(identical(issueFirst, issueDuplicate), isTrue);
    invitationAttempt.completeError(TimeoutException('transient'));
    await expectLater(
      issueFirst,
      throwsA(isA<BusinessAdministrationException>()),
    );
    final issued = await invitationController.submit(invitationRequest);
    expect(issued.invitation.id, 'invitation-a');
    expect(invitationKeys, ['invitation-key', 'invitation-key']);
  });

  test('administration entry is gated only by effective capabilities', () {
    final allowed = DashboardModuleAccess.fromContext(
      _context(const ['members.invite']),
    );
    final branchAdministrator = DashboardModuleAccess.fromContext(
      _context(const ['settings.branches'], roles: const ['custom_operator']),
    );
    final mixedAdministrator = DashboardModuleAccess.fromContext(
      _context(const ['settings.branches', 'members.invite']),
    );
    final denied = DashboardModuleAccess.fromContext(
      _context(const [], roles: const ['owner']),
    );

    expect(allowed.canOpenAdministration, isTrue);
    expect(allowed.canInviteMembers, isTrue);
    expect(allowed.canManageBranches, isFalse);
    expect(branchAdministrator.canOpenAdministration, isTrue);
    expect(branchAdministrator.canManageBranches, isTrue);
    expect(branchAdministrator.canInviteMembers, isFalse);
    expect(mixedAdministrator.canManageBranches, isTrue);
    expect(mixedAdministrator.canInviteMembers, isTrue);
    expect(denied.canOpenAdministration, isFalse);
  });

  testWidgets(
    'local settings.branches absent skips branch authority lookup',
    (tester) async {
      var branchAuthorityCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            administrationCurrentContextProvider.overrideWith(
              (ref) async => _context(const ['members.invite']),
            ),
            businessBranchAdministrationProvider.overrideWith(
              (ref, request) async {
                branchAuthorityCalls += 1;
                return const BusinessBranchAdministrationAvailability.available(
                    []);
              },
            ),
          ],
          child: const MaterialApp(home: AdministrationHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(branchAuthorityCalls, 0);
      expect(find.text('Sucursales'), findsNothing);
      expect(find.text('Equipo'), findsOneWidget);
    },
  );

  test(
    'successful branch lookup is cached and scoped by profile and business',
    () async {
      final calls = <String>[];
      final service = _branchService((businessId) async {
        calls.add(businessId);
        return {
          'branches': [_branchJson()],
        };
      });
      final containerA = ProviderContainer(
        overrides: [
          currentSupabaseUserProvider.overrideWithValue(_userA),
          businessAdministrationServiceProvider.overrideWithValue(
            service,
          ),
        ],
      );
      addTearDown(containerA.dispose);
      const requestA = BusinessBranchAdministrationRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        hasLocalSettingsBranches: true,
      );

      final first = await containerA.read(
        businessBranchAdministrationProvider(requestA).future,
      );
      final reused = await containerA.read(
        businessBranchAdministrationProvider(requestA).future,
      );
      expect(
          first.kind, BusinessBranchAdministrationAvailabilityKind.available);
      expect(first.branches.single.id, 'branch-a');
      expect(reused.branches.single.id, 'branch-a');
      expect(calls, ['business-a']);

      final containerB = ProviderContainer(
        overrides: [
          currentSupabaseUserProvider.overrideWithValue(_userB),
          businessAdministrationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(containerB.dispose);
      final staleA = await containerB.read(
        businessBranchAdministrationProvider(requestA).future,
      );
      expect(
        staleA.kind,
        BusinessBranchAdministrationAvailabilityKind.notApplicable,
      );

      const requestB = BusinessBranchAdministrationRequest(
        profileId: 'profile-b',
        businessId: 'business-b',
        hasLocalSettingsBranches: true,
      );
      final switched = await containerB.read(
        businessBranchAdministrationProvider(requestB).future,
      );
      expect(
        switched.kind,
        BusinessBranchAdministrationAvailabilityKind.available,
      );
      expect(calls, ['business-a', 'business-b']);
    },
  );

  test('42501 becomes terminal unauthorized scope', () async {
    final container = _branchProviderContainer(
      _branchService((_) async => throw const PostgrestException(
            message: 'Business-wide settings.branches permission is required',
            code: '42501',
          )),
    );
    addTearDown(container.dispose);

    final result = await container.read(
      businessBranchAdministrationProvider(_branchRequest).future,
    );

    expect(
      result.kind,
      BusinessBranchAdministrationAvailabilityKind.unauthorizedScope,
    );
  });

  testWidgets(
    'network failure stays retryable without blocking Team',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSupabaseUserProvider.overrideWithValue(_userA),
            administrationCurrentContextProvider.overrideWith(
              (ref) async => _context(
                const ['settings.branches', 'members.invite'],
              ),
            ),
            businessAdministrationServiceProvider.overrideWithValue(
              _branchService(
                (_) async => throw const SocketException('offline'),
              ),
            ),
          ],
          child: const MaterialApp(home: AdministrationHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Equipo'), findsOneWidget);
      expect(
        find.text('No fue posible verificar el acceso a sucursales.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(
        find.text('Disponible para administración general del negocio.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'scope denial leaves Team usable without retryable branch error',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            administrationCurrentContextProvider.overrideWith(
              (ref) async => _context(
                const ['settings.branches', 'members.invite'],
              ),
            ),
            businessBranchAdministrationProvider.overrideWith(
              (ref, request) async =>
                  const BusinessBranchAdministrationAvailability
                      .unauthorizedScope(),
            ),
          ],
          child: const MaterialApp(home: AdministrationHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Equipo'), findsOneWidget);
      expect(find.text('Sucursales'), findsOneWidget);
      expect(
        find.text('Disponible para administración general del negocio.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsNothing);
      expect(find.textContaining('42501'), findsNothing);
    },
  );

  testWidgets(
    'direct Branches access renders scope denial without retry button',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            administrationCurrentContextProvider.overrideWith(
              (ref) async => _context(const ['settings.branches']),
            ),
            businessBranchAdministrationProvider.overrideWith(
              (ref, request) async =>
                  const BusinessBranchAdministrationAvailability
                      .unauthorizedScope(),
            ),
          ],
          child: const MaterialApp(home: BusinessBranchesScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'No tienes acceso a la administración general de sucursales.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
    },
  );
}

const _branchRequest = BusinessBranchAdministrationRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  hasLocalSettingsBranches: true,
);

const _userA = User(
  id: 'profile-a',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  email: 'a@example.com',
  createdAt: '2026-08-27T00:00:00Z',
);

const _userB = User(
  id: 'profile-b',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  email: 'b@example.com',
  createdAt: '2026-08-27T00:00:00Z',
);

ProviderContainer _branchProviderContainer(
  BusinessAdministrationService service,
) {
  return ProviderContainer(
    overrides: [
      currentSupabaseUserProvider.overrideWithValue(_userA),
      businessAdministrationServiceProvider.overrideWithValue(service),
    ],
  );
}

BusinessAdministrationService _branchService(
  Future<Object?> Function(String businessId) invoke,
) {
  return BusinessAdministrationService(
    BusinessAdministrationRemoteDatasource.withInvokers(
      rpc: (name, params) {
        if (name != 'list_business_branches') {
          throw StateError(name);
        }
        return invoke(params['p_business_id'] as String);
      },
      edge: (_) async => throw UnimplementedError(),
    ),
  );
}

Map<String, dynamic> _branchJson() => {
      'id': 'branch-a',
      'business_id': 'business-a',
      'name': 'Principal',
      'status': 'active',
      'is_primary': true,
      'runtime_ready': true,
    };

Map<String, dynamic> _optionsJson() => {
      'profile_id': 'profile-a',
      'business_id': 'business-a',
      'can_invite_business_wide': false,
      'delegable_roles': [
        {'role_id': 'role-cashier', 'role_name': 'cashier'},
      ],
      'invitable_branches': [
        {'branch_id': 'branch-a', 'name': 'Principal', 'is_primary': true},
      ],
    };

Map<String, dynamic> _invitationJson({
  String status = 'pending',
  String deliveryStatus = 'sent',
}) =>
    {
      'invitation_id': 'invitation-a',
      'business_id': 'business-a',
      'business_name': 'Negocio A',
      'email': 'employee@example.com',
      'role_id': 'role-cashier',
      'role_name': 'cashier',
      'branch_id': 'branch-a',
      'branch_name': 'Principal',
      'scope': 'branch',
      'status': status,
      'delivery_status': deliveryStatus,
      'expires_at': '2099-01-01T00:00:00Z',
      'is_expired': false,
    };

Map<String, dynamic> _issueJson({String deliveryStatus = 'sent'}) => {
      'invitation': _invitationJson(deliveryStatus: 'pending'),
      'delivery_attempted': true,
      'delivery': {'delivery_status': deliveryStatus},
      'existing_user_notification_required': false,
    };

AppCurrentContext _context(
  List<String> permissions, {
  List<String> roles = const [],
  String profileId = 'profile-a',
  String businessId = 'business-a',
  String branchId = 'branch-a',
}) {
  return AppCurrentContext(
    businessId: businessId,
    branchId: branchId,
    profileId: profileId,
    installationId: 'installation-a',
    isOnline: true,
    effectiveRoles: roles,
    authorizationContextReady: true,
    permissions: AppPermissionSet.fromIterable(permissions),
  );
}
