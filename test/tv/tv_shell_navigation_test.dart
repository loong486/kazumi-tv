import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

void main() {
  void configureTvViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> sendAndroidGoBack(WidgetTester tester, Duration timeStamp) async {
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

  Widget buildTestShell({
    ValueChanged<int>? onDestinationChanged,
    VoidCallback? onExitRequested,
  }) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      home: TvShellPage(
        location: '/popular',
        onDestinationChanged: onDestinationChanged,
        onExitRequested: onExitRequested,
        childBuilder: (context) {
          final shell = TvShellScope.of(context);
          return Center(
            child: TvFocusable(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    TvKeys.isLeftKey(event.logicalKey)) {
                  shell.focusRail();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Content Tab ${shell.currentIndex}'),
              ),
            ),
          );
        },
      ),
    );
  }

  testWidgets(
    'expands rail on left/back, switches tabs on down+select, returns right',
    (tester) async {
      configureTvViewport(tester);
      final selectedTabs = <int>[];

      await tester.pumpWidget(
        buildTestShell(onDestinationChanged: selectedTabs.add),
      );
      await tester.pumpAndSettle();

      // Initially content is focused and the navigation rail is collapsed.
      expect(find.text('Content Tab 0'), findsOneWidget);
      expect(find.text('Kazumi TV'), findsNothing);

      // Left key from content moves focus into the rail and expands labels.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('Kazumi TV'), findsOneWidget);
      expect(find.text('热门'), findsOneWidget);

      // ArrowRight from the rail returns focus to content without switching tab.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('Kazumi TV'), findsNothing);
      expect(selectedTabs, isEmpty);

      // Focus rail again, move Down to Timeline (index 1), and activate Select.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(selectedTabs, [1]);
      expect(find.text('Content Tab 1'), findsOneWidget);
      expect(find.text('Kazumi TV'), findsNothing);
    },
  );

  testWidgets('double-back from rail confirms exit after focusing rail', (
    tester,
  ) async {
    configureTvViewport(tester);
    var exitCalls = 0;

    await tester.pumpWidget(
      buildTestShell(onExitRequested: () => exitCalls++),
    );
    await tester.pumpAndSettle();

    // Back while content has focus moves focus to the rail instead of exiting.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Kazumi TV'), findsOneWidget);
    expect(exitCalls, 0);

    // First Back on the rail shows exit prompt toast.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('再按一次返回键退出 Kazumi TV'), findsOneWidget);
    expect(exitCalls, 0);

    // Second Back within 2s invokes onExitRequested.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exitCalls, 1);
  });

  testWidgets(
    'goBack followed immediately by handlePopRoute from content focuses rail without exit prompt',
    (tester) async {
      configureTvViewport(tester);
      var exitCalls = 0;

      await tester.pumpWidget(
        buildTestShell(onExitRequested: () => exitCalls++),
      );
      await tester.pumpAndSettle();

      // Simulate Android TV KEYCODE_BACK delivering KeyDownEvent(goBack) + popRoute.
      await sendAndroidGoBack(tester, const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Kazumi TV'), findsOneWidget);
      expect(find.text('再按一次返回键退出 Kazumi TV'), findsNothing);
      expect(exitCalls, 0);
    },
  );

  testWidgets(
    'back on non-home rail tab returns to home tab before prompting exit',
    (tester) async {
      configureTvViewport(tester);
      final selectedTabs = <int>[];
      var exitCalls = 0;

      await tester.pumpWidget(
        buildTestShell(
          onDestinationChanged: selectedTabs.add,
          onExitRequested: () => exitCalls++,
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Timeline (tab index 1).
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(selectedTabs, [1]);
      expect(find.text('Content Tab 1'), findsOneWidget);

      // Focus rail from content (e.g. via Android Back).
      await sendAndroidGoBack(tester, const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Kazumi TV'), findsOneWidget);
      expect(find.text('再按一次返回键退出 Kazumi TV'), findsNothing);
      expect(exitCalls, 0);

      // Pressing Back on non-home rail tab returns to Home tab 0 without exit prompt.
      await sendAndroidGoBack(tester, const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(selectedTabs, [1, 0]);
      expect(find.text('Content Tab 0'), findsOneWidget);
      expect(find.text('Kazumi TV'), findsOneWidget);
      expect(find.text('再按一次返回键退出 Kazumi TV'), findsNothing);
      expect(exitCalls, 0);

      // First Back on Home rail tab shows exit prompt; second Back exits.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.text('再按一次返回键退出 Kazumi TV'), findsOneWidget);
      expect(exitCalls, 0);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(exitCalls, 1);
    },
  );

  testWidgets(
    'keyboard escape followed by handlePopRoute deduplicates within 250ms',
    (tester) async {
      configureTvViewport(tester);
      var exitCalls = 0;

      await tester.pumpWidget(
        buildTestShell(onExitRequested: () => exitCalls++),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Kazumi TV'), findsOneWidget);
      expect(find.text('再按一次返回键退出 Kazumi TV'), findsNothing);
      expect(exitCalls, 0);
    },
  );
}
