import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/color_type.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/modules/danmaku/danmaku_ch_convert.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/config/rules_repository_config.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/rules_mirror.dart';
import 'package:kazumi/services/player/low_memory_mode.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/image_cache_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/services/sync/danmaku_shield_sync_service.dart';
import 'package:kazumi/services/sync/webdav.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/update/tv_update_models.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_update_dialog.dart';
import 'package:kazumi/utils/constants.dart';

class TvSettingsPage extends StatefulWidget {
  const TvSettingsPage({
    super.key,
    required this.danmakuShieldSync,
  });

  final DanmakuShieldSyncService danmakuShieldSync;

  @override
  State<TvSettingsPage> createState() => _TvSettingsPageState();
}

class _TvSettingsPageState extends State<TvSettingsPage> {
  static const List<({String title, IconData icon})> _categories = [
    (title: '播放设置', icon: Icons.play_circle_outline_rounded),
    (title: '弹幕设置', icon: Icons.subtitles_outlined),
    (title: '同步与数据', icon: Icons.cloud_sync_outlined),
    (title: '网络与代理', icon: Icons.wifi_tethering_rounded),
    (title: '外观与显示', icon: Icons.palette_outlined),
    (title: '关于与日志', icon: Icons.info_outline_rounded),
  ];

  int _categoryIndex = 0;
  final ImageCacheService _imageCache = ImageCacheService();
  final FocusScopeNode _categoryScopeNode =
      FocusScopeNode(debugLabel: 'TvSettingsCategories');
  final FocusScopeNode _detailScopeNode =
      FocusScopeNode(debugLabel: 'TvSettingsDetail');
  late final List<FocusNode> _categoryNodes = List<FocusNode>.generate(
    _categories.length,
    (i) => FocusNode(debugLabel: 'TvSettingsCategory_$i'),
  );
  int? _cacheBytes;
  bool _syncBusy = false;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCacheSize());
  }

  @override
  void dispose() {
    for (final node in _categoryNodes) {
      node.dispose();
    }
    _categoryScopeNode.dispose();
    _detailScopeNode.dispose();
    super.dispose();
  }

  void _focusDetailPane() {
    final previous = _detailScopeNode.focusedChild;
    if (previous != null &&
        previous.canRequestFocus &&
        !previous.skipTraversal &&
        previous.context != null) {
      previous.requestFocus();
      return;
    }
    for (final candidate in _detailScopeNode.traversalDescendants) {
      if (candidate.canRequestFocus && !candidate.skipTraversal) {
        candidate.requestFocus();
        return;
      }
    }
  }

  Future<void> _refreshCacheSize() async {
    try {
      final bytes = await _imageCache.sizeInBytes();
      if (mounted) setState(() => _cacheBytes = bytes);
    } catch (_) {}
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _putAndRefresh<T>(SettingKey<T> key, T value) async {
    await GStorage.putSetting(key, value);
    _refresh();
  }

  void _applyTheme({
    String? themeMode,
    String? themeColorHex,
    bool? oledEnhance,
  }) {
    final provider = context.read<ThemeProvider>();
    final String modeStr =
        themeMode ?? GStorage.getSetting<String>(SettingsKeys.themeMode);
    final String colorStr =
        themeColorHex ?? GStorage.getSetting<String>(SettingsKeys.themeColor);
    final bool oled =
        oledEnhance ?? GStorage.getSetting<bool>(SettingsKeys.oledEnhance);

    final mode = switch (modeStr) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final seedColor = colorStr == 'default'
        ? Colors.green
        : Color(int.tryParse(colorStr, radix: 16) ?? Colors.green.toARGB32());

    provider.setThemeMode(mode, notify: false);
    provider.setTheme(
      TvTheme.buildTheme(
        brightness: Brightness.light,
        seedColor: seedColor,
        fontFamily: provider.currentFontFamily,
      ),
      TvTheme.buildTheme(
        brightness: Brightness.dark,
        seedColor: seedColor,
        fontFamily: provider.currentFontFamily,
        oledEnhance: oled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 24, 36, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '系统设置',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 256,
                  child: FocusScope(
                    node: _categoryScopeNode,
                    child: TvAxisClipRect(
                      axis: Axis.vertical,
                      child: ListView.separated(
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.all(18),
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final cat = _categories[index];
                          final selected = index == _categoryIndex;
                          return TvFocusable(
                            focusNode: _categoryNodes[index],
                            borderRadius: 14,
                            scaleOnFocus: 1.03,
                            onSelect: () =>
                                setState(() => _categoryIndex = index),
                            onFocusChange: (focused) {
                              if (focused && _categoryIndex != index) {
                                setState(() => _categoryIndex = index);
                              }
                            },
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent) {
                                if (TvKeys.isLeftKey(event.logicalKey)) {
                                  TvShellScope.maybeOf(context)?.focusRail();
                                  return KeyEventResult.handled;
                                }
                                if (TvKeys.isRightKey(event.logicalKey)) {
                                  _focusDetailPane();
                                  return KeyEventResult.handled;
                                }
                              }
                              return KeyEventResult.ignored;
                            },
                            builder: (context, focused) {
                              final bg = selected
                                  ? colors.primary
                                  : focused
                                      ? colors.surfaceContainerHighest
                                      : colors.surfaceContainer;
                              final fg =
                                  selected ? colors.onPrimary : colors.onSurface;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  children: [
                                    Icon(cat.icon, size: 22, color: fg),
                                    const SizedBox(width: 12),
                                    Text(
                                      cat.title,
                                      style: TextStyle(
                                        color: fg,
                                        fontSize: 15,
                                        fontWeight: selected || focused
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: FocusScope(
                    node: _detailScopeNode,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          TvKeys.isLeftKey(event.logicalKey)) {
                        _categoryNodes[_categoryIndex].requestFocus();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: TvAxisClipRect(
                        axis: Axis.vertical,
                        child: ListView(
                          key: ValueKey(_categoryIndex),
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.all(18),
                          children: switch (_categoryIndex) {
                            0 => _buildPlayerSettings(),
                            1 => _buildDanmakuSettings(),
                            2 => _buildSyncSettings(),
                            3 => _buildNetworkSettings(),
                            4 => _buildDisplaySettings(),
                            _ => _buildAboutSettings(),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlayerSettings() {
    final hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    final decoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    final renderer = GStorage.getSetting(SettingsKeys.androidVideoRenderer);
    final lowMem = LowMemoryMode.current;
    final speed = GStorage.getSetting(SettingsKeys.defaultPlaySpeed);
    final ratio = PlayerAspectRatio.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultAspectRatioType),
    );
    final sr = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting(SettingsKeys.defaultSuperResolutionMode),
    );
    final autoPlay = GStorage.getSetting(SettingsKeys.autoPlay);
    final autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    final buttonSkip = GStorage.getSetting(SettingsKeys.buttonSkipTime);
    final arrowSkip = GStorage.getSetting(SettingsKeys.arrowKeySkipTime);
    final forceAdBlocker = GStorage.getSetting(SettingsKeys.forceAdBlocker);
    final openSLES = GStorage.getSetting(SettingsKeys.androidEnableOpenSLES);

    return [
      _TvSwitchTile(
        title: '硬件解码',
        subtitle: '推荐在 Android TV 上开启以获得流畅 1080p/4K 播放体验',
        value: hAenable,
        onChanged: (v) => _putAndRefresh(SettingsKeys.hAenable, v),
      ),
      _TvOptionTile(
        title: '解码器模式',
        subtitle: '若部分电视盒子绿屏或花屏，可尝试 mediacodec-copy 或 no',
        valueText: decoder,
        onTap: () async {
          final next = await showTvChoiceDialog<String>(
            context,
            title: '选择硬件解码器',
            currentValue: decoder,
            options: const [
              TvChoiceOption(
                value: 'auto-safe',
                label: 'auto-safe (推荐)',
                subtitle: '自动选择稳定解码器',
              ),
              TvChoiceOption(
                value: 'mediacodec',
                label: 'mediacodec',
                subtitle: 'Android 硬解直通',
              ),
              TvChoiceOption(
                value: 'mediacodec-copy',
                label: 'mediacodec-copy',
                subtitle: 'Android 硬解带拷贝（兼容性更好）',
              ),
              TvChoiceOption(
                value: 'auto',
                label: 'auto',
                subtitle: '任意可用硬解',
              ),
              TvChoiceOption(
                value: 'no',
                label: '软件解码',
                subtitle: '兼容性最高但 CPU 占用较大',
              ),
            ],
          );
          if (next != null) await _putAndRefresh(SettingsKeys.hardwareDecoder, next);
        },
      ),
      _TvOptionTile(
        title: 'Android 视频渲染器',
        subtitle: '老旧电视盒子推荐 gpu 或 mediacodec_embed',
        valueText: androidVideoRenderersList[renderer] ?? renderer,
        onTap: () async {
          final next = await showTvChoiceDialog<String>(
            context,
            title: '选择视频渲染器',
            currentValue: renderer,
            options: [
              for (final entry in androidVideoRenderersList.entries)
                TvChoiceOption(
                  value: entry.key,
                  label: entry.key,
                  subtitle: entry.value,
                ),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.androidVideoRenderer, next);
          }
        },
      ),
      _TvOptionTile(
        title: '低内存缓存策略',
        subtitle: '小内存电视盒子可设为始终开启，减少 OOM 崩溃风险',
        valueText: switch (lowMem) {
          LowMemoryMode.auto => '自动',
          LowMemoryMode.always => '始终开启',
          LowMemoryMode.never => '始终关闭',
        },
        onTap: () async {
          final next = await showTvChoiceDialog<LowMemoryMode>(
            context,
            title: '低内存缓存策略',
            currentValue: lowMem,
            options: const [
              TvChoiceOption(
                value: LowMemoryMode.auto,
                label: '自动',
                subtitle: '正常 Wi-Fi 下使用大缓存',
              ),
              TvChoiceOption(
                value: LowMemoryMode.always,
                label: '始终开启',
                subtitle: '限制播放缓存占用（推荐低配电视）',
              ),
              TvChoiceOption(
                value: LowMemoryMode.never,
                label: '始终关闭',
              ),
            ],
          );
          if (next != null) {
            await next.save();
            _refresh();
          }
        },
      ),
      _TvOptionTile(
        title: '默认倍速',
        valueText: '${speed}x',
        onTap: () async {
          final next = await showTvChoiceDialog<double>(
            context,
            title: '默认播放倍速',
            currentValue: speed,
            options: [
              for (final s in const [0.75, 1.0, 1.25, 1.5, 2.0])
                TvChoiceOption(value: s, label: '${s}x'),
            ],
          );
          if (next != null) await _putAndRefresh(SettingsKeys.defaultPlaySpeed, next);
        },
      ),
      _TvOptionTile(
        title: '默认画面比例',
        valueText: ratio.label,
        onTap: () async {
          final next = await showTvChoiceDialog<PlayerAspectRatio>(
            context,
            title: '默认画面比例',
            currentValue: ratio,
            options: [
              for (final m in PlayerAspectRatio.values)
                TvChoiceOption(value: m, label: m.label),
            ],
          );
          if (next != null) {
            await _putAndRefresh(
              SettingsKeys.defaultAspectRatioType,
              next.storageValue,
            );
          }
        },
      ),
      _TvOptionTile(
        title: '默认超分辨率',
        subtitle: '电视端默认关闭，以免老旧 GPU 卡顿',
        valueText: sr.label,
        onTap: () async {
          final next = await showTvChoiceDialog<SuperResolutionMode>(
            context,
            title: '默认超分辨率',
            currentValue: sr,
            options: [
              for (final m in SuperResolutionMode.values)
                TvChoiceOption(
                  value: m,
                  label: m.label,
                  subtitle: m.description,
                ),
            ],
          );
          if (next != null) {
            await _putAndRefresh(
              SettingsKeys.defaultSuperResolutionMode,
              next.storageValue,
            );
          }
        },
      ),
      _TvSwitchTile(
        title: '自动播放',
        value: autoPlay,
        onChanged: (v) => _putAndRefresh(SettingsKeys.autoPlay, v),
      ),
      _TvSwitchTile(
        title: '自动连播下一集',
        value: autoPlayNext,
        onChanged: (v) => _putAndRefresh(SettingsKeys.autoPlayNext, v),
      ),
      _TvSwitchTile(
        title: '历史进度续播',
        value: playResume,
        onChanged: (v) => _putAndRefresh(SettingsKeys.playResume, v),
      ),
      _TvOptionTile(
        title: '方向键快进/快退步长',
        subtitle: '播放时按遥控器左/右键每次跳转的秒数',
        valueText: '$arrowSkip 秒',
        onTap: () async {
          final next = await showTvChoiceDialog<int>(
            context,
            title: '方向键跳转步长',
            currentValue: arrowSkip,
            options: [
              for (final sec in const [5, 10, 15, 30])
                TvChoiceOption(value: sec, label: '$sec 秒'),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.arrowKeySkipTime, next);
          }
        },
      ),
      _TvOptionTile(
        title: '跳过片头默认时长',
        valueText: '$buttonSkip 秒',
        onTap: () async {
          final next = await showTvChoiceDialog<int>(
            context,
            title: '跳过片头时长',
            currentValue: buttonSkip,
            options: [
              for (final sec in const [60, 80, 85, 90, 120])
                TvChoiceOption(value: sec, label: '$sec 秒'),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.buttonSkipTime, next);
          }
        },
      ),
      _TvSwitchTile(
        title: '强制 M3U8 广告过滤',
        value: forceAdBlocker,
        onChanged: (v) => _putAndRefresh(SettingsKeys.forceAdBlocker, v),
      ),
      _TvSwitchTile(
        title: '启用 OpenSL ES 音频输出',
        subtitle: '若个别电视无声或爆音可尝试关闭以切换至 AudioTrack',
        value: openSLES,
        onChanged: (v) => _putAndRefresh(SettingsKeys.androidEnableOpenSLES, v),
      ),
      _TvActionTile(
        title: '恢复默认播放设置',
        icon: Icons.restore_rounded,
        onTap: () async {
          final ok = await showTvConfirmDialog(
            context,
            title: '恢复默认播放设置',
            message: '确认将所有播放设置恢复为默认值吗？',
            confirmLabel: '恢复默认',
          );
          if (ok) {
            await GStorage.resetPlayerSettings();
            _refresh();
            KazumiDialog.showToast(message: '已恢复默认播放设置');
          }
        },
      ),
    ];
  }

  List<Widget> _buildDanmakuSettings() {
    final enabled = GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault);
    final fontSize = GStorage.getSetting(SettingsKeys.danmakuFontSize);
    final opacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
    final area = GStorage.getSetting(SettingsKeys.danmakuArea);
    final duration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    final border = GStorage.getSetting(SettingsKeys.danmakuBorder);
    final top = GStorage.getSetting(SettingsKeys.danmakuTop);
    final scroll = GStorage.getSetting(SettingsKeys.danmakuScroll);
    final bottom = GStorage.getSetting(SettingsKeys.danmakuBottom);
    final bili = GStorage.getSetting(SettingsKeys.danmakuBiliBiliSource);
    final gamer = GStorage.getSetting(SettingsKeys.danmakuGamerSource);
    final dandan = GStorage.getSetting(SettingsKeys.danmakuDanDanSource);
    final chConvert = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    final enhance = GStorage.getSetting(SettingsKeys.danmakuEnhance);

    return [
      _TvSwitchTile(
        title: '默认开启弹幕',
        value: enabled,
        onChanged: (v) =>
            _putAndRefresh(SettingsKeys.danmakuEnabledByDefault, v),
      ),
      _TvOptionTile(
        title: '弹幕字号',
        valueText: '${fontSize.round()} px',
        onTap: () async {
          final next = await showTvChoiceDialog<double>(
            context,
            title: '弹幕字号',
            currentValue: fontSize,
            options: [
              for (final size in const [18.0, 22.0, 24.0, 28.0, 32.0])
                TvChoiceOption(value: size, label: '${size.round()} px'),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.danmakuFontSize, next);
          }
        },
      ),
      _TvOptionTile(
        title: '弹幕不透明度',
        valueText: '${(opacity * 100).round()}%',
        onTap: () async {
          final next = await showTvChoiceDialog<double>(
            context,
            title: '弹幕不透明度',
            currentValue: opacity,
            options: [
              for (final val in const [0.4, 0.6, 0.8, 1.0])
                TvChoiceOption(value: val, label: '${(val * 100).round()}%'),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.danmakuOpacity, next);
          }
        },
      ),
      _TvOptionTile(
        title: '弹幕显示区域',
        valueText: '${(area * 100).round()}%',
        onTap: () async {
          final next = await showTvChoiceDialog<double>(
            context,
            title: '弹幕显示区域',
            currentValue: area,
            options: const [
              TvChoiceOption(value: 0.25, label: '四分之一屏 (25%)'),
              TvChoiceOption(value: 0.5, label: '半屏 (50%)'),
              TvChoiceOption(value: 0.75, label: '四分之三屏 (75%)'),
              TvChoiceOption(value: 1.0, label: '全屏 (100%)'),
            ],
          );
          if (next != null) await _putAndRefresh(SettingsKeys.danmakuArea, next);
        },
      ),
      _TvOptionTile(
        title: '弹幕滚动时长（越小越快）',
        valueText: '${duration.toStringAsFixed(0)} 秒',
        onTap: () async {
          final next = await showTvChoiceDialog<double>(
            context,
            title: '弹幕滚动时长',
            currentValue: duration,
            options: [
              for (final d in const [5.0, 7.0, 8.0, 10.0, 12.0])
                TvChoiceOption(value: d, label: '${d.toInt()} 秒'),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.danmakuDuration, next);
          }
        },
      ),
      _TvSwitchTile(
        title: '弹幕描边',
        value: border,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuBorder, v),
      ),
      _TvSwitchTile(
        title: '弹幕关键词精准匹配（DanmakuEnhance）',
        value: enhance,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuEnhance, v),
      ),
      _TvSwitchTile(
        title: '显示滚动弹幕',
        value: scroll,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuScroll, v),
      ),
      _TvSwitchTile(
        title: '显示顶部弹幕',
        value: top,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuTop, v),
      ),
      _TvSwitchTile(
        title: '显示底部弹幕',
        value: bottom,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuBottom, v),
      ),
      _TvSwitchTile(
        title: 'BiliBili 弹幕源',
        value: bili,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuBiliBiliSource, v),
      ),
      _TvSwitchTile(
        title: '巴哈姆特动画疯弹幕源',
        value: gamer,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuGamerSource, v),
      ),
      _TvSwitchTile(
        title: '弹弹play 官方弹幕源',
        value: dandan,
        onChanged: (v) => _putAndRefresh(SettingsKeys.danmakuDanDanSource, v),
      ),
      _TvOptionTile(
        title: '弹幕简繁转换',
        valueText: switch (chConvert) {
          DanmakuChConvert.none => '不转换',
          DanmakuChConvert.simplified => '转为简体',
          DanmakuChConvert.traditional => '转为繁体',
        },
        onTap: () async {
          final next = await showTvChoiceDialog<DanmakuChConvert>(
            context,
            title: '弹幕简繁转换',
            currentValue: chConvert,
            options: const [
              TvChoiceOption(value: DanmakuChConvert.none, label: '不转换'),
              TvChoiceOption(
                value: DanmakuChConvert.simplified,
                label: '转为简体中文',
              ),
              TvChoiceOption(
                value: DanmakuChConvert.traditional,
                label: '转为繁体中文',
              ),
            ],
          );
          if (next != null) {
            await _putAndRefresh(SettingsKeys.danmakuChConvert, next.value);
          }
        },
      ),
      _TvActionTile(
        title: '恢复默认弹幕设置',
        icon: Icons.restore_rounded,
        onTap: () async {
          final ok = await showTvConfirmDialog(
            context,
            title: '恢复默认弹幕设置',
            message: '确认将弹幕样式和来源设置恢复为默认值吗？',
            confirmLabel: '恢复默认',
          );
          if (ok) {
            await GStorage.resetDanmakuSettings();
            _refresh();
            KazumiDialog.showToast(message: '已恢复默认弹幕设置');
          }
        },
      ),
    ];
  }

  List<Widget> _buildSyncSettings() {
    final webDavEnable = GStorage.getSetting(SettingsKeys.webDavEnable);
    final webDavUrl = GStorage.getSetting(SettingsKeys.webDavURL).trim();
    final webDavUser = GStorage.getSetting(SettingsKeys.webDavUsername).trim();
    final webDavHistory =
        GStorage.getSetting(SettingsKeys.webDavEnableHistory);
    final webDavCollect =
        GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final webDavShield =
        GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield);
    final bangumiSync = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);
    final bangumiToken =
        GStorage.getSetting(SettingsKeys.bangumiAccessToken).trim();
    final privateMode = GStorage.getSetting(SettingsKeys.privateMode);
    final cacheLabel = _cacheBytes == null
        ? '统计中…'
        : '${(_cacheBytes! / (1024 * 1024)).toStringAsFixed(2)} MB';

    return [
      _TvOptionTile(
        title: 'WebDAV 服务器地址',
        subtitle: webDavUrl.isEmpty ? '点击输入 https://dav.example.com/dav' : webDavUrl,
        valueText: webDavUrl.isEmpty ? '未配置' : '已配置',
        onTap: () async {
          final val = await showTvInputDialog(
            context,
            title: 'WebDAV 服务器地址',
            initialValue: webDavUrl,
            hintText: 'https://...',
          );
          if (val != null) await _putAndRefresh(SettingsKeys.webDavURL, val);
        },
      ),
      _TvOptionTile(
        title: 'WebDAV 账号',
        subtitle: webDavUser.isEmpty ? '未填写' : webDavUser,
        valueText: webDavUser.isEmpty ? '未填写' : '修改',
        onTap: () async {
          final val = await showTvInputDialog(
            context,
            title: 'WebDAV 用户名',
            initialValue: webDavUser,
          );
          if (val != null) {
            await _putAndRefresh(SettingsKeys.webDavUsername, val);
          }
        },
      ),
      _TvOptionTile(
        title: 'WebDAV 密码',
        valueText: GStorage.getSetting(SettingsKeys.webDavPassword).isEmpty
            ? '未填写'
            : '已设置',
        onTap: () async {
          final val = await showTvInputDialog(
            context,
            title: 'WebDAV 密码',
            initialValue: GStorage.getSetting(SettingsKeys.webDavPassword),
            obscureText: true,
          );
          if (val != null) {
            await _putAndRefresh(SettingsKeys.webDavPassword, val);
          }
        },
      ),
      _TvSwitchTile(
        title: '启用 WebDAV 同步',
        value: webDavEnable,
        onChanged: (v) async {
          if (_syncBusy) return;
          if (v && webDavUrl.isEmpty) {
            KazumiDialog.showToast(message: '请先填写 WebDAV 服务器地址');
            return;
          }
          setState(() => _syncBusy = true);
          try {
            await WebDav().setEnabled(v);
            KazumiDialog.showToast(message: v ? 'WebDAV 已连接并启用' : 'WebDAV 已关闭');
          } catch (_) {
            KazumiDialog.showToast(message: 'WebDAV 连接失败，请检查地址与账号密码');
          } finally {
            if (mounted) setState(() => _syncBusy = false);
          }
        },
      ),
      if (webDavEnable) ...[
        _TvSwitchTile(
          title: 'WebDAV 同步观看记录',
          value: webDavHistory,
          onChanged: (v) =>
              _putAndRefresh(SettingsKeys.webDavEnableHistory, v),
        ),
        _TvSwitchTile(
          title: 'WebDAV 同步收藏',
          value: webDavCollect,
          onChanged: (v) =>
              _putAndRefresh(SettingsKeys.webDavEnableCollect, v),
        ),
        _TvSwitchTile(
          title: 'WebDAV 同步弹幕屏蔽词',
          value: webDavShield,
          onChanged: (v) =>
              _putAndRefresh(SettingsKeys.webDavEnableDanmakuShield, v),
        ),
        _TvActionTile(
          title: '立即同步 WebDAV 观看记录与屏蔽词',
          icon: Icons.sync_rounded,
          onTap: () async {
            if (_syncBusy) return;
            setState(() => _syncBusy = true);
            try {
              final wd = WebDav();
              if (!wd.initialized) await wd.init();
              await wd.syncHistory();
              await widget.danmakuShieldSync.syncIfEnabled();
              KazumiDialog.showToast(message: 'WebDAV 同步完成');
            } catch (_) {
              KazumiDialog.showToast(message: 'WebDAV 同步失败，请检查连接');
            } finally {
              if (mounted) setState(() => _syncBusy = false);
            }
          },
        ),
      ],
      _TvOptionTile(
        title: 'Bangumi Access Token',
        subtitle: bangumiToken.isEmpty ? '未配置（可在 bgm.tv 生成 Token）' : '已配置',
        valueText: bangumiToken.isEmpty ? '设置' : '更换',
        onTap: () async {
          final val = await showTvInputDialog(
            context,
            title: 'Bangumi Access Token',
            initialValue: bangumiToken,
            hintText: '粘贴 Bangumi 个人令牌',
            obscureText: true,
          );
          if (val == null || val.isEmpty || !mounted) return;
          setState(() => _syncBusy = true);
          try {
            await BangumiSyncService().saveToken(val);
            KazumiDialog.showToast(
              message: 'Bangumi 验证成功：${BangumiSyncService().username}',
            );
          } catch (e) {
            KazumiDialog.showToast(
              message: 'Token 验证失败：${BangumiSyncService.describeError(e)}',
            );
          } finally {
            if (mounted) setState(() => _syncBusy = false);
          }
        },
      ),
      _TvSwitchTile(
        title: '启用 Bangumi 追番同步',
        value: bangumiSync,
        onChanged: (v) async {
          if (_syncBusy) return;
          setState(() => _syncBusy = true);
          try {
            await BangumiSyncService().setEnabled(v);
            _refresh();
          } catch (e) {
            if (mounted) {
              KazumiDialog.showToast(
                message: BangumiSyncService.describeError(e),
              );
            }
          } finally {
            if (mounted) setState(() => _syncBusy = false);
          }
        },
      ),
      _TvSwitchTile(
        title: '无痕模式（不记录搜索历史与观看记录）',
        value: privateMode,
        onChanged: (v) => _putAndRefresh(SettingsKeys.privateMode, v),
      ),
      _TvActionTile(
        title: '清除图片缓存',
        subtitle: '当前占用：$cacheLabel',
        icon: Icons.cleaning_services_rounded,
        onTap: () async {
          final ok = await showTvConfirmDialog(
            context,
            title: '清除图片缓存',
            message: '确认清除所有本地封面缓存吗？',
            confirmLabel: '清除',
          );
          if (!ok) return;
          await _imageCache.clear();
          await _refreshCacheSize();
          KazumiDialog.showToast(message: '图片缓存已清除');
        },
      ),
    ];
  }

  List<Widget> _buildNetworkSettings() {
    final proxyEnabled = GStorage.getSetting(SettingsKeys.proxyEnable);
    final proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
    final ruleRepo = GStorage.getSetting(SettingsKeys.ruleRepositoryUrl);

    return [
      _TvOptionTile(
        title: '番剧条目加速',
        subtitle: BangumiAcceleration.current.description,
        valueText: BangumiAcceleration.current.label,
        onTap: () => _pickAcceleration<BangumiAcceleration>(
          title: '番剧条目加速',
          current: BangumiAcceleration.current,
          modes: BangumiAcceleration.values,
          key: SettingsKeys.bangumiAcceleration,
        ),
      ),
      _TvOptionTile(
        title: '规则仓库加速',
        subtitle: RulesMirror.current.description,
        valueText: RulesMirror.current.label,
        onTap: () => _pickAcceleration<RulesMirror>(
          title: '规则仓库加速',
          current: RulesMirror.current,
          modes: RulesMirror.values,
          key: SettingsKeys.rulesMirror,
        ),
      ),
      _TvOptionTile(
        title: '图片加速',
        subtitle: ImageAcceleration.current.description,
        valueText: ImageAcceleration.current.label,
        onTap: () => _pickAcceleration<ImageAcceleration>(
          title: '图片加速',
          current: ImageAcceleration.current,
          modes: ImageAcceleration.values,
          key: SettingsKeys.imageAcceleration,
        ),
      ),
      _TvOptionTile(
        title: '自定义规则仓库地址',
        subtitle: ruleRepo.isEmpty ? '当前使用官方默认仓库' : ruleRepo,
        valueText: ruleRepo.isEmpty ? '默认' : '修改',
        onTap: () async {
          final next = await showTvInputDialog(
            context,
            title: '自定义规则仓库地址',
            initialValue: ruleRepo,
            hintText: '留空恢复官方仓库',
          );
          if (next == null || !mounted) return;
          try {
            final normalized = RulesRepositoryConfig.normalizeForStorage(next);
            await _putAndRefresh(SettingsKeys.ruleRepositoryUrl, normalized);
          } on FormatException catch (e) {
            if (mounted) KazumiDialog.showToast(message: e.message);
          }
        },
      ),
      _TvOptionTile(
        title: 'HTTP 代理地址',
        subtitle: proxyUrl.isEmpty ? '例如 http://192.168.1.10:7890' : proxyUrl,
        valueText: proxyUrl.isEmpty ? '未配置' : '配置',
        onTap: () => unawaited(_configureProxy(proxyUrl)),
      ),
      _TvSwitchTile(
        title: '启用 HTTP 代理',
        value: proxyEnabled,
        onChanged: (v) async {
          if (v && !GStorage.getSetting(SettingsKeys.proxyConfigured)) {
            KazumiDialog.showToast(message: '请先配置并测试代理地址');
            return;
          }
          await GStorage.putSetting(SettingsKeys.proxyEnable, v);
          if (v) {
            ProxyManager.applyProxy();
          } else {
            ProxyManager.clearProxy();
          }
          _refresh();
        },
      ),
    ];
  }

  Future<void> _configureProxy(String currentUrl) async {
    final input = await showTvInputDialog(
      context,
      title: '配置 HTTP 代理并测试连通性',
      initialValue: currentUrl,
      hintText: 'http://192.168.1.10:7890',
    );
    if (input == null || input.isEmpty || !mounted) return;
    final parsed = ProxyUtils.parseProxyUrl(input);
    if (parsed == null) {
      KazumiDialog.showToast(message: '格式错误，请使用 http://host:port 格式');
      return;
    }

    await GStorage.putSetting(SettingsKeys.proxyUrl, input);
    if (!mounted) return;
    final cancelToken = RuleCancelToken();
    try {
      final succeeded = await showTvLoadingDialog<bool>(
        context,
        message: '正在测试代理连通性…',
        cancelToken: cancelToken,
        action: () async {
          final dio = DioFactory.createForConfig(
            NetworkConfig(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              proxyHost: parsed.$1,
              proxyPort: parsed.$2,
              allowBadCertificates: true,
              enableLog: false,
            ),
          );
          try {
            await dio
                .get('https://api.bgm.tv')
                .timeout(const Duration(seconds: 10));
            return true;
          } finally {
            dio.close();
          }
        },
      );
      if (succeeded != true || cancelToken.isCancelled || !mounted) return;
      await GStorage.putSetting(SettingsKeys.proxyConfigured, true);
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      ProxyManager.applyProxy();
      _refresh();
      if (mounted) KazumiDialog.showToast(message: '代理测试成功并已启用');
    } catch (_) {
      if (cancelToken.isCancelled || !mounted) return;
      await GStorage.putSetting(SettingsKeys.proxyEnable, false);
      ProxyManager.clearProxy();
      _refresh();
      if (mounted) {
        KazumiDialog.showToast(message: '代理连接失败，请检查局域网代理是否允许局域网连接');
      }
    }
  }

  Future<void> _pickAcceleration<T extends AccelerationMode>({
    required String title,
    required T current,
    required List<T> modes,
    required SettingKey<String> key,
  }) async {
    final next = await showTvChoiceDialog<T>(
      context,
      title: title,
      currentValue: current,
      options: [
        for (final mode in modes)
          TvChoiceOption(
            value: mode,
            label: mode.label,
            subtitle: mode.description,
          ),
      ],
    );
    if (next != null && next != current) {
      await _putAndRefresh(key, next.name);
    }
  }

  List<Widget> _buildDisplaySettings() {
    final themeMode = GStorage.getSetting(SettingsKeys.themeMode);
    final themeColor = GStorage.getSetting(SettingsKeys.themeColor);
    final oledEnhance = GStorage.getSetting(SettingsKeys.oledEnhance);
    final disableAnimations =
        GStorage.getSetting(SettingsKeys.playerDisableAnimations);
    final showRating = GStorage.getSetting(SettingsKeys.showRating);
    final displayMode = GStorage.getSetting(SettingsKeys.displayMode);

    return [
      _TvOptionTile(
        title: '界面深浅模式',
        valueText: switch (themeMode) {
          'light' => '浅色',
          'system' => '跟随系统',
          _ => '深色（TV 推荐）',
        },
        onTap: () async {
          final next = await showTvChoiceDialog<String>(
            context,
            title: '界面深浅模式',
            currentValue: themeMode,
            options: const [
              TvChoiceOption(value: 'dark', label: '深色（推荐）'),
              TvChoiceOption(value: 'system', label: '跟随系统'),
              TvChoiceOption(value: 'light', label: '浅色'),
            ],
          );
          if (next != null) {
            await GStorage.putSetting(SettingsKeys.themeMode, next);
            if (!mounted) return;
            _applyTheme(themeMode: next);
            _refresh();
          }
        },
      ),
      _TvOptionTile(
        title: '主题强调色',
        valueText: themeColor == 'default' ? '默认翠绿' : '自定义',
        onTap: () async {
          final next = await showTvChoiceDialog<String>(
            context,
            title: '选择主题颜色',
            currentValue: themeColor,
            options: [
              for (var i = 0; i < colorThemeTypes.length; i++)
                TvChoiceOption(
                  value: i == 0
                      ? 'default'
                      : (colorThemeTypes[i]['color'] as Color)
                          .toARGB32()
                          .toRadixString(16),
                  label: colorThemeTypes[i]['label'] as String,
                  icon: Icons.circle,
                ),
            ],
          );
          if (next != null) {
            await GStorage.putSetting(SettingsKeys.themeColor, next);
            if (!mounted) return;
            _applyTheme(themeColorHex: next);
            _refresh();
          }
        },
      ),
      _TvSwitchTile(
        title: 'OLED 纯黑背景',
        subtitle: '在 OLED 电视上使用纯黑色背景提升对比度',
        value: oledEnhance,
        onChanged: (v) async {
          await GStorage.putSetting(SettingsKeys.oledEnhance, v);
          if (!mounted) return;
          _applyTheme(oledEnhance: v);
          _refresh();
        },
      ),
      if (Platform.isAndroid)
        _TvOptionTile(
          title: '屏幕刷新率模式',
          valueText: displayMode ?? '自动',
          onTap: () async {
            try {
              final modes = await FlutterDisplayMode.supported;
              if (!mounted) return;
              if (modes.isEmpty) {
                KazumiDialog.showToast(message: '当前设备无可切换刷新率');
                return;
              }
              final next = await showTvChoiceDialog<DisplayMode>(
                context,
                title: '选择屏幕刷新率',
                options: [
                  for (final m in modes)
                    TvChoiceOption(
                      value: m,
                      label: m == DisplayMode.auto ? '自动' : m.toString(),
                    ),
                ],
              );
              if (next == null || !mounted) return;
              await FlutterDisplayMode.setPreferredMode(next);
              if (!mounted) return;
              await _putAndRefresh(SettingsKeys.displayMode, next.toString());
            } catch (_) {
              if (mounted) KazumiDialog.showToast(message: '获取显示模式失败');
            }
          },
        ),
      _TvSwitchTile(
        title: '减少界面过渡动画',
        subtitle: '在低配电视盒子上开启可提高界面响应速度',
        value: disableAnimations,
        onChanged: (v) =>
            _putAndRefresh(SettingsKeys.playerDisableAnimations, v),
      ),
      _TvSwitchTile(
        title: '在番剧封面显示 Bangumi 评分',
        value: showRating,
        onChanged: (v) => _putAndRefresh(SettingsKeys.showRating, v),
      ),
    ];
  }

  List<Widget> _buildAboutSettings() {
    final autoUpdate = GStorage.getSetting(SettingsKeys.autoUpdate);
    final activeRepo = TvUpdateConfig.activeRepo;
    final customRepo = GStorage.getSetting(SettingsKeys.tvUpdateRepo);
    final mirrorMode = TvUpdateConfig.activeMirrorMode;
    final customMirrorUrl = TvUpdateConfig.customMirrorUrl;
    final ignoredVersion = TvUpdateConfig.ignoredVersion;
    final mirrorSubtitle = mirrorMode == TvUpdateMirrorMode.custom &&
            customMirrorUrl.isNotEmpty
        ? '${mirrorMode.label}（$customMirrorUrl）'
        : '${mirrorMode.label} · ${mirrorMode.description}';

    return [
      _TvActionTile(
        title: '检查应用更新',
        subtitle: _checkingUpdate
            ? '正在检查更新…'
            : '当前版本 v${ApiEndpoints.version} · $activeRepo',
        icon: Icons.system_update_rounded,
        onTap: () async {
          if (_checkingUpdate) return;
          setState(() => _checkingUpdate = true);
          try {
            await checkTvUpdatesInteractively(context);
          } finally {
            if (mounted) {
              setState(() => _checkingUpdate = false);
            }
          }
        },
      ),
      _TvSwitchTile(
        title: '启动时自动检查更新',
        subtitle: '在进入首页后静默检查是否有新版本发布',
        value: autoUpdate,
        onChanged: (v) => _putAndRefresh(SettingsKeys.autoUpdate, v),
      ),
      _TvActionTile(
        title: '更新下载镜像',
        subtitle: mirrorSubtitle,
        icon: Icons.cloud_download_rounded,
        onTap: () async {
          final updated = await pickTvUpdateMirror(context);
          if (updated != null && mounted) {
            _refresh();
          }
        },
      ),
      _TvActionTile(
        title: '更新仓库',
        subtitle: activeRepo,
        icon: Icons.source_rounded,
        onTap: () async {
          final raw = await showTvInputDialog(
            context,
            title: '更新仓库',
            initialValue: customRepo,
            hintText: 'owner/repo 或 GitHub 地址，留空恢复默认 (${TvUpdateConfig.defaultRepo})',
          );
          if (raw == null || !mounted) return;
          final trimmed = raw.trim();
          if (trimmed.isEmpty) {
            await _putAndRefresh(SettingsKeys.tvUpdateRepo, '');
            if (mounted) {
              KazumiDialog.showToast(message: '已恢复默认更新仓库');
            }
            return;
          }
          final normalized = TvUpdateConfig.normalizeRepo(trimmed);
          if (normalized == null) {
            KazumiDialog.showToast(
              message: '仓库格式无效，请输入 owner/repo 或 GitHub 仓库地址',
            );
            return;
          }
          await _putAndRefresh(SettingsKeys.tvUpdateRepo, normalized);
          if (mounted) {
            KazumiDialog.showToast(message: '更新仓库已设为 $normalized');
          }
        },
      ),
      if (ignoredVersion.isNotEmpty)
        _TvActionTile(
          title: '已忽略版本 v$ignoredVersion',
          subtitle: '点击清除忽略标记，恢复该版本的更新提醒',
          icon: Icons.notifications_off_outlined,
          onTap: () async {
            await TvUpdateConfig.setIgnoredVersion('');
            if (mounted) {
              _refresh();
              KazumiDialog.showToast(message: '已清除忽略版本 v$ignoredVersion');
            }
          },
        ),
      _TvActionTile(
        title: 'Kazumi TV v${ApiEndpoints.version}',
        subtitle:
            '基于 Predidit/Kazumi (2.4.6) 构建的纯 Android TV 专用客户端 · GPL-3.0',
        icon: Icons.tv_rounded,
        onTap: () {
          KazumiDialog.showToast(
            message:
                'Kazumi TV v${ApiEndpoints.version} · 规则 API Lv.${ApiEndpoints.apiLevel}',
          );
        },
      ),
      _TvActionTile(
        title: '查看运行日志',
        subtitle: '排查规则解析与播放器报错信息',
        icon: Icons.receipt_long_rounded,
        onTap: () => context.pushNamed('/logs'),
      ),
      _TvActionTile(
        title: '开源许可协议',
        subtitle: '查看 GPL-3.0 与第三方依赖开源许可',
        icon: Icons.description_outlined,
        onTap: () {
          showLicensePage(
            context: context,
            applicationName: 'Kazumi TV',
            applicationVersion: ApiEndpoints.version,
            applicationLegalese:
                'Based on Predidit/Kazumi · GNU General Public License v3.0',
          );
        },
      ),
    ];
  }
}

class _TvSwitchTile extends StatelessWidget {
  const _TvSwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        borderRadius: 12,
        scaleOnFocus: 1.015,
        onSelect: () => onChanged(!value),
        builder: (context, focused) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: focused
                  ? colors.surfaceContainerHighest
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeFocus(
                  child: IgnorePointer(
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvOptionTile extends StatelessWidget {
  const _TvOptionTile({
    required this.title,
    this.subtitle,
    required this.valueText,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final String valueText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        borderRadius: 12,
        scaleOnFocus: 1.015,
        onSelect: onTap,
        builder: (context, focused) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: focused
                  ? colors.surfaceContainerHighest
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TvActionTile extends StatelessWidget {
  const _TvActionTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        borderRadius: 12,
        scaleOnFocus: 1.015,
        onSelect: onTap,
        builder: (context, focused) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: focused
                  ? colors.surfaceContainerHighest
                  : colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: colors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
