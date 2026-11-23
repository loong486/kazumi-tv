import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';

typedef TvFocusableBuilder = Widget Function(BuildContext context, bool focused);

class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    this.child,
    this.builder,
    this.onSelect,
    this.onLongSelect,
    this.onFocusChange,
    this.onKeyEvent,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.canRequestFocus = true,
    this.borderRadius = TvLayout.cardBorderRadius,
    this.scaleOnFocus = TvLayout.focusScale,
    this.showFocusBorder = true,
    this.ensureVisible = true,
    this.ensureVisibleAlignment = 0.5,
    this.focusBorderColor,
    this.padding = EdgeInsets.zero,
  }) : assert(child != null || builder != null);

  final Widget? child;
  final TvFocusableBuilder? builder;
  final VoidCallback? onSelect;
  final VoidCallback? onLongSelect;
  final ValueChanged<bool>? onFocusChange;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;
  final bool canRequestFocus;
  final double borderRadius;
  final double scaleOnFocus;
  final bool showFocusBorder;
  final bool ensureVisible;
  final double ensureVisibleAlignment;
  final Color? focusBorderColor;
  final EdgeInsetsGeometry padding;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  static const Duration _longPressThreshold = Duration(milliseconds: 500);

  FocusNode? _internalFocusNode;
  bool _focused = false;
  bool _selectDown = false;
  bool _longPressFired = false;
  Timer? _longPressTimer;

  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _internalFocusNode = FocusNode(debugLabel: 'TvFocusable');
    }
    _focused = _focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (widget.focusNode == null) {
        _internalFocusNode ??= FocusNode(debugLabel: 'TvFocusable');
      } else {
        _internalFocusNode?.dispose();
        _internalFocusNode = null;
      }
      _focused = _focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    _cancelLongPress();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _selectDown = false;
    _longPressFired = false;
  }

  void _handleFocusChange(bool hasFocus) {
    if (!hasFocus) {
      _cancelLongPress();
    }
    if (_focused != hasFocus) {
      setState(() => _focused = hasFocus);
    }
    widget.onFocusChange?.call(hasFocus);
    if (hasFocus && widget.ensureVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _ensureGlowVisibleIfNeeded();
      });
    }
  }

  void _ensureGlowVisibleIfNeeded() {
    if (!mounted || !_focusNode.hasFocus || !widget.ensureVisible) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }

    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final duration =
        disableAnimations ? Duration.zero : const Duration(milliseconds: 100);
    const glowMargin = 18.0;

    ScrollableState? scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      final position = scrollable.position;
      if (position.hasPixels &&
          position.hasContentDimensions &&
          position.maxScrollExtent > position.minScrollExtent) {
        final scrollableObject = scrollable.context.findRenderObject();
        if (scrollableObject is RenderBox &&
            scrollableObject.attached &&
            scrollableObject.hasSize) {
          final axis = axisDirectionToAxis(scrollable.axisDirection);
          final topLeft = renderObject.localToGlobal(
            Offset.zero,
            ancestor: scrollableObject,
          );
          final rect = topLeft & renderObject.size;
          final start = axis == Axis.vertical ? rect.top : rect.left;
          final end = axis == Axis.vertical ? rect.bottom : rect.right;
          final viewportExtent = axis == Axis.vertical
              ? scrollableObject.size.height
              : scrollableObject.size.width;

          if (viewportExtent > 0) {
            final isReversed = scrollable.axisDirection == AxisDirection.up ||
                scrollable.axisDirection == AxisDirection.left;
            ScrollPositionAlignmentPolicy? policy;
            double delta = 0.0;
            if (start - glowMargin < 0) {
              policy = ScrollPositionAlignmentPolicy.keepVisibleAtStart;
              delta = start - glowMargin;
            } else if (end + glowMargin > viewportExtent) {
              policy = ScrollPositionAlignmentPolicy.keepVisibleAtEnd;
              delta = (end + glowMargin) - viewportExtent;
              if (start - delta < glowMargin) {
                delta = math.max(0.0, start - glowMargin);
              }
            }

            if (policy != null && delta != 0.0) {
              final rawTarget = isReversed
                  ? position.pixels - delta
                  : position.pixels + delta;
              final target = clampDouble(
                rawTarget,
                position.minScrollExtent,
                position.maxScrollExtent,
              );
              final isForwardStep = policy ==
                      ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                  ? (isReversed
                      ? target < position.pixels
                      : target > position.pixels)
                  : (isReversed
                      ? target > position.pixels
                      : target < position.pixels);
              if (isForwardStep && (target - position.pixels).abs() >= 0.5) {
                if (duration == Duration.zero) {
                  position.jumpTo(target);
                } else {
                  unawaited(
                    position.animateTo(
                      target,
                      duration: duration,
                      curve: Curves.easeOutCubic,
                    ),
                  );
                }
              }
            }
          }
        }
      }
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final customResult = widget.onKeyEvent?.call(node, event);
    if (customResult == KeyEventResult.handled) {
      return KeyEventResult.handled;
    }
    if (!widget.enabled) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (TvKeys.isMenuKey(key) && event is KeyDownEvent) {
      if (widget.onLongSelect != null) {
        widget.onLongSelect!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (!TvKeys.isSelectKey(key)) {
      return KeyEventResult.ignored;
    }

    if (widget.onSelect == null && widget.onLongSelect == null) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent) {
      if (widget.onLongSelect == null) {
        widget.onSelect?.call();
        return KeyEventResult.handled;
      }
      _selectDown = true;
      _longPressFired = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(_longPressThreshold, () {
        if (!mounted || !_selectDown || _longPressFired) return;
        _longPressFired = true;
        widget.onLongSelect?.call();
      });
      return KeyEventResult.handled;
    }

    if (event is KeyRepeatEvent && widget.onLongSelect != null) {
      return _selectDown ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (event is KeyUpEvent && _selectDown) {
      final wasLongPress = _longPressFired;
      _cancelLongPress();
      if (!wasLongPress) {
        widget.onSelect?.call();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final glowColor = widget.focusBorderColor ?? colorScheme.primary;
    final isFocused = _focused && widget.enabled;
    final content = widget.builder?.call(context, isFocused) ?? widget.child!;
    final radius = BorderRadius.circular(widget.borderRadius);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled && widget.canRequestFocus,
      skipTraversal: !(widget.enabled && widget.canRequestFocus),
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled
            ? () {
                if (widget.canRequestFocus && !_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
                widget.onSelect?.call();
              }
            : null,
        onLongPress: widget.enabled && widget.onLongSelect != null
            ? () {
                if (widget.canRequestFocus && !_focusNode.hasFocus) {
                  _focusNode.requestFocus();
                }
                widget.onLongSelect?.call();
              }
            : null,
        child: AnimatedScale(
          scale: isFocused ? widget.scaleOnFocus : 1.0,
          duration:
              disableAnimations ? Duration.zero : TvLayout.focusAnimationDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: disableAnimations
                ? Duration.zero
                : TvLayout.focusAnimationDuration,
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: widget.showFocusBorder
                ? BoxDecoration(
                    borderRadius: radius,
                    boxShadow: isFocused
                        ? [
                            BoxShadow(
                              color: glowColor.withValues(alpha: 0.48),
                              blurRadius: TvLayout.focusGlowBlur,
                              spreadRadius: TvLayout.focusGlowSpread,
                            ),
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.24),
                              blurRadius: 4,
                            ),
                          ]
                        : const [],
                  )
                : null,
            foregroundDecoration: widget.showFocusBorder && isFocused
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.95),
                      width: TvLayout.focusBorderWidth,
                    ),
                  )
                : null,
            child: content,
          ),
        ),
      ),
    );
  }
}
