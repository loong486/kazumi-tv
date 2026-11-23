import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_episode_response.dart';
import 'package:kazumi/modules/danmaku/danmaku_search_response.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/request/apis/danmaku_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

Future<void> showTvDanmakuSearchDialog(
  BuildContext context, {
  required int bangumiId,
  required String initialKeyword,
  required PlayerDanmakuController danmakuController,
  required VoidCallback onBeforeApply,
}) {
  return KazumiDialog.show<void>(
    context: context,
    builder: (_) => _TvDanmakuSearchDialog(
      bangumiId: bangumiId,
      initialKeyword: initialKeyword,
      danmakuController: danmakuController,
      onBeforeApply: onBeforeApply,
    ),
  );
}

enum _DanmakuStep { search, anime, episode }

class _TvDanmakuSearchDialog extends StatefulWidget {
  const _TvDanmakuSearchDialog({
    required this.bangumiId,
    required this.initialKeyword,
    required this.danmakuController,
    required this.onBeforeApply,
  });

  final int bangumiId;
  final String initialKeyword;
  final PlayerDanmakuController danmakuController;
  final VoidCallback onBeforeApply;

  @override
  State<_TvDanmakuSearchDialog> createState() => _TvDanmakuSearchDialogState();
}

class _TvDanmakuSearchDialogState extends State<_TvDanmakuSearchDialog> {
  late final TextEditingController _keywordController =
      TextEditingController(text: widget.initialKeyword);
  late final List<String> _recentKeywords;

  _DanmakuStep _step = _DanmakuStep.search;
  bool _loading = false;
  String? _error;
  String? _animeTitle;
  List<DanmakuSearchAnime> _animes = const [];
  List<DanmakuEpisode> _episodes = const [];

  String get _historyKey => 'danmakuSearchHistory_${widget.bangumiId}';

  @override
  void initState() {
    super.initState();
    _recentKeywords = GStorage.getStringListSettingByName(_historyKey).toList();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _search([String? overrideKeyword]) async {
    if (_loading) return;
    final kw = (overrideKeyword ?? _keywordController.text).trim();
    if (kw.isEmpty) {
      setState(() => _error = '请输入番剧名称');
      return;
    }
    _keywordController.text = kw;
    if (!GStorage.getSetting(SettingsKeys.privateMode)) {
      _recentKeywords
        ..remove(kw)
        ..insert(0, kw);
      if (_recentKeywords.length > 5) _recentKeywords.removeLast();
      unawaited(GStorage.putStringListSettingByName(
        _historyKey,
        List<String>.of(_recentKeywords),
      ));
    }

    setState(() {
      _loading = true;
      _error = null;
      _step = _DanmakuStep.anime;
      _animes = const [];
    });
    try {
      final resp = await DanmakuApi.searchAnimes(kw);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _animes = resp.animes;
        if (_animes.isEmpty) _error = '未找到匹配的番剧';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '弹幕库检索失败，请检查网络连接';
      });
    }
  }

  Future<void> _selectAnime(DanmakuSearchAnime anime) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _animeTitle = anime.animeTitle;
      _step = _DanmakuStep.episode;
      _episodes = const [];
    });
    try {
      final resp =
          await DanmakuApi.getDanDanEpisodesByDanDanBangumiID(anime.animeId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _episodes = resp.episodes;
        if (_episodes.isEmpty) _error = '该作品暂无分集弹幕';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载分集列表失败';
      });
    }
  }

  Future<void> _selectEpisode(DanmakuEpisode episode) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      widget.onBeforeApply();
      final hasDanmakus = await widget.danmakuController
          .getDanDanmakuByEpisodeID(episode.episodeId);
      if (!mounted) return;
      widget.danmakuController.setDanmakuEnabled(hasDanmakus);
      Navigator.of(context).pop();
      KazumiDialog.showToast(
        message: hasDanmakus ? '已切换弹幕源：${episode.episodeTitle}' : '该分集暂无弹幕',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      KazumiDialog.showToast(message: '切换弹幕源失败');
    }
  }

  void _backStep() {
    if (_loading) return;
    setState(() {
      _error = null;
      _step = _step == _DanmakuStep.episode
          ? _DanmakuStep.anime
          : _DanmakuStep.search;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = switch (_step) {
      _DanmakuStep.search => '手动匹配弹幕源',
      _DanmakuStep.anime => '选择番剧（${_keywordController.text.trim()}）',
      _DanmakuStep.episode => '选择分集（${_animeTitle ?? ''}）',
    };

    final mediaSize = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxContentWidth = (mediaSize.width - 80).clamp(280.0, 560.0);
    final maxContentHeight =
        (mediaSize.height - viewInsets.bottom - 220).clamp(80.0, 360.0);

    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: TvFocusTraversalPolicy(),
        child: AlertDialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: maxContentWidth,
            height: maxContentHeight,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : switch (_step) {
                    _DanmakuStep.search => _buildSearchStep(colors),
                    _DanmakuStep.anime => _buildAnimeStep(colors),
                    _DanmakuStep.episode => _buildEpisodeStep(colors),
                  },
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            if (_step != _DanmakuStep.search && !_loading)
              TvSecondaryButton(
                label: '上一步',
                onPressed: _backStep,
              ),
            TvSecondaryButton(
              label: '关闭',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchStep(ColorScheme colors) {
    return TvAxisClipRect(
      axis: Axis.vertical,
      child: SingleChildScrollView(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    TvKeys.isDownKey(event.logicalKey)) {
                  (FocusManager.instance.primaryFocus ?? node)
                      .focusInDirection(TraversalDirection.down);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _keywordController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (v) => unawaited(_search(v)),
                decoration: InputDecoration(
                  hintText: '输入番剧名称',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TvPrimaryButton(
                  label: '搜索弹幕库',
                  icon: Icons.search_rounded,
                  onPressed: () => unawaited(_search()),
                ),
                if (_error != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(_error!, style: TextStyle(color: colors.error)),
                  ),
                ],
              ],
            ),
            if (_recentKeywords.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                '最近搜索',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  for (final kw in _recentKeywords)
                    TvChip(
                      label: kw,
                      icon: Icons.history_rounded,
                      selected: false,
                      onSelect: () => unawaited(_search(kw)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnimeStep(ColorScheme colors) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colors.error)),
      );
    }
    return TvAxisClipRect(
      axis: Axis.vertical,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.all(16),
        itemCount: _animes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final anime = _animes[index];
          return TvFocusable(
            autofocus: index == 0,
            borderRadius: 10,
            scaleOnFocus: 1.02,
            onSelect: () => unawaited(_selectAnime(anime)),
            builder: (context, focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: focused
                    ? colors.primaryContainer
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          anime.animeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (anime.typeDescription.isNotEmpty)
                          Text(
                            anime.typeDescription,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEpisodeStep(ColorScheme colors) {
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: colors.error)),
      );
    }
    return TvAxisClipRect(
      axis: Axis.vertical,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.all(16),
        itemCount: _episodes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final ep = _episodes[index];
          return TvFocusable(
            autofocus: index == 0,
            borderRadius: 10,
            scaleOnFocus: 1.02,
            onSelect: () => unawaited(_selectEpisode(ep)),
            builder: (context, focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: focused
                    ? colors.primaryContainer
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                ep.episodeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ),
          );
        },
      ),
    );
  }
}
