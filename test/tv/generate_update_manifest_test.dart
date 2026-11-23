import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_update_manifest.dart' as manifest_cli;

void main() {
  group('parsePubspecVersion', () {
    test('parses version name and base versionCode', () {
      final info = manifest_cli.parsePubspecVersion('''
name: kazumi
version: 2.4.7+20407
''');
      expect(info.version, '2.4.7');
      expect(info.versionCode, 20407);
    });

    test('parses quoted prerelease version with inline comment', () {
      final info = manifest_cli.parsePubspecVersion('''
name: kazumi
version: "2.5.0-rc.1+20500" # release candidate
''');
      expect(info.version, '2.5.0-rc.1');
      expect(info.versionCode, 20500);
    });

    test('throws when version field is missing', () {
      expect(
        () => manifest_cli.parsePubspecVersion('name: kazumi\n'),
        throwsA(isA<manifest_cli.ManifestGenerationException>()),
      );
    });
  });

  group('ABI detection and split versionCode', () {
    test('detects supported ABIs and computes split versionCode', () {
      expect(
        manifest_cli.detectApkAbi('KazumiTV_2.4.7_arm64-v8a.apk'),
        'arm64-v8a',
      );
      expect(
        manifest_cli.detectApkAbi('KazumiTV_2.4.7_armeabi-v7a.apk'),
        'armeabi-v7a',
      );
      expect(manifest_cli.detectApkAbi('KazumiTV_2.4.7_x86_64.apk'), 'x86_64');
      expect(
        manifest_cli.detectApkAbi('KazumiTV_2.4.7_universal.apk'),
        'universal',
      );
      expect(manifest_cli.detectApkAbi('app-release.apk'), 'universal');

      expect(
        manifest_cli.computeSplitVersionCode(20407, 'armeabi-v7a'),
        204071,
      );
      expect(manifest_cli.computeSplitVersionCode(20407, 'arm64-v8a'), 204072);
      expect(manifest_cli.computeSplitVersionCode(20407, 'x86_64'), 204074);
      expect(manifest_cli.computeSplitVersionCode(20407, 'universal'), 20407);
    });
  });

  group('generateUpdateManifest', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('kazumi_manifest_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generates exact latest.json schema and sorted SHA256SUMS.txt', () async {
      final apkDir = Directory('${tempDir.path}/dist');
      await apkDir.create(recursive: true);

      final arm64Bytes = utf8.encode('fake-arm64-apk-payload-001');
      final armeabiBytes = utf8.encode('fake-armeabi-apk-payload-0002');
      final x86Bytes = utf8.encode('fake-x86-64-apk-payload-00003');

      final arm64Name = 'KazumiTV_2.4.7_arm64-v8a.apk';
      final armeabiName = 'KazumiTV_2.4.7_armeabi-v7a.apk';
      final x86Name = 'KazumiTV_2.4.7_x86_64.apk';

      await File('${apkDir.path}/$arm64Name').writeAsBytes(arm64Bytes);
      await File('${apkDir.path}/$armeabiName').writeAsBytes(armeabiBytes);
      await File('${apkDir.path}/$x86Name').writeAsBytes(x86Bytes);
      // Non-APK files in the staging directory must be ignored.
      await File('${apkDir.path}/README.txt').writeAsString('ignore me');

      final changelogFile = File('${tempDir.path}/CHANGELOG.md');
      await changelogFile.writeAsString(
        '  - Fixed TV focus halo clipping\n  - Added OTA update  \n',
      );

      final result = await manifest_cli.generateUpdateManifest(
        apkDir: apkDir.path,
        repo: 'loong486/kazumi-tv',
        tag: 'v2.4.7',
        version: '2.4.7',
        versionCode: 20407,
        changelogFile: changelogFile.path,
        force: true,
        publishedAt: '2026-11-23T08:00:00Z',
      );

      final manifestOnDisk =
          jsonDecode(await result.manifestFile.readAsString())
              as Map<String, dynamic>;

      final expectedArm64Hash = sha256.convert(arm64Bytes).toString();
      final expectedArmeabiHash = sha256.convert(armeabiBytes).toString();
      final expectedX86Hash = sha256.convert(x86Bytes).toString();

      expect(expectedArm64Hash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(manifestOnDisk['schemaVersion'], 1);
      expect(manifestOnDisk['version'], '2.4.7');
      expect(manifestOnDisk['versionCode'], 20407);
      expect(manifestOnDisk['tag'], 'v2.4.7');
      expect(manifestOnDisk['publishedAt'], '2026-11-23T08:00:00Z');
      expect(
        manifestOnDisk['changelog'],
        '- Fixed TV focus halo clipping\n  - Added OTA update',
      );
      expect(manifestOnDisk['force'], isTrue);
      expect(
        manifestOnDisk['releaseUrl'],
        'https://github.com/loong486/kazumi-tv/releases/tag/v2.4.7',
      );

      final apks = manifestOnDisk['apks'] as Map<String, dynamic>;
      expect(apks.keys.toList(), ['arm64-v8a', 'armeabi-v7a', 'x86_64']);

      expect(apks['arm64-v8a'], <String, Object>{
        'fileName': arm64Name,
        'url':
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/$arm64Name',
        'sha256': expectedArm64Hash,
        'size': arm64Bytes.length,
        'versionCode': 204072,
      });
      expect(apks['armeabi-v7a'], <String, Object>{
        'fileName': armeabiName,
        'url':
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/$armeabiName',
        'sha256': expectedArmeabiHash,
        'size': armeabiBytes.length,
        'versionCode': 204071,
      });
      expect(apks['x86_64'], <String, Object>{
        'fileName': x86Name,
        'url':
            'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/$x86Name',
        'sha256': expectedX86Hash,
        'size': x86Bytes.length,
        'versionCode': 204074,
      });

      final checksumsOnDisk = await result.checksumsFile.readAsString();
      expect(
        checksumsOnDisk,
        '$expectedArm64Hash  $arm64Name\n'
        '$expectedArmeabiHash  $armeabiName\n'
        '$expectedX86Hash  $x86Name\n',
      );
    });

    test('reads pubspec.yaml defaults and handles universal APK', () async {
      final apkDir = Directory('${tempDir.path}/universal_dist');
      await apkDir.create(recursive: true);

      final universalBytes = utf8.encode('universal-apk-bytes');
      final universalName = 'KazumiTV_2.4.8_universal.apk';
      await File('${apkDir.path}/$universalName').writeAsBytes(universalBytes);

      final pubspecFile = File('${tempDir.path}/pubspec.yaml');
      await pubspecFile.writeAsString('name: kazumi\nversion: 2.4.8+20408\n');

      final outManifest = '${tempDir.path}/out/custom_latest.json';
      final outChecksums = '${tempDir.path}/out/custom_sums.txt';

      final result = await manifest_cli.generateUpdateManifest(
        apkDir: apkDir.path,
        pubspecPath: pubspecFile.path,
        outManifest: outManifest,
        outChecksums: outChecksums,
      );

      final manifest = result.manifest;
      expect(manifest['version'], '2.4.8');
      expect(manifest['versionCode'], 20408);
      expect(manifest['tag'], 'v2.4.8');
      expect(manifest['force'], isFalse);
      expect(manifest['changelog'], '');
      expect(
        () => DateTime.parse(manifest['publishedAt'] as String),
        returnsNormally,
      );

      final apks = manifest['apks'] as Map<String, Object?>;
      expect(apks.keys, ['universal']);
      expect(
        (apks['universal'] as Map<String, Object>)['versionCode'],
        20408,
      );
      expect(await File(outManifest).exists(), isTrue);
      expect(await File(outChecksums).exists(), isTrue);
    });

    test('throws when apk directory has no APK files or does not exist', () async {
      final emptyDir = Directory('${tempDir.path}/empty');
      await emptyDir.create(recursive: true);
      await File('${emptyDir.path}/not_an_apk.zip').writeAsString('zip');

      await expectLater(
        () => manifest_cli.generateUpdateManifest(
          apkDir: emptyDir.path,
          version: '2.4.7',
          versionCode: 20407,
        ),
        throwsA(isA<manifest_cli.ManifestGenerationException>()),
      );

      await expectLater(
        () => manifest_cli.generateUpdateManifest(
          apkDir: '${tempDir.path}/missing',
          version: '2.4.7',
          versionCode: 20407,
        ),
        throwsA(isA<manifest_cli.ManifestGenerationException>()),
      );
    });

    test('throws when duplicate APKs exist for the same ABI', () async {
      final dupDir = Directory('${tempDir.path}/dup');
      await dupDir.create(recursive: true);
      await File('${dupDir.path}/a_arm64-v8a.apk').writeAsBytes(<int>[1, 2, 3]);
      await File('${dupDir.path}/b_arm64-v8a.apk').writeAsBytes(<int>[4, 5, 6]);

      await expectLater(
        () => manifest_cli.generateUpdateManifest(
          apkDir: dupDir.path,
          version: '2.4.7',
          versionCode: 20407,
        ),
        throwsA(isA<manifest_cli.ManifestGenerationException>()),
      );
    });

    test('CLI main sets non-zero exitCode on empty dir and succeeds on valid input', () async {
      final previousExitCode = exitCode;
      try {
        final emptyDir = Directory('${tempDir.path}/cli_empty');
        await emptyDir.create(recursive: true);

        exitCode = 0;
        await manifest_cli.main(<String>[
          '--apk-dir',
          emptyDir.path,
          '--version',
          '2.4.7',
          '--version-code',
          '20407',
        ]);
        expect(exitCode, isNonZero);

        final validDir = Directory('${tempDir.path}/cli_valid');
        await validDir.create(recursive: true);
        await File('${validDir.path}/KazumiTV_2.4.7_arm64-v8a.apk')
            .writeAsBytes(utf8.encode('cli-apk'));

        exitCode = 0;
        await manifest_cli.main(<String>[
          '--repo',
          'loong486/kazumi-tv',
          '--tag',
          'v2.4.7',
          '--version',
          '2.4.7',
          '--version-code',
          '20407',
          '--apk-dir',
          validDir.path,
          '--force',
          'false',
        ]);
        expect(exitCode, 0);
        expect(await File('${validDir.path}/latest.json').exists(), isTrue);
        expect(await File('${validDir.path}/SHA256SUMS.txt').exists(), isTrue);
      } finally {
        exitCode = previousExitCode;
      }
    });
  });
}
