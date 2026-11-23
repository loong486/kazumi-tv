import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/modules/danmaku/danmaku_shield_sync.dart';
import 'package:kazumi/repositories/danmaku_shield_repository.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/tv/pages/tv_settings_page.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
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

class _FakeDanmakuShieldRepository implements IDanmakuShieldRepository {
  @override
  Stream<DanmakuShieldChange> get changes => const Stream.empty();

  @override
  Future<String> getDeviceId() async => 'test-device';

  @override
  List<String> getRules() => const [];

  @override
  Future<void> initialize() async {}

  @override
  Future<DanmakuShieldSyncState> mergeSyncState(
    DanmakuShieldSyncState remote,
  ) async =>
      remote;

  @override
  Future<bool> setRule(String rule, {required bool deleted}) async => false;
}

class _RecordingCanvas implements Canvas {
  final List<Color> filledRRectColors = <Color>[];
  final List<Color> strokedRRectColors = <Color>[];
  final List<Color> filledCircleColors = <Color>[];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.style == PaintingStyle.stroke) {
      strokedRRectColors.add(paint.color);
    } else {
      filledRRectColors.add(paint.color);
    }
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    if (paint.style == PaintingStyle.fill) {
      filledCircleColors.add(paint.color);
    }
  }

  @override
  int getSaveCount() => 0;

  @override
  Rect getLocalClipBounds() => Rect.largest;

  @override
  Rect getDestinationClipBounds() => Rect.largest;

  @override
  Float64List getTransform() => Float64List(16);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('TvTheme.buildTheme switchTheme', () {
    test('dark theme resolves selected, unselected, and disabled switch colors',
        () {
      for (final seed in const [
        Colors.green,
        Colors.blue,
        Colors.deepPurple,
        Colors.orange,
      ]) {
        final theme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: seed,
        );
        final scheme = theme.colorScheme;
        final switchTheme = theme.switchTheme;

        expect(
          switchTheme.trackColor?.resolve(const {WidgetState.selected}),
          scheme.primary,
        );
        expect(
          switchTheme.thumbColor?.resolve(const {WidgetState.selected}),
          scheme.onPrimary,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const {WidgetState.selected}),
          Colors.transparent,
        );

        expect(
          switchTheme.trackColor?.resolve(const <WidgetState>{}),
          const Color(0xFF2B3245),
        );
        expect(
          switchTheme.thumbColor?.resolve(const <WidgetState>{}),
          scheme.onSurfaceVariant,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const <WidgetState>{}),
          scheme.outline,
        );

        expect(
          switchTheme.trackColor?.resolve(
            const {WidgetState.disabled, WidgetState.selected},
          ),
          isNot(scheme.primary),
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(
            const {WidgetState.disabled, WidgetState.selected},
          ),
          Colors.transparent,
        );
      }

      final greenTheme = TvTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: Colors.green,
      );
      final blueTheme = TvTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: Colors.blue,
      );
      expect(
        greenTheme.switchTheme.trackColor?.resolve(
          const {WidgetState.selected},
        ),
        isNot(
          blueTheme.switchTheme.trackColor?.resolve(
            const {WidgetState.selected},
          ),
        ),
      );
    });

    test('OLED dark theme preserves switchTheme aligned with OLED colorScheme',
        () {
      for (final seed in const [Colors.green, Colors.blue]) {
        final theme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: seed,
          oledEnhance: true,
        );
        final scheme = theme.colorScheme;
        final switchTheme = theme.switchTheme;

        expect(theme.scaffoldBackgroundColor, Colors.black);
        expect(scheme.onPrimary, Colors.black);
        expect(
          switchTheme.trackColor?.resolve(const {WidgetState.selected}),
          scheme.primary,
        );
        expect(
          switchTheme.thumbColor?.resolve(const {WidgetState.selected}),
          scheme.onPrimary,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const {WidgetState.selected}),
          Colors.transparent,
        );
        expect(
          switchTheme.trackColor?.resolve(const <WidgetState>{}),
          const Color(0xFF2B3245),
        );
        expect(
          switchTheme.thumbColor?.resolve(const <WidgetState>{}),
          scheme.onSurfaceVariant,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const <WidgetState>{}),
          scheme.outline,
        );
      }
    });

    test('light theme resolves selected and unselected switch colors', () {
      for (final seed in const [Colors.green, Colors.blue]) {
        final theme = TvTheme.buildTheme(
          brightness: Brightness.light,
          seedColor: seed,
        );
        final scheme = theme.colorScheme;
        final switchTheme = theme.switchTheme;

        expect(
          switchTheme.trackColor?.resolve(const {WidgetState.selected}),
          scheme.primary,
        );
        expect(
          switchTheme.thumbColor?.resolve(const {WidgetState.selected}),
          scheme.onPrimary,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const {WidgetState.selected}),
          Colors.transparent,
        );
        expect(
          switchTheme.trackColor?.resolve(const <WidgetState>{}),
          scheme.surfaceContainerHighest,
        );
        expect(
          switchTheme.thumbColor?.resolve(const <WidgetState>{}),
          scheme.onSurfaceVariant,
        );
        expect(
          switchTheme.trackOutlineColor?.resolve(const <WidgetState>{}),
          scheme.outline,
        );
      }
    });
  });

  group('TvSettingsPage switch tiles', () {
    late Directory tempDir;
    late PathProviderPlatform originalPathProvider;
    late DanmakuShieldSyncService danmakuShieldSync;

    void configureTvViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget buildSettingsApp(ThemeData theme) {
      return MaterialApp(
        theme: theme,
        builder: (context, appChild) => Actions(
          actions: <Type, Action<Intent>>{
            DirectionalFocusIntent: TvDirectionalFocusAction(),
          },
          child: FocusTraversalGroup(
            policy: TvFocusTraversalPolicy(),
            child: appChild ?? const SizedBox.shrink(),
          ),
        ),
        home: Scaffold(
          body: TvSettingsPage(danmakuShieldSync: danmakuShieldSync),
        ),
      );
    }

    Finder switchForTile(String title) {
      final tile = find.ancestor(
        of: find.text(title),
        matching: find.byType(TvFocusable),
      );
      return find.descendant(of: tile, matching: find.byType(Switch));
    }

    _RecordingCanvas captureSwitchPaint(
      WidgetTester tester,
      Finder switchFinder,
    ) {
      final customPaintFinder = find.descendant(
        of: switchFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      );
      expect(customPaintFinder, findsOneWidget);
      final customPaint = tester.widget<CustomPaint>(customPaintFinder);
      final renderBox = tester.renderObject<RenderBox>(customPaintFinder);
      final canvas = _RecordingCanvas();
      customPaint.painter!.paint(canvas, renderBox.size);
      return canvas;
    }

    Future<void> reanchorHiveToRootZone(WidgetTester tester) async {
      // Hive's ReadWriteSync chains `_writeTask` on a Completer created in the
      // caller's Zone. Any write triggered from widget callbacks inside FakeAsync
      // leaves `_writeTask` bound to that test's FakeAsync Zone, which stops
      // draining once the test ends and would deadlock subsequent `setUp`/
      // `Hive.close` writes. Replace `_writeTask` with a `Zone.root` Future
      // while the current FakeAsync Zone can still flush its microtask.
      final future = Zone.root.run(
        () => GStorage.putSetting(SettingsKeys.themeMode, 'dark'),
      );
      await tester.pump();
      await tester.runAsync(() => future);
    }

    Future<void> waitForSwitchValue(
      WidgetTester tester,
      Finder switchFinder,
      bool expected,
    ) async {
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        if (tester.widget<Switch>(switchFinder).value == expected) {
          break;
        }
      }
      await tester.pumpAndSettle();
    }

    setUpAll(() async {
      Logger.level = Level.off;
      tempDir = await Directory.systemTemp.createTemp('kazumi_tv_switch_');
      originalPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TestPathProvider(tempDir.path);
      Hive.init(tempDir.path);
      await GStorage.init();
      danmakuShieldSync = DanmakuShieldSyncService(
        _FakeDanmakuShieldRepository(),
        WebDav(),
      );
    });

    setUp(() async {
      await GStorage.putSetting(SettingsKeys.themeMode, 'dark');
      await GStorage.putSetting(SettingsKeys.themeColor, 'default');
      await GStorage.putSetting(SettingsKeys.oledEnhance, false);
      await GStorage.putSetting(SettingsKeys.playerDisableAnimations, true);
      await GStorage.putSetting(SettingsKeys.showRating, false);
    });

    tearDownAll(() async {
      await danmakuShieldSync.dispose();
      await Hive.close();
      PathProviderPlatform.instance = originalPathProvider;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'ON switch is enabled, paints active primary track, and adapts across themes',
      (tester) async {
        configureTvViewport(tester);

        final blueDarkTheme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: Colors.blue,
        );
        await tester.pumpWidget(buildSettingsApp(blueDarkTheme));
        await tester.pumpAndSettle();

        await tester.tap(find.text('外观与显示'));
        await tester.pumpAndSettle();

        final onSwitchFinder = switchForTile('减少界面过渡动画');
        final offSwitchFinder = switchForTile('在番剧封面显示 Bangumi 评分');
        expect(onSwitchFinder, findsOneWidget);
        expect(offSwitchFinder, findsOneWidget);

        final onSwitch = tester.widget<Switch>(onSwitchFinder);
        final offSwitch = tester.widget<Switch>(offSwitchFinder);
        expect(onSwitch.value, isTrue);
        expect(onSwitch.onChanged, isNotNull);
        expect(offSwitch.value, isFalse);
        expect(offSwitch.onChanged, isNotNull);

        final excludeFocus = tester.widget<ExcludeFocus>(
          find
              .ancestor(
                of: onSwitchFinder,
                matching: find.byType(ExcludeFocus),
              )
              .first,
        );
        expect(excludeFocus.excluding, isTrue);

        final ignorePointer = tester.widget<IgnorePointer>(
          find
              .ancestor(
                of: onSwitchFinder,
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(ignorePointer.ignoring, isTrue);

        final onCanvasDark = captureSwitchPaint(tester, onSwitchFinder);
        expect(onCanvasDark.filledRRectColors, isNotEmpty);
        expect(
          onCanvasDark.filledRRectColors.first.toARGB32(),
          blueDarkTheme.colorScheme.primary.toARGB32(),
        );
        expect(
          onCanvasDark.filledRRectColors.last.toARGB32(),
          blueDarkTheme.colorScheme.onPrimary.toARGB32(),
        );

        final offCanvasDark = captureSwitchPaint(tester, offSwitchFinder);
        expect(offCanvasDark.filledRRectColors, isNotEmpty);
        expect(
          offCanvasDark.filledRRectColors.first.toARGB32(),
          const Color(0xFF2B3245).toARGB32(),
        );

        // Switch theme to OLED dark with green seedColor and verify adaptation.
        final greenOledTheme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: Colors.green,
          oledEnhance: true,
        );
        await tester.pumpWidget(buildSettingsApp(greenOledTheme));
        await tester.pumpAndSettle();

        final onCanvasOled = captureSwitchPaint(tester, onSwitchFinder);
        expect(
          onCanvasOled.filledRRectColors.first.toARGB32(),
          greenOledTheme.colorScheme.primary.toARGB32(),
        );
        expect(
          onCanvasOled.filledRRectColors.last.toARGB32(),
          greenOledTheme.colorScheme.onPrimary.toARGB32(),
        );

        // Switch theme to light with orange seedColor and verify adaptation.
        final orangeLightTheme = TvTheme.buildTheme(
          brightness: Brightness.light,
          seedColor: Colors.orange,
        );
        await tester.pumpWidget(buildSettingsApp(orangeLightTheme));
        await tester.pumpAndSettle();

        final onCanvasLight = captureSwitchPaint(tester, onSwitchFinder);
        expect(
          onCanvasLight.filledRRectColors.first.toARGB32(),
          orangeLightTheme.colorScheme.primary.toARGB32(),
        );
        expect(
          onCanvasLight.filledRRectColors.last.toARGB32(),
          orangeLightTheme.colorScheme.onPrimary.toARGB32(),
        );
      },
    );

    testWidgets(
      'Enter, Select, and tapping directly over Switch each toggle exactly once',
      (tester) async {
        configureTvViewport(tester);

        final theme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: Colors.green,
        );
        await tester.pumpWidget(buildSettingsApp(theme));
        await tester.pumpAndSettle();

        await tester.tap(find.text('外观与显示'));
        await tester.pumpAndSettle();

        const tileTitle = '减少界面过渡动画';
        final tileSwitchFinder = switchForTile(tileTitle);

        var writeCount = 0;
        final sub = GStorage.watchSettings(
          const [SettingsKeys.playerDisableAnimations],
        ).listen((_) => writeCount++);
        addTearDown(sub.cancel);

        // Focus the tile's TvFocusable node.
        Focus.of(tester.element(find.text(tileTitle))).requestFocus();
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(tileSwitchFinder).value, isTrue);

        // Enter toggles once: true -> false.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await waitForSwitchValue(tester, tileSwitchFinder, false);
        expect(writeCount, 1);
        expect(
          GStorage.getSetting(SettingsKeys.playerDisableAnimations),
          isFalse,
        );
        expect(tester.widget<Switch>(tileSwitchFinder).value, isFalse);

        // Select toggles once: false -> true.
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await waitForSwitchValue(tester, tileSwitchFinder, true);
        expect(writeCount, 2);
        expect(
          GStorage.getSetting(SettingsKeys.playerDisableAnimations),
          isTrue,
        );
        expect(tester.widget<Switch>(tileSwitchFinder).value, isTrue);

        // Tapping directly on the Switch center toggles once (no double toggle).
        await tester.tapAt(tester.getCenter(tileSwitchFinder));
        await waitForSwitchValue(tester, tileSwitchFinder, false);
        expect(writeCount, 3);
        expect(
          GStorage.getSetting(SettingsKeys.playerDisableAnimations),
          isFalse,
        );
        expect(tester.widget<Switch>(tileSwitchFinder).value, isFalse);

        await reanchorHiveToRootZone(tester);
      },
    );

    testWidgets(
      'D-pad ArrowUp/ArrowDown moves cleanly between switch tiles without focusing inside Switch',
      (tester) async {
        configureTvViewport(tester);

        final theme = TvTheme.buildTheme(
          brightness: Brightness.dark,
          seedColor: Colors.green,
        );
        await tester.pumpWidget(buildSettingsApp(theme));
        await tester.pumpAndSettle();

        await tester.tap(find.text('外观与显示'));
        await tester.pumpAndSettle();

        const tile1 = 'OLED 纯黑背景';
        const tile2 = '减少界面过渡动画';
        const tile3 = '在番剧封面显示 Bangumi 评分';

        FocusNode nodeFor(String title) =>
            Focus.of(tester.element(find.text(title)));

        void expectFocusedTile(String title) {
          final primary = FocusManager.instance.primaryFocus;
          expect(primary, isNotNull);
          expect(primary, same(nodeFor(title)));
          expect(
            primary!.context?.findAncestorWidgetOfExactType<Switch>(),
            isNull,
          );
        }

        nodeFor(tile1).requestFocus();
        await tester.pumpAndSettle();
        expectFocusedTile(tile1);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expectFocusedTile(tile2);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expectFocusedTile(tile3);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expectFocusedTile(tile2);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expectFocusedTile(tile1);

        // ArrowLeft from detail pane returns to the active category; ArrowRight
        // restores focus into the detail pane.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expectFocusedTile('外观与显示');

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expectFocusedTile(tile1);
      },
    );
  });
}
