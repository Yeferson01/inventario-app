import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/connectivity_service.dart';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

final isOnlineStreamProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).isOnlineStream;
});

final isOnlineFutureProvider = FutureProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).isOnline;
});
