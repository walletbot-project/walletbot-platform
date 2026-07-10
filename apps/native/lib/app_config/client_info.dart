import 'dart:io' show Platform;

import 'package:app/app_config/device_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Identifies this client build to the backend: the [platform] key and
/// [appVersion] used by the native version gate. Resolved once at startup and
/// passed to the consumers so there is a single source of client identity.
@immutable
class ClientInfo {
  const ClientInfo({
    required this.platform,
    required this.appVersion,
    required this.deviceId,
  });

  final String platform;
  final String appVersion;
  final String deviceId;

  static Future<ClientInfo> resolve({FlutterSecureStorage? storage}) async {
    final resolvedStorage = storage ?? const FlutterSecureStorage();
    return ClientInfo(
      platform: clientPlatform(),
      appVersion: await _resolveAppVersion(),
      deviceId: await resolveDeviceId(resolvedStorage),
    );
  }

  static Future<String> _resolveAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      debugPrint('client_info: package info failed: $e');
      return '0.0.0';
    }
  }
}

/// The platform key sent to the backend. Kept in one place so the config
/// verdict and sync gate agree on the string.
String clientPlatform() {
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  if (Platform.isMacOS) return 'macos';
  return 'unknown';
}
