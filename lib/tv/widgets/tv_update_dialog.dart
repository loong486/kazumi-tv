import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/tv/update/tv_update_models.dart';
import 'package:kazumi/tv/update/tv_update_service.dart';
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/utils/tv_platform_channel.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_dialog.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';
import 'package:kazumi/utils/date_time.dart';

enum TvUpdateDialogAction {
  updateNow,
  switchMirror,
  later,
  ignoreVersion,
}

Future<void> checkTvUpdatesSilently({TvUpdateService? service}) {
  return TvUpdateCoordinator.checkSilently(service: service);
}

Future<void> checkTvUpdatesInteractively(
  BuildContext context, {
  TvUpdateService? service,
}) {
  return TvUpdateCoordinator.checkInteractively(context, service: service);
}

Future<void> showTvUpdateFlow({
  BuildContext? context,
  required TvUpdateCheckResult result,
  TvUpdateService? service,
}) {
  return TvUpdateCoordinator.showUpdateFlow(
    context: context,
    result: result,
    service: service,
  );
}

class TvUpdateCoordinator {
  TvUpdateCoordinator._();

  static Future<void>? _activeFlow;

  static bool get isRunning => _activeFlow != null;

  static Future<void> _runSingleFlight(Future<void> Function() task) {
    final active = _activeFlow;
    if (active != null) {
      return active;
    }
    late final Future<void> flow;
    flow = () async {
      try {
        await task();
      } finally {
        if (identical(_activeFlow, flow)) {
          _activeFlow = null;
        }
      }
    }();
    _activeFlow = flow;
    return flow;
  }

  static Future<void> checkSilently({TvUpdateService? service}) {
    return _runSingleFlight(() async {
      final updateService = service ?? TvUpdateService.instance;
      final TvUpdateCheckResult result;
      try {
        result = await updateService.checkForUpdates();
      } catch (e, stackTrace) {
        KazumiLogger().w(
          'TvUpdate: silent update check failed',
          error: e,
          stackTrace: stackTrace,
        );
        return;
      }

      final release = result.release;
      final asset = result.matchedAsset;
      if (!result.hasUpdate || release == null || asset == null) {
        return;
      }

      final ignored = TvUpdateConfig.ignoredVersion;
      if (!release.force &&
          ignored.isNotEmpty &&
          TvVersionComparator.normalizeVersion(release.version) == ignored) {
        return;
      }

      await _executeUpdateFlow(
        result: result,
        service: updateService,
      );
    });
  }

  static Future<void> checkInteractively(
    BuildContext context, {
    TvUpdateService? service,
  }) {
    if (_activeFlow != null) {
      if (KazumiDialog.observer.hasKazumiDialog) {
        KazumiDialog.showToast(
          context: context.mounted ? context : null,
          message: '更新窗口已打开',
        );
      }
      return _activeFlow!;
    }

    return _runSingleFlight(() async {
      final updateService = service ?? TvUpdateService.instance;
      final cancelToken = RuleCancelToken();

      try {
        final result = await showTvLoadingDialog<TvUpdateCheckResult>(
          context,
          message: '正在检查更新…',
          cancelToken: cancelToken,
          action: () => updateService.checkForUpdates(cancelToken: cancelToken),
        );
        if (result == null || cancelToken.isCancelled) {
          return;
        }

        switch (result.status) {
          case TvUpdateCheckStatus.upToDate:
            KazumiDialog.showToast(
              context: context.mounted ? context : null,
              message: '当前已是最新版本 v${result.currentVersion}',
            );
          case TvUpdateCheckStatus.incompatibleAbi:
            final abis = result.supportedAbis.isEmpty
                ? '未知'
                : result.supportedAbis.join(', ');
            KazumiDialog.showToast(
              context: context.mounted ? context : null,
              message: '未找到适配当前设备架构 ($abis) 的安装包',
              duration: const Duration(seconds: 4),
            );
          case TvUpdateCheckStatus.updateAvailable:
            await _executeUpdateFlow(
              context: context.mounted ? context : null,
              result: result,
              service: updateService,
            );
        }
      } catch (e, stackTrace) {
        if (cancelToken.isCancelled) {
          return;
        }
        KazumiLogger().w(
          'TvUpdate: interactive update check failed',
          error: e,
          stackTrace: stackTrace,
        );
        final message = e is TvUpdateException
            ? e.message
            : '检查更新失败，请检查网络连接或镜像设置';
        KazumiDialog.showToast(
          context: context.mounted ? context : null,
          message: message,
          duration: const Duration(seconds: 3),
        );
      }
    });
  }

  static Future<void> showUpdateFlow({
    BuildContext? context,
    required TvUpdateCheckResult result,
    TvUpdateService? service,
  }) {
    return _runSingleFlight(
      () => _executeUpdateFlow(
        context: context,
        result: result,
        service: service ?? TvUpdateService.instance,
      ),
    );
  }

  static Future<void> _executeUpdateFlow({
    BuildContext? context,
    required TvUpdateCheckResult result,
    required TvUpdateService service,
  }) async {
    final release = result.release;
    final asset = result.matchedAsset;
    if (release == null || asset == null) {
      return;
    }

    var selectedMirror = TvUpdateConfig.activeMirrorMode;
    var selectedCustomMirror = TvUpdateConfig.customMirrorUrl;
    var activeMirrorLabel = release.sourceLabel.isNotEmpty
        ? release.sourceLabel
        : selectedMirror.label;

    while (true) {
      final action = await KazumiDialog.show<TvUpdateDialogAction>(
        context: context != null && context.mounted ? context : null,
        clickMaskDismiss: !release.force,
        builder: (_) => TvUpdateAvailableDialog(
          currentVersion: result.currentVersion,
          release: release,
          asset: asset,
          activeMirrorLabel: activeMirrorLabel,
        ),
      );

      switch (action) {
        case TvUpdateDialogAction.switchMirror:
          final updated = await pickTvUpdateMirror(
            context != null && context.mounted ? context : null,
            currentMode: selectedMirror,
            currentCustomUrl: selectedCustomMirror,
          );
          if (updated != null) {
            selectedMirror = updated.mode;
            selectedCustomMirror = updated.customUrl;
            activeMirrorLabel = updated.mode.label;
          }
          continue;
        case TvUpdateDialogAction.ignoreVersion:
          await TvUpdateConfig.setIgnoredVersion(release.version);
          KazumiDialog.showToast(
            context: context != null && context.mounted ? context : null,
            message: '已忽略版本 v${release.version}',
          );
          return;
        case TvUpdateDialogAction.later:
        case null:
          return;
        case TvUpdateDialogAction.updateNow:
          break;
      }
      break;
    }

    final cancelToken = RuleCancelToken();
    final progressNotifier = ValueNotifier<TvUpdateDownloadProgress>(
      TvUpdateDownloadProgress(
        stage: TvUpdateDownloadStage.preparing,
        receivedBytes: 0,
        totalBytes: asset.size,
        bytesPerSecond: 0,
        activeSourceLabel: activeMirrorLabel,
        message: '正在准备下载安装包...',
      ),
    );

    final dialogHandle = KazumiDialogHandle<bool>();
    final dialogFuture = KazumiDialog.show<bool>(
      context: context != null && context.mounted ? context : null,
      handle: dialogHandle,
      clickMaskDismiss: false,
      builder: (_) => TvUpdateDownloadDialog(
        version: release.version,
        progressListenable: progressNotifier,
        onCancel: () {
          if (!cancelToken.isCancelled) {
            cancelToken.cancel('user cancelled');
          }
        },
      ),
    );

    String? downloadedPath;
    try {
      downloadedPath = await service.downloadApk(
        release: release,
        asset: asset,
        mirrorOverride: selectedMirror,
        customMirrorOverride: selectedMirror == TvUpdateMirrorMode.custom
            ? selectedCustomMirror
            : null,
        cancelToken: cancelToken,
        onProgress: (progress) {
          if (!cancelToken.isCancelled) {
            progressNotifier.value = progress;
          }
        },
      );
      dialogHandle.dismiss(popWith: true);
    } catch (e, stackTrace) {
      dialogHandle.dismiss(popWith: true);
      await dialogFuture;
      final isCancelled = cancelToken.isCancelled ||
          (e is DioException && e.type == DioExceptionType.cancel) ||
          (e is NetworkException && e.type == NetworkExceptionType.cancel);
      if (isCancelled) {
        KazumiDialog.showToast(
          context: context != null && context.mounted ? context : null,
          message: '已取消下载',
        );
        return;
      }
      KazumiLogger().e(
        'TvUpdate: download failed',
        error: e,
        stackTrace: stackTrace,
      );
      final message =
          e is TvUpdateException ? e.message : '下载更新失败，请切换镜像或稍后重试';
      KazumiDialog.showToast(
        context: context != null && context.mounted ? context : null,
        message: message,
        duration: const Duration(seconds: 4),
      );
      return;
    } finally {
      await dialogFuture;
      progressNotifier.dispose();
    }

    if (cancelToken.isCancelled || downloadedPath.isEmpty) {
      return;
    }

    final installResult = await service.installApk(downloadedPath);
    switch (installResult.outcome) {
      case TvUpdateInstallOutcome.launched:
        KazumiDialog.showToast(
          context: context != null && context.mounted ? context : null,
          message: installResult.message.isNotEmpty
              ? installResult.message
              : '已拉起系统安装界面',
        );
        return;
      case TvUpdateInstallOutcome.failed:
        KazumiDialog.showToast(
          context: context != null && context.mounted ? context : null,
          message: installResult.message.isNotEmpty
              ? installResult.message
              : '无法打开安装包文件',
          duration: const Duration(seconds: 4),
        );
        return;
      case TvUpdateInstallOutcome.permissionRequired:
        await KazumiDialog.show<bool>(
          context: context != null && context.mounted ? context : null,
          clickMaskDismiss: false,
          builder: (_) => TvUpdateInstallPermissionDialog(
            apkPath: downloadedPath,
            onOpenSettings: () async {
              final opened =
                  await TvPlatformChannel.openInstallPermissionSettings();
              if (!opened) {
                KazumiDialog.showToast(
                  context: context != null && context.mounted ? context : null,
                  message:
                      '无法自动跳转权限设置，请手动前往「系统设置 -> 安全/隐私 -> 允许安装未知来源应用」',
                  duration: const Duration(seconds: 4),
                );
              }
              return opened;
            },
            onRetryInstall: () async {
              final retry = await service.installApk(downloadedPath!);
              if (retry.outcome == TvUpdateInstallOutcome.launched) {
                KazumiDialog.showToast(
                  context: context != null && context.mounted ? context : null,
                  message: retry.message.isNotEmpty
                      ? retry.message
                      : '已拉起系统安装界面',
                );
                return true;
              }
              if (retry.outcome == TvUpdateInstallOutcome.permissionRequired) {
                KazumiDialog.showToast(
                  context: context != null && context.mounted ? context : null,
                  message: '尚未检测到安装权限，请先开启后再试',
                  duration: const Duration(seconds: 3),
                );
                return false;
              }
              KazumiDialog.showToast(
                context: context != null && context.mounted ? context : null,
                message: retry.message.isNotEmpty
                    ? retry.message
                    : '无法打开安装包文件',
                duration: const Duration(seconds: 4),
              );
              return true;
            },
          ),
        );
    }
  }
}

Future<({TvUpdateMirrorMode mode, String customUrl})?> pickTvUpdateMirror(
  BuildContext? context, {
  TvUpdateMirrorMode? currentMode,
  String? currentCustomUrl,
}) async {
  final dialogContext =
      (context != null && context.mounted)
          ? context
          : KazumiDialog.observer.navigator?.context;
  if (dialogContext == null || !dialogContext.mounted) {
    return null;
  }

  final activeMode = currentMode ?? TvUpdateConfig.activeMirrorMode;
  final activeCustomUrl = currentCustomUrl ?? TvUpdateConfig.customMirrorUrl;

  final picked = await showTvChoiceDialog<TvUpdateMirrorMode>(
    dialogContext,
    title: '选择更新下载镜像',
    subtitle: '若当前线路较慢或失败，可切换至其他镜像源',
    currentValue: activeMode,
    options: [
      for (final mode in TvUpdateMirrorMode.values)
        TvChoiceOption(
          value: mode,
          label: mode.label,
          subtitle:
              mode == TvUpdateMirrorMode.custom && activeCustomUrl.isNotEmpty
                  ? '${mode.description}（$activeCustomUrl）'
                  : mode.description,
        ),
    ],
  );
  if (picked == null) {
    return null;
  }

  if (picked == TvUpdateMirrorMode.custom) {
    final nextContext =
        dialogContext.mounted
            ? dialogContext
            : KazumiDialog.observer.navigator?.context;
    if (nextContext == null || !nextContext.mounted) {
      return null;
    }
    final raw = await showTvInputDialog(
      nextContext,
      title: '自定义更新镜像地址',
      initialValue: activeCustomUrl,
      hintText: 'https://your-mirror.example.com/',
    );
    if (raw == null) {
      return null;
    }
    final normalized = TvUpdateConfig.normalizeMirrorPrefix(raw);
    if (normalized == null) {
      KazumiDialog.showToast(
        context: nextContext.mounted ? nextContext : null,
        message: '镜像地址无效，请输入 http:// 或 https:// 开头的有效地址',
      );
      return null;
    }
    await GStorage.putSetting(SettingsKeys.tvUpdateCustomMirrorUrl, normalized);
    await GStorage.putSetting(SettingsKeys.tvUpdateMirror, picked.name);
    return (mode: picked, customUrl: normalized);
  }

  await GStorage.putSetting(SettingsKeys.tvUpdateMirror, picked.name);
  return (mode: picked, customUrl: activeCustomUrl);
}

class _TvUpdateDialogShell extends StatelessWidget {
  const _TvUpdateDialogShell({
    required this.canPop,
    required this.onPopInvokedWithResult,
    required this.onKeyboardBack,
    required this.title,
    required this.content,
    required this.actions,
  });

  final bool canPop;
  final void Function(bool didPop, Object? result) onPopInvokedWithResult;
  final VoidCallback onKeyboardBack;
  final Widget title;
  final Widget content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: canPop,
      onPopInvokedWithResult: onPopInvokedWithResult,
      child: FocusScope(
        autofocus: true,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                TvKeys.isKeyboardBackKey(event.logicalKey)) {
              onKeyboardBack();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: FocusTraversalGroup(
            policy: TvFocusTraversalPolicy(),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 20,
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              actionsPadding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
              actionsOverflowButtonSpacing: 10,
              title: title,
              content: content,
              actions: actions,
            ),
          ),
        ),
      ),
    );
  }
}

class TvUpdateAvailableDialog extends StatefulWidget {
  const TvUpdateAvailableDialog({
    super.key,
    required this.currentVersion,
    required this.release,
    required this.asset,
    this.activeMirrorLabel,
  });

  final String currentVersion;
  final TvUpdateRelease release;
  final TvUpdateApkAsset asset;
  final String? activeMirrorLabel;

  @override
  State<TvUpdateAvailableDialog> createState() =>
      _TvUpdateAvailableDialogState();
}

class _TvUpdateAvailableDialogState extends State<TvUpdateAvailableDialog> {
  final ScrollController _changelogScrollController = ScrollController();
  final ScrollController _outerScrollController = ScrollController();
  bool _popped = false;

  @override
  void dispose() {
    _changelogScrollController.dispose();
    _outerScrollController.dispose();
    super.dispose();
  }

  void _closeWith(TvUpdateDialogAction? action) {
    if (_popped) {
      return;
    }
    _popped = true;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(action);
    }
  }

  void _handleBack() {
    if (widget.release.force) {
      return;
    }
    _closeWith(TvUpdateDialogAction.later);
  }

  KeyEventResult _handleChangelogKeyEvent(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_changelogScrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final maxExtent = _changelogScrollController.position.maxScrollExtent;
    if (maxExtent <= 0) {
      return KeyEventResult.ignored;
    }
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (TvKeys.isDownKey(event.logicalKey)) {
      if (_changelogScrollController.offset >= maxExtent - 0.5) {
        return KeyEventResult.ignored;
      }
      final next = (_changelogScrollController.offset + 140).clamp(
        0.0,
        maxExtent,
      );
      if (disableAnimations) {
        _changelogScrollController.jumpTo(next);
      } else {
        unawaited(
          _changelogScrollController.animateTo(
            next,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return KeyEventResult.handled;
    }
    if (TvKeys.isUpKey(event.logicalKey)) {
      if (_changelogScrollController.offset <= 0.5) {
        return KeyEventResult.ignored;
      }
      final next = (_changelogScrollController.offset - 140).clamp(
        0.0,
        maxExtent,
      );
      if (disableAnimations) {
        _changelogScrollController.jumpTo(next);
      } else {
        unawaited(
          _changelogScrollController.animateTo(
            next,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
          ),
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final release = widget.release;
    final asset = widget.asset;
    final currentVer = TvVersionComparator.normalizeVersion(
      widget.currentVersion,
    );
    final sizeText =
        asset.size > 0 ? TvUpdateService.formatBytes(asset.size) : '大小未知';
    final publishedText =
        release.publishedAt.trim().isNotEmpty
            ? formatDate(release.publishedAt.trim())
            : '';
    final mirrorLabel =
        (widget.activeMirrorLabel != null &&
                widget.activeMirrorLabel!.trim().isNotEmpty)
            ? widget.activeMirrorLabel!.trim()
            : (release.sourceLabel.trim().isNotEmpty
                ? release.sourceLabel.trim()
                : TvUpdateConfig.activeMirrorMode.label);
    final changelog =
        release.changelog.trim().isNotEmpty
            ? release.changelog.trim()
            : '暂无更新说明';
    final changelogMaxHeight =
        (MediaQuery.sizeOf(context).height * 0.25).clamp(100.0, 210.0);

    return _TvUpdateDialogShell(
      canPop: !release.force,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _popped = true;
        }
      },
      onKeyboardBack: _handleBack,
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: colors.primary, size: 26),
          const SizedBox(width: 10),
          const Text(
            '发现新版本',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (release.force) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '强制更新',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 640),
        child: TvAxisClipRect(
          axis: Axis.vertical,
          child: SingleChildScrollView(
            controller: _outerScrollController,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'v$currentVer -> v${release.version}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _TvMetaBadge(
                      icon: Icons.memory_rounded,
                      label: '架构: ${asset.abi}',
                    ),
                    _TvMetaBadge(
                      icon: Icons.inventory_2_outlined,
                      label: '大小: $sizeText',
                    ),
                    if (publishedText.isNotEmpty)
                      _TvMetaBadge(
                        icon: Icons.schedule_rounded,
                        label: publishedText,
                      ),
                    _TvMetaBadge(
                      icon: Icons.cloud_download_outlined,
                      label: '镜像: $mirrorLabel',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '更新内容',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: TvFocusable(
                    borderRadius: 12,
                    scaleOnFocus: 1.005,
                    onKeyEvent: (_, event) =>
                        _handleChangelogKeyEvent(context, event),
                    builder: (context, focused) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                        decoration: BoxDecoration(
                          color: focused
                              ? colors.surfaceContainerHighest
                              : colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: changelogMaxHeight,
                          ),
                          child: TvAxisClipRect(
                            axis: Axis.vertical,
                            child: Scrollbar(
                              controller: _changelogScrollController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _changelogScrollController,
                                clipBehavior: Clip.none,
                                padding: const EdgeInsets.only(right: 10),
                                child: Text(
                                  changelog,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.55,
                                    color: colors.onSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (!release.force)
          TvSecondaryButton(
            label: '忽略此版本',
            onPressed: () => _closeWith(TvUpdateDialogAction.ignoreVersion),
          ),
        if (!release.force)
          TvSecondaryButton(
            label: '暂不更新',
            onPressed: () => _closeWith(TvUpdateDialogAction.later),
          ),
        TvSecondaryButton(
          label: '切换镜像',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => _closeWith(TvUpdateDialogAction.switchMirror),
        ),
        TvPrimaryButton(
          label: '立即更新',
          icon: Icons.download_rounded,
          autofocus: true,
          onPressed: () => _closeWith(TvUpdateDialogAction.updateNow),
        ),
      ],
    );
  }
}

class TvUpdateDownloadDialog extends StatefulWidget {
  const TvUpdateDownloadDialog({
    super.key,
    required this.version,
    required this.progressListenable,
    required this.onCancel,
  });

  final String version;
  final ValueListenable<TvUpdateDownloadProgress> progressListenable;
  final VoidCallback onCancel;

  @override
  State<TvUpdateDownloadDialog> createState() => _TvUpdateDownloadDialogState();
}

class _TvUpdateDownloadDialogState extends State<TvUpdateDownloadDialog> {
  bool _cancelTriggered = false;

  void _handleCancel({bool popRoute = true}) {
    if (!_cancelTriggered) {
      _cancelTriggered = true;
      widget.onCancel();
    }
    if (popRoute && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final cleanVersion = TvVersionComparator.normalizeVersion(widget.version);

    return _TvUpdateDialogShell(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result != true) {
          _handleCancel(popRoute: false);
        }
      },
      onKeyboardBack: () => _handleCancel(popRoute: true),
      title: Row(
        children: [
          Icon(Icons.downloading_rounded, color: colors.primary, size: 26),
          const SizedBox(width: 10),
          Text(
            '正在下载更新 v$cleanVersion',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: ValueListenableBuilder<TvUpdateDownloadProgress>(
            valueListenable: widget.progressListenable,
            builder: (context, progress, _) {
              final fraction = progress.fraction;
              final percentText = fraction != null
                  ? '${(fraction * 100).clamp(0, 100).toStringAsFixed(1)}%'
                  : '--';
              final sizeText = progress.totalBytes > 0
                  ? '${TvUpdateService.formatBytes(progress.receivedBytes)} / '
                      '${TvUpdateService.formatBytes(progress.totalBytes)}'
                  : TvUpdateService.formatBytes(progress.receivedBytes);
              final speedText = progress.bytesPerSecond > 0
                  ? '${TvUpdateService.formatBytes(progress.bytesPerSecond.round())}/s'
                  : '--';

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          progress.message,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (progress.activeSourceLabel.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _TvMetaBadge(
                          icon: Icons.cloud_outlined,
                          label: progress.activeSourceLabel,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sizeText,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        speedText,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        percentText,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
      actions: [
        TvSecondaryButton(
          label: '取消下载',
          autofocus: true,
          onPressed: () => _handleCancel(popRoute: true),
        ),
      ],
    );
  }
}

class TvUpdateInstallPermissionDialog extends StatefulWidget {
  const TvUpdateInstallPermissionDialog({
    super.key,
    required this.onOpenSettings,
    required this.onRetryInstall,
    this.onLater,
    this.apkPath,
  });

  final FutureOr<bool> Function() onOpenSettings;
  final FutureOr<bool> Function() onRetryInstall;
  final VoidCallback? onLater;
  final String? apkPath;

  @override
  State<TvUpdateInstallPermissionDialog> createState() =>
      _TvUpdateInstallPermissionDialogState();
}

class _TvUpdateInstallPermissionDialogState
    extends State<TvUpdateInstallPermissionDialog> {
  final ScrollController _scrollController = ScrollController();
  bool _busy = false;
  bool _closed = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleOpenSettings() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onOpenSettings();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleRetryInstall() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final installed = await widget.onRetryInstall();
      if (installed && mounted && !_closed && Navigator.of(context).canPop()) {
        _closed = true;
        Navigator.of(context).maybePop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _handleLater({bool popRoute = true}) {
    if (!_closed) {
      _closed = true;
      widget.onLater?.call();
    }
    if (popRoute && mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).maybePop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _TvUpdateDialogShell(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result != true) {
          _handleLater(popRoute: false);
        }
      },
      onKeyboardBack: () => _handleLater(popRoute: true),
      title: Row(
        children: [
          Icon(Icons.security_rounded, color: colors.primary, size: 26),
          const SizedBox(width: 10),
          const Text(
            '需要安装未知应用权限',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 480, maxWidth: 620),
        child: TvAxisClipRect(
          axis: Axis.vertical,
          child: SingleChildScrollView(
            controller: _scrollController,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '新版安装包已下载并校验完成。继续安装前，请先授予 Kazumi TV「允许安装未知应用」权限。',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TCL / 国产电视手动开启指引：',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '• 系统设置 -> 安全/隐私 -> 允许安装未知来源应用\n'
                      '• 若电视卫士拦截或隐藏权限入口，请在「电视卫士 / 应用安全」中允许 Kazumi TV 安装应用',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (widget.apkPath != null &&
                        widget.apkPath!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '缓存路径：${widget.apkPath!.trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      actions: [
        TvSecondaryButton(
          label: '稍后安装',
          onPressed: () => _handleLater(popRoute: true),
        ),
        TvSecondaryButton(
          label: '我已开启，继续安装',
          onPressed: _handleRetryInstall,
        ),
        TvPrimaryButton(
          label: '去开启权限',
          autofocus: true,
          onPressed: _handleOpenSettings,
        ),
      ],
    );
  }
}

class _TvMetaBadge extends StatelessWidget {
  const _TvMetaBadge({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
