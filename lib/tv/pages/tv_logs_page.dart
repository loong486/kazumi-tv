import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvLogsPage extends StatefulWidget {
  const TvLogsPage({super.key});

  @override
  State<TvLogsPage> createState() => _TvLogsPageState();
}

class _TvLogsPageState extends State<TvLogsPage> {
  List<String> _lines = const [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final file = await getLogsPath();
      final text = await file.readAsString();
      final lines = text
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList()
          .reversed
          .take(300)
          .toList();
      if (mounted) {
        setState(() {
          _lines = lines;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showTvConfirmDialog(
      context,
      title: '清空运行日志',
      message: '确认清空所有本地日志记录吗？',
      confirmLabel: '清空',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await clearLogs();
    if (!mounted) return;
    await _load();
    if (mounted) KazumiDialog.showToast(message: '日志已清空');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Padding(
        padding: TvLayout.overscanPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TvIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  autofocus: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 14),
                const Text(
                  '运行日志（最新 300 条）',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TvSecondaryButton(
                  label: '刷新',
                  icon: Icons.refresh_rounded,
                  onPressed: () => unawaited(_load()),
                ),
                const SizedBox(width: 10),
                TvSecondaryButton(
                  label: '清空日志',
                  icon: Icons.delete_outline_rounded,
                  onPressed: () => unawaited(_clear()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TvFocusable(
                borderRadius: 14,
                scaleOnFocus: 1.01,
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
                    final next = (_scrollController.offset + 180)
                        .clamp(0.0, maxExtent);
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
                    if (_scrollController.offset <= 0) {
                      return KeyEventResult.ignored;
                    }
                    final next = (_scrollController.offset - 180)
                        .clamp(0.0, maxExtent);
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
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _lines.isEmpty
                          ? Center(
                              child: Text(
                                '暂无日志记录',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant),
                              ),
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              child: ListView.builder(
                                controller: _scrollController,
                                itemCount: _lines.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      _lines[index],
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
