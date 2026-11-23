import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/error/storage_error_page.dart';
import 'package:kazumi/services/network/ech_http_licenses.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerEchHttpLicenses();
  MediaKit.ensureInitialized();

  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  if (Platform.isAndroid) {
    await WebViewFeatureService.initialize();
  }

  try {
    final hivePath = '${(await getApplicationSupportDirectory()).path}/hive';
    await Hive.initFlutter(hivePath);
    await GStorage.init();
  } catch (e) {
    debugPrint('Storage initialization failed: $e');
    runApp(
      MaterialApp(
        title: '初始化失败',
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
        builder: (context, child) => const StorageErrorPage(),
      ),
    );
    return;
  }

  await MeteredNetworkService.refresh();
  ProxyManager.applyProxy();

  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
