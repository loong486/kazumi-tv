import 'package:flutter/material.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvPosterCard extends StatelessWidget {
  const TvPosterCard({
    super.key,
    required this.bangumiItem,
    required this.onSelect,
    this.onLongSelect,
    this.onFocusChange,
    this.onKeyEvent,
    this.focusNode,
    this.autofocus = false,
    this.badgeText,
    this.showScore,
  });

  final BangumiItem bangumiItem;
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;
  final ValueChanged<bool>? onFocusChange;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? badgeText;
  final bool? showScore;

  bool get _shouldShowScore {
    if (showScore != null) return showScore! && bangumiItem.ratingScore > 0;
    try {
      return GStorage.getSetting(SettingsKeys.showRating) &&
          bangumiItem.ratingScore > 0;
    } catch (_) {
      return bangumiItem.ratingScore > 0;
    }
  }

  String get _title =>
      bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;

  String get _posterUrl =>
      bangumiItem.images['large'] ?? bangumiItem.images['common'] ?? '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showRatingBadge = _shouldShowScore;

    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onSelect: onSelect,
      onLongSelect: onLongSelect,
      onFocusChange: onFocusChange,
      onKeyEvent: onKeyEvent,
      borderRadius: TvLayout.cardBorderRadius,
      scaleOnFocus: 1.03,
      builder: (context, focused) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(TvLayout.cardBorderRadius),
          child: Container(
            color: colors.surfaceContainer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    return NetworkImgLayer(
                      src: _posterUrl,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: BorderRadius.zero,
                    );
                  },
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.48, 1.0],
                        colors: [
                          Colors.black.withValues(alpha: 0.15),
                          Colors.transparent,
                          Colors.black.withValues(alpha: focused ? 0.92 : 0.84),
                        ],
                      ),
                    ),
                  ),
                ),
                if (badgeText != null && badgeText!.isNotEmpty)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText!,
                        style: TextStyle(
                          color: colors.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (showRatingBadge)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 13,
                            color: Color(0xFFFFCA28),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            bangumiItem.ratingScore.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Text(
                    _title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
