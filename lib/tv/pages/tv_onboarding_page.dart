import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/network/acceleration_mode.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/rules_mirror.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvOnboardingPage extends StatefulWidget {
  const TvOnboardingPage({super.key, required this.pluginsController});

  final PluginsController pluginsController;

  @override
  State<TvOnboardingPage> createState() => _TvOnboardingPageState();
}

class _TvOnboardingPageState extends State<TvOnboardingPage> {
  int _step = 0;
  String? _statements;
  bool _loadingCatalog = false;
  bool _catalogFailed = false;
  final Set<String> _installing = {};
  final ScrollController _disclaimerScrollController = ScrollController();
  DateTime? _lastExitPromptAt;
  DateTime? _lastKeyBackAt;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStatements());
  }

  @override
  void dispose() {
    _disclaimerScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadStatements() async {
    try {
      final text = await rootBundle.loadString('assets/statements/statements.txt');
      if (mounted) setState(() => _statements = text.trim());
    } catch (_) {
      if (mounted) setState(() => _statements = 'Kazumi 仅提供规则解析工具，请遵守当地法律法规。');
    }
  }

  Future<void> _loadCatalog({bool force = false}) async {
    if (_loadingCatalog) return;
    setState(() {
      _loadingCatalog = true;
      _catalogFailed = false;
    });
    try {
      if (force) {
        await widget.pluginsController.refreshPluginCatalog();
      } else {
        await widget.pluginsController.ensurePluginCatalog();
      }
      if (mounted) setState(() => _loadingCatalog = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingCatalog = false;
          _catalogFailed = true;
        });
      }
    }
  }

  Future<void> _installRule(PluginHTTPItem item) async {
    if (!_installing.add(item.name)) return;
    setState(() {});
    try {
      final status = widget.pluginsController.pluginStatus(item);
      await updatePluginWithFeedback(
        widget.pluginsController,
        item.name,
        installing: status == PluginCatalogItemStatus.install,
      );
    } finally {
      if (mounted) setState(() => _installing.remove(item.name));
    }
  }

  Future<void> _finish() async {
    if (widget.pluginsController.pluginList.isEmpty) {
      final confirmed = await showTvConfirmDialog(
        context,
        title: '尚未安装任何规则',
        message: '未安装视频源规则将无法在线搜索与播放番剧。确认先进入主界面吗？之后可在「规则」页随时安装。',
        confirmLabel: '先进入应用',
        cancelLabel: '继续安装规则',
      );
      if (!confirmed || !mounted) return;
    }
    await GStorage.putSetting(SettingsKeys.onboardingCompleted, true);
    if (mounted) {
      context.navigate('/tab/popular');
    }
  }

  Future<void> _pickAcceleration<T extends AccelerationMode>({
    required String title,
    required T current,
    required List<T> modes,
    required SettingKey<String> key,
  }) async {
    final chosen = await showTvChoiceDialog<T>(
      context,
      title: title,
      currentValue: current,
      options: [
        for (final mode in modes)
          TvChoiceOption(
            value: mode,
            label: mode.label,
            subtitle: mode.description,
          ),
      ],
    );
    if (chosen == null || chosen == current) return;
    await GStorage.putSetting(key, chosen.name);
    if (mounted) setState(() {});
  }

  void _goToStep(int next) {
    _lastExitPromptAt = null;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = next);
    if (next == 2 &&
        !widget.pluginsController.isPluginCatalogFresh &&
        !_loadingCatalog) {
      unawaited(_loadCatalog());
    }
  }

  void _handleBackPress({bool fromKeyEvent = false}) {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (!fromKeyEvent &&
        _lastKeyBackAt != null &&
        DateTime.now().difference(_lastKeyBackAt!) <
            const Duration(milliseconds: 250)) {
      return;
    }
    if (_step > 0) {
      _goToStep(_step - 1);
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
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final steps = ['1. 使用约定', '2. 网络加速', '3. 安装规则'];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _handleBackPress(fromKeyEvent: false);
        }
      },
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (ModalRoute.of(context)?.isCurrent == false) {
            return KeyEventResult.ignored;
          }
          if (event is KeyDownEvent &&
              TvKeys.isKeyboardBackKey(event.logicalKey)) {
            _lastKeyBackAt = DateTime.now();
            _handleBackPress(fromKeyEvent: true);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
        body: Padding(
          padding: TvLayout.overscanPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      'assets/images/logo/logo_rounded.png',
                      width: 40,
                      height: 40,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    '欢迎使用 Kazumi TV',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  for (var i = 0; i < steps.length; i++) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: i == _step
                            ? colors.primary
                            : i < _step
                                ? colors.primaryContainer
                                : colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: i == _step
                              ? colors.onPrimary
                              : i < _step
                                  ? colors.onPrimaryContainer
                                  : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (i < steps.length - 1) const SizedBox(width: 10),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      0 => _buildDisclaimerStep(colors),
                      1 => _buildNetworkStep(colors),
                      _ => _buildRulesStep(colors),
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_step == 0)
                    TvSecondaryButton(
                      label: '退出应用',
                      onPressed: SystemNavigator.pop,
                    )
                  else
                    TvSecondaryButton(
                      label: '上一步',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => _goToStep(_step - 1),
                    ),
                  const SizedBox(width: 14),
                  if (_step < 2)
                    TvPrimaryButton(
                      key: ValueKey('onboarding_primary_$_step'),
                      label: _step == 0 ? '同意并继续' : '下一步',
                      icon: Icons.arrow_forward_rounded,
                      autofocus: _step == 0,
                      onPressed: () => _goToStep(_step + 1),
                    )
                  else
                    TvPrimaryButton(
                      key: const ValueKey('onboarding_primary_2'),
                      label: '开始使用',
                      icon: Icons.check_rounded,
                      autofocus: widget.pluginsController.pluginList.isNotEmpty,
                      onPressed: _finish,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildDisclaimerStep(ColorScheme colors) {
    if (_statements == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return TvFocusable(
      borderRadius: 14,
      scaleOnFocus: 1.005,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (!_disclaimerScrollController.hasClients) {
          return KeyEventResult.ignored;
        }
        final maxExtent = _disclaimerScrollController.position.maxScrollExtent;
        if (maxExtent <= 0) {
          return KeyEventResult.ignored;
        }
        final disableAnimations = MediaQuery.disableAnimationsOf(context);
        if (TvKeys.isDownKey(event.logicalKey)) {
          if (_disclaimerScrollController.offset >= maxExtent - 0.5) {
            return KeyEventResult.ignored;
          }
          final next = (_disclaimerScrollController.offset + 180)
              .clamp(0.0, maxExtent);
          if (disableAnimations) {
            _disclaimerScrollController.jumpTo(next);
          } else {
            unawaited(
              _disclaimerScrollController.animateTo(
                next,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
              ),
            );
          }
          return KeyEventResult.handled;
        }
        if (TvKeys.isUpKey(event.logicalKey)) {
          if (_disclaimerScrollController.offset <= 0.5) {
            return KeyEventResult.ignored;
          }
          final next = (_disclaimerScrollController.offset - 180)
              .clamp(0.0, maxExtent);
          if (disableAnimations) {
            _disclaimerScrollController.jumpTo(next);
          } else {
            unawaited(
              _disclaimerScrollController.animateTo(
                next,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOutCubic,
              ),
            );
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Scrollbar(
          controller: _disclaimerScrollController,
          child: SingleChildScrollView(
            controller: _disclaimerScrollController,
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined, color: colors.primary),
                    const SizedBox(width: 10),
                    const Text(
                      '免责声明与遥控器提示',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final line in _statements!.split('\n'))
                  if (line.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        line.trim(),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.65,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '遥控器提示：播放时按「确定」暂停/继续，「左/右」快退快进，「上/下」呼出播放控制栏，「菜单」键或控制栏「选集与设置」打开选集与弹幕面板。',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStep(ColorScheme colors) {
    return TvAxisClipRect(
      axis: Axis.vertical,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.none,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '访问加速设置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '若在电视网络下加载番剧列表或规则仓库较慢，可在此切换加速路线（稍后也可在设置中修改）。',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _NetworkCard(
                    autofocus: true,
                    icon: Icons.travel_explore_rounded,
                  title: '番剧条目加速',
                  value: BangumiAcceleration.current.label,
                  subtitle: BangumiAcceleration.current.description,
                  onSelect: () => _pickAcceleration<BangumiAcceleration>(
                    title: '番剧条目加速',
                    current: BangumiAcceleration.current,
                    modes: BangumiAcceleration.values,
                    key: SettingsKeys.bangumiAcceleration,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _NetworkCard(
                  icon: Icons.extension_rounded,
                  title: '规则仓库加速',
                  value: RulesMirror.current.label,
                  subtitle: RulesMirror.current.description,
                  onSelect: () => _pickAcceleration<RulesMirror>(
                    title: '规则仓库加速',
                    current: RulesMirror.current,
                    modes: RulesMirror.values,
                    key: SettingsKeys.rulesMirror,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _NetworkCard(
                  icon: Icons.image_rounded,
                  title: '图片加速',
                  value: ImageAcceleration.current.label,
                  subtitle: ImageAcceleration.current.description,
                  onSelect: () => _pickAcceleration<ImageAcceleration>(
                    title: '图片加速',
                    current: ImageAcceleration.current,
                    modes: ImageAcceleration.values,
                    key: SettingsKeys.imageAcceleration,
                  ),
                ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesStep(ColorScheme colors) {
    return Observer(
      builder: (context) {
        final items = widget.pluginsController.pluginHTTPList.toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '官方规则仓库（已安装 ${widget.pluginsController.pluginList.length} 条）',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TvSecondaryButton(
                  label: '刷新列表',
                  icon: Icons.refresh_rounded,
                  onPressed: () {
                    if (!_loadingCatalog) {
                      unawaited(_loadCatalog(force: true));
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _loadingCatalog && items.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _catalogFailed && items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  size: 48, color: colors.error),
                              const SizedBox(height: 12),
                              const Text('规则仓库加载失败，请检查网络或返回上一步切换镜像'),
                              const SizedBox(height: 14),
                              TvPrimaryButton(
                                label: '重新加载',
                                icon: Icons.refresh_rounded,
                                onPressed: () => _loadCatalog(force: true),
                              ),
                            ],
                          ),
                        )
                      : TvAxisClipRect(
                          axis: Axis.vertical,
                          child: GridView.builder(
                            clipBehavior: Clip.none,
                            padding: const EdgeInsets.all(20),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              mainAxisExtent: 76,
                            ),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final status =
                                  widget.pluginsController.pluginStatus(item);
                              final busy = _installing.contains(item.name);
                              final installed =
                                  status == PluginCatalogItemStatus.installed;
                              return TvFocusable(
                                autofocus: index == 0,
                                borderRadius: 12,
                                scaleOnFocus: 1.03,
                                onSelect: () {
                                  if (installed) {
                                    KazumiDialog.showToast(
                                        message: '${item.name} 已安装');
                                  } else {
                                    unawaited(_installRule(item));
                                  }
                                },
                                builder: (context, focused) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: installed
                                          ? colors.primaryContainer
                                              .withValues(alpha: 0.45)
                                          : colors.surfaceContainerHigh,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                item.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'v${item.version}${item.author.isNotEmpty ? ' · ${item.author}' : ''}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colors.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (busy)
                                          const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        else
                                          Icon(
                                            installed
                                                ? Icons.check_circle_rounded
                                                : Icons.download_rounded,
                                            size: 20,
                                            color: installed
                                                ? colors.primary
                                                : colors.onSurfaceVariant,
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.onSelect,
    this.autofocus = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TvFocusable(
      autofocus: autofocus,
      onSelect: onSelect,
      borderRadius: 14,
      scaleOnFocus: 1.03,
      builder: (context, focused) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: colors.primary),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
