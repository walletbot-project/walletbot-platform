import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

const _deviceIdKey = 'native_device_id';

/// Stable per-install id for config/flag targeting.
///
/// This is intentionally random app state, not a hardware identifier.
Future<String> resolveDeviceId(FlutterSecureStorage storage) async {
  try {
    final existing = await storage.read(key: _deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) return existing;

    final created = const Uuid().v4();
    await storage.write(key: _deviceIdKey, value: created);
    return created;
  } catch (e) {
    debugPrint('device_id: failed to resolve stable id: $e');
    return 'unknown';
  }
}
