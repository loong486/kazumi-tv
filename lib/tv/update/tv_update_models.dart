import 'dart:math' as math;

import 'package:kazumi/services/storage/storage.dart';

enum TvUpdateMirrorMode {
  ghProxy,
  ghfast,
  custom,
  direct;

  String get label => switch (this) {
    ghProxy => 'gh-proxy',
    ghfast => 'ghfast',
    custom => '自定义镜像',
    direct => '直连 GitHub',
  };

  String get description => switch (this) {
    ghProxy => '默认 GitHub 加速镜像',
    ghfast => '备用 GitHub 加速镜像',
    custom => '使用自建反代或自定义镜像前缀',
    direct => '不使用镜像，适合已配置代理的环境',
  };

  String get defaultPrefix => switch (this) {
    ghProxy => 'https://gh-proxy.org/',
    ghfast => 'https://ghfast.top/',
    custom => '',
    direct => '',
  };

  static TvUpdateMirrorMode fromStorage(String value) {
    final normalized = value.trim();
    return values.asNameMap()[normalized] ??
        switch (normalized.toLowerCase()) {
          'gh-proxy' || 'ghproxy' => TvUpdateMirrorMode.ghProxy,
          'ghfast' => TvUpdateMirrorMode.ghfast,
          'custom' => TvUpdateMirrorMode.custom,
          'direct' => TvUpdateMirrorMode.direct,
          _ => TvUpdateMirrorMode.ghProxy,
        };
  }
}

class TvUpdateConfig {
  TvUpdateConfig._();

  static const String defaultRepo = String.fromEnvironment(
    'TV_UPDATE_REPO',
    defaultValue: 'loong486/kazumi-tv',
  );

  static T _readSetting<T>(SettingKey<T> key) {
    try {
      return GStorage.getSetting(key);
    } catch (_) {
      return key.defaultValue;
    }
  }

  static String get activeRepo {
    final stored = normalizeRepo(_readSetting(SettingsKeys.tvUpdateRepo));
    if (stored != null) {
      return stored;
    }
    return normalizeRepo(defaultRepo) ?? 'loong486/kazumi-tv';
  }

  static String? normalizeRepo(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }

    String owner;
    String repo;
    if (trimmed.contains('://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        return null;
      }
      final host = uri.host.toLowerCase();
      if (host != 'github.com' && host != 'www.github.com') {
        return null;
      }
      final segments =
          uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
      if (segments.length != 2) {
        return null;
      }
      owner = segments[0];
      repo = segments[1];
    } else {
      final segments = trimmed.split('/');
      if (segments.length != 2) {
        return null;
      }
      owner = segments[0];
      repo = segments[1];
    }

    if (repo.toLowerCase().endsWith('.git') && repo.length > 4) {
      repo = repo.substring(0, repo.length - 4);
    }

    final validOwner = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$');
    final validRepo = RegExp(r'^[A-Za-z0-9._-]+$');
    if (!validOwner.hasMatch(owner) ||
        !validRepo.hasMatch(repo) ||
        repo == '.' ||
        repo == '..') {
      return null;
    }
    return '$owner/$repo';
  }

  static TvUpdateMirrorMode get activeMirrorMode =>
      TvUpdateMirrorMode.fromStorage(_readSetting(SettingsKeys.tvUpdateMirror));

  static String get customMirrorUrl =>
      normalizeMirrorPrefix(_readSetting(SettingsKeys.tvUpdateCustomMirrorUrl)) ??
      '';

  static String? normalizeMirrorPrefix(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final built = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments,
    ).toString();
    return built.endsWith('/') ? built : '$built/';
  }

  static String get ignoredVersion => TvVersionComparator.normalizeVersion(
    _readSetting(SettingsKeys.tvIgnoredUpdateVersion),
  );

  static Future<void> setIgnoredVersion(String version) async {
    final normalized = TvVersionComparator.normalizeVersion(version);
    await GStorage.putSetting(SettingsKeys.tvIgnoredUpdateVersion, normalized);
  }
}

class TvUpdateMirrorRewriter {
  TvUpdateMirrorRewriter._();

  static const Set<String> _wrappableHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'raw.githubusercontent.com',
  };

  static List<({String label, String url})> buildCandidateUrls(
    String rawUrl, {
    required TvUpdateMirrorMode preferredMode,
    String customMirrorPrefix = '',
  }) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return const [];
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return const [];
    }

    final normalizedCustom = TvUpdateConfig.normalizeMirrorPrefix(
      customMirrorPrefix,
    );
    final host = uri.host.toLowerCase();

    if (!_wrappableHosts.contains(host) ||
        _isAlreadyWrapped(trimmed, normalizedCustom)) {
      return [
        (
          label: _inferSourceLabel(trimmed, normalizedCustom),
          url: trimmed,
        ),
      ];
    }

    final order = switch (preferredMode) {
      TvUpdateMirrorMode.ghProxy => const [
        TvUpdateMirrorMode.ghProxy,
        TvUpdateMirrorMode.ghfast,
        TvUpdateMirrorMode.direct,
      ],
      TvUpdateMirrorMode.ghfast => const [
        TvUpdateMirrorMode.ghfast,
        TvUpdateMirrorMode.ghProxy,
        TvUpdateMirrorMode.direct,
      ],
      TvUpdateMirrorMode.custom => const [
        TvUpdateMirrorMode.custom,
        TvUpdateMirrorMode.ghProxy,
        TvUpdateMirrorMode.direct,
      ],
      TvUpdateMirrorMode.direct => const [
        TvUpdateMirrorMode.direct,
        TvUpdateMirrorMode.ghProxy,
      ],
    };

    final candidates = <({String label, String url})>[];
    final seenUrls = <String>{};

    for (final mode in order) {
      final candidateUrl = switch (mode) {
        TvUpdateMirrorMode.ghProxy =>
          '${TvUpdateMirrorMode.ghProxy.defaultPrefix}$trimmed',
        TvUpdateMirrorMode.ghfast =>
          '${TvUpdateMirrorMode.ghfast.defaultPrefix}$trimmed',
        TvUpdateMirrorMode.custom =>
          normalizedCustom == null ? null : '$normalizedCustom$trimmed',
        TvUpdateMirrorMode.direct => trimmed,
      };
      if (candidateUrl == null || !seenUrls.add(candidateUrl)) {
        continue;
      }
      candidates.add((label: mode.label, url: candidateUrl));
    }
    return candidates;
  }

  static bool _isAlreadyWrapped(String url, String? customPrefix) {
    final lower = url.toLowerCase();
    if (lower.startsWith(TvUpdateMirrorMode.ghProxy.defaultPrefix) ||
        lower.startsWith(TvUpdateMirrorMode.ghfast.defaultPrefix)) {
      return true;
    }
    if (customPrefix != null &&
        lower.startsWith(customPrefix.toLowerCase())) {
      return true;
    }
    final schemeIdx = url.indexOf('://');
    if (schemeIdx >= 0) {
      final rest = url.substring(schemeIdx + 3).toLowerCase();
      if (rest.contains('https://') || rest.contains('http://')) {
        return true;
      }
    }
    return false;
  }

  static String _inferSourceLabel(String url, String? customPrefix) {
    final lower = url.toLowerCase();
    if (lower.startsWith(TvUpdateMirrorMode.ghProxy.defaultPrefix)) {
      return TvUpdateMirrorMode.ghProxy.label;
    }
    if (lower.startsWith(TvUpdateMirrorMode.ghfast.defaultPrefix)) {
      return TvUpdateMirrorMode.ghfast.label;
    }
    if (customPrefix != null &&
        lower.startsWith(customPrefix.toLowerCase())) {
      return TvUpdateMirrorMode.custom.label;
    }
    return TvUpdateMirrorMode.direct.label;
  }
}

class TvVersionComparator {
  TvVersionComparator._();

  static final RegExp _digitsOnlyPattern = RegExp(r'^\d+$');

  static String normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1).trim();
    }
    return value;
  }

  static bool isNewer({
    required String localVersion,
    required String remoteVersion,
    int? localVersionCode,
    int? remoteVersionCode,
    int? remoteAssetVersionCode,
  }) {
    final parsedLocal = _ParsedVersion.tryParse(localVersion);
    final parsedRemote = _ParsedVersion.tryParse(remoteVersion);
    if (parsedRemote == null) {
      return false;
    }
    if (parsedLocal == null) {
      return true;
    }

    final cmp = parsedRemote.compareTo(parsedLocal);
    if (cmp != 0) {
      return cmp > 0;
    }

    // Same semantic version: use versionCode as tie-breaker, accounting for
    // split-ABI overrides (baseVersionCode * 10 + abiCode).
    if (localVersionCode == null || localVersionCode <= 0) {
      return false;
    }
    if (remoteAssetVersionCode != null && remoteAssetVersionCode > 0) {
      if (remoteVersionCode != null &&
          remoteVersionCode > 0 &&
          localVersionCode == remoteVersionCode &&
          remoteAssetVersionCode ~/ 10 == remoteVersionCode) {
        return false;
      }
      return remoteAssetVersionCode > localVersionCode;
    }
    if (remoteVersionCode != null && remoteVersionCode > 0) {
      if (localVersionCode >= 10 &&
          remoteVersionCode < localVersionCode &&
          localVersionCode > remoteVersionCode * 5 &&
          localVersionCode ~/ 10 <= remoteVersionCode + 1000) {
        return remoteVersionCode > (localVersionCode ~/ 10);
      }
      return remoteVersionCode > localVersionCode;
    }
    return false;
  }
}

class _ParsedVersion implements Comparable<_ParsedVersion> {
  const _ParsedVersion({
    required this.coreSegments,
    required this.preReleaseIdentifiers,
  });

  final List<int> coreSegments;
  final List<String> preReleaseIdentifiers;

  static _ParsedVersion? tryParse(String raw) {
    var normalized = TvVersionComparator.normalizeVersion(raw);
    if (normalized.isEmpty) {
      return null;
    }
    final plusIndex = normalized.indexOf('+');
    if (plusIndex >= 0) {
      normalized = normalized.substring(0, plusIndex).trim();
    }
    if (normalized.isEmpty) {
      return null;
    }

    String corePart = normalized;
    String? preReleasePart;
    final dashIndex = normalized.indexOf('-');
    if (dashIndex >= 0) {
      corePart = normalized.substring(0, dashIndex).trim();
      final tail = normalized.substring(dashIndex + 1).trim();
      if (tail.isNotEmpty) {
        preReleasePart = tail;
      }
    }
    if (corePart.isEmpty) {
      return null;
    }

    final rawCoreSegments = corePart.split('.');
    final coreSegments = <int>[];
    var parsedAnyCoreDigit = false;
    for (final segment in rawCoreSegments) {
      final trimmedSeg = segment.trim();
      if (trimmedSeg.isEmpty) {
        coreSegments.add(0);
        continue;
      }
      final exact = int.tryParse(trimmedSeg);
      if (exact != null) {
        coreSegments.add(exact);
        parsedAnyCoreDigit = true;
        continue;
      }
      final leadingDigits = RegExp(r'^(\d+)').firstMatch(trimmedSeg);
      if (leadingDigits != null) {
        coreSegments.add(int.tryParse(leadingDigits.group(1)!) ?? 0);
        parsedAnyCoreDigit = true;
        final suffix = trimmedSeg.substring(leadingDigits.end).trim();
        if (suffix.isNotEmpty) {
          preReleasePart =
              preReleasePart == null ? suffix : '$suffix.$preReleasePart';
        }
      } else {
        return null;
      }
    }
    if (!parsedAnyCoreDigit) {
      return null;
    }

    final preIds = preReleasePart == null
        ? const <String>[]
        : preReleasePart
              .split('.')
              .map((part) => part.trim())
              .where((part) => part.isNotEmpty)
              .toList(growable: false);

    return _ParsedVersion(
      coreSegments: coreSegments,
      preReleaseIdentifiers: preIds,
    );
  }

  @override
  int compareTo(_ParsedVersion other) {
    final maxLen = math.max(coreSegments.length, other.coreSegments.length);
    for (var i = 0; i < maxLen; i++) {
      final a = i < coreSegments.length ? coreSegments[i] : 0;
      final b = i < other.coreSegments.length ? other.coreSegments[i] : 0;
      if (a != b) {
        return a.compareTo(b);
      }
    }

    final aPre = preReleaseIdentifiers;
    final bPre = other.preReleaseIdentifiers;
    if (aPre.isEmpty && bPre.isEmpty) {
      return 0;
    }
    // Stable release has higher precedence than any pre-release.
    if (aPre.isEmpty) {
      return 1;
    }
    if (bPre.isEmpty) {
      return -1;
    }

    final minLen = math.min(aPre.length, bPre.length);
    for (var i = 0; i < minLen; i++) {
      final left = aPre[i];
      final right = bPre[i];
      if (left == right) {
        continue;
      }
      final leftIsNum = TvVersionComparator._digitsOnlyPattern.hasMatch(left);
      final rightIsNum = TvVersionComparator._digitsOnlyPattern.hasMatch(right);
      if (leftIsNum && rightIsNum) {
        final leftNum = int.tryParse(left);
        final rightNum = int.tryParse(right);
        if (leftNum != null && rightNum != null) {
          return leftNum.compareTo(rightNum);
        }
        final leftBig = BigInt.tryParse(left);
        final rightBig = BigInt.tryParse(right);
        if (leftBig != null && rightBig != null) {
          return leftBig.compareTo(rightBig);
        }
      }
      // Numeric identifiers always have lower precedence than non-numeric.
      if (leftIsNum != rightIsNum) {
        return leftIsNum ? -1 : 1;
      }
      return left.compareTo(right);
    }

    return aPre.length.compareTo(bPre.length);
  }
}

class TvUpdateApkAsset {
  const TvUpdateApkAsset({
    required this.abi,
    required this.fileName,
    required this.rawDownloadUrl,
    this.sha256 = '',
    this.size = 0,
    this.versionCode,
  });

  final String abi;
  final String fileName;
  final String rawDownloadUrl;
  final String sha256;
  final int size;
  final int? versionCode;

  bool get hasValidSha256 => RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256);
}

class TvUpdateRelease {
  const TvUpdateRelease({
    required this.version,
    required this.tag,
    this.versionCode,
    this.changelog = '',
    this.publishedAt = '',
    this.releaseUrl = '',
    this.force = false,
    this.apks = const {},
    this.sourceLabel = '',
  });

  final String version;
  final String tag;
  final int? versionCode;
  final String changelog;
  final String publishedAt;
  final String releaseUrl;
  final bool force;
  final Map<String, TvUpdateApkAsset> apks;
  final String sourceLabel;

  TvUpdateApkAsset? selectAssetForAbis(List<String> supportedAbis) {
    for (final rawAbi in supportedAbis) {
      final abi = rawAbi.trim().toLowerCase();
      if (abi.isEmpty) {
        continue;
      }
      final directMatch = apks[abi];
      if (directMatch != null) {
        return directMatch;
      }
    }
    return apks['universal'];
  }
}

class TvUpdateParser {
  TvUpdateParser._();

  static final RegExp _sha256HexPattern = RegExp(r'^[a-f0-9]{64}$');

  static TvUpdateRelease parseManifestJson(
    Map<String, dynamic> json, {
    required String repo,
    required String sourceLabel,
  }) {
    final rawVersion = json['version'];
    if (rawVersion is! String ||
        TvVersionComparator.normalizeVersion(rawVersion).isEmpty) {
      throw const TvUpdateException('更新清单缺少有效的 version 字段');
    }
    final version = TvVersionComparator.normalizeVersion(rawVersion);

    final rawApks = json['apks'];
    if (rawApks is! Map) {
      throw const TvUpdateException('更新清单缺少有效的 apks 字段');
    }

    final rawTag = json['tag'];
    final tag =
        (rawTag is String && rawTag.trim().isNotEmpty)
            ? rawTag.trim()
            : 'v$version';
    final versionCode = _parseInt(json['versionCode']);
    final changelog =
        json['changelog'] is String ? (json['changelog'] as String).trim() : '';
    final publishedAt =
        json['publishedAt'] is String
            ? (json['publishedAt'] as String).trim()
            : '';
    final rawReleaseUrl = json['releaseUrl'];
    final releaseUrl =
        (rawReleaseUrl is String && rawReleaseUrl.trim().isNotEmpty)
            ? rawReleaseUrl.trim()
            : 'https://github.com/$repo/releases/tag/$tag';
    final force = json['force'] == true;

    final apks = <String, TvUpdateApkAsset>{};
    for (final entry in rawApks.entries) {
      final abi = entry.key.toString().trim().toLowerCase();
      final value = entry.value;
      if (abi.isEmpty || value is! Map) {
        continue;
      }
      final assetMap = Map<String, dynamic>.from(value);
      final url = (assetMap['url'] as String?)?.trim() ?? '';
      if (url.isEmpty) {
        continue;
      }
      final parsedUri = Uri.tryParse(url);
      final fallbackName =
          (parsedUri != null && parsedUri.pathSegments.isNotEmpty)
              ? parsedUri.pathSegments.last
              : 'KazumiTV_${version}_$abi.apk';
      final rawFileName = (assetMap['fileName'] as String?)?.trim() ?? '';
      final fileName = rawFileName.isNotEmpty ? rawFileName : fallbackName;

      apks[abi] = TvUpdateApkAsset(
        abi: abi,
        fileName: fileName,
        rawDownloadUrl: url,
        sha256: _normalizeSha256(assetMap['sha256']),
        size: _parseInt(assetMap['size']) ?? 0,
        versionCode: _parseInt(assetMap['versionCode']),
      );
    }

    return TvUpdateRelease(
      version: version,
      tag: tag,
      versionCode: versionCode,
      changelog: changelog,
      publishedAt: publishedAt,
      releaseUrl: releaseUrl,
      force: force,
      apks: Map<String, TvUpdateApkAsset>.unmodifiable(apks),
      sourceLabel: sourceLabel,
    );
  }

  static TvUpdateRelease parseGithubReleaseJson(
    Map<String, dynamic> json, {
    required String sourceLabel,
  }) {
    final rawTag = json['tag_name'];
    if (rawTag is! String || rawTag.trim().isEmpty) {
      throw const TvUpdateException('GitHub Release 数据缺少有效的 tag_name');
    }
    final tag = rawTag.trim();
    final version = TvVersionComparator.normalizeVersion(tag);
    if (version.isEmpty) {
      throw const TvUpdateException('GitHub Release 数据缺少有效的版本号');
    }

    final changelog =
        json['body'] is String ? (json['body'] as String).trim() : '';
    final publishedAt =
        json['published_at'] is String
            ? (json['published_at'] as String).trim()
            : '';
    final releaseUrl =
        json['html_url'] is String ? (json['html_url'] as String).trim() : '';

    final apks = <String, TvUpdateApkAsset>{};
    final rawAssets = json['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is! Map) {
          continue;
        }
        final assetMap = Map<String, dynamic>.from(item);
        final fileName = (assetMap['name'] as String?)?.trim() ?? '';
        final downloadUrl =
            (assetMap['browser_download_url'] as String?)?.trim() ?? '';
        if (fileName.isEmpty ||
            downloadUrl.isEmpty ||
            !fileName.toLowerCase().endsWith('.apk')) {
          continue;
        }

        final abi = _extractAbiFromFileName(fileName);
        if (abi == null) {
          continue;
        }

        apks[abi] = TvUpdateApkAsset(
          abi: abi,
          fileName: fileName,
          rawDownloadUrl: downloadUrl,
          sha256: _normalizeSha256(assetMap['digest']),
          size: _parseInt(assetMap['size']) ?? 0,
          versionCode: null,
        );
      }
    }

    return TvUpdateRelease(
      version: version,
      tag: tag,
      versionCode: null,
      changelog: changelog,
      publishedAt: publishedAt,
      releaseUrl: releaseUrl,
      force: false,
      apks: Map<String, TvUpdateApkAsset>.unmodifiable(apks),
      sourceLabel: sourceLabel,
    );
  }

  static String? _extractAbiFromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('arm64-v8a') || lower.contains('arm64')) {
      return 'arm64-v8a';
    }
    if (lower.contains('armeabi-v7a') || lower.contains('armeabi')) {
      return 'armeabi-v7a';
    }
    if (lower.contains('x86_64') || lower.contains('x86-64')) {
      return 'x86_64';
    }
    if (lower.contains('universal')) {
      return 'universal';
    }
    if (!lower.contains('x86') &&
        !lower.contains('mips') &&
        !lower.contains('riscv')) {
      return 'universal';
    }
    return null;
  }

  static String _normalizeSha256(Object? rawValue) {
    if (rawValue is! String) {
      return '';
    }
    var trimmed = rawValue.trim().toLowerCase();
    if (trimmed.startsWith('sha256:')) {
      trimmed = trimmed.substring(7).trim();
    }
    return _sha256HexPattern.hasMatch(trimmed) ? trimmed : '';
  }

  static int? _parseInt(Object? rawValue) {
    return switch (rawValue) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value.trim()),
      _ => null,
    };
  }
}

enum TvUpdateCheckStatus { upToDate, updateAvailable, incompatibleAbi }

class TvUpdateCheckResult {
  const TvUpdateCheckResult({
    required this.currentVersion,
    this.currentVersionCode,
    required this.status,
    this.release,
    this.matchedAsset,
    this.supportedAbis = const [],
  });

  final String currentVersion;
  final int? currentVersionCode;
  final TvUpdateCheckStatus status;
  final TvUpdateRelease? release;
  final TvUpdateApkAsset? matchedAsset;
  final List<String> supportedAbis;

  bool get hasUpdate =>
      status == TvUpdateCheckStatus.updateAvailable &&
      release != null &&
      matchedAsset != null;
}

enum TvUpdateDownloadStage {
  preparing,
  downloading,
  switchingMirror,
  verifying,
  completed,
}

class TvUpdateDownloadProgress {
  const TvUpdateDownloadProgress({
    required this.stage,
    required this.receivedBytes,
    required this.totalBytes,
    required this.bytesPerSecond,
    required this.activeSourceLabel,
    required this.message,
  });

  final TvUpdateDownloadStage stage;
  final int receivedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final String activeSourceLabel;
  final String message;

  double? get fraction {
    if (stage == TvUpdateDownloadStage.completed) {
      return 1.0;
    }
    if (totalBytes <= 0) {
      return null;
    }
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }
}

enum TvUpdateInstallOutcome { launched, permissionRequired, failed }

class TvUpdateInstallResult {
  const TvUpdateInstallResult({
    required this.outcome,
    this.message = '',
  });

  final TvUpdateInstallOutcome outcome;
  final String message;
}

class TvUpdateException implements Exception {
  const TvUpdateException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
