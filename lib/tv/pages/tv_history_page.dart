import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/utils/format.dart';

class TvHistoryPage extends StatefulWidget {
  const TvHistoryPage({
    super.key,
    required this.controller,
    required this.playbackService,
  });

  final HistoryController controller;
  final HistoryPlaybackService playbackService;

  @override
  State<TvHistoryPage> createState() => _TvHistoryPageState();
}

class _TvHistoryPageState extends State<TvHistoryPage> {
  bool _opening = false;

  HistoryController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.init();
  }

  Future<void> _resumePlayback(History history) async {
    if (_opening) return;
    _opening = true;
    final cancelToken = RuleCancelToken();
    try {
      final result = await showTvLoadingDialog<HistoryPlaybackResult>(
        context,
        message: '正在恢复播放列表…',
        cancelToken: cancelToken,
        action: () => widget.playbackService.open(
          history,
          cancelToken: cancelToken,
        ),
      );
      if (!mounted || result == null || cancelToken.isCancelled) return;
      switch (result) {
        case HistoryPlaybackReady(:final args):
          context.pushNamed('/video/', arguments: args);
        case HistoryPlaybackUnavailable(:final reason):
          final openInfo = await showTvConfirmDialog(
            context,
            title: '无法直接续播',
            message: '$reason\n\n是否跳转到番剧详情重新选择播放源？',
            confirmLabel: '选择播放源',
            cancelLabel: '关闭',
          );
          if (openInfo && mounted) {
            context.pushNamed('/info/', arguments: history.bangumiItem);
          }
      }
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(message: '暂时无法继续播放，请稍后重试');
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _showActions(History history) async {
    final title = history.bangumiItem.nameCn.isNotEmpty
        ? history.bangumiItem.nameCn
        : history.bangumiItem.name;
    final action = await showTvChoiceDialog<String>(
      context,
      title: title,
      options: const [
        TvChoiceOption(
          value: 'play',
          label: '继续播放',
          icon: Icons.play_arrow_rounded,
        ),
        TvChoiceOption(
          value: 'info',
          label: '查看番剧详情 / 换源',
          icon: Icons.info_outline_rounded,
        ),
        TvChoiceOption(
          value: 'delete',
          label: '删除此观看记录',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'play':
        await _resumePlayback(history);
      case 'info':
        context.pushNamed('/info/', arguments: history.bangumiItem);
      case 'delete':
        await _controller.deleteHistory(history);
    }
  }

  Future<void> _clearAll(int visibleCount) async {
    final confirmed = await showTvConfirmDialog(
      context,
      title: '清空观看历史',
      message: '将删除全部 $visibleCount 条观看记录，此操作无法撤销。',
      confirmLabel: '清空全部',
      destructive: true,
    );
    if (confirmed) {
      await _controller.clearAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Observer(
      builder: (context) {
        final entries = _controller.histories
            .where((h) =>
                HistoryEntryKind.normalize(h.entryKind) ==
                HistoryEntryKind.online)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 12),
              child: Row(
                children: [
                  const Text(
                    '观看历史',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    entries.isEmpty ? '' : '${entries.length} 条记录（长按确定可管理）',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (entries.isNotEmpty)
                    TvSecondaryButton(
                      label: '清空历史',
                      icon: Icons.delete_sweep_outlined,
                      onPressed: () => _clearAll(entries.length),
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent &&
                            TvKeys.isLeftKey(event.logicalKey)) {
                          TvShellScope.maybeOf(context)?.focusRail();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                    ),
                ],
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Focus(
                        onKeyEvent: (_, event) {
                          if (event is KeyDownEvent &&
                              TvKeys.isLeftKey(event.logicalKey)) {
                            TvShellScope.maybeOf(context)?.focusRail();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_toggle_off_rounded,
                              size: 52,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '还没有观看记录',
                              style: TextStyle(
                                fontSize: 18,
                                color: colors.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final cols = constraints.maxWidth >= 1360 ? 3 : 2;
                        return TvAxisClipRect(
                          axis: Axis.vertical,
                          child: GridView.builder(
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.fromLTRB(36, 20, 36, 32),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              mainAxisSpacing: TvLayout.gridSpacing,
                              crossAxisSpacing: TvLayout.gridSpacing,
                              mainAxisExtent: 112,
                            ),
                            itemCount: entries.length,
                            itemBuilder: (context, index) {
                              final history = entries[index];
                              final isLeftCol = index % cols == 0;
                              return _TvHistoryCard(
                                history: history,
                                onSelect: () => _resumePlayback(history),
                                onLongSelect: () => _showActions(history),
                                onKeyEvent: isLeftCol
                                    ? (_, event) {
                                        if (event is KeyDownEvent &&
                                            TvKeys.isLeftKey(
                                                event.logicalKey)) {
                                          TvShellScope.maybeOf(context)
                                              ?.focusRail();
                                          return KeyEventResult.handled;
                                        }
                                        return KeyEventResult.ignored;
                                      }
                                    : null,
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _TvHistoryCard extends StatelessWidget {
  const _TvHistoryCard({
    required this.history,
    required this.onSelect,
    required this.onLongSelect,
    this.onKeyEvent,
  });

  final History history;
  final VoidCallback onSelect;
  final VoidCallback onLongSelect;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final item = history.bangumiItem;
    final title = item.nameCn.isNotEmpty ? item.nameCn : item.name;
    final poster = item.images['large'] ?? item.images['common'] ?? '';
    final progress = history.progresses[history.lastWatchEpisode];
    final episodeLabel = history.lastWatchEpisodeName.isNotEmpty
        ? history.lastWatchEpisodeName
        : '第 ${history.lastWatchEpisode} 集';
    final timeStr = progress != null && progress.progress > Duration.zero
        ? '已看 ${durationToString(progress.progress)}'
        : '刚刚开始';

    return TvFocusable(
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      onKeyEvent: onKeyEvent,
      borderRadius: 14,
      scaleOnFocus: 1.03,
      builder: (context, focused) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: focused
                ? colors.surfaceContainerHighest
                : colors.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 0.72,
                child: NetworkImgLayer(
                  src: poster,
                  width: 110,
                  height: 150,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              history.adapterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            episodeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '$timeStr · ${_formatDate(history.lastWatchTime)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.play_circle_filled_rounded,
                size: 32,
                color: focused ? colors.primary : colors.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$m-$d $hh:$mm';
  }
}
