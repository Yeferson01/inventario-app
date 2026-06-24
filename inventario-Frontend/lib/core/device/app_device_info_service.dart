import 'dart:io' show Platform;

import 'package:package_info_plus/package_info_plus.dart';

class AppDeviceInfo {
  const AppDeviceInfo({
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    required this.deviceName,
    required this.osVersion,
  });

  final String platform;
  final String appVersion;
  final String buildNumber;
  final String deviceName;
  final String osVersion;

  Map<String, dynamic> toJson() {
    return {
      'platform': platform,
      'app_version': appVersion,
      'build_number': buildNumber,
      'device_name': deviceName,
      'os_version': osVersion,
    };
  }
}

class AppDeviceInfoService {
  Future<AppDeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    return AppDeviceInfo(
      platform: _platformName(),
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      deviceName: _deviceName(),
      osVersion: _osVersion(),
    );
  }

  String _platformName() {
    if (Platform.isAndroid) {
      return 'android';
    }

    if (Platform.isIOS) {
      return 'ios';
    }

    if (Platform.isWindows) {
      return 'windows';
    }

    if (Platform.isMacOS) {
      return 'macos';
    }

    if (Platform.isLinux) {
      return 'linux';
    }

    return 'unknown';
  }

  String _deviceName() {
    return Platform.localHostname;
  }

  String _osVersion() {
    return Platform.operatingSystemVersion;
  }
}
