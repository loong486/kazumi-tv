import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_poster_card.dart';

class TvPosterGrid extends StatelessWidget {
  const TvPosterGrid({
    super.key,
    required this.items,
    required this.onItemSelected,
    this.onItemLongSelected,
    this.badgeBuilder,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasError = false,
    this.errorTitle = '加载失败',
    this.errorMessage = '请检查网络连接后重试',
    this.emptyTitle = '暂无内容',
    this.emptyIcon = Icons.movie_filter_outlined,
    this.onRetry,
    this.onLoadMore,
    this.onLeftBoundary,
    this.scrollController,
    this.autofocusFirst = false,
    this.padding = const EdgeInsets.fromLTRB(36, 20, 36, 32),
  });

  final List<BangumiItem> items;
  final ValueChanged<BangumiItem> onItemSelected;
  final ValueChanged<BangumiItem>? onItemLongSelected;
  final String? Function(BangumiItem item)? badgeBuilder;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasError;
  final String errorTitle;
  final String errorMessage;
  final String emptyTitle;
  final IconData emptyIcon;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final VoidCallback? onLeftBoundary;
  final ScrollController? scrollController;
  final bool autofocusFirst;
  final EdgeInsetsGeometry padding;

  static int columnCountForWidth(double width) {
    if (width >= 1500) return 6;
    if (width >= 900) return 5;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (isLoading && items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载…', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    if (hasError && items.isEmpty) {
      return Center(
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                TvKeys.isLeftKey(event.logicalKey) &&
                onLeftBoundary != null) {
              onLeftBoundary!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 52, color: colors.error),
              const SizedBox(height: 14),
              Text(
                errorTitle,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                errorMessage,
                style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                TvPrimaryButton(
                  label: '重试',
                  icon: Icons.refresh_rounded,
                  autofocus: autofocusFirst,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                TvKeys.isLeftKey(event.logicalKey) &&
                onLeftBoundary != null) {
              onLeftBoundary!();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 52, color: colors.onSurfaceVariant),
              const SizedBox(height: 14),
              Text(
                emptyTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = columnCountForWidth(constraints.maxWidth);
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverPadding(
              padding: padding,
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: TvLayout.gridSpacing,
                  crossAxisSpacing: TvLayout.gridSpacing,
                  childAspectRatio: 0.68,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    final isLeftCol = index % crossAxisCount == 0;
                    return TvPosterCard(
                      key: ValueKey('poster_${item.id}_$index'),
                      bangumiItem: item,
                      autofocus: autofocusFirst && index == 0,
                      badgeText: badgeBuilder?.call(item),
                      onSelect: () => onItemSelected(item),
                      onLongSelect: onItemLongSelected == null
                          ? null
                          : () => onItemLongSelected!(item),
                      onFocusChange: (focused) {
                        if (focused &&
                            onLoadMore != null &&
                            !isLoadingMore &&
                            index >= items.length - crossAxisCount * 2) {
                          onLoadMore!();
                        }
                      },
                      onKeyEvent: isLeftCol && onLeftBoundary != null
                          ? (_, event) {
                              if (event is KeyDownEvent &&
                                  TvKeys.isLeftKey(event.logicalKey)) {
                                onLeftBoundary!();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            }
                          : null,
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
            if (isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }
}
