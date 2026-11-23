import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/repositories/download_repository.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/download/download_manager.dart';
import 'package:kazumi/services/player/audio_controller.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/pages/tv_video_page.dart';
import 'package:kazumi/tv/player/tv_danmaku_search_dialog.dart';
import 'package:kazumi/tv/player/tv_player_drawer.dart';
import 'package:kazumi/tv/player/tv_player_overlay.dart';
import 'package:kazumi/tv/player/tv_player_remote_controller.dart';
import 'package:kazumi/tv/player/tv_player_seek_hud.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:mobx/mobx.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _TestPathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TestPathProviderPlatform(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  @override
  Future<String?> getTemporaryPath() async => supportPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => supportPath;
}

class _FakeAudioController extends AudioController {
  @override
  Future<void> bindCallbacks({
    required AudioCallback onPlay,
    required AudioCallback onPause,
    required AudioCallback onSkipToNext,
    required AudioCallback onSkipToPrevious,
    required AudioSeekCallback onSeek,
    String? artworkUrl,
  }) async {}

  @override
  Future<void> updateSession({
    required String mediaId,
    required String title,
    String? album,
    String? artist,
    Duration? duration,
    required bool playing,
    required bool loading,
    required bool buffering,
    required bool completed,
    required Duration updatePosition,
    required Duration bufferedPosition,
    required double speed,
    int? queueIndex,
    bool canSkipToNext = false,
    bool canSkipToPrevious = false,
  }) async {}

  @override
  Future<void> deactivate() async {}
}

class _FakePlayerController extends PlayerController {
  _FakePlayerController(
    super.shaderAssetService,
    super.downloadController,
    super.audioController,
  );

  int playOrPauseCalls = 0;
  int seekCalls = 0;
  int beginShutdownCalls = 0;

  @override
  Future<void> playOrPause() async {
    playOrPauseCalls++;
    runInAction(() => playback.playing = !playback.playing);
  }

  @override
  Future<void> seek(Duration duration, {bool enableSync = true}) async {
    seekCalls++;
    runInAction(() => playback.currentPosition = duration);
  }

  @override
  Future<void> seekBy(Duration offset, {bool enableSync = true}) async {
    seekCalls++;
  }

  @override
  Future<void> setPlaybackSpeed(double playerSpeed) async {
    runInAction(() => playback.playerSpeed = playerSpeed);
  }

  @override
  void beginShutdown() {
    beginShutdownCalls++;
  }
}

class _FakeVideoPageController extends VideoPageController {
  _FakeVideoPageController(
    super.historyController,
    super.downloadRepository,
    super.downloadManager,
  );

  final Observable<bool> _fakeLoading = Observable<bool>(true);
  final Observable<String?> _fakeError = Observable<String?>(null);
  Completer<void>? pendingEpisodeLoad;

  @override
  bool get loading => _fakeLoading.value;

  @override
  String? get errorMessage => _fakeError.value;

  void setLoading(bool value) {
    runInAction(() => _fakeLoading.value = value);
  }

  void setError(String? value) {
    runInAction(() => _fakeError.value = value);
  }

  @override
  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    runInAction(() {
      selectedEpisode = VideoEpisodeSelection(episode: episode, road: currentRoad);
      _fakeLoading.value = true;
      _fakeError.value = null;
    });
    if (pendingEpisodeLoad != null) {
      await pendingEpisodeLoad!.future;
    }
    runInAction(() {
      _fakeLoading.value = false;
      playerController.playback.loading = false;
      playerController.playback.duration = const Duration(minutes: 24);
      playerController.playback.currentPosition = const Duration(minutes: 1);
      playerController.playback.playing = true;
    });
  }
}

BangumiItem _testBangumi() => BangumiItem(
      id: 1001,
      type: 2,
      name: 'Test Bangumi',
      nameCn: '测试番剧',
      summary: 'Summary',
      airDate: '2026-01-01',
      airWeekday: 1,
      rank: 1,
      images: const {'large': ''},
      tags: const [],
      alias: const [],
      ratingScore: 8.5,
      votes: 10,
      votesCount: const [],
      info: '',
    );

OnlineVideoPlaybackArgs _testPlaybackArgs({int roadCount = 2}) {
  return OnlineVideoPlaybackArgs(
    bangumiItem: _testBangumi(),
    plugin: Plugin.fromJson({'name': 'DemoSource'}),
    title: '测试番剧',
    src: 'https://example.com/anime',
    roads: [
      for (var r = 0; r < roadCount; r++)
        Road(
          name: '线路 ${r + 1}',
          data: ['/ep1', '/ep2', '/ep3', '/ep4', '/ep5'],
          identifier: ['第1集', '第2集', '第3集', '第4集', '第5集'],
        ),
    ],
  );
}

void main() {
  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUpAll(() async {
    originalPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp('kazumi_tv_player_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir.path);
    Hive.init(tempDir.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPathProvider;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('TvPlayerRemoteController', () {
    test('showOsd transitions to osd and auto-hides back to idle', () async {
      final controller = TvPlayerRemoteController(
        osdAutoHideDelay: const Duration(milliseconds: 30),
      );
      addTearDown(controller.dispose);

      final modes = <TvPlayerUiMode>[];
      controller.addListener(() => modes.add(controller.mode));

      expect(controller.mode, TvPlayerUiMode.idle);
      expect(controller.isSeeking, isFalse);

      controller.showOsd();
      expect(controller.mode, TvPlayerUiMode.osd);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.mode, TvPlayerUiMode.idle);
      expect(modes, [TvPlayerUiMode.osd, TvPlayerUiMode.idle]);
    });

    test('openDrawer switches mode, cancels osd hide, and clamps tab index', () async {
      final controller = TvPlayerRemoteController(
        osdAutoHideDelay: const Duration(milliseconds: 25),
      );
      addTearDown(controller.dispose);

      controller.showOsd();
      controller.openDrawer(tabIndex: 1);
      expect(controller.mode, TvPlayerUiMode.drawer);
      expect(controller.drawerTabIndex, 1);

      await Future<void>.delayed(const Duration(milliseconds: 45));
      expect(controller.mode, TvPlayerUiMode.drawer);

      controller.setDrawerTab(-3);
      expect(controller.drawerTabIndex, 0);

      controller.setDrawerTab(9);
      expect(controller.drawerTabIndex, 2);

      controller.closeDrawer();
      expect(controller.mode, TvPlayerUiMode.idle);
    });

    test('stepSeek accumulates, clamps bounds, and commits once on debounce', () async {
      final controller = TvPlayerRemoteController(
        seekDebounceDelay: const Duration(milliseconds: 40),
      );
      addTearDown(controller.dispose);

      final committed = <Duration>[];
      const total = Duration(seconds: 120);

      controller.stepSeek(
        currentPosition: const Duration(seconds: 30),
        duration: total,
        delta: const Duration(seconds: 10),
        onCommitSeek: committed.add,
      );
      expect(controller.isSeeking, isTrue);
      expect(controller.seekStartPosition, const Duration(seconds: 30));
      expect(controller.pendingSeekPosition, const Duration(seconds: 40));

      controller.stepSeek(
        currentPosition: const Duration(seconds: 30),
        duration: total,
        delta: const Duration(seconds: 15),
        onCommitSeek: committed.add,
      );
      expect(controller.pendingSeekPosition, const Duration(seconds: 55));

      // Upper clamp test before commit.
      controller.stepSeek(
        currentPosition: const Duration(seconds: 30),
        duration: total,
        delta: const Duration(seconds: 200),
        onCommitSeek: committed.add,
      );
      expect(controller.pendingSeekPosition, total);
      expect(committed, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(committed, [total]);
      expect(controller.isSeeking, isFalse);
      expect(controller.pendingSeekPosition, isNull);

      // Lower clamp to zero + cancelPendingSeek test.
      controller.stepSeek(
        currentPosition: const Duration(seconds: 5),
        duration: total,
        delta: const Duration(seconds: -20),
        onCommitSeek: committed.add,
      );
      expect(controller.pendingSeekPosition, Duration.zero);
      controller.cancelPendingSeek();
      expect(controller.isSeeking, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(committed, [total]);
    });

    test('handleBack closes Drawer -> OSD -> 2s double-back exit', () {
      var now = DateTime(2026, 11, 23, 4, 0, 0);
      final controller = TvPlayerRemoteController(
        doubleBackWindow: const Duration(seconds: 2),
        nowProvider: () => now,
      );
      addTearDown(controller.dispose);

      var promptCount = 0;

      // Drawer open -> closes drawer only.
      controller.openDrawer(tabIndex: 0);
      expect(
        controller.handleBack(onFirstBackPrompt: () => promptCount++),
        isFalse,
      );
      expect(controller.mode, TvPlayerUiMode.idle);
      expect(promptCount, 0);

      // OSD visible -> hides OSD only.
      controller.showOsd(autoHide: false);
      expect(
        controller.handleBack(onFirstBackPrompt: () => promptCount++),
        isFalse,
      );
      expect(controller.mode, TvPlayerUiMode.idle);
      expect(promptCount, 0);

      // Idle first Back -> prompts user, does not exit.
      expect(
        controller.handleBack(onFirstBackPrompt: () => promptCount++),
        isFalse,
      );
      expect(promptCount, 1);

      // Back after doubleBackWindow expired -> re-prompts.
      now = now.add(const Duration(seconds: 3));
      expect(
        controller.handleBack(onFirstBackPrompt: () => promptCount++),
        isFalse,
      );
      expect(promptCount, 2);

      // Second Back within window -> returns true to exit player.
      now = now.add(const Duration(milliseconds: 800));
      expect(
        controller.handleBack(onFirstBackPrompt: () => promptCount++),
        isTrue,
      );
      expect(promptCount, 2);
    });
  });

  group('TvPlayerOverlay', () {
    testWidgets(
      'ArrowUp/ArrowDown navigates focus cleanly between play/pause and seekbar without calling onOpenDrawer',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 720);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        var openDrawerCount = 0;
        var userActivityCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TvPlayerOverlay(
                title: 'Test Anime',
                subtitle: '第 1 集',
                pluginName: 'DemoSource',
                position: const Duration(seconds: 30),
                duration: const Duration(minutes: 4),
                buffered: const Duration(minutes: 1),
                playing: true,
                danmakuOn: true,
                playbackSpeed: 1.0,
                aspectRatioLabel: '自动',
                skipOpSeconds: 90,
                seekStepSeconds: 10,
                canPrevEpisode: false,
                canNextEpisode: true,
                onUserActivity: () => userActivityCount++,
                onBack: () {},
                onPlayPause: () {},
                onSeek: (_) {},
                onPrevEpisode: () {},
                onNextEpisode: () {},
                onSkipOp: () {},
                onToggleDanmaku: () {},
                onCycleSpeed: () {},
                onCycleAspectRatio: () {},
                onOpenDrawer: () => openDrawerCount++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final playPauseFocus = Focus.of(tester.element(find.text('暂停')));
        final seekbarFocus = Focus.of(tester.element(find.text('00:30')));

        expect(playPauseFocus.hasPrimaryFocus, isTrue);
        expect(seekbarFocus.hasPrimaryFocus, isFalse);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(seekbarFocus.hasPrimaryFocus, isTrue);
        expect(playPauseFocus.hasPrimaryFocus, isFalse);
        expect(openDrawerCount, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(playPauseFocus.hasPrimaryFocus, isTrue);
        expect(seekbarFocus.hasPrimaryFocus, isFalse);
        expect(openDrawerCount, 0);

        // Pressing ArrowDown again at the bottom row must not open the drawer.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();

        expect(openDrawerCount, 0);
        expect(userActivityCount, greaterThanOrEqualTo(3));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TvVideoPage controls & Back deduplication', () {
    void configureTvViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    ({
      _FakePlayerController player,
      _FakeVideoPageController video,
      HistoryController history,
      MyController my,
    }) createControllers() {
      final historyRepo = HistoryRepository();
      final downloadRepo = DownloadRepository();
      final downloadManager = DownloadManager();
      final shieldRepo = DanmakuShieldRepository();
      final historyController = HistoryController(historyRepo);
      final myController = MyController(historyRepo, downloadRepo, shieldRepo);
      final downloadController = DownloadController(
        downloadRepo,
        downloadManager,
        PluginsController(),
      );
      final player = _FakePlayerController(
        ShaderAssetService(),
        downloadController,
        _FakeAudioController(),
      );
      final video = _FakeVideoPageController(
        historyController,
        downloadRepo,
        downloadManager,
      );
      return (
        player: player,
        video: video,
        history: historyController,
        my: myController,
      );
    }

    Future<void> pumpFrames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }

    var keySeq = 1;
    Future<void> sendGoBackKey(WidgetTester tester) async {
      const goBackPhysical = 0x000c0224;
      final goBackLogical = LogicalKeyboardKey.goBack.keyId;
      final downMs = keySeq++ * 100;
      tester.platformDispatcher.onKeyData?.call(
        ui.KeyData(
          type: ui.KeyEventType.down,
          physical: goBackPhysical,
          logical: goBackLogical,
          timeStamp: Duration(milliseconds: downMs),
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
          timeStamp: Duration(milliseconds: downMs + 20),
          character: null,
          synthesized: false,
        ),
      );
      await tester.pump();
    }

    Future<void> pumpVideoRoute(
      WidgetTester tester, {
      required OnlineVideoPlaybackArgs args,
      required _FakePlayerController player,
      required _FakeVideoPageController video,
      required HistoryController history,
      required MyController my,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          scaffoldMessengerKey: rootScaffoldMessengerKey,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TvVideoPage(
                          args: args,
                          playerController: player,
                          videoPageController: video,
                          historyController: history,
                          myController: my,
                        ),
                      ),
                    );
                  },
                  child: const Text('Launch Player'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Launch Player'));
      await pumpFrames(tester);
    }

    testWidgets(
      'restores root focus after loading overlay ends and after 5s OSD auto-hide',
      (tester) async {
        configureTvViewport(tester);
        final c = createControllers();
        final loadGate = Completer<void>();
        c.video.pendingEpisodeLoad = loadGate;

        await pumpVideoRoute(
          tester,
          args: _testPlaybackArgs(),
          player: c.player,
          video: c.video,
          history: c.history,
          my: c.my,
        );

        // Loading overlay is visible with 取消并返回 focused.
        expect(find.text('取消并返回'), findsOneWidget);
        expect(c.player.playOrPauseCalls, 0);

        // Finish loading -> status overlay unmounts and restores _rootFocus.
        loadGate.complete();
        await pumpFrames(tester);
        expect(find.text('取消并返回'), findsNothing);

        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(c.player.playOrPauseCalls, 1);

        // Open OSD via ArrowDown -> OSD buttons take focus.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await pumpFrames(tester);
        expect(find.byType(TvPlayerOverlay), findsOneWidget);

        // Wait 5s for OSD timer to auto-hide back to idle -> restores _rootFocus.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        await tester.pump();
        expect(find.byType(TvPlayerOverlay), findsNothing);

        // Fullscreen D-pad controls must still work immediately after OSD auto-hide.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pump();
        expect(c.player.playOrPauseCalls, 2);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(find.byType(TvPlayerSeekHud), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 400));
        expect(c.player.seekCalls, 1);

        // Clean unmount cancels timers cleanly.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Back deduplicates goBack + PopScope across Drawer -> OSD -> 2s double-back exit',
      (tester) async {
        configureTvViewport(tester);
        final c = createControllers();

        await pumpVideoRoute(
          tester,
          args: _testPlaybackArgs(),
          player: c.player,
          video: c.video,
          history: c.history,
          my: c.my,
        );
        expect(find.byType(TvVideoPage), findsOneWidget);

        // Open drawer via Menu key and verify TvAxisClipRect wraps drawer scrollables.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await pumpFrames(tester);
        expect(find.byType(TvPlayerDrawer), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(TvPlayerDrawer),
            matching: find.byType(TvAxisClipRect),
          ),
          findsNWidgets(2),
        );

        // Android TV Back fires both goBack key event and PopScope popRoute;
        // must only close the drawer without exiting or prompting exit.
        await sendGoBackKey(tester);
        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        expect(find.byType(TvPlayerDrawer), findsNothing);
        expect(find.byType(TvVideoPage), findsOneWidget);
        expect(find.text('再按一次返回键退出播放'), findsNothing);
        expect(c.player.beginShutdownCalls, 0);

        // Open OSD via ArrowUp, then press Back (goBack + handlePopRoute) -> hides OSD only.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await pumpFrames(tester);
        expect(find.byType(TvPlayerOverlay), findsOneWidget);

        await sendGoBackKey(tester);
        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        expect(find.byType(TvPlayerOverlay), findsNothing);
        expect(find.byType(TvVideoPage), findsOneWidget);
        expect(find.text('再按一次返回键退出播放'), findsNothing);
        expect(c.player.beginShutdownCalls, 0);

        // Idle mode: consecutive Android TV physical Back (goBack + handlePopRoute)
        // prompts once on 1st press and exits on 2nd press within 2s.
        await sendGoBackKey(tester);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('再按一次返回键退出播放'), findsOneWidget);
        expect(find.byType(TvVideoPage), findsOneWidget);
        expect(c.player.beginShutdownCalls, 0);

        await sendGoBackKey(tester);
        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        expect(find.byType(TvVideoPage), findsNothing);
        expect(find.text('Launch Player'), findsOneWidget);
        expect(c.player.beginShutdownCalls, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'keyboard Escape + immediate handlePopRoute deduplicates (<250ms) before 2nd Escape exits',
      (tester) async {
        configureTvViewport(tester);
        final c = createControllers();

        await pumpVideoRoute(
          tester,
          args: _testPlaybackArgs(),
          player: c.player,
          video: c.video,
          history: c.history,
          my: c.my,
        );
        expect(find.byType(TvVideoPage), findsOneWidget);

        // Keyboard Escape followed immediately by handlePopRoute must deduplicate
        // (< 250ms) and only show the prompt without exiting.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.text('再按一次返回键退出播放'), findsOneWidget);
        expect(find.byType(TvVideoPage), findsOneWidget);
        expect(c.player.beginShutdownCalls, 0);

        // Second Escape within 2s double-back window exits cleanly.
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await pumpFrames(tester);
        expect(find.byType(TvVideoPage), findsNothing);
        expect(find.text('Launch Player'), findsOneWidget);
        expect(c.player.beginShutdownCalls, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TvPlayerDrawer and TvDanmakuSearchDialog wrap scrollables in TvAxisClipRect with Clip.none',
      (tester) async {
        configureTvViewport(tester);
        final c = createControllers();
        c.video.applyPlaybackArgs(_testPlaybackArgs(roadCount: 3));
        c.video.setLoading(false);

        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            home: Scaffold(
              body: Stack(
                children: [
                  TvPlayerDrawer(
                    initialTab: 0,
                    videoPageController: c.video,
                    playerController: c.player,
                    onTabChanged: (_) {},
                    onClose: () {},
                    onSelectEpisode: (_, _) {},
                    onToggleDanmaku: () {},
                    onSearchDanmaku: () {},
                    onDanmakuStyleChanged: () {},
                    onChangeSpeed: (_) {},
                    onChangeAspectRatio: (_) {},
                    onChangeSuperResolution: (_) {},
                    onReloadEpisode: () {},
                    showDebugLog: false,
                    onToggleDebugLog: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Episodes tab has horizontal road list + vertical episode grid inside TvAxisClipRect.
        expect(find.byType(TvAxisClipRect), findsNWidgets(2));
        final roadListView = tester.widget<ListView>(find.byType(ListView));
        expect(roadListView.clipBehavior, Clip.none);
        final episodeGrid = tester.widget<GridView>(find.byType(GridView));
        expect(episodeGrid.clipBehavior, Clip.none);

        // Switch to Danmaku tab and verify TvAxisClipRect + Clip.none.
        await tester.tap(find.text('弹幕'));
        await tester.pumpAndSettle();
        expect(find.byType(TvAxisClipRect), findsOneWidget);
        expect(tester.widget<ListView>(find.byType(ListView)).clipBehavior, Clip.none);

        // Switch to Playback tab and verify TvAxisClipRect + Clip.none.
        await tester.tap(find.text('播放'));
        await tester.pumpAndSettle();
        expect(find.byType(TvAxisClipRect), findsOneWidget);
        expect(tester.widget<ListView>(find.byType(ListView)).clipBehavior, Clip.none);

        // Open TvDanmakuSearchDialog (including compact IME viewInsets) and verify
        // TvAxisClipRect wraps its scrollable body without vertical overflow.
        tester.view.physicalSize = const Size(960, 540);
        tester.view.devicePixelRatio = 1.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: 250);
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: rootNavigatorKey,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showTvDanmakuSearchDialog(
                      context,
                      bangumiId: 1001,
                      initialKeyword: '测试',
                      danmakuController: c.player.danmaku,
                      onBeforeApply: () {},
                    ),
                    child: const Text('Open Danmaku Search'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Danmaku Search'));
        await tester.pumpAndSettle();
        expect(find.text('手动匹配弹幕源'), findsOneWidget);
        expect(find.byType(TvAxisClipRect), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'closing TvPlayerDrawer on error overlay keeps focus on error action buttons',
      (tester) async {
        configureTvViewport(tester);
        final c = createControllers();
        final loadGate = Completer<void>();
        c.video.pendingEpisodeLoad = loadGate;

        await pumpVideoRoute(
          tester,
          args: _testPlaybackArgs(),
          player: c.player,
          video: c.video,
          history: c.history,
          my: c.my,
        );

        // Transition to error state.
        c.video.setError('解析失败');
        c.video.setLoading(false);
        await pumpFrames(tester);
        expect(find.text('重试本集'), findsOneWidget);
        expect(find.text('切换线路/选集'), findsOneWidget);

        // Open drawer via Menu key, then close via Back -> focus must stay on an error button.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
        await pumpFrames(tester);
        expect(find.byType(TvPlayerDrawer), findsOneWidget);

        await tester.binding.handlePopRoute();
        await pumpFrames(tester);
        expect(find.byType(TvPlayerDrawer), findsNothing);

        final retryFocus = Focus.of(tester.element(find.text('重试本集')));
        final switchFocus = Focus.of(tester.element(find.text('切换线路/选集')));
        expect(
          retryFocus.hasPrimaryFocus || switchFocus.hasPrimaryFocus,
          isTrue,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  });
}
