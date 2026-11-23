import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/update/tv_update_models.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';
import 'package:kazumi/tv/utils/tv_platform_channel.dart';
import 'package:logger/logger.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.basePath);

  final String basePath;

  @override
  Future<String?> getApplicationSupportPath() async => basePath;

  @override
  Future<String?> getTemporaryPath() async => basePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late PathProviderPlatform originalPaths;

  setUpAll(() async {
    Logger.level = Level.off;
    hiveDir = await Directory.systemTemp.createTemp('kazumi_tv_update_hive_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(hiveDir.path);
    Hive.init(hiveDir.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.resetSettings(SettingsKeys.byGroup(SettingGroup.update));
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    if (await hiveDir.exists()) {
      await hiveDir.delete(recursive: true);
    }
  });

  group('SettingsKeys update registration', () {
    test('registers all TV update settings under SettingGroup.update', () {
      final updateKeys = SettingsKeys.byGroup(SettingGroup.update);
      expect(
        updateKeys,
        containsAll([
          SettingsKeys.autoUpdate,
          SettingsKeys.tvUpdateRepo,
          SettingsKeys.tvUpdateMirror,
          SettingsKeys.tvUpdateCustomMirrorUrl,
          SettingsKeys.tvIgnoredUpdateVersion,
        ]),
      );
      expect(SettingsKeys.autoUpdate.defaultValue, isTrue);
      expect(SettingsKeys.tvUpdateRepo.defaultValue, '');
      expect(SettingsKeys.tvUpdateMirror.defaultValue, 'ghProxy');
      expect(SettingsKeys.tvUpdateCustomMirrorUrl.defaultValue, '');
      expect(SettingsKeys.tvIgnoredUpdateVersion.defaultValue, '');
    });
  });

  group('TvPlatformChannel off-Android defaults', () {
    test('returns safe defaults on non-Android hosts', () async {
      if (Platform.isAndroid) {
        return;
      }
      expect(
        await TvPlatformChannel.getSupportedAbis(),
        const ['arm64-v8a', 'armeabi-v7a'],
      );
      expect(await TvPlatformChannel.getAppVersionInfo(), isNull);
      expect(await TvPlatformChannel.canRequestPackageInstalls(), isTrue);
      expect(await TvPlatformChannel.openInstallPermissionSettings(), isFalse);
    });
  });

  group('TvUpdateConfig & normalization', () {
    test('normalizes owner/repo and GitHub URLs', () {
      expect(
        TvUpdateConfig.normalizeRepo('loong486/kazumi-tv'),
        'loong486/kazumi-tv',
      );
      expect(
        TvUpdateConfig.normalizeRepo('  loong486/kazumi-tv  '),
        'loong486/kazumi-tv',
      );
      expect(
        TvUpdateConfig.normalizeRepo('https://github.com/loong486/kazumi-tv'),
        'loong486/kazumi-tv',
      );
      expect(
        TvUpdateConfig.normalizeRepo(
          'https://github.com/loong486/kazumi-tv.git/',
        ),
        'loong486/kazumi-tv',
      );
      expect(
        TvUpdateConfig.normalizeRepo('http://github.com/loong486/kazumi-tv'),
        'loong486/kazumi-tv',
      );

      expect(TvUpdateConfig.normalizeRepo(''), isNull);
      expect(TvUpdateConfig.normalizeRepo('invalid'), isNull);
      expect(TvUpdateConfig.normalizeRepo('a/b/c'), isNull);
      expect(TvUpdateConfig.normalizeRepo('https://gitlab.com/a/b'), isNull);
      expect(
        TvUpdateConfig.normalizeRepo('https://github.com/a/b/releases'),
        isNull,
      );
      expect(TvUpdateConfig.normalizeRepo('https://github.com/only'), isNull);
    });

    test('normalizes custom mirror prefixes', () {
      expect(
        TvUpdateConfig.normalizeMirrorPrefix('https://gh-proxy.org'),
        'https://gh-proxy.org/',
      );
      expect(
        TvUpdateConfig.normalizeMirrorPrefix('  https://mirror.example.com/gh///  '),
        'https://mirror.example.com/gh/',
      );
      expect(
        TvUpdateConfig.normalizeMirrorPrefix('http://192.168.1.2:8080/proxy'),
        'http://192.168.1.2:8080/proxy/',
      );

      expect(TvUpdateConfig.normalizeMirrorPrefix(''), isNull);
      expect(TvUpdateConfig.normalizeMirrorPrefix('gh-proxy.org'), isNull);
      expect(TvUpdateConfig.normalizeMirrorPrefix('ftp://mirror.com/'), isNull);
      expect(
        TvUpdateConfig.normalizeMirrorPrefix('https://mirror.com/?q=1'),
        isNull,
      );
    });

    test('persists and reads config settings via GStorage', () async {
      expect(TvUpdateConfig.activeRepo, 'loong486/kazumi-tv');
      expect(TvUpdateConfig.activeMirrorMode, TvUpdateMirrorMode.ghProxy);

      await GStorage.putSetting(
        SettingsKeys.tvUpdateRepo,
        'https://github.com/example/kazumi-fork.git',
      );
      await GStorage.putSetting(SettingsKeys.tvUpdateMirror, 'ghfast');
      await GStorage.putSetting(
        SettingsKeys.tvUpdateCustomMirrorUrl,
        'https://proxy.example.com/p',
      );
      await TvUpdateConfig.setIgnoredVersion('v2.4.7');

      expect(TvUpdateConfig.activeRepo, 'example/kazumi-fork');
      expect(TvUpdateConfig.activeMirrorMode, TvUpdateMirrorMode.ghfast);
      expect(TvUpdateConfig.customMirrorUrl, 'https://proxy.example.com/p/');
      expect(TvUpdateConfig.ignoredVersion, '2.4.7');
      expect(
        TvUpdateMirrorMode.fromStorage('unknown'),
        TvUpdateMirrorMode.ghProxy,
      );
    });
  });

  group('TvUpdateMirrorRewriter', () {
    const githubReleaseUrl =
        'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk';

    test('builds ordered deduplicated fallback chains for each mirror mode', () {
      final ghProxy = TvUpdateMirrorRewriter.buildCandidateUrls(
        githubReleaseUrl,
        preferredMode: TvUpdateMirrorMode.ghProxy,
      );
      expect(ghProxy.map((e) => e.label).toList(), [
        'gh-proxy',
        'ghfast',
        '直连 GitHub',
      ]);
      expect(ghProxy[0].url, 'https://gh-proxy.org/$githubReleaseUrl');
      expect(ghProxy[1].url, 'https://ghfast.top/$githubReleaseUrl');
      expect(ghProxy[2].url, githubReleaseUrl);

      final ghfast = TvUpdateMirrorRewriter.buildCandidateUrls(
        githubReleaseUrl,
        preferredMode: TvUpdateMirrorMode.ghfast,
      );
      expect(ghfast.map((e) => e.label).toList(), [
        'ghfast',
        'gh-proxy',
        '直连 GitHub',
      ]);

      final custom = TvUpdateMirrorRewriter.buildCandidateUrls(
        githubReleaseUrl,
        preferredMode: TvUpdateMirrorMode.custom,
        customMirrorPrefix: 'https://my-proxy.example.com/gh',
      );
      expect(custom.map((e) => e.label).toList(), [
        '自定义镜像',
        'gh-proxy',
        '直连 GitHub',
      ]);
      expect(
        custom[0].url,
        'https://my-proxy.example.com/gh/$githubReleaseUrl',
      );

      final deduplicatedCustom = TvUpdateMirrorRewriter.buildCandidateUrls(
        githubReleaseUrl,
        preferredMode: TvUpdateMirrorMode.custom,
        customMirrorPrefix: 'https://gh-proxy.org/',
      );
      expect(deduplicatedCustom.map((e) => e.url).toSet().length, 2);
      expect(deduplicatedCustom.map((e) => e.label).toList(), [
        '自定义镜像',
        '直连 GitHub',
      ]);

      final direct = TvUpdateMirrorRewriter.buildCandidateUrls(
        githubReleaseUrl,
        preferredMode: TvUpdateMirrorMode.direct,
      );
      expect(direct.map((e) => e.label).toList(), [
        '直连 GitHub',
        'gh-proxy',
      ]);
      expect(direct[0].url, githubReleaseUrl);
      expect(direct[1].url, 'https://gh-proxy.org/$githubReleaseUrl');
    });

    test('wraps supported GitHub asset hosts and excludes api.github.com', () {
      for (final host in [
        'github.com',
        'objects.githubusercontent.com',
        'release-assets.githubusercontent.com',
        'raw.githubusercontent.com',
      ]) {
        final candidates = TvUpdateMirrorRewriter.buildCandidateUrls(
          'https://$host/some/path',
          preferredMode: TvUpdateMirrorMode.ghProxy,
        );
        expect(candidates.first.url, 'https://gh-proxy.org/https://$host/some/path');
      }

      final apiCandidates = TvUpdateMirrorRewriter.buildCandidateUrls(
        'https://api.github.com/repos/loong486/kazumi-tv/releases/latest',
        preferredMode: TvUpdateMirrorMode.ghProxy,
      );
      expect(apiCandidates, hasLength(1));
      expect(apiCandidates.single.label, '直连 GitHub');
      expect(
        apiCandidates.single.url,
        'https://api.github.com/repos/loong486/kazumi-tv/releases/latest',
      );
    });

    test('never double-wraps already wrapped URLs or non-GitHub hosts', () {
      const preWrapped =
          'https://gh-proxy.org/https://github.com/loong486/kazumi-tv/releases/latest/download/latest.json';
      final wrappedResult = TvUpdateMirrorRewriter.buildCandidateUrls(
        preWrapped,
        preferredMode: TvUpdateMirrorMode.ghfast,
      );
      expect(wrappedResult, hasLength(1));
      expect(wrappedResult.single.url, preWrapped);
      expect(wrappedResult.single.label, 'gh-proxy');

      const otherHost = 'https://cdn.example.com/KazumiTV.apk';
      final otherResult = TvUpdateMirrorRewriter.buildCandidateUrls(
        otherHost,
        preferredMode: TvUpdateMirrorMode.ghProxy,
      );
      expect(otherResult, hasLength(1));
      expect(otherResult.single.url, otherHost);
      expect(otherResult.single.label, '直连 GitHub');
    });
  });

  group('TvVersionComparator', () {
    test('normalizes leading v/V and whitespace', () {
      expect(TvVersionComparator.normalizeVersion('  v2.4.7  '), '2.4.7');
      expect(TvVersionComparator.normalizeVersion('V2.4.7-beta.1'), '2.4.7-beta.1');
    });

    test('compares standard semantic versions and prereleases', () {
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.6',
          remoteVersion: 'v2.4.7',
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: 'v2.4.7',
        ),
        isFalse,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.8',
          remoteVersion: '2.4.7',
        ),
        isFalse,
      );

      // Stable > prerelease for same major.minor.patch
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7-beta.1',
          remoteVersion: '2.4.7',
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7-beta.1',
        ),
        isFalse,
      );

      // Numeric + string prerelease identifiers
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7-alpha.2',
          remoteVersion: '2.4.7-alpha.10',
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7-beta',
          remoteVersion: '2.4.7-beta.1',
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7-beta.1',
          remoteVersion: '2.4.7-rc.1',
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7-1',
          remoteVersion: '2.4.7-alpha',
        ),
        isTrue,
      );
    });

    test('handles split-ABI versionCode tie-breaking without throwing', () {
      // Exact same split-ABI build
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7',
          localVersionCode: 204072,
          remoteVersionCode: 20407,
          remoteAssetVersionCode: 204072,
        ),
        isFalse,
      );

      // Bumped rebuild on same version name
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7',
          localVersionCode: 204072,
          remoteVersionCode: 20408,
          remoteAssetVersionCode: 204082,
        ),
        isTrue,
      );

      // Unsplit/universal local build with matching base versionCode
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7',
          localVersionCode: 20407,
          remoteVersionCode: 20407,
          remoteAssetVersionCode: 204072,
        ),
        isFalse,
      );

      // Split-ABI local vs unsplit remote release versionCode only
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7',
          localVersionCode: 204072,
          remoteVersionCode: 20408,
        ),
        isTrue,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.7',
          remoteVersion: '2.4.7',
          localVersionCode: 204072,
          remoteVersionCode: 20407,
        ),
        isFalse,
      );

      // Malformed inputs must never throw FormatException
      expect(
        TvVersionComparator.isNewer(
          localVersion: '2.4.6',
          remoteVersion: 'not-a-version',
        ),
        isFalse,
      );
      expect(
        TvVersionComparator.isNewer(
          localVersion: 'unknown',
          remoteVersion: '2.4.7rc1',
        ),
        isTrue,
      );
    });
  });

  group('TvUpdateParser & ABI selection', () {
    test('parses latest.json manifest and selects best ABI', () {
      final shaArm64 = 'a' * 64;
      final shaV7a = 'b' * 64;
      final release = TvUpdateParser.parseManifestJson(
        {
          'schemaVersion': 1,
          'version': '2.4.7',
          'versionCode': 20407,
          'tag': 'v2.4.7',
          'publishedAt': '2026-11-23T08:00:00Z',
          'changelog': 'Fix focus & add updater',
          'force': true,
          'releaseUrl': 'https://github.com/loong486/kazumi-tv/releases/tag/v2.4.7',
          'apks': {
            'arm64-v8a': {
              'fileName': 'KazumiTV_2.4.7_arm64-v8a.apk',
              'url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
              'sha256': shaArm64,
              'size': 30450923,
              'versionCode': 204072,
            },
            'armeabi-v7a': {
              'fileName': 'KazumiTV_2.4.7_armeabi-v7a.apk',
              'url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_armeabi-v7a.apk',
              'sha256': shaV7a,
              'size': 29109411,
              'versionCode': 204071,
            },
          },
        },
        repo: 'loong486/kazumi-tv',
        sourceLabel: 'gh-proxy',
      );

      expect(release.version, '2.4.7');
      expect(release.tag, 'v2.4.7');
      expect(release.versionCode, 20407);
      expect(release.force, isTrue);
      expect(release.sourceLabel, 'gh-proxy');
      expect(
        release.selectAssetForAbis(['arm64-v8a', 'armeabi-v7a'])?.abi,
        'arm64-v8a',
      );
      expect(
        release.selectAssetForAbis(['armeabi-v7a'])?.abi,
        'armeabi-v7a',
      );
      expect(release.selectAssetForAbis(['x86_64']), isNull);
    });

    test('parses GitHub release API fallback JSON', () {
      final sha = 'c' * 64;
      final release = TvUpdateParser.parseGithubReleaseJson(
        {
          'tag_name': 'v2.4.8',
          'body': 'Release notes',
          'published_at': '2026-11-24T10:00:00Z',
          'html_url': 'https://github.com/loong486/kazumi-tv/releases/tag/v2.4.8',
          'assets': [
            {
              'name': 'latest.json',
              'browser_download_url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.8/latest.json',
              'size': 500,
            },
            {
              'name': 'KazumiTV_2.4.8_x86.apk',
              'browser_download_url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.8/KazumiTV_2.4.8_x86.apk',
              'size': 20000000,
            },
            {
              'name': 'KazumiTV_2.4.8_arm64-v8a.apk',
              'browser_download_url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.8/KazumiTV_2.4.8_arm64-v8a.apk',
              'digest': 'sha256:$sha',
              'size': 30000000,
            },
            {
              'name': 'KazumiTV_2.4.8_universal.apk',
              'browser_download_url':
                  'https://github.com/loong486/kazumi-tv/releases/download/v2.4.8/KazumiTV_2.4.8_universal.apk',
              'size': 50000000,
            },
          ],
        },
        sourceLabel: '直连 GitHub',
      );

      expect(release.version, '2.4.8');
      expect(release.apks.keys, containsAll(['arm64-v8a', 'universal']));
      expect(release.apks['arm64-v8a']?.sha256, sha);
      expect(release.selectAssetForAbis(['x86_64'])?.abi, 'universal');
    });
  });

  group('TvUpdateService.checkForUpdates', () {
    test('fetches latest.json with 12s timeout and mirror fallback', () async {
      final requestedUrls = <String>[];
      Duration? capturedTimeout;

      final manifestJson = jsonEncode({
        'schemaVersion': 1,
        'version': '2.4.7',
        'versionCode': 20407,
        'tag': 'v2.4.7',
        'changelog': 'Updated',
        'force': false,
        'apks': {
          'arm64-v8a': {
            'fileName': 'KazumiTV_2.4.7_arm64-v8a.apk',
            'url':
                'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
            'sha256': 'd' * 64,
            'size': 1024,
            'versionCode': 204072,
          },
        },
      });

      final service = TvUpdateService(
        plainGetter: (url, {headers = const {}, receiveTimeout, cancelToken}) async {
          requestedUrls.add(url);
          capturedTimeout = receiveTimeout;
          if (url.startsWith('https://gh-proxy.org/')) {
            throw const NetworkException(
              type: NetworkExceptionType.receiveTimeout,
              message: 'timeout',
            );
          }
          return manifestJson;
        },
        abiProvider: () async => ['arm64-v8a', 'armeabi-v7a'],
        versionInfoProvider: () async =>
            const TvAppVersionInfo(versionName: '2.4.6', versionCode: 204062),
      );

      final result = await service.checkForUpdates(
        mirrorOverride: TvUpdateMirrorMode.ghProxy,
      );

      expect(capturedTimeout, const Duration(seconds: 12));
      expect(requestedUrls, [
        'https://gh-proxy.org/https://github.com/loong486/kazumi-tv/releases/latest/download/latest.json',
        'https://ghfast.top/https://github.com/loong486/kazumi-tv/releases/latest/download/latest.json',
      ]);
      expect(result.status, TvUpdateCheckStatus.updateAvailable);
      expect(result.hasUpdate, isTrue);
      expect(result.matchedAsset?.abi, 'arm64-v8a');
      expect(result.release?.sourceLabel, 'ghfast');
    });

    test('falls back to GitHub API when all manifest attempts fail', () async {
      final calls = <({String url, Map<String, dynamic> headers})>[];
      final apiResponse = jsonEncode({
        'tag_name': 'v2.4.8',
        'body': 'From GitHub API',
        'published_at': '2026-11-24T00:00:00Z',
        'html_url': 'https://github.com/loong486/kazumi-tv/releases/tag/v2.4.8',
        'assets': [
          {
            'name': 'KazumiTV_2.4.8_armeabi-v7a.apk',
            'browser_download_url':
                'https://github.com/loong486/kazumi-tv/releases/download/v2.4.8/KazumiTV_2.4.8_armeabi-v7a.apk',
            'digest': 'sha256:${'e' * 64}',
            'size': 2000,
          },
        ],
      });

      final service = TvUpdateService(
        plainGetter: (url, {headers = const {}, receiveTimeout, cancelToken}) async {
          calls.add((url: url, headers: headers));
          if (url.contains('latest.json')) {
            throw const NetworkException(
              type: NetworkExceptionType.badResponse,
              statusCode: 404,
              message: 'not found',
            );
          }
          return apiResponse;
        },
        abiProvider: () async => ['arm64-v8a'],
        versionInfoProvider: () async =>
            const TvAppVersionInfo(versionName: '2.4.6', versionCode: 204062),
      );

      final result = await service.checkForUpdates(
        mirrorOverride: TvUpdateMirrorMode.ghProxy,
      );

      expect(calls.length, 4);
      expect(
        calls.last.url,
        'https://api.github.com/repos/loong486/kazumi-tv/releases/latest',
      );
      expect(calls.last.headers['Accept'], 'application/vnd.github+json');
      expect(result.status, TvUpdateCheckStatus.incompatibleAbi);
      expect(result.hasUpdate, isFalse);
      expect(result.matchedAsset, isNull);
    });

    test('returns upToDate and respects cancellation without fallback', () async {
      final token = CancelToken()..cancel('user aborted');
      var callCount = 0;

      final service = TvUpdateService(
        plainGetter: (url, {headers = const {}, receiveTimeout, cancelToken}) async {
          callCount++;
          return '{}';
        },
        abiProvider: () async => ['arm64-v8a'],
        versionInfoProvider: () async =>
            const TvAppVersionInfo(versionName: '2.4.7', versionCode: 204072),
      );

      await expectLater(
        service.checkForUpdates(cancelToken: token),
        throwsA(isA<DioException>()),
      );
      expect(callCount, 0);
    });

    test('falls back across mirrors when manifest JSON is malformed or missing fields', () async {
      final requestedUrls = <String>[];
      final validManifest = jsonEncode({
        'schemaVersion': 1,
        'version': '2.4.7',
        'versionCode': 20407,
        'tag': 'v2.4.7',
        'apks': {
          'arm64-v8a': {
            'fileName': 'KazumiTV_2.4.7_arm64-v8a.apk',
            'url':
                'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
            'sha256': 'a' * 64,
            'size': 1024,
            'versionCode': 204072,
          },
        },
      });

      final service = TvUpdateService(
        plainGetter: (url, {headers = const {}, receiveTimeout, cancelToken}) async {
          requestedUrls.add(url);
          if (url.startsWith('https://gh-proxy.org/')) {
            return '{"schemaVersion":1}'; // missing version & apks
          }
          return validManifest;
        },
        abiProvider: () async => ['arm64-v8a'],
        versionInfoProvider: () async =>
            const TvAppVersionInfo(versionName: '2.4.6', versionCode: 204062),
      );

      final result = await service.checkForUpdates(
        mirrorOverride: TvUpdateMirrorMode.ghProxy,
      );
      expect(requestedUrls.length, 2);
      expect(result.hasUpdate, isTrue);
      expect(result.release?.sourceLabel, 'ghfast');
    });

    test('rejects invalid repoOverride', () async {
      final service = TvUpdateService(
        plainGetter: (url, {headers = const {}, receiveTimeout, cancelToken}) async => '{}',
      );
      await expectLater(
        service.checkForUpdates(repoOverride: 'not-a-repo'),
        throwsA(isA<TvUpdateException>()),
      );
    });
  });

  group('TvUpdateService.downloadApk, installApk, cleanupCachedApks', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kazumi_tv_dl_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    TvUpdateRelease makeRelease(TvUpdateApkAsset asset) {
      return TvUpdateRelease(
        version: '2.4.7',
        tag: 'v2.4.7',
        versionCode: 20407,
        apks: {asset.abi: asset},
        sourceLabel: 'gh-proxy',
      );
    }

    test('throws TvUpdateException when available storage is insufficient', () async {
      const asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        size: 50 * 1024 * 1024, // 2.5x = 125 MB > 80 MB
      );
      var downloaded = false;

      final service = TvUpdateService(
        availableStorageProvider: (_) async => 100 * 1024 * 1024,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          downloaded = true;
        },
      );

      await expectLater(
        service.downloadApk(
          release: makeRelease(asset),
          asset: asset,
          cancelToken: CancelToken(),
          onProgress: (_) {},
        ),
        throwsA(isA<TvUpdateException>()),
      );
      expect(downloaded, isFalse);
    });

    test('downloads, verifies streaming SHA256, and cleans up temp dir', () async {
      final payload = utf8.encode('PK\x03\x04-valid-apk-payload-for-streaming-hash');
      final expectedHash = sha256.convert(payload).toString();
      final asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: expectedHash,
        size: payload.length,
      );
      final stages = <TvUpdateDownloadStage>[];

      final service = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          onReceiveProgress?.call(payload.length ~/ 2, payload.length);
          await File(savePath).writeAsBytes(payload, flush: true);
          onReceiveProgress?.call(payload.length, payload.length);
        },
      );

      final path = await service.downloadApk(
        release: makeRelease(asset),
        asset: asset,
        mirrorOverride: TvUpdateMirrorMode.ghProxy,
        cancelToken: CancelToken(),
        onProgress: (p) => stages.add(p.stage),
      );

      expect(path, '${tempDir.path}/kazumi-tv-update-2.4.7-arm64-v8a.apk');
      expect(await File(path).readAsBytes(), payload);
      expect(stages, containsAll([
        TvUpdateDownloadStage.preparing,
        TvUpdateDownloadStage.downloading,
        TvUpdateDownloadStage.verifying,
        TvUpdateDownloadStage.completed,
      ]));
      final remainingTempDirs = await tempDir
          .list()
          .where((e) => e is Directory && e.path.contains('kazumi-update-'))
          .toList();
      expect(remainingTempDirs, isEmpty);
    });

    test('fails immediately on SHA256 mismatch without switching mirrors', () async {
      final payload = utf8.encode('corrupted-payload');
      final asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: 'f' * 64,
        size: payload.length,
      );
      var downloadAttempts = 0;

      final service = TvUpdateService(
        availableStorageProvider: (_) async => 500 * 1024 * 1024,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          downloadAttempts++;
          await File(savePath).writeAsBytes(payload, flush: true);
        },
      );

      await expectLater(
        service.downloadApk(
          release: makeRelease(asset),
          asset: asset,
          mirrorOverride: TvUpdateMirrorMode.ghProxy,
          cancelToken: CancelToken(),
          onProgress: (_) {},
        ),
        throwsA(isA<TvUpdateException>()),
      );

      expect(downloadAttempts, 1);
      expect(
        await File('${tempDir.path}/kazumi-tv-update-2.4.7-arm64-v8a.apk').exists(),
        isFalse,
      );
    });

    test('verifies ZIP magic bytes and size when SHA256 is absent', () async {
      const asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: '',
        size: 8,
      );

      final badMagicService = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          await File(savePath).writeAsBytes(utf8.encode('<html>no'), flush: true);
        },
      );

      await expectLater(
        badMagicService.downloadApk(
          release: makeRelease(asset),
          asset: asset,
          cancelToken: CancelToken(),
          onProgress: (_) {},
        ),
        throwsA(isA<TvUpdateException>()),
      );

      final validZipPayload = <int>[0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4];
      final validService = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          await File(savePath).writeAsBytes(validZipPayload, flush: true);
        },
      );

      final savedPath = await validService.downloadApk(
        release: makeRelease(asset),
        asset: asset,
        cancelToken: CancelToken(),
        onProgress: (_) {},
      );
      expect(await File(savedPath).readAsBytes(), validZipPayload);
    });

    test('reuses valid cached APK and re-downloads corrupted cache', () async {
      final validPayload = utf8.encode('cached-valid-apk-bytes');
      final validSha = sha256.convert(validPayload).toString();
      final asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: validSha,
        size: validPayload.length,
      );
      final cachedFile = File(
        '${tempDir.path}/kazumi-tv-update-2.4.7-arm64-v8a.apk',
      );
      await cachedFile.writeAsBytes(validPayload, flush: true);

      var downloadCalls = 0;
      final service = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          downloadCalls++;
          await File(savePath).writeAsBytes(validPayload, flush: true);
        },
      );

      final reusedPath = await service.downloadApk(
        release: makeRelease(asset),
        asset: asset,
        cancelToken: CancelToken(),
        onProgress: (_) {},
      );
      expect(reusedPath, cachedFile.path);
      expect(downloadCalls, 0);

      // Corrupt cached file -> must delete and re-download
      await cachedFile.writeAsBytes(utf8.encode('corrupted'), flush: true);
      final refreshedPath = await service.downloadApk(
        release: makeRelease(asset),
        asset: asset,
        cancelToken: CancelToken(),
        onProgress: (_) {},
      );
      expect(refreshedPath, cachedFile.path);
      expect(downloadCalls, 1);
      expect(await cachedFile.readAsBytes(), validPayload);
    });

    test('switches mirror on network failure and updates activeSourceLabel', () async {
      final payload = utf8.encode('mirror-failover-apk');
      final sha = sha256.convert(payload).toString();
      final asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: sha,
        size: payload.length,
      );
      final attemptedUrls = <String>[];
      final events = <TvUpdateDownloadProgress>[];

      final service = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          attemptedUrls.add(url);
          if (url.startsWith('https://gh-proxy.org/')) {
            throw const NetworkException(
              type: NetworkExceptionType.connectionError,
              message: 'mirror down',
            );
          }
          await File(savePath).writeAsBytes(payload, flush: true);
        },
      );

      await service.downloadApk(
        release: makeRelease(asset),
        asset: asset,
        mirrorOverride: TvUpdateMirrorMode.ghProxy,
        cancelToken: CancelToken(),
        onProgress: events.add,
      );

      expect(attemptedUrls, [
        'https://gh-proxy.org/${asset.rawDownloadUrl}',
        'https://ghfast.top/${asset.rawDownloadUrl}',
      ]);
      expect(
        events.any(
          (e) =>
              e.stage == TvUpdateDownloadStage.switchingMirror &&
              e.activeSourceLabel == 'ghfast',
        ),
        isTrue,
      );
      expect(events.last.stage, TvUpdateDownloadStage.completed);
      expect(events.last.activeSourceLabel, 'ghfast');
      expect(events.last.fraction, 1.0);
    });

    test('does not switch mirrors when cancelled during download and cleans up temp dir', () async {
      final asset = TvUpdateApkAsset(
        abi: 'arm64-v8a',
        fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
        rawDownloadUrl:
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
        sha256: 'a' * 64,
        size: 1024,
      );
      final token = CancelToken();
      var downloadCalls = 0;

      final service = TvUpdateService(
        availableStorageProvider: (_) async => -1,
        tempDirProvider: () async => tempDir,
        fileDownloader: (url, savePath, {cancelToken, onReceiveProgress}) async {
          downloadCalls++;
          await File(savePath).writeAsBytes([1, 2, 3], flush: true);
          cancelToken?.cancel('user cancelled');
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: url),
            reason: 'user cancelled',
          );
        },
      );

      await expectLater(
        service.downloadApk(
          release: makeRelease(asset),
          asset: asset,
          mirrorOverride: TvUpdateMirrorMode.ghProxy,
          cancelToken: token,
          onProgress: (_) {},
        ),
        throwsA(isA<DioException>()),
      );

      expect(downloadCalls, 1);
      final remainingTempDirs = await tempDir
          .list()
          .where((e) => e is Directory && e.path.contains('kazumi-update-'))
          .toList();
      expect(remainingTempDirs, isEmpty);
    });

    test('installApk validates existence, permission, and opener outcome', () async {
      final apkFile = File('${tempDir.path}/KazumiTV.apk');

      final missingService = TvUpdateService(
        installPermissionChecker: () async => true,
        apkOpener: (_) async => OpenResult(type: ResultType.done),
      );
      final missingResult = await missingService.installApk(apkFile.path);
      expect(missingResult.outcome, TvUpdateInstallOutcome.failed);

      await apkFile.writeAsBytes([0x50, 0x4B, 0x03, 0x04], flush: true);

      final deniedService = TvUpdateService(
        installPermissionChecker: () async => false,
        apkOpener: (_) async => OpenResult(type: ResultType.done),
      );
      final deniedResult = await deniedService.installApk(apkFile.path);
      expect(deniedResult.outcome, TvUpdateInstallOutcome.permissionRequired);

      final grantedService = TvUpdateService(
        installPermissionChecker: () async => true,
        apkOpener: (_) async => OpenResult(type: ResultType.done),
      );
      final launchedResult = await grantedService.installApk(apkFile.path);
      expect(launchedResult.outcome, TvUpdateInstallOutcome.launched);

      final failedOpenService = TvUpdateService(
        installPermissionChecker: () async => true,
        apkOpener: (_) async =>
            OpenResult(type: ResultType.error, message: 'no installer'),
      );
      final failedOpenResult = await failedOpenService.installApk(apkFile.path);
      expect(failedOpenResult.outcome, TvUpdateInstallOutcome.failed);
      expect(failedOpenResult.message, 'no installer');
    });

    test('cleanupCachedApks deletes old cached APKs and preserves keepFilePath', () async {
      final oldApk = File(
        '${tempDir.path}/kazumi-tv-update-2.4.5-arm64-v8a.apk',
      );
      final keepApk = File(
        '${tempDir.path}/kazumi-tv-update-2.4.7-arm64-v8a.apk',
      );
      final unrelatedFile = File('${tempDir.path}/other.txt');
      final staleTempDir = Directory('${tempDir.path}/kazumi-update-stale');

      await oldApk.writeAsBytes([1, 2, 3], flush: true);
      await keepApk.writeAsBytes([4, 5, 6], flush: true);
      await unrelatedFile.writeAsString('keep');
      await staleTempDir.create();

      final service = TvUpdateService(tempDirProvider: () async => tempDir);
      final deleted = await service.cleanupCachedApks(keepFilePath: keepApk.path);

      expect(deleted, 1);
      expect(await oldApk.exists(), isFalse);
      expect(await keepApk.exists(), isTrue);
      expect(await unrelatedFile.exists(), isTrue);
      expect(await staleTempDir.exists(), isFalse);
    });

    test('formatBytes formats bytes cleanly', () {
      expect(TvUpdateService.formatBytes(0), '0 B');
      expect(TvUpdateService.formatBytes(512), '512 B');
      expect(TvUpdateService.formatBytes(1536), '1.5 KB');
      expect(TvUpdateService.formatBytes(30450923), '29.0 MB');
      expect(TvUpdateService.formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });
}
