import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/utils/format.dart';

class TvPlayerOverlay extends StatefulWidget {
  const TvPlayerOverlay({
    super.key,
    required this.title,
    required this.subtitle,
    required this.pluginName,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.playing,
    required this.danmakuOn,
    required this.playbackSpeed,
    required this.aspectRatioLabel,
    required this.skipOpSeconds,
    required this.seekStepSeconds,
    required this.canPrevEpisode,
    required this.canNextEpisode,
    required this.onUserActivity,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeek,
    required this.onPrevEpisode,
    required this.onNextEpisode,
    required this.onSkipOp,
    required this.onToggleDanmaku,
    required this.onCycleSpeed,
    required this.onCycleAspectRatio,
    required this.onOpenDrawer,
  });

  final String title;
  final String subtitle;
  final String pluginName;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool playing;
  final bool danmakuOn;
  final double playbackSpeed;
  final String aspectRatioLabel;
  final int skipOpSeconds;
  final int seekStepSeconds;
  final bool canPrevEpisode;
  final bool canNextEpisode;
  final VoidCallback onUserActivity;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPrevEpisode;
  final VoidCallback onNextEpisode;
  final VoidCallback onSkipOp;
  final VoidCallback onToggleDanmaku;
  final VoidCallback onCycleSpeed;
  final VoidCallback onCycleAspectRatio;
  final VoidCallback onOpenDrawer;

  @override
  State<TvPlayerOverlay> createState() => _TvPlayerOverlayState();
}

class _TvPlayerOverlayState extends State<TvPlayerOverlay> {
  Duration? _scrubPreview;

  @override
  void didUpdateWidget(TvPlayerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scrubPreview != null && widget.duration != oldWidget.duration) {
      _scrubPreview = null;
    }
  }

  void _stepScrub(int sign) {
    widget.onUserActivity();
    final base = _scrubPreview ?? widget.position;
    final stepMs = widget.seekStepSeconds * 1000 * sign;
    var nextMs = base.inMilliseconds + stepMs;
    if (nextMs < 0) nextMs = 0;
    if (widget.duration > Duration.zero &&
        nextMs > widget.duration.inMilliseconds) {
      nextMs = widget.duration.inMilliseconds;
    }
    setState(() => _scrubPreview = Duration(milliseconds: nextMs));
  }

  void _commitScrub() {
    widget.onUserActivity();
    final target = _scrubPreview;
    if (target != null) {
      setState(() => _scrubPreview = null);
      widget.onSeek(target);
    } else {
      widget.onPlayPause();
    }
  }

  String _clockNow() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayPos = _scrubPreview ?? widget.position;
    final totalMs = widget.duration.inMilliseconds;
    final posRatio =
        totalMs > 0 ? (displayPos.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    final bufRatio = totalMs > 0
        ? (widget.buffered.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return FocusScope(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          widget.onUserActivity();
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  TvIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '退出播放',
                    onPressed: widget.onBack,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (widget.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.pluginName.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.pluginName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Text(
                    _clockNow(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(36, 48, 36, 26),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvFocusable(
                    borderRadius: 10,
                    scaleOnFocus: 1.015,
                    onSelect: _commitScrub,
                    onFocusChange: (focused) {
                      if (!focused && _scrubPreview != null) {
                        setState(() => _scrubPreview = null);
                      }
                    },
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                        return KeyEventResult.ignored;
                      }
                      if (TvKeys.isLeftKey(event.logicalKey)) {
                        _stepScrub(-1);
                        return KeyEventResult.handled;
                      }
                      if (TvKeys.isRightKey(event.logicalKey)) {
                        _stepScrub(1);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    builder: (context, focused) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                durationToString(displayPos),
                                style: TextStyle(
                                  color: _scrubPreview != null
                                      ? colors.primary
                                      : Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: 14,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final w = constraints.maxWidth;
                                    return Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        Container(
                                          height: focused ? 6 : 4,
                                          decoration: BoxDecoration(
                                            color: Colors.white24,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                        Container(
                                          width: w * bufRatio,
                                          height: focused ? 6 : 4,
                                          decoration: BoxDecoration(
                                            color: Colors.white54,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                        Container(
                                          width: w * posRatio,
                                          height: focused ? 6 : 4,
                                          decoration: BoxDecoration(
                                            color: colors.primary,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                        Positioned(
                                          left: (w * posRatio - 7)
                                              .clamp(0.0, (w - 14).clamp(0.0, w)),
                                          child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: focused
                                                  ? Colors.white
                                                  : colors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 72,
                              child: Text(
                                durationToString(widget.duration),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TvPrimaryButton(
                        autofocus: true,
                        icon: widget.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: widget.playing ? '暂停' : '播放',
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onPlayPause();
                        },
                      ),
                      const SizedBox(width: 10),
                      TvIconButton(
                        icon: Icons.skip_previous_rounded,
                        tooltip: '上一集',
                        enabled: widget.canPrevEpisode,
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onPrevEpisode();
                        },
                      ),
                      const SizedBox(width: 8),
                      TvIconButton(
                        icon: Icons.skip_next_rounded,
                        tooltip: '下一集',
                        enabled: widget.canNextEpisode,
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onNextEpisode();
                        },
                      ),
                      const SizedBox(width: 12),
                      TvSecondaryButton(
                        icon: Icons.fast_forward_rounded,
                        label: '快进 ${widget.skipOpSeconds}s',
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onSkipOp();
                        },
                      ),
                      const Spacer(),
                      TvSecondaryButton(
                        icon: widget.danmakuOn
                            ? Icons.subtitles_rounded
                            : Icons.subtitles_off_outlined,
                        label: widget.danmakuOn ? '弹幕开' : '弹幕关',
                        selected: widget.danmakuOn,
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onToggleDanmaku();
                        },
                      ),
                      const SizedBox(width: 10),
                      TvSecondaryButton(
                        icon: Icons.speed_rounded,
                        label: '${widget.playbackSpeed}x',
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onCycleSpeed();
                        },
                      ),
                      const SizedBox(width: 10),
                      TvSecondaryButton(
                        icon: Icons.aspect_ratio_rounded,
                        label: widget.aspectRatioLabel,
                        onPressed: () {
                          widget.onUserActivity();
                          widget.onCycleAspectRatio();
                        },
                      ),
                      const SizedBox(width: 10),
                      TvSecondaryButton(
                        icon: Icons.menu_open_rounded,
                        label: '选集与设置',
                        onPressed: widget.onOpenDrawer,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
