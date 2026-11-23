import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-oriented directional focus traversal policy that:
/// - stops at scope boundaries rather than wrapping bottom<->top or left<->right,
/// - scopes up/down traversal within the active vertical [Scrollable] first
///   until its edge is reached, and
/// - picks the nearest visual row before resolving horizontal column alignment
///   so partial middle rows (e.g. left-aligned chip bars) are never skipped.
class TvFocusTraversalPolicy extends ReadingOrderTraversalPolicy {
  TvFocusTraversalPolicy({super.requestFocusCallback});

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final nearestScope = currentNode.nearestScope;
    if (nearestScope == null) {
      return super.inDirection(currentNode, direction);
    }

    nearestScope.directionalTraversalEdgeBehavior = TraversalEdgeBehavior.stop;

    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right) {
      return super.inDirection(currentNode, direction);
    }

    final focusedChild = nearestScope.focusedChild;
    if (focusedChild == null ||
        focusedChild.context == null ||
        !_isAttached(focusedChild)) {
      return super.inDirection(currentNode, direction);
    }

    final focusedRect = focusedChild.rect;
    final allCandidates = nearestScope.traversalDescendants
        .where(
          (node) =>
              node != focusedChild &&
              node.canRequestFocus &&
              !node.skipTraversal &&
              node.context != null &&
              !(node is FocusScopeNode && node.traversalDescendants.isNotEmpty) &&
              _isAttached(node),
        )
        .toList();

    if (allCandidates.isEmpty) {
      return false;
    }

    bool matchesVerticalDirection(FocusNode candidate) {
      final rect = candidate.rect;
      if (direction == TraversalDirection.down) {
        return rect.center.dy > focusedRect.center.dy + 6.0 &&
            rect.top >= focusedRect.center.dy - 4.0;
      }
      return rect.center.dy < focusedRect.center.dy - 6.0 &&
          rect.bottom <= focusedRect.center.dy + 4.0;
    }

    final focusedScrollable = _effectiveVerticalScrollable(focusedChild.context!);
    List<FocusNode> directionalCandidates = const [];
    if (focusedScrollable != null) {
      directionalCandidates = allCandidates
          .where(
            (node) =>
                _effectiveVerticalScrollable(node.context!) ==
                    focusedScrollable &&
                matchesVerticalDirection(node),
          )
          .toList();
    }

    if (directionalCandidates.isEmpty) {
      directionalCandidates =
          allCandidates.where(matchesVerticalDirection).toList();
    }

    if (directionalCandidates.isEmpty) {
      return false;
    }

    directionalCandidates.sort((a, b) {
      final dyA = (a.rect.center.dy - focusedRect.center.dy).abs();
      final dyB = (b.rect.center.dy - focusedRect.center.dy).abs();
      return dyA.compareTo(dyB);
    });

    final nearestRowRef = directionalCandidates.first.rect;
    final rowCandidates = <FocusNode>[];
    for (final candidate in directionalCandidates) {
      final rect = candidate.rect;
      final centerClose =
          (rect.center.dy - nearestRowRef.center.dy).abs() <= 24.0;
      final verticalOverlap = math.min(rect.bottom, nearestRowRef.bottom) -
          math.max(rect.top, nearestRowRef.top);
      final minHeight = math.min(rect.height, nearestRowRef.height);
      final overlapsRow = minHeight > 0 && verticalOverlap > 0.4 * minHeight;
      if (centerClose || overlapsRow) {
        rowCandidates.add(candidate);
      }
    }

    final inHorizontalBand = rowCandidates.where((candidate) {
      final rect = candidate.rect;
      return rect.right > focusedRect.left && rect.left < focusedRect.right;
    }).toList();

    final FocusNode chosen;
    if (inHorizontalBand.isNotEmpty) {
      inHorizontalBand.sort((a, b) {
        final dxA = (a.rect.center.dx - focusedRect.center.dx).abs();
        final dxB = (b.rect.center.dx - focusedRect.center.dx).abs();
        final dxCmp = dxA.compareTo(dxB);
        if (dxCmp != 0) return dxCmp;
        final dyA = (a.rect.center.dy - focusedRect.center.dy).abs();
        final dyB = (b.rect.center.dy - focusedRect.center.dy).abs();
        return dyA.compareTo(dyB);
      });
      chosen = inHorizontalBand.first;
    } else {
      rowCandidates.sort((a, b) {
        final edgeA = _horizontalEdgeDistance(a.rect, focusedRect.center.dx);
        final edgeB = _horizontalEdgeDistance(b.rect, focusedRect.center.dx);
        final edgeCmp = edgeA.compareTo(edgeB);
        if (edgeCmp != 0) return edgeCmp;
        final dxA = (a.rect.center.dx - focusedRect.center.dx).abs();
        final dxB = (b.rect.center.dx - focusedRect.center.dx).abs();
        final dxCmp = dxA.compareTo(dxB);
        if (dxCmp != 0) return dxCmp;
        final dyA = (a.rect.center.dy - focusedRect.center.dy).abs();
        final dyB = (b.rect.center.dy - focusedRect.center.dy).abs();
        return dyA.compareTo(dyB);
      });
      chosen = rowCandidates.first;
    }

    requestFocusCallback(
      chosen,
      alignmentPolicy: direction == TraversalDirection.down
          ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
          : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    return true;
  }

  static bool _isAttached(FocusNode node) {
    final renderObject = node.context?.findRenderObject();
    return renderObject != null &&
        renderObject.attached &&
        (renderObject is! RenderBox || renderObject.hasSize);
  }

  static ScrollableState? _effectiveVerticalScrollable(BuildContext context) {
    var scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    while (scrollable != null) {
      final position = scrollable.position;
      final isNonScrollable =
          scrollable.widget.physics is NeverScrollableScrollPhysics ||
              (position.hasContentDimensions &&
                  position.maxScrollExtent <= position.minScrollExtent);
      if (!isNonScrollable) {
        return scrollable;
      }
      scrollable = Scrollable.maybeOf(scrollable.context, axis: Axis.vertical);
    }
    return null;
  }

  static double _horizontalEdgeDistance(Rect rect, double targetX) {
    if (targetX < rect.left) return rect.left - targetX;
    if (targetX > rect.right) return targetX - rect.right;
    return 0.0;
  }
}

/// Throttles held-key auto-repeats ([KeyRepeatEvent]) for directional D-pad
/// navigation while keeping fresh [KeyDownEvent] steps instantaneous.
class TvDirectionalFocusAction extends DirectionalFocusAction {
  TvDirectionalFocusAction() {
    _ensureRegistered();
  }

  static const Duration initialRepeatDelay = Duration(milliseconds: 240);
  static const Duration repeatInterval = Duration(milliseconds: 95);

  static FocusManager? _registeredFocusManager;
  static KeyEvent? _currentEvent;
  static final Map<LogicalKeyboardKey, Duration> _downTimeStamp = {};
  static final Map<LogicalKeyboardKey, DateTime> _downWallTime = {};
  static final Map<LogicalKeyboardKey, Duration> _downFrameTimeStamp = {};
  static final Map<LogicalKeyboardKey, Duration> _lastRepeatTimeStamp = {};
  static final Map<LogicalKeyboardKey, DateTime> _lastRepeatWallTime = {};
  static final Map<LogicalKeyboardKey, Duration> _lastRepeatFrameTimeStamp = {};

  static void _ensureRegistered() {
    final focusManager = FocusManager.instance;
    if (!identical(_registeredFocusManager, focusManager)) {
      _registeredFocusManager = focusManager;
      _currentEvent = null;
      _downTimeStamp.clear();
      _downWallTime.clear();
      _downFrameTimeStamp.clear();
      _lastRepeatTimeStamp.clear();
      _lastRepeatWallTime.clear();
      _lastRepeatFrameTimeStamp.clear();
      focusManager.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
      focusManager.addLateKeyEventHandler(_handleLateKeyEvent);
    }
  }

  static TraversalDirection? _directionForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.arrowUp) return TraversalDirection.up;
    if (key == LogicalKeyboardKey.arrowDown) return TraversalDirection.down;
    if (key == LogicalKeyboardKey.arrowLeft) return TraversalDirection.left;
    if (key == LogicalKeyboardKey.arrowRight) return TraversalDirection.right;
    return null;
  }

  static KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    final key = event.logicalKey;
    final dir = _directionForKey(key);
    if (dir == null) {
      _currentEvent = null;
      return KeyEventResult.ignored;
    }

    final now = DateTime.now();
    final frameTs = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    if (event is KeyDownEvent) {
      _downTimeStamp[key] = event.timeStamp;
      _downWallTime[key] = now;
      _downFrameTimeStamp[key] = frameTs;
      _lastRepeatTimeStamp.remove(key);
      _lastRepeatWallTime.remove(key);
      _lastRepeatFrameTimeStamp.remove(key);
      _currentEvent = event;
    } else if (event is KeyRepeatEvent) {
      _downTimeStamp.putIfAbsent(key, () => event.timeStamp);
      _downWallTime.putIfAbsent(key, () => now);
      _downFrameTimeStamp.putIfAbsent(key, () => frameTs);
      _currentEvent = event;
    } else if (event is KeyUpEvent) {
      _downTimeStamp.remove(key);
      _downWallTime.remove(key);
      _downFrameTimeStamp.remove(key);
      _lastRepeatTimeStamp.remove(key);
      _lastRepeatWallTime.remove(key);
      _lastRepeatFrameTimeStamp.remove(key);
      _currentEvent = null;
    }
    return KeyEventResult.ignored;
  }

  static KeyEventResult _handleLateKeyEvent(KeyEvent event) {
    if (identical(_currentEvent, event)) {
      _currentEvent = null;
    }
    return KeyEventResult.ignored;
  }

  static Duration _fallbackElapsed(
    DateTime now,
    DateTime? prevWall,
    Duration frameTs,
    Duration? prevFrameTs,
  ) {
    final wallElapsed =
        prevWall != null ? now.difference(prevWall) : Duration.zero;
    final frameElapsed =
        prevFrameTs != null && frameTs >= prevFrameTs
            ? frameTs - prevFrameTs
            : Duration.zero;
    return wallElapsed >= frameElapsed ? wallElapsed : frameElapsed;
  }

  static bool _shouldThrottleRepeat(KeyEvent event) {
    final key = event.logicalKey;
    final now = DateTime.now();
    final frameTs = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    final downTs = _downTimeStamp[key];
    final downWall = _downWallTime[key];
    final downFrameTs = _downFrameTimeStamp[key];
    final lastRepeatTs = _lastRepeatTimeStamp[key];
    final lastRepeatWall = _lastRepeatWallTime[key];
    final lastRepeatFrameTs = _lastRepeatFrameTimeStamp[key];

    final hasValidEventTs = event.timeStamp > Duration.zero &&
        (lastRepeatTs != null
            ? event.timeStamp >= lastRepeatTs
            : (downTs != null && event.timeStamp >= downTs));

    if (lastRepeatTs == null) {
      final elapsed = hasValidEventTs
          ? event.timeStamp - downTs!
          : _fallbackElapsed(now, downWall, frameTs, downFrameTs);
      if (elapsed < initialRepeatDelay) {
        return true;
      }
    } else {
      final elapsed = hasValidEventTs
          ? event.timeStamp - lastRepeatTs
          : _fallbackElapsed(now, lastRepeatWall, frameTs, lastRepeatFrameTs);
      if (elapsed < repeatInterval) {
        return true;
      }
    }

    _lastRepeatTimeStamp[key] = event.timeStamp;
    _lastRepeatWallTime[key] = now;
    _lastRepeatFrameTimeStamp[key] = frameTs;
    return false;
  }

  @override
  void invoke(DirectionalFocusIntent intent) {
    _ensureRegistered();
    final event = _currentEvent;
    _currentEvent = null;
    if (event is KeyRepeatEvent &&
        _directionForKey(event.logicalKey) == intent.direction &&
        _shouldThrottleRepeat(event)) {
      return;
    }
    if (primaryFocus == null) {
      return;
    }
    super.invoke(intent);
  }
}
