import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';

class AppWidget extends StatefulWidget {
  const AppWidget({super.key});

  @override
  State<AppWidget> createState() => _AppWidgetState();
}

class _AppWidgetState extends State<AppWidget> with WidgetsBindingObserver {
  bool _didApplyStoredThemeSettings = false;
  final TvDirectionalFocusAction _directionalFocusAction =
      TvDirectionalFocusAction();
  final TvFocusTraversalPolicy _traversalPolicy = TvFocusTraversalPolicy();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configurePreferredDisplayMode();
  }

  Future<void> _configurePreferredDisplayMode() async {
    if (!Platform.isAndroid) return;
    try {
      final modes = await FlutterDisplayMode.supported;
      if (modes.isEmpty) return;
      final storageDisplay = GStorage.getSetting(SettingsKeys.displayMode);
      DisplayMode selectedMode = DisplayMode.auto;
      if (storageDisplay != null) {
        selectedMode = modes.firstWhere(
          (e) => e.toString() == storageDisplay,
          orElse: () => DisplayMode.auto,
        );
      }
      final preferred = modes.firstWhere(
        (el) => el == selectedMode,
        orElse: () => DisplayMode.auto,
      );
      await FlutterDisplayMode.setPreferredMode(preferred);
    } catch (e) {
      KazumiLogger().w('DisplayMode: set preferred mode failed', error: e);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = context.watch<ThemeProvider>();
    _applyStoredThemeSettings(themeProvider);
  }

  void _applyStoredThemeSettings(ThemeProvider themeProvider) {
    if (_didApplyStoredThemeSettings) return;
    _didApplyStoredThemeSettings = true;

    themeProvider.setThemeMode(_storedThemeMode(), notify: false);
    themeProvider.setDynamic(
      GStorage.getSetting(SettingsKeys.useDynamicColor),
      notify: false,
    );
    themeProvider.setFontFamily(
      GStorage.getSetting(SettingsKeys.useSystemFont),
      notify: false,
    );

    final color = _storedThemeColor();
    final oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    themeProvider.setTheme(
      TvTheme.buildTheme(
        brightness: Brightness.light,
        seedColor: color,
        fontFamily: themeProvider.currentFontFamily,
      ),
      TvTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: color,
        fontFamily: themeProvider.currentFontFamily,
        oledEnhance: oledEnhance,
      ),
      notify: false,
    );
  }

  ThemeMode _storedThemeMode() {
    return switch (GStorage.getSetting(SettingsKeys.themeMode)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Color _storedThemeColor() {
    final defaultThemeColor = GStorage.getSetting(SettingsKeys.themeColor);
    if (defaultThemeColor == 'default') {
      return Colors.green;
    }
    return Color(int.tryParse(defaultThemeColor, radix: 16) ??
        Colors.green.toARGB32());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      MeteredNetworkService.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final bool oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: DynamicColorBuilder(
        builder: (theme, darkTheme) {
          final useDynamicColor = themeProvider.useDynamicColor &&
              theme != null &&
              darkTheme != null;
          final lightTheme = useDynamicColor
              ? TvTheme.buildTheme(
                  brightness: Brightness.light,
                  colorScheme: theme,
                  fontFamily: themeProvider.currentFontFamily,
                )
              : themeProvider.light;
          final effectiveDarkTheme = useDynamicColor
              ? TvTheme.buildTheme(
                  brightness: Brightness.dark,
                  colorScheme: darkTheme,
                  fontFamily: themeProvider.currentFontFamily,
                  oledEnhance: oledEnhance,
                )
              : themeProvider.dark;

          return MaterialApp.router(
            title: 'Kazumi TV',
            debugShowCheckedModeBanner: false,
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [
              Locale.fromSubtags(
                languageCode: 'zh',
                scriptCode: 'Hans',
                countryCode: 'CN',
              ),
            ],
            locale: const Locale.fromSubtags(
              languageCode: 'zh',
              scriptCode: 'Hans',
              countryCode: 'CN',
            ),
            theme: lightTheme,
            darkTheme: effectiveDarkTheme,
            themeMode: themeProvider.themeMode,
            scaffoldMessengerKey: rootScaffoldMessengerKey,
            routerConfig: ModularApp.routerConfigOf(context),
            builder: (context, child) => Actions(
              actions: <Type, Action<Intent>>{
                DirectionalFocusIntent: _directionalFocusAction,
              },
              child: FocusTraversalGroup(
                policy: _traversalPolicy,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
      ),
    );
  }
}
