import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/shaders/shader_asset_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/services/update/startup_update_check.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';
import 'package:kazumi/tv/widgets/tv_update_dialog.dart';

class TvInitPage extends StatefulWidget {
  const TvInitPage({
    super.key,
    required this.pluginsController,
    required this.collectController,
    required this.shaderAssetService,
    required this.myController,
    required this.danmakuShieldSync,
  });

  final PluginsController pluginsController;
  final CollectController collectController;
  final ShaderAssetService shaderAssetService;
  final MyController myController;
  final DanmakuShieldSyncService danmakuShieldSync;

  static const tvDefaultsInitializedKey = SettingKey<bool>(
    'tvDefaultsInitialized',
    false,
    group: SettingGroup.misc,
  );

  @override
  State<TvInitPage> createState() => _TvInitPageState();
}

class _TvInitPageState extends State<TvInitPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _applyTvFirstLaunchDefaults() async {
    if (GStorage.getSetting(TvInitPage.tvDefaultsInitializedKey)) {
      return;
    }
    await Future.wait([
      GStorage.putSetting(SettingsKeys.themeMode, 'dark'),
      GStorage.putSetting(SettingsKeys.defaultStartupPage, '/tab/popular'),
      GStorage.putSetting(
        SettingsKeys.defaultSuperResolutionMode,
        SuperResolutionMode.off.storageValue,
      ),
      GStorage.putSetting(SettingsKeys.hAenable, true),
      GStorage.putSetting(SettingsKeys.hardwareDecoder, 'auto-safe'),
      GStorage.putSetting(SettingsKeys.autoPlay, true),
      GStorage.putSetting(SettingsKeys.autoPlayNext, true),
      GStorage.putSetting(SettingsKeys.playResume, true),
      GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, true),
      GStorage.putSetting(SettingsKeys.danmakuFontSize, 24.0),
      if (!BangumiAcceleration.hasMirrorCredentials &&
          GStorage.getSetting(SettingsKeys.bangumiAcceleration).isEmpty)
        GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'ech'),
      GStorage.putSetting(TvInitPage.tvDefaultsInitializedKey, true),
    ]);
  }

  Future<void> _initializeApp() async {
    await _applyTvFirstLaunchDefaults();
    widget.danmakuShieldSync.start();
    unawaited(
      TvUpdateService.instance.cleanupCachedApks().catchError((Object e) {
        KazumiLogger().w('TvInitPage: cleanupCachedApks failed', error: e);
        return 0;
      }),
    );
    unawaited(widget.collectController.migrateCollect());
    unawaited(widget.shaderAssetService.copyShadersToExternalDirectory());
    unawaited(widget.myController.loadShieldList());
    unawaited(_webDavInit());
    unawaited(_bangumiInit());

    try {
      await widget.pluginsController.init();
      unawaited(_pluginUpdate());
    } catch (error, stackTrace) {
      KazumiLogger().e(
        'TvInitPage: failed to initialize plugins',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (!mounted) {
      return;
    }

    if (!GStorage.getSetting(SettingsKeys.onboardingCompleted) &&
        widget.pluginsController.pluginList.isEmpty) {
      context.navigate('/onboarding');
      return;
    }

    unawaited(
      runStartupUpdateCheck(
        isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
        checkForUpdate: () => checkTvUpdatesSilently(),
        delay: const Duration(seconds: 2),
      ),
    );

    context.navigate('/tab/popular');
  }

  Future<void> _webDavInit() async {
    final webDavEnable = GStorage.getSetting(SettingsKeys.webDavEnable);
    final webDavEnableHistory =
        GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    if (!webDavEnable) return;
    final webDav = WebDav();
    try {
      await webDav.init();
      await widget.danmakuShieldSync.syncIfEnabled();
      if (webDavEnableHistory) {
        await webDav.syncHistory();
      }
    } catch (e, stackTrace) {
      KazumiLogger().w(
        'TvInitPage: WebDAV init/sync failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _bangumiInit() async {
    if (!GStorage.getSetting(SettingsKeys.bangumiSyncEnable)) return;
    try {
      await BangumiSyncService().ping();
    } catch (e) {
      KazumiLogger().w('TvInitPage: Bangumi ping failed', error: e);
    }
  }

  Future<void> _pluginUpdate() async {
    final checkOnStartup =
        GStorage.getSetting(SettingsKeys.checkPluginUpdateOnStartup);
    try {
      final count = await widget.pluginsController.checkPluginUpdatesOnStartup(
        enabled: checkOnStartup,
      );
      if (count > 0) {
        KazumiDialog.showToast(
          message: '检测到 $count 条规则可更新，可在「规则」页一键更新',
          duration: const Duration(seconds: 4),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/images/logo/logo_rounded.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.tv_rounded, size: 72),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Kazumi TV',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.8),
            ),
          ],
        ),
      ),
    );
  }
}
