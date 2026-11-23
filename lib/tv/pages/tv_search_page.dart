import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/search/search_history_module.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_poster_grid.dart';
import 'package:kazumi/utils/constants.dart';

class TvSearchPage extends StatefulWidget {
  const TvSearchPage({
    super.key,
    required this.controller,
    this.initialQuery = '',
  });

  final SearchPageController controller;
  final String initialQuery;

  @override
  State<TvSearchPage> createState() => _TvSearchPageState();
}

class _TvSearchPageState extends State<TvSearchPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _searchWrapperFocus =
      FocusNode(debugLabel: 'TvSearchBarWrapper');
  final FocusNode _textFieldFocus = FocusNode(
    debugLabel: 'TvSearchTextField',
    skipTraversal: true,
    canRequestFocus: false,
  );
  final FocusNode _resultsScope = FocusNode(debugLabel: 'TvSearchResults');
  final GlobalKey _hotTagsWrapKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  String _activeQuery = '';
  bool _hasSearched = false;
  int _searchTicket = 0;

  SearchPageController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _textFieldFocus.addListener(_handleTextFieldFocusChange);
    _controller.loadSearchHistories();
    if (widget.initialQuery.trim().isNotEmpty) {
      _textController.text = widget.initialQuery.trim();
      unawaited(_runSearch(widget.initialQuery.trim()));
    }
  }

  @override
  void dispose() {
    _textFieldFocus.removeListener(_handleTextFieldFocusChange);
    _textController.dispose();
    _searchWrapperFocus.dispose();
    _textFieldFocus.dispose();
    _resultsScope.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTextFieldFocusChange() {
    if (!_textFieldFocus.hasFocus && _textFieldFocus.canRequestFocus) {
      _textFieldFocus.canRequestFocus = false;
    }
  }

  void _openImeInput() {
    _textFieldFocus.canRequestFocus = true;
    _textFieldFocus.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  Future<void> _runSearch(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    final ticket = ++_searchTicket;
    _textController.text = query;
    setState(() {
      _activeQuery = query;
      _hasSearched = true;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _controller.searchBangumi(query, type: 'init');
    if (!mounted ||
        !_hasSearched ||
        ticket != _searchTicket ||
        _controller.bangumiList.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_hasSearched ||
          ticket != _searchTicket ||
          _controller.bangumiList.isEmpty) {
        return;
      }
      _resultsScope.descendants
          .where((n) => n.canRequestFocus && !n.skipTraversal)
          .firstOrNull
          ?.requestFocus();
    });
  }

  Future<void> _confirmDeleteHistory(SearchHistory history) async {
    final ok = await showTvConfirmDialog(
      context,
      title: '删除搜索记录',
      message: '确认删除「${history.keyword}」吗？',
      confirmLabel: '删除',
      destructive: true,
    );
    if (ok) {
      await _controller.deleteSearchHistory(history);
    }
  }

  Future<void> _confirmClearHistories() async {
    final ok = await showTvConfirmDialog(
      context,
      title: '清空搜索历史',
      message: '确认清空全部搜索历史记录吗？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (ok) {
      await _controller.clearSearchHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Observer(
      builder: (context) {
        final histories = _controller.searchHistories.toList();
        final results = _controller.bangumiList.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 10),
              child: Row(
                children: [
                  const Text(
                    '搜索番剧',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: TvFocusable(
                      focusNode: _searchWrapperFocus,
                      borderRadius: 14,
                      scaleOnFocus: 1.015,
                      onSelect: _openImeInput,
                      onKeyEvent: (_, event) {
                        if (!_textFieldFocus.hasFocus &&
                            event is KeyDownEvent &&
                            TvKeys.isLeftKey(event.logicalKey)) {
                          TvShellScope.maybeOf(context)?.focusRail();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      builder: (context, focused) {
                        return Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  color: colors.onSurfaceVariant),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Focus(
                                  skipTraversal: true,
                                  canRequestFocus: false,
                                  onKeyEvent: (_, event) {
                                    if (event is KeyDownEvent &&
                                        _textFieldFocus.hasFocus) {
                                      if (TvKeys.isKeyboardBackKey(
                                          event.logicalKey)) {
                                        _textFieldFocus.canRequestFocus = false;
                                        _searchWrapperFocus.requestFocus();
                                        return KeyEventResult.handled;
                                      }
                                      if (TvKeys.isDownKey(event.logicalKey)) {
                                        _textFieldFocus.canRequestFocus = false;
                                        _searchWrapperFocus.requestFocus();
                                        _searchWrapperFocus.focusInDirection(
                                          TraversalDirection.down,
                                        );
                                        return KeyEventResult.handled;
                                      }
                                    }
                                    return KeyEventResult.ignored;
                                  },
                                  child: TextField(
                                    controller: _textController,
                                    focusNode: _textFieldFocus,
                                    textInputAction: TextInputAction.search,
                                    style: const TextStyle(fontSize: 15),
                                    decoration: const InputDecoration(
                                      hintText: '按确定键输入番剧名称、标签或 Bangumi ID',
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    onTap: _openImeInput,
                                    onSubmitted: (value) {
                                      _textFieldFocus.canRequestFocus = false;
                                      _searchWrapperFocus.requestFocus();
                                      unawaited(_runSearch(value));
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  TvPrimaryButton(
                    label: '搜索',
                    icon: Icons.search_rounded,
                    onPressed: () => unawaited(_runSearch(_textController.text)),
                  ),
                  const SizedBox(width: 10),
                  TvSecondaryButton(
                    label: '清空',
                    icon: Icons.close_rounded,
                    onPressed: () {
                      ++_searchTicket;
                      _textController.clear();
                      _controller.bangumiList.clear();
                      setState(() {
                        _activeQuery = '';
                        _hasSearched = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            if (histories.isNotEmpty)
              SizedBox(
                height: 56,
                child: TvAxisClipRect(
                  axis: Axis.horizontal,
                  child: ListView.separated(
                    clipBehavior: Clip.none,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
                    scrollDirection: Axis.horizontal,
                    itemCount: histories.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      if (index == histories.length) {
                        return TvChip(
                          label: '清空历史',
                          icon: Icons.delete_sweep_outlined,
                          selected: false,
                          onSelect: _confirmClearHistories,
                        );
                      }
                      final history = histories[index];
                      return TvChip(
                        label: history.keyword,
                        icon: Icons.history_rounded,
                        selected: _activeQuery == history.keyword,
                        onSelect: () => unawaited(_runSearch(history.keyword)),
                        onLongSelect: () => _confirmDeleteHistory(history),
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
            if (!_hasSearched)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(36, 18, 36, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '热门标签快捷搜索',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Wrap(
                          key: _hotTagsWrapKey,
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final tag in defaultAnimeTags)
                              TvChip(
                                label: tag,
                                selected: false,
                                onSelect: () =>
                                    unawaited(_runSearch('tag:$tag')),
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent &&
                                      TvKeys.isLeftKey(event.logicalKey)) {
                                    final wrapObj = _hotTagsWrapKey
                                        .currentContext
                                        ?.findRenderObject();
                                    final chipObj =
                                        node.context?.findRenderObject();
                                    if (wrapObj is RenderBox &&
                                        chipObj is RenderBox &&
                                        chipObj
                                                .localToGlobal(
                                                  Offset.zero,
                                                  ancestor: wrapObj,
                                                )
                                                .dx <=
                                            4.0) {
                                      TvShellScope.maybeOf(context)?.focusRail();
                                      return KeyEventResult.handled;
                                    }
                                  }
                                  return KeyEventResult.ignored;
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: Focus(
                  focusNode: _resultsScope,
                  skipTraversal: true,
                  child: TvPosterGrid(
                    scrollController: _scrollController,
                    items: results,
                    isLoading: _controller.isLoading && results.isEmpty,
                    isLoadingMore: _controller.isLoading && results.isNotEmpty,
                    hasError: _controller.isTimeOut && results.isEmpty,
                    errorTitle: '未找到相关番剧或请求超时',
                    errorMessage: '请尝试更换关键词或检查网络连接',
                    emptyTitle: '没有找到「$_activeQuery」相关番剧',
                    emptyIcon: Icons.search_off_rounded,
                    onRetry: () => unawaited(_runSearch(_activeQuery)),
                    onLoadMore: _controller.hasMoreSearchResults
                        ? () => unawaited(
                              _controller.searchBangumi(
                                _activeQuery,
                                type: 'add',
                              ),
                            )
                        : null,
                    onLeftBoundary: () =>
                        TvShellScope.maybeOf(context)?.focusRail(),
                    onItemSelected: (item) {
                      context.pushNamed('/info/', arguments: item);
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
