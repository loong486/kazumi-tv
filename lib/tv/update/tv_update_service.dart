import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/request/clients/download_http_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/tv/update/tv_update_models.dart';
import 'package:kazumi/tv/utils/tv_platform_channel.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef TvUpdatePlainGetter = Future<String> Function(
  String url, {
  Map<String, dynamic> headers,
  Duration? receiveTimeout,
  CancelToken? cancelToken,
});

typedef TvUpdateFileDownloader = Future<void> Function(
  String url,
  String savePath, {
  CancelToken? cancelToken,
  ProgressCallback? onReceiveProgress,
});

typedef TvUpdateAbiProvider = Future<List<String>> Function();
typedef TvUpdateVersionInfoProvider = Future<TvAppVersionInfo?> Function();
typedef TvUpdateAvailableStorageProvider = Future<int> Function(String path);
typedef TvUpdateTempDirProvider = Future<Directory> Function();
typedef TvUpdateInstallPermissionChecker = Future<bool> Function();
typedef TvUpdateApkOpener = Future<OpenResult> Function(String filePath);

class _TvUpdateIntegrityException extends TvUpdateException {
  const _TvUpdateIntegrityException(super.message);
}

class TvUpdateService {
  TvUpdateService({
    TvUpdatePlainGetter? plainGetter,
    TvUpdateFileDownloader? fileDownloader,
    TvUpdateAbiProvider? abiProvider,
    TvUpdateVersionInfoProvider? versionInfoProvider,
    TvUpdateAvailableStorageProvider? availableStorageProvider,
    TvUpdateTempDirProvider? tempDirProvider,
    TvUpdateInstallPermissionChecker? installPermissionChecker,
    TvUpdateApkOpener? apkOpener,
  }) : _plainGetter = plainGetter ?? _defaultPlainGetter,
       _fileDownloader = fileDownloader ?? _defaultFileDownloader,
       _abiProvider = abiProvider ?? TvPlatformChannel.getSupportedAbis,
       _versionInfoProvider =
           versionInfoProvider ?? TvPlatformChannel.getAppVersionInfo,
       _availableStorageProvider =
           availableStorageProvider ?? _defaultAvailableStorageProvider,
       _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
       _installPermissionChecker =
           installPermissionChecker ??
           TvPlatformChannel.canRequestPackageInstalls,
       _apkOpener = apkOpener ?? _defaultApkOpener;

  static final TvUpdateService instance = TvUpdateService();

  static const MethodChannel _storageChannel = MethodChannel(
    'com.predidit.kazumi/storage',
  );
  static const Duration _metadataReceiveTimeout = Duration(seconds: 12);
  static const int _minRequiredStorageBytes = 80 * 1024 * 1024;
  static const List<int> _apkMagicBytes = [0x50, 0x4B, 0x03, 0x04];
  static const int _progressThrottleMs = 250;

  final TvUpdatePlainGetter _plainGetter;
  final TvUpdateFileDownloader _fileDownloader;
  final TvUpdateAbiProvider _abiProvider;
  final TvUpdateVersionInfoProvider _versionInfoProvider;
  final TvUpdateAvailableStorageProvider _availableStorageProvider;
  final TvUpdateTempDirProvider _tempDirProvider;
  final TvUpdateInstallPermissionChecker _installPermissionChecker;
  final TvUpdateApkOpener _apkOpener;

  static Future<String> _defaultPlainGetter(
    String url, {
    Map<String, dynamic> headers = const {},
    Duration? receiveTimeout,
    CancelToken? cancelToken,
  }) {
    return DownloadHttpClient.instance.getPlain(
      url,
      headers: headers,
      receiveTimeout: receiveTimeout,
      cancelToken: cancelToken,
    );
  }

  static Future<void> _defaultFileDownloader(
    String url,
    String savePath, {
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) {
    return DownloadHttpClient.instance.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }

  static Future<int> _defaultAvailableStorageProvider(String path) async {
    try {
      final result = await _storageChannel.invokeMethod<int>(
        'getAvailableStorage',
        {'path': path},
      );
      return result ?? -1;
    } on MissingPluginException {
      return -1;
    } catch (e) {
      KazumiLogger().w('TvUpdate: failed to get available storage', error: e);
      return -1;
    }
  }

  static Future<OpenResult> _defaultApkOpener(String filePath) {
    return OpenFilex.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );
  }

  Future<TvUpdateCheckResult> checkForUpdates({
    String? repoOverride,
    TvUpdateMirrorMode? mirrorOverride,
    String? customMirrorOverride,
    CancelToken? cancelToken,
  }) async {
    final repo = _resolveRepo(repoOverride);
    final mode = mirrorOverride ?? TvUpdateConfig.activeMirrorMode;
    final customPrefix =
        customMirrorOverride != null
            ? (TvUpdateConfig.normalizeMirrorPrefix(customMirrorOverride) ?? '')
            : TvUpdateConfig.customMirrorUrl;

    _throwIfCancelled(cancelToken, 'https://github.com/$repo');

    final versionInfo = await _versionInfoProvider();
    final rawVersionName = versionInfo?.versionName.trim() ?? '';
    final currentVersion = TvVersionComparator.normalizeVersion(
      rawVersionName.isNotEmpty ? rawVersionName : ApiEndpoints.version,
    );
    final currentVersionCode = versionInfo?.versionCode;

    final rawAbis = await _abiProvider();
    final supportedAbis = rawAbis
        .map((abi) => abi.trim())
        .where((abi) => abi.isNotEmpty)
        .toList(growable: false);

    _throwIfCancelled(cancelToken, 'https://github.com/$repo');

    TvUpdateRelease? release;
    Object? lastError;

    final manifestUrl =
        'https://github.com/$repo/releases/latest/download/latest.json';
    final manifestCandidates = TvUpdateMirrorRewriter.buildCandidateUrls(
      manifestUrl,
      preferredMode: mode,
      customMirrorPrefix: customPrefix,
    );

    for (final candidate in manifestCandidates) {
      _throwIfCancelled(cancelToken, candidate.url);
      try {
        final raw = await _plainGetter(
          candidate.url,
          receiveTimeout: _metadataReceiveTimeout,
          cancelToken: cancelToken,
        );
        _throwIfCancelled(cancelToken, candidate.url);
        final decoded = json.decode(raw);
        if (decoded is! Map) {
          throw const TvUpdateException('更新清单 JSON 顶层必须是对象');
        }
        final map = Map<String, dynamic>.from(decoded);
        if (map['version'] is! String ||
            TvVersionComparator.normalizeVersion(
              map['version'] as String,
            ).isEmpty ||
            map['apks'] is! Map) {
          throw const TvUpdateException('更新清单缺少必要的 version 或 apks 字段');
        }
        release = TvUpdateParser.parseManifestJson(
          map,
          repo: repo,
          sourceLabel: candidate.label,
        );
        break;
      } catch (e) {
        if (_isCancelledError(e, cancelToken)) {
          rethrow;
        }
        lastError = e;
        KazumiLogger().w(
          'TvUpdate: manifest fetch failed from ${candidate.label}',
          error: e,
        );
      }
    }

    if (release == null) {
      final apiUrl = 'https://api.github.com/repos/$repo/releases/latest';
      final apiCandidates = TvUpdateMirrorRewriter.buildCandidateUrls(
        apiUrl,
        preferredMode: mode,
        customMirrorPrefix: customPrefix,
      );

      for (final candidate in apiCandidates) {
        _throwIfCancelled(cancelToken, candidate.url);
        try {
          final raw = await _plainGetter(
            candidate.url,
            headers: const {'Accept': 'application/vnd.github+json'},
            receiveTimeout: _metadataReceiveTimeout,
            cancelToken: cancelToken,
          );
          _throwIfCancelled(cancelToken, candidate.url);
          final decoded = json.decode(raw);
          if (decoded is! Map) {
            throw const TvUpdateException('GitHub Release API 响应格式无效');
          }
          release = TvUpdateParser.parseGithubReleaseJson(
            Map<String, dynamic>.from(decoded),
            sourceLabel: candidate.label,
          );
          break;
        } catch (e) {
          if (_isCancelledError(e, cancelToken)) {
            rethrow;
          }
          lastError = e;
          KazumiLogger().w(
            'TvUpdate: GitHub release fallback failed from ${candidate.label}',
            error: e,
          );
        }
      }
    }

    if (release == null) {
      throw _wrapCheckError(lastError);
    }

    final matchedAsset = release.selectAssetForAbis(supportedAbis);
    final hasNewerVersion = TvVersionComparator.isNewer(
      localVersion: currentVersion,
      remoteVersion: release.version,
      localVersionCode: currentVersionCode,
      remoteVersionCode: release.versionCode,
      remoteAssetVersionCode: matchedAsset?.versionCode,
    );

    if (!hasNewerVersion) {
      return TvUpdateCheckResult(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        status: TvUpdateCheckStatus.upToDate,
        release: release,
        matchedAsset: matchedAsset,
        supportedAbis: supportedAbis,
      );
    }

    if (matchedAsset == null) {
      return TvUpdateCheckResult(
        currentVersion: currentVersion,
        currentVersionCode: currentVersionCode,
        status: TvUpdateCheckStatus.incompatibleAbi,
        release: release,
        matchedAsset: null,
        supportedAbis: supportedAbis,
      );
    }

    return TvUpdateCheckResult(
      currentVersion: currentVersion,
      currentVersionCode: currentVersionCode,
      status: TvUpdateCheckStatus.updateAvailable,
      release: release,
      matchedAsset: matchedAsset,
      supportedAbis: supportedAbis,
    );
  }

  Future<String> downloadApk({
    required TvUpdateRelease release,
    required TvUpdateApkAsset asset,
    TvUpdateMirrorMode? mirrorOverride,
    String? customMirrorOverride,
    required CancelToken cancelToken,
    required void Function(TvUpdateDownloadProgress progress) onProgress,
  }) async {
    _throwIfCancelled(cancelToken, asset.rawDownloadUrl);

    final mode = mirrorOverride ?? TvUpdateConfig.activeMirrorMode;
    final customPrefix =
        customMirrorOverride != null
            ? (TvUpdateConfig.normalizeMirrorPrefix(customMirrorOverride) ?? '')
            : TvUpdateConfig.customMirrorUrl;

    onProgress(
      TvUpdateDownloadProgress(
        stage: TvUpdateDownloadStage.preparing,
        receivedBytes: 0,
        totalBytes: asset.size,
        bytesPerSecond: 0,
        activeSourceLabel: release.sourceLabel,
        message: '正在准备下载安装包...',
      ),
    );

    final tempDir = await _tempDirProvider();
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    _throwIfCancelled(cancelToken, asset.rawDownloadUrl);

    final availableStorage = await _availableStorageProvider(tempDir.path);
    final requiredStorage = math.max(
      (asset.size * 2.5).ceil(),
      _minRequiredStorageBytes,
    );
    if (availableStorage > 0 && requiredStorage > availableStorage) {
      throw TvUpdateException(
        '可用存储空间不足（需要 ${formatBytes(requiredStorage)}，当前可用 ${formatBytes(availableStorage)}）',
      );
    }

    final targetPath = _cachedApkPath(tempDir, release.version, asset.abi);
    final targetFile = File(targetPath);

    if (await targetFile.exists()) {
      final cacheValid = await _isCachedFileValid(targetFile, asset);
      _throwIfCancelled(cancelToken, asset.rawDownloadUrl);
      if (cacheValid) {
        final size = await targetFile.length();
        onProgress(
          TvUpdateDownloadProgress(
            stage: TvUpdateDownloadStage.completed,
            receivedBytes: size,
            totalBytes: size,
            bytesPerSecond: 0,
            activeSourceLabel: '本地缓存',
            message: '已命中本地校验缓存',
          ),
        );
        return targetFile.path;
      }
      await targetFile.delete();
    }

    final candidates = TvUpdateMirrorRewriter.buildCandidateUrls(
      asset.rawDownloadUrl,
      preferredMode: mode,
      customMirrorPrefix: customPrefix,
    );
    if (candidates.isEmpty) {
      throw const TvUpdateException('没有可用的安装包下载地址');
    }

    final downloadDir = await tempDir.createTemp('kazumi-update-');
    try {
      final partial = File(p.join(downloadDir.path, 'download.part'));
      Object? lastError;

      for (var i = 0; i < candidates.length; i++) {
        _throwIfCancelled(cancelToken, candidates[i].url);
        final candidate = candidates[i];

        if (await partial.exists()) {
          await partial.delete();
        }

        final speedTracker = _SmoothedSpeedTracker();
        DateTime? lastEmitTime;

        onProgress(
          TvUpdateDownloadProgress(
            stage: TvUpdateDownloadStage.downloading,
            receivedBytes: 0,
            totalBytes: asset.size,
            bytesPerSecond: 0,
            activeSourceLabel: candidate.label,
            message: '正在通过 ${candidate.label} 下载...',
          ),
        );

        try {
          await _fileDownloader(
            candidate.url,
            partial.path,
            cancelToken: cancelToken,
            onReceiveProgress: (received, total) {
              if (cancelToken.isCancelled) {
                return;
              }
              final effectiveTotal = total > 0 ? total : asset.size;
              final now = DateTime.now();
              final speed = speedTracker.update(received, now);
              final isDone = effectiveTotal > 0 && received >= effectiveTotal;
              final elapsedMs =
                  lastEmitTime == null
                      ? _progressThrottleMs
                      : now.difference(lastEmitTime!).inMilliseconds;
              if (elapsedMs >= _progressThrottleMs || isDone) {
                lastEmitTime = now;
                onProgress(
                  TvUpdateDownloadProgress(
                    stage: TvUpdateDownloadStage.downloading,
                    receivedBytes: received,
                    totalBytes: effectiveTotal,
                    bytesPerSecond: speed,
                    activeSourceLabel: candidate.label,
                    message: '正在通过 ${candidate.label} 下载...',
                  ),
                );
              }
            },
          );

          _throwIfCancelled(cancelToken, candidate.url);

          final downloadedSize = await partial.exists() ? await partial.length() : 0;
          onProgress(
            TvUpdateDownloadProgress(
              stage: TvUpdateDownloadStage.verifying,
              receivedBytes: downloadedSize,
              totalBytes: asset.size > 0 ? asset.size : downloadedSize,
              bytesPerSecond: 0,
              activeSourceLabel: candidate.label,
              message: '正在校验安装包完整性...',
            ),
          );

          await _verifyDownloadedFile(partial, asset);
          _throwIfCancelled(cancelToken, candidate.url);

          await _moveFileAtomically(partial, targetFile);
          final finalSize = await targetFile.length();

          onProgress(
            TvUpdateDownloadProgress(
              stage: TvUpdateDownloadStage.completed,
              receivedBytes: finalSize,
              totalBytes: finalSize,
              bytesPerSecond: 0,
              activeSourceLabel: candidate.label,
              message: '下载完成',
            ),
          );
          return targetFile.path;
        } catch (e) {
          if (_isCancelledError(e, cancelToken)) {
            rethrow;
          }
          if (e is _TvUpdateIntegrityException) {
            rethrow;
          }
          if (e is FileSystemException) {
            throw _wrapFileSystemError(e);
          }

          lastError = e;
          KazumiLogger().w(
            'TvUpdate: download failed from ${candidate.label}',
            error: e,
          );

          if (i + 1 < candidates.length) {
            final next = candidates[i + 1];
            onProgress(
              TvUpdateDownloadProgress(
                stage: TvUpdateDownloadStage.switchingMirror,
                receivedBytes: 0,
                totalBytes: asset.size,
                bytesPerSecond: 0,
                activeSourceLabel: next.label,
                message: '当前源不可用，正在切换至 ${next.label}...',
              ),
            );
          }
        }
      }

      throw _wrapDownloadError(lastError);
    } finally {
      try {
        if (await downloadDir.exists()) {
          await downloadDir.delete(recursive: true);
        }
      } catch (e) {
        KazumiLogger().w('TvUpdate: temp download cleanup failed', error: e);
      }
    }
  }

  Future<TvUpdateInstallResult> installApk(String filePath) async {
    final trimmed = filePath.trim();
    if (trimmed.isEmpty || !await File(trimmed).exists()) {
      return const TvUpdateInstallResult(
        outcome: TvUpdateInstallOutcome.failed,
        message: '安装包文件不存在，请重新下载',
      );
    }

    final canInstall = await _installPermissionChecker();
    if (!canInstall) {
      return const TvUpdateInstallResult(
        outcome: TvUpdateInstallOutcome.permissionRequired,
        message: '需要开启“允许安装未知应用”权限后才能安装更新',
      );
    }

    try {
      final result = await _apkOpener(trimmed);
      if (result.type == ResultType.done) {
        return const TvUpdateInstallResult(
          outcome: TvUpdateInstallOutcome.launched,
          message: '已拉起系统安装界面',
        );
      }
      if (result.type == ResultType.permissionDenied) {
        return TvUpdateInstallResult(
          outcome: TvUpdateInstallOutcome.permissionRequired,
          message:
              result.message.isNotEmpty
                  ? result.message
                  : '缺少安装权限，请授予“允许安装未知应用”权限',
        );
      }
      return TvUpdateInstallResult(
        outcome: TvUpdateInstallOutcome.failed,
        message:
            result.message.isNotEmpty ? result.message : '无法打开安装包文件',
      );
    } catch (e) {
      KazumiLogger().e('TvUpdate: launch installer failed', error: e);
      return TvUpdateInstallResult(
        outcome: TvUpdateInstallOutcome.failed,
        message: '启动安装程序失败: $e',
      );
    }
  }

  Future<int> cleanupCachedApks({String? keepFilePath}) async {
    final tempDir = await _tempDirProvider();
    if (!await tempDir.exists()) {
      return 0;
    }
    final normalizedKeep =
        keepFilePath == null || keepFilePath.trim().isEmpty
            ? null
            : p.normalize(File(keepFilePath).absolute.path);

    var deletedCount = 0;
    await for (final entity in tempDir.list(followLinks: false)) {
      final baseName = p.basename(entity.path);
      if (entity is File &&
          baseName.startsWith('kazumi-tv-update-') &&
          baseName.endsWith('.apk')) {
        if (normalizedKeep != null &&
            p.normalize(entity.absolute.path) == normalizedKeep) {
          continue;
        }
        try {
          await entity.delete();
          deletedCount++;
        } catch (e) {
          KazumiLogger().w('TvUpdate: failed to delete cached APK', error: e);
        }
      } else if (entity is Directory &&
          baseName.startsWith('kazumi-update-')) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          KazumiLogger().w('TvUpdate: failed to delete temp dir', error: e);
        }
      }
    }
    return deletedCount;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _resolveRepo(String? repoOverride) {
    if (repoOverride == null || repoOverride.trim().isEmpty) {
      return TvUpdateConfig.activeRepo;
    }
    final normalized = TvUpdateConfig.normalizeRepo(repoOverride);
    if (normalized == null) {
      throw const TvUpdateException('更新仓库格式无效，请输入 owner/repo 或 GitHub 仓库地址');
    }
    return normalized;
  }

  String _cachedApkPath(Directory tempDir, String version, String abi) {
    final safeVersion = _sanitizeFileNamePart(
      TvVersionComparator.normalizeVersion(version),
    );
    final safeAbi = _sanitizeFileNamePart(abi.trim());
    return '${tempDir.path}/kazumi-tv-update-$safeVersion-$safeAbi.apk';
  }

  String _sanitizeFileNamePart(String value) {
    return value.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  }

  Future<bool> _isCachedFileValid(File file, TvUpdateApkAsset asset) async {
    try {
      await _verifyDownloadedFile(file, asset);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _verifyDownloadedFile(File file, TvUpdateApkAsset asset) async {
    if (!await file.exists()) {
      throw const _TvUpdateIntegrityException('下载文件不存在');
    }
    final length = await file.length();
    if (length <= 0) {
      throw const _TvUpdateIntegrityException('下载文件为空，可能被网络中断');
    }

    if (asset.hasValidSha256) {
      final digest = await sha256.bind(file.openRead()).first;
      final actual = digest.toString().toLowerCase();
      final expected = asset.sha256.toLowerCase();
      if (actual != expected) {
        throw _TvUpdateIntegrityException(
          '安装包 SHA256 校验失败（期望 $expected，实际 $actual）',
        );
      }
      return;
    }

    if (!await _hasApkMagicBytes(file)) {
      throw const _TvUpdateIntegrityException('下载文件不是有效的 APK 安装包');
    }
    if (asset.size > 0 && length != asset.size) {
      throw _TvUpdateIntegrityException(
        '安装包大小不匹配（期望 ${asset.size} 字节，实际 $length 字节）',
      );
    }
  }

  Future<bool> _hasApkMagicBytes(File file) async {
    final header = <int>[];
    await for (final chunk in file.openRead(0, 4)) {
      header.addAll(chunk);
      if (header.length >= 4) {
        break;
      }
    }
    if (header.length < _apkMagicBytes.length) {
      return false;
    }
    for (var i = 0; i < _apkMagicBytes.length; i++) {
      if (header[i] != _apkMagicBytes[i]) {
        return false;
      }
    }
    return true;
  }

  Future<void> _moveFileAtomically(File source, File destination) async {
    if (!await destination.parent.exists()) {
      await destination.parent.create(recursive: true);
    }
    if (await destination.exists()) {
      await destination.delete();
    }
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      await source.copy(destination.path);
      if (await source.exists()) {
        await source.delete();
      }
    }
  }

  bool _isCancelledError(Object error, CancelToken? cancelToken) {
    if (cancelToken?.isCancelled ?? false) {
      return true;
    }
    if (error is NetworkException && error.type == NetworkExceptionType.cancel) {
      return true;
    }
    if (error is DioException && error.type == DioExceptionType.cancel) {
      return true;
    }
    return false;
  }

  void _throwIfCancelled(CancelToken? cancelToken, String path) {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw cancelToken.cancelError ??
          DioException.requestCancelled(
            requestOptions: RequestOptions(path: path),
            reason: 'cancelled',
          );
    }
  }

  TvUpdateException _wrapCheckError(Object? error) {
    if (error is TvUpdateException) {
      return error;
    }
    if (error is NetworkException) {
      final status = error.statusCode;
      if (status == 404) {
        return TvUpdateException(
          '未找到仓库或发布版本（404），请检查更新仓库配置',
          cause: error,
        );
      }
      if (status == 403 || status == 429) {
        return TvUpdateException(
          'GitHub 请求受限（$status），请切换加速镜像或稍后重试',
          cause: error,
        );
      }
      return TvUpdateException('检查更新失败：${error.message}', cause: error);
    }
    return TvUpdateException('检查更新失败，请检查网络连接或镜像设置', cause: error);
  }

  TvUpdateException _wrapFileSystemError(FileSystemException error) {
    final code = error.osError?.errorCode;
    final isWindows = Platform.isWindows;
    if (isWindows ? code == 112 || code == 39 : code == 28) {
      return TvUpdateException('磁盘空间不足，请清理后重试', cause: error);
    }
    if (isWindows ? code == 5 : code == 1 || code == 13) {
      return TvUpdateException('无法写入临时目录，请检查存储权限', cause: error);
    }
    return TvUpdateException('安装包文件读写失败', cause: error);
  }

  TvUpdateException _wrapDownloadError(Object? error) {
    if (error is TvUpdateException) {
      return error;
    }
    if (error is NetworkException) {
      return switch (error.type) {
        NetworkExceptionType.connectionTimeout ||
        NetworkExceptionType.receiveTimeout ||
        NetworkExceptionType.sendTimeout =>
          TvUpdateException('下载超时，所有镜像源均未响应', cause: error),
        _ => TvUpdateException('下载失败：${error.message}', cause: error),
      };
    }
    return TvUpdateException('下载失败，所有镜像源均不可用', cause: error);
  }
}

class _SmoothedSpeedTracker {
  DateTime? _lastSampleTime;
  int _lastSampleBytes = 0;
  double _smoothedSpeed = 0;

  double update(int receivedBytes, DateTime now) {
    if (_lastSampleTime == null) {
      _lastSampleTime = now;
      _lastSampleBytes = receivedBytes;
      return 0;
    }
    final elapsedMs = now.difference(_lastSampleTime!).inMilliseconds;
    if (elapsedMs < 150) {
      return _smoothedSpeed;
    }
    final deltaBytes = receivedBytes - _lastSampleBytes;
    if (deltaBytes >= 0 && elapsedMs > 0) {
      final instant = deltaBytes / (elapsedMs / 1000.0);
      _smoothedSpeed =
          _smoothedSpeed <= 0 ? instant : (_smoothedSpeed * 0.65 + instant * 0.35);
    }
    _lastSampleTime = now;
    _lastSampleBytes = receivedBytes;
    return _smoothedSpeed;
  }
}
