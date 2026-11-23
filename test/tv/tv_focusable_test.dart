import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

void main() {
  group('TvKeys', () {
    test('recognizes select keys', () {
      expect(TvKeys.isSelectKey(LogicalKeyboardKey.select), isTrue);
      expect(TvKeys.isSelectKey(LogicalKeyboardKey.enter), isTrue);
      expect(TvKeys.isSelectKey(LogicalKeyboardKey.numpadEnter), isTrue);
      expect(TvKeys.isSelectKey(LogicalKeyboardKey.gameButtonA), isTrue);
      expect(TvKeys.isSelectKey(LogicalKeyboardKey.arrowRight), isFalse);
    });

    test('recognizes back keys', () {
      expect(TvKeys.isBackKey(LogicalKeyboardKey.goBack), isTrue);
      expect(TvKeys.isBackKey(LogicalKeyboardKey.escape), isTrue);
      expect(TvKeys.isBackKey(LogicalKeyboardKey.browserBack), isTrue);
      expect(TvKeys.isBackKey(LogicalKeyboardKey.gameButtonB), isTrue);
      expect(TvKeys.isBackKey(LogicalKeyboardKey.enter), isFalse);
    });

    test('recognizes keyboard-only back keys separately from goBack', () {
      expect(TvKeys.isKeyboardBackKey(LogicalKeyboardKey.escape), isTrue);
      expect(TvKeys.isKeyboardBackKey(LogicalKeyboardKey.gameButtonB), isTrue);
      expect(TvKeys.isKeyboardBackKey(LogicalKeyboardKey.goBack), isFalse);
      expect(
        TvKeys.isKeyboardBackKey(LogicalKeyboardKey.browserBack),
        isFalse,
      );
      expect(TvKeys.isKeyboardBackKey(LogicalKeyboardKey.enter), isFalse);
    });

    test('recognizes menu keys', () {
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.contextMenu), isTrue);
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.info), isTrue);
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.f1), isTrue);
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.keyM), isTrue);
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.gameButtonX), isTrue);
      expect(TvKeys.isMenuKey(LogicalKeyboardKey.select), isFalse);
    });

    test('recognizes directional and media transport keys', () {
      expect(TvKeys.isLeftKey(LogicalKeyboardKey.arrowLeft), isTrue);
      expect(TvKeys.isRightKey(LogicalKeyboardKey.arrowRight), isTrue);
      expect(TvKeys.isUpKey(LogicalKeyboardKey.arrowUp), isTrue);
      expect(TvKeys.isDownKey(LogicalKeyboardKey.arrowDown), isTrue);

      expect(TvKeys.isPlayPauseKey(LogicalKeyboardKey.mediaPlayPause), isTrue);
      expect(TvKeys.isPlayPauseKey(LogicalKeyboardKey.mediaPlay), isTrue);
      expect(TvKeys.isPlayPauseKey(LogicalKeyboardKey.mediaPause), isTrue);
      expect(TvKeys.isPlayPauseKey(LogicalKeyboardKey.space), isTrue);

      expect(TvKeys.isRewindKey(LogicalKeyboardKey.mediaRewind), isTrue);
      expect(TvKeys.isRewindKey(LogicalKeyboardKey.mediaSkipBackward), isTrue);
      expect(
        TvKeys.isFastForwardKey(LogicalKeyboardKey.mediaFastForward),
        isTrue,
      );
      expect(
        TvKeys.isFastForwardKey(LogicalKeyboardKey.mediaSkipForward),
        isTrue,
      );
      expect(
        TvKeys.isPrevEpisodeKey(LogicalKeyboardKey.mediaTrackPrevious),
        isTrue,
      );
      expect(TvKeys.isPrevEpisodeKey(LogicalKeyboardKey.channelUp), isTrue);
      expect(
        TvKeys.isNextEpisodeKey(LogicalKeyboardKey.mediaTrackNext),
        isTrue,
      );
      expect(TvKeys.isNextEpisodeKey(LogicalKeyboardKey.channelDown), isTrue);
    });
  });

  group('TvFocusable', () {
    void configureTvViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('activates onSelect on select and enter keys when focused', (
      tester,
    ) async {
      configureTvViewport(tester);
      var selectCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusable(
                autofocus: true,
                onSelect: () => selectCount++,
                child: const Text('Card'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(selectCount, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(selectCount, 2);
    });

    testWidgets('invokes onLongSelect on menu key and >= 500ms hold', (
      tester,
    ) async {
      configureTvViewport(tester);
      var selectCount = 0;
      var longSelectCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TvFocusable(
                autofocus: true,
                onSelect: () => selectCount++,
                onLongSelect: () => longSelectCount++,
                child: const Text('Card'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Context menu key triggers onLongSelect directly.
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(longSelectCount, 1);
      expect(selectCount, 0);

      // Quick tap of select key triggers onSelect on release.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(selectCount, 1);
      expect(longSelectCount, 1);

      // Holding select key >= 500ms triggers onLongSelect once and not onSelect.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 550));
      expect(longSelectCount, 2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(selectCount, 1);
      expect(longSelectCount, 2);
    });

    testWidgets('ignores input when disabled and supports pointer tap', (
      tester,
    ) async {
      configureTvViewport(tester);
      var disabledSelects = 0;
      var enabledSelects = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                TvFocusable(
                  enabled: false,
                  onSelect: () => disabledSelects++,
                  child: const Text('Disabled'),
                ),
                TvFocusable(
                  autofocus: true,
                  onSelect: () => enabledSelects++,
                  child: const Text('Enabled'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Disabled'));
      await tester.pump();
      expect(disabledSelects, 0);

      await tester.tap(find.text('Enabled'));
      await tester.pump();
      expect(enabledSelects, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(enabledSelects, 2);
    });

    testWidgets(
      'paints outer glow in decoration and white ring in foregroundDecoration',
      (tester) async {
        configureTvViewport(tester);
        final focusA = FocusNode(debugLabel: 'A');
        final focusB = FocusNode(debugLabel: 'B');
        addTearDown(focusA.dispose);
        addTearDown(focusB.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Row(
                children: [
                  TvFocusable(
                    focusNode: focusA,
                    autofocus: true,
                    borderRadius: 12,
                    focusBorderColor: Colors.teal,
                    onSelect: () {},
                    child: const SizedBox(
                      width: 100,
                      height: 44,
                      child: Center(child: Text('A')),
                    ),
                  ),
                  TvFocusable(
                    focusNode: focusB,
                    borderRadius: 12,
                    onSelect: () {},
                    child: const SizedBox(
                      width: 100,
                      height: 44,
                      child: Center(child: Text('B')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final containerFinder = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is TvFocusable && w.focusNode == focusA,
          ),
          matching: find.byType(AnimatedContainer),
        );
        final focusedContainer = tester.widget<AnimatedContainer>(containerFinder);
        final focusedDec = focusedContainer.decoration! as BoxDecoration;
        final focusedFg =
            focusedContainer.foregroundDecoration! as BoxDecoration;
        expect(focusedDec.border, isNull);
        expect(focusedDec.boxShadow, hasLength(2));
        expect(TvLayout.focusGlowBlur, 10.0);
        expect(TvLayout.focusGlowSpread, 0.5);
        expect(
          focusedDec.boxShadow!.first.color,
          Colors.teal.withValues(alpha: 0.48),
        );
        expect(focusedDec.boxShadow!.first.blurRadius, 10.0);
        expect(focusedDec.boxShadow!.first.spreadRadius, 0.5);
        expect(focusedFg.border, isNotNull);
        expect(
          (focusedFg.border! as Border).top.width,
          TvLayout.focusBorderWidth,
        );
        expect(
          (focusedFg.border! as Border).top.color,
          Colors.white.withValues(alpha: 0.95),
        );

        final unfocusedContainerFinder = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is TvFocusable && w.focusNode == focusB,
          ),
          matching: find.byType(AnimatedContainer),
        );
        final unfocusedContainer =
            tester.widget<AnimatedContainer>(unfocusedContainerFinder);
        final unfocusedDec = unfocusedContainer.decoration! as BoxDecoration;
        expect(unfocusedDec.boxShadow, isEmpty);
        expect(unfocusedContainer.foregroundDecoration, isNull);
      },
    );

    testWidgets(
      'only scrolls when focused item plus 18px glow margin exceeds viewport',
      (tester) async {
        configureTvViewport(tester);
        final scrollController = ScrollController();
        final nodes = List.generate(10, (i) => FocusNode(debugLabel: 'Item$i'));
        addTearDown(scrollController.dispose);
        for (final node in nodes) {
          addTearDown(node.dispose);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                width: 400,
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  itemCount: nodes.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, index) => TvFocusable(
                    focusNode: nodes[index],
                    autofocus: index == 0,
                    onSelect: () {},
                    child: SizedBox(
                      height: 60,
                      child: Text('Item $index'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(scrollController.offset, 0.0);

        // Item 1 spans y=96..156; with 18px glow margin (78..174) it is well
        // inside [0, 300], so focusing it must not scroll.
        nodes[1].requestFocus();
        await tester.pumpAndSettle();
        expect(scrollController.offset, 0.0);

        // Item 4 starts at y=312 (outside 300px viewport). Post-frame scroll
        // brings it + 18px glow margin into view at the bottom edge (not 0.5).
        nodes[4].requestFocus();
        await tester.pumpAndSettle();
        // Item 4 bottom = 24 + 4*(60+12) + 60 = 372; + 18 margin - 300 = 90.
        expect(scrollController.offset, closeTo(90.0, 1.0));
      },
    );
  });

  group('TvFocusTraversalPolicy and TvDirectionalFocusAction', () {
    void configureTvViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'top-right button -> left-aligned chip row -> 3-col grid never skips middle row and stops at edges',
      (tester) async {
        configureTvViewport(tester);
        final topRightNode = FocusNode(debugLabel: 'TopRight');
        final chip0Node = FocusNode(debugLabel: 'Chip0');
        final chip1Node = FocusNode(debugLabel: 'Chip1');
        final gridNodes =
            List.generate(6, (i) => FocusNode(debugLabel: 'Grid$i'));
        addTearDown(topRightNode.dispose);
        addTearDown(chip0Node.dispose);
        addTearDown(chip1Node.dispose);
        for (final node in gridNodes) {
          addTearDown(node.dispose);
        }

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Actions(
              actions: <Type, Action<Intent>>{
                DirectionalFocusIntent: TvDirectionalFocusAction(),
              },
              child: FocusTraversalGroup(
                policy: TvFocusTraversalPolicy(),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 20, 36, 12),
                    child: Row(
                      children: [
                        const Text('Header'),
                        const Spacer(),
                        TvIconButton(
                          focusNode: topRightNode,
                          autofocus: true,
                          icon: Icons.refresh_rounded,
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        TvChip(
                          focusNode: chip0Node,
                          label: '全部',
                          selected: true,
                          onSelect: () {},
                        ),
                        const SizedBox(width: 12),
                        TvChip(
                          focusNode: chip1Node,
                          label: '热血',
                          selected: false,
                          onSelect: () {},
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(36, 18, 36, 32),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: 18,
                        mainAxisExtent: 120,
                      ),
                      itemCount: 6,
                      itemBuilder: (_, index) => TvFocusable(
                        focusNode: gridNodes[index],
                        onSelect: () {},
                        child: Center(child: Text('Card $index')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(topRightNode.hasFocus, isTrue);

        // Pressing Up on top-most item must NOT wrap to bottom grid.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(topRightNode.hasFocus, isTrue);

        // Pressing Down from top-right button must land on the middle chip row
        // (closest chip to topRight center is chip1), NOT skip to grid col 3.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(chip1Node.hasFocus, isTrue);

        // Pressing Down from chip1 enters grid row 0.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(
          gridNodes[0].hasFocus || gridNodes[1].hasFocus || gridNodes[2].hasFocus,
          isTrue,
        );

        // Focus grid col 3 (index 2); pressing Up must return to middle chip row
        // (chip1), NOT skip directly to top-right button.
        gridNodes[2].requestFocus();
        await tester.pumpAndSettle();
        expect(gridNodes[2].hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
        expect(chip1Node.hasFocus, isTrue);

        // Inside grid: col 2 row 0 -> Down -> col 2 row 1; Down again stops (no wrap).
        gridNodes[1].requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(gridNodes[4].hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(gridNodes[4].hasFocus, isTrue);

        // Left/right boundaries do not wrap.
        gridNodes[0].requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(gridNodes[0].hasFocus, isTrue);

        gridNodes[2].requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(gridNodes[2].hasFocus, isTrue);
      },
    );

    testWidgets(
      'keeps KeyDownEvent steps instantaneous and throttles held KeyRepeatEvent steps',
      (tester) async {
        configureTvViewport(tester);
        final nodes = List.generate(5, (i) => FocusNode(debugLabel: 'Row$i'));
        for (final node in nodes) {
          addTearDown(node.dispose);
        }

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => Actions(
              actions: <Type, Action<Intent>>{
                DirectionalFocusIntent: TvDirectionalFocusAction(),
              },
              child: FocusTraversalGroup(
                policy: TvFocusTraversalPolicy(),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
            home: Scaffold(
              body: Column(
                children: [
                  for (var i = 0; i < nodes.length; i++)
                    TvSecondaryButton(
                      focusNode: nodes[i],
                      autofocus: i == 0,
                      label: 'Row $i',
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(nodes[0].hasFocus, isTrue);

        // Rapid fresh KeyDownEvent steps via sendKeyEvent never drop.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(nodes[1].hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        expect(nodes[2].hasFocus, isTrue);

        // Reset back to Row 0 to verify repeat throttling timestamps.
        nodes[0].requestFocus();
        await tester.pumpAndSettle();

        const arrowDownPhysical = 0x00070051;
        final arrowDownLogical = LogicalKeyboardKey.arrowDown.keyId;

        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.down,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1000),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
        expect(nodes[1].hasFocus, isTrue);

        // Repeat at +120ms (< 240ms initial delay) is throttled.
        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.repeat,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1120),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
        expect(nodes[1].hasFocus, isTrue);

        // Repeat at +240ms (>= 240ms) advances focus.
        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.repeat,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1240),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
        expect(nodes[2].hasFocus, isTrue);

        // Subsequent repeat at +60ms (< 95ms) is throttled.
        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.repeat,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1300),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
        expect(nodes[2].hasFocus, isTrue);

        // Subsequent repeat at +100ms (>= 95ms) advances focus.
        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.repeat,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1340),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
        expect(nodes[3].hasFocus, isTrue);

        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.up,
            physical: arrowDownPhysical,
            logical: arrowDownLogical,
            timeStamp: const Duration(milliseconds: 1360),
            character: null,
            synthesized: true,
          ),
        );
        await tester.pump();
      },
    );
  });

  group('TvDialog', () {
    void configureTvViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets(
      'showTvInputDialog moves focus from TextField to action buttons on ArrowDown',
      (tester) async {
        configureTvViewport(tester);
        String? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Open',
                    onPressed: () async {
                      dialogResult = await showTvInputDialog(
                        context,
                        title: '输入关键词',
                        initialValue: 'abc',
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

        expect(find.byType(TextField), findsOneWidget);
        expect(FocusManager.instance.primaryFocus, isNotNull);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        // Step through the dialog pop transition frames to verify the
        // controller is not disposed before the exit animation finishes.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(dialogResult, 'abc');
      },
    );

    testWidgets(
      'showTvChoiceDialog navigates options with ArrowDown and selects value',
      (tester) async {
        configureTvViewport(tester);
        String? selected;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Choose',
                    onPressed: () async {
                      selected = await showTvChoiceDialog<String>(
                        context,
                        title: '选择模式',
                        currentValue: 'a',
                        options: const [
                          TvChoiceOption(value: 'a', label: '选项 A'),
                          TvChoiceOption(value: 'b', label: '选项 B'),
                        ],
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
        expect(find.text('选项 A'), findsOneWidget);
        expect(find.text('选项 B'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();

        expect(selected, 'b');
      },
    );

    testWidgets(
      'showTvChoiceDialog wraps option list in TvAxisClipRect with Clip.none',
      (tester) async {
        configureTvViewport(tester);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TvPrimaryButton(
                    autofocus: true,
                    label: 'Choose',
                    onPressed: () => showTvChoiceDialog<String>(
                      context,
                      title: '选择模式',
                      options: const [
                        TvChoiceOption(value: 'a', label: '选项 A'),
                        TvChoiceOption(value: 'b', label: '选项 B'),
                      ],
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

        final axisClip = tester.widget<TvAxisClipRect>(
          find.byType(TvAxisClipRect),
        );
        expect(axisClip.axis, Axis.vertical);
        final listView = tester.widget<ListView>(find.byType(ListView));
        expect(listView.clipBehavior, Clip.none);
      },
    );

    testWidgets(
      'showTvLoadingDialog handles goBack + handlePopRoute without popping host route',
      (tester) async {
        configureTvViewport(tester);
        final actionCompleter = Completer<String>();
        final cancelToken = RuleCancelToken();
        var hostRoutePopped = false;
        late BuildContext hostContext;

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [KazumiDialog.observer],
            home: Builder(
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

        final loadingFuture = showTvLoadingDialog<String>(
          hostContext,
          message: '正在加载…',
          action: () => actionCompleter.future,
          cancelToken: cancelToken,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('正在加载…'), findsOneWidget);
        expect(KazumiDialog.observer.hasKazumiDialog, isTrue);

        // Simulate Android TV KEYCODE_BACK: KeyDownEvent(goBack) followed by
        // system handlePopRoute(). Only the loading dialog may pop.
        const goBackPhysical = 0x000c0224;
        final goBackLogical = LogicalKeyboardKey.goBack.keyId;
        tester.platformDispatcher.onKeyData?.call(
          ui.KeyData(
            type: ui.KeyEventType.down,
            physical: goBackPhysical,
            logical: goBackLogical,
            timeStamp: const Duration(milliseconds: 100),
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
            timeStamp: const Duration(milliseconds: 120),
            character: null,
            synthesized: false,
          ),
        );
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(cancelToken.isCancelled, isTrue);
        expect(find.text('正在加载…'), findsNothing);
        expect(find.text('Host Page'), findsOneWidget);
        expect(hostRoutePopped, isFalse);

        // showTvLoadingDialog resolves immediately on cancel without waiting
        // for the abandoned action() future, and ignores late errors on it.
        var loadingResolved = false;
        unawaited(loadingFuture.then((_) => loadingResolved = true));
        await tester.pump();
        expect(loadingResolved, isTrue);
        expect(await loadingFuture, isNull);

        actionCompleter.completeError(StateError('abandoned'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('TvAxisClipRect', () {
    testWidgets(
      'clips only along scroll axis and bleeds crossAxisBleed on cross axis',
      (tester) async {
        await tester.pumpWidget(
          const Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: [
                TvAxisClipRect(
                  axis: Axis.horizontal,
                  crossAxisBleed: 36.0,
                  child: SizedBox(width: 200, height: 56),
                ),
                TvAxisClipRect(
                  axis: Axis.vertical,
                  crossAxisBleed: 24.0,
                  child: SizedBox(width: 200, height: 56),
                ),
              ],
            ),
          ),
        );

        final clips = tester.widgetList<ClipRect>(find.byType(ClipRect)).toList();
        expect(clips, hasLength(2));

        final horizClipper = clips[0].clipper!;
        expect(
          horizClipper.getClip(const Size(200, 56)),
          const Rect.fromLTRB(0, -36, 200, 92),
        );

        final vertClipper = clips[1].clipper!;
        expect(
          vertClipper.getClip(const Size(200, 56)),
          const Rect.fromLTRB(-24, 0, 224, 56),
        );

        expect(horizClipper.shouldReclip(horizClipper), isFalse);
        expect(horizClipper.shouldReclip(vertClipper), isTrue);
      },
    );
  });
}
