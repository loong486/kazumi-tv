import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/popular/popular_controller.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_poster_grid.dart';
import 'package:kazumi/utils/constants.dart';

class TvPopularPage extends StatefulWidget {
  const TvPopularPage({super.key, required this.controller});

  final PopularController controller;

  @override
  State<TvPopularPage> createState() => _TvPopularPageState();
}

class _TvPopularPageState extends State<TvPopularPage> {
  final ScrollController _scrollController = ScrollController();

  PopularController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.currentTag.isEmpty && _controller.trendList.isEmpty) {
      unawaited(_controller.queryBangumiByTrend(type: 'init'));
    } else if (_controller.currentTag.isNotEmpty &&
        _controller.bangumiList.isEmpty) {
      unawaited(_controller.queryBangumiByTag(type: 'init'));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectTag(String tag) {
    if (_controller.currentTag == tag) return;
    _controller.setCurrentTag(tag);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (tag.isEmpty) {
      if (_controller.trendList.isEmpty) {
        unawaited(_controller.queryBangumiByTrend(type: 'init'));
      }
    } else {
      unawaited(_controller.queryBangumiByTag(type: 'init'));
    }
  }

  void _refresh() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (_controller.currentTag.isEmpty) {
      unawaited(_controller.queryBangumiByTrend(type: 'init'));
    } else {
      unawaited(_controller.queryBangumiByTag(type: 'init'));
    }
  }

  void _loadMore() {
    if (_controller.isLoadingMore) return;
    if (_controller.currentTag.isEmpty) {
      unawaited(_controller.queryBangumiByTrend(type: 'add'));
    } else {
      unawaited(_controller.queryBangumiByTag(type: 'add'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tags = <String>['', ...defaultAnimeTags];

    return Observer(
      builder: (context) {
        final currentTag = _controller.currentTag;
        final items = currentTag.isEmpty
            ? _controller.trendList.toList()
            : _controller.bangumiList.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 8),
              child: Row(
                children: [
                  const Text(
                    '热门番剧',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    currentTag.isEmpty ? '近期趋势' : '标签 · $currentTag',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TvIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新列表',
                    onPressed: _refresh,
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
                  itemCount: tags.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final tag = tags[index];
                    final label = tag.isEmpty ? '全部趋势' : tag;
                    return TvChip(
                      label: label,
                      selected: currentTag == tag,
                      onSelect: () => _selectTag(tag),
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
                items: items,
                isLoading: _controller.isLoadingMore && items.isEmpty,
                isLoadingMore: _controller.isLoadingMore && items.isNotEmpty,
                hasError: _controller.isTimeOut && items.isEmpty,
                errorTitle: '番剧列表加载失败',
                errorMessage: '请检查网络或切换「设置 -> 网络与代理」中的加速方式',
                emptyTitle: '暂无番剧数据',
                onRetry: _refresh,
                onLoadMore: _loadMore,
                onLeftBoundary: () => TvShellScope.maybeOf(context)?.focusRail(),
                onItemSelected: (item) {
                  context.pushNamed('/info/', arguments: item);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
