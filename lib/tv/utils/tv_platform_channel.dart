import 'dart:io';

import 'package:flutter/services.dart';

class TvAppVersionInfo {
  const TvAppVersionInfo({
    required this.versionName,
    required this.versionCode,
  });

  final String versionName;
  final int versionCode;
}

class TvPlatformChannel {
  TvPlatformChannel._();

  static const MethodChannel _channel = MethodChannel('com.predidit.kazumi/tv');
  static const List<String> _defaultAbis = ['arm64-v8a', 'armeabi-v7a'];

  static Future<void> setKeepScreenOn(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } catch (_) {
      // Ignore in widget tests or when channel is unavailable.
    }
  }

  static Future<bool> isTvDevice() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('isTvDevice') ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<List<String>> getSupportedAbis() async {
    if (!Platform.isAndroid) {
      return _defaultAbis;
    }
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'getSupportedAbis',
      );
      if (result == null || result.isEmpty) {
        return _defaultAbis;
      }
      final abis = result
          .whereType<String>()
          .map((abi) => abi.trim())
          .where((abi) => abi.isNotEmpty)
          .toList(growable: false);
      return abis.isEmpty ? _defaultAbis : abis;
    } catch (_) {
      return _defaultAbis;
    }
  }

  static Future<TvAppVersionInfo?> getAppVersionInfo() async {
    if (!Platform.isAndroid) {
      return null;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'getAppVersionInfo',
      );
      if (result == null) {
        return null;
      }
      final versionName = (result['versionName'] as String?)?.trim() ?? '';
      final rawCode = result['versionCode'];
      final versionCode = switch (rawCode) {
        int value => value,
        num value => value.toInt(),
        String value => int.tryParse(value) ?? 0,
        _ => 0,
      };
      if (versionName.isEmpty && versionCode <= 0) {
        return null;
      }
      return TvAppVersionInfo(
        versionName: versionName,
        versionCode: versionCode,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('canRequestPackageInstalls') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>(
            'openInstallPermissionSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
