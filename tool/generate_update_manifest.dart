import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Default GitHub repository slug used when `--repo` is not provided.
const String defaultUpdateRepo = 'loong486/kazumi-tv';

const List<String> _canonicalAbiOrder = <String>[
  'arm64-v8a',
  'armeabi-v7a',
  'x86_64',
  'universal',
];

/// Exception thrown when manifest generation inputs or outputs are invalid.
class ManifestGenerationException implements Exception {
  ManifestGenerationException(this.message);

  final String message;

  @override
  String toString() => 'ManifestGenerationException: $message';
}

/// Parsed semantic version name and optional build number from `pubspec.yaml`.
class PubspecVersionInfo {
  const PubspecVersionInfo({
    required this.version,
    this.versionCode,
  });

  final String version;
  final int? versionCode;
}

/// Metadata for a single APK entry inside `latest.json`.
class GeneratedApkArtifact {
  const GeneratedApkArtifact({
    required this.abi,
    required this.fileName,
    required this.url,
    required this.sha256,
    required this.size,
    required this.versionCode,
  });

  final String abi;
  final String fileName;
  final String url;
  final String sha256;
  final int size;
  final int versionCode;

  Map<String, Object> toJson() => <String, Object>{
        'fileName': fileName,
        'url': url,
        'sha256': sha256,
        'size': size,
        'versionCode': versionCode,
      };
}

/// Result returned by [generateUpdateManifest].
class GeneratedUpdateManifestResult {
  const GeneratedUpdateManifestResult({
    required this.manifest,
    required this.manifestFile,
    required this.checksumsFile,
    required this.checksumsContent,
  });

  final Map<String, Object?> manifest;
  final File manifestFile;
  final File checksumsFile;
  final String checksumsContent;
}

/// Normalizes a version string by stripping a leading `v` or `V`.
String normalizeVersionName(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw ManifestGenerationException('Version must not be empty.');
  }
  final stripped = (trimmed.startsWith('v') || trimmed.startsWith('V'))
      ? trimmed.substring(1).trim()
      : trimmed;
  if (stripped.isEmpty) {
    throw ManifestGenerationException('Version "$raw" is invalid.');
  }
  return stripped;
}

/// Parses `version: X.Y.Z+N` from `pubspec.yaml` content.
PubspecVersionInfo parsePubspecVersion(String pubspecContent) {
  final match = RegExp(
    r'''^\s*version\s*:\s*['"]?([^'"\s#]+)['"]?''',
    multiLine: true,
  ).firstMatch(pubspecContent);
  if (match == null) {
    throw ManifestGenerationException(
      'Could not find a `version:` field in pubspec.yaml.',
    );
  }
  final raw = match.group(1)!.trim();
  return _splitVersionAndCode(raw);
}

PubspecVersionInfo _splitVersionAndCode(String raw) {
  final plusIndex = raw.indexOf('+');
  if (plusIndex == -1) {
    return PubspecVersionInfo(version: normalizeVersionName(raw));
  }
  final versionPart = raw.substring(0, plusIndex);
  final codePart = raw.substring(plusIndex + 1).trim();
  if (codePart.isEmpty) {
    return PubspecVersionInfo(version: normalizeVersionName(versionPart));
  }
  final parsedCode = int.tryParse(codePart);
  if (parsedCode == null || parsedCode <= 0) {
    throw ManifestGenerationException(
      'Invalid versionCode "$codePart" in version "$raw".',
    );
  }
  return PubspecVersionInfo(
    version: normalizeVersionName(versionPart),
    versionCode: parsedCode,
  );
}

/// Normalizes and validates a GitHub `owner/repo` slug.
String normalizeGitHubRepo(String rawRepo) {
  var value = rawRepo.trim();
  if (value.isEmpty) {
    throw ManifestGenerationException('Repository slug must not be empty.');
  }
  if (value.startsWith('https://github.com/') ||
      value.startsWith('http://github.com/')) {
    final uri = Uri.tryParse(value);
    if (uri == null || uri.pathSegments.length < 2) {
      throw ManifestGenerationException(
        'Invalid GitHub repository URL: "$rawRepo".',
      );
    }
    value = '${uri.pathSegments[0]}/${uri.pathSegments[1]}';
  }
  value = value.replaceAll(RegExp(r'^/+|/+$'), '');
  if (value.endsWith('.git')) {
    value = value.substring(0, value.length - 4);
  }
  final validPattern = RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$');
  if (!validPattern.hasMatch(value)) {
    throw ManifestGenerationException(
      'Repository "$rawRepo" must be in "owner/repo" format.',
    );
  }
  return value;
}

/// Detects the Android ABI encoded in [fileName].
String detectApkAbi(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.contains('arm64-v8a')) {
    return 'arm64-v8a';
  }
  if (lower.contains('armeabi-v7a')) {
    return 'armeabi-v7a';
  }
  if (lower.contains('x86_64')) {
    return 'x86_64';
  }
  return 'universal';
}

/// Computes the split-ABI Android `versionCode` matching `android/app/build.gradle`.
int computeSplitVersionCode(int baseVersionCode, String abi) {
  return switch (abi) {
    'armeabi-v7a' => baseVersionCode * 10 + 1,
    'arm64-v8a' => baseVersionCode * 10 + 2,
    'x86_64' => baseVersionCode * 10 + 4,
    _ => baseVersionCode,
  };
}

String _baseName(String filePath) {
  final sep = Platform.pathSeparator;
  final normalized = filePath.replaceAll('/', sep).replaceAll('\\', sep);
  final lastSep = normalized.lastIndexOf(sep);
  return lastSep == -1 ? normalized : normalized.substring(lastSep + 1);
}

String _joinPath(String directory, String child) {
  final trimmed = directory.replaceAll(RegExp(r'[/\\]+$'), '');
  if (trimmed.isEmpty) {
    return child;
  }
  return '$trimmed${Platform.pathSeparator}$child';
}

int _compareAbis(String a, String b) {
  final idxA = _canonicalAbiOrder.indexOf(a);
  final idxB = _canonicalAbiOrder.indexOf(b);
  if (idxA != -1 && idxB != -1) {
    return idxA.compareTo(idxB);
  }
  if (idxA != -1) {
    return -1;
  }
  if (idxB != -1) {
    return 1;
  }
  return a.compareTo(b);
}

bool _parseBoolFlag(String raw, String flagName) {
  final normalized = raw.trim().toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  throw ManifestGenerationException(
    'Invalid boolean value "$raw" for --$flagName (expected "true" or "false").',
  );
}

/// Scans [apkDir] for `.apk` files, computes streaming SHA-256 checksums,
/// and writes both `latest.json` and `SHA256SUMS.txt`.
Future<GeneratedUpdateManifestResult> generateUpdateManifest({
  required String apkDir,
  String repo = defaultUpdateRepo,
  String? tag,
  String? version,
  int? versionCode,
  String? changelog,
  String? changelogFile,
  bool force = false,
  String? publishedAt,
  String? outManifest,
  String? outChecksums,
  String pubspecPath = 'pubspec.yaml',
}) async {
  final normalizedRepo = normalizeGitHubRepo(repo);

  String? resolvedVersion = version;
  int? resolvedVersionCode = versionCode;

  if (resolvedVersion != null && resolvedVersion.trim().isNotEmpty) {
    final parsed = _splitVersionAndCode(resolvedVersion.trim());
    resolvedVersion = parsed.version;
    resolvedVersionCode ??= parsed.versionCode;
  } else {
    resolvedVersion = null;
  }

  if (resolvedVersion == null || resolvedVersionCode == null) {
    final pubspec = File(pubspecPath);
    if (!await pubspec.exists()) {
      throw ManifestGenerationException(
        'Cannot resolve version/versionCode: "$pubspecPath" not found.',
      );
    }
    final pubspecInfo = parsePubspecVersion(await pubspec.readAsString());
    resolvedVersion ??= pubspecInfo.version;
    resolvedVersionCode ??= pubspecInfo.versionCode;
  }

  if (resolvedVersionCode == null || resolvedVersionCode <= 0) {
    throw ManifestGenerationException(
      'Unable to determine a positive base versionCode from arguments or "$pubspecPath".',
    );
  }

  final resolvedTag =
      (tag != null && tag.trim().isNotEmpty) ? tag.trim() : 'v$resolvedVersion';

  String resolvedChangelog;
  if (changelogFile != null && changelogFile.trim().isNotEmpty) {
    final clFile = File(changelogFile.trim());
    if (!await clFile.exists()) {
      throw ManifestGenerationException(
        'Changelog file not found: "${clFile.path}".',
      );
    }
    resolvedChangelog = (await clFile.readAsString()).trim();
  } else {
    resolvedChangelog = (changelog ?? '').trim();
  }

  final resolvedPublishedAt =
      (publishedAt != null && publishedAt.trim().isNotEmpty)
          ? publishedAt.trim()
          : DateTime.now().toUtc().toIso8601String();
  try {
    DateTime.parse(resolvedPublishedAt);
  } on FormatException {
    throw ManifestGenerationException(
      'Invalid ISO-8601 timestamp for --published-at: "$resolvedPublishedAt".',
    );
  }

  final directory = Directory(apkDir);
  if (!await directory.exists()) {
    throw ManifestGenerationException(
      'APK directory does not exist: "$apkDir".',
    );
  }

  final apkFiles = <File>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is File && _baseName(entity.path).toLowerCase().endsWith('.apk')) {
      apkFiles.add(entity);
    }
  }
  apkFiles.sort((a, b) => _baseName(a.path).compareTo(_baseName(b.path)));

  if (apkFiles.isEmpty) {
    throw ManifestGenerationException(
      'No matching .apk files found in "$apkDir".',
    );
  }

  final encodedTag = Uri.encodeComponent(resolvedTag);
  final artifactsByAbi = <String, GeneratedApkArtifact>{};

  for (final file in apkFiles) {
    final fileName = _baseName(file.path);
    final abi = detectApkAbi(fileName);
    if (artifactsByAbi.containsKey(abi)) {
      throw ManifestGenerationException(
        'Multiple APK files detected for ABI "$abi" in "$apkDir": '
        '"${artifactsByAbi[abi]!.fileName}" and "$fileName".',
      );
    }

    final size = await file.length();
    final digest = await sha256.bind(file.openRead()).first;
    final sha256Hex = digest.toString().toLowerCase();
    final encodedFileName = Uri.encodeComponent(fileName);
    final downloadUrl =
        'https://github.com/$normalizedRepo/releases/download/$encodedTag/$encodedFileName';

    artifactsByAbi[abi] = GeneratedApkArtifact(
      abi: abi,
      fileName: fileName,
      url: downloadUrl,
      sha256: sha256Hex,
      size: size,
      versionCode: computeSplitVersionCode(resolvedVersionCode, abi),
    );
  }

  final sortedAbis = artifactsByAbi.keys.toList()..sort(_compareAbis);
  final apksJson = <String, Map<String, Object>>{
    for (final abi in sortedAbis) abi: artifactsByAbi[abi]!.toJson(),
  };

  final manifest = <String, Object?>{
    'schemaVersion': 1,
    'version': resolvedVersion,
    'versionCode': resolvedVersionCode,
    'tag': resolvedTag,
    'publishedAt': resolvedPublishedAt,
    'changelog': resolvedChangelog,
    'force': force,
    'releaseUrl':
        'https://github.com/$normalizedRepo/releases/tag/$encodedTag',
    'apks': apksJson,
  };

  final manifestPath =
      (outManifest != null && outManifest.trim().isNotEmpty)
          ? outManifest.trim()
          : _joinPath(apkDir, 'latest.json');
  final checksumsPath =
      (outChecksums != null && outChecksums.trim().isNotEmpty)
          ? outChecksums.trim()
          : _joinPath(apkDir, 'SHA256SUMS.txt');

  final manifestFile = File(manifestPath);
  await manifestFile.parent.create(recursive: true);
  final encodedManifest =
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
  await manifestFile.writeAsString(encodedManifest, flush: true);

  final checksumArtifacts = artifactsByAbi.values.toList()
    ..sort((a, b) => a.fileName.compareTo(b.fileName));
  final checksumBuffer = StringBuffer();
  for (final artifact in checksumArtifacts) {
    checksumBuffer.write('${artifact.sha256}  ${artifact.fileName}\n');
  }
  final checksumsContent = checksumBuffer.toString();

  final checksumsFile = File(checksumsPath);
  await checksumsFile.parent.create(recursive: true);
  await checksumsFile.writeAsString(checksumsContent, flush: true);

  return GeneratedUpdateManifestResult(
    manifest: manifest,
    manifestFile: manifestFile,
    checksumsFile: checksumsFile,
    checksumsContent: checksumsContent,
  );
}

void _printUsage() {
  stdout.writeln('''
Generate latest.json and SHA256SUMS.txt for Kazumi TV release APKs.

Usage:
  dart run tool/generate_update_manifest.dart --apk-dir <dir> [options]

Options:
  --apk-dir <dir>           Directory containing release APK files (required)
  --repo <owner/repo>       GitHub repository (default: $defaultUpdateRepo)
  --tag <tag>               Release tag (default: v<version>)
  --version <X.Y.Z>         Release version name (default: parsed from pubspec.yaml)
  --version-code <int>      Base versionCode (default: parsed from pubspec.yaml)
  --changelog <text>        Inline release notes text
  --changelog-file <path>   Path to UTF-8 release notes file
  --force <true|false>      Whether update is forced (default: false)
  --published-at <iso8601>  UTC ISO-8601 publish timestamp (default: now UTC)
  --out-manifest <path>     Output manifest path (default: <apk-dir>/latest.json)
  --out-checksums <path>    Output checksums path (default: <apk-dir>/SHA256SUMS.txt)
  --pubspec <path>          Path to pubspec.yaml (default: pubspec.yaml)
  -h, --help                Show this help message
''');
}

Map<String, String> _parseCliArguments(List<String> args) {
  final parsed = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      parsed['help'] = 'true';
      continue;
    }
    if (!arg.startsWith('--')) {
      throw ManifestGenerationException('Unexpected positional argument: "$arg".');
    }
    final eqIndex = arg.indexOf('=');
    String name;
    String value;
    if (eqIndex != -1) {
      name = arg.substring(2, eqIndex);
      value = arg.substring(eqIndex + 1);
    } else {
      name = arg.substring(2);
      if (i + 1 >= args.length) {
        throw ManifestGenerationException('Missing value for flag "--$name".');
      }
      value = args[++i];
    }
    if (!_supportedFlags.contains(name)) {
      throw ManifestGenerationException('Unknown flag "--$name".');
    }
    parsed[name] = value;
  }
  return parsed;
}

const Set<String> _supportedFlags = <String>{
  'repo',
  'tag',
  'version',
  'version-code',
  'apk-dir',
  'changelog',
  'changelog-file',
  'force',
  'published-at',
  'out-manifest',
  'out-checksums',
  'pubspec',
};

Future<void> main(List<String> args) async {
  try {
    final options = _parseCliArguments(args);
    if (options.containsKey('help')) {
      _printUsage();
      return;
    }

    final apkDir = options['apk-dir'];
    if (apkDir == null || apkDir.trim().isEmpty) {
      throw ManifestGenerationException('--apk-dir is required.');
    }

    int? versionCode;
    final rawVersionCode = options['version-code'];
    if (rawVersionCode != null && rawVersionCode.trim().isNotEmpty) {
      versionCode = int.tryParse(rawVersionCode.trim());
      if (versionCode == null || versionCode <= 0) {
        throw ManifestGenerationException(
          'Invalid integer for --version-code: "$rawVersionCode".',
        );
      }
    }

    final force = options.containsKey('force')
        ? _parseBoolFlag(options['force']!, 'force')
        : false;

    final result = await generateUpdateManifest(
      apkDir: apkDir.trim(),
      repo: options['repo'] ?? defaultUpdateRepo,
      tag: options['tag'],
      version: options['version'],
      versionCode: versionCode,
      changelog: options['changelog'],
      changelogFile: options['changelog-file'],
      force: force,
      publishedAt: options['published-at'],
      outManifest: options['out-manifest'],
      outChecksums: options['out-checksums'],
      pubspecPath: options['pubspec'] ?? 'pubspec.yaml',
    );

    final apks = result.manifest['apks'] as Map<String, Object?>;
    stdout.writeln(
      'Generated ${result.manifestFile.path} and ${result.checksumsFile.path} '
      '(${apks.length} APK(s), tag=${result.manifest['tag']}).',
    );
  } on Object catch (error) {
    stderr.writeln('Error: $error');
    exitCode = 1;
  }
}
