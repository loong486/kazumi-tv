import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvDestination {
  const TvDestination({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<TvDestination> tvDestinations = [
  TvDestination(
    path: '/popular',
    label: '热门',
    icon: Icons.local_fire_department_outlined,
    selectedIcon: Icons.local_fire_department_rounded,
  ),
  TvDestination(
    path: '/timeline',
    label: '新番',
    icon: Icons.calendar_today_outlined,
    selectedIcon: Icons.calendar_today_rounded,
  ),
  TvDestination(
    path: '/search',
    label: '搜索',
    icon: Icons.search_outlined,
    selectedIcon: Icons.search_rounded,
  ),
  TvDestination(
    path: '/collect',
    label: '收藏',
    icon: Icons.bookmarks_outlined,
    selectedIcon: Icons.bookmarks_rounded,
  ),
  TvDestination(
    path: '/history',
    label: '历史',
    icon: Icons.history_outlined,
    selectedIcon: Icons.history_rounded,
  ),
  TvDestination(
    path: '/plugins',
    label: '规则',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension_rounded,
  ),
  TvDestination(
    path: '/settings',
    label: '设置',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
  ),
];

int tvDestinationIndexForPath(String path) {
  final index = tvDestinations.indexWhere(
    (item) =>
        path == '/tab${item.path}' ||
        path == '/tab${item.path}/' ||
        path.startsWith('/tab${item.path}/'),
  );
  return index < 0 ? 0 : index;
}

class TvShellScope extends InheritedWidget {
  const TvShellScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final TvShellController controller;

  static TvShellController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TvShellScope>()?.controller;
  }

  static TvShellController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'TvShellScope not found in widget tree');
    return controller!;
  }

  @override
  bool updateShouldNotify(TvShellScope oldWidget) =>
      !identical(controller, oldWidget.controller);
}

abstract class TvShellController {
  int get currentIndex;
  void focusRail();
  void focusContent();
  void selectTab(int index, {bool moveFocusToContent = true});
}

class TvShellPage extends StatefulWidget {
  const TvShellPage({
    super.key,
    required this.location,
    this.childBuilder,
    this.onDestinationChanged,
    this.onExitRequested,
  });

  final String location;
  final WidgetBuilder? childBuilder;
  final ValueChanged<int>? onDestinationChanged;
  final VoidCallback? onExitRequested;

  @override
  State<TvShellPage> createState() => _TvShellPageState();
}

class _TvShellPageState extends State<TvShellPage>
    with RouteAware
    implements TvShellController {
  final _outletKey = GlobalKey<RouterOutletState>();
  final FocusScopeNode _railScope = FocusScopeNode(debugLabel: 'TvRailScope');
  final FocusScopeNode _contentScope =
      FocusScopeNode(debugLabel: 'TvContentScope');
  late final List<FocusNode> _railNodes = List<FocusNode>.generate(
    tvDestinations.length,
    (i) => FocusNode(debugLabel: 'TvRailItem_$i'),
  );

  late int _selectedIndex = tvDestinationIndexForPath(widget.location);
  bool _railHasFocus = false;
  bool _isCovered = false;
  DateTime? _lastExitPromptAt;
  DateTime? _lastKeyBackAt;

  @override
  int get currentIndex => _selectedIndex;

  @override
  void didUpdateWidget(covariant TvShellPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location && widget.childBuilder == null) {
      final nextIndex = tvDestinationIndexForPath(widget.location);
      if (nextIndex != _selectedIndex) {
        setState(() => _selectedIndex = nextIndex);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    _railScope.dispose();
    _contentScope.dispose();
    for (final node in _railNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didPushNext() {
    if (mounted && !_isCovered) setState(() => _isCovered = true);
  }

  @override
  void didPopNext() {
    if (mounted && _isCovered) setState(() => _isCovered = false);
  }

  @override
  void focusRail() {
    _lastExitPromptAt = null;
    if (!mounted) return;
    _railNodes[_selectedIndex].requestFocus();
  }

  @override
  void focusContent() {
    _lastExitPromptAt = null;
    if (!mounted) return;
    _contentScope.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_contentScope.focusedChild == null) {
        _contentScope.nextFocus();
      }
    });
  }

  @override
  void selectTab(int index, {bool moveFocusToContent = true}) {
    _lastExitPromptAt = null;
    if (index < 0 || index >= tvDestinations.length) return;
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
      if (widget.childBuilder != null) {
        widget.onDestinationChanged?.call(index);
      } else {
        _outletKey.currentState?.navigate('/tab${tvDestinations[index].path}/');
      }
    }
    if (moveFocusToContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusContent();
      });
    }
  }

  void _handleBackAction({bool fromKeyEvent = false}) {
    if (!mounted || _isCovered || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    if (!fromKeyEvent &&
        _lastKeyBackAt != null &&
        DateTime.now().difference(_lastKeyBackAt!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }
    if (!_railHasFocus) {
      focusRail();
      return;
    }
    if (_railHasFocus && _selectedIndex != 0) {
      selectTab(0, moveFocusToContent: false);
      _railNodes[0].requestFocus();
      _lastExitPromptAt = null;
      return;
    }

    final now = DateTime.now();
    final last = _lastExitPromptAt;
    if (last == null || now.difference(last) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(
        message: '再按一次返回键退出 Kazumi TV',
        context: context,
      );
      return;
    }

    _lastExitPromptAt = null;
    if (widget.onExitRequested != null) {
      widget.onExitRequested!();
    } else {
      SystemNavigator.pop();
    }
  }

  KeyEventResult _handleShellKeyEvent(FocusNode _, KeyEvent event) {
    if (_isCovered || ModalRoute.of(context)?.isCurrent == false) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && TvKeys.isKeyboardBackKey(event.logicalKey)) {
      _lastKeyBackAt = DateTime.now();
      _handleBackAction(fromKeyEvent: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RouteVisibility(
      isCovered: _isCovered,
      child: TvShellScope(
        controller: this,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _handleBackAction(fromKeyEvent: false);
            }
          },
          child: Scaffold(
            body: Row(
              children: [
                FocusScope(
                  node: _railScope,
                  onFocusChange: (hasFocus) {
                    if (_railHasFocus != hasFocus) {
                      setState(() => _railHasFocus = hasFocus);
                    }
                  },
                  onKeyEvent: _handleShellKeyEvent,
                  child: AnimatedContainer(
                    duration: disableAnimations
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: _railHasFocus
                        ? TvLayout.railExpandedWidth
                        : TvLayout.railCollapsedWidth,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainer,
                      border: Border(
                        right: BorderSide(
                          color: colors.outlineVariant.withValues(alpha: 0.25),
                        ),
                      ),
                    ),
                    child: SafeArea(
                      right: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final showLabels =
                              _railHasFocus && constraints.maxWidth >= 160;
                          return Column(
                            children: [
                              const SizedBox(height: 20),
                              _RailBrandHeader(expanded: showLabels),
                              const SizedBox(height: 20),
                              Expanded(
                                child: TvAxisClipRect(
                                  axis: Axis.vertical,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 14,
                                    ),
                                    clipBehavior: Clip.none,
                                    itemCount: tvDestinations.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final dest = tvDestinations[index];
                                      final isSelected = index == _selectedIndex;
                                      return _RailItem(
                                        destination: dest,
                                        selected: isSelected,
                                        expanded: showLabels,
                                        focusNode: _railNodes[index],
                                        onSelect: () => selectTab(index),
                                        onMoveRight: focusContent,
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: FocusScope(
                    node: _contentScope,
                    autofocus: true,
                    onKeyEvent: _handleShellKeyEvent,
                    child: widget.childBuilder != null
                        ? Builder(
                            builder: (innerContext) =>
                                widget.childBuilder!(innerContext),
                          )
                        : NotificationListener<NavigationNotification>(
                            onNotification: (n) => !n.canHandlePop,
                            child: RouterOutlet(key: _outletKey),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrandHeader extends StatelessWidget {
  const _RailBrandHeader({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: expanded ? 18 : 16),
      child: Row(
        mainAxisAlignment:
            expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/logo/logo_rounded.png',
              width: 38,
              height: 38,
              errorBuilder: (_, __, ___) => Icon(
                Icons.tv_rounded,
                size: 32,
                color: colors.primary,
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Kazumi TV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.expanded,
    required this.focusNode,
    required this.onSelect,
    required this.onMoveRight,
  });

  final TvDestination destination;
  final bool selected;
  final bool expanded;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback onMoveRight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusable(
      focusNode: focusNode,
      onSelect: onSelect,
      borderRadius: 14,
      scaleOnFocus: 1.03,
      ensureVisibleAlignment: 0.5,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && TvKeys.isRightKey(event.logicalKey)) {
          onMoveRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      builder: (context, focused) {
        final bg = focused
            ? colors.primary
            : selected
                ? colors.primaryContainer.withValues(alpha: 0.65)
                : Colors.transparent;
        final fg = focused
            ? colors.onPrimary
            : selected
                ? colors.primary
                : colors.onSurfaceVariant;

        return Container(
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(
                selected || focused
                    ? destination.selectedIcon
                    : destination.icon,
                size: 24,
                color: fg,
              ),
              if (expanded) ...[
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15,
                      fontWeight:
                          selected || focused ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
