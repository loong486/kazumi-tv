import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvPlayerDrawer extends StatefulWidget {
  const TvPlayerDrawer({
    super.key,
    required this.initialTab,
    required this.videoPageController,
    required this.playerController,
    required this.onTabChanged,
    required this.onClose,
    required this.onSelectEpisode,
    required this.onToggleDanmaku,
    required this.onSearchDanmaku,
    required this.onDanmakuStyleChanged,
    required this.onChangeSpeed,
    required this.onChangeAspectRatio,
    required this.onChangeSuperResolution,
    required this.onReloadEpisode,
    required this.showDebugLog,
    required this.onToggleDebugLog,
  });

  final int initialTab;
  final VideoPageController videoPageController;
  final PlayerController playerController;
  final ValueChanged<int> onTabChanged;
  final VoidCallback onClose;
  final void Function(int episode, int road) onSelectEpisode;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onSearchDanmaku;
  final VoidCallback onDanmakuStyleChanged;
  final ValueChanged<double> onChangeSpeed;
  final ValueChanged<PlayerAspectRatio> onChangeAspectRatio;
  final ValueChanged<SuperResolutionMode> onChangeSuperResolution;
  final VoidCallback onReloadEpisode;
  final bool showDebugLog;
  final VoidCallback onToggleDebugLog;

  @override
  State<TvPlayerDrawer> createState() => _TvPlayerDrawerState();
}

class _TvPlayerDrawerState extends State<TvPlayerDrawer> {
  static const List<String> _tabs = ['选集', '弹幕', '播放'];

  late int _tabIndex = widget.initialTab.clamp(0, 2);
  late int _viewingRoad = widget.videoPageController.selectedEpisode.road;

  @override
  void didUpdateWidget(TvPlayerDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      _tabIndex = widget.initialTab.clamp(0, 2);
    }
  }

  void _selectTab(int idx) {
    setState(() => _tabIndex = idx);
    widget.onTabChanged(idx);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerRight,
      child: FocusScope(
        autofocus: true,
        child: Container(
          width: 440,
          height: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xEB12151F),
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
            ),
          ),
          child: SafeArea(
            left: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++) ...[
                        TvChip(
                          label: _tabs[i],
                          selected: _tabIndex == i,
                          onSelect: () => _selectTab(i),
                        ),
                        if (i < _tabs.length - 1) const SizedBox(width: 8),
                      ],
                      const Spacer(),
                      TvIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '关闭面板',
                        size: 38,
                        iconSize: 20,
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colors.outlineVariant.withValues(alpha: 0.25)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: switch (_tabIndex) {
                      0 => _buildEpisodesTab(colors),
                      1 => _buildDanmakuTab(colors),
                      _ => _buildPlaybackTab(colors),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodesTab(ColorScheme colors) {
    return Observer(
      builder: (context) {
        final roads = widget.videoPageController.roadList.toList();
        if (roads.isEmpty) {
          return const Center(
            child: Text('暂无可用剧集', style: TextStyle(color: Colors.white70)),
          );
        }
        final roadIndex = _viewingRoad.clamp(0, roads.length - 1);
        final Road road = roads[roadIndex];
        final selected = widget.videoPageController.selectedEpisode;
        final hasPlayingInRoad = selected.road == roadIndex &&
            selected.episode >= 1 &&
            selected.episode <= road.data.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (roads.length > 1) ...[
              SizedBox(
                height: 58,
                child: TvAxisClipRect(
                  axis: Axis.horizontal,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    itemCount: roads.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return TvChip(
                        label: roads[index].name.isNotEmpty
                            ? roads[index].name
                            : '线路 ${index + 1}',
                        selected: index == roadIndex,
                        onSelect: () => setState(() => _viewingRoad = index),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Expanded(
              child: road.data.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无可用剧集',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : TvAxisClipRect(
                      axis: Axis.vertical,
                      child: GridView.builder(
                        clipBehavior: Clip.none,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 48,
                        ),
                        itemCount: road.data.length,
                        itemBuilder: (context, index) {
                          final episodeNum = index + 1;
                          final isPlaying = selected.road == roadIndex &&
                              selected.episode == episodeNum;
                          final rawTitle = index < road.identifier.length
                              ? road.identifier[index]
                              : '$episodeNum';
                          final label =
                              rawTitle.trim().isEmpty ? '$episodeNum' : rawTitle;

                          return TvFocusable(
                            autofocus:
                                isPlaying || (!hasPlayingInRoad && index == 0),
                            borderRadius: 10,
                            scaleOnFocus: 1.03,
                            onSelect: () =>
                                widget.onSelectEpisode(episodeNum, roadIndex),
                            builder: (context, focused) {
                              return Container(
                                alignment: Alignment.center,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                decoration: BoxDecoration(
                                  color: isPlaying
                                      ? colors.primary
                                      : focused
                                          ? Colors.white.withValues(alpha: 0.22)
                                          : Colors.white
                                              .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isPlaying
                                        ? colors.onPrimary
                                        : Colors.white,
                                    fontSize: 13,
                                    fontWeight: isPlaying
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDanmakuTab(ColorScheme colors) {
    return Observer(
      builder: (context) {
        final danmakuOn = widget.playerController.danmaku.danmakuOn;
        final danmakuCount = widget.playerController.danmaku.danDanmakus.length;
        final fontSize = GStorage.getSetting(SettingsKeys.danmakuFontSize);
        final opacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
        final area = GStorage.getSetting(SettingsKeys.danmakuArea);
        final offset = GStorage.getSetting(SettingsKeys.danmakuTimeOffset);

        return TvAxisClipRect(
          axis: Axis.vertical,
          child: ListView(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.all(16),
            children: [
              _DrawerRow(
                autofocus: true,
                title: '弹幕开关',
                trailingText: danmakuOn ? '已开启' : '已关闭',
                onTap: widget.onToggleDanmaku,
              ),
              _DrawerRow(
                title: '手动检索/更换弹幕源',
                subtitle: danmakuCount > 0 ? '已加载弹幕数据' : '未匹配到弹幕或需手动搜索',
                trailingText: '搜索',
                onTap: widget.onSearchDanmaku,
              ),
              _DrawerRow(
                title: '弹幕字号（循环切换）',
                trailingText: '${fontSize.round()} px',
                onTap: () async {
                  const sizes = [18.0, 22.0, 24.0, 28.0, 32.0];
                  final nextIdx =
                      (sizes.indexWhere((s) => s >= fontSize) + 1) %
                          sizes.length;
                  await GStorage.putSetting(
                      SettingsKeys.danmakuFontSize, sizes[nextIdx]);
                  if (!mounted) return;
                  widget.onDanmakuStyleChanged();
                  setState(() {});
                },
              ),
              _DrawerRow(
                title: '弹幕不透明度（循环切换）',
                trailingText: '${(opacity * 100).round()}%',
                onTap: () async {
                  const vals = [0.4, 0.6, 0.8, 1.0];
                  final nextIdx =
                      (vals.indexWhere((v) => v >= opacity) + 1) % vals.length;
                  await GStorage.putSetting(
                      SettingsKeys.danmakuOpacity, vals[nextIdx]);
                  if (!mounted) return;
                  widget.onDanmakuStyleChanged();
                  setState(() {});
                },
              ),
              _DrawerRow(
                title: '弹幕显示区域',
                trailingText: '${(area * 100).round()}%',
                onTap: () async {
                  const areas = [0.25, 0.5, 0.75, 1.0];
                  final nextIdx =
                      (areas.indexWhere((a) => a >= area) + 1) % areas.length;
                  await GStorage.putSetting(
                      SettingsKeys.danmakuArea, areas[nextIdx]);
                  if (!mounted) return;
                  widget.onDanmakuStyleChanged();
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Text(
                '弹幕时间轴偏移：${offset >= 0 ? '+' : ''}${offset.toStringAsFixed(1)} 秒',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final delta in const [-5.0, -1.0, 0.0, 1.0, 5.0])
                    TvSecondaryButton(
                      label: delta == 0.0
                          ? '归零'
                          : '${delta > 0 ? '+' : ''}${delta.toInt()}s',
                      onPressed: () async {
                        final next = delta == 0.0 ? 0.0 : offset + delta;
                        await GStorage.putSetting(
                            SettingsKeys.danmakuTimeOffset, next);
                        if (!mounted) return;
                        widget.onDanmakuStyleChanged();
                        setState(() {});
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaybackTab(ColorScheme colors) {
    return Observer(
      builder: (context) {
        final speed = widget.playerController.playback.playerSpeed;
        final ratio = widget.playerController.panel.aspectRatioMode;
        final sr = widget.playerController.playback.superResolutionMode;

        const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        final hasMatchedSpeed = speeds.contains(speed);

        return TvAxisClipRect(
          axis: Axis.vertical,
          child: ListView(
            clipBehavior: Clip.none,
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                '播放倍速',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in speeds)
                    TvChip(
                      autofocus: hasMatchedSpeed ? speed == s : s == 0.5,
                      label: '${s}x',
                      selected: speed == s,
                      onSelect: () => widget.onChangeSpeed(s),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '画面比例',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in PlayerAspectRatio.values)
                    TvChip(
                      label: mode.label,
                      selected: ratio == mode,
                      onSelect: () => widget.onChangeAspectRatio(mode),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Anime4K 超分辨率',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in SuperResolutionMode.values)
                    TvChip(
                      label: mode.label,
                      selected: sr == mode,
                      onSelect: () => widget.onChangeSuperResolution(mode),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _DrawerRow(
                title: '重新解析当前剧集',
                trailingText: '刷新',
                onTap: widget.onReloadEpisode,
              ),
              _DrawerRow(
                title: '显示解析日志',
                trailingText: widget.showDebugLog ? '开启' : '关闭',
                onTap: widget.onToggleDebugLog,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.title,
    this.subtitle,
    required this.trailingText,
    required this.onTap,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final String trailingText;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TvFocusable(
        autofocus: autofocus,
        borderRadius: 10,
        scaleOnFocus: 1.02,
        onSelect: onTap,
        builder: (context, focused) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: focused
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
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
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailingText,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
