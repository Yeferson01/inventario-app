import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/self_service_business_creation_providers.dart';
import 'package:inventario_frontend/features/auth/application/self_service_business_creation_service.dart';
import 'package:inventario_frontend/features/auth/data/datasources/self_service_business_creation_remote_datasource.dart';
import 'package:inventario_frontend/features/auth/presentation/screens/create_business_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('CB-04/05/06 validates, normalizes and calls the exact RPC contract',
      () async {
    Map<String, dynamic>? captured;
    final remote = SelfServiceBusinessCreationRemoteDataSource.withInvoker(
      (params) async {
        captured = params;
        return const {
          'business_id': 'business-created',
          'branch_id': 'branch-created',
        };
      },
    );
    final service = SelfServiceBusinessCreationService(
      remote: remote,
      isOnline: () async => true,
    );

    final result = await service.create(
      businessName: '  Mi Tienda  ',
      branchName: '   ',
      idempotencyKey: '  attempt-1  ',
    );

    expect(result.businessId, 'business-created');
    expect(result.branchId, 'branch-created');
    expect(captured, {
      'p_business_name': 'Mi Tienda',
      'p_idempotency_key': 'attempt-1',
      'p_branch_name': 'Sucursal Principal',
    });
  });

  test('CB-09 offline creation fails before invoking the RPC', () async {
    var rpcCalls = 0;
    final service = SelfServiceBusinessCreationService(
      remote: SelfServiceBusinessCreationRemoteDataSource.withInvoker(
        (_) async {
          rpcCalls += 1;
          return const {};
        },
      ),
      isOnline: () async => false,
    );

    await expectLater(
      service.create(
        businessName: 'Mi Tienda',
        branchName: 'Sucursal Principal',
        idempotencyKey: 'attempt-1',
      ),
      throwsA(
        isA<SelfServiceBusinessCreationException>()
            .having(
              (error) => error.kind,
              'kind',
              SelfServiceBusinessCreationFailureKind.network,
            )
            .having(
              (error) => error.message,
              'message',
              'Necesitas conexión a internet para crear un negocio.',
            ),
      ),
    );
    expect(rpcCalls, 0);
  });

  test('CB-13 idempotency conflict uses the safe productive copy', () async {
    final remote = SelfServiceBusinessCreationRemoteDataSource.withInvoker(
      (_) async => throw const PostgrestException(
        message: 'self_service_business_creation_idempotency_conflict',
        code: '23505',
      ),
    );

    await expectLater(
      remote.create(
        businessName: 'Mi Tienda',
        branchName: 'Principal',
        idempotencyKey: 'attempt-1',
      ),
      throwsA(
        isA<SelfServiceBusinessCreationException>().having(
          (error) => error.message,
          'message',
          'No pudimos completar la creación porque esta solicitud cambió. Intenta nuevamente.',
        ),
      ),
    );
  });

  testWidgets(
      'CB-07/08 single-flight disables duplicate submit and retry reuses key',
      (tester) async {
    final first = Completer<SelfServiceBusinessCreationResult>();
    final keys = <String>[];
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selfServiceBusinessCreationIdempotencyKeyProvider.overrideWithValue(
            () => 'stable-attempt-key',
          ),
          selfServiceBusinessCreatorProvider.overrideWithValue(({
            required businessName,
            required branchName,
            required idempotencyKey,
          }) {
            calls += 1;
            keys.add(idempotencyKey);
            if (calls == 1) return first.future;
            return Future.value(
              const SelfServiceBusinessCreationResult(
                businessId: 'business-created',
                branchId: 'branch-created',
              ),
            );
          }),
        ],
        child: MaterialApp(
          home: CreateBusinessScreen(
            onCreated: (_) async {},
            onCancel: () {},
            onSessionInvalid: () async {},
          ),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('create-business-name')),
      'Mi Tienda',
    );
    await tester.tap(find.byKey(const Key('create-business-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-business-submit')));
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Creando negocio…'), findsOneWidget);

    first.completeError(
      const SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.network,
        message: 'Necesitas conexión a internet para crear un negocio.',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Necesitas conexión a internet para crear un negocio.'),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('create-business-submit')));
    await tester.pump();

    expect(calls, 2);
    expect(keys, ['stable-attempt-key', 'stable-attempt-key']);
  });

  testWidgets('CB-04 empty business name is rejected locally', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selfServiceBusinessCreatorProvider.overrideWithValue(({
            required businessName,
            required branchName,
            required idempotencyKey,
          }) async {
            calls += 1;
            return const SelfServiceBusinessCreationResult(
              businessId: 'business-created',
              branchId: 'branch-created',
            );
          }),
        ],
        child: MaterialApp(
          home: CreateBusinessScreen(
            onCreated: (_) async {},
            onCancel: () {},
            onSessionInvalid: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('create-business-submit')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text('Ingresa el nombre del negocio.'), findsOneWidget);
  });

  testWidgets('CB-12 unknown errors are sanitized', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selfServiceBusinessCreationIdempotencyKeyProvider.overrideWithValue(
            () => 'attempt-key',
          ),
          selfServiceBusinessCreatorProvider.overrideWithValue(({
            required businessName,
            required branchName,
            required idempotencyKey,
          }) async {
            throw StateError('internal SQL detail business-secret');
          }),
        ],
        child: MaterialApp(
          home: CreateBusinessScreen(
            onCreated: (_) async {},
            onCancel: () {},
            onSessionInvalid: () async {},
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('create-business-name')),
      'Mi Tienda',
    );
    await tester.tap(find.byKey(const Key('create-business-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('No fue posible crear el negocio. Intenta nuevamente.'),
      findsOneWidget,
    );
    expect(find.textContaining('SQL'), findsNothing);
    expect(find.textContaining('business-secret'), findsNothing);
  });
}
