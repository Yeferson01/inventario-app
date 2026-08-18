import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_selected_sync_context_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppSelectedSyncContextStore', () {
    test('saves and loads selected sync context', () async {
      SharedPreferences.setMockInitialValues({});

      final store = AppSelectedSyncContextStore();

      const context = AppSelectedSyncContext(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
      );

      await store.saveSelectedContext(context);

      final loaded = await store.getSelectedContext(profileId: 'profile-1');

      expect(loaded, isNotNull);
      expect(loaded!.businessId, equals('business-1'));
      expect(loaded.branchId, equals('branch-1'));
      expect(loaded.profileId, equals('profile-1'));
    });

    test('clears selected sync context', () async {
      SharedPreferences.setMockInitialValues({});

      final store = AppSelectedSyncContextStore();

      await store.saveSelectedContext(
        const AppSelectedSyncContext(
          businessId: 'business-1',
          profileId: 'profile-1',
        ),
      );

      await store.clearSelectedContext(profileId: 'profile-1');

      final loaded = await store.getSelectedContext(profileId: 'profile-1');

      expect(loaded, isNull);
    });

    test('serializes selected context', () {
      const context = AppSelectedSyncContext(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
      );

      final json = context.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['branch_id'], equals('branch-1'));
      expect(json['profile_id'], equals('profile-1'));
    });

    test('keeps selections isolated by profile', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppSelectedSyncContextStore();

      await store.saveSelectedContext(
        const AppSelectedSyncContext(
          businessId: 'business-a',
          branchId: 'branch-a',
          profileId: 'profile-a',
        ),
      );
      await store.saveSelectedContext(
        const AppSelectedSyncContext(
          businessId: 'business-b',
          branchId: 'branch-b',
          profileId: 'profile-b',
        ),
      );

      expect(
        (await store.getSelectedContext(profileId: 'profile-a'))?.businessId,
        'business-a',
      );
      expect(
        (await store.getSelectedContext(profileId: 'profile-b'))?.businessId,
        'business-b',
      );
    });

    test('does not give profile B a legacy context owned by profile A',
        () async {
      SharedPreferences.setMockInitialValues({
        'app_sync.selected_context':
            '{"business_id":"business-a","branch_id":"branch-a",'
                '"profile_id":"profile-a"}',
      });
      final store = AppSelectedSyncContextStore();

      expect(
        await store.getSelectedContext(profileId: 'profile-b'),
        isNull,
      );
      expect(
        (await store.getSelectedContext(profileId: 'profile-a'))?.branchId,
        'branch-a',
      );
    });

    test('ignores an unverifiable legacy global context', () async {
      SharedPreferences.setMockInitialValues({
        'app_sync.selected_context':
            '{"business_id":"business-a","branch_id":"branch-a"}',
      });
      final store = AppSelectedSyncContextStore();

      expect(
        await store.getSelectedContext(profileId: 'profile-b'),
        isNull,
      );
    });
  });
}
