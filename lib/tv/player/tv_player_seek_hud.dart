import 'package:flutter/material.dart';
import 'package:kazumi/utils/format.dart';

class TvPlayerSeekHud extends StatelessWidget {
  const TvPlayerSeekHud({
    super.key,
    required this.targetPosition,
    required this.startPosition,
    required this.duration,
  });

  final Duration targetPosition;
  final Duration startPosition;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final deltaSec = targetPosition.inSeconds - startPosition.inSeconds;
    final isForward = deltaSec >= 0;
    final progress = duration > Duration.zero
        ? (targetPosition.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return IgnorePointer(
      child: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xD912151F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isForward
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    size: 28,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${isForward ? '+' : ''}${deltaSec}s',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${durationToString(targetPosition)} / ${durationToString(duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
