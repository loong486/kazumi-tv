import 'package:flutter/services.dart';

class TvKeys {
  TvKeys._();

  static bool isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  static bool isBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.browserBack ||
        key == LogicalKeyboardKey.gameButtonB;
  }

  static bool isKeyboardBackKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.gameButtonB;
  }

  static bool isMenuKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.info ||
        key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.keyM ||
        key == LogicalKeyboardKey.gameButtonX;
  }

  static bool isLeftKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowLeft;

  static bool isRightKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowRight;

  static bool isUpKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp;

  static bool isDownKey(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowDown;

  static bool isPlayPauseKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause ||
        key == LogicalKeyboardKey.space;
  }

  static bool isRewindKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaRewind ||
        key == LogicalKeyboardKey.mediaSkipBackward;
  }

  static bool isFastForwardKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaFastForward ||
        key == LogicalKeyboardKey.mediaSkipForward;
  }

  static bool isPrevEpisodeKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.channelUp;
  }

  static bool isNextEpisodeKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.channelDown;
  }
}
