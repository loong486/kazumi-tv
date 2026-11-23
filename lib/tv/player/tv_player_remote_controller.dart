import 'dart:async';

import 'package:flutter/foundation.dart';

enum TvPlayerUiMode { idle, osd, drawer }

class TvPlayerRemoteController extends ChangeNotifier {
  TvPlayerRemoteController({
    this.osdAutoHideDelay = const Duration(seconds: 5),
    this.seekDebounceDelay = const Duration(milliseconds: 350),
    this.doubleBackWindow = const Duration(seconds: 2),
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final Duration osdAutoHideDelay;
  final Duration seekDebounceDelay;
  final Duration doubleBackWindow;
  final DateTime Function() _nowProvider;

  TvPlayerUiMode _mode = TvPlayerUiMode.idle;
  int _drawerTabIndex = 0;
  Duration? _pendingSeekPosition;
  Duration? _seekStartPosition;
  Timer? _osdTimer;
  Timer? _seekCommitTimer;
  DateTime? _lastBackPromptAt;
  bool _disposed = false;

  TvPlayerUiMode get mode => _mode;
  int get drawerTabIndex => _drawerTabIndex;
  Duration? get pendingSeekPosition => _pendingSeekPosition;
  Duration? get seekStartPosition => _seekStartPosition;
  bool get isSeeking => _pendingSeekPosition != null;

  void showOsd({bool autoHide = true}) {
    _mode = TvPlayerUiMode.osd;
    _lastBackPromptAt = null;
    if (autoHide) {
      resetOsdTimer();
    } else {
      _osdTimer?.cancel();
    }
    _notify();
  }

  void hideOsd() {
    _osdTimer?.cancel();
    if (_mode == TvPlayerUiMode.osd) {
      _mode = TvPlayerUiMode.idle;
      _notify();
    }
  }

  void openDrawer({int tabIndex = 0}) {
    _osdTimer?.cancel();
    _mode = TvPlayerUiMode.drawer;
    _drawerTabIndex = tabIndex.clamp(0, 2);
    _lastBackPromptAt = null;
    _notify();
  }

  void setDrawerTab(int tabIndex) {
    final next = tabIndex.clamp(0, 2);
    if (_drawerTabIndex != next) {
      _drawerTabIndex = next;
      _notify();
    }
  }

  void closeDrawer() {
    if (_mode == TvPlayerUiMode.drawer) {
      _mode = TvPlayerUiMode.idle;
      _notify();
    }
  }

  void resetOsdTimer() {
    _osdTimer?.cancel();
    if (_mode == TvPlayerUiMode.osd) {
      _osdTimer = Timer(osdAutoHideDelay, () {
        if (!_disposed && _mode == TvPlayerUiMode.osd) {
          _mode = TvPlayerUiMode.idle;
          _notify();
        }
      });
    }
  }

  void stepSeek({
    required Duration currentPosition,
    required Duration duration,
    required Duration delta,
    required ValueChanged<Duration> onCommitSeek,
  }) {
    final base = _pendingSeekPosition ?? currentPosition;
    _seekStartPosition ??= currentPosition;
    var nextMs = base.inMilliseconds + delta.inMilliseconds;
    if (nextMs < 0) nextMs = 0;
    if (duration > Duration.zero && nextMs > duration.inMilliseconds) {
      nextMs = duration.inMilliseconds;
    }
    _pendingSeekPosition = Duration(milliseconds: nextMs);
    _notify();

    _seekCommitTimer?.cancel();
    _seekCommitTimer = Timer(seekDebounceDelay, () {
      final target = _pendingSeekPosition;
      _pendingSeekPosition = null;
      _seekStartPosition = null;
      if (!_disposed) {
        _notify();
        if (target != null) {
          onCommitSeek(target);
        }
      }
    });
  }

  void cancelPendingSeek() {
    _seekCommitTimer?.cancel();
    _pendingSeekPosition = null;
    _seekStartPosition = null;
    _notify();
  }

  /// Handles Android TV Back key across Drawer -> OSD -> Double-Back Exit.
  /// Returns `true` when the caller should exit the player route.
  bool handleBack({VoidCallback? onFirstBackPrompt}) {
    if (_mode == TvPlayerUiMode.drawer) {
      closeDrawer();
      return false;
    }
    if (_mode == TvPlayerUiMode.osd) {
      hideOsd();
      return false;
    }

    final now = _nowProvider();
    final last = _lastBackPromptAt;
    if (last == null || now.difference(last) > doubleBackWindow) {
      _lastBackPromptAt = now;
      onFirstBackPrompt?.call();
      return false;
    }
    _lastBackPromptAt = null;
    return true;
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _osdTimer?.cancel();
    _seekCommitTimer?.cancel();
    super.dispose();
  }
}
