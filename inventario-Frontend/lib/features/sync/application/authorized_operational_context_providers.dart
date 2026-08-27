import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/authorized_operational_context_remote_datasource.dart';
import 'authorized_operational_context_service.dart';

final authorizedOperationalContextRemoteDataSourceProvider =
    Provider<AuthorizedOperationalContextRemoteDataSource>((ref) {
  return AuthorizedOperationalContextRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final authorizedOperationalContextServiceProvider =
    Provider<AuthorizedOperationalContextService>((ref) {
  return AuthorizedOperationalContextService(
    remoteDataSource:
        ref.watch(authorizedOperationalContextRemoteDataSourceProvider),
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
  );
});
