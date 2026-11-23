import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/danmaku/danmaku_module.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/player/controller/player_aspect_ratio.dart';
import 'package:kazumi/pages/player/controller/player_danmaku_controller.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/player/player_item_surface.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/platform/display_mode_service.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/player/tv_danmaku_search_dialog.dart';
import 'package:kazumi/tv/player/tv_player_drawer.dart';
import 'package:kazumi/tv/player/tv_player_overlay.dart';
import 'package:kazumi/tv/player/tv_player_remote_controller.dart';
import 'package:kazumi/tv/player/tv_player_seek_hud.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/utils/tv_platform_channel.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/utils/constants.dart';

class TvVideoPage extends StatefulWidget {
  const TvVideoPage({
    super.key,
    required this.args,
    required this.playerController,
    required this.videoPageController,
    required this.historyController,
    required this.myController,
  });

  final VideoPlaybackArgs args;
  final PlayerController playerController;
  final VideoPageController videoPageController;
  final HistoryController historyController;
  final MyController myController;

  @override
  State<TvVideoPage> createState() => _TvVideoPageState();
}

class _TvVideoPageState extends State<TvVideoPage> with WidgetsBindingObserver {
  final TvPlayerRemoteController _remote = TvPlayerRemoteController();
  final FocusNode _rootFocus = FocusNode(debugLabel: 'TvPlayerRoot');
  final FocusNode _errorRetryFocus = FocusNode(debugLabel: 'TvPlayerErrorRetry');
  final FocusNode _loadingCancelFocus =
      FocusNode(debugLabel: 'TvPlayerLoadingCancel');
  final GlobalKey _danmakuKey = GlobalKey();

  Timer? _playerTimer;
  Timer? _centerIconTimer;
  StreamSubscription<String>? _logSub;
  final List<String> _snifferLogs = [];

  bool _isExiting = false;
  bool _showDebugLogs = false;
  bool _showCenterIcon = false;
  bool _centerIconPlaying = true;
  bool _didInit = false;
  bool _wasStatusOverlayVisible = true;
  DateTime? _lastKeyBackAt;

  late bool _playResume;
  late bool _autoPlayNext;
  late bool _danmakuBorder;
  late double _danmakuOpacity;
  late double _danmakuArea;
  late bool _hideTop;
  late bool _hideBottom;
  late bool _hideScroll;
  late bool _massiveMode;
  late bool _danmakuColor;
  late bool _biliSource;
  late bool _gamerSource;
  late bool _dandanSource;
  late double _danmakuDuration;
  late double _danmakuLineHeight;
  late int _danmakuFontWeight;
  late bool _danmakuUseSystemFont;
  late double _danmakuBorderSize;
  late double _danmakuFontSize;

  PlayerController get _player => widget.playerController;
  VideoPageController get _video => widget.videoPageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remote.addListener(_onRemoteChanged);
    _video.applyPlaybackArgs(widget.args);
    _loadSettings();
    unawaited(TvPlatformChannel.setKeepScreenOn(true));
    unawaited(DisplayModeService.setSystemBarsHidden(owner: this, hidden: true));
    unawaited(_bindAudioService());
    _playerTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onPlayerTick(),
    );
  }

  void _loadSettings() {
    _playResume = GStorage.getSetting(SettingsKeys.playResume);
    _autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);
    _player.danmaku.setDanmakuEnabled(
      GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault),
    );
    _danmakuBorder = GStorage.getSetting(SettingsKeys.danmakuBorder);
    _danmakuOpacity = GStorage.getSetting(SettingsKeys.danmakuOpacity);
    _danmakuArea = GStorage.getSetting(SettingsKeys.danmakuArea);
    _hideTop = !GStorage.getSetting(SettingsKeys.danmakuTop);
    _hideBottom = !GStorage.getSetting(SettingsKeys.danmakuBottom);
    _hideScroll = !GStorage.getSetting(SettingsKeys.danmakuScroll);
    _massiveMode = GStorage.getSetting(SettingsKeys.danmakuMassive);
    _danmakuColor = GStorage.getSetting(SettingsKeys.danmakuColor);
    _danmakuDuration = GStorage.getSetting(SettingsKeys.danmakuDuration);
    _danmakuLineHeight = GStorage.getSetting(SettingsKeys.danmakuLineHeight);
    _biliSource = GStorage.getSetting(SettingsKeys.danmakuBiliBiliSource);
    _gamerSource = GStorage.getSetting(SettingsKeys.danmakuGamerSource);
    _dandanSource = GStorage.getSetting(SettingsKeys.danmakuDanDanSource);
    _danmakuFontWeight = GStorage.getSetting(SettingsKeys.danmakuFontWeight);
    _danmakuUseSystemFont = GStorage.getSetting(SettingsKeys.useSystemFont);
    _danmakuBorderSize = GStorage.getSetting(SettingsKeys.danmakuBorderSize);
    _danmakuFontSize = GStorage.getSetting(SettingsKeys.danmakuFontSize);
  }

  void _refreshDanmakuCanvasOptions() {
    _loadSettings();
    try {
      _player.danmaku.canvasController.updateOption(
        DanmakuOption(
          hideTop: _hideTop,
          hideScroll: _hideScroll,
          hideBottom: _hideBottom,
          area: _danmakuArea,
          opacity: _danmakuOpacity,
          fontSize: _danmakuFontSize,
          duration: _danmakuDuration /
              (GStorage.getSetting(SettingsKeys.danmakuFollowSpeed)
                  ? _player.playback.playerSpeed
                  : 1.0),
          lineHeight: _danmakuLineHeight,
          strokeWidth: _danmakuBorder ? _danmakuBorderSize : 0.0,
          fontWeight: _danmakuFontWeight,
          massiveMode: _massiveMode,
          fontFamily: _danmakuUseSystemFont ? null : customAppFontFamily,
        ),
      );
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    _initPlayback();
  }

  void _initPlayback() {
    _video.historyOffset = 0;
    if (!_video.isOfflineMode) {
      final progress = widget.historyController.lastWatching(
        _video.bangumiItem,
        _video.currentPlugin.name,
      );
      if (progress != null &&
          progress.road >= 0 &&
          progress.episode > 0 &&
          _video.roadList.length > progress.road &&
          _video.roadList[progress.road].data.length >= progress.episode) {
        _video.resetEpisodeState(
          episode: progress.episode,
          road: progress.road,
        );
        if (_playResume) {
          _video.historyOffset = progress.progress.inSeconds;
        }
      }
    }

    _logSub = _video.logStream.listen((line) {
      if (!mounted) return;
      setState(() {
        _snifferLogs.add(line);
        if (_snifferLogs.length > 40) _snifferLogs.removeAt(0);
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_changeEpisode(
        _video.selectedEpisode.episode,
        currentRoad: _video.selectedEpisode.road,
        offset: _video.historyOffset,
      ));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      unawaited(_player.playback.setPrefetchSuspended(true));
      if (_player.playback.mediaPlayer != null &&
          _player.playback.playerPlaying) {
        unawaited(_player.pause(enableSync: false));
      }
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_player.playback.setPrefetchSuspended(false));
      try {
        if (_player.playback.playerPlaying) {
          _player.danmaku.canvasController.resume();
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playerTimer?.cancel();
    _centerIconTimer?.cancel();
    _logSub?.cancel();
    _remote.removeListener(_onRemoteChanged);
    _remote.dispose();
    _errorRetryFocus.dispose();
    _loadingCancelFocus.dispose();
    _rootFocus.dispose();
    unawaited(TvPlatformChannel.setKeepScreenOn(false));
    unawaited(DisplayModeService.releaseSystemBars(this));
    super.dispose();
  }

  Future<void> _bindAudioService() async {
    try {
      await _player.audioController.bindCallbacks(
        onPlay: () => _player.play(),
        onPause: () => _player.pause(),
        onSkipToNext: () => _switchRelativeEpisode(1),
        onSkipToPrevious: () => _switchRelativeEpisode(-1),
        onSeek: (pos) => _player.seek(pos),
        artworkUrl: _video.bangumiItem.images['large'],
      );
    } catch (e) {
      KazumiLogger().w('TvVideoPage: bindAudioService failed', error: e);
    }
  }

  void _syncAudioServiceState() {
    try {
      final selection = _video.playbackEpisode;
      if (_video.roadList.isEmpty ||
          selection.road < 0 ||
          selection.road >= _video.roadList.length) {
        return;
      }
      final roadData = _video.roadList[selection.road];
      if (selection.episode <= 0 || roadData.data.isEmpty) return;
      final episodeRef = _video.resolveEpisode(selection);
      if (episodeRef == null) return;
      if (_player.playback.duration <= Duration.zero) return;

      final title = _video.bangumiItem.nameCn.isNotEmpty
          ? _video.bangumiItem.nameCn
          : _video.bangumiItem.name;

      unawaited(
        _player.audioController.updateSession(
          mediaId:
              '${_video.bangumiItem.id}_${selection.road}_${selection.episode}',
          title: title,
          album: _video.currentPlugin.name,
          artist: episodeRef.displayTitle,
          duration: _player.playback.duration,
          playing: _player.playback.playing,
          loading: _player.playback.loading,
          buffering: _player.playback.isBuffering,
          completed: _player.playback.completed,
          updatePosition: _player.playback.currentPosition,
          bufferedPosition: _player.playback.buffer,
          speed: _player.playback.playerSpeed,
          queueIndex: episodeRef.listIndex - 1,
          canSkipToNext: selection.episode < roadData.data.length,
          canSkipToPrevious: selection.episode > 1,
        ),
      );
    } catch (_) {}
  }

  void _onPlayerTick() {
    if (!mounted || _isExiting) return;
    _player.syncPlaybackState();
    _syncAudioServiceState();
    _emitDanmakusForCurrentPosition();

    final historyIdentity = _video.currentHistoryIdentity;
    if (_player.playback.playerPlaying &&
        !_video.loading &&
        historyIdentity != null &&
        historyIdentity.canRecord) {
      widget.historyController.updateHistory(
        historyIdentity,
        _player.playback.playerPosition,
        duration: _player.playback.playerDuration,
      );
    }

    final playingSelection = _video.playbackEpisode;
    if (_video.roadList.isNotEmpty &&
        playingSelection.road >= 0 &&
        playingSelection.road < _video.roadList.length &&
        _player.playback.completed &&
        !_video.loading) {
      final roadData = _video.roadList[playingSelection.road];
      if (_player.playback.resumedNearEnd) {
        unawaited(_player.playback.restartFromBeginning());
      } else if (playingSelection.episode < roadData.data.length &&
          _autoPlayNext) {
        final nextSelection = VideoEpisodeSelection(
          episode: playingSelection.episode + 1,
          road: playingSelection.road,
        );
        final nextRef = _video.resolveEpisode(nextSelection);
        if (nextRef != null) {
          KazumiDialog.showToast(message: '正在自动播放 ${nextRef.displayTitle}');
        }
        unawaited(_changeEpisode(
          playingSelection.episode + 1,
          currentRoad: playingSelection.road,
        ));
      }
    }
  }

  bool _isDanmakuSourceEnabled(DanmakuEntry danmaku) {
    if (!_biliSource && danmaku.source.contains('BiliBili')) return false;
    if (!_gamerSource && danmaku.source.contains('Gamer')) return false;
    if (!_dandanSource &&
        !(danmaku.source.contains('BiliBili') ||
            danmaku.source.contains('Gamer'))) {
      return false;
    }
    return true;
  }

  void _emitDanmakusForCurrentPosition() {
    if (_player.playback.currentPosition.inMicroseconds == 0 ||
        !_player.playback.playerPlaying ||
        !_player.danmaku.danmakuOn) {
      return;
    }
    final list = _player.danmaku
        .danmakusForPlaybackPosition(_player.playback.currentPosition);
    final total = list.length;
    for (final entry in list.asMap().entries) {
      final danmaku = entry.value;
      if (!_isDanmakuSourceEnabled(danmaku)) continue;
      final color = _danmakuColor ? danmaku.color : Colors.white;
      final delay = DanmakuTimeline.staggerDelayMilliseconds(
        index: entry.key,
        total: total,
      );
      final gen = _player.danmaku.scheduledDanmakuGeneration;
      Future.delayed(Duration(milliseconds: delay), () {
        if (!mounted ||
            _isExiting ||
            !_player.playback.playerPlaying ||
            _player.playback.playerBuffering ||
            !_player.danmaku.danmakuOn ||
            _player.danmaku.scheduledDanmakuGeneration != gen ||
            widget.myController.isDanmakuBlocked(danmaku.message)) {
          return;
        }
        final type = switch (danmaku.type) {
          4 => DanmakuItemType.bottom,
          5 => DanmakuItemType.top,
          _ => DanmakuItemType.scroll,
        };
        _player.danmaku.canvasController.addDanmaku(
          DanmakuContentItem(danmaku.message, color: color, type: type),
        );
      });
    }
  }

  Future<void> _changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
  }) async {
    if (!mounted || _isExiting) return;
    _remote.cancelPendingSeek();
    _remote.hideOsd();
    setState(() {
      _snifferLogs.clear();
      _showDebugLogs = false;
    });
    await _video.changeEpisode(
      episode,
      currentRoad: currentRoad,
      offset: offset,
      playerController: _player,
    );
  }

  Future<void> _switchRelativeEpisode(int delta) async {
    if (_video.loading) return;
    final sel = _video.selectedEpisode;
    if (_video.roadList.isEmpty ||
        sel.road < 0 ||
        sel.road >= _video.roadList.length) {
      return;
    }
    final target = sel.episode + delta;
    final maxLen = _video.roadList[sel.road].data.length;
    if (target <= 0) {
      KazumiDialog.showToast(message: '已经是第一集');
      return;
    }
    if (target > maxLen) {
      KazumiDialog.showToast(message: '已经是最新一集');
      return;
    }
    final nextRef = _video.resolveEpisode(
      VideoEpisodeSelection(episode: target, road: sel.road),
    );
    if (nextRef != null) {
      KazumiDialog.showToast(message: '正在加载 ${nextRef.displayTitle}');
    }
    await _changeEpisode(target, currentRoad: sel.road);
  }

  void _togglePlayPause() {
    unawaited(_player.playOrPause());
    _centerIconTimer?.cancel();
    setState(() {
      _showCenterIcon = true;
      _centerIconPlaying = !_player.playback.playing;
    });
    _centerIconTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showCenterIcon = false);
    });
  }

  void _toggleDanmaku() {
    try {
      _player.danmaku.canvasController.clear();
    } catch (_) {}
    if (_player.danmaku.danmakuOn) {
      _player.danmaku.setDanmakuEnabled(false);
      unawaited(
          GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, false));
      return;
    }
    if (_player.danmaku.danDanmakus.isEmpty) {
      _openDanmakuSearch();
      return;
    }
    _player.danmaku.setDanmakuEnabled(true);
    unawaited(GStorage.putSetting(SettingsKeys.danmakuEnabledByDefault, true));
  }

  Future<void> _openDanmakuSearch() async {
    await showTvDanmakuSearchDialog(
      context,
      bangumiId: _video.bangumiItem.id,
      initialKeyword: _video.title,
      danmakuController: _player.danmaku,
      onBeforeApply: _video.cancelAutomaticDanmakuLoad,
    );
    if (!mounted || _isExiting) return;
    if (_remote.mode == TvPlayerUiMode.idle) {
      _restoreRootFocus();
    } else if (_remote.mode == TvPlayerUiMode.osd) {
      _remote.resetOsdTimer();
    }
  }

  void _cycleSpeed() {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    final current = _player.playback.playerSpeed;
    final idx = speeds.indexWhere((s) => (s - current).abs() < 0.05);
    final next = speeds[(idx + 1) % speeds.length];
    unawaited(_player.setPlaybackSpeed(next));
    KazumiDialog.showToast(message: '倍速：${next}x');
  }

  void _cycleAspectRatio() {
    final current = _player.panel.aspectRatioMode;
    final all = PlayerAspectRatio.values;
    final next = all[(all.indexOf(current) + 1) % all.length];
    _player.panel.aspectRatioMode = next;
    KazumiDialog.showToast(message: '画面比例：${next.label}');
  }

  Future<void> _setSuperResolution(SuperResolutionMode mode) async {
    if (Platform.isAndroid &&
        mode != SuperResolutionMode.off &&
        GStorage.getSetting(SettingsKeys.androidVideoRenderer) ==
            'mediacodec_embed') {
      KazumiDialog.showToast(
        message: 'mediacodec_embed 渲染器不支持超分辨率，请在设置中切换为 gpu',
      );
      return;
    }
    await _player.setShader(mode);
    if (!mounted || _isExiting) return;
    KazumiDialog.showToast(message: '超分辨率：${mode.label}');
  }

  void _exitPlayer() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _player.beginShutdown();
    Navigator.of(context).pop();
  }

  void _onRemoteChanged() {
    if (!mounted || _isExiting) return;
    if (_remote.mode == TvPlayerUiMode.idle) {
      _restoreRootFocus();
    }
  }

  void _restoreRootFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _isExiting ||
          _remote.mode != TvPlayerUiMode.idle ||
          ModalRoute.of(context)?.isCurrent == false) {
        return;
      }
      if (_video.errorMessage != null) {
        if (!(_rootFocus.hasFocus && !_rootFocus.hasPrimaryFocus) &&
            _errorRetryFocus.canRequestFocus) {
          _errorRetryFocus.requestFocus();
        }
        return;
      }
      if (_video.loading || _player.playback.loading) {
        if (!(_rootFocus.hasFocus && !_rootFocus.hasPrimaryFocus) &&
            _loadingCancelFocus.canRequestFocus) {
          _loadingCancelFocus.requestFocus();
        }
        return;
      }
      if (!_rootFocus.hasPrimaryFocus) {
        _rootFocus.requestFocus();
      }
    });
  }

  void _handleBackPress({bool fromKeyEvent = false}) {
    if (_isExiting || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (fromKeyEvent) {
      _lastKeyBackAt = DateTime.now();
    } else if (_lastKeyBackAt != null &&
        DateTime.now().difference(_lastKeyBackAt!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    final shouldExit = _remote.handleBack(
      onFirstBackPrompt: () => KazumiDialog.showToast(
        message: '再按一次返回键退出播放',
        context: context,
      ),
    );
    if (shouldExit) {
      _exitPlayer();
    } else {
      _restoreRootFocus();
    }
  }

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (TvKeys.isKeyboardBackKey(key) && event is KeyDownEvent) {
      if (ModalRoute.of(context)?.isCurrent == false) {
        return KeyEventResult.ignored;
      }
      _handleBackPress(fromKeyEvent: true);
      return KeyEventResult.handled;
    }

    if (_remote.mode != TvPlayerUiMode.idle) {
      if (TvKeys.isMenuKey(key) && event is KeyDownEvent) {
        if (_remote.mode == TvPlayerUiMode.drawer) {
          _remote.closeDrawer();
          _restoreRootFocus();
        } else {
          _remote.openDrawer(tabIndex: 0);
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_video.loading ||
        _player.playback.loading ||
        _video.errorMessage != null) {
      if (TvKeys.isMenuKey(key) && event is KeyDownEvent) {
        _remote.openDrawer(tabIndex: 0);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Idle fullscreen mode key handling
    if (TvKeys.isPlayPauseKey(key) ||
        (TvKeys.isSelectKey(key) && event is KeyDownEvent)) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (TvKeys.isLeftKey(key) || TvKeys.isRewindKey(key)) {
      _remote.stepSeek(
        currentPosition: _player.playback.currentPosition,
        duration: _player.playback.duration,
        delta: Duration(seconds: -_player.playback.arrowKeySkipTime),
        onCommitSeek: (target) => unawaited(_player.seek(target)),
      );
      return KeyEventResult.handled;
    }
    if (TvKeys.isRightKey(key) || TvKeys.isFastForwardKey(key)) {
      _remote.stepSeek(
        currentPosition: _player.playback.currentPosition,
        duration: _player.playback.duration,
        delta: Duration(seconds: _player.playback.arrowKeySkipTime),
        onCommitSeek: (target) => unawaited(_player.seek(target)),
      );
      return KeyEventResult.handled;
    }
    if ((TvKeys.isUpKey(key) || TvKeys.isDownKey(key)) &&
        event is KeyDownEvent) {
      _remote.showOsd();
      return KeyEventResult.handled;
    }
    if (TvKeys.isMenuKey(key) && event is KeyDownEvent) {
      _remote.openDrawer(tabIndex: 0);
      return KeyEventResult.handled;
    }
    if (TvKeys.isPrevEpisodeKey(key) && event is KeyDownEvent) {
      unawaited(_switchRelativeEpisode(-1));
      return KeyEventResult.handled;
    }
    if (TvKeys.isNextEpisodeKey(key) && event is KeyDownEvent) {
      unawaited(_switchRelativeEpisode(1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          if (!_isExiting) {
            _player.beginShutdown();
          }
          return;
        }
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _isExiting
            ? const SizedBox.expand()
            : Focus(
                focusNode: _rootFocus,
                autofocus: true,
                onKeyEvent: _handleRootKeyEvent,
                child: ListenableBuilder(
                  listenable: _remote,
                  builder: (context, _) {
                    return Observer(
                      builder: (context) {
                        final isLoadingVideo =
                            _video.loading || _player.playback.loading;
                        final errorMessage = _video.errorMessage;
                        final isStatusOverlayVisible =
                            isLoadingVideo || errorMessage != null;
                        if (_wasStatusOverlayVisible &&
                            !isStatusOverlayVisible &&
                            _remote.mode == TvPlayerUiMode.idle) {
                          _restoreRootFocus();
                        }
                        _wasStatusOverlayVisible = isStatusOverlayVisible;
                        final sel = _video.selectedEpisode;
                        final epRef = _video.resolveEpisode(sel);
                        final animeTitle = _video.bangumiItem.nameCn.isNotEmpty
                            ? _video.bangumiItem.nameCn
                            : _video.bangumiItem.name;
                        final epTitle = epRef?.displayTitle ?? '第 ${sel.episode} 集';
                        final roadLen = _video.roadList.isNotEmpty &&
                                sel.road >= 0 &&
                                sel.road < _video.roadList.length
                            ? _video.roadList[sel.road].data.length
                            : 0;

                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            Center(
                              child: PlayerItemSurface(
                                playerController: _player,
                              ),
                            ),
                            Positioned.fill(
                              child: DanmakuScreen(
                                key: _danmakuKey,
                                createdController: (DanmakuController c) {
                                  _player.danmaku.canvasController = c;
                                  WidgetsBinding.instance
                                      .addPostFrameCallback((_) {
                                    _player.updateDanmakuSpeed();
                                  });
                                },
                                option: DanmakuOption(
                                  hideTop: _hideTop,
                                  hideScroll: _hideScroll,
                                  hideBottom: _hideBottom,
                                  area: _danmakuArea,
                                  opacity: _danmakuOpacity,
                                  fontSize: _danmakuFontSize,
                                  duration: _danmakuDuration,
                                  lineHeight: _danmakuLineHeight,
                                  strokeWidth:
                                      _danmakuBorder ? _danmakuBorderSize : 0.0,
                                  fontWeight: _danmakuFontWeight,
                                  massiveMode: _massiveMode,
                                  fontFamily: _danmakuUseSystemFont
                                      ? null
                                      : customAppFontFamily,
                                ),
                              ),
                            ),
                            if (_player.playback.isBuffering &&
                                !isLoadingVideo &&
                                errorMessage == null)
                              const Center(
                                child: CircularProgressIndicator(),
                              ),
                            if (isLoadingVideo || errorMessage != null)
                              _buildLoadingOrErrorOverlay(
                                colors: colors,
                                animeTitle: animeTitle,
                                episodeTitle: epTitle,
                                errorMessage: errorMessage,
                              ),
                            if (_showDebugLogs && _snifferLogs.isNotEmpty)
                              Positioned(
                                top: 24,
                                left: 36,
                                right: 36,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.72),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _snifferLogs
                                          .skip(
                                            math.max(
                                              0,
                                              _snifferLogs.length - 8,
                                            ),
                                          )
                                          .join('\n'),
                                      style: const TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_remote.isSeeking)
                              TvPlayerSeekHud(
                                targetPosition: _remote.pendingSeekPosition!,
                                startPosition: _remote.seekStartPosition ??
                                    _player.playback.currentPosition,
                                duration: _player.playback.duration,
                              )
                            else if (_showCenterIcon)
                              Center(
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    _centerIconPlaying
                                        ? Icons.play_arrow_rounded
                                        : Icons.pause_rounded,
                                    color: Colors.white,
                                    size: 44,
                                  ),
                                ),
                              ),
                            if (_remote.mode == TvPlayerUiMode.osd &&
                                !isLoadingVideo &&
                                errorMessage == null)
                              TvPlayerOverlay(
                                title: animeTitle,
                                subtitle: epTitle,
                                pluginName: _video.currentPlugin.name,
                                position: _player.playback.currentPosition,
                                duration: _player.playback.duration,
                                buffered: _player.playback.buffer,
                                playing: _player.playback.playing,
                                danmakuOn: _player.danmaku.danmakuOn,
                                playbackSpeed: _player.playback.playerSpeed,
                                aspectRatioLabel:
                                    _player.panel.aspectRatioMode.label,
                                skipOpSeconds: _player.playback.buttonSkipTime,
                                seekStepSeconds:
                                    _player.playback.arrowKeySkipTime,
                                canPrevEpisode: sel.episode > 1,
                                canNextEpisode: sel.episode < roadLen,
                                onUserActivity: _remote.resetOsdTimer,
                                onBack: _exitPlayer,
                                onPlayPause: _togglePlayPause,
                                onSeek: (target) =>
                                    unawaited(_player.seek(target)),
                                onPrevEpisode: () =>
                                    unawaited(_switchRelativeEpisode(-1)),
                                onNextEpisode: () =>
                                    unawaited(_switchRelativeEpisode(1)),
                                onSkipOp: () => unawaited(_player.seekBy(
                                  Duration(
                                      seconds: _player.playback.buttonSkipTime),
                                )),
                                onToggleDanmaku: _toggleDanmaku,
                                onCycleSpeed: _cycleSpeed,
                                onCycleAspectRatio: _cycleAspectRatio,
                                onOpenDrawer: () =>
                                    _remote.openDrawer(tabIndex: 0),
                              ),
                            if (_remote.mode == TvPlayerUiMode.drawer)
                              TvPlayerDrawer(
                                initialTab: _remote.drawerTabIndex,
                                videoPageController: _video,
                                playerController: _player,
                                onTabChanged: _remote.setDrawerTab,
                                onClose: () {
                                  _remote.closeDrawer();
                                  _restoreRootFocus();
                                },
                                onSelectEpisode: (ep, road) {
                                  _remote.closeDrawer();
                                  _restoreRootFocus();
                                  unawaited(
                                      _changeEpisode(ep, currentRoad: road));
                                },
                                onToggleDanmaku: _toggleDanmaku,
                                onSearchDanmaku: _openDanmakuSearch,
                                onDanmakuStyleChanged:
                                    _refreshDanmakuCanvasOptions,
                                onChangeSpeed: (s) =>
                                    unawaited(_player.setPlaybackSpeed(s)),
                                onChangeAspectRatio: (mode) =>
                                    _player.panel.aspectRatioMode = mode,
                                onChangeSuperResolution: (mode) =>
                                    unawaited(_setSuperResolution(mode)),
                                onReloadEpisode: () {
                                  _remote.closeDrawer();
                                  _restoreRootFocus();
                                  unawaited(_changeEpisode(
                                    sel.episode,
                                    currentRoad: sel.road,
                                  ));
                                },
                                showDebugLog: _showDebugLogs,
                                onToggleDebugLog: () => setState(
                                    () => _showDebugLogs = !_showDebugLogs),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingOrErrorOverlay({
    required ColorScheme colors,
    required String animeTitle,
    required String episodeTitle,
    required String? errorMessage,
  }) {
    final latestLog = _snifferLogs.isNotEmpty ? _snifferLogs.last : '';
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (errorMessage != null) ...[
              Icon(Icons.videocam_off_outlined, size: 56, color: colors.error),
              const SizedBox(height: 16),
              const Text(
                '播放失败',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TvPrimaryButton(
                    focusNode: _errorRetryFocus,
                    autofocus: true,
                    icon: Icons.refresh_rounded,
                    label: '重试本集',
                    onPressed: () {
                      final sel = _video.selectedEpisode;
                      unawaited(_changeEpisode(sel.episode, currentRoad: sel.road));
                    },
                  ),
                  const SizedBox(width: 14),
                  TvSecondaryButton(
                    icon: Icons.list_alt_rounded,
                    label: '切换线路/选集',
                    onPressed: () => _remote.openDrawer(tabIndex: 0),
                  ),
                  const SizedBox(width: 14),
                  TvSecondaryButton(
                    icon: Icons.arrow_back_rounded,
                    label: '返回',
                    onPressed: _exitPlayer,
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(strokeWidth: 3.2),
              ),
              const SizedBox(height: 18),
              Text(
                '$animeTitle · $episodeTitle',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _video.loading
                    ? '正在从「${_video.currentPlugin.name}」嗅探视频流…'
                    : '视频流解析成功，正在缓冲播放器…',
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              if (latestLog.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  latestLog,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
              const SizedBox(height: 22),
              TvSecondaryButton(
                focusNode: _loadingCancelFocus,
                autofocus: true,
                icon: Icons.arrow_back_rounded,
                label: '取消并返回',
                onPressed: _exitPlayer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
