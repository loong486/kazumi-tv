import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/tv/widgets/tv_poster_card.dart';

class TvInfoPage extends StatefulWidget {
  const TvInfoPage({
    super.key,
    required this.inputBangumiItem,
    required this.infoController,
    required this.pluginsController,
    required this.collectController,
    required this.historyController,
    required this.historyPlaybackService,
  });

  final BangumiItem inputBangumiItem;
  final InfoController infoController;
  final PluginsController pluginsController;
  final CollectController collectController;
  final HistoryController historyController;
  final HistoryPlaybackService historyPlaybackService;

  @override
  State<TvInfoPage> createState() => _TvInfoPageState();
}

class _TvInfoPageState extends State<TvInfoPage> {
  late final PluginSearchService _searchService;
  final Map<String, String> _sourceKeywords = {};
  final FocusNode _sourceSectionFocus =
      FocusNode(debugLabel: 'TvInfoSourceSection');

  String _baseKeyword = '';
  String? _selectedPluginName;
  bool _userPickedPlugin = false;
  bool _openingVideo = false;

  InfoController get _info => widget.infoController;

  @override
  void initState() {
    super.initState();
    _info.bangumiItem = widget.inputBangumiItem;
    widget.historyController.init();
    _baseKeyword = _resolveTitle(widget.inputBangumiItem);

    _searchService = PluginSearchService(
      infoController: _info,
      pluginsController: widget.pluginsController,
    );

    if (widget.pluginsController.pluginList.isNotEmpty) {
      _selectedPluginName = widget.pluginsController.pluginList.first.name;
      unawaited(_searchService.queryAllSource(_baseKeyword));
    }

    unawaited(_refreshBangumiDetails());
    unawaited(_loadRelations());
  }

  @override
  void dispose() {
    _searchService.cancel();
    _sourceSectionFocus.dispose();
    super.dispose();
  }

  String _resolveTitle(BangumiItem item) =>
      item.nameCn.isNotEmpty ? item.nameCn : item.name;

  Future<void> _refreshBangumiDetails() async {
    final item = widget.inputBangumiItem;
    if (item.summary.isNotEmpty && item.tags.isNotEmpty) return;
    try {
      await _info.queryBangumiInfoByID(item.id, type: 'update');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadRelations() async {
    try {
      await _info.queryBangumiRelationsByID(widget.inputBangumiItem.id);
    } catch (_) {}
  }

  History? _findLatestHistory() {
    final id = _info.bangumiItem.id;
    History? latest;
    for (final h in widget.historyController.histories) {
      if (h.bangumiItem.id == id &&
          HistoryEntryKind.normalize(h.entryKind) == HistoryEntryKind.online) {
        if (latest == null || h.lastWatchTime.isAfter(latest.lastWatchTime)) {
          latest = h;
        }
      }
    }
    return latest;
  }

  void _focusSourceSection() {
    _sourceSectionFocus.descendants
        .where((n) => n.canRequestFocus && !n.skipTraversal)
        .firstOrNull
        ?.requestFocus();
  }

  Future<void> _resumeHistory(History history) async {
    if (_openingVideo) return;
    _openingVideo = true;
    final cancelToken = RuleCancelToken();
    try {
      final result = await showTvLoadingDialog<HistoryPlaybackResult>(
        context,
        message: '正在恢复播放列表…',
        cancelToken: cancelToken,
        action: () => widget.historyPlaybackService.open(
          history,
          cancelToken: cancelToken,
        ),
      );
      if (!mounted || result == null || cancelToken.isCancelled) return;
      switch (result) {
        case HistoryPlaybackReady(:final args):
          context.pushNamed('/video/', arguments: args);
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
          _focusSourceSection();
      }
    } catch (_) {
      if (mounted) {
        KazumiDialog.showToast(message: '恢复播放失败，请在下方选择播放源');
      }
    } finally {
      _openingVideo = false;
    }
  }

  Future<void> _pickCollectStatus() async {
    final item = _info.bangumiItem;
    final current = widget.collectController.getCollectType(item);
    final selected = await showTvChoiceDialog<int>(
      context,
      title: '追番收藏状态',
      subtitle: _resolveTitle(item),
      currentValue: current,
      options: [
        for (final type in [
          CollectType.watching,
          CollectType.planToWatch,
          CollectType.watched,
          CollectType.onHold,
          CollectType.abandoned,
        ])
          TvChoiceOption(
            value: type.value,
            label: type.label,
            icon: Icons.bookmark_rounded,
          ),
        if (current != 0)
          const TvChoiceOption(
            value: 0,
            label: '取消收藏',
            icon: Icons.delete_outline_rounded,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    try {
      if (selected == 0) {
        await widget.collectController.deleteCollect(item);
      } else {
        await widget.collectController.addCollect(item, type: selected);
      }
    } catch (e) {
      KazumiLogger().w('TvInfoPage: failed to update collect status', error: e);
      if (mounted) KazumiDialog.showToast(message: '收藏操作失败');
    }
  }

  Future<void> _searchWithAliasOrCustom() async {
    final aliases = _info.bangumiItem.alias;
    final selected = await showTvChoiceDialog<String>(
      context,
      title: '更换搜索关键词',
      subtitle: '若原译名未能匹配到片源，可尝试别名或手动输入关键词',
      options: [
        const TvChoiceOption(
          value: '__custom__',
          label: '手动输入关键词…',
          icon: Icons.edit_rounded,
        ),
        if (_info.bangumiItem.name.isNotEmpty &&
            _info.bangumiItem.name != _baseKeyword)
          TvChoiceOption(
            value: _info.bangumiItem.name,
            label: _info.bangumiItem.name,
            subtitle: '原名',
            icon: Icons.translate_rounded,
          ),
        for (final alias in aliases)
          if (alias.trim().isNotEmpty)
            TvChoiceOption(
              value: alias.trim(),
              label: alias.trim(),
              subtitle: '别名',
              icon: Icons.label_outline_rounded,
            ),
      ],
    );
    if (selected == null || !mounted) return;

    var keyword = selected;
    if (selected == '__custom__') {
      final typed = await showTvInputDialog(
        context,
        title: '输入搜索关键词',
        initialValue: _baseKeyword,
        hintText: '输入番剧名称或简写',
      );
      if (typed == null || typed.isEmpty || !mounted) return;
      keyword = typed;
      if (!_info.bangumiItem.alias.contains(keyword)) {
        _info.bangumiItem.alias.add(keyword);
        unawaited(
          widget.collectController.updateLocalCollect(_info.bangumiItem),
        );
      }
    }
    _requeryAll(keyword);
  }

  void _requeryAll(String keyword) {
    setState(() {
      _baseKeyword = keyword;
      _sourceKeywords.clear();
      _userPickedPlugin = false;
    });
    unawaited(_searchService.queryAllSource(keyword));
  }

  void _retryPlugin(String pluginName) {
    final kw = _sourceKeywords[pluginName] ?? _baseKeyword;
    unawaited(_searchService.querySource(kw, pluginName));
  }

  Future<void> _openSearchItem(Plugin plugin, SearchItem searchItem) async {
    if (_openingVideo) return;
    _openingVideo = true;
    final cancelToken = RuleCancelToken();
    try {
      final roads = await showTvLoadingDialog<List<Road>>(
        context,
        message: '正在从「${plugin.name}」获取选集列表…',
        cancelToken: cancelToken,
        action: () => plugin.queryChapterRoads(
          searchItem.src,
          cancelToken: cancelToken,
        ),
      );
      if (!mounted || cancelToken.isCancelled) return;
      if (roads == null || roads.isEmpty) {
        KazumiDialog.showToast(message: '未能获取到可用播放列表，请尝试其他结果');
        return;
      }
      context.pushNamed(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: _info.bangumiItem,
          plugin: plugin,
          title: searchItem.name,
          src: searchItem.src,
          roads: roads,
        ),
      );
    } catch (e) {
      KazumiLogger().w('TvInfoPage: queryChapterRoads failed', error: e);
      if (mounted) {
        KazumiDialog.showToast(message: '获取播放列表失败，请重试或换源');
      }
    } finally {
      _openingVideo = false;
    }
  }

  Future<void> _showFullSummary() async {
    final summary = _info.bangumiItem.summary.trim();
    if (summary.isEmpty) return;
    await KazumiDialog.show<void>(
      context: context,
      builder: (dialogContext) => _FullSummaryDialog(
        title: _resolveTitle(_info.bangumiItem),
        summary: summary,
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _searchService.cancel();
      },
      child: Scaffold(
        body: Observer(
          builder: (context) {
            final item = _info.bangumiItem;
            final title = _resolveTitle(item);
            final poster = item.images['large'] ?? item.images['common'] ?? '';
            final collectValue = widget.collectController.getCollectType(item);
            widget.collectController.collectibles.length;
            final collectType = CollectType.fromValue(collectValue);
            final latestHistory = _findLatestHistory();

            final plugins = widget.pluginsController.pluginList.toList();
            final resultsByPlugin = <String, List<SearchItem>>{};
            for (final resp in _info.pluginSearchResponseList) {
              resultsByPlugin[resp.pluginName] = resp.data;
            }

            if (!_userPickedPlugin && plugins.isNotEmpty) {
              final currentHasResults =
                  (resultsByPlugin[_selectedPluginName]?.isNotEmpty ?? false);
              if (!currentHasResults) {
                for (final p in plugins) {
                  if (resultsByPlugin[p.name]?.isNotEmpty ?? false) {
                    _selectedPluginName = p.name;
                    break;
                  }
                }
              }
            }

            // Sort tabs so plugins with results appear first while keeping order.
            final orderedPlugins = [...plugins]..sort((a, b) {
                final aHas =
                    (resultsByPlugin[a.name]?.isNotEmpty ?? false) ? 0 : 1;
                final bHas =
                    (resultsByPlugin[b.name]?.isNotEmpty ?? false) ? 0 : 1;
                return aHas.compareTo(bHas);
              });

            Plugin? activePlugin;
            for (final p in plugins) {
              if (p.name == _selectedPluginName) {
                activePlugin = p;
                break;
              }
            }
            activePlugin ??= orderedPlugins.isNotEmpty ? orderedPlugins.first : null;
            final activeStatus = activePlugin == null
                ? PluginSearchStatus.noResult
                : (_info.pluginSearchStatus[activePlugin.name] ??
                    PluginSearchStatus.pending);
            final activeResults = activePlugin == null
                ? const <SearchItem>[]
                : (resultsByPlugin[activePlugin.name] ?? const <SearchItem>[]);

            final relations = _info.relationList.toList();

            return Stack(
              children: [
                if (poster.isNotEmpty)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 360,
                    child: ClipRect(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                        child: Opacity(
                          opacity: 0.25,
                          child: NetworkImgLayer(
                            src: poster,
                            width: MediaQuery.sizeOf(context).width,
                            height: 360,
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.45],
                        colors: [
                          colors.surface.withValues(alpha: 0.35),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
                ),
                CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: TvLayout.overscanPadding,
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildHeroSection(
                            context,
                            colors: colors,
                            item: item,
                            title: title,
                            poster: poster,
                            collectType: collectType,
                            latestHistory: latestHistory,
                          ),
                          const SizedBox(height: 28),
                          Focus(
                            focusNode: _sourceSectionFocus,
                            skipTraversal: true,
                            child: _buildSourceSection(
                              colors: colors,
                              orderedPlugins: orderedPlugins,
                              resultsByPlugin: resultsByPlugin,
                              activePlugin: activePlugin,
                              activeStatus: activeStatus,
                              activeResults: activeResults,
                            ),
                          ),
                          if (relations.isNotEmpty) ...[
                            const SizedBox(height: 28),
                            const Text(
                              '关联番剧',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 256,
                              child: TvAxisClipRect(
                                axis: Axis.horizontal,
                                child: ListView.separated(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  clipBehavior: Clip.none,
                                  scrollDirection: Axis.horizontal,
                                  itemCount: relations.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 16),
                                  itemBuilder: (context, index) {
                                    final rel = relations[index];
                                    return SizedBox(
                                      width: 156,
                                      child: TvPosterCard(
                                        bangumiItem: rel.toBangumiItem(),
                                        badgeText: rel.relation,
                                        showScore: false,
                                        onSelect: () {
                                          context.pushNamed(
                                            '/info/',
                                            arguments: rel.toBangumiItem(),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                        ]),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeroSection(
    BuildContext context, {
    required ColorScheme colors,
    required BangumiItem item,
    required String title,
    required String poster,
    required CollectType collectType,
    required History? latestHistory,
  }) {
    final subtitleParts = <String>[
      if (item.ratingScore > 0) '★ ${item.ratingScore.toStringAsFixed(1)}',
      if (item.rank > 0) '排名 #${item.rank}',
      if (item.airDate.isNotEmpty) item.airDate,
    ];
    final tags = item.tags.take(6).map((t) => t.name).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: NetworkImgLayer(
            src: poster,
            width: 190,
            height: 270,
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TvIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              if (item.name.isNotEmpty && item.name != title) ...[
                const SizedBox(height: 4),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (subtitleParts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  subtitleParts.join('  ·  '),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ],
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final tag in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TvFocusable(
                onSelect: _showFullSummary,
                borderRadius: 10,
                scaleOnFocus: 1.015,
                builder: (context, focused) => Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: focused
                        ? colors.surfaceContainerHigh.withValues(alpha: 0.85)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    item.summary.trim().isEmpty
                        ? '暂无简介'
                        : item.summary.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.55,
                      color: colors.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  if (latestHistory != null)
                    TvPrimaryButton(
                      autofocus: true,
                      icon: Icons.play_arrow_rounded,
                      label:
                          '继续观看 (${latestHistory.lastWatchEpisodeName.isNotEmpty ? latestHistory.lastWatchEpisodeName : '第${latestHistory.lastWatchEpisode}集'})',
                      onPressed: () => unawaited(_resumeHistory(latestHistory)),
                    )
                  else
                    TvPrimaryButton(
                      autofocus: true,
                      icon: Icons.play_circle_outline_rounded,
                      label: '选择播放源',
                      onPressed: _focusSourceSection,
                    ),
                  TvSecondaryButton(
                    icon: collectType.isCollected
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    label: collectType.isCollected ? collectType.label : '追番收藏',
                    selected: collectType.isCollected,
                    onPressed: _pickCollectStatus,
                  ),
                  TvSecondaryButton(
                    icon: Icons.translate_rounded,
                    label: '别名/换词搜',
                    onPressed: _searchWithAliasOrCustom,
                  ),
                  TvSecondaryButton(
                    icon: Icons.refresh_rounded,
                    label: '重新检索',
                    onPressed: () => _requeryAll(_baseKeyword),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourceSection({
    required ColorScheme colors,
    required List<Plugin> orderedPlugins,
    required Map<String, List<SearchItem>> resultsByPlugin,
    required Plugin? activePlugin,
    required PluginSearchStatus activeStatus,
    required List<SearchItem> activeResults,
  }) {
    if (orderedPlugins.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.extension_off_rounded, color: colors.error, size: 32),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                '尚未安装任何视频源规则，请前往侧边栏「规则」安装后再试。',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '播放源检索',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            Text(
              '关键词：$_baseKeyword',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: TvAxisClipRect(
            axis: Axis.horizontal,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              clipBehavior: Clip.none,
              scrollDirection: Axis.horizontal,
              itemCount: orderedPlugins.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final plugin = orderedPlugins[index];
                final status = _info.pluginSearchStatus[plugin.name] ??
                    PluginSearchStatus.pending;
                final count = resultsByPlugin[plugin.name]?.length ?? 0;
                final suffix = switch (status) {
                  PluginSearchStatus.pending => ' · 检索中',
                  PluginSearchStatus.success => ' ($count)',
                  PluginSearchStatus.noResult => ' · 无结果',
                  PluginSearchStatus.error => ' · 失败',
                  PluginSearchStatus.captcha => ' · 需验证',
                };
                return TvChip(
                  key: ValueKey('source_tab_${plugin.name}'),
                  label: '${plugin.name}$suffix',
                  selected: activePlugin?.name == plugin.name,
                  onSelect: () {
                    setState(() {
                      _userPickedPlugin = true;
                      _selectedPluginName = plugin.name;
                    });
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (activePlugin != null)
          _buildPluginResultsBody(
            colors: colors,
            plugin: activePlugin,
            status: activeStatus,
            results: activeResults,
          ),
      ],
    );
  }

  Widget _buildPluginResultsBody({
    required ColorScheme colors,
    required Plugin plugin,
    required PluginSearchStatus status,
    required List<SearchItem> results,
  }) {
    if (status == PluginSearchStatus.pending && results.isEmpty) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Text('正在从「${plugin.name}」搜索「$_baseKeyword」…'),
            ],
          ),
        ),
      );
    }

    if (results.isEmpty) {
      final msg = switch (status) {
        PluginSearchStatus.captcha =>
          '「${plugin.name}」触发了网站人机验证，TV 端无法自动完成，建议切换上方其他播放源。',
        PluginSearchStatus.error => '「${plugin.name}」请求失败，可能是网络超时或站点维护。',
        _ => '「${plugin.name}」未搜索到「$_baseKeyword」相关剧集。',
      };
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              status == PluginSearchStatus.error
                  ? Icons.error_outline_rounded
                  : Icons.search_off_rounded,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(msg, style: const TextStyle(fontSize: 15))),
            const SizedBox(width: 12),
            TvSecondaryButton(
              label: '重试此源',
              icon: Icons.refresh_rounded,
              onPressed: () => _retryPlugin(plugin.name),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 68,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final searchItem = results[index];
        return TvFocusable(
          borderRadius: 12,
          scaleOnFocus: 1.03,
          onSelect: () => unawaited(_openSearchItem(plugin, searchItem)),
          builder: (context, focused) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? colors.primaryContainer
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 22,
                    color: focused
                        ? colors.onPrimaryContainer
                        : colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      searchItem.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: focused
                            ? colors.onPrimaryContainer
                            : colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FullSummaryDialog extends StatefulWidget {
  const _FullSummaryDialog({
    required this.title,
    required this.summary,
    required this.onClose,
  });

  final String title;
  final String summary;
  final VoidCallback onClose;

  @override
  State<_FullSummaryDialog> createState() => _FullSummaryDialogState();
}

class _FullSummaryDialogState extends State<_FullSummaryDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: TvFocusTraversalPolicy(),
        child: AlertDialog(
          title: Text(widget.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 420),
            child: TvFocusable(
              borderRadius: 12,
              scaleOnFocus: 1.005,
              onKeyEvent: (_, event) {
                if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                  return KeyEventResult.ignored;
                }
                if (!_scrollController.hasClients) {
                  return KeyEventResult.ignored;
                }
                final maxExtent = _scrollController.position.maxScrollExtent;
                if (maxExtent <= 0) {
                  return KeyEventResult.ignored;
                }
                final disableAnimations =
                    MediaQuery.disableAnimationsOf(context);
                if (TvKeys.isDownKey(event.logicalKey)) {
                  if (_scrollController.offset >= maxExtent - 0.5) {
                    return KeyEventResult.ignored;
                  }
                  final next =
                      (_scrollController.offset + 140).clamp(0.0, maxExtent);
                  if (disableAnimations) {
                    _scrollController.jumpTo(next);
                  } else {
                    unawaited(
                      _scrollController.animateTo(
                        next,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOutCubic,
                      ),
                    );
                  }
                  return KeyEventResult.handled;
                }
                if (TvKeys.isUpKey(event.logicalKey)) {
                  if (_scrollController.offset <= 0.5) {
                    return KeyEventResult.ignored;
                  }
                  final next =
                      (_scrollController.offset - 140).clamp(0.0, maxExtent);
                  if (disableAnimations) {
                    _scrollController.jumpTo(next);
                  } else {
                    unawaited(
                      _scrollController.animateTo(
                        next,
                        duration: const Duration(milliseconds: 100),
                        curve: Curves.easeOutCubic,
                      ),
                    );
                  }
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Scrollbar(
                  controller: _scrollController,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(
                      widget.summary,
                      style: const TextStyle(fontSize: 15, height: 1.65),
                    ),
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TvPrimaryButton(
              label: '关闭',
              autofocus: true,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}
