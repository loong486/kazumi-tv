import 'package:flutter/material.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvChip extends StatelessWidget {
  const TvChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelect,
    this.onLongSelect,
    this.icon,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;
  final IconData? icon;
  final bool autofocus;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      onKeyEvent: onKeyEvent,
      borderRadius: 22,
      scaleOnFocus: 1.03,
      builder: (context, focused) {
        final bg = selected
            ? colors.primary
            : focused
                ? colors.surfaceContainerHighest
                : colors.surfaceContainerHigh;
        final fg = selected ? colors.onPrimary : colors.onSurface;
        return Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
