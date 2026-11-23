import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/tv/utils/tv_focus_traversal.dart';
import 'package:kazumi/tv/utils/tv_keys.dart';
import 'package:kazumi/tv/widgets/tv_axis_clip_rect.dart';
import 'package:kazumi/tv/widgets/tv_button.dart';
import 'package:kazumi/tv/widgets/tv_focusable.dart';

class TvChoiceOption<T> {
  const TvChoiceOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
}

Future<bool> showTvConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await KazumiDialog.show<bool>(
    context: context,
    builder: (dialogContext) => FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: TvFocusTraversalPolicy(),
        child: AlertDialog(
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              message,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TvSecondaryButton(
              label: cancelLabel,
              autofocus: destructive,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            const SizedBox(width: 10),
            TvPrimaryButton(
              label: confirmLabel,
              destructive: destructive,
              autofocus: !destructive,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

Future<T?> showTvChoiceDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<TvChoiceOption<T>> options,
  T? currentValue,
}) {
  return KazumiDialog.show<T>(
    context: context,
    builder: (dialogContext) {
      final colors = Theme.of(dialogContext).colorScheme;
      final selectedIdx = options.indexWhere((o) => o.value == currentValue);
      final initialIndex = selectedIdx >= 0 ? selectedIdx : 0;

      return FocusScope(
        autofocus: true,
        child: FocusTraversalGroup(
          policy: TvFocusTraversalPolicy(),
          child: AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
            content: SizedBox(
              width: 440,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: TvAxisClipRect(
                  axis: Axis.vertical,
                  child: ListView.separated(
                    clipBehavior: Clip.none,
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(18),
                    itemCount: options.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = option.value == currentValue;
                      return TvFocusable(
                        autofocus: index == initialIndex,
                        borderRadius: 12,
                        scaleOnFocus: 1.02,
                        onSelect: () =>
                            Navigator.of(dialogContext).pop(option.value),
                        builder: (context, focused) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colors.primaryContainer.withValues(alpha: 0.7)
                                  : focused
                                      ? colors.surfaceContainerHighest
                                      : colors.surfaceContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                if (option.icon != null) ...[
                                  Icon(
                                    option.icon,
                                    size: 20,
                                    color: isSelected
                                        ? colors.primary
                                        : colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        option.label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: isSelected
                                              ? colors.onPrimaryContainer
                                              : colors.onSurface,
                                        ),
                                      ),
                                      if (option.subtitle != null &&
                                          option.subtitle!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          option.subtitle!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 20,
                                    color: colors.primary,
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
            ),
            actions: [
              TvSecondaryButton(
                label: '关闭',
                autofocus: options.isEmpty,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<String?> showTvInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String hintText = '',
  String confirmLabel = '确定',
  bool obscureText = false,
  TextInputType keyboardType = TextInputType.text,
  List<TextInputFormatter>? inputFormatters,
}) {
  return KazumiDialog.show<String>(
    context: context,
    builder: (dialogContext) => _TvInputDialog(
      title: title,
      initialValue: initialValue,
      hintText: hintText,
      confirmLabel: confirmLabel,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
    ),
  );
}

class _TvInputDialog extends StatefulWidget {
  const _TvInputDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.confirmLabel,
    required this.obscureText,
    required this.keyboardType,
    this.inputFormatters,
  });

  final String title;
  final String initialValue;
  final String hintText;
  final String confirmLabel;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_TvInputDialog> createState() => _TvInputDialogState();
}

class _TvInputDialogState extends State<_TvInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: FocusTraversalGroup(
        policy: TvFocusTraversalPolicy(),
        child: AlertDialog(
          title: Text(
            widget.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 460,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    TvKeys.isDownKey(event.logicalKey)) {
                  (FocusManager.instance.primaryFocus ?? node)
                      .focusInDirection(TraversalDirection.down);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                autofocus: true,
                obscureText: widget.obscureText,
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
                textInputAction: TextInputAction.done,
                onSubmitted: (value) =>
                    Navigator.of(context).pop(value.trim()),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          actions: [
            TvSecondaryButton(
              label: '取消',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 10),
            TvPrimaryButton(
              label: widget.confirmLabel,
              onPressed: () =>
                  Navigator.of(context).pop(_controller.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}

Future<T?> showTvLoadingDialog<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() action,
  RuleCancelToken? cancelToken,
}) {
  var dismissed = false;
  var completed = false;
  BuildContext? activeDialogContext;
  final resultCompleter = Completer<T?>();

  void closeDialogIfMounted() {
    if (dismissed) return;
    final ctx = activeDialogContext;
    if (ctx != null && ctx.mounted) {
      dismissed = true;
      Navigator.of(ctx).pop();
    }
  }

  void cancelAndDismiss({BuildContext? dialogContext, bool popRoute = true}) {
    if (!dismissed) {
      dismissed = true;
      cancelToken?.cancel();
      if (popRoute && dialogContext != null && dialogContext.mounted) {
        Navigator.of(dialogContext).maybePop();
      }
    }
    if (!resultCompleter.isCompleted) {
      resultCompleter.complete(null);
    }
  }

  unawaited(
    KazumiDialog.show<void>(
      context: context,
      clickMaskDismiss: false,
      builder: (dialogContext) {
        activeDialogContext = dialogContext;
        if (completed && !dismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            closeDialogIfMounted();
          });
        }
        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              cancelAndDismiss(popRoute: false);
            }
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  TvKeys.isKeyboardBackKey(event.logicalKey)) {
                cancelAndDismiss(dialogContext: dialogContext);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: FocusTraversalGroup(
              policy: TvFocusTraversalPolicy(),
              child: AlertDialog(
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 20),
                      Flexible(
                        child: Text(
                          message,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TvSecondaryButton(
                    label: '取消',
                    autofocus: true,
                    onPressed: () =>
                        cancelAndDismiss(dialogContext: dialogContext),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  unawaited(() async {
    try {
      final result = await action();
      if (!dismissed && !(cancelToken?.isCancelled ?? false)) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(result);
        }
      } else if (!resultCompleter.isCompleted) {
        resultCompleter.complete(null);
      }
    } catch (error, stackTrace) {
      if (!dismissed && !(cancelToken?.isCancelled ?? false)) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(error, stackTrace);
        }
      } else if (!resultCompleter.isCompleted) {
        resultCompleter.complete(null);
      }
    } finally {
      completed = true;
      closeDialogIfMounted();
    }
  }());

  return resultCompleter.future;
}
