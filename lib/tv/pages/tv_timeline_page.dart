import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/timeline/timeline_controller.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_poster_grid.dart';
import 'package:kazumi/utils/anime_season.dart';

class TvTimelinePage extends StatefulWidget {
  const TvTimelinePage({super.key, required this.controller});

  final TimelineController controller;

  @override
  State<TvTimelinePage> createState() => _TvTimelinePageState();
}

class _TvTimelinePageState extends State<TvTimelinePage> {
  static const List<String> _weekdayLabels = [
    '周一',
    '周二',
    '周三',
    '周四',
    '周五',
    '周六',
    '周日',
  ];

  late int _selectedWeekday = DateTime.now().weekday - 1;
  final ScrollController _scrollController = ScrollController();

  TimelineController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_controller.bangumiCalendar.isEmpty && !_controller.isLoading) {
      unawaited(_controller.loadSeason(_controller.selectedDate));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _shiftSeason(int monthsDelta) {
    final current = _controller.selectedDate;
    final next = DateTime(current.year, current.month + monthsDelta, 1);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    unawaited(_controller.loadSeason(next));
  }

  void _cycleSort() {
    final nextSort = switch (_controller.sort) {
      TimelineSort.popularity => TimelineSort.rating,
      TimelineSort.rating => TimelineSort.defaultOrder,
      TimelineSort.defaultOrder => TimelineSort.popularity,
    };
    _controller.changeSort(nextSort);
  }

  String _sortLabel(TimelineSort sort) => switch (sort) {
        TimelineSort.popularity => '按热度',
        TimelineSort.rating => '按评分',
        TimelineSort.defaultOrder => '默认排序',
      };

  Future<void> _showFiltersDialog() async {
    final choice = await showTvChoiceDialog<String>(
      context,
      title: '时间表筛选',
      options: [
        TvChoiceOption(
          value: 'watching',
          label: '只看在看番剧',
          subtitle: _controller.onlyShowWatchingBangumis ? '当前：已开启' : '当前：未开启',
          icon: _controller.onlyShowWatchingBangumis
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
        ),
        TvChoiceOption(
          value: 'watched',
          label: '隐藏已看过番剧',
          subtitle: _controller.notShowWatchedBangumis ? '当前：已开启' : '当前：未开启',
          icon: _controller.notShowWatchedBangumis
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
        ),
        TvChoiceOption(
          value: 'abandoned',
          label: '隐藏已抛弃番剧',
          subtitle: _controller.notShowAbandonedBangumis ? '当前：已开启' : '当前：未开启',
          icon: _controller.notShowAbandonedBangumis
              ? Icons.check_box_rounded
              : Icons.check_box_outline_blank_rounded,
        ),
        const TvChoiceOption(
          value: 'clear',
          label: '清除全部筛选',
          icon: Icons.clear_all_rounded,
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'watching':
        await _controller
            .setOnlyShowWatchingBangumis(!_controller.onlyShowWatchingBangumis);
      case 'watched':
        await _controller
            .setNotShowWatchedBangumis(!_controller.notShowWatchedBangumis);
      case 'abandoned':
        await _controller
            .setNotShowAbandonedBangumis(!_controller.notShowAbandonedBangumis);
      case 'clear':
        await _controller.clearFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final todayIdx = DateTime.now().weekday - 1;

    return Observer(
      builder: (context) {
        final watchingIds = _controller.loadWatchingBangumiIds();
        final filtered = _controller.filterCalendar(watchingIds);
        final dayItems =
            _selectedWeekday >= 0 && _selectedWeekday < filtered.length
                ? filtered[_selectedWeekday]
                : const <Never>[];
        final seasonTitle = AnimeSeason(_controller.selectedDate).toString();
        final filterCount = _controller.activeFilterCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 8),
              child: Row(
                children: [
                  const Text(
                    '新番放送',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    seasonTitle,
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TvSecondaryButton(
                    label: '上一季',
                    icon: Icons.chevron_left_rounded,
                    onPressed: () {
                      if (!_controller.isLoading) _shiftSeason(-3);
                    },
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          TvKeys.isLeftKey(event.logicalKey)) {
                        TvShellScope.maybeOf(context)?.focusRail();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                  ),
                  const SizedBox(width: 10),
                  TvSecondaryButton(
                    label: '下一季',
                    icon: Icons.chevron_right_rounded,
                    onPressed: () {
                      if (!_controller.isLoading) _shiftSeason(3);
                    },
                  ),
                  const SizedBox(width: 10),
                  TvSecondaryButton(
                    label: _sortLabel(_controller.sort),
                    icon: Icons.sort_rounded,
                    onPressed: _cycleSort,
                  ),
                  const SizedBox(width: 10),
                  TvSecondaryButton(
                    label: filterCount > 0 ? '筛选 ($filterCount)' : '筛选',
                    icon: Icons.filter_list_rounded,
                    selected: filterCount > 0,
                    onPressed: _showFiltersDialog,
                  ),
                  const SizedBox(width: 10),
                  TvIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新时间表',
                    onPressed: () {
                      if (!_controller.isLoading) {
                        unawaited(
                          _controller.loadSeason(_controller.selectedDate),
                        );
                      }
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
                  itemCount: _weekdayLabels.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final label = index == todayIdx
                        ? '${_weekdayLabels[index]} · 今天'
                        : _weekdayLabels[index];
                    return TvChip(
                      label: label,
                      selected: _selectedWeekday == index,
                      onSelect: () {
                        setState(() => _selectedWeekday = index);
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
                items: dayItems,
                isLoading: _controller.isLoading &&
                    _controller.bangumiCalendar.isEmpty,
                hasError: _controller.isTimeOut &&
                    _controller.bangumiCalendar.isEmpty,
                errorTitle: '时间表加载失败',
                errorMessage: '请检查网络连接后重试',
                emptyTitle: filterCount > 0 ? '当前筛选条件下暂无番剧' : '当日暂无放送番剧',
                onRetry: () => _controller.loadSeason(_controller.selectedDate),
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
