import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_poster_grid.dart';

class TvCollectPage extends StatefulWidget {
  const TvCollectPage({super.key, required this.controller});

  final CollectController controller;

  @override
  State<TvCollectPage> createState() => _TvCollectPageState();
}

class _TvCollectPageState extends State<TvCollectPage> {
  static const List<CollectType> _tabs = [
    CollectType.watching,
    CollectType.planToWatch,
    CollectType.watched,
    CollectType.onHold,
    CollectType.abandoned,
  ];

  CollectType _selectedType = CollectType.watching;
  bool _syncing = false;
  final ScrollController _scrollController = ScrollController();

  CollectController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.loadCollectibles();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showItemActions(BangumiItem item) async {
    final currentType = _controller.getCollectType(item);
    final action = await showTvChoiceDialog<int>(
      context,
      title: item.nameCn.isNotEmpty ? item.nameCn : item.name,
      subtitle: '选择操作或修改追番状态（按菜单键/长按确定可随时打开）',
      options: [
        const TvChoiceOption(
          value: -1,
          label: '打开番剧详情',
          icon: Icons.info_outline_rounded,
        ),
        for (final type in _tabs)
          if (type.value != currentType)
            TvChoiceOption(
              value: type.value,
              label: '移至「${type.label}」',
              icon: Icons.bookmark_border_rounded,
            ),
        const TvChoiceOption(
          value: 0,
          label: '取消收藏',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
    if (action == null || !mounted) return;
    if (action == -1) {
      context.pushNamed('/info/', arguments: item);
    } else if (action == 0) {
      await _controller.deleteCollect(item);
    } else {
      await _controller.addCollect(item, type: action);
    }
  }

  Future<void> _syncCollections() async {
    if (_syncing) return;
    final webDavCollect = GStorage.getSetting(SettingsKeys.webDavEnable) &&
        GStorage.getSetting(SettingsKeys.webDavEnableCollect);
    final bangumiSync = GStorage.getSetting(SettingsKeys.bangumiSyncEnable);

    if (!webDavCollect && !bangumiSync) {
      KazumiDialog.showToast(message: '请先在「设置 -> 同步与数据」中启用同步');
      return;
    }

    setState(() => _syncing = true);
    try {
      if (bangumiSync) {
        final ok = await _controller.syncCollectiblesBangumi(
          onProgress: (_, __, ___) {},
          onError: (msg) => KazumiDialog.showToast(message: msg),
        );
        if (ok && webDavCollect) {
          await _controller.uploadCollectiblesToWebDav(
            onError: (msg) => KazumiDialog.showToast(message: msg),
          );
        }
        if (ok) {
          KazumiDialog.showToast(message: '追番同步完成');
        }
      } else if (webDavCollect) {
        final ok = await _controller.syncCollectibles(
          onError: (msg) => KazumiDialog.showToast(message: msg),
        );
        if (ok) {
          KazumiDialog.showToast(message: 'WebDAV 收藏同步完成');
        }
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Observer(
      builder: (context) {
        final all = _controller.collectibles.toList();
        final counts = <int, int>{
          for (final t in _tabs) t.value: 0,
        };
        for (final entry in all) {
          counts[entry.type] = (counts[entry.type] ?? 0) + 1;
        }
        final filtered = all
            .where((entry) => entry.type == _selectedType.value)
            .map((entry) => entry.bangumiItem)
            .toList()
            .reversed
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 8),
              child: Row(
                children: [
                  const Text(
                    '我的收藏',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '共 ${all.length} 部',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TvSecondaryButton(
                    label: _syncing ? '同步中…' : '同步收藏',
                    icon: Icons.sync_rounded,
                    onPressed: _syncCollections,
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
            SizedBox(
              height: 56,
              child: TvAxisClipRect(
                axis: Axis.horizontal,
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: _tabs.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final tab = _tabs[index];
                    final count = counts[tab.value] ?? 0;
                    return TvChip(
                      label: '${tab.label} ($count)',
                      selected: _selectedType == tab,
                      onSelect: () {
                        setState(() => _selectedType = tab);
                        if (_scrollController.hasClients) {
                          _scrollController.jumpTo(0);
                        }
                      },
                      onKeyEvent: index == 0
                          ? (_, event) {
                              if (event is KeyDownEvent &&
                                  TvKeys.isLeftKey(event.logicalKey)) {
                                TvShellScope.maybeOf(context)?.focusRail();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            }
                          : null,
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: TvPosterGrid(
                scrollController: _scrollController,
                items: filtered,
                emptyTitle: '「${_selectedType.label}」暂无番剧',
                emptyIcon: Icons.bookmarks_outlined,
                onLeftBoundary: () => TvShellScope.maybeOf(context)?.focusRail(),
                onItemSelected: (item) {
                  context.pushNamed('/info/', arguments: item);
                },
                onItemLongSelected: _showItemActions,
              ),
            ),
          ],
        );
      },
    );
  }
}
