import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/update/tv_update_models.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_platform_channel.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_update_dialog.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.rootPath);

  final String rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getTemporaryPath() async => rootPath;
}

class _FakeTvUpdateService extends TvUpdateService {
  _FakeTvUpdateService(this.handler)
    : super(
        abiProvider: () async => const ['arm64-v8a'],
        versionInfoProvider: () async =>
            const TvAppVersionInfo(versionName: '2.4.6', versionCode: 20406),
      );

  final Future<TvUpdateCheckResult> Function({CancelToken? cancelToken}) handler;
  int checkCount = 0;

  @override
  Future<TvUpdateCheckResult> checkForUpdates({
    String? repoOverride,
    TvUpdateMirrorMode? mirrorOverride,
    String? customMirrorOverride,
    CancelToken? cancelToken,
  }) {
    checkCount++;
    return handler(cancelToken: cancelToken);
  }
}

void main() {
  void configureTvViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> sendAndroidGoBack(
    WidgetTester tester,
    Duration timeStamp,
  ) async {
    final goBackPhysical = PhysicalKeyboardKey.browserBack.usbHidUsage;
    final goBackLogical = LogicalKeyboardKey.goBack.keyId;
    tester.platformDispatcher.onKeyData?.call(
      ui.KeyData(
        type: ui.KeyEventType.down,
        physical: goBackPhysical,
        logical: goBackLogical,
        timeStamp: timeStamp,
        character: null,
        synthesized: false,
      ),
    );
    await tester.pump();
    tester.platformDispatcher.onKeyData?.call(
      ui.KeyData(
        type: ui.KeyEventType.up,
        physical: goBackPhysical,
        logical: goBackLogical,
        timeStamp: timeStamp + const Duration(milliseconds: 20),
        character: null,
        synthesized: false,
      ),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
  }

  TvUpdateApkAsset sampleAsset({int size = 30450923}) {
    return TvUpdateApkAsset(
      abi: 'arm64-v8a',
      fileName: 'KazumiTV_2.4.7_arm64-v8a.apk',
      rawDownloadUrl:
          'https://github.com/loong486/kazumi-tv/releases/download/v2.4.7/KazumiTV_2.4.7_arm64-v8a.apk',
      sha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      size: size,
      versionCode: 204072,
    );
  }

  TvUpdateRelease sampleRelease({
    bool force = false,
    String changelog = '1. 新增应用内自更新\n2. 优化遥控器焦点体验',
    String publishedAt = '2026-11-23T08:00:00Z',
  }) {
    final asset = sampleAsset();
    return TvUpdateRelease(
      version: '2.4.7',
      tag: 'v2.4.7',
      versionCode: 20407,
      changelog: changelog,
      publishedAt: publishedAt,
      releaseUrl: 'https://github.com/loong486/kazumi-tv/releases/tag/v2.4.7',
      force: force,
      apks: {'arm64-v8a': asset},
      sourceLabel: 'gh-proxy',
    );
  }

  Widget buildDialogHostApp({required Widget child}) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      navigatorObservers: [KazumiDialog.observer],
      theme: TvTheme.buildTheme(brightness: Brightness.dark),
      builder: (context, appChild) => Actions(
        actions: <Type, Action<Intent>>{
          DirectionalFocusIntent: TvDirectionalFocusAction(),
        },
        child: FocusTraversalGroup(
          policy: TvFocusTraversalPolicy(),
          child: appChild ?? const SizedBox.shrink(),
        ),
      ),
      home: child,
    );
  }

  group('TvUpdateAvailableDialog', () {
    testWidgets(
      'renders version, ABI, size, date, source, changelog and defaults focus to 立即更新',
      (tester) async {
        configureTvViewport(tester);
        TvUpdateDialogAction? dialogResult;
        final release = sampleRelease();
        final asset = sampleAsset();

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Open',
                    onPressed: () async {
                      dialogResult = await KazumiDialog.show<
                        TvUpdateDialogAction
                      >(
                        context: context,
                        builder: (_) => TvUpdateAvailableDialog(
                          currentVersion: '2.4.6',
                          release: release,
                          asset: asset,
                          activeMirrorLabel: 'gh-proxy',
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(find.text('发现新版本'), findsOneWidget);
        expect(find.text('v2.4.6 -> v2.4.7'), findsOneWidget);
        expect(find.text('架构: arm64-v8a'), findsOneWidget);
        expect(find.text('大小: 29.0 MB'), findsOneWidget);
        expect(find.text('2026-11-23'), findsOneWidget);
        expect(find.text('镜像: gh-proxy'), findsOneWidget);
        expect(find.textContaining('新增应用内自更新'), findsOneWidget);

        // Default autofocus must be on '立即更新'; pressing Select immediately returns updateNow.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(dialogResult, TvUpdateDialogAction.updateNow);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('returns TvUpdateDialogAction.ignoreVersion when 忽略此版本 selected', (
      tester,
    ) async {
      configureTvViewport(tester);
      TvUpdateDialogAction? dialogResult;
      final release = sampleRelease();
      final asset = sampleAsset();

      await tester.pumpWidget(
        buildDialogHostApp(
          child: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TvPrimaryButton(
                  autofocus: true,
                  label: 'Open',
                  onPressed: () async {
                    dialogResult = await KazumiDialog.show<
                      TvUpdateDialogAction
                    >(
                      context: context,
                      builder: (_) => TvUpdateAvailableDialog(
                        currentVersion: '2.4.6',
                        release: release,
                        asset: asset,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      // Move left 3 steps from 立即更新 -> 切换镜像 -> 暂不更新 -> 忽略此版本.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(dialogResult, TvUpdateDialogAction.ignoreVersion);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'handles goBack + handlePopRoute without double-popping host route',
      (tester) async {
        configureTvViewport(tester);
        var hostRoutePopped = false;
        late BuildContext hostContext;
        final release = sampleRelease();
        final asset = sampleAsset();

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (rootContext) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Push Host',
                    onPressed: () {
                      Navigator.of(rootContext).push<void>(
                        MaterialPageRoute<void>(
                          builder: (ctx) {
                            hostContext = ctx;
                            return PopScope(
                              onPopInvokedWithResult: (didPop, _) {
                                if (didPop) hostRoutePopped = true;
                              },
                              child: const Scaffold(
                                body: Center(child: Text('Host Page')),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(find.text('Host Page'), findsOneWidget);

        unawaited(
          KazumiDialog.show<TvUpdateDialogAction>(
            context: hostContext,
            builder: (_) => TvUpdateAvailableDialog(
              currentVersion: '2.4.6',
              release: release,
              asset: asset,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('发现新版本'), findsOneWidget);
        expect(KazumiDialog.observer.hasKazumiDialog, isTrue);

        await sendAndroidGoBack(tester, const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.text('发现新版本'), findsNothing);
        expect(find.text('Host Page'), findsOneWidget);
        expect(hostRoutePopped, isFalse);
        expect(KazumiDialog.observer.hasKazumiDialog, isFalse);
      },
    );

    testWidgets(
      'force: true hides 暂不更新 and 忽略此版本 and blocks back dismissal',
      (tester) async {
        configureTvViewport(tester);
        final release = sampleRelease(force: true);
        final asset = sampleAsset();

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Open',
                    onPressed: () => KazumiDialog.show<TvUpdateDialogAction>(
                      context: context,
                      clickMaskDismiss: false,
                      builder: (_) => TvUpdateAvailableDialog(
                        currentVersion: '2.4.6',
                        release: release,
                        asset: asset,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(find.text('强制更新'), findsOneWidget);
        expect(find.text('立即更新'), findsOneWidget);
        expect(find.text('切换镜像'), findsOneWidget);
        expect(find.text('暂不更新'), findsNothing);
        expect(find.text('忽略此版本'), findsNothing);

        // Escape and system back must not dismiss forced update dialog.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.text('发现新版本'), findsOneWidget);
        expect(KazumiDialog.observer.hasKazumiDialog, isTrue);
      },
    );

    testWidgets(
      'D-pad ArrowUp focuses changelog and ArrowDown scrolls long notes',
      (tester) async {
        configureTvViewport(tester);
        final longNotes = List.generate(
          30,
          (i) => '第 ${i + 1} 条更新说明：修复并优化 Android TV 端焦点移动与播放器表现。',
        ).join('\n');
        final release = sampleRelease(changelog: longNotes);
        final asset = sampleAsset();

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Open',
                    onPressed: () => KazumiDialog.show<TvUpdateDialogAction>(
                      context: context,
                      builder: (_) => TvUpdateAvailableDialog(
                        currentVersion: '2.4.6',
                        release: release,
                        asset: asset,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        // ArrowUp moves focus from '立即更新' into the scrollable changelog box.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        final changelogScrollable = find.byType(Scrollable).last;
        final state = tester.state<ScrollableState>(changelogScrollable);
        expect(state.position.maxScrollExtent, greaterThan(0));
        expect(state.position.pixels, 0.0);

        // ArrowDown inside changelog scrolls downward before leaving to buttons.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(state.position.pixels, greaterThan(0));
      },
    );
  });

  group('TvUpdateDownloadDialog', () {
    testWidgets(
      'updates progress bar, percentage, speed, source label and cancels via button & Escape',
      (tester) async {
        configureTvViewport(tester);
        final progress = ValueNotifier<TvUpdateDownloadProgress>(
          const TvUpdateDownloadProgress(
            stage: TvUpdateDownloadStage.preparing,
            receivedBytes: 0,
            totalBytes: 20 * 1024 * 1024,
            bytesPerSecond: 0,
            activeSourceLabel: 'gh-proxy',
            message: '正在准备下载安装包...',
          ),
        );
        addTearDown(progress.dispose);

        var cancelCalls = 0;

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Scaffold(
              body: TvUpdateDownloadDialog(
                version: '2.4.7',
                progressListenable: progress,
                onCancel: () => cancelCalls++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('正在下载更新 v2.4.7'), findsOneWidget);
        expect(find.text('正在准备下载安装包...'), findsOneWidget);
        expect(find.text('gh-proxy'), findsOneWidget);
        expect(find.text('0.0%'), findsOneWidget);

        progress.value = const TvUpdateDownloadProgress(
          stage: TvUpdateDownloadStage.downloading,
          receivedBytes: 10 * 1024 * 1024,
          totalBytes: 20 * 1024 * 1024,
          bytesPerSecond: 2 * 1024 * 1024,
          activeSourceLabel: 'ghfast',
          message: '正在通过 ghfast 下载...',
        );
        await tester.pump();

        expect(find.text('正在通过 ghfast 下载...'), findsOneWidget);
        expect(find.text('ghfast'), findsOneWidget);
        expect(find.text('10.0 MB / 20.0 MB'), findsOneWidget);
        expect(find.text('2.0 MB/s'), findsOneWidget);
        expect(find.text('50.0%'), findsOneWidget);
        final indicator = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(indicator.value, closeTo(0.5, 0.001));

        // Cancel via default-focused '取消下载' button.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(cancelCalls, 1);

        // Repeated Escape does not fire onCancel a second time.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(cancelCalls, 1);
      },
    );

    testWidgets(
      'Escape and goBack + handlePopRoute dismiss download dialog cleanly and call onCancel once',
      (tester) async {
        configureTvViewport(tester);
        final progress = ValueNotifier<TvUpdateDownloadProgress>(
          const TvUpdateDownloadProgress(
            stage: TvUpdateDownloadStage.downloading,
            receivedBytes: 1024 * 1024,
            totalBytes: 4 * 1024 * 1024,
            bytesPerSecond: 512 * 1024,
            activeSourceLabel: 'gh-proxy',
            message: '正在通过 gh-proxy 下载...',
          ),
        );
        addTearDown(progress.dispose);

        var cancelCalls = 0;
        var hostRoutePopped = false;
        late BuildContext hostContext;

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (rootContext) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Push Host',
                    onPressed: () {
                      Navigator.of(rootContext).push<void>(
                        MaterialPageRoute<void>(
                          builder: (ctx) {
                            hostContext = ctx;
                            return PopScope(
                              onPopInvokedWithResult: (didPop, _) {
                                if (didPop) hostRoutePopped = true;
                              },
                              child: const Scaffold(
                                body: Center(child: Text('Host Page')),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        // Test 1: Escape key dismisses dialog and triggers onCancel.
        unawaited(
          KazumiDialog.show<bool>(
            context: hostContext,
            clickMaskDismiss: false,
            builder: (_) => TvUpdateDownloadDialog(
              version: '2.4.7',
              progressListenable: progress,
              onCancel: () => cancelCalls++,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('正在下载更新 v2.4.7'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(cancelCalls, 1);
        expect(find.text('正在下载更新 v2.4.7'), findsNothing);
        expect(find.text('Host Page'), findsOneWidget);
        expect(hostRoutePopped, isFalse);

        // Test 2: Android goBack + handlePopRoute does not double-pop host route.
        var secondCancelCalls = 0;
        unawaited(
          KazumiDialog.show<bool>(
            context: hostContext,
            clickMaskDismiss: false,
            builder: (_) => TvUpdateDownloadDialog(
              version: '2.4.7',
              progressListenable: progress,
              onCancel: () => secondCancelCalls++,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await sendAndroidGoBack(tester, const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(secondCancelCalls, 1);
        expect(find.text('正在下载更新 v2.4.7'), findsNothing);
        expect(find.text('Host Page'), findsOneWidget);
        expect(hostRoutePopped, isFalse);
      },
    );
  });

  group('TvUpdateInstallPermissionDialog', () {
    testWidgets(
      'renders fallback guidance and triggers open settings, retry install, and later callbacks',
      (tester) async {
        configureTvViewport(tester);
        var openSettingsCalls = 0;
        var retryInstallCalls = 0;
        var retryReturnValue = false;
        var laterCalls = 0;

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Open',
                    onPressed: () => KazumiDialog.show<bool>(
                      context: context,
                      clickMaskDismiss: false,
                      builder: (_) => TvUpdateInstallPermissionDialog(
                        apkPath: '/data/local/tmp/KazumiTV_2.4.7_arm64-v8a.apk',
                        onOpenSettings: () async {
                          openSettingsCalls++;
                          return true;
                        },
                        onRetryInstall: () async {
                          retryInstallCalls++;
                          return retryReturnValue;
                        },
                        onLater: () => laterCalls++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(find.text('需要安装未知应用权限'), findsOneWidget);
        expect(find.textContaining('TCL / 国产电视'), findsOneWidget);
        expect(
          find.textContaining('系统设置 -> 安全/隐私 -> 允许安装未知来源应用'),
          findsOneWidget,
        );

        // Default focus is on '去开启权限'.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(openSettingsCalls, 1);
        expect(find.text('需要安装未知应用权限'), findsOneWidget);

        // Move left to '我已开启，继续安装'; returning false keeps dialog open.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(retryInstallCalls, 1);
        expect(find.text('需要安装未知应用权限'), findsOneWidget);

        // Returning true from onRetryInstall closes the dialog.
        retryReturnValue = true;
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(retryInstallCalls, 2);
        expect(find.text('需要安装未知应用权限'), findsNothing);
        expect(laterCalls, 0);

        // Re-open and test '稍后安装'.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(laterCalls, 1);
        expect(find.text('需要安装未知应用权限'), findsNothing);
      },
    );
  });

  group('TvUpdateCoordinator', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;

    setUpAll(() async {
      Logger.level = Level.off;
      tempDir = await Directory.systemTemp.createTemp('kazumi_tv_update_ui_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(tempDir.path);
      Hive.init(tempDir.path);
      await GStorage.init();
    });

    setUp(() async {
      await TvUpdateConfig.setIgnoredVersion('');
      await GStorage.putSetting(SettingsKeys.autoUpdate, true);
    });

    tearDownAll(() async {
      await Hive.close();
      PathProviderPlatform.instance = originalPathProvider;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'checkTvUpdatesSilently skips ignored version unless force is true and avoids duplicate dialogs',
      (tester) async {
        configureTvViewport(tester);
        await tester.runAsync(
          () => TvUpdateConfig.setIgnoredVersion('2.4.7'),
        );

        final nonForceResult = TvUpdateCheckResult(
          currentVersion: '2.4.6',
          status: TvUpdateCheckStatus.updateAvailable,
          release: sampleRelease(force: false),
          matchedAsset: sampleAsset(),
          supportedAbis: const ['arm64-v8a'],
        );
        final forceResult = TvUpdateCheckResult(
          currentVersion: '2.4.6',
          status: TvUpdateCheckStatus.updateAvailable,
          release: sampleRelease(force: true),
          matchedAsset: sampleAsset(),
          supportedAbis: const ['arm64-v8a'],
        );

        await tester.pumpWidget(
          buildDialogHostApp(
            child: const Scaffold(body: Center(child: Text('Home'))),
          ),
        );
        await tester.pumpAndSettle();

        final ignoredService = _FakeTvUpdateService(
          ({cancelToken}) async => nonForceResult,
        );
        final ignoredCheck = checkTvUpdatesSilently(service: ignoredService);
        await tester.pump();
        await ignoredCheck;
        await tester.pumpAndSettle();
        expect(ignoredService.checkCount, 1);
        expect(find.text('发现新版本'), findsNothing);

        // Force update overrides ignored version, and single-flight blocks second check.
        final forceService = _FakeTvUpdateService(
          ({cancelToken}) async => forceResult,
        );
        final firstFlow = checkTvUpdatesSilently(service: forceService);
        await tester.pumpAndSettle();
        expect(find.text('发现新版本'), findsOneWidget);

        // Calling silent check again while dialog is open must not stack another check/dialog.
        final secondFlow = checkTvUpdatesSilently(service: forceService);
        await tester.pump();
        expect(forceService.checkCount, 1);
        expect(find.text('发现新版本'), findsOneWidget);

        // Dismiss dialog via Navigator so the flow settles cleanly.
        rootNavigatorKey.currentState!.pop(TvUpdateDialogAction.later);
        await tester.pumpAndSettle();
        await Future.wait([firstFlow, secondFlow]);
        expect(TvUpdateCoordinator.isRunning, isFalse);
      },
    );

    testWidgets(
      'checkTvUpdatesInteractively handles upToDate and incompatibleAbi toasts',
      (tester) async {
        configureTvViewport(tester);
        late BuildContext pageContext;

        await tester.pumpWidget(
          buildDialogHostApp(
            child: Builder(
              builder: (ctx) {
                pageContext = ctx;
                return const Scaffold(body: Center(child: Text('Settings')));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final upToDateService = _FakeTvUpdateService(
          ({cancelToken}) async => const TvUpdateCheckResult(
            currentVersion: '2.4.6',
            status: TvUpdateCheckStatus.upToDate,
          ),
        );
        final upToDateFlow = checkTvUpdatesInteractively(
          pageContext,
          service: upToDateService,
        );
        await tester.pumpAndSettle();
        await upToDateFlow;
        await tester.pumpAndSettle();
        expect(find.text('当前已是最新版本 v2.4.6'), findsOneWidget);

        final incompatibleService = _FakeTvUpdateService(
          ({cancelToken}) async => TvUpdateCheckResult(
            currentVersion: '2.4.6',
            status: TvUpdateCheckStatus.incompatibleAbi,
            release: sampleRelease(),
            supportedAbis: const ['mips64'],
          ),
        );
        final incompatibleFlow = checkTvUpdatesInteractively(
          pageContext,
          service: incompatibleService,
        );
        await tester.pumpAndSettle();
        await incompatibleFlow;
        await tester.pumpAndSettle();
        expect(find.text('未找到适配当前设备架构 (mips64) 的安装包'), findsOneWidget);
      },
    );
  });
}
