import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device/app_device_info_service.dart';
import '../device/installation_id_service.dart';

final installationIdServiceProvider = Provider<InstallationIdService>((ref) {
  return InstallationIdService();
});

final installationIdProvider = FutureProvider<String>((ref) {
  return ref.watch(installationIdServiceProvider).getOrCreateInstallationId();
});

final appDeviceInfoServiceProvider = Provider<AppDeviceInfoService>((ref) {
  return AppDeviceInfoService();
});

final appDeviceInfoProvider = FutureProvider<AppDeviceInfo>((ref) {
  return ref.watch(appDeviceInfoServiceProvider).getDeviceInfo();
});
