import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/connectivity_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../../core/utils/app_uuid.dart';
import '../data/datasources/self_service_business_creation_remote_datasource.dart';
import 'self_service_business_creation_service.dart';

final selfServiceBusinessCreationRemoteDataSourceProvider =
    Provider<SelfServiceBusinessCreationRemoteDataSource>((ref) {
  return SelfServiceBusinessCreationRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final selfServiceBusinessCreationServiceProvider =
    Provider<SelfServiceBusinessCreationService>((ref) {
  return SelfServiceBusinessCreationService(
    remote: ref.watch(selfServiceBusinessCreationRemoteDataSourceProvider),
    isOnline: () => ref.read(connectivityServiceProvider).isOnline,
  );
});

typedef SelfServiceBusinessCreator = Future<SelfServiceBusinessCreationResult>
    Function({
  required String businessName,
  required String branchName,
  required String idempotencyKey,
});

final selfServiceBusinessCreatorProvider =
    Provider<SelfServiceBusinessCreator>((ref) {
  return ref.watch(selfServiceBusinessCreationServiceProvider).create;
});

final selfServiceBusinessCreationIdempotencyKeyProvider =
    Provider<String Function()>((ref) => AppUuid.v7);
