import 'package:flutter/material.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvPrimaryButton extends StatelessWidget {
  const TvPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.destructive = false,
    this.onKeyEvent,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool destructive;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bgColor = destructive ? colors.error : colors.primary;
    final fgColor = destructive ? colors.onError : colors.onPrimary;

    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled && onPressed != null,
      onSelect: onPressed,
      onKeyEvent: onKeyEvent,
      borderRadius: 12,
      scaleOnFocus: 1.03,
      focusBorderColor: destructive ? colors.error : colors.primary,
      builder: (context, focused) {
        return Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: enabled ? bgColor : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: enabled ? fgColor : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: enabled ? fgColor : colors.onSurfaceVariant,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TvSecondaryButton extends StatelessWidget {
  const TvSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.selected = false,
    this.onKeyEvent,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool selected;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled && onPressed != null,
      onSelect: onPressed,
      onKeyEvent: onKeyEvent,
      borderRadius: 12,
      scaleOnFocus: 1.03,
      builder: (context, focused) {
        final bg = selected
            ? colors.primaryContainer
            : focused
                ? colors.surfaceContainerHighest
                : colors.surfaceContainerHigh;
        final fg = selected ? colors.onPrimaryContainer : colors.onSurface;
        return Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: enabled ? fg : colors.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TvIconButton extends StatelessWidget {
  const TvIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.size = 44,
    this.iconSize = 22,
    this.active = false,
    this.onKeyEvent,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final double size;
  final double iconSize;
  final bool active;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final button = TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled && onPressed != null,
      onSelect: onPressed,
      onKeyEvent: onKeyEvent,
      borderRadius: size / 2,
      scaleOnFocus: 1.04,
      builder: (context, focused) {
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? colors.primaryContainer
                : focused
                    ? colors.surfaceContainerHighest
                    : colors.surfaceContainerHigh.withValues(alpha: 0.85),
          ),
          child: Icon(
            icon,
            size: iconSize,
            color: active ? colors.onPrimaryContainer : colors.onSurface,
          ),
        );
      },
    );

    if (tooltip == null || tooltip!.isEmpty) {
      return button;
    }
    return Tooltip(message: tooltip!, child: button);
  }
}
