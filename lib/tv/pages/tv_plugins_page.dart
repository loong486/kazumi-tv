import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/pages/plugin_editor/plugin_update_actions.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/tv/shell/tv_shell_page.dart';
import 'package:kazumi/tv/theme/tv_theme.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_chip.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvPluginsPage extends StatefulWidget {
  const TvPluginsPage({super.key, required this.controller});

  final PluginsController controller;

  @override
  State<TvPluginsPage> createState() => _TvPluginsPageState();
}

class _TvPluginsPageState extends State<TvPluginsPage> {
  int _tabIndex = 0;
  bool _loadingCatalog = false;
  bool _catalogFailed = false;
  bool _updatingAll = false;
  final Set<String> _busyNames = {};

  PluginsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCatalog());
  }

  Future<void> _ensureCatalog({bool force = false}) async {
    if (_loadingCatalog) return;
    if (!force && _controller.isPluginCatalogFresh) return;
    setState(() {
      _loadingCatalog = true;
      _catalogFailed = false;
    });
    try {
      if (force) {
        await _controller.refreshPluginCatalog();
      } else {
        await _controller.ensurePluginCatalog();
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

  Future<void> _updateAll() async {
    if (_updatingAll) return;
    setState(() => _updatingAll = true);
    try {
      await updateAllPluginsWithFeedback(_controller, ensureCatalog: true);
    } finally {
      if (mounted) setState(() => _updatingAll = false);
    }
  }

  Future<void> _editRepository() async {
    final nextRepo = await showTvInputDialog(
      context,
      title: '自定义规则仓库地址',
      initialValue: _controller.ruleRepository,
      hintText: '留空使用官方默认仓库',
      confirmLabel: '保存并刷新',
    );
    if (nextRepo == null || !mounted) return;
    try {
      final changed = await _controller.setRuleRepository(nextRepo);
      if (!mounted) return;
      if (changed) {
        KazumiDialog.showToast(message: '规则仓库地址已更新');
        await _ensureCatalog(force: true);
      }
    } on FormatException catch (e) {
      if (mounted) KazumiDialog.showToast(message: e.message);
    } catch (_) {
      if (mounted) KazumiDialog.showToast(message: '规则仓库地址格式无效');
    }
  }

  Future<void> _handleInstalledPluginTap(Plugin plugin, int index) async {
    final availability = _controller.pluginUpdateStatus(plugin);
    final action = await showTvChoiceDialog<String>(
      context,
      title: plugin.name,
      subtitle: '版本 ${plugin.version} · ${plugin.baseUrl}',
      options: [
        if (availability == PluginUpdateAvailability.updatable)
          const TvChoiceOption(
            value: 'update',
            label: '更新此规则',
            icon: Icons.sync_rounded,
          ),
        if (index > 0)
          const TvChoiceOption(
            value: 'pin_top',
            label: '置顶排序（优先展示）',
            icon: Icons.vertical_align_top_rounded,
          ),
        const TvChoiceOption(
          value: 'delete',
          label: '删除此规则',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'update':
        if (_busyNames.add(plugin.name)) {
          setState(() {});
          try {
            await updatePluginWithFeedback(_controller, plugin.name,
                installing: false);
          } finally {
            if (mounted) setState(() => _busyNames.remove(plugin.name));
          }
        }
      case 'pin_top':
        await _controller.onReorder(index, 0);
        if (mounted) KazumiDialog.showToast(message: '已置顶 ${plugin.name}');
      case 'delete':
        final ok = await showTvConfirmDialog(
          context,
          title: '删除规则',
          message: '确认删除「${plugin.name}」吗？',
          confirmLabel: '删除',
          destructive: true,
        );
        if (ok) {
          await _controller.removePlugin(plugin);
        }
    }
  }

  Future<void> _handleCatalogTap(PluginHTTPItem item) async {
    if (!_busyNames.add(item.name)) return;
    setState(() {});
    try {
      final status = _controller.pluginStatus(item);
      await updatePluginWithFeedback(
        _controller,
        item.name,
        installing: status == PluginCatalogItemStatus.install,
      );
    } finally {
      if (mounted) setState(() => _busyNames.remove(item.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Observer(
      builder: (context) {
        final installed = _controller.pluginList.toList();
        final catalog = _controller.pluginHTTPList.toList();
        final updatableCount = installed
            .where((p) =>
                _controller.pluginUpdateStatus(p) ==
                PluginUpdateAvailability.updatable)
            .length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 24, 36, 10),
              child: Row(
                children: [
                  const Text(
                    '规则管理',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 24),
                  TvChip(
                    label: '已安装 (${installed.length})',
                    selected: _tabIndex == 0,
                    onSelect: () => setState(() => _tabIndex = 0),
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          TvKeys.isLeftKey(event.logicalKey)) {
                        TvShellScope.maybeOf(context)?.focusRail();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                  ),
                  const SizedBox(width: 10),
                  TvChip(
                    label: '规则仓库 (${catalog.length})',
                    selected: _tabIndex == 1,
                    onSelect: () {
                      setState(() => _tabIndex = 1);
                      unawaited(_ensureCatalog());
                    },
                  ),
                  const Spacer(),
                  TvSecondaryButton(
                    label: _updatingAll
                        ? '更新中…'
                        : updatableCount > 0
                            ? '全部更新 ($updatableCount)'
                            : '全部更新',
                    icon: Icons.system_update_alt_rounded,
                    onPressed: _updateAll,
                  ),
                  const SizedBox(width: 10),
                  TvSecondaryButton(
                    label: '仓库地址',
                    icon: Icons.link_rounded,
                    onPressed: _editRepository,
                  ),
                  const SizedBox(width: 10),
                  TvIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '刷新仓库',
                    onPressed: () => unawaited(_ensureCatalog(force: true)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tabIndex == 0
                  ? _buildInstalledGrid(colors, installed)
                  : _buildCatalogGrid(colors, catalog),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInstalledGrid(ColorScheme colors, List<Plugin> installed) {
    if (installed.isEmpty) {
      return Center(
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && TvKeys.isLeftKey(event.logicalKey)) {
              TvShellScope.maybeOf(context)?.focusRail();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_off_rounded,
                  size: 52, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('暂无已安装规则', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              TvPrimaryButton(
                label: '前往规则仓库安装',
                icon: Icons.download_rounded,
                onPressed: () {
                  setState(() => _tabIndex = 1);
                  unawaited(_ensureCatalog());
                },
              ),
            ],
          ),
        ),
      );
    }

    return TvAxisClipRect(
      axis: Axis.vertical,
      child: GridView.builder(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(36, 20, 36, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: TvLayout.gridSpacing,
          crossAxisSpacing: TvLayout.gridSpacing,
          mainAxisExtent: 82,
        ),
      itemCount: installed.length,
      itemBuilder: (context, index) {
        final plugin = installed[index];
        final isLeftCol = index % 3 == 0;
        final availability = _controller.pluginUpdateStatus(plugin);
        final busy = _busyNames.contains(plugin.name);

        return TvFocusable(
          borderRadius: 14,
          scaleOnFocus: 1.03,
          onSelect: () => unawaited(_handleInstalledPluginTap(plugin, index)),
          onKeyEvent: isLeftCol
              ? (_, event) {
                  if (event is KeyDownEvent &&
                      TvKeys.isLeftKey(event.logicalKey)) {
                    TvShellScope.maybeOf(context)?.focusRail();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
              : null,
          builder: (context, focused) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: focused
                    ? colors.surfaceContainerHighest
                    : colors.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plugin.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                plugin.usesApiSearch ? 'API' : 'XPath',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'v${plugin.version} · ${plugin.baseUrl}',
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
                  const SizedBox(width: 10),
                  if (busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (availability == PluginUpdateAvailability.updatable)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '可更新',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.onPrimary,
                        ),
                      ),
                    )
                  else
                    Icon(Icons.more_horiz_rounded,
                        color: colors.onSurfaceVariant),
                ],
              ),
            );
          },
        );
      },
      ),
    );
  }

  Widget _buildCatalogGrid(
      ColorScheme colors, List<PluginHTTPItem> catalog) {
    if (_loadingCatalog && catalog.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalogFailed && catalog.isEmpty) {
      return Center(
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && TvKeys.isLeftKey(event.logicalKey)) {
              TvShellScope.maybeOf(context)?.focusRail();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 52, color: colors.error),
              const SizedBox(height: 12),
              const Text('规则仓库加载失败，请检查网络连接或切换仓库加速'),
              const SizedBox(height: 16),
              TvPrimaryButton(
                label: '重新加载',
                icon: Icons.refresh_rounded,
                onPressed: () => unawaited(_ensureCatalog(force: true)),
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      TvKeys.isLeftKey(event.logicalKey)) {
                    TvShellScope.maybeOf(context)?.focusRail();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
              ),
            ],
          ),
        ),
      );
    }
    if (catalog.isEmpty) {
      return Center(
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent && TvKeys.isLeftKey(event.logicalKey)) {
              TvShellScope.maybeOf(context)?.focusRail();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_off_rounded,
                  size: 52, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('规则仓库暂无可用规则', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              TvPrimaryButton(
                label: '刷新仓库',
                icon: Icons.refresh_rounded,
                onPressed: () => unawaited(_ensureCatalog(force: true)),
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      TvKeys.isLeftKey(event.logicalKey)) {
                    TvShellScope.maybeOf(context)?.focusRail();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
              ),
            ],
          ),
        ),
      );
    }

    return TvAxisClipRect(
      axis: Axis.vertical,
      child: GridView.builder(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(36, 20, 36, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: TvLayout.gridSpacing,
          crossAxisSpacing: TvLayout.gridSpacing,
          mainAxisExtent: 82,
        ),
      itemCount: catalog.length,
      itemBuilder: (context, index) {
        final item = catalog[index];
        final isLeftCol = index % 3 == 0;
        final status = _controller.pluginStatus(item);
        final busy = _busyNames.contains(item.name);

        return TvFocusable(
          borderRadius: 14,
          scaleOnFocus: 1.03,
          onSelect: () {
            if (status == PluginCatalogItemStatus.installed) {
              KazumiDialog.showToast(message: '${item.name} 已是最新版本');
            } else {
              unawaited(_handleCatalogTap(item));
            }
          },
          onKeyEvent: isLeftCol
              ? (_, event) {
                  if (event is KeyDownEvent &&
                      TvKeys.isLeftKey(event.logicalKey)) {
                    TvShellScope.maybeOf(context)?.focusRail();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                }
              : null,
          builder: (context, focused) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: status == PluginCatalogItemStatus.installed
                    ? colors.primaryContainer.withValues(alpha: 0.35)
                    : focused
                        ? colors.surfaceContainerHighest
                        : colors.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
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
                  const SizedBox(width: 10),
                  if (busy)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: switch (status) {
                          PluginCatalogItemStatus.install => colors.primary,
                          PluginCatalogItemStatus.update => colors.tertiary,
                          PluginCatalogItemStatus.installed =>
                            colors.surfaceContainerHigh,
                        },
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        switch (status) {
                          PluginCatalogItemStatus.install => '安装',
                          PluginCatalogItemStatus.update => '更新',
                          PluginCatalogItemStatus.installed => '已安装',
                        },
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: switch (status) {
                            PluginCatalogItemStatus.install => colors.onPrimary,
                            PluginCatalogItemStatus.update => colors.onTertiary,
                            PluginCatalogItemStatus.installed =>
                              colors.onSurfaceVariant,
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
      ),
    );
  }
}
